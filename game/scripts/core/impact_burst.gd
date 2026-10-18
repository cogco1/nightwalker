extends Node
## Hit-impact prototype (2026-10-18; on by default, F10 switches it off and on to compare): sword qi that bursts
## out of the screen and a slight shake, laid over impact v2 (impact_v2.gd's ink cuts and splatter, GameSession's
## hit-stops), in the same ink-and-crimson look: no additive light and no full-screen flash. Visual only.
##
## - Sword qi: a heavy swing (QI_MOVES) releases a black-crimson crescent from the blade, ink speed streaks behind
##   it. It accelerates and swells to nearly the screen's height as it travels, as if coming at the viewer, passes
##   over the HUD and breaks out through the screen edge: a jagged crack along the edge and ink splinters. It hurts
##   nobody.
## - Screen cut: a critical, heavy or killing blow slices the frozen frame. From the second freeze frame a cut runs
##   through the contact across the whole screen and past both edges, and the two halves slide apart along it
##   (shaders/screen_cut.gdshader) until the freeze ends; the ink line fades CUT_FADE seconds later.
## - Tremor: after every hit-stop the camera shakes in a short fixed pattern (TREMORS), replacing the plain recoil
##   and keeping its bounds: at most 3 native pixels across and 1 down, back to rest.
##
## GameSession owns it: bind_player() follows the hero's swings and contacts, tremor() supplies the pattern and the
## session's hit_stop_frame / hit_stop_finished drive the cut. Everything runs on real time, freezes included.

const CONTROLS = preload("res://scripts/core/controls.gd")
const STYLE = preload("res://scripts/ui/hud_style.gd")
const CUT_SHADER = preload("res://shaders/screen_cut.gdshader")
const TOGGLE_KEY := KEY_F10
const SCREEN := Vector2(320, 180)
## Moves whose release throws sword qi, with its size.
const QI_MOVES := {&"heavy_slash": 1.25, &"rush_cleave": 1.0, &"chase_cleave": 1.0, &"spin_cleave_b": 0.9,
	&"counter_slash": 1.1, &"air_spin_c": 0.85}
const QI_LIFE := 0.36
## Distance from the blade at the start and travelled over the life (eased in: it speeds up as it goes).
const QI_START := 22.0
const QI_TRAVEL := 520.0
const QI_HEIGHT := -19.0
## Crescent half-height at the start and what it gains by the end (times the move's size), and its thickness.
const QI_RADIUS := 20.0
const QI_GROWTH := 190.0
const QI_THICK := 3.0
const QI_THICK_GROWTH := 11.0
const CRACK_LIFE := 0.14
const MAX_WAVES := 3
const MAX_SPLINTERS := 64
const CUT_WEIGHTS := [&"critical", &"heavy", &"kill"]
const CUT_FADE := 0.16
const SPLIT_PX := 2.0
## A contact older than this does not cut (a story freeze long after the last blow).
const STRIKE_MEMORY := 0.5
## Camera offsets after a freeze, one per displayed frame; x follows the blow.
const TREMORS := {
	&"tick": [Vector2(1, 0), Vector2(-1, 0), Vector2.ZERO],
	&"light": [Vector2(1, 0), Vector2(-1, 0), Vector2(1, 0), Vector2.ZERO],
	&"critical": [Vector2(2, 0), Vector2(-2, 1), Vector2(1, -1), Vector2(-1, 0), Vector2.ZERO],
	&"heavy": [Vector2(3, 1), Vector2(-2, -1), Vector2(2, 0), Vector2(-1, 1), Vector2.ZERO],
	&"kill": [Vector2(3, 1), Vector2(-3, -1), Vector2(2, 1), Vector2(-1, -1), Vector2.ZERO],
}
const INK := Color(0.055, 0.025, 0.06)
const CRIMSON := Color(0.57, 0.11, 0.21)
const EMBER := Color(0.78, 0.24, 0.32)
const CORE := Color(0.93, 0.96, 1.0)
const TOAST_SECONDS := 1.4
## Layers above everything a scene draws, the hit-stop's frozen frame (100) included.
const SPLIT_LAYER := 108
const DRAW_LAYER := 109

## On for every scene until F10 turns it off; the choice lasts for the run.
static var enabled := true

