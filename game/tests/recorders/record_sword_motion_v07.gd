extends "res://tests/support/isolated_suite.gd"

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
var arena: Node2D
var captured := 0
var section_name := ""
var section_start := 0
var sections: Array[Dictionary] = []
var states: Array[Dictionary] = []
var stop_events: Array[Dictionary] = []
const OUTPUT := "res://evidence/sword_motion_v07/"

func _initialize() -> void:
	create_timer(180.0).timeout.connect(func() -> void: quit(2))
	call_deferred("record")

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func release() -> void:
	mouse(false)
	for code in [KEY_A,KEY_D,KEY_W,KEY_S,KEY_J,KEY_SPACE,KEY_CAPSLOCK]:
		key(code,false)

func reset(mode: int) -> void:
	release()
	arena.build_arena(mode)
	for _index in range(6):
		await physics_frame
	arena.player.critical_roll_override = 0.99

func section(label: String) -> void:
	if not section_name.is_empty():
		sections.append({"name":section_name,"first":section_start,"last":captured-1})
	section_name = label
	section_start = captured

func capture() -> void:
	# Capture metadata immediately before the actual render. A stop manager can
	# resume at post_draw, so post-draw flags alone mislabel the second frozen image.
	await RenderingServer.frame_pre_draw
	var player: CharacterBody2D = arena.player
	var sprite: AnimatedSprite2D = player.sprite
	var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
	var targets: Array[Dictionary] = []
	for target in arena.targets:
		var slash_pixels: Array[Array] = []
		for point in target.slash_flash_pixels():
			var native := Vector2(point)
			slash_pixels.append([native.x,native.y])
		targets.append({"position":[target.global_position.x,target.global_position.y],"velocity":[target.velocity.x,target.velocity.y],"hp":target.hp,"knock_count":target.knock_count,"weak_knock_count":target.weak_knock_count,"slash_flash_left":target.slash_flash_left,"slash_pixels":slash_pixels})
	var air: Array[Array] = []
	for effect in player._effects:
		if effect.has("tail"):
			var point: Vector2 = effect["position"]
			var tail: Vector2 = effect["tail"]
			var a := point.round()
			var b := (point+tail).round()
			air.append([a.x,a.y,b.x,b.y,float(effect["life"])])
	var afterimages: Array[Array] = []
	for ghost in player._afterimages:
		var point: Vector2 = ghost["position"]
		var native := point.round()
		afterimages.append([native.x,native.y,float(ghost["life"])])
	var blade_tip: Vector2 = player._blade_tip_for_frame(sprite.frame)
	var blade_points: Array[Array] = []
	for point in player._blade_effect_pixels():
		blade_points.append([point.x,point.y])
	var canvas_offset: Vector2 = root.canvas_transform.origin
	var hud_offset: Vector2 = arena.hud_layer.offset
	var state := {"index":captured,"section":section_name,"engine_frame":Engine.get_process_frames(),"native_viewport":[root.get_texture().get_width(),root.get_texture().get_height()],"animation":str(sprite.animation),"frame":sprite.frame,"frame_progress":sprite.frame_progress,"position":[player.global_position.x,player.global_position.y],"velocity":[player.velocity.x,player.velocity.y],"render_position":[sprite.global_position.x,sprite.global_position.y],"sprite_offset":[sprite.offset.x,sprite.offset.y],"texture_size":[texture.get_width(),texture.get_height()],"special_kind":player.special_kind,"stage":player.combo_stage,"is_critical":player.stage_is_critical,"rolls":player.critical_rolls,"critical_impact_count":player.critical_impact_count,"hits":arena.hits,"targets":targets,"paused":paused,"stop_active":arena.hit_stop_active,"stop_requested_frames":arena.hit_stop_requested_frames,"normal_contact_events":arena.normal_contact_events,"stop_elapsed_seconds":arena.hit_stop_elapsed_seconds,"stop_min_seconds":arena.hit_stop_min_seconds,"stop_displayed_before_render":arena.hit_stop_displayed_frames,"stop_shake":[arena.hit_stop_shake.x,arena.hit_stop_shake.y],"canvas_offset":[canvas_offset.x,canvas_offset.y],"hud_offset":[hud_offset.x,hud_offset.y],"stop_overlay_visible":arena.hit_stop_overlay.visible,"airflow_count":player.airflow_count,"air_lines":air,"afterimage_positions":afterimages,"blade_pixels":player._blade_effect_pixels().size(),"drawn_blade_tip":[blade_tip.x,blade_tip.y],"blade_effect_points":blade_points,"dash_executed":player.dash_executed,"dash_start":[player.dash_start.x,player.dash_start.y],"dash_end":[player.dash_end.x,player.dash_end.y],"duration_ms":17}
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if picture.is_empty() or picture.save_png(OUTPUT+"%04d.png" % captured) != OK:
		push_error("Actual special gameplay capture failed")
		quit(1)
		return
	states.append(state)
	captured += 1

