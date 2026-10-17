extends "res://tests/support/isolated_suite.gd"
## Perfect dodge and counter (GameSession clock): the world slows to 25 % for 1.2 s of real time while the hero
## keeps full speed and Engine.time_scale stays 1, the screen edges glow, the hero cannot be hit, hit-stops pause the
## slow-motion clock, and a left or right click blinks the hero behind the enemy for a 3x critical with the 10-frame
## freeze, which ends the slow motion.

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
var arena: Node2D
var session: Node
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var results: Array[int] = []
var drone: CharacterBody2D


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		check(false, "Perfect counter suite completes before its deadline")
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


func mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
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


func run() -> void:
	arena = MAIN.instantiate()
	root.add_child(arena)
	arena.build_arena(1)
	await frames(6)
	session = arena.session
	arena.player.attack_received.connect(func(result: int, _attack: Dictionary) -> void: results.append(result))
	await verify_slow_motion()
	await verify_stop_pauses_clock()
	await verify_counter(MOUSE_BUTTON_LEFT)
	await verify_counter(MOUSE_BUTTON_RIGHT)
	await verify_no_counter_without_dodge()
	finish()


# Hero at x facing right, practice targets parked, a fresh drone 40 px ahead; returns once the perfect dodge landed.
func perfect_dodge(x: float) -> bool:
	var player: CharacterBody2D = arena.player
	session.end_slowmo()
	if is_instance_valid(drone):
		arena.attackers.erase(drone)
		drone.queue_free()
	await wait_until(func() -> bool: return player.state == player.State.FREE and player.is_on_floor() and not arena.hit_stop_active, 180)
	await frames(18)
	for target in arena.targets:
		target.position = Vector2(300, 160)
	player.position = Vector2(x, 160)
	player.velocity = Vector2.ZERO
	player.facing = "right"
	await frames(3)
	results.clear()
	drone = arena.add_attacker(Vector2(x + 40, 147))
	drone.max_hp = 30
	drone.hp = 30
	var attacker: Node = drone.attacker
	await wait_until(func() -> bool: return attacker.phase == attacker.Phase.TELEGRAPH and attacker.phase_time >= 0.42, 60)
	key(KEY_SHIFT, true)
	await frames(1)
	key(KEY_SHIFT, false)
	await wait_until(func() -> bool: return not results.is_empty(), 40)
	return results == [player.AttackResult.PERFECT]


func verify_slow_motion() -> void:
	var player: CharacterBody2D = arena.player
	check(await perfect_dodge(100), "a timely dash is a perfect dodge")
	check(session.slowmo_active and is_equal_approx(session.world_time_scale, 0.25), "the perfect dodge slows the world to 25 %")
	check(Engine.time_scale == 1.0, "Engine.time_scale stays 1")
	check(session.slowmo_overlay.visible, "the screen edges glow during the slow motion")
	# the drone's clock runs at a quarter of the hero's
	var attacker: Node = drone.attacker
	var world_before: float = attacker.phase_time
	var phase_before: int = attacker.phase
	var hero_before: float = player.combat_time
	await frames(8)
	var world_step: float = attacker.phase_time - world_before
	var hero_step: float = player.combat_time - hero_before
	check(attacker.phase == phase_before and is_equal_approx(world_step, hero_step * 0.25), "the drone runs at a quarter of the hero's speed")
	observations["clock_steps"] = {"world": snappedf(world_step, 0.0001), "hero": snappedf(hero_step, 0.0001)}
	# the hero walks at full speed
	await wait_until(func() -> bool: return player.state == player.State.FREE, 40)
	key(KEY_D, true)
	await frames(8)
	check(is_equal_approx(player.velocity.x, player.move_speed), "the hero walks at full speed in the slow motion")
	key(KEY_D, false)
	# enemy attacks cannot hit
	check(player.receive_attack({"contact": true, "window_age": 0.0, "direction": Vector2.LEFT}) == player.AttackResult.EVADE and player.state != player.State.HURT, "the hero cannot be hit in the slow motion")
	# 1.2 s of real time without a counter
	var left: float = session.slowmo_left
	var ticks := 0
	while session.slowmo_active and ticks < 120:
		ticks += 1
		await frames(1)
	var total: float = (session.SLOWMO_SECONDS - left) * 60.0 + ticks
	check(absf(total - 72.0) <= 2.0, "the slow motion lasts 1.2 s of real time")
	check(not session.slowmo_active and session.world_time_scale == 1.0 and not session.slowmo_overlay.visible, "the world returns to full speed")
	check(not player.invulnerable, "the hero can be hit again")
	observations["slowmo_ticks"] = snappedf(total, 0.1)


