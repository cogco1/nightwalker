extends "res://tests/support/isolated_suite.gd"

const HOSPITAL = preload("res://scenes/underground_hospital.tscn")
const EXPECTED_CHECKS := 54
var environment: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var greatest_route_step := 0.0
var greatest_floor_error := 0.0
var greatest_drawn_foot_drop := 0.0


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("Physical hospital stair suite timed out")
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
	if is_instance_valid(environment) and is_instance_valid(environment.player):
		var grid_offset: Vector2 = environment.player.global_position.round() - environment.player.global_position
		var drawn_offset: Vector2 = environment.player.get_node("Sprite").position
		greatest_drawn_foot_drop = maxf(greatest_drawn_foot_drop, drawn_offset.y - grid_offset.y)


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func release() -> void:
	for code in [KEY_W, KEY_A, KEY_D, KEY_S, KEY_E, KEY_SPACE, KEY_SHIFT]:
		key(code, false)


func fixture(point: Vector2, room := "entry") -> void:
	release()
	environment.activate_view(1, room, point)
	await frames(10)


func enter(code: Key) -> void:
	key(code, true)
	await frames(3)
	key(code, false)
	await frames(8)


func travel_to_x(code: Key, destination: float, maximum_frames: int, flat_y := -1.0) -> bool:
	var right := code == KEY_D
	greatest_floor_error = 0.0
	key(code, true)
	for _index in range(maximum_frames):
		var before: Vector2 = environment.player.position
		await frames(1)
		greatest_route_step = maxf(greatest_route_step, before.distance_to(environment.player.position))
		if flat_y >= 0.0:
			greatest_floor_error = maxf(greatest_floor_error, absf(environment.player.position.y - flat_y))
		if (right and environment.player.position.x >= destination) or (not right and environment.player.position.x <= destination):
			key(code, false)
			return true
	key(code, false)
	return false


func pause_position() -> Vector2:
	# Exclude the existing controller's short braking movement from the stop check.
	release()
	await frames(10)
	var point: Vector2 = environment.player.position
	await frames(12)
	return point


func camera_matches() -> bool:
	var expected: Vector2 = environment.player.position.round().clamp(Vector2(160, 90), Vector2(environment.world_size) - Vector2(160, 90))
	return environment.camera.position == expected


