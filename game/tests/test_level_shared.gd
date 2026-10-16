extends "res://tests/support/isolated_suite.gd"
## Shared level plumbing: the owner-counted player freeze, story modals keeping Esc / F1 from the settings menu,
## the shared dialogue box (per-scene paging, speakers from layout data), the reserved E key with its save
## migration, control hints written from the current bindings, and LevelKit (colliders and the follow camera).

const CONTROLS = preload("res://scripts/core/controls.gd")
const HOME = preload("res://scenes/home_601.tscn")
const HOSPITAL = preload("res://scenes/underground_hospital.tscn")
const LEVEL_KIT = preload("res://scripts/levels/level_kit.gd")
const TEST_PATH := "user://level_shared_keybindings.cfg"
var checks := 0
var failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		check(false, "Level shared suite completes before its deadline")
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
		await process_frame


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)


func use_bindings(changes: Dictionary) -> void:
	var profile := CONTROLS.defaults()
	profile.merge(changes, true)
	CONTROLS.current = profile
	CONTROLS.install(false)


func run() -> void:
	check_reserved_key()
	check_level_kit()
	var home: Node2D = HOME.instantiate()
	root.add_child(home)
	current_scene = home
	await frames(5)
	await check_freeze(home)
	await check_home_dialogue(home)
	home.queue_free()
	await frames(2)
	var hospital: Node2D = HOSPITAL.instantiate()
	root.add_child(hospital)
	current_scene = hospital
	await frames(5)
	await check_hospital(hospital)
	finish()


func check_reserved_key() -> void:
	var profile := CONTROLS.defaults()
	profile["jump"] = KEY_E
	check(CONTROLS.validate(profile).contains("E 保留"), "validate rejects binding an action to the reserved E key")
	check(KEY_E not in CONTROLS.SPARE_KEYS, "E is never offered as a spare key when a saved binding has to move")
	var saved := ConfigFile.new()
	saved.set_value("bindings", "version", 3)
	for slot in CONTROLS.SLOTS:
		saved.set_value("bindings", slot, profile[slot])
	saved.save(TEST_PATH)
	CONTROLS.settings_path = TEST_PATH
	CONTROLS.current.clear()
	CONTROLS.install()
	var expected := CONTROLS.defaults()
	expected["jump"] = KEY_CTRL
	check(CONTROLS.current == expected, "a saved profile with jump on E keeps every other binding and moves jump to the first free key")
	check(CONTROLS.load_notice.contains("跳跃") and CONTROLS.load_notice.contains("Ctrl"), "the moved binding is reported to the player")
	CONTROLS.settings_path = ISOLATED_SETTINGS_PATH
	use_bindings({})
	check(CONTROLS.hint_text("attack_mouse") == "左键" and CONTROLS.hint_text("heavy_mouse") == "右键"
		and CONTROLS.binding_text("attack_mouse") == "LMB", "scene hints name the default mouse buttons in Chinese; the settings menu keeps LMB")
	use_bindings({"attack_mouse": MOUSE_BUTTON_MIDDLE, "heavy_mouse": MOUSE_BUTTON_XBUTTON1})
	check(CONTROLS.hint_text("attack_mouse") == "中键" and CONTROLS.hint_text("heavy_mouse") == "侧键1", "scene hints follow rebound mouse buttons")
	use_bindings({})


