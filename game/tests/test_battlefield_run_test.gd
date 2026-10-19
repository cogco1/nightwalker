extends "res://tests/support/isolated_suite.gd"
## Fast native-pixel and terrain integration checks. The scene's --battlefield-smoke covers the full map.

const SCENE = preload("res://scenes/battlefield_run_test.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const OUTPUT := "res://evidence/battlefield_run_test/"
var scene: Node2D
var checks := 0
var failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	create_timer(35.0).timeout.connect(func() -> void:
		check(false, "Battlefield regression finishes before its deadline")
		finish())
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func ticks(count: int) -> void:
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


func run() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	scene = SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await ticks(12)
	check(scene.ready_for_test, "The delivered panorama and ground profile load")
	if not scene.ready_for_test:
		finish()
		return
	var player: CharacterBody2D = scene.player
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/boot.tscn", "The normal chapter entry point is unchanged")
	check(player.view_mode == 1 and player.is_on_floor(), "The shipped side-view player stands on the new lowland")
	check(player.scale == Vector2.ONE and scene.background.scale == Vector2.ONE and scene.camera.zoom == Vector2.ONE,
		"Hero, panorama and camera preserve the native pixel grid")
	check(root.content_scale_size == Vector2i(320, 180) and root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER,
		"The original 320x180 integer viewport is preserved")
	check(scene.ground_source == scene.GROUND_PATH, "Collision follows the delivered surface profile")
	check(player.get_node("Sprite").sprite_frames.resource_path == "res://assets/side_view.tres", "The existing side-view animation library is reused")
	check(player.get_node("Sprite").material != null, "The existing hero material is preserved")
	for code in [KEY_F7, KEY_F8]:
		key(code, true)
		await ticks(1)
		key(code, false)
	check(current_scene == scene, "Interior debug routes leave the standalone playground in place")
	key(KEY_D, true)
	key(KEY_SHIFT, true)
	await ticks(7)
	check(not player.is_running and not player.is_dodging, "The existing short Shift hold waits for the run gesture")
	await ticks(20)
	check(player.is_running and player.velocity.x > 125.0, "Holding Shift enters the existing run at its normal speed")
	var airborne := 0
	var max_ground_error := 0.0
	for _index in range(180):
		await ticks(1)
		if not player.is_on_floor():
			airborne += 1
		max_ground_error = maxf(max_ground_error, absf(player.position.y - scene.ground_y_at(player.position.x)))
		if player.position.x >= 370.0:
			break
	check(player.position.x >= 370.0 and airborne <= 3 and max_ground_error <= 6.0, "Original collision and running climb the drawn slope onto the ridge")
	key(KEY_SHIFT, false)
	key(KEY_D, false)
	await ticks(12)
	check(not player.is_running and not player.is_dodging and absf(player.velocity.x) < 0.1, "Releasing a run stops normally without a dodge")
	key(KEY_A, true)
	key(KEY_SHIFT, true)
	for _index in range(200):
		await ticks(1)
		if player.position.x <= 70.0:
			break
	key(KEY_SHIFT, false)
	key(KEY_A, false)
	await ticks(12)
	check(player.position.x < 80.0 and player.is_on_floor() and absf(player.position.y - scene.ground_y_at(player.position.x)) <= 2.0,
		"Floor snapping lets the unchanged player run back down to the lowland")
	var grounded_y := player.position.y
	key(KEY_SPACE, true)
	await ticks(2)
	key(KEY_SPACE, false)
	await ticks(8)
	check(player.position.y < grounded_y - 12.0 and not player.is_on_floor(), "The original jump works on the continuous terrain")
	var half := Vector2(160, 90)
	check(scene.camera.position.x >= half.x and scene.camera.position.y >= half.y
		and scene.camera.position.x <= scene.world_size.x - half.x and scene.camera.position.y <= scene.world_size.y - half.y,
		"The camera stays inside the native image during a jump")
	await ticks(65)
	check(player.is_on_floor() and absf(player.position.y - grounded_y) <= 2.0, "The original jump lands on the same native surface")
	key(KEY_A, true)
	key(KEY_SHIFT, true)
	await ticks(50)
	key(KEY_SHIFT, false)
	key(KEY_A, false)
	await ticks(12)
	check(player.position.x >= scene.EDGE_MARGIN and player.is_on_floor(), "Running into the first edge stays inside the terrain")
	player.position = Vector2(scene.world_size.x - 40.0, scene.ground_y_at(scene.world_size.x - 40.0) - 1.0)
	player.velocity = Vector2.ZERO
	await ticks(6)
	check(absf(scene.camera.position.x - (scene.world_size.x - 160.0)) <= 1.0, "The camera shows the last local 320px portion of the panorama")
	key(KEY_D, true)
	key(KEY_SHIFT, true)
	await ticks(40)
	key(KEY_SHIFT, false)
	key(KEY_D, false)
	await ticks(12)
	check(player.position.x <= scene.world_size.x - scene.EDGE_MARGIN and player.is_on_floor(), "Running into the final edge stays inside the terrain")
	key(KEY_R, true)
	await ticks(1)
	key(KEY_R, false)
	await ticks(6)
	check(absf(player.position.x - scene.START_X) <= 1.0 and player.is_on_floor(), "Reset returns to the lowland without changing scenes")
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	for code in [KEY_A, KEY_D, KEY_SHIFT, KEY_SPACE, KEY_R]:
		key(code, false)
	CONTROLS.release_actions()
	var report := {"suite": "battlefield_run_test", "checks": checks, "failures": failures, "passed": failures.is_empty()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + "test_report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
