extends "res://tests/support/isolated_suite.gd"
## Light / heavy combo graph (side view): the five-hit light string, heavy finishers after light 1-4, heavy on
## its own and H H, cancel windows of the new moves, multi-hit spins with blade arcs, knockback, the rift slash
## landing wave, and the limits (top-down view, airborne, crouching, latest press wins). Dodge offset: light swings
## cut into the dash after their hit frame, and a press during or just after the dash gives the shadow slash (which
## resumes the interrupted string) or the chase cleave. Aerial spin: right click in the air, or a fourth click after
## the air string; three hits (2, 2 and 6 frame stops), about 0.6 s up, then the dive can follow. Leap cleave: W + right
## click on the floor leaps about 52 px forward, chops on the way down (2x, heavy stop, launch) and lands with a
## shockwave along the floor (2x, heavy stop, launch; landing effects even on a miss).

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
const MOVESET = preload("res://scripts/player/moves_long_blade.gd")
const LIGHT := MOUSE_BUTTON_LEFT
const HEAVY := MOUSE_BUTTON_RIGHT
var arena: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var moves_seen: Array[StringName] = []
var hits_seen: Array[Dictionary] = []
var last_frame: Dictionary = {}
var arc_pixels := 0


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		check(false, "Rhythm combat suite completes before its deadline")
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
		var player: CharacterBody2D = arena.player
		if player.is_attacking:
			last_frame[player.move_id] = maxi(int(last_frame.get(player.move_id, -1)), player.sprite.frame)
			if player.move.has("arc"):
				var still: Array = player.fx.effects.filter(func(effect: Dictionary) -> bool: return effect.has("tail") and Vector2(effect["velocity"]) == Vector2.ZERO)
				arc_pixels = maxi(arc_pixels, still.size())
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


func tap(button: MouseButton) -> void:
	mouse(button, true)
	await frames(1)
	mouse(button, false)
	if button==LIGHT:await frames(1)


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
	arena.player.move_started.connect(func(id: StringName) -> void: moves_seen.append(id))
	arena.player.hit_resolved.connect(func(target: Node, damage: int, critical: bool, _kind: String) -> void:
		hits_seen.append({"move": arena.player.move_id, "target": target, "damage": damage, "critical": critical}))
	await verify_light_string()
	await verify_heavy_alone_and_twice()
	await verify_finishers()
	await verify_rift_slash()
	await verify_latest_press_wins()
	await verify_dodge_offset()
	await verify_dash_cancel()
	await verify_air_spin()
	await verify_leap_cleave()
	await verify_limits()
	finish()


# Hero at `at`, one practice target at `target_at` (others parked at the far wall), fresh logs.
func stage(at: Vector2, target_at: Vector2, second_at := Vector2(300, 160)) -> void:
	var player: CharacterBody2D = arena.player
	await wait_until(func() -> bool: return player.state == player.State.FREE and player.is_on_floor() and not arena.hit_stop_active, 180)
	# let the dodge-offset windows of the previous case close
	await frames(int(ceil(player.DODGE_OFFSET_SECONDS * 60.0)) + 2)
	player.critical_roll_override = 0.99
	player.position = at
	player.velocity = Vector2.ZERO
	player.facing = "right"
	for index in range(arena.targets.size()):
		var target: CharacterBody2D = arena.targets[index]
		target.position = target_at if index == 0 else (second_at if index == 1 else Vector2(300, 160))
		target.velocity = Vector2.ZERO
		target.max_hp = 99
		target.hp = 99
		target.knock_count = 0
		target.knock_back_count = 0
	await frames(4)
	moves_seen.clear()
	hits_seen.clear()
	last_frame.clear()
	arc_pixels = 0
	arena.completed_stop_requests.clear()


