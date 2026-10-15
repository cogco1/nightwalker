extends "res://tests/support/isolated_suite.gd"
## Uses the retained combat QA fixture; no training entrance is required in play.

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
const TARGET = preload("res://tests/fixtures/training_target.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
var arena: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(2))
	call_deferred("run_tests")


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)


func tick(count := 1) -> void:
	for _index in range(count):
		await process_frame


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
	event.position = Vector2(50, 140)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func attack() -> void:
	mouse(true)
	await tick()
	mouse(false)
	await tick()


func tap(code: Key) -> void:
	key(code, true)
	await tick()
	key(code, false)
	await tick()


func reset() -> void:
	for code in [KEY_SPACE, KEY_S, KEY_W, KEY_A, KEY_D, KEY_SHIFT]:
		key(code, false)
	mouse(false)
	arena.build_arena(1)
	for target in arena.targets:
		target.queue_free()
	arena.targets.clear()
	await tick(8)
	arena.player.critical_roll_override = 0.99


func target_at(point: Vector2, health := 30) -> CharacterBody2D:
	var target := TARGET.new()
	target.side_view = true
	target.max_hp = health
	target.position = point
	arena.world.add_child(target)
	arena.targets.append(target)
	return target


func dash_input(direction: int) -> void:
	key(KEY_D if direction > 0 else KEY_A, true)
	await tap(KEY_SHIFT)
	key(KEY_D if direction > 0 else KEY_A, false)


func wait_stage(stage: int, limit := 70) -> bool:
	for _index in range(limit):
		if arena.player.combo_stage == stage:
			return true
		await tick()
	return false


func wait_dash(limit := 35) -> bool:
	for _index in range(limit):
		if arena.player.dash_executed:
			return true
		await tick()
	return false


func check_body(description: String) -> void:
	check(arena.player.scale == Vector2.ONE and arena.player.sprite.scale == Vector2.ONE, description + ": character scale stays one")
	check(arena.player.body_shape.shape.size == Vector2(12, 26) and arena.player.body_shape.position == Vector2(0, -13), description + ": standing collider and foot origin are unchanged")
	var texture: Texture2D = arena.player.sprite.sprite_frames.get_frame_texture(arena.player.sprite.animation, arena.player.sprite.frame)
	var pivot := Vector2(texture.get_width() / 2.0, texture.get_height() - 12.0)
	check(arena.player.sprite.offset == -pivot, description + ": sprite keeps its registered foot pivot")
	check((arena.player.sprite.global_position + arena.player.sprite.offset + pivot).is_equal_approx(arena.player.global_position.round()), description + ": atlas padding never moves the drawn world foot")


func resource_checks() -> bool:
	var frames := load("res://assets/side_view.tres") as SpriteFrames
	var paths: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/blade_paths.json"))["side_view"]
	var ready := true
	for direction in ["right", "left"]:
		var animation: String = "air_dash_stab_" + direction
		var exists := frames.has_animation(animation)
		check(exists, "dedicated airborne dash is registered: " + direction)
		ready = ready and exists
		if not exists:
			continue
		check(frames.get_frame_count(animation) == 16 and not frames.get_animation_loop(animation), "air dash has sixteen non-looping frames: " + direction)
		check(is_equal_approx(frames.get_animation_speed(animation), 40.0), "air dash retains the original forty-fps dash timing: " + direction)
		check(frames.get_frame_count("dash_stab_" + direction) == 16 and is_equal_approx(frames.get_animation_speed("dash_stab_" + direction), 40.0), "ground dash registration and speed remain unchanged: " + direction)
		check(paths.has(animation) and paths[animation].size() == 16, "each new airborne frame has a registered sword tip: " + direction)
		var distinct := false
		for index in range(16):
			var aerial := frames.get_frame_texture(animation, index)
			var ground := frames.get_frame_texture("dash_stab_" + direction, index)
			check(aerial != null and aerial.get_size() == Vector2(112, 96), "air dash native canvas: %s/%02d" % [direction, index])
			check(ground != null and ground.get_size() == Vector2(112, 96), "ground dash native canvas preserved: %s/%02d" % [direction, index])
			distinct = distinct or aerial.get_image().get_data() != ground.get_image().get_data()
		check(distinct, "air dash uses independent drawings rather than the standing dash: " + direction)
	return ready


