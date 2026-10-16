extends Node2D
## Night street (side view only). F8 enters from an interior and returns to that interior's safe position.
## Run-NightStreet.cmd can also launch it directly; F8 then returns to the safe house.
## Light = being watched: standing in the patrol drone's cone raises exposure; full exposure marks you.

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const GAME_SESSION = preload("res://scripts/core/game_session.gd")
const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const LEVEL_KIT = preload("res://scripts/levels/level_kit.gd")
const BEAM_DRONE = preload("res://scripts/levels/night_street/beam_drone.gd")
const HOVER_TARGET = preload("res://scripts/levels/night_street/hover_target.gd")
const RAIN = preload("res://scripts/levels/night_street/rain.gd")
const EMISSIVE = preload("res://shaders/emissive_add.gdshader")
const WET = preload("res://shaders/wet_reflection.gdshader")
const FOG = preload("res://shaders/low_fog.gdshader")
const POST = preload("res://shaders/exposure_post.gdshader")
const ART := "res://assets/night_street/"
const VIEWPORT_SIZE := Vector2i(320, 180)
const WORLD_WIDTH := 960.0
const FLOOR_Y := 156.0
const START := Vector2(60, 156)
const AMBIENT := Color(0.6, 0.55, 0.76)
# name, scroll factor (0 = fixed to the screen, 1 = moves with the street)
const LAYERS := [["sky", 0.0], ["far_towers", 0.15], ["petra", 0.34], ["district_c", 0.7], ["street", 1.0]]
# Street lights come from the art: tools/art/assemble_night_street.py writes one entry per self-lit fixture
# (lamp heads, kiosk sign, vending machine, ID gate) into lights.json. layout.json holds the hand-placed data:
# hover drone spots ("targets") and "fallback_lights" (same entry format, colour as hex or [r, g, b]) used
# only if lights.json is missing.
const LIGHTS_PATH := "res://assets/night_street/lights.json"
const LAYOUT_PATH := "res://assets/night_street/layout.json"
# Street lights only reach the street layer and the actors; the parallax backdrop keeps its own colours.
const LIT_MASK := 1
const BACKDROP_MASK := 2
const EXPOSURE_RISE := 0.55
const EXPOSURE_FALL := 0.22
const UNMARK_BELOW := 0.35

var player: CharacterBody2D
var camera: Camera2D
var drone: Node2D
var exposure := 0.0
var marked := false
var in_beam := false
var look_on := true
var layout: Dictionary = {}
var _parallax: Array = []
var _lights: Array[PointLight2D] = []
var _beam_light: PointLight2D
var _hero_material: ShaderMaterial
var _wet: ShaderMaterial
var _fog: ShaderMaterial
var _post: ShaderMaterial
var _rain: Node2D
var _hud: Node2D
var _status: Label
var _hint: Label
var _route_hint: Label
var _implants: Node2D
var _scan: Node2D
var _scan_label: Label
var _notice_left := 0.0
var _clock := 0.0


func _ready() -> void:
	get_tree().root.content_scale_size = VIEWPORT_SIZE
	DisplayServer.window_set_title("夜行者 · 夜街原型")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Run after the player's own physics step so camera and exposure use its final position.
	process_physics_priority = 100
	CONTROLS.install()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH)) if FileAccess.file_exists(LAYOUT_PATH) else null
	if parsed is Dictionary:
		layout = parsed
	else:
		push_error("Night street layout is missing: " + LAYOUT_PATH)
	_build_environment()
	_build_backdrop()
	_build_world()
	_build_overlays()
	_create_ui()
	var session := GAME_SESSION.new()
	session.name = "GameSession"
	add_child(session)
	session.keybindings_closed.connect(func(_saved: bool) -> void: refresh_hint())
	_follow_player()


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world_environment := WorldEnvironment.new()
	world_environment.name = "Glow"
	world_environment.environment = environment
	add_child(world_environment)
	var ambient := CanvasModulate.new()
	ambient.name = "NightAmbient"
	ambient.color = AMBIENT
	add_child(ambient)