var player: CharacterBody2D
var session: Node
## Flying sword qi: {at (world feet line point), direction, scale, age, tore}.
var waves: Array[Dictionary] = []
## Ink splinters in screen pixels: {at, velocity, age, life, colour, size}.
var splinters: Array[Dictionary] = []
## Jagged cracks along the screen edge where sword qi broke out: {x, top, bottom, age, seed}.
var cracks: Array[Dictionary] = []
## The current screen cut: {origin (screen px), axis, age, frozen, fade}; empty when none.
var cut: Dictionary = {}
## The last contact: {point (world), direction, weight, time}.
var last_strike: Dictionary = {}
## Counters for tests and recordings.
var waves_thrown := 0
var cuts_made := 0
var tears := 0
var split_layer: CanvasLayer
var split_rect: ColorRect
var split_material: ShaderMaterial
var draw_layer: CanvasLayer
var canvas: Node2D
var toast: Panel
var toast_label: Label
var _toast_left := 0.0
var _clock := 0.0
var _serial := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	session = get_parent()
	split_layer = CanvasLayer.new()
	split_layer.name = "ImpactSplitLayer"
	split_layer.layer = SPLIT_LAYER
	split_layer.add_to_group(&"no_stop_shift")
	add_child(split_layer)
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	split_layer.add_child(copy)
	split_material = ShaderMaterial.new()
	split_material.shader = CUT_SHADER
	split_material.set_shader_parameter("native_size", SCREEN)
	split_material.set_shader_parameter("shift", SPLIT_PX)
	split_rect = ColorRect.new()
	split_rect.name = "ScreenCut"
	split_rect.size = SCREEN
	split_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split_rect.material = split_material
	split_rect.hide()
	split_layer.add_child(split_rect)
	draw_layer = CanvasLayer.new()
	draw_layer.name = "ImpactBurstLayer"
	draw_layer.layer = DRAW_LAYER
	draw_layer.add_to_group(&"no_stop_shift")
	add_child(draw_layer)
	canvas = Node2D.new()
	canvas.name = "ImpactBurstInk"
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	draw_layer.add_child(canvas)
	canvas.draw.connect(_draw_ink)
	toast = STYLE.panel(draw_layer, "PrototypeToast", STYLE.plate(STYLE.INK, Color.TRANSPARENT, STYLE.CYAN))
	toast_label = STYLE.small(toast, Vector2(6, 1), "", STYLE.TEXT)
	toast.hide()
	session.hit_stop_started.connect(_on_stop_started)
	session.hit_stop_frame.connect(_on_stop_frame)
	session.hit_stop_finished.connect(_on_stop_finished)


func bind_player(next: CharacterBody2D) -> void:
	player = next
	waves.clear()
	if not is_instance_valid(player):
		return
	if not player.swing_released.is_connected(_on_swing):
		player.swing_released.connect(_on_swing)
		player.struck.connect(_on_struck)


## The camera pattern after a freeze of `weight`: the prototype's tremor, or `plain` (impact v2's recoil) when off.
func tremor(weight: StringName, plain: Array) -> Array:
	return TREMORS.get(weight, TREMORS[&"light"]) if enabled else plain


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		waves.clear()
		splinters.clear()
		cracks.clear()
		_end_cut()
	toast_label.text = "打击原型 %s · F10" % ("开" if on else "关")
	toast.size = Vector2(STYLE.width(toast_label.text) + 12, 14)
	toast.position = Vector2(roundf((SCREEN.x - toast.size.x) * 0.5), 4)
	toast.modulate.a = 1.0
	toast.show()
	_toast_left = TOAST_SECONDS


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	# A player who bound F10 to an action keeps it.
	if code != TOGGLE_KEY or CONTROLS.current.values().has(TOGGLE_KEY) or session.settings_open:
		return
	set_enabled(not enabled)
	get_viewport().set_input_as_handled()


# --- triggers ------------------------------------------------------------------------------------

func _on_swing(move: StringName) -> void:
	if not enabled or not QI_MOVES.has(move) or not is_instance_valid(player) or int(player.view_mode) != 1:
		return
	var forward := 1.0 if player.facing == "right" else -1.0
	waves.append({"at": player.global_position + Vector2(forward * QI_START, QI_HEIGHT), "direction": forward,
		"scale": float(QI_MOVES[move]), "age": 0.0, "tore": false, "move": move})
	waves_thrown += 1
	while waves.size() > MAX_WAVES:
		waves.pop_front()


func _on_struck(point: Vector2, weight: StringName, direction: Vector2, _killed: bool) -> void:
	last_strike = {"point": point, "direction": direction, "weight": weight, "time": _clock}


