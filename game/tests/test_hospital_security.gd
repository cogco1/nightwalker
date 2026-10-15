extends SceneTree

const HOSPITAL = preload("res://scenes/underground_hospital.tscn")
const DOORS := [
	{"id": "storage_door", "floor": 1, "room": "storage", "rect": Rect2(523, 82, 30, 10), "direction": 1},
	{"id": "treatment_door", "floor": 2, "room": "treatment", "rect": Rect2(283, 135, 33, 10), "direction": -1},
	{"id": "office_door", "floor": 2, "room": "office", "rect": Rect2(486, 135, 32, 10), "direction": -1}
]

var hospital: Node2D
var security: Node2D
var story_state: Node
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var _finished := false


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		check(false, "Hospital security suite completes before its deadline")
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


func key(code: int, pressed: bool, character := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = character
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func release() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_J, KEY_E, KEY_R, KEY_TAB, KEY_ENTER, KEY_ESCAPE, KEY_BACKSPACE, KEY_0, KEY_1, KEY_2, KEY_CAPSLOCK, KEY_F7]:
		key(code, false)


func tap(code: int, character := 0) -> void:
	key(code, true, character)
	await frames(2)
	key(code, false, character)
	await frames(2)


func type_digits(digits: String) -> void:
	var edit: LineEdit = security.get("_code_edit")
	edit.grab_focus()
	for index in range(digits.length()):
		var character := digits.unicode_at(index)
		await tap(character, character)


func clear_code() -> void:
	var edit: LineEdit = security.get("_code_edit")
	edit.grab_focus()
	for _index in range(4):
		await tap(KEY_BACKSPACE)


func close_ui() -> void:
	release()
	if is_instance_valid(security) and bool(security.get("keypad_active")):
		security.call("close_keypad")
	if is_instance_valid(hospital) and hospital.interactions.dialogue_active:
		hospital.interactions.close_dialogue()


func place(point: Vector2) -> void:
	close_ui()
	hospital.player.position = point
	hospital.player.velocity = Vector2.ZERO
	await frames(4)


func walk(code: Key, count: int) -> Vector2:
	key(code, true)
	await frames(count)
	key(code, false)
	await frames(6)
	return hospital.player.position


func door_body(id: String) -> StaticBody2D:
	return hospital.world.get_node_or_null(NodePath("SecurityDoor_" + id)) as StaticBody2D


func activate_top(door: Dictionary) -> void:
	close_ui()
	hospital.floor_id = int(door["floor"])
	var rectangle: Rect2 = door["rect"]
	var down := int(door["direction"]) > 0
	var point := Vector2(rectangle.get_center().x, rectangle.position.y - 17.0 if down else rectangle.end.y + 19.0)
	hospital.call("_activate_view", 0, String(door["room"]), point)
	await frames(5)
	security = hospital.get("security")