func _build_backdrop() -> void:
	for index in range(LAYERS.size()):
		var layer_name: String = LAYERS[index][0]
		var holder := Node2D.new()
		holder.name = "Layer_" + layer_name
		holder.z_index = -20 + index
		add_child(holder)
		var base := Sprite2D.new()
		base.centered = false
		base.texture = load(ART + layer_name + ".png")
		base.light_mask = LIT_MASK if layer_name == "street" else BACKDROP_MASK
		holder.add_child(base)
		var lit := Sprite2D.new()
		lit.name = "SelfLit"
		lit.centered = false
		lit.texture = load(ART + layer_name + "_emit.png")
		var glow := ShaderMaterial.new()
		glow.shader = EMISSIVE
		glow.set_shader_parameter("gain", 1.25 + 0.15 * index)
		glow.set_shader_parameter("flicker", 0.35 if layer_name == "street" else 0.0)
		lit.material = glow
		holder.add_child(lit)
		_parallax.append([holder, float(LAYERS[index][1])])


func _build_world() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)
	LEVEL_KIT.add_box(world, Rect2(0, FLOOR_Y, WORLD_WIDTH, 40))
	LEVEL_KIT.add_box(world, Rect2(-16, -40, 16, 240))
	LEVEL_KIT.add_box(world, Rect2(WORLD_WIDTH, -40, 16, 240))
	for item in _light_table():
		var light := _make_light(item[0], item[1], item[2], item[3])
		world.add_child(light)
		_lights.append(light)
	drone = BEAM_DRONE.new()
	drone.name = "PatrolDrone"
	drone.position = Vector2(300, 14)
	drone.floor_y = FLOOR_Y
	drone.z_index = 1
	world.add_child(drone)
	_beam_light = _make_light(Vector2(300, FLOOR_Y - 8), BEAM_DRONE.WATCH, 1.2, 42.0)
	world.add_child(_beam_light)
	var hover_targets: Array = []
	for spot in layout.get("targets", []):
		var target := HOVER_TARGET.new()
		target.position = Vector2(spot[0], spot[1])
		target.z_index = 1
		world.add_child(target)
		hover_targets.append(target)
	player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	player.view_mode = 1
	player.position = START
	player.floor_snap_length = 6.0
	player.z_index = 2
	world.add_child(player)
	for target in hover_targets:
		target.attacker.bind_target(player)
	_hero_material = player.get_node("Sprite").material as ShaderMaterial
	_hero_material.set_shader_parameter("emission_lift", Vector3(1.0 / AMBIENT.r, 1.0 / AMBIENT.g, 1.0 / AMBIENT.b))
	_hero_material.set_shader_parameter("emission_gain", 1.5)
	_hero_material.set_shader_parameter("body_lift", 1.3)
	_implants = player.get_node("Sprite/ImplantOverlay")
	camera = Camera2D.new()
	camera.name = "StreetCamera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position_smoothing_enabled = false
	camera.limit_left = 0
	camera.limit_right = int(WORLD_WIDTH)
	camera.limit_top = 0
	camera.limit_bottom = VIEWPORT_SIZE.y
	add_child(camera)
	camera.make_current()


## Lights as [position, colour, energy, radius in native px]: lights.json, else layout.json fallback_lights.
func _light_table() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LIGHTS_PATH)) if FileAccess.file_exists(LIGHTS_PATH) else null
	var entries: Array = parsed if parsed is Array else layout.get("fallback_lights", [])
	var table: Array = []
	for entry in entries:
		var colour: Variant = entry["colour"]
		table.append([Vector2(entry["position"][0], entry["position"][1]),
			Color(String(colour)) if colour is String else Color(colour[0], colour[1], colour[2]),
			float(entry["energy"]), float(entry["radius"])])
	return table