func ground_checks(direction: int) -> void:
	await reset()
	arena.player.position = Vector2(60 if direction > 0 else 120, 160)
	await tick(3)
	await dash_input(direction)
	var facing := "right" if direction > 0 else "left"
	check(arena.player.sprite.animation == "dash_stab_" + facing, "ground chord still selects the original dash: " + facing)
	check(not arena.player.dash_executed and arena.player.sprite.frame < 6, "ground dash retains its anticipation: " + facing)
	check_body("ground dash " + facing)
	check(await wait_dash(), "ground dash reaches its swept movement: " + facing)
	check(arena.player.sprite.frame >= 6 and arena.player.sprite.frame <= 9, "ground dash executes inside the original active frames: " + facing)
	check(absf(arena.player.dash_end.x - arena.player.dash_start.x - direction * 48.0) < 0.1, "ground dash still travels forty-eight pixels: " + facing)
	check(await wait_stage(0), "ground dash completes once: " + facing)
	await tick(5)
	check(arena.player.sprite.animation == "idle_" + facing and arena.player.collision_mask == 3, "ground dash returns to standing idle and normal collision: " + facing)


func air_chain_checks(direction: int) -> void:
	await reset()
	await tap(KEY_SPACE)
	var start_x := 60.0 if direction > 0 else 120.0
	arena.player.position = Vector2(start_x, 90)
	arena.player.velocity.y = 80.0
	var enemy := target_at(Vector2(start_x + direction * 56, 90))
	await tick(2)
	var jumps: int = arena.player._jumps_used
	var starting_y: float = arena.player.position.y
	await dash_input(direction)
	var facing := "right" if direction > 0 else "left"
	check(arena.player.special_kind == "dash_stab" and arena.player.sprite.animation == "air_dash_stab_" + facing, "air chord selects its own dash while retaining the shared special kind: " + facing)
	check(not arena.player.dash_executed and arena.player.sprite.frame < 6, "air dash keeps the original anticipation: " + facing)
	check(arena.player.velocity.y == 6.0 and arena.player._attack_active_start() == 6, "air dash preserves slow fall and frame-six activation: " + facing)
	check_body("air dash " + facing)
	check(await wait_dash(), "air dash executes its swept movement: " + facing)
	check(arena.player.sprite.frame >= 6 and arena.player.sprite.frame <= 9, "air dash does not execute outside active frames: " + facing)
	check(absf(arena.player.dash_end.x - arena.player.dash_start.x - direction * 48.0) < 0.1, "air dash travels forty-eight pixels: " + facing)
	check(enemy.hp == 29 and enemy._air_hold_left > 0.0, "air dash damages and suspends its pierced target: " + facing)
	check(arena.player._jumps_used == jumps and arena.player.critical_rolls == 0, "air dash never replenishes jumps or consumes a critical roll: " + facing)
	check(await wait_stage(0), "air dash finishes naturally: " + facing)
	check(arena.player._air_hold_left > 0.26 and arena.player._air_hold_left <= 0.30, "dash completion preserves the point-three-second follow-up window: " + facing)
	check(arena.player.position.y - starting_y < 4.0 and not arena.player.is_on_floor(), "air dash stays near the original height: " + facing)
	await tick(3)
	check(arena.player.sprite.animation == "air_idle_" + facing and arena.player.sprite.is_playing(), "air dash returns to the independent looping airborne idle: " + facing)
	check(arena.player.sprite.offset == Vector2(-40, -68), "air idle restores its own eighty-pixel atlas pivot: " + facing)
	check_body("air idle after dash " + facing)
	await attack()
	check(arena.player.sprite.animation == "air_attack1_" + facing, "fresh click follows the dash with aerial strike one: " + facing)
	await attack()
	check(await wait_stage(2), "air dash connects into aerial strike two: " + facing)
	check(arena.player.sprite.animation == "air_attack2_" + facing, "second aerial strike retains its own animation: " + facing)
	arena.player.critical_roll_override = 0.0
	await attack()
	check(await wait_stage(3), "air dash connects into aerial strike three: " + facing)
	await tick(22)
	check(enemy.hp == 24 and arena.player.critical_rolls == 1, "piercing dash plus three hits keeps triple critical damage: " + facing)
	check(arena.completed_stop_requests.has(4) and arena.completed_stop_requests.has(6), "ordinary and critical hit stops survive the air chain: " + facing)
	await tap(KEY_S)
	check(arena.player.special_kind == "dive_slash" and arena.player.sprite.animation == "dive_slash_" + facing, "S cancels the follow-up into the separate downward strike: " + facing)
	check(arena.player._air_hold_left == 0.0 and arena.player.velocity.y == 360.0, "downward strike clears hover and retains its speed: " + facing)
	await tick(25)
	check(arena.player.is_on_floor() and arena.player._jumps_used == 0, "dash-combo-dive lands and restores ordinary jump availability: " + facing)
	key(KEY_A if direction > 0 else KEY_D, true)
	await tick(20)
	key(KEY_A if direction > 0 else KEY_D, false)
	check(arena.player.collision_mask == 3 and not arena.player._dash_phasing, "leaving the pierced target restores normal collisions: " + facing)
	observations["air_chain_" + facing] = {"jumps_during_dash": jumps, "dash_distance": direction * 48, "target_hp_after_combo": 24, "completed_stops": arena.completed_stop_requests.duplicate()}


