extends "res://tests/support/isolated_suite.gd"

## The received v14 player inside the retained playable scenes: the top-down safehouse and the side-view night
## street, joined by F8.

const MAIN = preload("res://scenes/main.tscn")
const STREET_PATH := "res://scenes/night_street_proto.tscn"
const CONTROLS = preload("res://scripts/core/controls.gd")
const MENU_SCRIPT = preload("res://scripts/ui/keybindings_menu.gd")
const SIDE_BASE_ANIMATIONS := [
	"attack1_left", "attack2_left", "attack3_left", "crouch_left", "crouch_stab_left", "idle_left", "jump_left", "run_left", "stab_left", "walk_left",
	"attack1_right", "attack2_right", "attack3_right", "crouch_right", "crouch_stab_right", "idle_right", "jump_right", "run_right", "stab_right", "walk_right",
	"dash_stab_left", "rising_slash_left", "dash_stab_right", "rising_slash_right", "dive_slash_right", "dive_slash_left", "air_idle_right", "air_idle_left",
	"air_attack1_right", "air_attack1_left", "air_attack2_right", "air_attack2_left", "air_attack3_right", "air_attack3_left"
]

var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var _finished := false


func _initialize() -> void:
	# Keep this suite independent from the user's saved controls and the baseline suites.
	CONTROLS.settings_path = "user://scene_integration_v14_bindings.cfg"
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(90.0, true).timeout.connect(func() -> void:
		check(false, "The scene integration suite completes before its deadline")
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


func key(code: int, pressed: bool, character := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = character
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(code: int, character := 0) -> void:
	key(code, true, character)
	await frames(2)
	key(code, false, character)
	await frames(2)


func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(2, 2)
	event.global_position = event.position
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func release() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_SPACE, KEY_CAPSLOCK, KEY_E, KEY_R, KEY_TAB, KEY_F1, KEY_F6, KEY_F8, KEY_ESCAPE, KEY_ENTER, KEY_0, KEY_1]:
		key(code, false)
	mouse(false)
	CONTROLS.release_actions()


func has_property(object: Object, name: String) -> bool:
	for property in object.get_property_list():
		if String(property["name"]) == name:
			return true
	return false


func node_with_script(node: Node, script: Script) -> Node:
	if node.get_script() == script:
		return node
	for child in node.get_children():
		var found := node_with_script(child, script)
		if found != null:
			return found
	return null


func count_characters(node: Node) -> int:
	var count := 1 if node is CharacterBody2D else 0
	for child in node.get_children():
		count += count_characters(child)
	return count


func has_training_actor(node: Node) -> bool:
	var script: Script = node.get_script()
	if script != null and script.resource_path.ends_with("training_target.gd"):
		return true
	for child in node.get_children():
		if has_training_actor(child):
			return true
	return false


func is_street() -> bool:
	return current_scene != null and current_scene.scene_file_path == STREET_PATH


func is_home() -> bool:
	return current_scene != null and current_scene.has_method("reset_home")


func wait_for_street(expected: bool) -> bool:
	for _index in range(90):
		if is_street() == expected and (is_street() or is_home()):
			await frames(5)
			return true
		await frames(1)
	return false


func validate_player(host: Node2D, side: bool, label: String) -> void:
	var player: CharacterBody2D = host.get("player")
	check(player != null and player.scene_file_path == "res://scenes/player.tscn", label + " instantiates the received baseline player scene")
	if player == null:
		return
	check(player.get_script() == load("res://scripts/player/player.gd") and has_property(player, "input_suspended") and has_property(player, "_jumps_used"), label + " uses the new air-combat controller rather than the earlier scene avatar")
	var sprite: AnimatedSprite2D = player.get_node("Sprite")
	check(player.scale == Vector2.ONE and sprite.scale == Vector2.ONE and sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, label + " preserves original character size and pixel sampling")
	check(player.collision_layer == 4 and player.collision_mask == 3, label + " keeps the new player's world and enemy collision layers")
	var collider: CollisionShape2D = player.get_node("BodyShape")
	check(collider.shape is RectangleShape2D and collider.shape.size == (Vector2(12, 26) if side else Vector2(12, 8)), label + " retains the correct original feet or standing collider")
	check(sprite.sprite_frames == load("res://assets/side_view.tres" if side else "res://assets/top_down.tres"), label + " uses the matching received animation resource")
	check(count_characters(root) == 1 and not has_training_actor(root), label + " has one protagonist with no training targets or NPCs")
	var session := host.get_node_or_null("GameSession")
	var stop_signals_connected := session != null
	for signal_name in ["impact"]:
		var connected := false
		for connection in player.get_signal_connection_list(signal_name):
			var callback: Callable = connection["callable"]
			connected = connected or callback.get_object() == session
		stop_signals_connected = stop_signals_connected and connected
	check(stop_signals_connected, label + " binds the new player to reusable normal and critical impact feedback")


func validate_dialogue(owner: Node, label: String) -> void:
	var panel: Panel = owner.get("dialogue")
	var body: Label = panel.get("body")
	var portrait: TextureRect = panel.get("portrait")
	check(panel.scale.is_equal_approx(Vector2(0.8, 0.8)) and panel.size == Vector2(284, 72), label + " preserves the approved compact 80-percent dialogue presentation")
	check(body.get_theme_font("font") is FontFile and body.get_theme_font_size("font_size") == 12, label + " preserves the clear native 12px pixel font")
	check(portrait.texture != null and portrait.size == Vector2(48, 64), label + " keeps the original protagonist portrait source")
	check(root.content_scale_size == Vector2i(320, 180) and root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, label + " combines the original logical grid with clear window-resolution text")


func validate_reading(host: Node2D, dialogue: Node, label: String) -> void:
	var player: CharacterBody2D = host.get("player")
	var still := player.global_position
	check(bool(dialogue.get("dialogue_active")) and player.input_suspended, label + " suspends new controller input while reading")
	key(KEY_D, true)
	mouse(true)
	await frames(3)
	check(player.global_position.distance_to(still) < 0.1 and not player.is_attacking, label + " cannot move or attack through its dialogue")
	await tap(KEY_ESCAPE)
	key(KEY_D, false)
	mouse(false)
	await frames(6)
	check(not bool(dialogue.get("dialogue_active")) and not player.input_suspended and player.is_physics_processing(), label + " Escape closes reading and returns player control")
	check(not player._mouse_attack_pending and not player._mouse_attack_held and not player.queued_attack and not player.pending_new_attack and not player.is_attacking, label + " clears buffered or held attacks on close")
	check(not paused, label + " leaves the game unpaused after closing dialogue")


func validate_settings(host: Node2D, label: String) -> void:
	var scene_instance := current_scene.get_instance_id()
	var player: CharacterBody2D = host.get("player")
	await tap(KEY_F1)
	var menu := node_with_script(root, MENU_SCRIPT)
	check(menu != null and bool(menu.get("active")), label + " retains the new baseline's F1 controls menu")
	if menu == null or not bool(menu.get("active")):
		return
	check(paused and player.input_suspended, label + " pauses the world and suspends character input while editing controls")
	await tap(KEY_F8)
	check(current_scene.get_instance_id() == scene_instance and bool(menu.get("active")), label + " prevents scene routing while the controls menu is open")
	key(KEY_D, true)
	mouse(true)
	await frames(3)
	await tap(KEY_ESCAPE)
	key(KEY_D, false)
	mouse(false)
	await frames(6)
	check(not bool(menu.get("active")) and not paused and not player.input_suspended, label + " closes controls without leaving a paused or suspended player")
	check(not player._mouse_attack_pending and not player._mouse_attack_held and not player.queued_attack and not player.pending_new_attack, label + " clears transient combat input after the controls menu")


func validate_reset_remap(host: Node2D, label: String) -> void:
	release()
	var profile := CONTROLS.defaults()
	profile["reset_arena"] = KEY_T
	CONTROLS.current = profile
	CONTROLS.install(false)
	var player: CharacterBody2D = host.get("player")
	player.position = Vector2(110, 94) if host.has_method("reset_home") else Vector2(160, 65)
	player.velocity = Vector2.ZERO
	key(KEY_D, true)
	await frames(10)
	key(KEY_D, false)
	await frames(6)
	var away := player.position
	await tap(KEY_R)
	check(player.position.distance_to(away) < 0.35, label + " no longer resets on R after the reset binding moves to T")
	await tap(KEY_T)
	var expected: Vector2
	if host.has_method("reset_home"):
		var spawn: Array = host.get("layout")["spawn"]
		expected = Vector2(spawn[0], spawn[1])
	else:
		expected = host.start_position()
	check(player.position.distance_to(expected) < 0.5, label + " honors the remapped T reset action and returns to its real spawn")
	release()
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)