func verify_door(door: Dictionary) -> void:
	var id := String(door["id"])
	var rectangle: Rect2 = door["rect"]
	var down := int(door["direction"]) > 0
	var inward: Key = KEY_S if down else KEY_W
	var outward: Key = KEY_W if down else KEY_S
	await activate_top(door)
	var body := door_body(id)
	check(body != null and body.collision_layer == 1, id + " starts with a real closed collision body in the doorway")
	check(not bool(security.call("is_door_unlocked", id)) and not bool(story_state.call("has_flag", "door:" + id)), id + " starts locked in the shared story state")
	check(bool(security.call("is_position_blocked", rectangle.get_center(), int(door["floor"]))), id + " contributes to top-down position clearance")
	var stopped := await walk(inward, 55)
	var north_limit := rectangle.position.y
	var south_limit := rectangle.end.y + 8.0
	check(stopped.y <= north_limit + 0.25 if down else stopped.y >= south_limit - 0.25, id + " physically stops the original player approaching from the corridor")
	observations[id + "_closed_corridor_stop"] = [stopped.x, stopped.y]
	var inner_y := rectangle.end.y + 11.0 if down else rectangle.position.y - 3.0
	await place(Vector2(rectangle.get_center().x, inner_y))
	var reverse_stopped := await walk(outward, 40)
	check(reverse_stopped.y >= south_limit - 0.25 if down else reverse_stopped.y <= north_limit + 0.25, id + " also blocks a player approaching from the room side")
	await activate_top(door)
	body = door_body(id)
	await walk(inward, 45)
	await tap(KEY_E)
	check(bool(security.get("keypad_active")) and String(security.get("active_door_id")) == id, id + " physical E opens its nearby password keypad")
	var edit: LineEdit = security.get("_code_edit")
	var status: Label = security.get("_status")
	check(edit != null and edit.has_focus(), id + " gives the real LineEdit keyboard focus")
	check(not status.text.contains("1010") and not edit.placeholder_text.contains("1010"), id + " does not disclose the accepted code in its instructions")
	var frozen_position: Vector2 = hospital.player.position
	key(KEY_D, true)
	key(KEY_J, true)
	await frames(8)
	key(KEY_D, false)
	key(KEY_J, false)
	check(hospital.player.position.distance_to(frozen_position) < 0.1 and not hospital.player.is_attacking, id + " freezes both movement and attacks while entering a password")
	await tap(KEY_TAB)
	await tap(KEY_R)
	check(hospital.view_mode == 0 and bool(security.get("keypad_active")) and hospital.player.position.distance_to(frozen_position) < 0.1, id + " blocks view switching and resetting while its keypad is active")
	await clear_code()
	await type_digits("0000")
	check(edit.text == "0000", id + " receives numeric characters through actual keyboard input")
	await tap(KEY_ENTER)
	check(bool(security.get("keypad_active")) and not bool(security.call("is_door_unlocked", id)) and body.collision_layer == 1, id + " rejects an incorrect code without removing its collision")
	check(not status.text.is_empty(), id + " supplies visible feedback after rejecting the wrong code")
	await tap(KEY_ESCAPE)
	check(not bool(security.get("keypad_active")) and hospital.player.is_physics_processing() and hospital.player.process_mode != Node.PROCESS_MODE_DISABLED, id + " Escape cancels password entry and restores the player")
	check(not bool(security.call("is_door_unlocked", id)) and body.collision_layer == 1, id + " cancelling never unlocks the doorway")
	await walk(inward, 20)
	var after_cancel: Vector2 = hospital.player.position
	check(after_cancel.y <= north_limit + 0.25 if down else after_cancel.y >= south_limit - 0.25, id + " remains physically impassable after a cancelled attempt")
	await tap(KEY_E)
	await clear_code()
	await type_digits("1010")
	check(edit.text == "1010", id + " accepts all four correct digits from keyboard events")
	await tap(KEY_ENTER)
	check(bool(security.call("is_door_unlocked", id)) and bool(story_state.call("has_flag", "door:" + id)), id + " records successful authentication in shared story state")
	check(body.collision_layer == 1, id + " keeps its physical barrier until the sliding animation finishes")
	await frames(24)
	check(not bool(security.get("keypad_active")) and body.collision_layer == 0, id + " automatically finishes opening and removes the physical barrier")
	check(not bool(security.call("is_position_blocked", rectangle.get_center(), int(door["floor"]))), id + " removes the opened door from clearance queries")
	check(hospital.player.is_physics_processing() and hospital.player.process_mode != Node.PROCESS_MODE_DISABLED, id + " returns control after a successful unlock")
	var crossed := await walk(inward, 47)
	check(crossed.y > rectangle.end.y + 8.0 if down else crossed.y < rectangle.position.y - 1.0, id + " lets the real player walk through the opened doorway")
	var returned := await walk(outward, 47)
	check(returned.y < rectangle.position.y if down else returned.y > rectangle.end.y + 8.0, id + " remains freely traversable in the return direction")
	observations[id + "_opened_route"] = {"inside": [crossed.x, crossed.y], "returned": [returned.x, returned.y]}


