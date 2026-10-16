extends "res://tests/support/isolated_suite.gd"
## Real-GPU capture of the NieR-style rhythm system in the night street: the five-hit light string, heavy finishers,
## dodge offsets and the aerial spin on a hover drone, then a hover drone's own attack: a hit taken, a perfect dodge,
## the slow motion and the counter. Run windowed:
##   godot --path game --fixed-fps 60 --script res://tests/recorders/record_night_street_rhythm.gd
## Output: res://evidence/night_street_rhythm/ (stills, frames/NNNN.png every second physics tick, capture_report.json
## with the sound timeline and per-segment moves). tools/art_qa/compose_combat_capture.py makes the MP4.

const SCENE = preload("res://scenes/night_street_proto.tscn")
const OUTPUT := "res://evidence/night_street_rhythm/"
const L := MOUSE_BUTTON_LEFT
const H := MOUSE_BUTTON_RIGHT
# W held while the right button is clicked: the leap cleave.
const LEAP := -1
# name, presses (mouse buttons or keys), the move each press should start (&"" = none, for a jump)
const SEGMENTS := [
	["light_x5", [L, L, L, L, L], [&"attack1", &"attack2", &"attack3", &"thrust4", &"spin5a"]],
	["light3_heavy", [L, L, L, H], [&"attack1", &"attack2", &"attack3", &"spin_cleave_a"]],
	["light4_heavy", [L, L, L, L, H], [&"attack1", &"attack2", &"attack3", &"thrust4", &"rift_hop"]],
	["heavy_heavy", [H, H], [&"rush_cleave", &"launch_slash"]],
	["dash_light", [KEY_SHIFT, L, L], [&"dash_stab", &"shadow_slash", &"attack2"]],
	["air_spin", [KEY_SPACE, H], [&"", &"air_spin_a"]],
	["leap_cleave", [LEAP], [&"leap_cleave"]],
]
var street: Node2D
var session: Node
var feedback: Node
var player: CharacterBody2D
var targets: Array = []
var frame_number := 0
var physics_count := 0
var _sounds_seen := 0
var _moves: Array = []
var report: Dictionary = {"stills": [], "sounds": [], "segments": []}


func _initialize() -> void:
	create_timer(150.0).timeout.connect(func() -> void: quit(2))
	call_deferred("run")


func mouse(button: int, pressed: bool) -> void:
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


func press(code: int) -> void:
	if code == LEAP:
		key(KEY_W, true)
		mouse(H, true)
		await tick(2)
		mouse(H, false)
		key(KEY_W, false)
	elif code > MOUSE_BUTTON_XBUTTON2:
		key(code, true)
		await tick(2)
		key(code, false)
	else:
		mouse(code, true)
		await tick(2)
		mouse(code, false)


func tick(count := 1) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame
		physics_count += 1
		street.drone.position.x = 940.0
		while _sounds_seen < feedback.played.size():
			report["sounds"].append({"sound": feedback.played[_sounds_seen], "seconds": physics_count / 60.0})
			_sounds_seen += 1
		if physics_count % 2 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + "frames/%04d.png" % frame_number)
			frame_number += 1


func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + name + ".png")
	report["stills"].append(name)


func wait_for(condition: Callable, limit: int) -> bool:
	for _index in range(limit):
		if condition.call():
			return true
		await tick()
	return condition.call()


func settle() -> void:
	await wait_for(func() -> bool: return player.state == player.State.FREE and player.is_on_floor() and not session.hit_stop_active, 240)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "frames"))
	street = SCENE.instantiate()
	root.add_child(street)
	current_scene = street
	for _index in range(20):
		await physics_frame
	session = street.get_node("GameSession")
	feedback = session.get_node("CombatFeedback")
	player = street.player
	player.critical_roll_override = 0.99
	player.move_started.connect(func(id: StringName) -> void: _moves.append(String(id)))
	targets = street.get_node("World").get_children().filter(func(node: Node) -> bool: return node.has_method("take_damage"))
	# combos on the first drone with its attack off and plenty of hit points
	var bag: Node = targets[0]
	bag.attacker.set_physics_process(false)
	for entry in SEGMENTS:
		await settle()
		bag.max_hp = 40
		bag.hp = 40
		player.position = Vector2(bag.global_position.x - (64.0 if entry[1][0] == KEY_SHIFT else (56.0 if entry[1][0] == LEAP else 22.0)), 156)
		player.velocity = Vector2.ZERO
		player.facing = "right"
		player.show_idle()
		await tick(26)
		_moves.clear()
		var presses: Array = entry[1]
		var expected: Array = entry[2]
		for index in range(presses.size()):
			await press(presses[index])
			if presses[index] == KEY_SPACE:
				await tick(3)
				continue
			await wait_for(func() -> bool: return player.move_id == expected[index], 60)
		await settle()
		await tick(10)
		report["segments"].append({"name": entry[0], "moves": _moves.duplicate()})
	# the second drone fights back: a hit taken, then a perfect dodge, the slow motion and the counter
	var foe: Node = targets[1]
	var attacker: Node = foe.attacker
	var results: Array = []
	player.attack_received.connect(func(result: int, _attack: Dictionary) -> void: results.append(["HIT", "EVADE", "PERFECT"][result]))
	await settle()
	foe.hp = foe.max_hp
	player.position = Vector2(foe.global_position.x - 44.0, 156)
	player.velocity = Vector2.ZERO
	player.facing = "right"
	player.show_idle()
	await wait_for(func() -> bool: return attacker.phase == attacker.Phase.TELEGRAPH, 60)
	await tick(10)
	await still("drone_telegraph")
	await wait_for(func() -> bool: return not results.is_empty(), 60)
	await tick(3)
	await still("hit_taken")
	await settle()
	# stand 44 px from the drone's post (it may still be drifting back) until it blinks again
	for _index in range(300):
		if attacker.phase == attacker.Phase.TELEGRAPH:
			break
		player.position = Vector2(attacker.post.x - 44.0, 156)
		player.velocity = Vector2.ZERO
		player.facing = "right"
		await tick()
	await wait_for(func() -> bool: return attacker.phase_time >= 0.42, 60)
	await press(KEY_SHIFT)
	await wait_for(func() -> bool: return results.size() >= 2, 40)
	await tick(18)
	await still("slow_motion")
	await press(L)
	await wait_for(func() -> bool: return session.hit_stop_active, 40)
	await tick(1)
	await still("counter")
	await settle()
	await tick(40)
	report["attack_results"] = results
	report["foe_hp_after_counter"] = foe.hp
	report["frames"] = frame_number
	report["fps"] = 30
	report["stops"] = session.completed_stop_frames
	var file := FileAccess.open(OUTPUT + "capture_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	quit(0)
