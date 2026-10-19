extends Node2D
## The hero's pixel effects. The player adds it as its first child, so everything draws behind the sprite, and
## steps it from its own physics tick (no extra loop). Two layers:
## - this node (normal blend): dust and afterimages;
## - Glow child (additive, unshaded, so a scene's CanvasModulate cannot dim it and overlaps bloom): sparks,
##   impact rays and slash marks, shockwave rings, shards, embers, focus lines, speed lines, airflow, charge
##   light and the blade arcs.
## It listens to the player's public move_started signal to size the blade arcs; it never reads player state.
## Decorative randomness has its own generator, so effects never shift the player's critical-hit rolls.

const MAX_BLADE_PIXELS := 330
const WHITE := Color("f2f8ff")
const BLUE := Color("8ebce8")
const CYAN := Color("5fd8ff")
const DEEP := Color("3a6fd8")
const DUST := Color("82717c")
# Per hit-stop weight: ray count / reach / life, slash-mark rows, rings, shards, embers, focus lines.
const IMPACT := {
	&"light": {"rays": 8, "reach": 8.0, "life": 0.1, "rows": 2, "rings": [[10.0, 0.0]], "shards": 4, "embers": 3, "focus": 0},
	&"critical": {"rays": 12, "reach": 13.0, "life": 0.13, "rows": 3, "rings": [[20.0, 0.0], [12.0, 0.05]], "shards": 9, "embers": 8, "focus": 20},
	&"heavy": {"rays": 16, "reach": 22.0, "life": 0.17, "rows": 4, "rings": [[34.0, 0.0], [24.0, 0.05], [14.0, 0.1]], "shards": 16, "embers": 14, "focus": 36},
}
# Blade arc width (layers outside the white core) by move.
const ARC_WIDTH := {&"attack1": 2, &"attack2": 3, &"heavy_slash": 4, &"attack3": 3, &"rising_slash": 3, &"dive_slash": 3, &"dash_stab": 2, &"air_attack3": 2}

var effects: Array[Dictionary] = []
var bursts: Array[Dictionary] = []
var blade_trails: Array[Dictionary] = []
var afterimages: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var arc_width := 1
var _glow: Node2D


func _ready() -> void:
	rng.randomize()
	_glow = Node2D.new()
	_glow.name = "Glow"
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow.material = additive
	add_child(_glow)
	_glow.draw.connect(_draw_glow)
	var owner_player := get_parent()
	if owner_player != null and owner_player.has_signal("move_started"):
		owner_player.move_started.connect(_on_move_started)


func _on_move_started(move: StringName) -> void:
	arc_width = int(ARC_WIDTH.get(move, 1))
	if move == &"dash_stab":
		speed_lines(global_position, Vector2.RIGHT if get_parent().get("facing") != "left" else Vector2.LEFT, false)


func add(effect: Dictionary) -> void:
	effects.append(effect)


func dust(point: Vector2, count: int) -> void:
	for index in range(count):
		add({"position": point.round() + Vector2(index * 2 - count, -1), "velocity": Vector2((index - count / 2.0) * 9.0, -10.0 - index * 2.0), "life": 0.18, "color": DUST, "back": true})


func sparks(point: Vector2) -> void:
	for index in range(5):
		add({"position": point.round(), "velocity": Vector2(-32 + index * 16, -35 + abs(index - 2) * 16), "life": 0.14, "color": WHITE if index % 2 == 0 else BLUE})


# Small neutral contact sparks; no ink cuts, blood spray or execution halo.
func impact(point: Vector2, _weight: StringName, _direction: Vector2, _feet: Vector2) -> void:
	sparks(point)


