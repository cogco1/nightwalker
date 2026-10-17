extends "res://tests/support/isolated_suite.gd"
## Real keyboard/mouse edges exercise tap, hold, attack priority, crouch locomotion, menus and custom keys.
const LAB = preload("res://tests/fixtures/combat_lab.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const GESTURE = preload("res://scripts/player/shift_gesture.gd")
var arena: Node2D
var checks := 0
var failures: Array[String] = []
var dodge_count := 0
var attacks := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)


func tick(count := 1) -> void:
	for _i in range(count):
		await physics_frame
	await process_frame


func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func mouse(pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = Vector2(160, 100)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func fixture(mode := 1, profile: Dictionary = {}) -> void:
	paused = false
	for code in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SHIFT, KEY_CTRL, KEY_SPACE, KEY_F1, KEY_LEFT, KEY_RIGHT]:
		key(code, false)
	mouse(false)
	mouse(false, MOUSE_BUTTON_MIDDLE)
	CONTROLS.release_actions()
	if is_instance_valid(arena):
		arena.queue_free()
		await tick(2)
	CONTROLS.current = CONTROLS.defaults() if profile.is_empty() else profile.duplicate()
	CONTROLS.install(false)
	arena = LAB.instantiate()
	root.add_child(arena)
	arena.build_arena(mode)
	await tick(6)
	for target in arena.targets:
		target.position.x = 290
	arena.player.position = Vector2(90, 160) if mode == 1 else Vector2(90, 85)
	await tick(2)
	attacks = 0
	dodge_count = 0
	arena.player.attack_started.connect(func() -> void: attacks += 1)
	arena.player.special_started.connect(func(kind: String, _direction: Vector2) -> void:
		if kind == "dodge": dodge_count += 1
	)


func tap_shift() -> void:
	key(KEY_SHIFT, true)
	await tick(2)
	key(KEY_SHIFT, false)
	await tick(1)


func wait_evade() -> void:
	for _i in range(30):
		if not arena.player.is_dodging: return
		await tick(1)