func validate_impact_timing(host: Node2D) -> void:
	var session := host.get_node_or_null("GameSession")
	if session == null:
		check(false, "The safehouse exposes its shared impact feedback component")
		return
	for requested in [2, 6]:
		var label := "normal" if requested == 2 else "critical"
		host.player.impact.emit(&"light" if requested == 2 else &"critical", Vector2.RIGHT)
		await frames(1)
		check(bool(session.get("hit_stop_active")) and paused, "The reusable safehouse " + label + " impact produces a real visible-time pause")
		for _index in range(30):
			if not bool(session.get("hit_stop_active")):
				break
			await frames(1)
		check(not bool(session.get("hit_stop_active")) and not paused, "The reusable safehouse " + label + " impact resumes the scene without the removed arena controller")
		var completed: Array = session.get("completed_stop_frames")
		var displayed := int(completed.back()) if not completed.is_empty() else 0
		var elapsed := float(session.get("hit_stop_elapsed_seconds"))
		check(displayed >= int(requested) and elapsed + 0.000001 >= float(requested) / 60.0, "The reusable safehouse " + label + " impact preserves its minimum displayed frames and visible duration")
		observations["impact_" + label] = {"displayed_frames": displayed, "elapsed_seconds": elapsed, "minimum_frames": requested, "minimum_seconds": float(requested) / 60.0}


