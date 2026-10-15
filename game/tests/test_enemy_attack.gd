extends "res://tests/support/isolated_suite.gd"
## Enemy attacks and the hero's reaction (side view, combat_lab attack drone): the red telegraph and lunge, HIT
## (knockback about 20 px, red blink, 0.3 s stun that interrupts swings and charges, presses wait for it), EVADE
## (a dash too early, jumping over the lunge) and PERFECT (a dash at most 0.2 s before the hit window or inside
## it), and a destroyed drone that stops attacking.

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
var arena: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var results: Array[int] = []
var drone: CharacterBody2D


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		check(false, "Enemy attack suite completes before its deadline")
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


func tap_key(code: int) -> void:
	key(code, true)
	await frames(1)
	key(code, false)


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
	arena.player.attack_received.connect(func(result: int, _attack: Dictionary) -> void: results.append(result))
	await verify_hit()
	await verify_interrupts()
	await verify_evades()
	await verify_perfect()
	await verify_destroyed()
	finish()


# Hero at x on the floor facing right, practice targets parked, one fresh drone at `drone_at`.
func stage(x: float, drone_at: Vector2) -> void:
	var player: CharacterBody2D = arena.player
	# a perfect dodge's slow motion (test_perfect_counter.gd) must not carry into the next case
	arena.session.end_slowmo()
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
	player.critical_roll_override = 0.99
	await frames(3)
	results.clear()
	drone = arena.add_attacker(drone_at)


func phase() -> int:
	return drone.attacker.phase


func verify_hit() -> void:
	var player: CharacterBody2D = arena.player
	var attacker: Node = null
	await stage(100, Vector2(140, 147))
	attacker = drone.attacker
	check(await wait_until(func() -> bool: return phase() == attacker.Phase.TELEGRAPH, 10), "a hero in reach starts the drone's telegraph")
	var telegraph_ticks := 0
	var red_seen := false
	var plain_seen := false
	while phase() == attacker.Phase.TELEGRAPH and telegraph_ticks < 60:
		red_seen = red_seen or drone.modulate == attacker.warning_color
		plain_seen = plain_seen or drone.modulate == Color.WHITE
		telegraph_ticks += 1
		await frames(1)
	check(red_seen and plain_seen, "the drone blinks red during the telegraph")
	check(absi(telegraph_ticks - 30) <= 2, "the telegraph lasts about 0.5 s")
	check(phase() == attacker.Phase.LUNGE, "the telegraph ends in the lunge")
	var start_x := player.position.x
	check(await wait_until(func() -> bool: return not results.is_empty(), 30), "the lunge resolves against the hero")
	check(results == [player.AttackResult.HIT] and player.state == player.State.HURT, "a hero standing still is hit and stunned")
	check(arena.session.combat_feedback.played.has("hit_heavy"), "taking a hit plays an impact sound")
	var hurt_ticks := 0
	var tint_seen := false
	while player.state == player.State.HURT and hurt_ticks < 60:
		tint_seen = tint_seen or player.sprite.modulate == player.HURT_TINT
		hurt_ticks += 1
		await frames(1)
	var pushed := player.position.x - start_x
	check(tint_seen and player.sprite.modulate == Color.WHITE, "the hero blinks red while stunned and returns to normal colour")
	check(absi(hurt_ticks - 18) <= 2, "the stun lasts about 0.3 s")
	check(pushed <= -15.0 and pushed >= -25.0, "the hit knocks the hero about 20 px away from the drone")
	check(player.state == player.State.FREE, "the hero is free after the stun")
	observations["hit"] = {"telegraph_ticks": telegraph_ticks, "hurt_ticks": hurt_ticks, "pushed_px": snappedf(pushed, 0.1)}


