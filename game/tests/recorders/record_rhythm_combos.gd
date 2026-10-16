extends "res://tests/support/isolated_suite.gd"
## Real-GPU capture of the light / heavy combo graph through the shipped GameSession path: hospital side view,
## a fixture target in front (and one behind for the rift slash). Strings: L x5, H, H H, L-H, L L-H, L L L-H,
## L L L L-H, the dodge offsets Shift-L-L, L L-Shift-L-L, Shift-H-H, the aerial spin (jump-H, jump-L L L L)
## around a hovering drone whose attack is off, and the leap cleave (W+H). Run windowed:
##   godot --path game --fixed-fps 60 --script res://tests/recorders/record_rhythm_combos.gd
## Output: res://evidence/rhythm_combos/ (stills, frames/NNNN.png every second physics tick, capture_report.json
## with the sound timeline and per-string moves / hits / stops). tools/art_qa/compose_combat_capture.py makes the MP4.

const HOSPITAL = preload("res://scenes/underground_hospital.tscn")
const TARGET = preload("res://tests/fixtures/training_target.gd")
const DRONE = preload("res://tests/fixtures/attack_drone.gd")
const OUTPUT := "res://evidence/rhythm_combos/"
const L := MOUSE_BUTTON_LEFT
const H := MOUSE_BUTTON_RIGHT
# W held while the right button is clicked.
const LEAP := -1
const STRINGS := [
	["light_x5", [L, L, L, L, L], [&"attack1", &"attack2", &"attack3", &"thrust4", &"spin5a"]],
	["heavy", [H], [&"rush_cleave"]],
	["heavy_heavy", [H, H], [&"rush_cleave", &"launch_slash"]],
	["light_heavy", [L, H], [&"attack1", &"rush_cleave"]],
	["light2_heavy", [L, L, H], [&"attack1", &"attack2", &"launch_slash"]],
	["light3_heavy", [L, L, L, H], [&"attack1", &"attack2", &"attack3", &"spin_cleave_a"]],
	["light4_heavy", [L, L, L, L, H], [&"attack1", &"attack2", &"attack3", &"thrust4", &"rift_hop"]],
	["dash_light", [KEY_SHIFT, L, L], [&"dash_stab", &"shadow_slash", &"attack2"]],
	["light2_dash_light", [L, L, KEY_SHIFT, L, L], [&"attack1", &"attack2", &"dash_stab", &"shadow_slash", &"thrust4"]],
	["dash_heavy", [KEY_SHIFT, H, H], [&"dash_stab", &"chase_cleave", &"launch_slash"]],
	["air_heavy", [KEY_SPACE, H], [&"", &"air_spin_a"]],
	["air_light4", [KEY_SPACE, L, L, L, L], [&"", &"attack1", &"attack2", &"attack3", &"air_spin_a"]],
	["leap_cleave", [LEAP], [&"leap_cleave"]],
]
# A still is taken the first time each of these moves reaches the frame.
const STILLS := {&"spin5a": 7, &"spin5b": 9, &"rush_cleave": 7, &"launch_slash": 6, &"spin_cleave_b": 7, &"rift_dive": 7}
var hospital: Node2D
var feedback: Node
var session: Node
var player: CharacterBody2D
var front: CharacterBody2D
var behind: CharacterBody2D
var bag: CharacterBody2D
var frame_number := 0
var physics_count := 0
var _sounds_seen := 0
var _stills_taken: Dictionary = {}
var report: Dictionary = {"stills": [], "sounds": [], "strings": []}
var _moves: Array = []
var _hits: Array = []


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(2))
	call_deferred("run")


func mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = Vector2(160, 90)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# A mouse button, or a key (codes above the mouse range) such as Shift for the dash.
func press(button: int, pressed: bool) -> void:
	if button == LEAP:
		if pressed:
			key(KEY_W, true)
		mouse(H, pressed)
		if not pressed:
			key(KEY_W, false)
	elif button > MOUSE_BUTTON_XBUTTON2:
		key(button, pressed)
	else:
		mouse(button, pressed)