## Preserved v1 hit shapes, callable from legacy_dash_hit_feedback.gd; disabled for thrusts by default.
func legacy_impact(point: Vector2, weight: StringName, direction: Vector2, feet: Vector2) -> void:
	var look: Dictionary = IMPACT.get(weight, IMPACT[&"light"])
	var rays: int = look["rays"]
	var reach: float = look["reach"]
	var life: float = look["life"]
	for index in range(rays):
		var ray := Vector2.from_angle(TAU * index / rays + 0.35)
		var length := reach * (1.0 if index % 2 == 0 else 0.6)
		add({"position": (point + ray * 3.0).round(), "velocity": ray * length / life, "tail": ray * length * 0.5,
			"life": life, "color": WHITE if index % 2 == 0 else CYAN})
	var across := Vector2(direction.x, -0.65).normalized() if direction.x != 0.0 else Vector2(0.65, direction.y).normalized()
	for row in range(int(look["rows"])):
		var offset := Vector2(0, row) if direction.x != 0.0 else Vector2(row, 0)
		add({"position": (point + across * reach + offset).round(), "velocity": Vector2.ZERO, "tail": across * reach * 2.0,
			"life": life * 1.5, "color": WHITE if row == 0 else (CYAN if row == 1 else DEEP)})
	for ring in look["rings"]:
		bursts.append({"kind": "ring", "position": point.round(), "radius": 2.0, "max_radius": ring[0], "delay": ring[1],
			"life": 0.2, "max_life": 0.2, "color": WHITE})
	for index in range(int(look["shards"])):
		var angle := rng.randf_range(-PI, 0.0) if index % 3 != 0 else rng.randf_range(-PI, PI)
		var speed := rng.randf_range(70.0, 170.0) * (1.3 if weight == &"heavy" else 1.0)
		bursts.append({"kind": "shard", "position": point, "velocity": Vector2.from_angle(angle) * speed + direction * 40.0,
			"life": rng.randf_range(0.25, 0.45), "color": WHITE if index % 2 == 0 else CYAN})
	for index in range(int(look["embers"])):
		bursts.append({"kind": "ember", "position": point + Vector2(rng.randf_range(-6, 6), rng.randf_range(-8, 4)),
			"velocity": Vector2(rng.randf_range(-30, 30) + direction.x * 20.0, rng.randf_range(-60, -15)),
			"life": rng.randf_range(0.3, 0.55), "color": Color("ffe9a8") if index % 3 == 0 else CYAN})
	if int(look["focus"]) > 0:
		var lines: Array = []
		for index in range(int(look["focus"])):
			var angle := TAU * index / int(look["focus"]) + rng.randf_range(-0.08, 0.08)
			lines.append([angle, rng.randf_range(34.0, 70.0), rng.randf_range(150.0, 190.0)])
		bursts.append({"kind": "focus", "position": point.round(), "lines": lines, "life": 0.07 if weight == &"heavy" else 0.05, "color": WHITE})
	if weight != &"light":
		sparks(point + Vector2(0, -3))
	if weight == &"heavy":
		sparks(point + Vector2(0, 3))
		sparks(point + direction * 6.0)
		dust(feet + direction * 6.0, 7)
		dust(feet - direction * 4.0, 5)


# Horizontal streaks behind the hero for heavy releases and dashes.
func speed_lines(feet: Vector2, forward: Vector2, heavy: bool) -> void:
	for index in range(9 if heavy else 6):
		var height := -rng.randf_range(2.0, 30.0)
		var length := rng.randf_range(10.0, 26.0) * (1.4 if heavy else 1.0)
		bursts.append({"kind": "streak", "position": feet + Vector2(-forward.x * rng.randf_range(4.0, 20.0), height),
			"velocity": -forward * rng.randf_range(80.0, 160.0), "tail": -forward * length, "life": rng.randf_range(0.1, 0.18),
			"color": WHITE if index % 2 == 0 else CYAN})


func airflow(point: Vector2, direction: Vector2, rising: bool) -> void:
	for index in range(3):
		var location := point + Vector2(-direction.x * (5 + index * 3), -7 - index * 8)
		var drift := Vector2(direction.x * 8, -50) if rising else Vector2(-direction.x * 30, 0)
		var tail := Vector2(direction.x * 2, 5) if rising else direction * 8.0
		add({"position": location.round(), "velocity": drift, "tail": tail, "life": 0.14, "color": BLUE})


# Charge: light rising off the body.
func mote(feet: Vector2, bright: bool) -> void:
	var at := feet + Vector2(rng.randf_range(-7.0, 7.0), -rng.randf_range(3.0, 24.0))
	add({"position": at.round(), "velocity": Vector2(0, -34), "life": 0.22, "color": WHITE if bright else BLUE})


