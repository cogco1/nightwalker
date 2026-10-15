extends "res://tests/support/isolated_suite.gd"

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
var arena: Node2D
var captured := 0
var sections: Array[Dictionary] = []
var section_name := ""
var section_start := 0
var states: Array[Dictionary] = []
var _output_folder := "motion_v04"

func _initialize() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		push_error("Live motion capture did not finish within 180 simulated seconds")
		quit(2)
	)
	call_deferred("record")

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func release() -> void:
	for code in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_J, KEY_CAPSLOCK, KEY_SPACE]:
		key(code, false)

func start_section(label: String) -> void:
	if not section_name.is_empty():
		sections.append({"name":section_name, "first":section_start, "last":captured - 1})
	section_name = label
	section_start = captured

func capture(physics_ticks := 2) -> void:
	for _index in range(physics_ticks):
		await physics_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := "res://evidence/%s/%04d.png" % [_output_folder,captured]
	if picture.is_empty() or picture.save_png(path) != OK:
		push_error("Could not capture rendered frame: " + path)
		quit(1)
		return
	var sprite: AnimatedSprite2D = arena.player.sprite
	var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
	states.append({"index":captured, "section":section_name, "duration_ms":roundi(physics_ticks * 1000.0 / 60.0), "viewport_width":picture.get_width(), "viewport_height":picture.get_height(), "view_mode":arena.view_mode, "animation":str(sprite.animation), "frame":sprite.frame, "frame_progress":sprite.frame_progress, "position":[arena.player.position.x,arena.player.position.y], "render_position":[sprite.global_position.x,sprite.global_position.y], "sprite_offset":[sprite.offset.x,sprite.offset.y], "texture_size":[texture.get_width(),texture.get_height()], "idle_bob_y":arena.player.idle_bob_y, "blade_effect_pixels":arena.player.fx.blade_effect_pixels().size(), "velocity":[arena.player.velocity.x,arena.player.velocity.y], "stage":arena.player.combo_stage, "queued":arena.player.queued_attack, "hits":arena.hits})
	captured += 1

func shots(count: int, physics_ticks := 2) -> void:
	for _index in range(count):
		await capture(physics_ticks)

func reset(mode: int) -> void:
	release()
	arena.build_arena(mode)
	for _index in range(6):
		await physics_frame

func combo(mode: int, direction := "right") -> void:
	await reset(mode)
	arena.player.position = Vector2(67,83) if mode == 0 else Vector2(73,160)
	if mode == 0 and direction == "up":
		arena.player.position = Vector2(90,114)
	elif mode == 0 and direction == "down":
		arena.targets[0].position = Vector2(90,143)
		arena.player.position = Vector2(90,112)
	arena.player.facing = direction
	var label := "top_down_three_hit_combo" if mode == 0 else "side_three_hit_combo"
	start_section(label if direction == "right" else label + "_" + direction)
	key(KEY_J, true)
	await capture(1)
	key(KEY_J, false)
	var buffered_second := false
	var buffered_third := false
	for _index in range(96):
		if arena.player.combo_stage == 1 and arena.player.sprite.frame >= 9 and not buffered_second:
			key(KEY_J, true)
			buffered_second = true
		elif arena.player.combo_stage == 2 and arena.player.sprite.frame >= 10 and not buffered_third:
			key(KEY_J, true)
			buffered_third = true
		else:
			key(KEY_J, false)
		await capture(1)

func record() -> void:
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute("res://evidence/" + _output_folder)
	arena = MAIN.instantiate()
	root.add_child(arena)
	await reset(0)
	start_section("top_down_breathing_idle")
	await shots(68)
	start_section("top_down_walk_run_brake_turn")
	arena.player.position = Vector2(36,151)
	key(KEY_D,true)
	await shots(18)
	key(KEY_CAPSLOCK,true)
	await shots(13)
	key(KEY_CAPSLOCK,false)
	await shots(7)
	key(KEY_D,false)
	await shots(10)
	key(KEY_A,true)
	await shots(15)
	release()
	await shots(12)
	await combo(0)
	await reset(1)
	start_section("side_breathing_idle")
	await shots(68)
	start_section("side_walk_run_turn")
	arena.player.position = Vector2(32,160)
	key(KEY_D,true)
	await shots(12)
	key(KEY_CAPSLOCK,true)
	await shots(7)
	key(KEY_CAPSLOCK,false)
	await shots(6)
	key(KEY_D,false)
	key(KEY_A,true)
	await shots(9)
	release()
	await shots(12)
	await combo(1)
	await reset(1)
	start_section("side_jump_platform")
	arena.player.position = Vector2(110,160)
	key(KEY_D,true)
	key(KEY_SPACE,true)
	await capture(1)
	key(KEY_SPACE,false)
	await shots(12)
	key(KEY_D,false)
	await shots(24)
	await reset(1)
	start_section("side_crouch_attack_stand_jump")
	arena.player.position = Vector2(73,160)
	key(KEY_S,true)
	await shots(10)
	key(KEY_J,true)
	await capture(1)
	key(KEY_J,false)
	await shots(18)
	key(KEY_S,false)
	await capture(1)
	key(KEY_SPACE,true)
	await capture(1)
	key(KEY_SPACE,false)
	await shots(35)
	release()
	sections.append({"name":section_name, "first":section_start, "last":captured - 1})
	var file := FileAccess.open("res://evidence/%s/capture_manifest.json" % _output_folder, FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info()["string"], "source":"actual Godot viewport rendering", "native_viewport":[320,180], "captured_frames":captured, "sections":sections, "states":states}, "\t"))
	file.close()
	print("PASS: captured %d actual rendered frames across %d motion sections" % [captured,sections.size()])
	quit(0)