func verify_breaker() -> void:
	close_ui()
	hospital.call("_activate_view", 0, "entry", Vector2(116, 157))
	await frames(5)
	check(not bool(security.call("has_item", "breaker_key")) and not bool(security.call("is_breaker_unlocked")), "The top-down power cabinet begins locked without an invented key pickup")
	var initial_power := bool(hospital.interactions.power_states.get("clinical", true))
	await tap(KEY_E)
	check(hospital.interactions.dialogue_active and hospital.interactions.current_interaction == "breaker", "E at the locked cabinet opens its existing story dialogue")
	var text := ""
	for page in hospital.interactions.get("_pages"):
		text += String(page)
	check(text.contains("钥匙"), "The locked cabinet explains that a key is needed")
	check(bool(hospital.interactions.power_states.get("clinical", true)) == initial_power and not bool(security.call("is_breaker_unlocked")), "Inspecting the cabinet without its key neither opens it nor changes power")
	await tap(KEY_ESCAPE)
	security.call("grant_item", "breaker_key")
	check(bool(security.call("has_item", "breaker_key")) and bool(story_state.call("has_item", "breaker_key")), "The reserved grant_item API updates the shared inventory")
	await tap(KEY_E)
	check(bool(security.call("is_breaker_unlocked")) and bool(story_state.call("has_flag", "breaker_unlocked")), "The key opens the cabinet and persists its unlocked state")
	check(bool(hospital.interactions.power_states.get("clinical", true)) != initial_power, "The first keyed cabinet interaction also switches clinical power")
	check(bool(story_state.call("has_item", "breaker_key")), "Opening the cabinet does not consume the reserved key")
	await tap(KEY_ESCAPE)
	await tap(KEY_E)
	check(bool(hospital.interactions.power_states.get("clinical", true)) == initial_power, "The opened cabinet can switch clinical power back on")
	await tap(KEY_ESCAPE)
	await tap(KEY_E)
	check(not bool(hospital.interactions.power_states.get("clinical", true)), "The cabinet can be left off for the cross-scene persistence test")
	await tap(KEY_ESCAPE)


func verify_side_view_before_unlocks() -> void:
	hospital.call("_activate_view", 1, "storage", Vector2(510, 286))
	await frames(10)
	var no_security_bodies := true
	for door in DOORS:
		no_security_bodies = no_security_bodies and door_body(String(door["id"])) == null
	check(no_security_bodies, "Top-down password doors do not add collision barriers to the side projection")
	var crossed := await walk(KEY_D, 45)
	check(crossed.x > 545.0 and hospital.player.is_on_floor(), "Side-view D still walks freely through the existing storage route")
	security.call("open_keypad", "storage_door")
	check(not bool(security.get("keypad_active")), "The top-down keypad cannot activate while in side view")
	hospital.call("_activate_view", 1, "entry", Vector2(71, 286))
	await frames(8)
	var before := bool(hospital.interactions.power_states.get("clinical", true))
	await tap(KEY_E)
	check(hospital.interactions.current_interaction == "breaker" and bool(hospital.interactions.power_states.get("clinical", true)) != before, "Side-view breaker interaction preserves its former key-free behavior")
	check(not bool(security.call("has_item", "breaker_key")) and not bool(security.call("is_breaker_unlocked")), "Using the side-view switch does not invent a key or unlock the top-down cabinet")
	await tap(KEY_ESCAPE)
	await tap(KEY_E)
	check(bool(hospital.interactions.power_states.get("clinical", true)) == before, "The old side-view switch can also restore its lighting section")
	await tap(KEY_ESCAPE)


