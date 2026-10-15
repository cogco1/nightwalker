extends "res://tests/support/isolated_suite.gd"

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
const TARGET = preload("res://tests/fixtures/training_target.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
var arena: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var impacts: Array[Vector2] = []


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(2))
	call_deferred("run_tests")


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)


func tick(count: int = 1) -> void:
	for _index in range(count):
		await process_frame


func key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(code: Key) -> void:
	key(code, true)
	await tick(1)
	key(code, false)
	await tick(1)


func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(50, 140)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func attack() -> void:
	mouse(true)
	await tick(1)
	mouse(false)
	await tick(1)


func reset(mode: int = 1) -> void:
	for code in [KEY_SPACE, KEY_S, KEY_W, KEY_A, KEY_D, KEY_J, KEY_SHIFT]:
		key(code, false)
	mouse(false)
	arena.build_arena(mode)
	for target in arena.targets:
		target.queue_free()
	arena.targets.clear()
	await tick(8)
	arena.player.critical_roll_override = 0.99
	arena.player.landing_impact.connect(func(point: Vector2) -> void: impacts.append(point))


func target_at(position: Vector2) -> CharacterBody2D:
	var target := TARGET.new()
	target.side_view = true
	target.max_hp = 30
	target.position = position
	arena.world.add_child(target)
	arena.targets.append(target)
	return target


func screenshot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	var saved_pause := paused
	paused = true
	for _index in range(3):
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.resize(1280, 720, Image.INTERPOLATE_NEAREST)
	image.save_png("res://evidence/air_" + name + ".png")
	paused = saved_pause