## The freeze shows its first frame next and photographs it as the frozen image: stay out of that photograph, or
## a still copy of the flying qi would hang in the frozen frame behind the moving one.
func _on_stop_started() -> void:
	draw_layer.visible = false


## Frame 1 of a freeze has been shown (and photographed): the qi comes back, and the cut starts on the frames that
## follow.
func _on_stop_frame(frame: int, _shake: Vector2i) -> void:
	if frame == 1:
		draw_layer.visible = true
	if frame != 1 or not enabled or last_strike.is_empty() or _clock - float(last_strike["time"]) > STRIKE_MEMORY:
		return
	if session.stop_weight() not in CUT_WEIGHTS:
		return
	_serial += 1
	var direction: Vector2 = last_strike["direction"]
	var forward := Vector2(signf(direction.x) if direction.x != 0.0 else 1.0, 0.0) if absf(direction.x) >= absf(direction.y) else direction.normalized()
	# A steep diagonal through the contact, alternating its lean from blow to blow.
	var axis := forward.rotated(-0.62 if _serial % 2 == 1 else 0.58)
	cut = {"origin": _screen(Vector2(last_strike["point"])).round(), "axis": axis, "age": 0.0, "frozen": true,
		"fade": CUT_FADE, "weight": session.stop_weight()}
	cuts_made += 1
	split_material.set_shader_parameter("origin", Vector2(cut["origin"]) / SCREEN)
	split_material.set_shader_parameter("axis", axis)
	split_material.set_shader_parameter("strength", 1.0)
	split_rect.show()
	# The cut leaves the frame at both ends: ink tears there.
	for end in _edge_points(Vector2(cut["origin"]), axis):
		_tear(end, (end - Vector2(cut["origin"])).normalized(), 7)


func _on_stop_finished(_frames: int) -> void:
	draw_layer.visible = true
	if not cut.is_empty():
		cut["frozen"] = false
	split_material.set_shader_parameter("strength", 0.0)
	split_rect.hide()


func _end_cut() -> void:
	cut = {}
	split_material.set_shader_parameter("strength", 0.0)
	split_rect.hide()


# --- motion ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	for index in range(waves.size() - 1, -1, -1):
		var wave := waves[index]
		wave["age"] = float(wave["age"]) + delta
		if float(wave["age"]) >= QI_LIFE:
			waves.remove_at(index)
			continue
		if not wave["tore"]:
			var lead := _screen(_wave_center(wave)) + Vector2(_wave_radius(wave) * float(wave["direction"]), 0)
			if lead.x < 0.0 or lead.x >= SCREEN.x:
				wave["tore"] = true
				tears += 1
				var edge := Vector2(0.0 if lead.x < 0.0 else SCREEN.x - 1.0, clampf(lead.y, 0.0, SCREEN.y - 1.0))
				var reach := _wave_radius(wave)
				cracks.append({"x": edge.x, "top": maxf(0.0, edge.y - reach * 0.9),
					"bottom": minf(SCREEN.y - 1.0, edge.y + reach * 0.9), "age": 0.0, "seed": tears})
				_tear(edge, Vector2(float(wave["direction"]), 0.0), 18)
				# More splinters burst back off the crack along its length.
				for along in [-0.6, -0.3, 0.3, 0.6]:
					_tear(edge + Vector2(0, reach * along), Vector2(-float(wave["direction"]), along), 3)
	for index in range(cracks.size() - 1, -1, -1):
		cracks[index]["age"] = float(cracks[index]["age"]) + delta
		if float(cracks[index]["age"]) >= CRACK_LIFE:
			cracks.remove_at(index)
	for index in range(splinters.size() - 1, -1, -1):
		var bit := splinters[index]
		bit["age"] = float(bit["age"]) + delta
		if float(bit["age"]) >= float(bit["life"]):
			splinters.remove_at(index)
			continue
		bit["at"] = Vector2(bit["at"]) + Vector2(bit["velocity"]) * delta
	if not cut.is_empty():
		cut["age"] = float(cut["age"]) + delta
		if not cut["frozen"]:
			cut["fade"] = float(cut["fade"]) - delta
			if float(cut["fade"]) <= 0.0:
				_end_cut()
	if _toast_left > 0.0:
		_toast_left -= delta
		toast.modulate.a = clampf(_toast_left / 0.4, 0.0, 1.0)
		if _toast_left <= 0.0:
			toast.hide()
	canvas.queue_redraw()