func validate_air_dash(street: Node2D, direction: int) -> void:
	release()
	var player: CharacterBody2D = street.get("player")
	player.position = Vector2(480, street.FLOOR_Y)
	player.velocity = Vector2.ZERO
	await frames(10)
	var side := "right" if direction > 0 else "left"
	var new_animation := "air_dash_stab_" + side
	check(player.is_on_floor(), "Street " + side + " air-dash fixture begins on the street floor")
	await tap(KEY_SPACE)
	check(player._jumps_used == 1 and player.velocity.y < 0.0, "Street " + side + " first jump uses the received controller")
	await tap(KEY_SPACE)
	check(player._jumps_used == 2 and player.velocity.y < 0.0, "Street " + side + " allows the original fresh-input double jump")
	key(KEY_D if direction > 0 else KEY_A, true)
	key(KEY_SHIFT, true)
	mouse(true)
	await frames(2)
	mouse(false)
	key(KEY_SHIFT, false)
	key(KEY_D if direction > 0 else KEY_A, false)
	check(player.special_kind == "dash_stab" and player.sprite.animation == new_animation, "Street " + side + " airborne Shift press plays its independent dash animation")
	for _index in range(80):
		if player.special_kind.is_empty():
			break
		await frames(1)
	var displacement: Vector2 = player.dash_end - player.dash_start
	check(player.dash_executed and absf(displacement.x - direction * 48.0) < 0.1, "Street " + side + " preserves the original real 48px piercing movement")
	check(player._jumps_used == 2 and not player.is_on_floor(), "Street " + side + " dash does not reset jumps or force an early landing")
	await frames(3)
	check(player.sprite.animation == "air_idle_" + side and player.sprite.is_playing(), "Street " + side + " dash returns smoothly to the dedicated looping airborne idle")
	check(player.collision_mask == 3 and not player._dash_phasing, "Street " + side + " dash restores normal collision after its sweep")
	observations["air_dash_" + side] = {"distance": [displacement.x, displacement.y], "animation": new_animation, "followup": String(player.sprite.animation)}