func verify_interrupts() -> void:
	var player: CharacterBody2D = arena.player
	# a swing in progress
	await stage(100, Vector2(140, 147))
	var attacker: Node = drone.attacker
	await wait_until(func() -> bool: return phase() == attacker.Phase.TELEGRAPH and attacker.phase_time >= 0.40, 60)
	mouse(true)
	await frames(1)
	mouse(false)
	check(await wait_until(func() -> bool: return not results.is_empty(), 40), "the lunge resolves during the swing")
	check(results == [player.AttackResult.HIT] and player.state == player.State.HURT and not player.is_attacking and player.move_id == &"", "a hit interrupts the swing")
	# a press during the stun comes out once it ends
	mouse(true)
	await frames(1)
	mouse(false)
	await frames(1)
	check(player.state == player.State.HURT and not player.is_attacking, "a click during the stun does not attack at once")
	check(await wait_until(func() -> bool: return player.is_attacking, 30), "the click comes out after the stun")
	# a charge in progress
	await stage(100, Vector2(140, 147))
	var released: Array[bool] = []
	player.charge_ended.connect(func(was_released: bool) -> void: released.append(was_released), CONNECT_ONE_SHOT)
	mouse(true)
	check(await wait_until(func() -> bool: return not results.is_empty(), 90), "the lunge resolves during the charge")
	mouse(false)
	check(results == [player.AttackResult.HIT] and released == [false] and player.state == player.State.HURT, "a hit cancels the charge")


func verify_evades() -> void:
	var player: CharacterBody2D = arena.player
	# a dash 0.26 s before the hit window: the lunge misses, but too early to be perfect
	await stage(100, Vector2(140, 147))
	var attacker: Node = drone.attacker
	await wait_until(func() -> bool: return phase() == attacker.Phase.TELEGRAPH and attacker.phase_time >= 0.30, 60)
	await tap_key(KEY_SHIFT)
	check(await wait_until(func() -> bool: return not results.is_empty(), 40), "the lunge resolves after an early dash")
	check(results == [player.AttackResult.EVADE] and player.state != player.State.HURT, "a dash 0.26 s early evades but is not perfect")
	# jumping over the lunge
	await stage(100, Vector2(140, 147))
	attacker = drone.attacker
	await wait_until(func() -> bool: return phase() == attacker.Phase.TELEGRAPH and attacker.phase_time >= 0.31, 60)
	await tap_key(KEY_SPACE)
	check(await wait_until(func() -> bool: return not results.is_empty(), 40), "the lunge resolves under a jump")
	check(results == [player.AttackResult.EVADE] and player.state != player.State.HURT, "jumping over the lunge evades it")


func verify_perfect() -> void:
	var player: CharacterBody2D = arena.player
	# a dash 0.14 s before the hit window
	await stage(100, Vector2(140, 147))
	var attacker: Node = drone.attacker
	await wait_until(func() -> bool: return phase() == attacker.Phase.TELEGRAPH and attacker.phase_time >= 0.42, 60)
	await tap_key(KEY_SHIFT)
	check(await wait_until(func() -> bool: return not results.is_empty(), 40), "the lunge resolves after a timely dash")
	check(results == [player.AttackResult.PERFECT] and player.state != player.State.HURT, "a dash 0.14 s before the hit window is a perfect dodge")
	check(arena.session.combat_feedback.played.back() == "charge_ready" or arena.session.combat_feedback.played.has("charge_ready"), "a perfect dodge chimes")
	# a dash inside the hit window, before contact: the dash's invulnerability takes the hit
	await stage(100, Vector2(190, 147))
	attacker = drone.attacker
	await wait_until(func() -> bool: return phase() == attacker.Phase.LUNGE and attacker.window_age() >= 0.02, 60)
	check(results.is_empty(), "the far drone has not touched the hero yet")
	await tap_key(KEY_SHIFT)
	check(await wait_until(func() -> bool: return not results.is_empty(), 40), "the lunge resolves against the dashing hero")
	check(results == [player.AttackResult.PERFECT] and player.state != player.State.HURT, "a dash inside the hit window is a perfect dodge")
	observations["late_dash_contact"] = attacker.last_result


func verify_destroyed() -> void:
	var player: CharacterBody2D = arena.player
	await stage(100, Vector2(126, 147))
	drone.hp = 1
	mouse(true)
	await frames(1)
	mouse(false)
	check(await wait_until(func() -> bool: return drone.hp == 0, 40), "the hero destroys the drone")
	await wait_until(func() -> bool: return player.state == player.State.FREE, 120)
	results.clear()
	await frames(90)
	check(results.is_empty() and drone.attacker.phase != drone.attacker.Phase.LUNGE, "a destroyed drone no longer attacks")


func finish() -> void:
	for code in [KEY_SPACE, KEY_SHIFT]:
		key(code, false)
	mouse(false)
	var report := {"suite": "enemy_attack", "status": "passed" if failures.is_empty() else "failed", "checks": checks,
		"failures": failures, "observations": observations}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