func check_level_kit() -> void:
	# In the tree so global positions and the camera scroll resolve without "not inside tree" errors.
	var parent := Node2D.new()
	root.add_child(parent)
	var box := LEVEL_KIT.add_box(parent, Rect2(10, 20, 30, 8), "Crate")
	var shape := box.get_child(0) as CollisionShape2D
	check(box.get_parent() == parent and box.name == "Crate" and box.position == Vector2(25, 24)
		and (shape.shape as RectangleShape2D).size == Vector2(30, 8) and box.collision_layer == 1 and box.collision_mask == 0,
		"LevelKit box: centred static body of the rectangle's size on layer 1, mask 0")
	var door := LEVEL_KIT.add_box(parent, Rect2(0, 0, 4, 4), "", 0)
	check(door.collision_layer == 0 and not String(door.name).is_empty(), "LevelKit box: an open door has no layer and keeps a generated name")
	var ledge := LEVEL_KIT.add_layout_collider(parent, {"id": "ledge", "rect": [0, 100, 40, 6], "one_way": true})
	check(ledge.name == "ledge" and (ledge.get_child(0) as CollisionShape2D).one_way_collision, "LevelKit layout entry: a one-way ledge")
	var ramp := LEVEL_KIT.add_layout_collider(parent, {"id": "ramp", "rect": [0, 0, 1, 1], "stair_only": true,
		"polygon": [[0, 10], [20, 0], [20, 10]]})
	var polygon := ramp.get_child(0) as CollisionPolygon2D
	check(polygon != null and polygon.polygon.size() == 3 and polygon.polygon[1] == Vector2(20, 0) and ramp.position == Vector2.ZERO
		and ramp.collision_layer == 0, "LevelKit layout entry: a stair-only polygon starts with no layer, points in world space")
	var camera := Camera2D.new()
	parent.add_child(camera)
	var bounds := Rect2(0, 0, 640, 360)
	LEVEL_KIT.follow(camera, Vector2(300.6, 200.4), bounds, Vector2(320, 180))
	check(camera.global_position == Vector2(301, 200), "LevelKit follow: the camera sits on whole pixels at the hero")
	LEVEL_KIT.follow(camera, Vector2(5, 355), bounds, Vector2(320, 180))
	check(camera.global_position == Vector2(160, 270), "LevelKit follow: the view stays inside the world at its edges")
	parent.free()


func check_freeze(home: Node2D) -> void:
	var player: CharacterBody2D = home.player
	var session: Node = home.get_node("GameSession")
	var first := Node.new()
	var second := Node.new()
	player.velocity = Vector2(30, 0)
	player.freeze(first)
	check(player.is_frozen() and player.input_suspended and player.process_mode == Node.PROCESS_MODE_DISABLED and player.velocity == Vector2.ZERO,
		"freeze stops the player, suspends input and clears movement")
	player.freeze(second)
	player.unfreeze(first)
	check(player.is_frozen() and player.input_suspended and player.process_mode == Node.PROCESS_MODE_DISABLED,
		"the player stays frozen while another owner still holds it")
	player.unfreeze(first)
	check(player.is_frozen(), "releasing the same owner twice does not release the other one")
	player.unfreeze(second)
	check(not player.is_frozen() and not player.input_suspended and player.process_mode == Node.PROCESS_MODE_INHERIT,
		"the last owner releases the player back to its own process mode")
	player.velocity = Vector2(0, -40)
	session.open_keybindings()
	check(session.settings_open and player.is_frozen() and player.velocity == Vector2(0, -40),
		"the settings menu freezes the player but keeps its velocity, so a jump keeps its arc")
	await tap(KEY_ESCAPE)
	check(not session.settings_open and not player.is_frozen() and not player.input_suspended, "closing the settings menu releases the player")
	session.push_modal(first)
	await tap(KEY_F1)
	check(not session.settings_open and session.has_modal(), "a registered story modal keeps F1 from opening the settings menu")
	session.pop_modal(first)
	check(not session.has_modal(), "pop_modal unregisters the modal")
	var dropped := Node.new()
	session.push_modal(dropped)
	dropped.free()
	check(not session.has_modal(), "a freed modal owner no longer blocks the settings menu")
	first.free()
	second.free()


