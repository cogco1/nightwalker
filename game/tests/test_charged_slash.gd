extends SceneTree
## Light / heavy attacks: a tap is the unchanged light chain; holding the attack button after a ground
## swing coils into a charge, and releasing it full fires a heavy slash (3x damage, critical hit-stop).

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
const HOSPITAL = preload("res://scenes/underground_hospital.tscn")
const TARGET = preload("res://tests/fixtures/training_target.gd")
var arena: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var _finished := false


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		check(false, "Charged-slash suite completes before its deadline")
		finish()
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


func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(160, 90)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func wait_until(condition: Callable, limit := 120) -> bool:
	for _index in range(limit):
		if condition.call():
			return true
		await frames(1)
	return condition.call()


func setup(mode: int, player_at: Vector2, target_at: Vector2) -> CharacterBody2D:
	arena.build_arena(mode)
	var player: CharacterBody2D = arena.player
	player.position = player_at
	player.critical_roll_override = 0.99
	arena.targets[0].position = target_at
	arena.targets[0].max_hp = 12
	arena.targets[0].hp = 12
	for index in range(1, arena.targets.size()):
		arena.targets[index].position = Vector2(300, 40) if mode == 0 else Vector2(300, 160)
	await frames(6)
	return player


func hold_into_charge(player: CharacterBody2D) -> bool:
	mouse(true)
	await frames(1)
	return await wait_until(func() -> bool: return player.is_charging, 90)


func run() -> void:
	arena = MAIN.instantiate()
	root.add_child(arena)
	await verify_tap_stays_light()
	await verify_charge_and_heavy(1)
	await verify_charge_and_heavy(0)
	await verify_early_release_cancels()
	await verify_charge_locks_and_jump_cancels()
	await verify_specials_and_air_never_coil()
	arena.queue_free()
	await frames(2)
	await verify_session_feedback()
	finish()


func verify_tap_stays_light() -> void:
	var player := await setup(1, Vector2(42, 160), Vector2(300, 160))
	mouse(true)
	await frames(1)
	mouse(false)
	check(player.is_attacking and player.combo_stage == 1, "A tap still starts the light chain on the press")
	await wait_until(func() -> bool: return not player.is_attacking, 90)
	await frames(20)
	check(not player.is_charging and player.charge_time == 0.0, "A tap never enters the charge")
	check(String(player.sprite.animation).begins_with("idle_"), "After a tap the hero returns to idle")


func verify_charge_and_heavy(mode: int) -> void:
	var label := "side" if mode == 1 else "top-down"
	# Top-down starts facing down, so its drone stands below the hero.
	var start := Vector2(60, 160) if mode == 1 else Vector2(90, 56)
	var target_at := Vector2(108, 160) if mode == 1 else Vector2(90, 100)
	var player := await setup(mode, start, target_at)
	var ready := [0]
	player.charge_ready.connect(func() -> void: ready[0] += 1)
	var target: Node = arena.targets[0]
	var hp_before: int = target.hp
	check(await hold_into_charge(player), label + ": holding after the swing coils into a charge")
	check(String(player.sprite.animation).begins_with("attack3_") and player.sprite.frame <= 1, label + ": the charge starts at the beginning of the attack3 wind-up")
	var coil_start: Vector2 = player.global_position
	var hp_after_light: int = target.hp
	await frames(int(ceil(player.CHARGE_FULL_SECONDS * 60.0)) + 4)
	check(player.is_charging and player.charge_time >= player.CHARGE_FULL_SECONDS, label + ": the charge fills while held")
	check(player.sprite.frame == player.CHARGE_POSE_FRAME, label + ": a full charge holds the attack3 wind-up pose")
	var backstep: float = (coil_start - player.global_position).dot(player.call("_facing_vector"))
	observations[label + "_backstep"] = snappedf(backstep, 0.1)
	check(backstep > 1.5 and backstep < 4.5, label + ": coiling settles back about three pixels")
	check(ready[0] == 1, label + ": charge_ready fires once when full")
	var rolls_before: int = player.critical_rolls
	var criticals_before: int = arena.critical_events
	var before_release: Vector2 = player.global_position
	mouse(false)
	await frames(2)
	check(player.is_attacking and player.special_kind == "heavy_slash", label + ": releasing a full charge fires the heavy slash")
	check(player.stage_is_critical and player.critical_rolls == rolls_before, label + ": the heavy slash is always critical and never rolls")
	var box: Rect2 = player.attack_box()
	observations[label + "_heavy_box"] = [box.size.x, box.size.y]
	await wait_until(func() -> bool: return not player.is_attacking, 120)
	await frames(30)
	observations[label + "_heavy_damage"] = hp_after_light - target.hp
	observations[label + "_light_damage"] = hp_before - hp_after_light
	observations[label + "_heavy_lunge"] = snappedf(player.global_position.distance_to(before_release), 0.1)
	check(player.global_position.distance_to(before_release) >= 24.0, label + ": the heavy slash lunges well past a light swing")
	check(hp_after_light - target.hp == 3, label + ": the heavy slash deals three times the light damage")
	check(arena.critical_events == criticals_before + 1, label + ": the heavy hit raises one critical event")
	var stops: Array = arena.completed_stop_requests
	check(not stops.is_empty() and int(stops[stops.size() - 1]) >= 6, label + ": the heavy hit uses the critical hit-stop")
	check(not player.is_charging and String(player.sprite.animation).begins_with("idle_"), label + ": the hero recovers to idle after the heavy slash")