func _make_light(at: Vector2, colour: Color, energy: float, radius: float) -> PointLight2D:
	# Banded falloff reads as pixel-art lighting instead of a smooth airbrush.
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.65, 0.9])
	gradient.colors = PackedColorArray([Color.WHITE, Color(0.55, 0.55, 0.55), Color(0.22, 0.22, 0.22), Color.BLACK])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	var light := PointLight2D.new()
	light.texture = texture
	light.texture_scale = radius * 2.0 / 128.0
	light.color = colour
	light.energy = energy
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.position = at
	light.range_item_cull_mask = LIT_MASK
	light.set_meta("radius", radius)
	return light


func _build_overlays() -> void:
	var wet_layer := CanvasLayer.new()
	wet_layer.name = "WetStreet"
	wet_layer.layer = 1
	add_child(wet_layer)
	var wet_copy := BackBufferCopy.new()
	wet_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	wet_layer.add_child(wet_copy)
	_wet = ShaderMaterial.new()
	_wet.shader = WET
	_wet.set_shader_parameter("floor_y", FLOOR_Y)
	# the street art already has painted reflections under its lamps; the live mirror only adds the actors
	_wet.set_shader_parameter("strength", 0.2)
	_wet.set_shader_parameter("puddle_strength", 0.5)
	wet_layer.add_child(_screen_rect(Rect2(0, FLOOR_Y, VIEWPORT_SIZE.x, VIEWPORT_SIZE.y - FLOOR_Y), _wet))
	var weather := CanvasLayer.new()
	weather.name = "Weather"
	weather.layer = 2
	add_child(weather)
	_fog = ShaderMaterial.new()
	_fog.shader = FOG
	weather.add_child(_screen_rect(Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE)), _fog))
	_rain = RAIN.new()
	_rain.floor_y = FLOOR_Y
	weather.add_child(_rain)
	var post_layer := CanvasLayer.new()
	post_layer.name = "ExposurePost"
	post_layer.layer = 30
	add_child(post_layer)
	var post_copy := BackBufferCopy.new()
	post_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	post_layer.add_child(post_copy)
	_post = ShaderMaterial.new()
	_post.shader = POST
	post_layer.add_child(_screen_rect(Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE)), _post))


func _screen_rect(area: Rect2, shader_material: ShaderMaterial) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = area.position
	rect.size = area.size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = shader_material
	return rect


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "StreetUI"
	canvas.layer = 31
	add_child(canvas)
	var title := PIXEL_UI.label(canvas, Vector2(5, 3), Vector2(310, 16), "C区 · 夜街（原型）")
	title.modulate = Color("c9b8e8")
	_route_hint = PIXEL_UI.label(canvas, Vector2(168, 3), Vector2(66, 16), "")
	_route_hint.modulate = Color("c9b8e8")
	_hint = PIXEL_UI.label(canvas, Vector2(5, 162), Vector2(310, 16))
	_hint.modulate = Color("9d8fc0")
	refresh_hint()
	_status = PIXEL_UI.label(canvas, Vector2(206, 16), Vector2(110, 16))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var meter_label := PIXEL_UI.label(canvas, Vector2(236, 1), Vector2(310, 16), "暴露")
	meter_label.modulate = Color("9ff6ff")
	_hud = Node2D.new()
	_hud.name = "ExposureMeter"
	canvas.add_child(_hud)
	_hud.draw.connect(_draw_meter)
	# Scanner readout above the hero while the beam is on them: the scratched serial never resolves.
	_scan = Node2D.new()
	_scan.name = "ScanReadout"
	canvas.add_child(_scan)
	_scan.draw.connect(_draw_scan)
	_scan_label = PIXEL_UI.label(canvas, Vector2.ZERO, Vector2(72, 16))
	_scan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Control hint from the current bindings; the defaults read "AD走 左键斩 右键重击 W+右键跃劈 Shift闪避 R重置"
