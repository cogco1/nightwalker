extends "res://tests/support/isolated_suite.gd"
## GPU proof from real interiors and real F8 travel. Does not add targets or replace game materials.
## Godot --path game --fixed-fps 60 --script res://tests/recorders/capture_interior_lighting.gd

const CONTROLS = preload("res://scripts/core/controls.gd")
const HOME := "res://scenes/home_601.tscn"
const HOSPITAL := "res://scenes/underground_hospital.tscn"
const STREET := "res://scenes/night_street_proto.tscn"
const OUT := "res://evidence/interior_lighting/"
const WINDOW_SIZE := Vector2i(1280, 720)
var shots: Array[Dictionary] = []
var _finished := false


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(120.0).timeout.connect(func() -> void:
		push_error("Interior lighting GPU recorder exceeded its deadline")
		quit(2)
	)
	call_deferred("run")


func frames(count := 4) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(code: int) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(4)


func open_scene(path: String) -> Node2D:
	assert(change_scene_to_file(path) == OK)
	await frames(15)
	assert(current_scene != null and current_scene.scene_file_path == path)
	return current_scene as Node2D


func place(scene: Node2D, point: Vector2, facing := "down") -> void:
	var player: CharacterBody2D = scene.get("player")
	player.freeze(self)
	player.position = point
	player.velocity = Vector2.ZERO
	player.facing = facing
	player.show_idle()
	if scene.has_method("follow_player"):
		scene.call("follow_player")
	await frames(6)


func hospital_view(scene: Node2D, mode: int, floor_id: int, room: String, point: Vector2) -> void:
	var old_player: CharacterBody2D = scene.get("player")
	old_player.unfreeze(self)
	scene.set("floor_id", floor_id)
	scene.call("activate_view", mode, room, point)
	await frames(6)
	await place(scene, point, "right" if mode == 1 else "down")


func shot(label: String) -> void:
	if root.mode != Window.MODE_WINDOWED or root.size != WINDOW_SIZE:
		root.mode = Window.MODE_WINDOWED
		root.size = WINDOW_SIZE
		await frames(2)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var rendered_size := image.get_size()
	# A viewport-rendered street uses the same nearest enlargement as its visible window.
	if rendered_size == Vector2i(320, 180):
		image.resize(WINDOW_SIZE.x, WINDOW_SIZE.y, Image.INTERPOLATE_NEAREST)
	assert(image.get_size() == WINDOW_SIZE)
	var filename := "%02d_%s.png" % [shots.size() + 1, label]
	assert(image.save_png(OUT + filename) == OK)
	var scene: Node2D = current_scene as Node2D
	var player: CharacterBody2D = scene.get("player")
	var sprite := player.get_node("Sprite") as AnimatedSprite2D
	var material := sprite.material as ShaderMaterial
	var snapshot := {"file": filename, "scene": scene.scene_file_path,
		"window_size": [1280, 720], "render_source_size": [rendered_size.x, rendered_size.y],
		"player": [player.position.x, player.position.y], "player_scale": [player.scale.x, player.scale.y],
		"sprite_scale": [sprite.scale.x, sprite.scale.y], "animation": sprite.animation,
		"frame": sprite.frame, "interior_helpers": scene.find_children("InteriorLighting", "Node2D", true, false).size(),
		"ambient_nodes": scene.find_children("*", "CanvasModulate", true, false).size(),
		"glow_nodes": scene.find_children("*", "WorldEnvironment", true, false).size()}
	if scene.scene_file_path == HOME:
		snapshot["tv_frame"] = int(scene.prop_effects.tv_frame)
		snapshot["pc_frame"] = int(scene.prop_effects.pc_frame)
	elif scene.scene_file_path == HOSPITAL:
		snapshot["view_mode"] = int(scene.view_mode)
		snapshot["floor_id"] = int(scene.floor_id)
		snapshot["clinical_power"] = bool(scene.interactions.power_states.get("clinical", true))
	if material != null:
		snapshot["rim_direction"] = material.get_shader_parameter("rim_a_dir")
		snapshot["rim_color"] = material.get_shader_parameter("rim_a_color")
		snapshot["reflection"] = material.get_shader_parameter("reflect_strength")
	shots.append(snapshot)