func run() -> void:
	environment = HOSPITAL.instantiate()
	root.add_child(environment)
	current_scene = environment
	await frames(6)
	await fixture(Vector2(60, 286))
	check(environment.player.is_physics_processing() and not environment.stairs_busy, "side stairs retain the original live player controller")
	var ramp := environment.world.get_node_or_null("stair_ramp") as StaticBody2D
	check(ramp != null and ramp.get_child(0) is CollisionPolygon2D, "the straight stair has a real polygon walking surface")
	check(ramp != null and ramp.collision_layer == 0, "stairs do not intercept ordinary lower-floor walking before entry is selected")

	# A staircase beside the route must not redirect normal movement on either floor.
	check(await travel_to_x(KEY_D, 220, 250, 286.0), "D walks through the complete lower stair area into the ward")
	check(greatest_floor_error < 0.5, "lower rightward passage stays on the flat floor throughout")
	check(await travel_to_x(KEY_A, 60, 250, 286.0), "A walks back through the lower stair area")
	check(greatest_floor_error < 0.5, "lower leftward passage never starts an unintended ascent")
	await fixture(Vector2(20, 164), "reception")
	check(await travel_to_x(KEY_D, 200, 280, 164.0), "D walks across the upper stair opening without entering it")
	check(greatest_floor_error < 0.5, "ordinary upper rightward walking remains on the upper floor")
	check(await travel_to_x(KEY_A, 20, 280, 164.0), "A walks back across the upper stair opening")
	check(greatest_floor_error < 0.5, "ordinary upper leftward walking cannot fall into the stairs")
	check(environment.floor_id == 2 and environment.player.is_on_floor(), "both upper passage directions retain the actual upper floor")

	# Entry selects the physical route; it never walks or teleports the player.
	await fixture(Vector2(166, 286))
	var before_entry: Vector2 = environment.player.position
	await enter(KEY_W)
	check(environment.player.position.distance_to(before_entry) < 1.0, "W selects the lower stair entrance without moving the player")
	check(environment.world.get_node("stair_ramp").collision_layer == 1 and environment.player.is_physics_processing() and not environment.stairs_busy, "W enables the real slope while retaining full player control")
	check(await travel_to_x(KEY_A, 110, 140), "A walks from the selected lower entrance onto the stairs")
	check(environment.player.is_on_floor() and environment.player.position.y > 210.0 and environment.player.position.y < 275.0, "ascent is supported by the slope rather than the floor below")
	var lower_pause := await pause_position()
	check(environment.player.is_on_floor() and environment.player.position.distance_to(lower_pause) < 0.35, "releasing movement stops on the slope without sliding")
	check(environment.player.is_physics_processing() and not environment.stairs_busy, "stopping halfway never locks or replaces the original controller")
	check(await travel_to_x(KEY_D, 132, 90), "D reverses a partial ascent on the same stair flight")
	check(environment.player.position.y > lower_pause.y + 10.0, "reversing ascent really walks downhill")
	check(await travel_to_x(KEY_A, 20, 260), "A can reverse again and finish the whole ascent")
	await frames(10)
	check(environment.player.is_on_floor() and absf(environment.player.position.y - 164.0) < 1.0 and environment.floor_id == 2, "the physical ascent reaches the real upper floor")
	check(camera_matches(), "the camera follows the complete physical ascent")
	observations["upstairs_position"] = [environment.player.position.x, environment.player.position.y]
	check(await travel_to_x(KEY_D, 200, 280, 164.0), "the player can immediately walk forward along the upper floor after ascent")
	check(greatest_floor_error < 0.5, "leaving the upper stairs restores a continuous upper walking surface")

	# Descending and then continuing forward is the user-reported blocked route.
	await fixture(Vector2(30, 164), "reception")
	before_entry = environment.player.position
	await enter(KEY_E)
	check(environment.player.position.distance_to(before_entry) < 8.0 and environment.player.is_physics_processing() and not environment.stairs_busy, "E selects descent without a teleport or automatic traversal")
	check(await travel_to_x(KEY_D, 84, 140), "D walks down the selected straight staircase")
	check(environment.player.is_on_floor() and environment.player.position.y > 190.0 and environment.player.position.y < 260.0, "descent remains supported by the stair slope")
	var upper_pause := await pause_position()
	check(environment.player.is_on_floor() and environment.player.position.distance_to(upper_pause) < 0.35, "the player can stop freely during descent")
	check(await travel_to_x(KEY_D, 168, 190), "D finishes descending to the lower right stair foot")
	await frames(10)
	check(environment.player.is_on_floor() and absf(environment.player.position.y - 286.0) < 1.0 and environment.floor_id == 1, "the complete descent reaches the actual lower floor")
	check(await travel_to_x(KEY_D, 220, 100, 286.0), "D continues forward from the stair foot into the lower corridor")
	check(greatest_floor_error < 0.5, "forward movement after descent does not get redirected upstairs")
	check(await travel_to_x(KEY_A, 60, 250, 286.0), "A can return through the lower stair area after descending")
	check(greatest_floor_error < 0.5, "returning past the stair foot stays on the lower floor")
	observations["downstairs_position"] = [environment.player.position.x, environment.player.position.y]

	# Either entrance can be cancelled by walking back, without a reset or view switch.
	await fixture(Vector2(30, 164), "reception")
	await enter(KEY_S)
	var reached_descent: bool = await travel_to_x(KEY_D, 65, 100)
	var returned_up: bool = await travel_to_x(KEY_A, 20, 130)
	await frames(10)
	check(reached_descent and returned_up, "S enters descent and A can reverse back to the upper entrance")
	check(environment.player.is_on_floor() and absf(environment.player.position.y - 164.0) < 1.0, "cancelling descent restores upper-floor support")
	check(await travel_to_x(KEY_D, 200, 280, 164.0), "the upper opening can be crossed normally after cancelling descent")
	check(greatest_floor_error < 0.5, "cancelled descent never forces another fall into the opening")
	await fixture(Vector2(166, 286))
	await enter(KEY_W)
	check(await travel_to_x(KEY_D, 190, 80), "a selected lower entry can be cancelled by walking away from it")
	await frames(10)
	check(environment.world.get_node("stair_ramp").collision_layer == 0 and environment.player.is_on_floor(), "walking away cancels lower stair selection and restores normal passage")
	check(await travel_to_x(KEY_A, 60, 220, 286.0), "after cancelling lower entry A crosses the stairs without climbing")
	check(greatest_floor_error < 0.5, "a cancelled lower entry cannot leave a blocking ramp behind")

	# The original jump, air steering, crouch, and run must also work on the slope.
	await fixture(Vector2(166, 286))
	await enter(KEY_W)
	await travel_to_x(KEY_A, 108, 150)
	await pause_position()
	var jump_start: Vector2 = environment.player.position
	key(KEY_SPACE, true)
	await frames(2)
	key(KEY_SPACE, false)
	await frames(5)
	check(not environment.player.is_on_floor() and environment.player.position.y < jump_start.y - 8.0, "Space launches a real jump from the stair surface")
	key(KEY_D, true)
	await frames(10)
	key(KEY_D, false)
	check(environment.player.position.x > jump_start.x + 3.0, "the player can reverse direction in the air above the stairs")
	await frames(90)
	check(environment.player.is_on_floor() and environment.player.position.y <= 287.0, "a stair jump lands on real architecture without falling through")
	await fixture(Vector2(166, 286))
	await enter(KEY_W)
	await travel_to_x(KEY_A, 55, 260)
	await pause_position()
	key(KEY_SPACE, true)
	await frames(2)
	key(KEY_SPACE, false)
	await frames(12)
	check(environment.player.position.y < 164.0 and environment.world.get_node("stair_entry").collision_layer == 1 and not environment._using_stairs, "jumping above the upper landing restores its floor before falling")
	await frames(75)
	check(environment.player.is_on_floor() and absf(environment.player.position.y - 164.0) < 1.0 and environment.floor_id == 2, "an upper stair jump lands on the second floor rather than falling through it")
	await fixture(Vector2(166, 286))
	await enter(KEY_W)
	await travel_to_x(KEY_A, 110, 150)
	await pause_position()
	key(KEY_S, true)
	await frames(10)
	check(environment.player.is_crouching and environment.player.is_on_floor() and environment.player.get_node("BodyShape").shape.size.y < 26.0, "S crouches normally while supported halfway along the stairs")
	key(KEY_S, false)
	await frames(18)
	check(not environment.player.is_crouching and environment.player.is_on_floor(), "releasing S restores standing on the same physical stair")
	await fixture(Vector2(166, 286))
	await enter(KEY_W)
	var walk_origin: Vector2 = environment.player.position
	key(KEY_A, true)
	await frames(28)
	release()
	var walked: float = walk_origin.x - environment.player.position.x
	await fixture(Vector2(166, 286))
	await enter(KEY_W)
	var run_origin: Vector2 = environment.player.position
	key(KEY_SHIFT, true)
	await frames(12)
	key(KEY_A, true)
	await frames(28)
	release()
	var ran: float = run_origin.x - environment.player.position.x
	check(ran > walked * 1.5 and environment.player.is_on_floor() and environment.player.position.y < 275.0, "Shift running remains faster and supported on the same stair surface")
	observations["stair_walk_run_distance"] = [walked, ran]
	check(greatest_drawn_foot_drop <= 1.0, "stair movement never pushes the sprite feet downward by the old six-pixel correction")
	check(greatest_route_step < 6.0, "every walked route advances continuously without teleport-sized steps")
	check(environment.player.is_physics_processing() and not environment.stairs_busy and camera_matches(), "stair controls and follow camera remain live after all routes")
	observations["greatest_walked_step"] = greatest_route_step
	observations["greatest_drawn_foot_drop"] = greatest_drawn_foot_drop
	release()
	if checks != EXPECTED_CHECKS:
		failures.append("Physical stair suite count changed: expected%d, got%d" % [EXPECTED_CHECKS, checks])
	var report := {"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "observations": observations}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	var file := FileAccess.open("res://evidence/hospital_physical_stairs_v11.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
