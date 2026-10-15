extends SceneTree
## Final visual proof uses playable scenes, never the combat laboratory fixture.

const HOME = preload("res://scenes/home_601.tscn")
const HOSPITAL = preload("res://scenes/underground_hospital.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const OUTPUT := "res://evidence/integrated_v14/"
var hospital: Node2D
var recording := ""
var frame_number := 0
var states: Array[Dictionary] = []
var observed: Dictionary = {}


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(2))
	call_deferred("record")


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(50, 120)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tick(count := 1) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame
		if not recording.is_empty():
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			assert(image.get_size() == Vector2i(1280, 720))
			assert(image.save_png(OUTPUT + recording + "/%04d.png" % frame_number) == OK)
			var sprite: AnimatedSprite2D = hospital.player.sprite
			var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
			var pivot := Vector2(texture.get_width() / 2.0, texture.get_height() - 12.0)
			var world_foot := sprite.global_position + sprite.offset + pivot
			assert(world_foot.is_equal_approx(hospital.player.global_position.round()))
			states.append({"clip": recording, "index": frame_number, "scene": hospital.scene_file_path,
				"animation": sprite.animation, "animation_frame": sprite.frame,
				"position": [hospital.player.position.x, hospital.player.position.y],
				"scale": [hospital.player.scale.x, hospital.player.scale.y],
				"sprite_scale": [sprite.scale.x, sprite.scale.y], "world_foot": [world_foot.x, world_foot.y],
				"texture": texture.resource_path, "special_kind": hospital.player.special_kind})
			observed[String(sprite.animation)] = true
			frame_number += 1


func picture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.get_size() == Vector2i(1280, 720))
	assert(image.save_png(OUTPUT + name + "_window.png") == OK)


func tap(code: Key) -> void:
	key(code, true)
	await tick()
	key(code, false)
	await tick()


func attack() -> void:
	mouse(true)
	await tick()
	mouse(false)
	await tick()


func wait_frame(stage: int, frame: int) -> void:
	for _index in range(90):
		if hospital.player.combo_stage == stage and hospital.player.sprite.frame >= frame:
			return
		await tick()
	assert(false, "Requested animation frame did not occur")


func air_chain(direction: int) -> void:
	var facing := "right" if direction > 0 else "left"
	hospital.player.position = Vector2(250 if direction > 0 else 350, 286)
	hospital.player.velocity = Vector2.ZERO
	hospital.player.facing = facing
	hospital.player.call("_show_idle")
	await tick(8)
	assert(hospital.player.is_on_floor())
	recording = "air_dash_" + facing
	frame_number = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + recording))
	await tick(10)
	await tap(KEY_SPACE)
	await tick(8)
	key(KEY_SHIFT, true)
	key(KEY_D if direction > 0 else KEY_A, true)
	await attack()
	key(KEY_D if direction > 0 else KEY_A, false)
	key(KEY_SHIFT, false)
	assert(hospital.player.sprite.animation == "air_dash_stab_" + facing)
	await wait_frame(1, 7)
	assert(hospital.player.dash_executed)
	assert(absf(hospital.player.dash_end.x - hospital.player.dash_start.x - direction * 48.0) < 0.1)
	await picture("hospital_air_dash_" + facing)
	for _index in range(60):
		if not hospital.player.is_attacking:
			break
		await tick()
	await tick(4)
	assert(hospital.player.sprite.animation == "air_idle_" + facing)
	await picture("hospital_air_idle_" + facing)
	await attack()
	await wait_frame(1, 8)
	assert(hospital.player.sprite.animation == "air_attack1_" + facing)
	await picture("hospital_air_combo1_" + facing)
	await attack()
	await wait_frame(2, 8)
	assert(hospital.player.sprite.animation == "air_attack2_" + facing)
	await picture("hospital_air_combo2_" + facing)
	await attack()
	await wait_frame(3, 8)
	assert(hospital.player.sprite.animation == "air_attack3_" + facing)
	await picture("hospital_air_combo3_" + facing)
	await tap(KEY_S)
	assert(hospital.player.special_kind == "dive_slash")
	await picture("hospital_dive_slash_" + facing)
	for _index in range(60):
		if hospital.player.is_on_floor():
			break
		await tick()
	assert(hospital.player.is_on_floor())
	await tick(17)
	await picture("hospital_air_chain_landed_" + facing)
	recording = ""


func record() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	CONTROLS.install(false)
	var home := HOME.instantiate()
	root.add_child(home)
	current_scene = home
	await tick(16)
	home.player.facing = "down"
	home.player.call("_show_idle")
	await tick(4)
	await picture("home_player_top_down")
	root.remove_child(home)
	home.queue_free()
	await process_frame
	hospital = HOSPITAL.instantiate()
	root.add_child(hospital)
	current_scene = hospital
	await tick(16)
	hospital.player.position = Vector2(269, 174)
	hospital.player.facing = "down"
	hospital.player.call("_show_idle")
	hospital.call("follow_player")
	await tick(6)
	await picture("hospital_player_top_down")
	hospital.call("switch_view")
	await tick(16)
	hospital.player.position = Vector2(250, 286)
	hospital.player.facing = "right"
	hospital.player.call("_show_idle")
	await tick(8)
	await picture("hospital_player_side_view")
	await air_chain(1)
	await air_chain(-1)
	var report := {"status": "passed", "window_size": [1280, 720], "logical_size": [320, 180],
		"scenes": ["res://scenes/home_601.tscn", "res://scenes/underground_hospital.tscn"],
		"combat_fixture_used": false, "npc_count": 0, "observed_animations": observed.keys(), "frames": states}
	var file := FileAccess.open(OUTPUT + "capture_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify({"status": "passed", "frames": states.size(), "observed_animations": observed.keys(), "output": OUTPUT}))
	quit(0)