func tick(count := 1) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame
		physics_count += 1
		while _sounds_seen < feedback.played.size():
			report["sounds"].append({"sound": feedback.played[_sounds_seen], "seconds": physics_count / 60.0})
			_sounds_seen += 1
		if physics_count % 2 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + "frames/%04d.png" % frame_number)
			frame_number += 1
		if player.is_attacking and STILLS.has(player.move_id) and not _stills_taken.has(player.move_id) and player.sprite.frame >= STILLS[player.move_id]:
			_stills_taken[player.move_id] = true
			await still(String(player.move_id))


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


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "frames"))
	hospital = HOSPITAL.instantiate()
	root.add_child(hospital)
	current_scene = hospital
	for _index in range(10):
		await physics_frame
	hospital.call("switch_view")
	for _index in range(20):
		await physics_frame
	session = hospital.get_node("GameSession")
	feedback = session.get_node("CombatFeedback")
	player = hospital.player
	player.facing = "right"
	player.show_idle()
	player.critical_roll_override = 0.99
	player.move_started.connect(func(id: StringName) -> void: _moves.append(String(id)))
	player.hit_resolved.connect(func(target: Node, damage: int, critical: bool, _kind: String) -> void:
		_hits.append({"move": String(player.move_id), "target": "front" if target == front else ("behind" if target == behind else "drone"), "damage": damage, "critical": critical}))
	var base := player.global_position
	report["base"] = [base.x, base.y]
	front = add_target()
	behind = add_target()
	bag = DRONE.new()
	bag.max_hp = 99
	hospital.world.add_child(bag)
	bag.attacker.set_physics_process(false)
	bag.hp = 99
	for entry in STRINGS:
		await play(entry, base)
	report["frames"] = frame_number
	report["fps"] = 30
	report["stops"] = session.completed_stop_frames
	var file := FileAccess.open(OUTPUT + "capture_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	quit(0)


func add_target() -> CharacterBody2D:
	var target := TARGET.new()
	target.side_view = true
	target.max_hp = 99
	hospital.world.add_child(target)
	target.hp = 99
	return target


func play(entry: Array, base: Vector2) -> void:
	await wait_for(func() -> bool: return player.state == player.State.FREE and player.is_on_floor() and not session.hit_stop_active, 180)
	player.position = base
	player.velocity = Vector2.ZERO
	player.facing = "right"
	player.show_idle()
	# the dash carries the hero 48 px, so the dodge strings put the target past the dash end
	front.position = base + Vector2(78 if KEY_SHIFT in entry[1] else (56 if LEAP in entry[1] else 34), 0)
	front.velocity = Vector2.ZERO
	front.hp = 99
	# the second target only stands in for the rift slash: it steps in behind the hero once the thrust starts
	behind.position = base + Vector2(-200, 0)
	# the air strings swing at a hovering drone at jump height instead
	var airborne: bool = KEY_SPACE in entry[1]
	bag.position = base + (Vector2(18, -44) if airborne else Vector2(-240, -40))
	bag.hp = 99
	if airborne:
		front.position = base + Vector2(-220, 0)
	behind.velocity = Vector2.ZERO
	behind.hp = 99
	# 24 ticks also let the previous string's dodge-offset window close
	await tick(24)
	_moves.clear()
	_hits.clear()
	var stops_before: int = session.completed_stop_frames.size()
	var buttons: Array = entry[1]
	var expected: Array = entry[2]
	for index in range(buttons.size()):
		press(buttons[index], true)
		await tick(2)
		press(buttons[index], false)
		if buttons[index] == KEY_SPACE:
			await tick(12)
		await wait_for(func() -> bool: return player.move_id == expected[index], 60)
		if entry[0] == "light4_heavy" and index == 3:
			behind.position = player.global_position - Vector2(22, 0)
	await wait_for(func() -> bool: return player.state == player.State.FREE and player.is_on_floor(), 180)
	await tick(30)
	report["strings"].append({"name": entry[0], "moves": _moves.duplicate(), "hits": _hits.duplicate(),
		"stops": session.completed_stop_frames.slice(stops_before)})