func verify_stop_pauses_clock() -> void:
	var player: CharacterBody2D = arena.player
	check(await perfect_dodge(100), "a second perfect dodge")
	await frames(2)
	var left: float = session.slowmo_left
	player.impact.emit(&"critical", Vector2.RIGHT)
	check(arena.hit_stop_active, "a hit-stop runs inside the slow motion")
	await wait_until(func() -> bool: return not arena.hit_stop_active, 30)
	check(session.completed_stop_frames.back() == 6, "the freeze still holds its 6 frames in the slow motion")
	check(absf(session.slowmo_left - left) <= 1.0 / 60.0 + 0.0001, "the slow-motion clock stands still during the hit-stop")
	observations["clock_during_stop"] = snappedf(left - session.slowmo_left, 0.0001)


func verify_counter(button: MouseButton) -> void:
	var player: CharacterBody2D = arena.player
	check(await perfect_dodge(100), "a perfect dodge before the counter")
	var hp_before: int = drone.hp
	var stops_before: int = session.completed_stop_frames.size()
	var blink_snapshot: Dictionary = {}
	player.counter_started.connect(func(enemy: Node2D) -> void:
		blink_snapshot["distance"] = absf(player.global_position.x - enemy.global_position.x)
	, CONNECT_ONE_SHOT)
	await frames(3)
	mouse(button, true)
	await frames(1)
	mouse(button, false)
	check(player.move_id == &"counter_slash" and player.special_kind == "counter", "a click in the slow motion starts the counter")
	var side := signf(player.global_position.x - drone.global_position.x)
	check(absf(float(blink_snapshot.get("distance", INF)) - player.COUNTER_BEHIND) < 0.5, "the counter lands at the correct offset at its blink event, before the moving drone advances")
	check(player.attack_direction.x == -side, "the hero faces the drone after the blink")
	check(await wait_until(func() -> bool: return drone.hp < hp_before, 40), "the counter hits the drone")
	check(hp_before - drone.hp == 3, "the counter deals triple damage")
	check(not session.slowmo_active and session.world_time_scale == 1.0, "the counter's hit ends the slow motion")
	await wait_until(func() -> bool: return not arena.hit_stop_active, 40)
	check(session.completed_stop_frames.size() > stops_before and session.completed_stop_frames.back() == 10, "the counter freezes 10 frames")
	observations["counter_" + str(button)] = {"side": side, "damage": hp_before - drone.hp}


func verify_no_counter_without_dodge() -> void:
	var player: CharacterBody2D = arena.player
	session.end_slowmo()
	await wait_until(func() -> bool: return player.state == player.State.FREE and not arena.hit_stop_active, 120)
	await frames(18)
	var x := player.global_position.x
	mouse(MOUSE_BUTTON_LEFT, true)
	await frames(1)
	mouse(MOUSE_BUTTON_LEFT, false)
	await frames(1)
	check(player.move_id == &"attack1" and absf(player.global_position.x - x) < 2.0, "without a perfect dodge a click is an ordinary swing")


func finish() -> void:
	for code in [KEY_SHIFT, KEY_D]:
		key(code, false)
	mouse(MOUSE_BUTTON_LEFT, false)
	mouse(MOUSE_BUTTON_RIGHT, false)
	var report := {"suite": "perfect_counter", "status": "passed" if failures.is_empty() else "failed", "checks": checks,
		"failures": failures, "observations": observations}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