func run() -> void:
	var home := MAIN.instantiate()
	root.add_child(home)
	current_scene = home
	await frames(8)
	var entry := String(ProjectSettings.get_setting("application/run/main_scene"))
	check(entry == "res://scenes/boot.tscn" and is_home(), "The game entry stays the start page and main.tscn opens the safehouse instead of the training arena")
	if not is_home():
		finish()
		return
	validate_player(home, false, "Safehouse")
	var top: SpriteFrames = load("res://assets/top_down.tres")
	var side: SpriteFrames = load("res://assets/side_view.tres")
	check(top.get_animation_names().size() == 32 and side.get_animation_names().size() == 50, "All baseline animation states remain with the dedicated charged draw and the perfect-dodge poses")
	var originals_present := true
	for name in SIDE_BASE_ANIMATIONS:
		originals_present = originals_present and side.has_animation(name)
	check(originals_present, "The received 34 side-view animations remain available")
	var dedicated_dash_sources := true
	for facing in ["left", "right"]:
		var name: String = "air_dash_stab_" + String(facing)
		dedicated_dash_sources = dedicated_dash_sources and side.has_animation(name)
		if side.has_animation(name):
			dedicated_dash_sources = dedicated_dash_sources and side.get_frame_count(name) > 1 and not side.get_animation_loop(name)
			dedicated_dash_sources = dedicated_dash_sources and side.get_frame_texture(name, 0).resource_path != side.get_frame_texture("dash_stab_" + facing, 0).resource_path
	check(dedicated_dash_sources, "Each new airborne dash has its own non-looping authored frames")
	var initial_instance := home.get_instance_id()
	await tap(KEY_F6)
	check(current_scene.get_instance_id() == initial_instance and not has_training_actor(root), "The removed F6 route cannot reopen the training scene")
	await validate_settings(home, "Safehouse")
	await validate_reset_remap(home, "Safehouse")
	await validate_impact_timing(home)
	home.player.position = Vector2(158, 66)
	home.player.velocity = Vector2.ZERO
	await frames(4)
	await tap(KEY_E)
	check(home.dialogue_active and home.current_interaction == "frame", "The received protagonist can inspect the original safehouse objects with E")
	validate_dialogue(home, "Safehouse dialogue")
	await validate_reading(home, home, "Safehouse dialogue")
	home.player.position = Vector2(127, 66)
	home.player.velocity = Vector2.ZERO
	await frames(4)
	await tap(KEY_E)
	check(home.dialogue_active and home.current_interaction == "door" and is_home(), "The safehouse door is read like the other objects")
	await validate_reading(home, home, "Safehouse door")
	await tap(KEY_F8)
	check(await wait_for_street(true), "F8 leaves the safehouse for the night street")
	if not is_street():
		finish()
		return
	var street := current_scene as Node2D
	validate_player(street, true, "Street side-view")
	await validate_settings(street, "Street")
	for direction in [1, -1]:
		await validate_air_dash(street, direction)
	release()
	await tap(KEY_F8)
	check(await wait_for_street(false) and is_home(), "F8 returns from the street to the safehouse")
	check(not paused and count_characters(root) == 1 and not has_training_actor(root) and not current_scene.player.input_suspended,
		"Scene round trips return an active single protagonist without leftover UI locks or training targets")
	observations["baseline_animation_count"] = 62
	observations["integrated_animation_count"] = top.get_animation_names().size() + side.get_animation_names().size()
	observations["settings_path"] = CONTROLS.settings_path
	observations["player_script_sha256"] = FileAccess.get_sha256("res://scripts/player/player.gd")
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	release()
	paused = false
	var report := {"suite": "scene_integration_v14", "status": "passed" if failures.is_empty() else "failed", "checks": checks, "passed": checks - failures.size(), "failures": failures, "observations": observations}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	for path in ["res://evidence/scene_integration_results_v14.json", "user://scene_integration_results_v14.json"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
