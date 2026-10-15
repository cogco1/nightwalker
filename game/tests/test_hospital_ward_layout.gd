extends "res://tests/support/isolated_suite.gd"

const HOSPITAL = preload("res://scenes/underground_hospital.tscn")
const EXPECTED_CHECKS := 22
var environment: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var greatest_walked_step := 0.0


func _initialize() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		push_error("Hospital ward layout suite timed out")
		quit(2)
	)
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)


func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func release() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_ESCAPE, KEY_CAPSLOCK]:
		key(code, false)


func fixture(point: Vector2) -> void:
	release()
	if environment.interactions.dialogue_active:
		environment.interactions.close_dialogue()
	environment.player.position = point
	environment.player.velocity = Vector2.ZERO
	await frames(6)


func travel(code: Key, destination: float, maximum_frames: int) -> bool:
	var horizontal := code == KEY_A or code == KEY_D
	var positive := code == KEY_D or code == KEY_S
	var reached := false
	key(code, true)
	for _index in range(maximum_frames):
		var before: Vector2 = environment.player.position
		await frames(1)
		greatest_walked_step = maxf(greatest_walked_step, before.distance_to(environment.player.position))
		var coordinate: float = environment.player.position.x if horizontal else environment.player.position.y
		if (positive and coordinate >= destination) or (not positive and coordinate <= destination):
			reached = true
			break
	key(code, false)
	await frames(6)
	return reached


func push_for(code: Key, count: int) -> void:
	key(code, true)
	await frames(count)
	key(code, false)
	await frames(6)


func run() -> void:
	environment = HOSPITAL.instantiate()
	root.add_child(environment)
	current_scene = environment
	await frames(6)
	check(environment.view_mode == 0 and environment.floor_id == 1, "ward regression starts on the first-floor top-down map")
	await fixture(Vector2(372, 65))
	check(environment.position_is_clear(environment.player.position, 0), "eastward ward entrance has a clear corridor approach")
	check(await travel(KEY_S, 174, 170), "S continuously enters through the east-side doorway and reaches the bed-foot aisle")
	check(absf(environment.player.position.x - 372.0) < 0.5, "entrance traversal needs no sideways correction around a bed")
	check(environment.shared_room_id == "ward", "the east entrance actually reaches the ward room")
	var stopped: Vector2 = environment.player.position
	await frames(10)
	check(environment.player.position.distance_to(stopped) < 0.35, "releasing movement stops on the ward floor")
	observations["entered_ward"] = [stopped.x, stopped.y]
	check(await travel(KEY_A, 166, 270), "A walks continuously across the clear aisle below all three beds")
	check(environment.player.position.y >= 166.0 and environment.player.position.y < 185.0, "the bed-foot route remains inside the visible floor aisle")
	check(await travel(KEY_D, 372, 270), "D retraces the complete bed-foot aisle to the east entrance")
	check(await travel(KEY_W, 65, 170), "W returns through the same doorway to the corridor without a bed blocking it")
	check(environment.player.position.y < 75.0 and absf(environment.player.position.x - 372.0) < 3.0, "the complete return route ends back on the corridor floor")
	observations["returned_to_corridor"] = [environment.player.position.x, environment.player.position.y]
	var expected_camera: Vector2 = environment.player.position.round().clamp(Vector2(160, 90), Vector2(environment.world_size) - Vector2(160, 90))
	check(environment.camera.position == expected_camera, "the camera follows the real ward route on the native pixel grid")
	check(greatest_walked_step < 3.0, "the ward route uses continuous ordinary walking without a position jump")
	observations["greatest_walked_step"] = greatest_walked_step

	# The former centred doorway is now wall behind the middle bed.
	await fixture(Vector2(269, 65))
	await push_for(KEY_S, 65)
	check(environment.player.position.y >= 80.0 and environment.player.position.y <= 83.0, "S meets the solid north wall at the former centred doorway")
	check(absf(environment.player.position.x - 269.0) < 0.5 and environment.player.position.y < 90.0, "the closed doorway cannot put the player behind or inside the middle bed")
	observations["closed_old_door_stop"] = [environment.player.position.x, environment.player.position.y]

	# Bed collision must match the moved art rather than the old southern beds.
	await fixture(Vector2(268, 170))
	await push_for(KEY_W, 65)
	check(environment.player.position.y >= 156.5 and environment.player.position.y <= 159.0, "walking north from the aisle meets the middle bed at its relocated foot")
	check(environment.position_is_clear(environment.player.position, 0), "the stopped player's foot collider stays outside the middle bed")
	observations["middle_bed_foot_stop"] = [environment.player.position.x, environment.player.position.y]

	await fixture(Vector2(269, 164))
	check(environment.position_is_clear(environment.player.position, 0), "the relocated bed inspection position stands on reachable floor")
	await frames(5)
	check(environment.interactions.nearest_id == "ward_bed", "the empty-bed prompt belongs to the middle bed's reachable foot")
	key(KEY_E, true)
	await frames(2)
	key(KEY_E, false)
	check(environment.interactions.dialogue_active and environment.interactions.current_interaction == "ward_bed", "physical E opens the empty-bed story interaction from the new layout")
	key(KEY_ESCAPE, true)
	await frames(2)
	key(KEY_ESCAPE, false)
	await frames(4)
	check(not environment.interactions.dialogue_active and environment.player.is_physics_processing(), "Escape restores free movement after inspecting the relocated bed")
	check(checks == EXPECTED_CHECKS - 1, "the ward regression executes its complete fixed set of checks")
	release()
	var report := {"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "observations": observations}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	var file := FileAccess.open("res://evidence/hospital_ward_layout_v11_2.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