# Charge full: a blinking white star on the blade tip.
func star(tip: Vector2) -> void:
	for offset in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
		add({"position": tip + offset, "velocity": Vector2.ZERO, "life": 0.05, "color": WHITE})


# Coiling: light gathers onto the blade from a ring of the given radius.
func gather(tip: Vector2, radius: float, angle: float) -> void:
	var start := tip + Vector2.from_angle(angle) * radius
	add({"position": start.round(), "velocity": (tip - start) / 0.1, "life": 0.1, "color": BLUE})


func trail(pixels: Array[Vector2i], edge: Vector2i, life: float) -> void:
	blade_trails.append({"pixels": pixels, "edge": edge, "life": life * (1.0 + 0.2 * (arc_width - 1)), "width": arc_width})


func clear_trails() -> void:
	blade_trails.clear()


func ghost(texture: Texture2D, at: Vector2, life: float) -> void:
	afterimages.append({"texture": texture, "position": at, "life": life})


func step(delta: float) -> void:
	for index in range(afterimages.size() - 1, -1, -1):
		afterimages[index]["life"] = float(afterimages[index]["life"]) - delta
		if float(afterimages[index]["life"]) <= 0.0:
			afterimages.remove_at(index)
	for index in range(effects.size() - 1, -1, -1):
		var effect := effects[index]
		effect["life"] = float(effect["life"]) - delta
		if float(effect["life"]) <= 0.0:
			effects.remove_at(index)
		else:
			effect["position"] = Vector2(effect["position"]) + Vector2(effect["velocity"]) * delta
	for index in range(bursts.size() - 1, -1, -1):
		var burst := bursts[index]
		if float(burst.get("delay", 0.0)) > 0.0:
			burst["delay"] = float(burst["delay"]) - delta
			continue
		burst["life"] = float(burst["life"]) - delta
		if float(burst["life"]) <= 0.0:
			bursts.remove_at(index)
			continue
		match String(burst["kind"]):
			"ring":
				var grown := 1.0 - float(burst["life"]) / float(burst["max_life"])
				burst["radius"] = lerpf(2.0, float(burst["max_radius"]), 1.0 - pow(1.0 - grown, 3.0))
			"shard", "ember", "streak":
				var velocity: Vector2 = burst["velocity"]
				if burst["kind"] == "shard":
					velocity.y += 420.0 * delta
				elif burst["kind"] == "ember":
					velocity *= 0.94
				burst["velocity"] = velocity
				burst["position"] = Vector2(burst["position"]) + velocity * delta
	for index in range(blade_trails.size() - 1, -1, -1):
		blade_trails[index]["life"] = float(blade_trails[index]["life"]) - delta
		if float(blade_trails[index]["life"]) <= 0.0:
			blade_trails.remove_at(index)
	_glow.queue_redraw()


func blade_effect_pixels() -> Dictionary:
	var pixels: Dictionary = {}
	# Newest arcs first: a white core, then cyan and deep-blue layers outward on the trailing side.
	for index in range(blade_trails.size() - 1, -1, -1):
		var item := blade_trails[index]
		var fresh := float(item["life"]) > 0.085
		var edge: Vector2i = item.get("edge", Vector2i(0, 1))
		var width: int = item.get("width", 1)
		for pixel in item["pixels"]:
			var point: Vector2i = pixel
			if not pixels.has(point) and pixels.size() < MAX_BLADE_PIXELS:
				pixels[point] = WHITE if fresh else BLUE
			for layer in range(1, width + 1):
				var outside := point + edge * layer
				if not pixels.has(outside) and pixels.size() < MAX_BLADE_PIXELS:
					pixels[outside] = (BLUE if layer == 1 else (CYAN if layer == 2 else DEEP)) if fresh else DEEP
	return pixels


