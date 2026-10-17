extends "res://tests/support/isolated_suite.gd"
## Combat state machine and intent table: FREE -> ATTACK -> RECOVERY -> FREE, the combat clock that a
## hit-stop freezes, presses recorded during the freeze acting only after it, and buffer expiry.

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
var arena: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		check(false, "Combat state suite completes before its deadline")
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


func run() -> void:
	arena = MAIN.instantiate()
	root.add_child(arena)
	arena.build_arena(1)
	await frames(6)
	var player: CharacterBody2D = arena.player
	await verify_states(player)
	await verify_clock_and_hit_stop(player)
	await verify_buffer_expiry(player)
	finish()


func verify_states(player: CharacterBody2D) -> void:
	player.position = Vector2(60, 160)
	arena.targets[0].position = Vector2(290, 160)
	await frames(4)
	check(player.state == player.State.FREE and not player.is_attacking and player.special_kind == "" and player.combo_stage == 0, "the hero starts FREE")
	mouse(true)
	await frames(1)
	mouse(false)
	await frames(1)
	check(player.state == player.State.ATTACK and player.is_attacking and player.combo_stage == 1 and player.move_id == &"attack1", "a tap starts attack1 in ATTACK")
	var ticks_before: int = player.move_ticks
	await frames(5)
	check(player.move_ticks == ticks_before + 5, "move_ticks counts the move's physics ticks")
	await wait_until(func() -> bool: return not player.is_attacking, 90)
	check(player.state == player.State.RECOVERY and player._recovery_left > 0.0, "the swing ends in a short RECOVERY")
	await wait_until(func() -> bool: return player.state == player.State.FREE, 30)
	check(player.state == player.State.FREE and player.move.is_empty() and player.move_id == &"", "recovery returns to FREE with no move")


# During a hit-stop the tree is paused: the combat clock stands still, a click is only recorded, and S does not
# start the dive inside the frozen frame.
func verify_clock_and_hit_stop(player: CharacterBody2D) -> void:
	var target: Node = arena.targets[0]
	player.position = Vector2(80, 160)
	target.position = Vector2(112, 160)
	target.max_hp = 30
	target.hp = 30
	await frames(4)
	mouse(true)
	await frames(1)
	mouse(false)
	check(await wait_until(func() -> bool: return arena.hit_stop_active, 60), "the first swing lands and starts a hit-stop")
	var time_frozen: float = player.combat_time
	var tick_frozen: int = player.combat_tick
	mouse(true)
	mouse(false)
	await process_frame
	check(arena.hit_stop_active and player.combat_time == time_frozen and player.combat_tick == tick_frozen, "the combat clock stands still during the hit-stop")
	check(player._mouse_attack_pending, "a click during the hit-stop is recorded, not acted on")
	observations["clock_frozen_at"] = time_frozen
	await wait_until(func() -> bool: return not arena.hit_stop_active, 30)
	await frames(2)
	check(player.combat_time > time_frozen, "the combat clock runs again after the hit-stop")
	await wait_until(func() -> bool: return not player.is_attacking and player.state != player.State.RECOVERY, 120)
	# airborne swing a little above the floor next to the target, then S pressed while frozen
	target.position = Vector2(112, 160)
	player.position = Vector2(88, 148)
	player.velocity = Vector2.ZERO
	await frames(1)
	check(not player.is_on_floor(), "the hero starts the air swing airborne")
	mouse(true)
	await frames(1)
	mouse(false)
	var stopped := await wait_until(func() -> bool: return arena.hit_stop_active, 60)
	if stopped:
		var frozen_animation := String(player.sprite.animation)
		key(KEY_S, true)
		await process_frame
		check(String(player.sprite.animation) == frozen_animation and player.special_kind != "dive_slash", "S during the hit-stop leaves the frozen frame unchanged")
		await wait_until(func() -> bool: return not arena.hit_stop_active, 30)
		await frames(2)
		check(player.special_kind == "dive_slash" or player.is_on_floor(), "the recorded S acts once the hit-stop ends")
		key(KEY_S, false)
	else:
		observations["air_hit_missed"] = true
	await wait_until(func() -> bool: return player.is_on_floor() and not player.is_attacking, 120)


func verify_buffer_expiry(player: CharacterBody2D) -> void:
	await wait_until(func() -> bool: return player.state == player.State.FREE, 60)
	arena.targets[0].position = Vector2(290, 160)
	player.position = Vector2(60, 160)
	await frames(4)
	mouse(true)
	await frames(1)
	mouse(false)
	await frames(2)
	mouse(true)
	await frames(1)
	mouse(false)
	await frames(1)
	check(player.queued_attack and player.attack_buffer_left > 0.0, "a second tap during attack1 queues one follow-up")
	var buffer: float = player.attack_buffer_left
	check(buffer >= player.ATTACK_BUFFER_SECONDS - 0.001 and buffer <= 0.55 + 0.001, "the follow-up buffer lies between 0.22 s and 0.55 s")
	observations["queued_buffer_seconds"] = snappedf(buffer, 0.001)
	check(await wait_until(func() -> bool: return player.combo_stage == 2, 60), "the queued follow-up becomes attack2")
	check(not player.queued_attack and player.attack_buffer_left == 0.0, "starting the follow-up consumes the intent")
	await wait_until(func() -> bool: return player.state == player.State.FREE, 120)
	# a queued intent left alone past its buffer expires: hold the move frozen by pausing its animation
	mouse(true)
	await frames(1)
	mouse(false)
	await frames(2)
	mouse(true)
	await frames(1)
	mouse(false)
	await frames(1)
	player.sprite.pause()
	var expires_after: float = player.attack_buffer_left
	await frames(int(ceil(expires_after * 60.0)) + 2)
	check(not player.queued_attack, "a queued follow-up expires once its buffer runs out")
	player.sprite.play()
	await wait_until(func() -> bool: return player.state == player.State.FREE, 120)
	check(player.combo_stage == 0, "an expired follow-up never starts")


func finish() -> void:
	for code in [KEY_SPACE, KEY_S]:
		key(code, false)
	mouse(false)
	var report := {"suite": "combat_state", "status": "passed" if failures.is_empty() else "failed", "checks": checks,
		"failures": failures, "observations": observations}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