func breaker(scene: Node2D, powered: bool) -> void:
	await hospital_view(scene, 0, 1, "entry", Vector2(116, 157))
	var player: CharacterBody2D = scene.get("player")
	player.unfreeze(self)
	scene.security.grant_item("breaker_key")
	if bool(scene.interactions.power_states.get("clinical", true)) != powered:
		await tap(KEY_E)
		await tap(KEY_ESCAPE)
	await frames(6)
	assert(bool(scene.interactions.power_states.get("clinical", true)) == powered)


func f8_arrive(path: String) -> void:
	await tap(KEY_F8)
	for _index in range(90):
		if current_scene != null and current_scene.scene_file_path == path and not root.get_node("SceneRoutes").switching:
			await frames(8)
			return
		await frames(1)
	assert(false, "F8 did not arrive at " + path)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var home := await open_scene(HOME)
	await place(home, Vector2(110, 104))
	await shot("home_both_screens_on_a")
	await frames(24)
	await shot("home_both_screens_on_b")
	home.call("set_device_power", "computer", false)
	await frames(8)
	await shot("home_computer_off_tv_on")
	home.call("set_device_power", "television", false)
	await frames(8)
	await shot("home_both_screens_off")
	home.call("set_device_power", "computer", true)
	await frames(8)
	await shot("home_computer_on_tv_off")
	home.call("set_device_power", "television", true)
	await place(home, Vector2(60, 89))
	await shot("home_player_below_computer")
	await place(home, Vector2(180, 82))
	await shot("home_player_below_television")
	home.call("_open_interaction", "television")
	await frames(65)
	await shot("home_dialogue_hud_untinted")
	home.call("close_dialogue")
	home.player.unfreeze(self)
	await f8_arrive(STREET)
	await shot("f8_actual_night_street_entry")
	await f8_arrive(HOME)
	home = current_scene as Node2D
	await shot("f8_return_home_light_rig_once")
	var hospital := await open_scene(HOSPITAL)
	await breaker(hospital, true)
	await hospital_view(hospital, 0, 1, "ward", Vector2(235, 65))
	await shot("hospital_top_1f_power_on")
	await hospital_view(hospital, 0, 2, "treatment", Vector2(371, 168))
	await shot("hospital_top_2f_power_on")
	await hospital_view(hospital, 1, 2, "treatment", Vector2(219, 164))
	await shot("hospital_side_upper_power_on")
	await hospital_view(hospital, 1, 1, "ward", Vector2(219, 286))
	await shot("hospital_side_lower_power_on")
	await breaker(hospital, false)
	await hospital_view(hospital, 0, 1, "ward", Vector2(235, 65))
	await shot("hospital_top_1f_clinical_off")
	await hospital_view(hospital, 0, 2, "treatment", Vector2(371, 168))
	await shot("hospital_top_2f_clinical_off")
	await hospital_view(hospital, 1, 2, "treatment", Vector2(219, 164))
	await shot("hospital_side_upper_clinical_off_lower_still_on")
	await hospital_view(hospital, 1, 1, "ward", Vector2(219, 286))
	await shot("hospital_side_lower_clinical_off")
	await breaker(hospital, true)
	await hospital_view(hospital, 1, 2, "treatment", Vector2(219, 164))
	await shot("hospital_side_upper_power_restored")
	var file := FileAccess.open(OUT + "capture_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": "passed", "renderer": RenderingServer.get_video_adapter_name(),
		"source": "real playable interiors and actual F8 travel", "shots": shots}, "\t"))
	file.close()
	_finished = true
	print(JSON.stringify({"status": "passed", "captures": shots.size(), "output": OUT}))
	quit(0)