## (the charge, a held left click, no longer fits on the line once the leap cleave is named).
func refresh_hint() -> void:
	_route_hint.text = "" if CONTROLS.current.values().has(KEY_F8) else "F8返回"
	_hint.text = "%s%s走 %s斩 %s重击 %s+%s跃劈 %s闪避 %s重置" % [CONTROLS.hint_text("move_left"), CONTROLS.hint_text("move_right"),
		CONTROLS.hint_text("attack_mouse"), CONTROLS.hint_text("heavy_mouse"), CONTROLS.hint_text("rising_modifier"),
		CONTROLS.hint_text("heavy_mouse"), CONTROLS.hint_text("dash_modifier"), CONTROLS.hint_text("reset_arena")]


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	_follow_player()
	var feet := player.global_position + Vector2(0, -2)
	in_beam = drone.contains(feet) or drone.contains(feet + Vector2(0, -14)) or drone.contains(feet + Vector2(0, -24))
	exposure = clampf(exposure + (EXPOSURE_RISE if in_beam else -EXPOSURE_FALL) * delta, 0.0, 1.0)
	if exposure >= 1.0:
		marked = true
	elif exposure < UNMARK_BELOW:
		marked = false
	drone.marked = marked
	drone.target_x = player.global_position.x if marked else -1.0
	_update_hero_light()


func _process(delta: float) -> void:
	_clock += delta
	_notice_left = maxf(0.0, _notice_left - delta)
	var left := camera.get_screen_center_position().x - VIEWPORT_SIZE.x * 0.5
	for entry in _parallax:
		entry[0].position.x = roundf(left * (1.0 - entry[1]))
	_beam_light.position = drone.ground_spot() + Vector2(0, -8)
	_beam_light.color = drone.light_color()
	_wet.set_shader_parameter("scroll_x", left)
	_fog.set_shader_parameter("scroll_x", left)
	_rain.scroll_x = left
	_post.set_shader_parameter("exposure", exposure)
	_post.set_shader_parameter("marked", 1.0 if marked else 0.0)
	if _notice_left <= 0.0:
		if marked:
			_status.text = "已被标记" if fmod(_clock, 0.5) < 0.3 else ""
			_status.modulate = Color("ff4f7e")
		elif in_beam:
			_status.text = "监控中"
			_status.modulate = Color("9ff6ff")
		else:
			_status.text = ""
	_hud.queue_redraw()
	_scan.queue_redraw()
	_scan_label.visible = in_beam
	if in_beam:
		_scan_label.position = _scan_panel(left).position + Vector2(0, 9)
		_scan_label.text = "已标记" if marked else ("ID 无法识别" if fmod(_clock, 0.6) < 0.45 else "ID ？？？？")
		_scan_label.modulate = Color("ff4f7e") if marked else Color("9ff6ff")


func _follow_player() -> void:
	# Horizontal follow only: the street is one screen tall.
	LEVEL_KIT.follow(camera, Vector2(player.global_position.x, VIEWPORT_SIZE.y * 0.5), Rect2(0, 0, WORLD_WIDTH, VIEWPORT_SIZE.y),
		Vector2(VIEWPORT_SIZE))


# The two strongest nearby lights drive the hero's rim shader; inside the beam the drone wins.
func _update_hero_light() -> void:
	var chest := player.global_position + Vector2(0, -16)
	var candidates: Array = []
	for light in _lights:
		var to_light := light.global_position - chest
		var influence := light.energy * clampf(1.0 - to_light.length() / float(light.get_meta("radius")), 0.0, 1.0)
		if influence > 0.03:
			candidates.append([influence, to_light.normalized(), light.color])
	if in_beam:
		candidates.append([1.4, (drone.global_position - chest).normalized(), drone.light_color()])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var rims := [[Vector2.UP, Color(0.31, 0.94, 1.0), 0.15], [Vector2.RIGHT, Color(1.0, 0.24, 0.6), 0.0]]
	for index in range(mini(2, candidates.size())):
		rims[index] = [candidates[index][1], candidates[index][2], clampf(candidates[index][0] * 0.75, 0.0, 0.85)]
	_hero_material.set_shader_parameter("rim_a_dir", rims[0][0])
	_hero_material.set_shader_parameter("rim_a_color", Color(rims[0][1], rims[0][2]))
	_hero_material.set_shader_parameter("rim_b_dir", rims[1][0])
	_hero_material.set_shader_parameter("rim_b_color", Color(rims[1][1], rims[1][2]))
	# Reflective tape on the straps flares in whatever light is strongest on the hero.
	var strongest: Array = candidates[0] if not candidates.is_empty() else [0.0, Vector2.UP, Color(0.85, 0.95, 1.0)]
	_hero_material.set_shader_parameter("reflect_strength", clampf(0.12 + float(strongest[0]) * 0.7, 0.12, 1.0))
	_hero_material.set_shader_parameter("reflect_color", Color(strongest[2]).lightened(0.35))
	_implants.scanned = 1.0 if in_beam else 0.0