func run() -> void:
	var gesture = GESTURE.new()
	gesture.press(1.0)
	check(gesture.release(1.17), "release before 0.18 seconds is a tap")
	gesture.press(2.0)
	check(gesture.running(2.19) and not gesture.release(2.19), "a hold runs and cannot become an evade on release")
	gesture.press(3.0)
	gesture.consume()
	check(not gesture.release(3.05), "an attack consumes a short modifier gesture")
	check(CONTROLS.defaults()["run"] == KEY_SHIFT and CONTROLS.defaults()["dash_modifier"] == KEY_SHIFT and CONTROLS.validate(CONTROLS.defaults()).is_empty(), "Shift intentionally shares run and dodge bindings")
	var config := ConfigFile.new()
	config.set_value("bindings", "version", 3)
	var old := CONTROLS.defaults()
	old["run"] = KEY_CAPSLOCK
	for slot in CONTROLS.SLOTS:
		config.set_value("bindings", slot, old[slot])
	CONTROLS.settings_path = "user://shift_migration_test.cfg"
	config.save(CONTROLS.settings_path)
	CONTROLS.current.clear()
	CONTROLS.install()
	check(CONTROLS.current["run"] == KEY_SHIFT and CONTROLS.current["dash_modifier"] == KEY_SHIFT, "version 3 default Caps/Shift profile migrates to tap/hold Shift")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONTROLS.settings_path))
	CONTROLS.settings_path = "user://shift_regression_test.cfg"
	await fixture()
	key(KEY_D, true)
	key(KEY_SHIFT, true)
	await tick(7)
	check(not arena.player.is_running and not arena.player.is_dodging and attacks == 0, "the initial short hold neither dodges nor attacks")
	await tick(15)
	check(arena.player.is_running and arena.player.velocity.x > 130.0, "a continued Shift hold accelerates to running speed")
	key(KEY_SHIFT, false)
	await tick(8)
	check(not arena.player.is_running and dodge_count == 0 and absf(arena.player.velocity.x - 60.0) < 0.1, "release after a run returns to walking without an evade")
	await fixture()
	var target: CharacterBody2D = arena.targets[0]
	target.position = Vector2(106, 160)
	var health: int = target.hp
	var start: Vector2 = arena.player.position
	await tap_shift()
	check(arena.player.is_dodging and not arena.player.is_attacking and attacks == 0, "a quick released Shift starts a separate non-attacking evade")
	await wait_evade()
	check(dodge_count == 1 and target.hp == health and arena.player.position.x - start.x > 32.0, "an evade travels through a target without causing weapon damage")
	check(absf(arena.player.position.x - start.x - arena.player.DODGE_DISTANCE) < 0.2, "unblocked evade displacement is the configured distance")
	await fixture()
	arena.player.facing = "left"
	var from_x: float = arena.player.position.x
	await tap_shift()
	await wait_evade()
	check(arena.player.position.x < from_x - 32.0, "stationary tap uses the current facing")
	await fixture()
	arena.add_wall(Rect2(110, 120, 10, 40))
	await tick(2)
	await tap_shift()
	await wait_evade()
	check(arena.player.position.x <= 104.1, "evade respects walls instead of teleporting through them")
	for facing in [-1, 1]:
		await fixture()
		key(KEY_A if facing < 0 else KEY_D, true)
		key(KEY_SHIFT, true)
		mouse(true)
		await tick(1)
		check(arena.player.special_kind == "dash_stab" and arena.player.attack_direction.x == facing, "fresh Shift + direction + left click prioritizes directional thrust " + str(facing))
		key(KEY_SHIFT, false)
		mouse(false)
		await tick(35)
		check(dodge_count == 0 and not arena.player._intents.has(&"dodge"), "thrust consumes release so it never adds a second evade " + str(facing))
	await fixture()
	key(KEY_SHIFT, true)
	mouse(true)
	await tick(1)
	mouse(false)
	await tick(2)
	check(arena.player.move_id == &"attack1", "Shift plus released click without A/D remains a normal light attack")
	mouse(false)
	key(KEY_SHIFT, false)
	await tick(24)
	check(dodge_count == 0, "a non-directional modified attack also consumes the tap")
	await fixture()
	key(KEY_SHIFT, true)
	key(KEY_A, true)
	key(KEY_D, true)
	mouse(true)
	await tick(1)
	check(arena.player.special_kind != "dash_stab", "opposed A/D do not choose an arbitrary thrust direction")
	await fixture()
	key(KEY_S, true)
	key(KEY_D, true)
	await tick(22)
	check(arena.player.is_crouching and arena.player.sprite.animation == "crouch_walk_right" and absf(arena.player.velocity.x - 20.0) < 0.1, "S + D uses a moving crouched gait at crouch speed")
	check(arena.player.body_shape.shape.size == Vector2(12, 14), "crouch walking keeps the short collision box")
	key(KEY_SHIFT, true)
	await tick(15)
	check(not arena.player.is_running and arena.player.sprite.animation == "crouch_walk_right", "held Shift cannot stand up or sprint through a low passage")
	key(KEY_SHIFT, false)
	key(KEY_D, false)
	key(KEY_A, true)
	await tick(10)
	check(arena.player.sprite.animation == "crouch_walk_left" and arena.player.velocity.x < -19.0, "S + A turns the crouch gait to the left")
	key(KEY_A, false)
	await tick(7)
	check(arena.player.sprite.animation == "crouch_left" and arena.player.sprite.frame == 7 and absf(arena.player.velocity.x) < 0.1, "stopping while S remains held returns to the original static crouch pose")
	key(KEY_S, false)
	await tick(20)
	check(not arena.player.is_crouching and arena.player.body_shape.shape.size == Vector2(12, 26), "releasing S restores standing only when clear")
	await fixture()
	key(KEY_S, true)
	await tick(20)
	arena.add_wall(Rect2(arena.player.position + Vector2(-16, -28), Vector2(32, 12)))
	await tick(2)
	key(KEY_S, false)
	key(KEY_D, true)
	await tick(12)
	check(arena.player.is_crouching and arena.player.sprite.animation == "crouch_walk_right", "release of S under a low ceiling retains the crouched walk")
	await tick(75)
	check(not arena.player.is_crouching and arena.player.can_stand(), "the player stands safely after clearing a low ceiling")
	await fixture()
	key(KEY_SHIFT, true)
	await tick(2)
	arena.session.open_keybindings()
	await tick(5)
	key(KEY_SHIFT, false)
	arena.session.keybindings_menu.cancel()
	await tick(4)
	check(dodge_count == 0 and not arena.player.is_running and not arena.player._shift_gesture.held, "opening and closing settings clears unfinished Shift gestures")
	await fixture()
	var before: float = arena.player.combat_time
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SHIFT
	event.keycode = KEY_SHIFT
	event.pressed = true
	arena.player.handle_input(event)
	paused = true
	await tick(20)
	event.pressed = false
	arena.player.handle_input(event)
	check(arena.player.combat_time == before and not arena.player.is_dodging, "paused forwarding records tap edges without changing the frozen pose")
	paused = false
	await tick(1)
	check(arena.player.is_dodging, "a short combat-clock tap survives hit-stop and acts after it")
	await fixture()
	mouse(true)
	await tick(1)
	mouse(false)
	var cancel_snapshot: Dictionary = {}
	arena.player.special_started.connect(func(kind: String, _direction: Vector2) -> void:
		if kind == "dodge": cancel_snapshot["frame"] = arena.player.sprite.frame
	)
	await tap_shift()
	await tick(12)
	check(dodge_count == 1 and int(cancel_snapshot.get("frame", -1)) >= 7 and attacks == 1, "an early tapped evade waits for the light swing cancel window without adding a hit")
	await tick(8)
	for _i in range(30):
		if not arena.player.is_dodging:
			break
		await tick(1)
	mouse(true)
	await tick(1)
	mouse(false)
	await tick(1)
	check(arena.player.move_id == &"shadow_slash" and arena.player.combo_stage == 2, "a real tapped evade preserves the light string's dodge-offset follow-up")
	await fixture()
	mouse(true)
	await tick(1)
	key(KEY_D, true)
	key(KEY_SHIFT, true)
	await tick(2)
	check(arena.player.special_kind != "dash_stab" and dodge_count == 0, "holding an old attack before Shift cannot synthesize a fresh thrust click")
	var custom := CONTROLS.defaults()
	custom["run"] = KEY_CTRL
	custom["dash_modifier"] = KEY_CTRL
	custom["attack_mouse"] = MOUSE_BUTTON_MIDDLE
	await fixture(1, custom)
	key(KEY_CTRL, true)
	key(KEY_D, true)
	mouse(true, MOUSE_BUTTON_MIDDLE)
	await tick(1)
	check(arena.player.special_kind == "dash_stab", "shared custom modifier and custom attack mouse button form the same chord")
	await fixture(0)
	key(KEY_W, true)
	key(KEY_SHIFT, true)
	await tick(22)
	check(arena.player.is_running and arena.player.velocity.y < -130.0, "top-down movement also runs on a held Shift")
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	await tick(5)
	await tap_shift()
	check(arena.player.is_dodging and not arena.player.is_attacking, "top-down Shift tap is also a non-attacking directional evade")
	await fixture()
	arena.player.position = Vector2(140, 110)
	await tick(2)
	key(KEY_D, true)
	key(KEY_SHIFT, true)
	mouse(true)
	await tick(1)
	check(arena.player.sprite.animation == "air_dash_stab_right", "directional modifier chord retains the dedicated airborne thrust")
	for facing in ["left", "right"]:
		var clip := StringName("crouch_walk_" + facing)
		check(arena.player.SIDE_FRAMES.get_frame_count(clip) == 16 and arena.player.SIDE_FRAMES.get_animation_loop(clip), "new crouch loop has all 16 frames: " + facing)
	var result := {"checks": checks, "failed": failures.size(), "failures": failures, "status": "passed" if failures.is_empty() else "failed"}
	var file := FileAccess.open("res://evidence/shift_controls_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print(JSON.stringify(result))
	paused = false
	quit(0 if failures.is_empty() else 1)