func check_home_dialogue(home: Node2D) -> void:
	var dialogue: Panel = home.dialogue
	var session: Node = home.get_node("GameSession")
	check(dialogue.page_characters == 24 and is_equal_approx(dialogue.type_speed, 28.0), "the safehouse keeps 24 characters per page at 28 per second")
	home.player.position = Vector2(180, 82)
	home.player.velocity = Vector2.ZERO
	await frames(4)
	await tap(KEY_E)
	check(home.dialogue_active and home.current_interaction == "television", "E opens the television")
	check(home.player.is_frozen() and session.has_modal(), "an open dialogue freezes the player and registers as a story modal")
	var short_pages := true
	for page in dialogue.pages:
		short_pages = short_pages and String(page).length() <= 24
	check(short_pages, "safehouse pages hold at most 24 characters")
	check(dialogue.page_speakers[0] == "television" and dialogue.page_speakers[-1] == "protagonist" and not dialogue.portrait.visible,
		"speakers come from layout.json: the broadcast pages show no portrait, the last line is the protagonist's")
	check(dialogue.footer.text.begins_with("E继续"), "the footer names the interaction key")
	await tap(KEY_ESCAPE)
	check(not home.dialogue_active and not home.player.is_frozen() and not session.has_modal(), "Esc closes the dialogue, releases the player and the modal")
	home.player.position = Vector2(60, 89)
	await frames(4)
	await tap(KEY_E)
	var speakers: Array[String] = dialogue.page_speakers
	check(speakers.has("qiaolun") and speakers.has("terminal") and speakers.has("protagonist"), "the computer's message, own words and terminal lines keep their speakers")
	await tap(KEY_ESCAPE)


func control_hint(hospital: Node2D) -> String:
	return (hospital.get("_hint") as Label).text


func check_hospital(hospital: Node2D) -> void:
	var interactions: Node2D = hospital.interactions
	check(interactions.dialogue.page_characters == 32 and is_equal_approx(interactions.dialogue.type_speed, 36.0), "the hospital keeps 32 characters per page at 36 per second")
	check(control_hint(hospital) == "WASD移动 E交互/楼梯 Tab视角 Caps跑 F7家中", "the default top-down hint reads as before")
	use_bindings({"move_left": KEY_J, "jump": KEY_K})
	hospital.get_node("GameSession").keybindings_closed.emit(true)
	check(control_hint(hospital) == "WJSD移动 E交互/楼梯 Tab视角 Caps跑 F7家中", "the top-down hint follows a remapped key once the settings menu closes")
	hospital.activate_view(1, "entry", Vector2(110, 286))
	await frames(4)
	check(control_hint(hospital) == "JD直走 W上楼 S蹲/下楼 E交互 K跳 Tab视角", "the side-view hint follows remapped keys")
	use_bindings({"reset_arena": KEY_F7})
	hospital.activate_view(0, "entry", Vector2(110, 300))
	await frames(4)
	check(not control_hint(hospital).contains("F7"), "the F7 home shortcut leaves the hint while F7 is bound to an action")
	use_bindings({})
	hospital.refresh_ui()
	check(control_hint(hospital) == "WASD移动 E交互/楼梯 Tab视角 Caps跑 F7家中", "default bindings restore the original hint")
	var flight: Dictionary = hospital.base_layout["stairs"]["side_flight"]
	check(flight.get("upper_landing_y") == 164.0 and flight.get("lower_landing_y") == 286.0, "stair landings come from layout.json stairs")
	var security: Node2D = hospital.security
	var session: Node = hospital.get_node("GameSession")
	hospital.floor_id = 1
	hospital.activate_view(0, "", Vector2(538, 87))
	hospital.player.global_position = Vector2(538, 87)
	await frames(4)
	check(security.open_keypad("storage_door") and hospital.player.is_frozen() and session.has_modal(), "the door keypad freezes the player and registers as a story modal")
	await tap(KEY_ESCAPE)
	check(not security.keypad_active and not hospital.player.is_frozen() and not session.has_modal(), "Esc closes the keypad, releases the player and the modal")


func finish() -> void:
	if _finished:
		return
	_finished = true
	for code in [KEY_E, KEY_ESCAPE, KEY_F1]:
		key(code, false)
	CONTROLS.settings_path = ISOLATED_SETTINGS_PATH
	use_bindings({})
	var report := {"suite": "level_shared", "status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