func run_tests() -> void:
	CONTROLS.install(false)
	arena = MAIN.instantiate()
	root.add_child(arena)
	arena.build_arena(1)
	check(arena.targets[0].hp >= 6, "default side-view targets survive a launcher and full critical air combo")
	await reset()
	await tap(KEY_J)
	check(not arena.player.is_attacking and InputMap.action_get_events("attack").size() == 1, "J is removed and attack is mouse-only")
	check(not CONTROLS.SLOTS.has("attack_keyboard"), "keyboard attack binding is removed from settings")
	key(KEY_SPACE, true)
	await tick(8)
	check(arena.player._jumps_used == 1 and arena.player.velocity.y < 0.0, "first Space jumps once")
	key(KEY_SPACE, true, true)
	await tick(2)
	check(arena.player._jumps_used == 1, "holding Space and key repeat cannot double jump")
	key(KEY_SPACE, false)
	await tick(1)
	await tap(KEY_SPACE)
	check(arena.player._jumps_used == 2 and arena.player.velocity.y < -190.0, "second fresh Space performs one real midair jump")
	await screenshot("double_jump")
	var velocity_before: float = arena.player.velocity.y
	await tap(KEY_SPACE)
	check(arena.player._jumps_used == 2 and arena.player.velocity.y > velocity_before, "third Space cannot reset vertical velocity")
	await tick(100)
	check(arena.player.is_on_floor() and arena.player._jumps_used == 0, "landing replenishes both jumps")
	await reset()
	await tap(KEY_SPACE)
	await tap(KEY_SPACE)
	check(arena.player._jumps_used == 2, "quick double Space also performs the double jump")
	await reset()
	arena.player.position = Vector2(50, 100)
	arena.player.velocity.y = 30.0
	await tick(2)
	var start_y: float = arena.player.position.y
	await attack()
	check(arena.player.sprite.animation == "air_attack1_right", "first aerial strike uses its own tucked-leg animation")
	await tick(15)
	check(arena.player.velocity.y <= 6.01 and arena.player.position.y - start_y < 3.0, "air attack arrests falling and limits descent to six native pixels per second")
	var hold_before: float = arena.player._air_hold_left
	await attack()
	await tick(15)
	check(arena.player.combo_stage == 2 and arena.player._air_hold_left > hold_before, "next fresh combo strike renews air suspension")
	check(arena.player.sprite.animation == "air_attack2_right", "second aerial strike uses a separate upward sweep")
	await screenshot("air_combo")
	await tick(21)
	check(arena.player.sprite.animation == "air_idle_right" and arena.player.sprite.is_playing(), "completed aerial attack returns to the looping airborne pose while suspended")
	await tick(120)
	check(arena.player.is_on_floor(), "stopping attacks eventually restores normal gravity")
	await reset()
	arena.player.position = Vector2(70, 160)
	var enemy := target_at(Vector2(95, 160))
	await tick(3)
	key(KEY_W, true)
	await attack()
	key(KEY_W, false)
	await tick(27)
	check(enemy.knock_count == 1 and enemy.last_knock_velocity.y == -300.0 and enemy.position.y < 105.0, "rising slash launches the enemy substantially higher")
	observations["launcher_enemy_y"] = enemy.position.y
	observations["launcher_player_y"] = arena.player.position.y
	await screenshot("launcher")
	await attack()
	await tick(15)
	check(enemy.hp == 28 and enemy._air_hold_left > 0.0, "launcher connects into a real airborne hit and suspends the target")
	await attack()
	await tick(28)
	check(enemy.hp == 27 and not arena.player.is_on_floor(), "air combo follow-up hits the launched enemy again")
	arena.player.critical_roll_override = 0.0
	await attack()
	await tick(28)
	check(arena.player.sprite.animation == "air_attack3_right", "third aerial strike uses its own airborne finisher")
	check(enemy.hp == 24 and arena.player.critical_rolls == 1 and not arena.player.is_on_floor(), "third aerial strike delivers the existing triple critical damage while suspended")
	check(arena.completed_stop_requests.has(6), "aerial critical retains the six-frame whole-screen hit stop")
	observations["air_combo_enemy_hp"] = enemy.hp
	await reset()
	arena.player.position = Vector2(90, 100)
	var below := target_at(Vector2(90, 160))
	await tick(3)
	await attack()
	var dive_directions: Array[Vector2] = []
	arena.player.special_started.connect(func(_kind: String, direction: Vector2) -> void: dive_directions.append(direction))
	key(KEY_S, true)
	check(arena.player.special_kind == "dive_slash" and arena.player.attack_direction == Vector2.DOWN and arena.player._air_hold_left == 0.0, "S cancels the air combo into a downward attack")
	check(arena.player.sprite.animation == "dive_slash_right", "S starts an actual dedicated downward sword animation")
	check(dive_directions == [Vector2.DOWN], "downward attack reports its real downward direction to the arena")
	await screenshot("dive_slash")
	await tick(20)
	key(KEY_S, false)
	check(arena.player.is_on_floor() and absf(arena.player.position.y - 160.0) < 0.2, "downward attack reaches the real floor quickly through enemies")
	check(below.hp == 29, "downward attack deals damage once to a target below")
	check(arena.player._recovery_left <= 2.0 / 60.0 and arena.player._landing_left <= 2.0 / 60.0, "landing recovery is limited to two frames")
	await tick(3)
	await tap(KEY_SPACE)
	check(arena.player.velocity.y < -190.0 and arena.player._jumps_used == 1, "jump responds immediately after landing")
	await tick(10)
	check(arena.player.collision_mask == 3 and not arena.player._dash_phasing, "downward attack restores normal collision once clear of the enemy")
	await reset()
	arena.player.position = Vector2(140, 80)
	await tick(2)
	await tap(KEY_S)
	await tick(15)
	check(arena.player.is_on_floor() and absf(arena.player.position.y - 122.0) < 0.2, "downward attack respects elevated platform collision")
	await reset()
	key(KEY_S, true)
	await tick(4)
	check(arena.player.is_crouching and arena.player.special_kind.is_empty(), "ground S remains crouch rather than downward attack")
	await impact_checks()
	await air_dash_checks()
	asset_checks()
	await reset(0)
	await tap(KEY_SPACE)
	await tap(KEY_S)
	await tap(KEY_J)
	check(arena.player.special_kind.is_empty() and not arena.player.is_attacking and arena.player.velocity.y >= 0.0, "top-down movement is unaffected by side-view air actions")
	observations["air_fall_speed"] = 6.0
	observations["landing_seconds"] = 2.0 / 60.0
	var result := {"checks": checks, "failures": failures, "observations": observations, "status": "passed" if failures.is_empty() else "failed"}
	var file := FileAccess.open("res://evidence/air_combat_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)


func impact_checks() -> void:
	for direction in ["right", "left"]:
		await reset()
		arena.player.position = Vector2(60, 20)
		arena.player.facing = direction
		await tick(1)
		var impact_count := impacts.size()
		await tap(KEY_S)
		await tick(14)
		check(arena.player.special_kind == "dive_slash" and arena.player.sprite.animation == "dive_slash_" + direction, "dedicated plunge plays throughout airborne descent: " + direction)
		await screenshot("downward_" + direction)
		for _index in range(30):
			if arena.player.is_on_floor():
				break
			await tick(1)
		check(impacts.size() == impact_count + 1 and impacts[-1].is_equal_approx(arena.player.global_position), "landing impact emits once at the actual ground position: " + direction)
		check(arena.player.sprite.animation == "dive_slash_" + direction and arena.player.sprite.frame == 14, "landing displays the dedicated impact pose: " + direction)
		check(arena.player._effects.size() >= 12 and arena.player._effects.filter(func(effect: Dictionary) -> bool: return effect.has("tail")).size() == 2, "landing creates dust, sparks and two spreading pixel waves: " + direction)
		check(not paused and arena.completed_stop_requests.is_empty(), "empty-floor impact does not add a combat pause: " + direction)
		await screenshot("impact_" + direction)
		await tick(2)
		await screenshot("impact_spread_" + direction)
		await tap(KEY_SPACE)
		check(arena.player.velocity.y < -190.0 and arena.player._jumps_used == 1, "impact leaves immediate re-jump available after two frames: " + direction)
		await tick(15)
		check(impacts.size() == impact_count + 1 and arena.player._effects.filter(func(effect: Dictionary) -> bool: return effect.has("tail")).is_empty(), "impact waves expire and never repeat while airborne: " + direction)
	await reset()
	await tap(KEY_SPACE)
	key(KEY_D, true)
	await tap(KEY_SHIFT)
	check(arena.player.special_kind == "dash_stab", "a Shift press with a held direction also starts a piercing dash in the air")
	key(KEY_D, false)


func wait_for_stage(stage: int, limit: int = 60) -> bool:
	for _index in range(limit):
		if arena.player.combo_stage == stage:
			return true
		await tick(1)
	return false


func dash_input(direction: int) -> void:
	key(KEY_D if direction > 0 else KEY_A, true)
	await tap(KEY_SHIFT)
	key(KEY_D if direction > 0 else KEY_A, false)


func air_dash_checks() -> void:
	var cases: Array[Dictionary] = []
	for direction in [-1, 1]:
		await reset()
		await tap(KEY_SPACE)
		var start_x := 60.0 if direction > 0 else 110.0
		arena.player.position = Vector2(start_x, 90)
		arena.player.velocity.y = 80.0
		var enemy := target_at(Vector2(start_x + direction * 56, 90))
		await tick(2)
		var jumps: int = arena.player._jumps_used
		var start_y: float = arena.player.position.y
		await dash_input(direction)
		check(arena.player.special_kind == "dash_stab" and arena.player.attack_direction.x == direction, "air dash locks the requested horizontal direction: " + str(direction))
		check(arena.player.velocity.y == 6.0, "air dash arrests falling at the existing slow descent speed: " + str(direction))
		await tick(12)
		check(arena.player.dash_executed and absf(arena.player.dash_end.x - arena.player.dash_start.x - direction * 48.0) < 0.1, "air dash performs the same real 48px sweep: " + str(direction))
		check(enemy.hp == 29 and enemy._air_hold_left > 0.0 and enemy.last_knock_velocity == Vector2(0, 6), "pierced airborne enemy takes one hit and remains available for an air combo: " + str(direction))
		check(arena.player._jumps_used == jumps and arena.player.critical_rolls == 0, "air dash neither refills jumps nor rolls a critical: " + str(direction))
		await screenshot("dash_" + str(direction))
		check(await wait_for_stage(0), "air dash completes its special animation: " + str(direction))
		check(arena.player._air_hold_left > 0.26 and arena.player._air_hold_left <= 0.30, "dash completion opens a fresh 0.30-second suspension window: " + str(direction))
		check(not arena.player.is_on_floor() and arena.player.position.y - start_y < 4.0, "air dash stays near its starting height throughout the attack: " + str(direction))
		await tick(3)
		check(arena.player.sprite.animation == "air_idle_" + ("right" if direction > 0 else "left"), "dash returns to the dedicated airborne idle: " + str(direction))
		await attack()
		check(arena.player.sprite.animation == "air_attack1_" + ("right" if direction > 0 else "left"), "fresh click after dash starts aerial combo stage one: " + str(direction))
		await attack()
		check(await wait_for_stage(2), "air dash can flow into aerial combo stage two: " + str(direction))
		arena.player.critical_roll_override = 0.0
		await attack()
		check(await wait_for_stage(3), "air dash can flow into aerial combo stage three: " + str(direction))
		await tick(22)
		check(enemy.hp == 24 and arena.player.critical_rolls == 1 and not arena.player.is_on_floor(), "pierce plus full airborne combo connects with the original triple critical: " + str(direction))
		await screenshot("dash_combo_" + str(direction))
		await tap(KEY_S)
		check(arena.player.special_kind == "dive_slash" and arena.player._air_hold_left == 0.0 and arena.player.velocity.y == 360.0, "S cancels the follow-up combo into fast downward attack: " + str(direction))
		await tick(25)
		check(arena.player.is_on_floor() and arena.player._jumps_used == 0, "dash-combo-dive reaches the floor and restores ordinary jump count: " + str(direction))
		key(KEY_A if direction > 0 else KEY_D, true)
		await tick(20)
		key(KEY_A if direction > 0 else KEY_D, false)
		check(arena.player.collision_mask == 3, "leaving the pierced enemy restores normal collision after the air chain: " + str(direction))
		cases.append({"direction": direction, "enemy_hp_after_combo": 24, "dash_distance": direction * 48})
	await reset()
	arena.player.position = Vector2(60, 90)
	await tick(2)
	key(KEY_W, true)
	await dash_input(1)
	check(arena.player.special_kind == "dash_stab", "held W cannot suppress a valid airborne Shift directional dash")
	key(KEY_W, false)
	check(await wait_for_stage(0), "empty-air dash finishes normally")
	var hold_y: float = arena.player.position.y
	await tick(12)
	check(arena.player._air_hold_left > 0.0 and arena.player.position.y - hold_y < 2.0, "post-dash suspension remains slow through its short follow-up window")
	await tick(24)
	check(arena.player._air_hold_left <= 0.0 and arena.player.velocity.y > 35.0, "normal gravity resumes when no follow-up attack is entered")
	await reset()
	arena.player.position = Vector2(60, 80)
	await tick(2)
	await dash_input(1)
	check(await wait_for_stage(0), "direct dive fixture completes the airborne dash")
	await tap(KEY_S)
	check(arena.player.special_kind == "dive_slash" and arena.player._air_hold_left == 0.0, "S can directly cancel post-dash suspension without first attacking")
	await reset()
	arena.player.position = Vector2(60, 80)
	arena.add_wall(Rect2(94, 38, 3, 122))
	await tick(2)
	await dash_input(1)
	await tick(12)
	check(arena.player.dash_end.x <= 88.1 and arena.player.dash_end.x > arena.player.dash_start.x, "air dash stops before a real wall instead of teleporting through it")
	check(await wait_for_stage(0), "wall-clipped air dash finishes normally")
	await tick(3)
	check(arena.player.collision_mask == 3 and arena.player._air_hold_left > 0.0, "wall-clipped dash still gives suspension and restores collision")
	await reset()
	await tap(KEY_SPACE)
	key(KEY_SHIFT, true)
	key(KEY_D, true)
	mouse(true)
	await tick(2)
	key(KEY_SHIFT, false)
	key(KEY_D, false)
	check(await wait_for_stage(0), "held-button air dash completes once")
	await tick(5)
	check(not arena.player.is_attacking and arena.hits == 0, "holding the mouse never repeats dash or auto-starts a combo")
	mouse(false)
	await reset()
	await tap(KEY_SPACE)
	key(KEY_D, true)
	await attack()
	check(arena.player.special_kind.is_empty() and arena.player.sprite.animation == "air_attack1_right", "directional click without Shift retains the ordinary airborne combo")
	observations["air_dash_cases"] = cases
	observations["air_dash_post_hold_seconds"] = 0.30


func asset_checks() -> void:
	var frames := load("res://assets/side_view.tres") as SpriteFrames
	var registration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art_metadata/master_registration.json"))
	var palette: Array[Color] = []
	for value in registration["palette"]:
		palette.append(Color(String(value)))
	var paths: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/blade_paths.json"))["side_view"]
	for action in ["air_idle", "air_attack1", "air_attack2", "air_attack3", "dive_slash"]:
		var native_pixels := true
		var correct_mirror := true
		var distinct_frames := false
		var first := frames.get_frame_texture(action + "_right", 0).get_image().get_data()
		for frame in range(16):
			var right := frames.get_frame_texture(action + "_right", frame).get_image()
			var left := frames.get_frame_texture(action + "_left", frame).get_image()
			distinct_frames = distinct_frames or right.get_data() != first
			for y in range(80):
				for x in range(80):
					var color := right.get_pixel(x, y)
					native_pixels = native_pixels and (color.a == 0.0 or color.a == 1.0 and color in palette)
					if x > 0:
						var mirrored := left.get_pixel(x, y)
						correct_mirror = correct_mirror and (mirrored.a == 0.0 and right.get_pixel(80 - x, y).a == 0.0 or mirrored == right.get_pixel(80 - x, y))
		check(native_pixels, "native action uses only the original eighteen opaque palette colors: " + action)
		check(correct_mirror, "left/right action shares the identical fixed foot pivot: " + action)
		check(distinct_frames, "action contains drawn frame changes: " + action)
		check(paths[action + "_right"].size() == 16, "drawn sword-tip trajectory exists for all action frames: " + action)
	for direction in ["right", "left"]:
		var downward := true
		for frame in range(6, 13):
			var point: Array = paths["dive_slash_" + direction][frame]
			downward = downward and absf(point[0]) < 8 and point[1] > -10
		check(downward, "real steel tip points down below tucked boots during plunge: " + direction)
		check(frames.get_animation_loop("air_idle_" + direction), "airborne idle loops independently of standing idle: " + direction)
	observations["new_action_frames"] = 160
	observations["impact_events"] = impacts.size()