func _draw_meter() -> void:
	var origin := Vector2(262, 6)
	var colour := Color("ff4f7e") if marked else Color("ff3d9a") if exposure >= 0.7 else Color("4ff0ff")
	_hud.draw_rect(Rect2(origin + Vector2(-4, 0), Vector2(2, 5)), colour)
	var lit := int(ceilf(exposure * 10.0 - 0.001))
	for index in range(10):
		var on := index < lit and not (marked and fmod(_clock, 0.5) > 0.3)
		_hud.draw_rect(Rect2(origin + Vector2(index * 5, 1), Vector2(4, 3)), colour if on else Color("2a2a4a"))


const SCAN_BARS := [2, 1, 1, 3, 1, 2, 1, 1, 2, 3, 1, 1, 2, 1]


# Panel above the hero's head, kept on screen: magnified serial on top, verdict underneath.
func _scan_panel(left: float) -> Rect2:
	var head := (player.global_position - Vector2(left, 0)).round() + Vector2(0, -34)
	var origin := Vector2(clampf(head.x - 36.0, 2.0, VIEWPORT_SIZE.x - 74.0), maxf(head.y - 26.0, 22.0))
	return Rect2(origin, Vector2(72, 24))


func _draw_scan() -> void:
	if not in_beam:
		return
	var left := camera.get_screen_center_position().x - VIEWPORT_SIZE.x * 0.5
	var panel := _scan_panel(left)
	var colour := Color("ff4f7e") if marked else Color("4ff0ff")
	_scan.draw_rect(panel, Color(0.02, 0.02, 0.06, 0.82))
	_scan.draw_rect(panel, Color(colour, 0.9), false)
	# magnified serial: a scratched-out band shifts every tick, so it never reads
	var bars_width := 0
	for width in SCAN_BARS:
		bars_width += width
	var x := panel.position.x + floorf((panel.size.x - bars_width) * 0.5)
	var top := panel.position.y + 2.0
	var glitch := int(_clock * 9.0)
	var bar_index := 0
	for width in SCAN_BARS:
		var scratched := (bar_index + glitch) % 5 < 2
		if bar_index % 2 == 0:
			_scan.draw_rect(Rect2(Vector2(x, top), Vector2(width, 6)), Color("6a2032") if scratched else Color(colour, 0.95))
		x += width
		bar_index += 1
	for scratch in range(2):
		var sx := panel.position.x + 24.0 + scratch * 9.0 + float(glitch % 3)
		_scan.draw_line(Vector2(sx, top), Vector2(sx + 4.0, top + 6.0), Color("ff3d6e"), 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F9:
		look_on = not look_on
		_hero_material.set_shader_parameter("look", 1.0 if look_on else 0.0)
		_notice("赛博配色" if look_on else "原始配色")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_arena"):
		reset_street()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("switch_view"):
		_notice("夜街原型只有侧视")
		get_viewport().set_input_as_handled()


func _notice(text: String) -> void:
	_status.text = text
	_status.modulate = Color("e8e0ff")
	_notice_left = 1.5


func reset_street() -> void:
	player.position = START
	player.velocity = Vector2.ZERO
	exposure = 0.0
	marked = false
	_follow_player()