func verify_persistence() -> void:
	close_ui()
	hospital.call("_activate_view", 0, "entry", Vector2(74, 174))
	await frames(5)
	await tap(KEY_E)
	check(hospital.floor_id == 2 and hospital.view_mode == 0, "Existing staircase E still reaches the upper floor after using the security system")
	for id in ["treatment_door", "office_door"]:
		var body := door_body(id)
		check(bool(security.call("is_door_unlocked", id)) and body != null and body.collision_layer == 0, id + " rebuilds open when revisiting its floor")
	await tap(KEY_TAB)
	await tap(KEY_TAB)
	check(hospital.floor_id == 2 and hospital.view_mode == 0 and bool(security.call("has_item", "breaker_key")), "View round trips preserve the actual floor and reserved inventory")
	check(bool(security.call("is_breaker_unlocked")) and not bool(hospital.interactions.power_states.get("clinical", true)), "Cabinet unlock and power state survive projection changes")
	await place(Vector2(71, 124))
	await tap(KEY_E)
	check(hospital.floor_id == 1 and door_body("storage_door") != null and door_body("storage_door").collision_layer == 0, "Returning downstairs retains the opened storage door")
	var story_instance := story_state.get_instance_id()
	await tap(KEY_F7)
	check(current_scene.scene_file_path == "res://scenes/home_601.tscn", "F7 can still leave the hospital for the safehouse")
	await tap(KEY_F7)
	hospital = current_scene as Node2D
	security = hospital.get("security")
	story_state = root.get_node("NightwalkerStoryState")
	check(current_scene.scene_file_path == "res://scenes/underground_hospital.tscn" and story_state.get_instance_id() == story_instance, "F7 returns to a fresh hospital using the same session story state")
	var all_unlocked := true
	for door in DOORS:
		all_unlocked = all_unlocked and bool(security.call("is_door_unlocked", String(door["id"])))
	check(all_unlocked and bool(security.call("has_item", "breaker_key")), "All three password unlocks and the key survive a real scene round trip")
	check(bool(security.call("is_breaker_unlocked")) and not bool(hospital.interactions.power_states.get("clinical", true)), "The opened cabinet and chosen clinical power state survive leaving the hospital")
	check(door_body("storage_door") != null and door_body("storage_door").collision_layer == 0, "The reloaded scene reconstructs its storage doorway without a closed barrier")
	observations["persistent_state"] = {"key": security.call("has_item", "breaker_key"), "cabinet_open": security.call("is_breaker_unlocked"), "clinical_power": hospital.interactions.power_states.get("clinical", true)}


func run() -> void:
	hospital = HOSPITAL.instantiate()
	root.add_child(hospital)
	current_scene = hospital
	await frames(6)
	security = hospital.get("security")
	story_state = root.get_node_or_null("NightwalkerStoryState")
	check(security != null and story_state != null, "The real hospital exposes security and a session-wide story-state service")
	if security == null or story_state == null:
		finish()
		return
	check(hospital.view_mode == 0 and hospital.floor_id == 1, "Security checks start in the first-floor top-down hospital")
	var configuration: Dictionary = hospital.base_layout.get("security", {})
	check(configuration.get("doors", []).size() == 3, "Only the three requested room doors receive password locks")
	story_state.call("set_flag", "security_test_probe", true)
	check(bool(story_state.call("has_flag", "security_test_probe")), "The story-state flag API is available for future scripted events")
	check(not bool(story_state.call("has_item", "breaker_key")), "A fresh session does not start with the deferred NPC key")
	await verify_side_view_before_unlocks()
	for door in DOORS:
		await verify_door(door)
	await verify_breaker()
	await verify_persistence()
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	release()
	var report := {"suite": "hospital_security", "status": "passed" if failures.is_empty() else "failed", "checks": checks, "passed": checks - failures.size(), "failures": failures, "observations": observations}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	for path in ["res://evidence/hospital_security_results_v13.json", "user://hospital_security_results_v13.json"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