func _screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


func _progress(wave: Dictionary) -> float:
	return clampf(float(wave["age"]) / QI_LIFE, 0.0, 1.0)


func _wave_center(wave: Dictionary) -> Vector2:
	var t := _progress(wave)
	return Vector2(wave["at"]) + Vector2(float(wave["direction"]) * QI_TRAVEL * pow(t, 1.5), 0.0)


## The crescent grows as it flies, faster at the end: it seems to come out at the viewer.
func _wave_radius(wave: Dictionary) -> float:
	var t := _progress(wave)
	return (QI_RADIUS + QI_GROWTH * pow(t, 1.4)) * float(wave["scale"])


## Where a line through `origin` along `axis` leaves the screen, both ways.
func _edge_points(origin: Vector2, axis: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for way in [1.0, -1.0]:
		var direction: Vector2 = axis * way
		var best := INF
		for bound in [[direction.x, 0.0 - origin.x, SCREEN.x - 1.0 - origin.x], [direction.y, 0.0 - origin.y, SCREEN.y - 1.0 - origin.y]]:
			if absf(bound[0]) < 0.0001:
				continue
			for limit in [bound[1], bound[2]]:
				var t: float = limit / bound[0]
				if t > 0.0:
					best = minf(best, t)
		if best < INF:
			points.append((origin + direction * best).round())
	return points


func _tear(at: Vector2, outward: Vector2, count: int) -> void:
	for index in range(count):
		var spread := (float(index) / maxf(1.0, count - 1.0) - 0.5) * 2.2
		var velocity := outward.rotated(spread) * (120.0 + 40.0 * (index % 3)) + Vector2(0, -30.0 + 15.0 * (index % 4))
		splinters.append({"at": at - outward * 3.0, "velocity": velocity, "age": 0.0, "life": 0.16 + 0.03 * (index % 3),
			"colour": [INK, CRIMSON, EMBER][index % 3], "size": 2 if index % 4 == 0 else 1})
	while splinters.size() > MAX_SPLINTERS:
		splinters.pop_front()


# --- drawing -----------------------------------------------------------------------------------

func _draw_ink() -> void:
	for wave in waves:
		_draw_wave(wave)
	if not cut.is_empty():
		_draw_cut()
	for crack in cracks:
		_draw_crack(crack)
	for bit in splinters:
		var fade := 1.0 - float(bit["age"]) / float(bit["life"])
		var at: Vector2 = Vector2(bit["at"]).round()
		var tail := (-Vector2(bit["velocity"]).normalized() * 4.0).round()
		canvas.draw_line(at, at + tail, Color(bit["colour"], 0.9 * fade), float(bit["size"]), false)


## Where sword qi left the screen: a zigzag split down the edge, dark with a crimson lip, closing fast.
func _draw_crack(crack: Dictionary) -> void:
	var fade := 1.0 - float(crack["age"]) / CRACK_LIFE
	var x := float(crack["x"])
	var inward := 1.0 if x < SCREEN.x * 0.5 else -1.0
	var y := float(crack["top"])
	var step := 0
	var previous := Vector2(x, y)
	while y < float(crack["bottom"]):
		y = minf(float(crack["bottom"]), y + 5.0)
		step += 1
		var depth := (3.0 + float((step * 7 + int(crack["seed"]) * 3) % 7)) * (0.5 + 0.5 * fade)
		var point := Vector2(x + inward * depth, y).round()
		canvas.draw_line(previous, point, Color(INK, 0.95 * fade), 3.0, false)
		canvas.draw_line(previous + Vector2(inward * 2.0, 0), point + Vector2(inward * 2.0, 0), Color(CRIMSON, 0.9 * fade), 1.0, false)
		if step % 2 == 0:
			canvas.draw_line(point, point + Vector2(inward * (depth + 4.0), 2.0).round(), Color(EMBER, 0.8 * fade), 1.0, false)
		previous = point


## One crescent, open behind, as tapering ink with a crimson body, an ember edge and a pale core; three fading
## copies trail it and ink streaks run back towards the blade.
func _draw_wave(wave: Dictionary) -> void:
	var t := _progress(wave)
	var fade := 1.0 - smoothstep(0.8, 1.0, t)
	var forward := float(wave["direction"])
	var center := _screen(_wave_center(wave))
	var radius := _wave_radius(wave)
	var start := _screen(Vector2(wave["at"]))
	for lane in [-0.55, -0.2, 0.25, 0.6]:
		var y := roundf(center.y + radius * lane)
		var tail := center.x - forward * (radius * 0.35 + 6.0)
		var back := lerpf(tail, start.x, 0.55 + 0.1 * absf(lane))
		canvas.draw_line(Vector2(roundf(back), y), Vector2(roundf(tail), y), Color(INK if lane < 0.0 else CRIMSON, 0.55 * fade), 1.0, false)
	for ghost in [3, 2, 1, 0]:
		var past := wave.duplicate()
		past["age"] = maxf(0.0, float(wave["age"]) - ghost * 0.025)
		var alpha: float = fade * [1.0, 0.45, 0.25, 0.12][ghost]
		_crescent(_screen(_wave_center(past)), _wave_radius(past), forward,
			(QI_THICK + QI_THICK_GROWTH * _progress(past)) * float(wave["scale"]) * (1.0 if ghost == 0 else 0.55), alpha, ghost == 0)


func _crescent(center: Vector2, radius: float, forward: float, thickness: float, alpha: float, full: bool) -> void:
	var segments := 26
	var span := 1.2
	var points: Array[Vector2] = []
	for index in range(segments + 1):
		var angle := lerpf(-span, span, float(index) / segments)
		# A flattened arc: tall and shallow, the open side towards the hero.
		points.append((center + Vector2(cos(angle) * radius * 0.5 * forward, sin(angle) * radius)).round())
	for index in range(segments):
		var middle := (float(index) + 0.5) / segments
		var swell := pow(sin(middle * PI), 1.3)
		var width := maxf(1.0, roundf(thickness * swell))
		canvas.draw_line(points[index], points[index + 1], Color(INK, 0.92 * alpha), width + 2.0, false)
		var body := maxf(1.0, roundf(width * 0.6))
		var inward := Vector2(-forward * roundf(width * 0.2), 0)
		canvas.draw_line(points[index] + inward, points[index + 1] + inward, Color(CRIMSON, 0.95 * alpha), body, false)
		if not full:
			continue
		var lip := Vector2(forward * maxf(1.0, roundf(width * 0.3)), 0)
		if index % 3 != 2:
			canvas.draw_line(points[index] + lip, points[index + 1] + lip, Color(EMBER, 0.85 * alpha), 1.0, false)
		if middle > 0.3 and middle < 0.7:
			canvas.draw_line(points[index], points[index + 1], Color(CORE, 0.9 * alpha), 2.0 if width >= 7.0 else 1.0, false)


## The cut across the screen: a hairline first, then an ink band with crimson edges that thins and fades after the
## freeze, both ends running off the screen.
func _draw_cut() -> void:
	var origin: Vector2 = cut["origin"]
	var axis: Vector2 = cut["axis"]
	var normal := axis.orthogonal()
	var age := float(cut["age"])
	var fade := 1.0 if cut["frozen"] else clampf(float(cut["fade"]) / CUT_FADE, 0.0, 1.0)
	var heavy := String(cut["weight"]) != "critical"
	var width := minf(3.0 if not heavy else 5.0, 1.0 + floorf(age * 60.0)) * (0.5 + 0.5 * fade)
	var from := (origin - axis * 420.0).round()
	var to := (origin + axis * 420.0).round()
	canvas.draw_line(from, to, Color(INK, 0.85 * fade), maxf(1.0, roundf(width)), false)
	var edge := normal * (roundf(width * 0.5) + 1.0)
	canvas.draw_line((from + edge).round(), (to + edge).round(), Color(CRIMSON, 0.8 * fade), 1.0, false)
	canvas.draw_line((from - edge).round(), (to - edge).round(), Color(EMBER, 0.55 * fade), 1.0, false)
	if age < 0.06 or cut["frozen"]:
		# Only the cut's hairline is pale; the screen around it keeps its colours.
		canvas.draw_line((origin - axis * 60.0).round(), (origin + axis * 90.0).round(), Color(CORE, 0.9 * fade), 1.0, false)
	# Ink beads along the cut.
	for index in range(9):
		var along := -150.0 + index * 37.0 + (_serial % 3) * 5.0
		var bead := (origin + axis * along + normal * (2.0 + (index % 3))).round()
		canvas.draw_rect(Rect2(bead, Vector2(1 + index % 2, 1)), Color(CRIMSON if index % 2 else INK, 0.8 * fade))
