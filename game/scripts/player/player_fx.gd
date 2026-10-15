extends Node2D
## The hero's pixel effects: dust, sparks, impact rays and slash marks, airflow, charge motes, blade trails and
## afterimages. The player adds it as its first child, so it draws behind the sprite exactly like the old
## player._draw did, and steps it from its own physics tick (no extra loop). Decorative randomness has its own
## generator, so effects never shift the player's critical-hit rolls.

const MAX_BLADE_PIXELS := 70
const WHITE := Color("f2f8ff")
const BLUE := Color("8ebce8")
const DUST := Color("82717c")
# Impact read per hit-stop weight: ray count, ray reach, life, rows of the slash mark.
const IMPACT := {
	&"light": {"rays": 6, "reach": 6.0, "life": 0.09, "rows": 1},
	&"critical": {"rays": 8, "reach": 9.0, "life": 0.11, "rows": 2},
	&"heavy": {"rays": 12, "reach": 15.0, "life": 0.15, "rows": 3},
}

var effects: Array[Dictionary] = []
var blade_trails: Array[Dictionary] = []
var afterimages: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func add(effect: Dictionary) -> void:
	effects.append(effect)


func dust(point: Vector2, count: int) -> void:
	for index in range(count):
		add({"position": point.round() + Vector2(index * 2 - count, -1), "velocity": Vector2((index - count / 2.0) * 9.0, -10.0 - index * 2.0), "life": 0.18, "color": DUST})


func sparks(point: Vector2) -> void:
	for index in range(5):
		add({"position": point.round(), "velocity": Vector2(-32 + index * 16, -35 + abs(index - 2) * 16), "life": 0.14, "color": WHITE if index % 2 == 0 else BLUE})


# A slash mark across the target along the swing, rays bursting from the contact and extra sparks.
# The hit-stop freezes on the frame these are spawned in.
func impact(point: Vector2, weight: StringName, direction: Vector2, feet: Vector2) -> void:
	var look: Dictionary = IMPACT.get(weight, IMPACT[&"light"])
	var rays: int = look["rays"]
	var reach: float = look["reach"]
	var life: float = look["life"]
	for index in range(rays):
		var ray := Vector2.from_angle(TAU * index / rays + 0.35)
		add({"position": (point + ray * 3.0).round(), "velocity": ray * reach / life, "tail": ray * reach * 0.45,
			"life": life, "color": WHITE if index % 2 == 0 else BLUE})
	var across := Vector2(direction.x, -0.65).normalized() if direction.x != 0.0 else Vector2(0.65, direction.y).normalized()
	for row in range(int(look["rows"])):
		var offset := Vector2(0, row) if direction.x != 0.0 else Vector2(row, 0)
		add({"position": (point + across * reach + offset).round(), "velocity": Vector2.ZERO, "tail": across * reach * 2.0,
			"life": life * 1.4, "color": WHITE if row == 0 else BLUE})
	if weight != &"light":
		sparks(point + Vector2(0, -3))
	if weight == &"heavy":
		sparks(point + Vector2(0, 3))
		dust(feet + direction * 6.0, 5)


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
	for offset in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		add({"position": tip + offset, "velocity": Vector2.ZERO, "life": 0.05, "color": WHITE})


# Coiling: light gathers onto the blade from a ring of the given radius.
func gather(tip: Vector2, radius: float, angle: float) -> void:
	var start := tip + Vector2.from_angle(angle) * radius
	add({"position": start.round(), "velocity": (tip - start) / 0.1, "life": 0.1, "color": BLUE})


func trail(pixels: Array[Vector2i], edge: Vector2i, life: float) -> void:
	blade_trails.append({"pixels": pixels, "edge": edge, "life": life})


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
	for index in range(blade_trails.size() - 1, -1, -1):
		blade_trails[index]["life"] = float(blade_trails[index]["life"]) - delta
		if float(blade_trails[index]["life"]) <= 0.0:
			blade_trails.remove_at(index)


func blade_effect_pixels() -> Dictionary:
	var pixels: Dictionary = {}
	# Prefer the newest white core and limit the sweep to a crisp, readable footprint.
	for index in range(blade_trails.size() - 1, -1, -1):
		var item := blade_trails[index]
		var core := WHITE if float(item["life"]) > 0.085 else BLUE
		var edge: Vector2i = item.get("edge", Vector2i(0, 1))
		for pixel in item["pixels"]:
			var point: Vector2i = pixel
			if not pixels.has(point) and pixels.size() < MAX_BLADE_PIXELS:
				pixels[point] = core
			var outside := point + edge
			if not pixels.has(outside) and pixels.size() < MAX_BLADE_PIXELS:
				pixels[outside] = BLUE
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


func _draw() -> void:
	for item in afterimages:
		draw_texture(item["texture"], Vector2(item["position"]).round() - global_position, Color(0.55, 0.75, 0.95, 0.30))
	for effect in effects:
		var point := Vector2(effect["position"]).round() - global_position
		if effect.has("tail"):
			for pixel in pixel_line(Vector2(effect["position"]), Vector2(effect["position"]) - Vector2(effect["tail"])):
				draw_rect(Rect2(Vector2(pixel) - global_position, Vector2.ONE), effect["color"])
		else:
			draw_rect(Rect2(point, Vector2.ONE), effect["color"])
	var pixels := blade_effect_pixels()
	for pixel in pixels:
		draw_rect(Rect2(Vector2(pixel) - global_position, Vector2.ONE), pixels[pixel])