func hits_by(moves: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hit in hits_seen:
		if hit["move"] in moves:
			result.append(hit)
	return result


# Taps `buttons` one by one, each once the previous one's move has started; returns false if a move never came.
func play_string(buttons: Array, expected: Array) -> bool:
	var player: CharacterBody2D = arena.player
	for index in range(buttons.size()):
		await tap(buttons[index])
		if not await wait_until(func() -> bool: return player.move_id == expected[index], 90):
			observations["stalled_at"] = String(expected[index])
			return false
	return true


func verify_light_string() -> void:
	var player: CharacterBody2D = arena.player
	await stage(Vector2(40, 160), Vector2(80, 160))
	var played := await play_string([LIGHT, LIGHT, LIGHT, LIGHT, LIGHT], [&"attack1", &"attack2", &"attack3", &"thrust4", &"spin5a"])
	check(played, "five left clicks keep the light string going")
	await wait_until(func() -> bool: return player.state == player.State.FREE, 120)
	check(moves_seen == [&"attack1", &"attack2", &"attack3", &"thrust4", &"spin5a", &"spin5b"], "L x5 plays attack1-3, the thrust and the two-part spin")
	check(int(last_frame.get(&"attack1", -1)) == 15 and int(last_frame.get(&"attack2", -1)) == 15, "the original three hits still wait for each clip to end")
	check(int(last_frame.get(&"thrust4", 99)) < 15, "the thrust's cancel window starts the spin before the stab clip ends")
	check(hits_by([&"spin5a", &"spin5b"]).size() == 2, "the spin hits the same target twice")
	check(hits_by([&"thrust4"]).size() == 1 and hits_by([&"attack1", &"attack2", &"attack3"]).size() == 3, "every light hit of the string connects once")
	check(arc_pixels >= 8, "the spin draws a blade circle")
	check(arena.completed_stop_requests == [2, 2, 2, 2, 2, 6], "light hits stop 2 frames, the spin's last hit 6")
	observations["light_string_stops"] = arena.completed_stop_requests.duplicate()
	observations["thrust_last_frame"] = last_frame.get(&"thrust4", -1)
	observations["arc_pixels"] = arc_pixels


func verify_heavy_alone_and_twice() -> void:
	var player: CharacterBody2D = arena.player
	var target: CharacterBody2D = arena.targets[0]
	await stage(Vector2(40, 160), Vector2(84, 160))
	var start_x := player.position.x
	await tap(HEAVY)
	check(player.move_id == &"rush_cleave", "a right click on its own starts the rush cleave at once")
	check(not arena.session.combat_feedback.played.has("swing_heavy"), "the heavy swing cue waits for the cleave release")
	await wait_until(func() -> bool: return player.state == player.State.FREE, 120)
	check(player.position.x - start_x >= 14.0, "the rush cleave lunges forward")
	var cleave := hits_by([&"rush_cleave"])
	check(cleave.size() == 1 and cleave[0]["damage"] == 3 and not cleave[0]["critical"], "the committed rush cleave hits once for triple damage")
	check(target.knock_back_count == 1, "the rush cleave knocks the target back")
	check(arena.completed_stop_requests == [10] and arena.session.combat_feedback.played.count("swing_heavy")==1, "the cleave retains 10-frame heavy contact and one release sound")
	observations["rush_lunge_px"] = snappedf(player.position.x - start_x, 0.1)
	observations["rush_target_x"] = snappedf(target.position.x, 0.1)
	# H H: the second right click follows into the launch slash
	await stage(Vector2(40, 160), Vector2(84, 160))
	var played := await play_string([HEAVY, HEAVY], [&"rush_cleave", &"launch_slash"])
	check(played, "H H follows the rush cleave with the launch slash")
	check(int(last_frame.get(&"rush_cleave", 99)) < 15, "the rush cleave's cancel window starts the launch before its clip ends")
	await frames(3)
	check(not player.is_on_floor() and player.velocity.y < 0.0, "the launch slash lifts the hero")
	await wait_until(func() -> bool: return player.state != player.State.ATTACK, 90)
	check(target.knock_count >= 1, "the launch slash launches the target")
	observations["hh_target_x"] = snappedf(target.position.x, 0.1)


func verify_finishers() -> void:
	var player: CharacterBody2D = arena.player
	await stage(Vector2(40, 160), Vector2(80, 160))
	check(await play_string([LIGHT, HEAVY], [&"attack1", &"rush_cleave"]), "L then H gives the rush cleave")
	check(int(last_frame.get(&"attack1", -1)) == 15, "a heavy follow-up waits for the original swing to end")
	await stage(Vector2(40, 160), Vector2(80, 160))
	check(await play_string([LIGHT, LIGHT, HEAVY], [&"attack1", &"attack2", &"launch_slash"]), "L L then H gives the launch slash")
	await stage(Vector2(40, 160), Vector2(80, 160))
	check(await play_string([LIGHT, LIGHT, LIGHT, HEAVY], [&"attack1", &"attack2", &"attack3", &"spin_cleave_a"]), "L L L then H gives the spin cleave")
	await wait_until(func() -> bool: return player.state == player.State.FREE, 120)
	check(moves_seen.slice(-2) == [&"spin_cleave_a", &"spin_cleave_b"], "the spin cleave flows into its second part")
	var spin := hits_by([&"spin_cleave_a", &"spin_cleave_b"])
	check(spin.size() == 3, "the spin cleave hits three times")
	check(spin.size() == 3 and not spin[0]["critical"] and not spin[1]["critical"] and spin[2]["critical"] and spin[2]["damage"] == 3, "only the last spin cleave hit is a critical")
	check(arena.completed_stop_requests.slice(-3) == [2, 2, 6], "the spin cleave stops 2, 2 and 6 frames")
	check(arc_pixels >= 8, "the spin cleave draws a blade circle")
	observations["spin_cleave_stops"] = arena.completed_stop_requests.duplicate()


func verify_rift_slash() -> void:
	var player: CharacterBody2D = arena.player
	var behind: CharacterBody2D = arena.targets[1]
	await stage(Vector2(60, 160), Vector2(100, 160))
	var played := await play_string([LIGHT, LIGHT, LIGHT, LIGHT, HEAVY], [&"attack1", &"attack2", &"attack3", &"thrust4", &"rift_hop"])
	check(played, "L L L L then H gives the rift slash")
	# a second target stands behind the hero where it will land
	behind.position = Vector2(player.position.x - 24.0, 160)
	check(await wait_until(func() -> bool: return not player.is_on_floor(), 20), "the rift slash hops off the floor")
	var peak := player.position.y
	for _index in range(40):
		peak = minf(peak, player.position.y)
		if player.move_id == &"rift_dive":
			break
		await frames(1)
	check(player.move_id == &"rift_dive", "the hop turns into the dive")
	check(await wait_until(func() -> bool: return player.is_on_floor(), 60), "the dive lands")
	await wait_until(func() -> bool: return player.state == player.State.FREE, 120)
	check(160.0 - peak >= 8.0 and 160.0 - peak <= 40.0, "the hop is a small one")
	var wave: Array[Dictionary] = []
	for hit in hits_by([&"rift_dive"]):
		if hit["target"] == behind:
			wave.append(hit)
	check(wave.size() == 1 and wave[0]["critical"] and wave[0]["damage"] == 3, "the landing wave hits a target behind the hero once, as a critical")
	check(behind.knock_count == 1, "the landing wave launches the target")
	observations["rift_hop_px"] = snappedf(160.0 - peak, 0.1)


func verify_latest_press_wins() -> void:
	var player: CharacterBody2D = arena.player
	await stage(Vector2(40, 160), Vector2(80, 160))
	await tap(LIGHT)
	await frames(2)
	await tap(LIGHT)
	await frames(1)
	await tap(HEAVY)
	check(player.queued_attack == false and player._intent_stage(&"heavy") == &"queued", "a heavy press replaces the buffered light follow-up")
	await wait_until(func() -> bool: return player.move_id != &"attack1", 90)
	check(player.move_id == &"rush_cleave", "the latest press decides the follow-up")
	await stage(Vector2(40, 160), Vector2(80, 160))
	await tap(LIGHT)
	await frames(2)
	await tap(HEAVY)
	await frames(1)
	await tap(LIGHT)
	await wait_until(func() -> bool: return player.move_id != &"attack1", 90)
	check(player.move_id == &"attack2", "a light press after a heavy one takes the follow-up back")


func dash() -> void:
	var direction := KEY_D if arena.player.facing == "right" else KEY_A
	key(direction, true)
	key(KEY_SHIFT, true)
	mouse(LIGHT, true)
	await frames(1)
	mouse(LIGHT, false)
	key(KEY_SHIFT, false)
	key(direction, false)


func verify_dodge_offset() -> void:
	var player: CharacterBody2D = arena.player
	# right after the dash: the shadow slash, a longer attack1 with afterimages, then the string goes on
	await stage(Vector2(40, 160), Vector2(300, 160))
	await dash()
	check(player.move_id == &"dash_stab", "Shift dashes")
	await wait_until(func() -> bool: return player.state != player.State.ATTACK, 60)
	await tap(LIGHT)
	await wait_until(func() -> bool: return player.is_attacking, 10)
	check(player.move_id == &"shadow_slash" and player.combo_stage == 1, "a click right after the dash gives the shadow slash in place of hit 1")
	var plain_reach := float(MOVESET.BLADE["length"]) + MOVESET.SIDE_EXTRA_REACH
	check(is_equal_approx(player.attack_box().size.x - plain_reach, 8.0), "the shadow slash reaches 8 px further than attack1")
	check(await wait_until(func() -> bool: return not player.fx.afterimages.is_empty(), 20), "the shadow slash leaves afterimages")
	await tap(LIGHT)
	check(await wait_until(func() -> bool: return player.move_id == &"attack2", 60), "the string goes on from the shadow slash into hit 2")
	# the window closes 0.25 s after the dash
	await stage(Vector2(40, 160), Vector2(300, 160))
	await dash()
	await wait_until(func() -> bool: return player.state == player.State.FREE, 60)
	await frames(18)
	await tap(LIGHT)
	check(player.move_id == &"attack1", "a click well after the dash is an ordinary attack1")
	# a click during the dash comes out at the dash's cancel frame
	await stage(Vector2(40, 160), Vector2(300, 160))
	await dash()
	await frames(3)
	await tap(LIGHT)
	check(await wait_until(func() -> bool: return player.move_id == &"shadow_slash", 40), "a click during the dash follows with the shadow slash")
	check(int(last_frame.get(&"dash_stab", -1)) == int(MOVESET.MOVES[&"dash_stab"]["cancel"]), "the shadow slash starts on the dash's cancel frame")
	# right button after the dash: the chase cleave, then H gives the launch slash
	await stage(Vector2(40, 160), Vector2(300, 160))
	await dash()
	await wait_until(func() -> bool: return player.state != player.State.ATTACK, 60)
	var chase_from := player.position.x
	await tap(HEAVY)
	await wait_until(func() -> bool: return player.is_attacking, 10)
	check(player.move_id == &"chase_cleave", "a right click right after the dash gives the chase cleave")
	check(arena.session.combat_feedback.played.back() == "swing_heavy", "the chase cleave plays the heavy swing")
	await tap(HEAVY)
	check(await wait_until(func() -> bool: return player.move_id == &"launch_slash", 60), "the chase cleave counts as a rush cleave: H follows with the launch slash")
	check(player.position.x - chase_from >= 20.0, "the chase cleave lunges further")
	observations["chase_lunge_px"] = snappedf(player.position.x - chase_from, 0.1)
	# in the air the shadow slash plays the air swing
	await stage(Vector2(40, 160), Vector2(300, 160))
	key(KEY_SPACE, true)
	await frames(2)
	key(KEY_SPACE, false)
	await frames(8)
	await dash()
	await wait_until(func() -> bool: return player.state != player.State.ATTACK, 60)
	await tap(LIGHT)
	await wait_until(func() -> bool: return player.is_attacking, 10)
	check(player.move_id == &"shadow_slash" and String(player.sprite.animation).begins_with("air_attack1"), "after an air dash the shadow slash uses the air swing")
	await wait_until(func() -> bool: return player.is_on_floor() and player.state == player.State.FREE, 180)


func verify_dash_cancel() -> void:
	var player: CharacterBody2D = arena.player
	# L L, Shift: the dash cuts hit 2 after its hit frame, and the shadow slash takes the place of hit 3
	await stage(Vector2(40, 160), Vector2(300, 160))
	check(await play_string([LIGHT, LIGHT], [&"attack1", &"attack2"]), "L L plays two hits")
	await dash()
	check(await wait_until(func() -> bool: return player.move_id == &"dash_stab", 30), "Shift + direction + fresh click during hit 2 thrusts")
	var cut := int(last_frame.get(&"attack2", -1))
	check(cut >= 6 and cut < 15, "the dash cuts hit 2 after its hit frame and before its clip ends")
	await wait_until(func() -> bool: return player.state != player.State.ATTACK, 60)
	await tap(LIGHT)
	await wait_until(func() -> bool: return player.is_attacking, 10)
	check(player.move_id == &"shadow_slash" and player.combo_stage == 3, "after the dodge the shadow slash counts as hit 3")
	await tap(LIGHT)
	check(await wait_until(func() -> bool: return player.move_id == &"thrust4", 60), "the interrupted string goes on to hit 4")
	observations["dash_cut_attack2_at"] = cut
	# Shift pressed early in a swing waits for its dodge window
	await stage(Vector2(40, 160), Vector2(300, 160))
	await tap(LIGHT)
	await frames(1)
	await dash()
	check(await wait_until(func() -> bool: return player.move_id == &"dash_stab", 40), "an early modifier thrust waits for its cancel window")
	var waited := int(last_frame.get(&"attack1", -1))
	check(waited >= 7 and waited < 15, "an early Shift waits for hit 1's dodge window")
	# heavy swings are not cut by the dash
	await stage(Vector2(40, 160), Vector2(300, 160))
	await tap(HEAVY)
	await frames(2)
	await dash()
	await wait_until(func() -> bool: return player.state == player.State.FREE, 120)
	check(moves_seen == [&"rush_cleave"] and int(last_frame.get(&"rush_cleave", -1)) >= 14, "a dash press does not cut the rush cleave")
	observations["rush_then_shift"] = {"moves": moves_seen.map(func(id: StringName) -> String: return String(id)), "last_frame": last_frame.get(&"rush_cleave", -1)}


func jump() -> void:
	key(KEY_SPACE, true)
	await frames(2)
	key(KEY_SPACE, false)


func verify_air_spin() -> void:
	var player: CharacterBody2D = arena.player
	# right click in the air, next to a hovering drone whose attack is switched off
	await stage(Vector2(60, 160), Vector2(300, 160))
	var bag: CharacterBody2D = arena.add_attacker(Vector2(300, 100))
	bag.attacker.set_physics_process(false)
	bag.max_hp = 30
	bag.hp = 30
	await jump()
	await frames(10)
	bag.position = player.position + Vector2(16, -14)
	await tap(HEAVY)
	check(player.move_id == &"air_spin_a", "a right click in the air starts the aerial spin")
	var start_y := player.position.y
	var lowest := start_y
	var ticks := 0
	while player.move_id in [&"air_spin_a", &"air_spin_b", &"air_spin_c"] and ticks < 90:
		lowest = maxf(lowest, player.position.y)
		ticks += 1
		await frames(1)
	check(moves_seen.slice(-3) == [&"air_spin_a", &"air_spin_b", &"air_spin_c"], "the aerial spin plays its three parts")
	var spin := hits_by([&"air_spin_a", &"air_spin_b", &"air_spin_c"])
	check(spin.size() == 3 and not spin[0]["critical"] and not spin[1]["critical"] and spin[2]["critical"], "the aerial spin hits three times, the last one critical")
	check(arena.completed_stop_requests.slice(-3) == [2, 2, 6], "the middle spin hits stop 2 frames, the last one 6")
	check(ticks >= 30 and ticks <= 46, "the spin keeps the hero up for about 0.6 s")
	check(lowest - start_y <= 6.0, "the spin holds the hero in the air")
	check(arc_pixels >= 8, "the aerial spin draws a blade circle")
	check(not player.is_on_floor() and player._air_hold_left > 0.0, "the hero hangs on after the spin")
	key(KEY_S, true)
	await frames(1)
	key(KEY_S, false)
	check(player.special_kind == "dive_slash", "the dive slash follows the spin")
	observations["air_spin"] = {"ticks": ticks, "drop_px": snappedf(lowest - start_y, 0.1), "stops": arena.completed_stop_requests.duplicate()}
	await wait_until(func() -> bool: return player.is_on_floor() and player.state == player.State.FREE, 180)
	# a fourth click after the air string: the aerial spin, never the ground thrust
	await stage(Vector2(60, 160), Vector2(300, 160))
	await jump()
	await frames(6)
	check(await play_string([LIGHT, LIGHT, LIGHT, LIGHT], [&"attack1", &"attack2", &"attack3", &"air_spin_a"]), "a fourth click after the air string starts the aerial spin")
	check(&"thrust4" not in moves_seen, "the air string never continues into the ground thrust")
	await wait_until(func() -> bool: return player.is_on_floor() and player.state == player.State.FREE, 180)
	arena.attackers.erase(bag)
	bag.queue_free()
	# on the floor the right click is still the rush cleave
	await stage(Vector2(60, 160), Vector2(300, 160))
	await tap(HEAVY)
	check(player.move_id == &"rush_cleave", "on the floor a right click is still the rush cleave")


# W held, then a click of `button`; W is let go afterwards.
func with_w(button: MouseButton) -> void:
	key(KEY_W, true)
	await frames(1)
	await tap(button)
	key(KEY_W, false)


func verify_leap_cleave() -> void:
	var player: CharacterBody2D = arena.player
	var played: Array = arena.session.combat_feedback.played
	# into empty air: forward leap, small apex, about 0.4 s up, lands with its effects even on a miss
	await stage(Vector2(40, 160), Vector2(300, 160))
	var start_x := player.position.x
	var sounds_before := played.size()
	await with_w(HEAVY)
	check(player.move_id == &"leap_cleave" and player.special_kind == "leap_cleave", "W + right click on the floor starts the leap cleave")
	check(played.slice(sounds_before).has("swing_heavy"), "the leap takes off with the heavy swing")
	var peak := player.position.y
	var airborne := 0
	for _index in range(60):
		if player.is_on_floor() and airborne > 0:
			break
		if not player.is_on_floor():
			airborne += 1
		peak = minf(peak, player.position.y)
		await frames(1)
	var travel := player.position.x - start_x
	check(player.is_on_floor(), "the leap cleave lands")
	check(travel >= 40.0, "the leap carries the hero at least 40 px forward")
	check(160.0 - peak >= 10.0 and 160.0 - peak <= 20.0, "the leap rises about half a body")
	check(airborne >= 20 and airborne <= 32, "the leap stays up about 0.4 s")
	check(moves_seen.slice(-2) == [&"leap_cleave", &"leap_cleave_chop"], "the leap turns into the chop on the way down")
	var landing_effects: Array = player.fx.effects.filter(func(effect: Dictionary) -> bool: return effect["color"] == player.PLAYER_FX.DUST and Vector2(effect["velocity"]).y < -40.0)
	check(landing_effects.size() >= 8, "the landing throws up dust columns even on a miss")
	check(hits_seen.is_empty() and arena.completed_stop_requests.is_empty(), "a missed leap hits nothing and stops nothing")
	observations["leap"] = {"travel_px": snappedf(travel, 0.1), "apex_px": snappedf(160.0 - peak, 0.1), "air_ticks": airborne}
	await wait_until(func() -> bool: return player.state == player.State.FREE, 60)
	check(player.state == player.State.FREE, "the hero recovers after the landing")
	# a target where the hero comes down: the chop hits it once, 2x, heavy stop, and bounces it up
	await stage(Vector2(40, 160), Vector2(92, 160))
	var target: CharacterBody2D = arena.targets[0]
	await with_w(HEAVY)
	await wait_until(func() -> bool: return player.is_on_floor() and player.state != player.State.ATTACK, 90)
	var hits := hits_by([&"leap_cleave_chop"])
	check(hits.size() == 1 and hits[0]["target"] == target and hits[0]["damage"] == 2 and not hits[0]["critical"], "a target at the landing point takes one 2x hit")
	check(arena.completed_stop_requests == [10], "the hit holds the 10-frame heavy stop")
	check(target.knock_count == 1, "the hit bounces the target up for an air combo")
	check(played.has("hit_heavy"), "the hit plays the heavy impact sound")
	# the landing wave: a target beside the landing spot is hit by the wave, one farther away is not
	await stage(Vector2(40, 160), Vector2(300, 160), Vector2(300, 160))
	var near: CharacterBody2D = arena.targets[0]
	var far: CharacterBody2D = arena.targets[1]
	await with_w(HEAVY)
	# they step in behind once the hero has flown past (the leap is too low to clear a standing target)
	await wait_until(func() -> bool: return player.position.x >= start_x + travel - 8.0 or player.is_on_floor() and player.move_id != &"leap_cleave", 40)
	near.position = Vector2(start_x + travel - 21.0, 160)
	far.position = Vector2(start_x + travel - 42.0, 160)
	await wait_until(func() -> bool: return player.is_on_floor() and player.state != player.State.ATTACK, 90)
	await wait_until(func() -> bool: return not arena.hit_stop_active, 30)
	var wave := hits_by([&"leap_cleave_chop"])
	check(wave.size() == 1 and wave[0]["target"] == near and wave[0]["damage"] == 2, "the landing wave hits a target within 24 px along the floor, 2x")
	check(near.knock_count == 1 and far.hp == far.max_hp, "the wave bounces the near target and leaves the far one alone")
	check(arena.completed_stop_requests == [10], "the wave hit holds the 10-frame heavy stop")
	observations["leap_wave"] = {"hits": wave.map(func(hit: Dictionary) -> String: return "%s %d" % ["near" if hit["target"] == near else "other", hit["damage"]]), "landed_x": snappedf(player.position.x, 0.1)}
	# the other buttons keep their moves
	await stage(Vector2(40, 160), Vector2(300, 160))
	await with_w(LIGHT)
	check(player.special_kind == "rising_slash", "W + left click is still the rising slash")
	await stage(Vector2(40, 160), Vector2(300, 160))
	await tap(HEAVY)
	check(player.move_id == &"rush_cleave", "a right click without W is still the rush cleave")
	await stage(Vector2(40, 160), Vector2(300, 160))
	await jump()
	await frames(8)
	key(KEY_W, true)
	await tap(HEAVY)
	key(KEY_W, false)
	check(player.move_id == &"air_spin_a", "W + right click in the air is still the aerial spin")
	await wait_until(func() -> bool: return player.is_on_floor() and player.state == player.State.FREE, 180)


func verify_limits() -> void:
	var player: CharacterBody2D = arena.player
	# crouching: the right button does nothing
	await stage(Vector2(40, 160), Vector2(80, 160))
	key(KEY_S, true)
	await frames(8)
	await tap(HEAVY)
	await frames(2)
	check(player.is_crouching and not player.is_attacking, "a right click while crouching does nothing")
	key(KEY_S, false)
	await frames(12)
	# top-down: no heavy, and the light string stops at three
	arena.build_arena(0)
	await frames(6)
	player = arena.player
	player.move_started.connect(func(id: StringName) -> void: moves_seen.append(id))
	moves_seen.clear()
	await tap(HEAVY)
	await frames(2)
	check(not player.is_attacking, "the top-down view has no heavy attack")
	check(await play_string([LIGHT, LIGHT, LIGHT], [&"attack1", &"attack2", &"attack3"]), "the top-down string plays three hits")
	await tap(LIGHT)
	await wait_until(func() -> bool: return player.state == player.State.FREE, 180)
	check(moves_seen.slice(0, 3) == [&"attack1", &"attack2", &"attack3"] and &"thrust4" not in moves_seen, "the top-down light string still stops at three")
	observations["top_down_moves"] = moves_seen.map(func(id: StringName) -> String: return String(id))


func finish() -> void:
	for code in [KEY_SPACE, KEY_S]:
		key(code, false)
	mouse(LIGHT, false)
	mouse(HEAVY, false)
	var report := {"suite": "rhythm_combat", "status": "passed" if failures.is_empty() else "failed", "checks": checks,
		"failures": failures, "observations": observations}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