func verify_early_release_cancels() -> void:
	var player := await setup(1, Vector2(60, 160), Vector2(108, 160))
	check(await hold_into_charge(player), "Early release case reaches the charge")
	var target: Node = arena.targets[0]
	var hp_coiled: int = target.hp
	await frames(10)
	mouse(false)
	await frames(2)
	check(not player.is_charging and not player.is_attacking and player.special_kind == "", "Releasing before full cancels without an attack")
	await frames(30)
	check(target.hp == hp_coiled, "A cancelled charge deals no damage")


func verify_charge_locks_and_jump_cancels() -> void:
	var player := await setup(1, Vector2(60, 160), Vector2(300, 160))
	check(await hold_into_charge(player), "Lock case reaches the charge")
	await wait_until(func() -> bool: return player.charge_time >= player.CHARGE_FULL_SECONDS, 90)
	var x_coiled: float = player.global_position.x
	key(KEY_A, true)
	await frames(12)
	check(absf(player.global_position.x - x_coiled) < 0.5 and player.facing == "right", "The charge roots the hero and keeps the facing")
	key(KEY_A, false)
	key(KEY_SPACE, true)
	await frames(3)
	key(KEY_SPACE, false)
	await frames(4)
	check(not player.is_charging and not player.is_on_floor(), "Jumping out of the charge cancels it")
	mouse(false)
	await wait_until(func() -> bool: return player.is_on_floor(), 120)
	await frames(10)
	check(not player.is_attacking and player.special_kind == "", "Releasing after a jump-cancel fires nothing")
	player.position = Vector2(60, 160)
	await frames(4)
	check(await hold_into_charge(player), "Input-buffer case reaches the charge")
	player.clear_input_buffer()
	await frames(2)
	check(not player.is_charging, "Clearing the input buffer (dialogue, keypad) cancels the charge")
	mouse(false)
	await frames(4)
	check(not player.is_attacking, "A buffer-cleared charge does not fire on release")


func verify_specials_and_air_never_coil() -> void:
	var player := await setup(1, Vector2(60, 160), Vector2(300, 160))
	key(KEY_SHIFT, true)
	key(KEY_D, true)
	mouse(true)
	await frames(2)
	key(KEY_D, false)
	key(KEY_SHIFT, false)
	check(player.special_kind == "dash_stab", "Shift with D held dash-stabs even with the mouse held")
	await wait_until(func() -> bool: return not player.is_attacking, 90)
	await frames(10)
	check(not player.is_charging, "Holding through a dash stab does not coil")
	mouse(false)
	await frames(20)
	key(KEY_SPACE, true)
	await frames(2)
	key(KEY_SPACE, false)
	await frames(8)
	mouse(true)
	await frames(2)
	check(player.is_attacking and not player.is_on_floor(), "A press in the air starts the air chain")
	await wait_until(func() -> bool: return player.is_on_floor(), 150)
	await frames(30)
	check(not player.is_charging, "Holding through an air attack does not coil after landing")
	mouse(false)
	await frames(10)


