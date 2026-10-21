extends "res://tests/support/isolated_suite.gd"
## Real F8 travel between the safe house and the night street: return context, binding ownership, modal guards
## and clean hit-stop exit.

const CONTROLS = preload("res://scripts/core/controls.gd")
const HOME := "res://scenes/home_601.tscn"
const MAIN := "res://scenes/main.tscn"
const STREET := "res://scenes/night_street_proto.tscn"

var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var routes: Node
var _finished := false


func _initialize() -> void:
	CONTROLS.settings_path = "user://test_scene_routes_bindings.cfg"
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(90.0, true).timeout.connect(func() -> void:
		check(false, "Scene routes complete before the deadline")
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


func key(code: int, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(160, 90)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(code: int) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(3)


func arrive(path: String) -> bool:
	for _index in range(90):
		if current_scene != null and current_scene.scene_file_path == path and not routes.switching:
			await frames(3)
			return true
		await frames(1)
	check(false, "Scene arrives at " + path)
	return false


func stay(code: int, label: String) -> void:
	var before := current_scene.get_instance_id()
	await tap(code)
	check(current_scene != null and current_scene.get_instance_id() == before and not routes.switching, label)


func bindings(changes: Dictionary = {}) -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.current.merge(changes, true)
	CONTROLS.install(false)


func session() -> Node:
	return current_scene.get_node("GameSession")


func clean_player(label: String) -> void:
	var player: CharacterBody2D = current_scene.player
	check(not paused and not session().hit_stop_active and not session().settings_open, label + " restores the shared pause state")
	check(not player.input_suspended and player.is_physics_processing(), label + " restores player processing")
	check(not player.is_attacking and not player._mouse_attack_pending and not player._mouse_attack_held
		and not player.queued_attack and not player.pending_new_attack, label + " starts without a held or buffered attack")


func run() -> void:
	routes = root.get_node("SceneRoutes")
	var home: Node = load(MAIN).instantiate()
	root.add_child(home)
	current_scene = home
	await frames(8)
	check(current_scene.scene_file_path == MAIN and current_scene.player.view_mode == 0, "The sandbox scene is the top-down safe house")
	check(routes.STREET_PATH == STREET, "The shared router names the actual street scene")
	check(home._route_hint.text == "F8夜街", "The safe house shows its F8 street shortcut")
	await stay(KEY_F6, "F6 does not restore a training-scene route")
	var before := current_scene.get_instance_id()
	routes.switch_to("res://tests/fixtures/combat_lab.tscn")
	await frames(3)
	check(current_scene.get_instance_id() == before, "The public router rejects the combat test fixture")

	# Real reading and settings owners keep the scene shortcut until they close.
	var item: Dictionary = home.layout.interactions.filter(func(value: Dictionary) -> bool:
		return not value.get("lines", []).is_empty())[0]
	home._open_interaction(String(item.id))
	check(home.dialogue_active and session().has_modal(), "Home reading registers its actual modal owner")
	await stay(KEY_F8, "F8 cannot interrupt home reading")
	await tap(KEY_ESCAPE)
	check(not home.dialogue_active, "Escape closes home reading before travel")
	await tap(KEY_F1)
	check(session().settings_open and paused, "The real settings menu pauses before route guarding")
	await stay(KEY_F8, "F8 cannot interrupt settings")
	await tap(KEY_ESCAPE)
	check(not session().settings_open and not paused, "Closing settings releases the route guard")

	bindings({"move_right": KEY_F8})
	var origin: Vector2 = home.player.position
	await stay(KEY_F8, "A rebound F8 belongs to the player's movement action")
	check(home.player.position.x > origin.x, "The F8 movement binding still moves the real player")
	bindings()
	await frames(8)
	home.player.facing = "left"
	home.player.show_idle()
	var home_feet: Vector2 = home.player.position
	key(KEY_F8, true, true)
	await frames(2)
	key(KEY_F8, false)
	check(current_scene == home, "A repeated F8 key event does not switch scenes")
	key(KEY_F8, true)
	key(KEY_F8, true)
	await frames(2)
	key(KEY_F8, false)
	if not await arrive(STREET):
		finish()
		return
	check(current_scene.player.view_mode == 1, "F8 enters the actual side-view street from the safe house")
	check(current_scene._route_hint.text == "F8返回", "The street shows its return shortcut separately from combat controls")
	check(current_scene._route_hint.get_rect().end.x <= 236.0, "The return hint leaves room for the exposure HUD")
	clean_player("Entering the street")
	await stay(KEY_F6, "The street has no F6 training route")
	bindings({"jump": KEY_F8})
	current_scene.refresh_hint()
	check(current_scene._route_hint.text.is_empty(), "The street hides F8 travel while F8 is rebound")
	await stay(KEY_F8, "A rebound F8 jumps instead of leaving the street")
	check(current_scene.player._jumps_used == 1 and current_scene.player.velocity.y < 0.0, "The street player receives its real F8 jump input")
	bindings()
	current_scene.refresh_hint()
	await tap(KEY_F8)
	if not await arrive(HOME):
		finish()
		return
	check(current_scene.player.position.distance_to(home_feet) < 0.1 and current_scene.player.facing == "left", "F8 restores the safe-house feet and facing")
	clean_player("Returning home")
	await verify_hit_stop_and_input()

	# A user who starts the street directly has no interior snapshot in this process.
	routes._street_return.clear()
	change_scene_to_file(STREET)
	await frames(8)
	check(current_scene.scene_file_path == STREET, "The standalone street launcher remains supported")
	await tap(KEY_F8)
	if await arrive(HOME):
		check(current_scene.player.view_mode == 0, "A directly launched street falls back to the safe house")
		await tap(KEY_F8)
		check(await arrive(STREET), "F8 still leaves the fallback safe house for the street")
	finish()


func verify_hit_stop_and_input() -> void:
	var old_session: Node = session()
	current_scene.player.impact.emit(&"light", Vector2.RIGHT)
	check(old_session.hit_stop_active and paused, "The route check begins during an actual shared hit-stop")
	await tap(KEY_F8)
	if not await arrive(STREET):
		return
	clean_player("Travel during hit-stop")
	check(not paused and not routes.switching, "F8 cancels a hit-stop without leaving the new scene paused")
	await tap(KEY_F8)
	if not await arrive(HOME):
		return
	key(KEY_D, true)
	mouse(true)
	key(KEY_F8, true)
	await frames(2)
	key(KEY_F8, false)
	if await arrive(STREET):
		clean_player("Travel with pressed combat controls")
	key(KEY_D, false)
	mouse(false)
	CONTROLS.release_actions()


func finish() -> void:
	if _finished:
		return
	_finished = true
	for code in [KEY_D, KEY_F1, KEY_F6, KEY_F8, KEY_ESCAPE, KEY_SPACE]:
		key(code, false)
	mouse(false)
	CONTROLS.release_actions()
	paused = false
	var report := {"suite": "scene_routes", "status": "passed" if failures.is_empty() else "failed",
		"checks": checks, "failures": failures, "observations": observations}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	var file := FileAccess.open("res://evidence/scene_routes_results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