func shots(count: int) -> void:
	for _index in range(count):
		await capture()

func rising() -> void:
	await reset(1)
	arena.player.position = Vector2(73,160)
	for _index in range(3):
		await physics_frame
	section("side_rising_slash")
	await shots(4)
	key(KEY_W,true)
	mouse(true)
	await capture()
	mouse(false)
	await shots(40)
	key(KEY_W,false)
	await shots(65)

func dash() -> void:
	await reset(1)
	arena.player.position = Vector2(86,160)
	for _index in range(3):
		await physics_frame
	section("side_dash_stab")
	await shots(4)
	key(KEY_D,true)
	await capture()
	key(KEY_D,false)
	await shots(3)
	key(KEY_D,true)
	mouse(true)
	await capture()
	key(KEY_D,false)
	mouse(false)
	await shots(91)

func critical(mode: int) -> void:
	await reset(mode)
	arena.player.position = Vector2(90,112) if mode == 0 else Vector2(73,160)
	if mode == 0:
		arena.targets[0].position = Vector2(90,143)
		arena.player.facing = "down"
	else:
		arena.player.facing = "right"
	arena.targets[0].max_hp = 9
	arena.targets[0].hp = 9
	arena.player.critical_roll_override = 0.0
	for _index in range(3):
		await physics_frame
	section("critical_top_y_stop" if mode == 0 else "critical_side_x_stop")
	await shots(4)
	key(KEY_J,true)
	await capture()
	key(KEY_J,false)
	var second := false
	var third := false
	for _index in range(105):
		if arena.player.combo_stage == 1 and arena.player.sprite.frame >= 9 and not second:
			key(KEY_J,true)
			second = true
		elif arena.player.combo_stage == 2 and arena.player.sprite.frame >= 9 and not third:
			key(KEY_J,true)
			third = true
		else:
			key(KEY_J,false)
		await capture()

func isolate_ground_target() -> void:
	arena.player.position = Vector2(73,160)
	arena.player.facing = "right"
	arena.targets[0].max_hp = 12
	arena.targets[0].hp = 12
	for index in range(3,arena.targets.size()):
		arena.targets[index].position = Vector2(285+index,160)
	for _index in range(3):
		await physics_frame

func ordinary_combo() -> void:
	await reset(1)
	await isolate_ground_target()
	section("side_longblade_combo")
	await shots(4)
	key(KEY_J,true)
	await capture()
	key(KEY_J,false)
	var second := false
	var third := false
	for _index in range(105):
		if arena.player.combo_stage == 1 and arena.player.sprite.frame >= 9 and not second:
			key(KEY_J,true)
			second = true
		elif arena.player.combo_stage == 2 and arena.player.sprite.frame >= 9 and not third:
			key(KEY_J,true)
			third = true
		else:
			key(KEY_J,false)
		await capture()

func crouch() -> void:
	await reset(1)
	await isolate_ground_target()
	section("side_longblade_crouch")
	key(KEY_S,true)
	await shots(10)
	key(KEY_J,true)
	await capture()
	key(KEY_J,false)
	await shots(49)
	key(KEY_S,false)
	await shots(10)

func record() -> void:
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	arena = MAIN.instantiate()
	root.add_child(arena)
	arena.hit_stop_started.connect(func() -> void: stop_events.append({"event":"started","section":section_name,"requested_frames":arena.hit_stop_requested_frames,"engine_frame":Engine.get_process_frames()}))
	arena.hit_stop_frame.connect(func(frame: int, shake: Vector2i) -> void: stop_events.append({"event":"frame","section":section_name,"frame":frame,"shake":[shake.x,shake.y],"engine_frame":Engine.get_process_frames()}))
	arena.hit_stop_finished.connect(func(frames: int) -> void: stop_events.append({"event":"finished","section":section_name,"frames":frames,"elapsed_seconds":arena.hit_stop_elapsed_seconds,"min_seconds":arena.hit_stop_min_seconds,"engine_frame":Engine.get_process_frames()}))
	await ordinary_combo()
	await crouch()
	await rising()
	await dash()
	await critical(1)
	release()
	sections.append({"name":section_name,"first":section_start,"last":captured-1})
	var file := FileAccess.open(OUTPUT+"capture_manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info()["string"],"source":"Actual Godot GPU viewport, one record per pre/post-render pair","captured_frames":captured,"sections":sections,"states":states,"hit_stop_events":stop_events},"\t"))
	file.close()
	print("PASS: captured%d sword/contact nativeGPU frames" % captured)
	quit(0)