# Real scene path: GameSession hit-stops and CombatFeedback sounds in the hospital side view, with one
# fixture target dropped next to the hero (the shipped hospital has no enemies).
func verify_session_feedback() -> void:
	var hospital: Node2D = HOSPITAL.instantiate()
	root.add_child(hospital)
	current_scene = hospital
	await frames(10)
	hospital.call("switch_view")
	await frames(20)
	var player: CharacterBody2D = hospital.player
	var session: Node = hospital.get_node("GameSession")
	var feedback: Node = session.get_node_or_null("CombatFeedback")
	check(feedback != null, "GameSession owns a CombatFeedback node")
	if feedback == null:
		return
	check(feedback.process_mode == Node.PROCESS_MODE_ALWAYS, "Combat sounds keep playing through the hit-stop pause")
	player.facing = "right"
	player.call("_show_idle")
	var target := TARGET.new()
	target.side_view = true
	target.max_hp = 30
	target.position = player.global_position + Vector2(30, 0)
	hospital.world.add_child(target)
	target.hp = 30
	player.critical_roll_override = 0.99
	await frames(4)
	mouse(true)
	await frames(1)
	mouse(false)
	await wait_until(func() -> bool: return not player.is_attacking, 90)
	await frames(20)
	observations["session_light_stops"] = session.completed_stop_frames.duplicate()
	check(target.hp == 29 and session.completed_stop_frames == [4], "A light hit in a real scene keeps the 4-frame stop")
	check(feedback.played.has("swing_light") and feedback.played.has("hit_light"), "A light hit plays the light swing and hit sounds")
	feedback.played.clear()
	player.position = target.global_position - Vector2(46, 0)
	await frames(4)
	check(await hold_into_charge(player), "Real scene: holding coils into the charge")
	await frames(int(ceil(player.CHARGE_FULL_SECONDS * 60.0)) + 4)
	mouse(false)
	await wait_until(func() -> bool: return not player.is_attacking, 120)
	await frames(20)
	observations["session_heavy_stops"] = session.completed_stop_frames.duplicate()
	observations["session_heavy_sounds"] = feedback.played.duplicate()
	var stops: Array = session.completed_stop_frames
	check(not stops.is_empty() and int(stops[stops.size() - 1]) >= session.HEAVY_STOP_FRAMES, "The heavy slash freezes for the longer heavy stop")
	check(target.hp <= 26, "The heavy slash lands in the real scene")
	var order: Array = []
	for sound in ["charge", "charge_ready", "swing_heavy", "hit_heavy"]:
		order.append(feedback.played.find(sound))
	check(order[0] >= 0 and order[0] < order[1] and order[1] < order[2] and order[2] < order[3], "Charge, ready, heavy swing and heavy hit sound in order")
	check(not session.get_viewport().get_camera_2d() or session.get_viewport().get_camera_2d().offset == Vector2.ZERO, "The after-shock returns the camera to rest")
	# The hospital stays in the tree like the other suites' scenes: freeing it right before quit strands the
	# audio server's playbacks and reports leaks at exit.


func finish() -> void:
	if _finished:
		return
	_finished = true
	mouse(false)
	for code in [KEY_A, KEY_D, KEY_SHIFT, KEY_SPACE]:
		key(code, false)
	var report := {"suite": "charged_slash", "status": "passed" if failures.is_empty() else "failed", "checks": checks,
		"failures": failures, "observations": observations}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	var file := FileAccess.open("res://evidence/charged_slash_results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