func wall_checks(direction: int) -> void:
	await reset()
	var start_x := 60.0 if direction > 0 else 120.0
	arena.player.position = Vector2(start_x, 80)
	var wall_x := 94.0 if direction > 0 else 86.0
	arena.add_wall(Rect2(wall_x, 38, 3, 122))
	var near_target := target_at(Vector2(start_x + direction * 18, 80))
	var behind_target := target_at(Vector2(start_x + direction * 54, 80))
	await tick(2)
	await dash_input(direction)
	check(await wait_dash(), "wall fixture reaches air dash: " + str(direction))
	check(arena.player.dash_end.x <= 88.1 if direction > 0 else arena.player.dash_end.x >= 94.9, "air dash stops before the real wall: " + str(direction))
	check(near_target.hp == 29 and behind_target.hp == 30, "wall-clipped sweep hits the near target and protects the far target: " + str(direction))
	check(await wait_stage(0), "wall-clipped air dash completes: " + str(direction))
	key(KEY_A if direction > 0 else KEY_D, true)
	await tick(34)
	key(KEY_A if direction > 0 else KEY_D, false)
	await tick(3)
	check(arena.player.collision_mask == 3, "wall-clipped dash restores enemy collisions after separation: " + str(direction))


func many_target_checks() -> void:
	await reset()
	arena.player.position = Vector2(60, 90)
	var victims: Array[CharacterBody2D] = []
	for index in range(22):
		victims.append(target_at(Vector2(78 + index, 90), 6))
	var outside := target_at(Vector2(149, 90), 6)
	await tick(2)
	await dash_input(1)
	check(await wait_stage(0), "crowded airborne dash completes")
	check(victims.all(func(target: CharacterBody2D) -> bool: return target.hp == 5), "air dash still pierces all twenty-two swept targets exactly once")
	check(outside.hp == 6 and arena.hits == 22, "air dash preserves finite reach and once-per-target damage")
	check(arena.completed_stop_requests == [4], "all pierced targets share one ordinary hit stop")


func run_tests() -> void:
	CONTROLS.install(false)
	arena = MAIN.instantiate()
	root.add_child(arena)
	await reset()
	if resource_checks():
		for direction in [-1, 1]:
			await ground_checks(direction)
			await air_chain_checks(direction)
			await wall_checks(direction)
		await many_target_checks()
	var report := {"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "observations": observations}
	var file := FileAccess.open("res://evidence/air_dash_animation_v14_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