# Integer Bresenham segments keep thin lines on the native pixel grid.
static func pixel_line(start: Vector2, end: Vector2) -> Array[Vector2i]:
	var pixels: Array[Vector2i] = []
	var a := Vector2i(start.round())
	var b := Vector2i(end.round())
	var dx := absi(b.x - a.x)
	var sx := 1 if a.x < b.x else -1
	var dy := -absi(b.y - a.y)
	var sy := 1 if a.y < b.y else -1
	var error := dx + dy
	while true:
		pixels.append(a)
		if a == b:
			break
		var twice := 2 * error
		if twice >= dy:
			error += dy
			a.x += sx
		if twice <= dx:
			error += dx
			a.y += sy
	return pixels


# Midpoint circle on the native grid.
static func pixel_circle(center: Vector2i, radius: int) -> Array[Vector2i]:
	var pixels: Array[Vector2i] = []
	var x := radius
	var y := 0
	var error := 1 - radius
	while x >= y:
		for point in [Vector2i(x, y), Vector2i(y, x), Vector2i(-y, x), Vector2i(-x, y), Vector2i(-x, -y), Vector2i(-y, -x), Vector2i(y, -x), Vector2i(x, -y)]:
			pixels.append(center + point)
		y += 1
		if error < 0:
			error += 2 * y + 1
		else:
			x -= 1
			error += 2 * (y - x) + 1
	return pixels


func _draw() -> void:
	for item in afterimages:
		draw_texture(item["texture"], Vector2(item["position"]).round() - global_position, Color(0.55, 0.75, 0.95, 0.30))
	for effect in effects:
		if effect.get("back", false):
			draw_rect(Rect2(Vector2(effect["position"]).round() - global_position, Vector2.ONE), effect["color"])


func _draw_glow() -> void:
	var origin := global_position
	for effect in effects:
		if effect.get("back", false):
			continue
		if effect.has("tail"):
			for pixel in pixel_line(Vector2(effect["position"]), Vector2(effect["position"]) - Vector2(effect["tail"])):
				_glow.draw_rect(Rect2(Vector2(pixel) - origin, Vector2.ONE), effect["color"])
		else:
			_glow.draw_rect(Rect2(Vector2(effect["position"]).round() - origin, Vector2.ONE), effect["color"])
	for burst in bursts:
		if float(burst.get("delay", 0.0)) > 0.0:
			continue
		var colour: Color = burst["color"]
		match String(burst["kind"]):
			"ring":
				var fade := float(burst["life"]) / float(burst["max_life"])
				var radius := int(round(float(burst["radius"])))
				for pixel in pixel_circle(Vector2i(Vector2(burst["position"])), radius):
					_glow.draw_rect(Rect2(Vector2(pixel) - origin, Vector2.ONE), Color(colour, 0.35 + 0.65 * fade))
				if fade > 0.5:
					for pixel in pixel_circle(Vector2i(Vector2(burst["position"])), maxi(1, radius - 1)):
						_glow.draw_rect(Rect2(Vector2(pixel) - origin, Vector2.ONE), Color(CYAN, fade * 0.8))
			"shard":
				var tip := Vector2(burst["position"])
				for pixel in pixel_line(tip, tip - Vector2(burst["velocity"]).normalized() * 3.0):
					_glow.draw_rect(Rect2(Vector2(pixel) - origin, Vector2.ONE), colour)
			"ember":
				if int(float(burst["life"]) * 30.0) % 3 != 0:
					_glow.draw_rect(Rect2(Vector2(burst["position"]).round() - origin, Vector2.ONE), colour)
			"streak":
				for pixel in pixel_line(Vector2(burst["position"]), Vector2(burst["position"]) - Vector2(burst["tail"])):
					_glow.draw_rect(Rect2(Vector2(pixel) - origin, Vector2.ONE), Color(colour, 0.8))
			"focus":
				var center := Vector2(burst["position"])
				for line in burst["lines"]:
					var ray := Vector2.from_angle(float(line[0]))
					for pixel in pixel_line(center + ray * float(line[1]), center + ray * float(line[2])):
						_glow.draw_rect(Rect2(Vector2(pixel) - origin, Vector2.ONE), Color(colour, 0.9))
	var pixels := blade_effect_pixels()
	for pixel in pixels:
		_glow.draw_rect(Rect2(Vector2(pixel) - origin, Vector2.ONE), pixels[pixel])
