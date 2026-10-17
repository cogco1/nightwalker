extends "res://tests/support/isolated_suite.gd"
## Night-street prototype: hero material everywhere, surveillance exposure, combat and hit-stop on hover
## drones, the drones' own attack (hit, perfect dodge, counter), prototype-only controls, hand-placed data from
## layout.json, binding-aware hints, and the F8 route shared with the safe house / hospital.

const STREET = preload("res://scenes/night_street_proto.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const PLAYER = preload("res://scenes/player.tscn")
const HERO_SHADER := "res://shaders/character_cyber.gdshader"
const PALETTE_SOURCE := ["11141a", "20242b", "303842", "414b58", "5a6268", "566170", "6b7480", "8a8a85", "75695a",
	"33251f", "533729", "76513a", "a07a5b", "e1b999", "c5a18a", "8e999f", "bbc2c3", "e5e8e0"]

var street: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var _finished := false


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		check(false, "Night-street suite completes before its deadline")
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


func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(code: int) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)


func click() -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = Vector2(160, 90)
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(1)


func run() -> void:
	verify_material_everywhere()
	verify_route_entry()
	street = STREET.instantiate()
	root.add_child(street)
	current_scene = street
	await frames(20)
	var player: CharacterBody2D = street.player
	check(player.view_mode == 1, "The night street spawns a side-view player")
	check(player.is_on_floor(), "The player stands on the street")
	var material := player.get_node("Sprite").material as ShaderMaterial
	check(material != null and material.shader.resource_path == HERO_SHADER, "The street player uses the hero shader")
	check(Vector3(material.get_shader_parameter("emission_lift")).x > 1.0, "The street lifts self-lit hero pixels above its dark ambient")
	check(street.get_node("NightAmbient") is CanvasModulate, "The street is darkened by a CanvasModulate")
	check((street.get_node("Glow") as WorldEnvironment).environment.glow_enabled, "WorldEnvironment glow is on for the street")
	var lights := street.get_node("World").get_children().filter(func(node: Node) -> bool: return node is PointLight2D)
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/night_street/lights.json"))
	check(table is Array and lights.size() == table.size() + 1 and lights.size() >= 10, "Street lights follow the fixtures in lights.json (plus the beam spot)")
	observations["street_lights"] = lights.size()
	verify_layout_and_hint()
	await verify_exposure(player)
	await verify_combat(player)
	await verify_drone_attack(player)
	await verify_prototype_keys(player, material)
	finish()


func verify_layout_and_hint() -> void:
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/night_street/layout.json"))
	var spots: Array = layout.get("targets", []) if layout is Dictionary else []
	var drones := street.get_node("World").get_children().filter(func(node: Node) -> bool: return node.has_method("take_damage"))
	var placed := drones.map(func(node: Node2D) -> Vector2: return node.position)
	check(spots.size() == 3 and placed == spots.map(func(spot: Array) -> Vector2: return Vector2(spot[0], spot[1])),
		"Hover drones stand where layout.json targets puts them")
	check(drones[0].max_hp==9 and drones[0].hp==9 and drones[1].max_hp==3 and drones[2].max_hp==3,"First street drone can survive a charged launch for the jump chase")
	check(layout is Dictionary and layout.get("fallback_lights", []).size() == 3, "The fallback street lights live in layout.json")
	var hint: Label = street._hint
	check(hint.text == "AD走 S蹲行 Shift点滚/长跑 Shift+方向+左键突刺", "The default bindings give the default controls hint")
	var profile := CONTROLS.defaults()
	profile.merge({"move_left": KEY_J, "move_right": KEY_L, "dash_modifier": KEY_CTRL, "heavy_mouse": MOUSE_BUTTON_MIDDLE}, true)
	CONTROLS.current = profile
	CONTROLS.install(false)
	street.refresh_hint()
	check(hint.text == "JL走 S蹲行 Ctrl点滚 Shift跑 Ctrl+方向+左键突刺", "The controls hint follows rebound keys")
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	street.refresh_hint()


func verify_material_everywhere() -> void:
	var player := PLAYER.instantiate()
	var material := player.get_node("Sprite").material as ShaderMaterial
	check(material != null and material.shader.resource_path == HERO_SHADER, "player.tscn carries the hero shader, so every scene uses it")
	check(material != null and material.resource_local_to_scene, "Each player instance gets its own hero material")
	var palette: Texture2D = material.get_shader_parameter("palette") if material != null else null
	check(palette != null and palette.get_width() == 18 and palette.get_height() == 4, "The hero lookup is 18 x 4")
	if palette != null:
		var image := palette.get_image()
		var found: Array[String] = []
		for index in range(image.get_width()):
			found.append(image.get_pixel(index, 0).to_html(false))
		check(found == PALETTE_SOURCE, "Lookup row 0 lists the 18 colours used by the shipped frames")
		check(is_equal_approx(image.get_pixel(17, 2).a, 1.0) and image.get_pixel(0, 2).a == 0.0, "Blade edge is emissive and the outline is not")
		check(is_equal_approx(image.get_pixel(PALETTE_SOURCE.find("533729"), 3).a, 1.0) and image.get_pixel(0, 3).a == 0.0, "Only the strap leather is reflective tape")
	var overlay := player.get_node_or_null("Sprite/ImplantOverlay")
	check(overlay != null and overlay.get_script().resource_path == "res://scripts/player/implant_overlay.gd", "player.tscn carries the barcode-scar overlay")
	var anchors: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fx/implant_anchors.json"))
	check(anchors is Dictionary and anchors.has("res://frames/side_view_right_idle/00.png") and anchors.size() >= 700, "Forearm anchors cover the side-view idle and most frames")
	player.free()


func verify_route_entry() -> void:
	var routes := root.get_node_or_null("SceneRoutes")
	check(routes != null and routes.STREET_PATH == STREET.resource_path, "SceneRoutes registers the night-street scene")
	check(routes != null and routes.has_method("toggle_street"), "The shared router exposes F8 street travel")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/boot.tscn"
		and load("res://scripts/core/boot.gd").MAIN_PATH == "res://scenes/main.tscn", "The game still starts in the safe house (through the chapter boot)")


func verify_exposure(player: CharacterBody2D) -> void:
	var drone: Node2D = street.drone
	check(street.exposure == 0.0 and not street.marked, "Exposure starts at zero")
	for _index in range(150):
		drone.position.x = player.global_position.x
		await frames(1)
		if street.marked:
			break
	observations["seconds_to_mark"] = snappedf(street.exposure / 0.55, 0.01)
	check(street.in_beam, "Standing under the drone puts the player in the beam")
	check(street.marked and drone.marked, "Full exposure marks the player")
	check(drone.light_color() == drone.MARKED, "A marked player turns the beam red")
	var hero_material := player.get_node("Sprite").material as ShaderMaterial
	check(float(hero_material.get_shader_parameter("reflect_strength")) > 0.9, "Reflective straps flare inside the beam")
	check(float(player.get_node("Sprite/ImplantOverlay").scanned) == 1.0, "The beam scans the barcode scar")
	check(street.get_node("StreetUI/ScanReadout") != null and street._scan_label.visible, "The scan readout shows while the beam is on the hero")
	player.position = Vector2(820, 156)
	player.velocity = Vector2.ZERO
	await frames(10)
	var after_leaving: float = street.exposure
	check(not street.in_beam and after_leaving < 1.0, "Leaving the beam lowers exposure")
	check(float(player.get_node("Sprite/ImplantOverlay").scanned) == 0.0 and not street._scan_label.visible, "Out of the beam the scar is no longer scanned")
	await frames(200)
	check(not street.marked, "Exposure decays below the unmark threshold and clears the mark")
	observations["exposure_after_decay"] = snappedf(street.exposure, 0.01)


func verify_combat(player: CharacterBody2D) -> void:
	var target: Node = null
	for node in street.get_node("World").get_children():
		if node.has_method("take_damage"):
			target = node
			break
	check(target != null, "The street has hover drones to hit")
	if target == null:
		return
	street.drone.position.x = 900.0
	# the drone's own attack is checked on its own (verify_drone_attack)
	target.attacker.set_physics_process(false)
	player.position = Vector2(target.global_position.x - 18.0, 156)
	player.velocity = Vector2.ZERO
	player.facing = "right"
	player.show_idle()
	await frames(6)
	var session: Node = street.get_node("GameSession")
	var hits := [0]
	player.hit_resolved.connect(func(_t: Node, _d: int, _c: bool, _k: String) -> void: hits[0] += 1)
	for _stage in range(3):
		await click()
		await frames(10)
	await frames(20)
	observations["combo_hits"] = hits[0]
	observations["hit_stop_frames"] = session.completed_stop_frames
	check(hits[0] >= 2, "The ground combo hits a hover drone")
	check(target.hp < target.max_hp, "Hits reduce the hover drone's health")
	check(not session.completed_stop_frames.is_empty(), "Hits on hover drones trigger the shared hit-stop")


func verify_drone_attack(player: CharacterBody2D) -> void:
	var targets := street.get_node("World").get_children().filter(func(node: Node) -> bool: return node.has_method("take_damage"))
	check(targets.all(func(node: Node) -> bool: return node.attacker.target == player), "Every hover drone is bound to attack the hero")
	var target: Node = targets[1]
	var attacker: Node = target.attacker
	# only this drone attacks here, so another one's lunge cannot cut in
	for other in targets:
		other.attacker.set_physics_process(other == target)
	var session: Node = street.get_node("GameSession")
	var results: Array[int] = []
	player.attack_received.connect(func(result: int, _attack: Dictionary) -> void: results.append(result))
	street.drone.position.x = 900.0
	target.hp = target.max_hp
	await frames(4)
	# standing still in reach: the drone blinks red, lunges and hits
	player.position = Vector2(target.global_position.x - 40.0, 156)
	player.velocity = Vector2.ZERO
	player.facing = "right"
	await frames(70)
	check(results.size() == 1 and results[0] == player.AttackResult.HIT, "A hover drone lunges at a hero in reach and hits")
	observations["drone_first_result"] = results.duplicate()
	# after its cooldown: a timely dash is a perfect dodge, the street slows, and a click counters
	for _index in range(240):
		if attacker.phase == attacker.Phase.TELEGRAPH:
			break
		player.position = Vector2(target.global_position.x - 40.0, 156)
		player.facing = "right"
		await frames(1)
	for _index in range(60):
		if attacker.phase_time >= 0.42:
			break
		await frames(1)
	await tap(KEY_SHIFT)
	for _index in range(40):
		if results.size() >= 2:
			break
		await frames(1)
	check(results.size() == 2 and results[1] == player.AttackResult.PERFECT, "A timely dash perfectly dodges the hover drone")
	check(session.slowmo_active and is_equal_approx(session.world_time_scale, 0.25), "The perfect dodge slows the street")
	await click()
	check(player.move_id == &"counter_slash", "A click in the slow motion counters")
	for _index in range(40):
		if target.hp == 0:
			break
		await frames(1)
	check(target.hp == 0, "The counter destroys the hover drone")
	for _index in range(30):
		if not session.hit_stop_active:
			break
		await frames(1)
	check(not session.slowmo_active, "The street returns to full speed after the counter")
	await frames(20)
	check(attacker.phase == attacker.Phase.COOLDOWN, "A destroyed hover drone stands down")
	# the controls hint fits the screen
	var hint: Label = street._hint
	check(hint.text.contains("点滚") and hint.text.contains("突刺") and hint.get_theme_font("font").get_string_size(hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hint.get_theme_font_size("font_size")).x <= 310.0, "The controls hint names tap/hold and thrust and fits the screen")


func verify_prototype_keys(player: CharacterBody2D, material: ShaderMaterial) -> void:
	await tap(KEY_TAB)
	check(player.view_mode == 1 and is_instance_valid(street.player) and street.player == player, "Tab does not switch views in the side-only prototype")
	await tap(KEY_F9)
	check(is_equal_approx(float(material.get_shader_parameter("look")), 0.0), "F9 shows the original hero colours")
	await tap(KEY_F9)
	check(is_equal_approx(float(material.get_shader_parameter("look")), 1.0), "F9 again restores the cyber colours")
	player.position = Vector2(600, 156)
	street.exposure = 0.5
	await tap(KEY_R)
	check(player.position.distance_to(street.START) < 2.0 and street.exposure == 0.0, "R resets position and exposure")


func finish() -> void:
	if _finished:
		return
	_finished = true
	for code in [KEY_A, KEY_D, KEY_TAB, KEY_F9, KEY_R]:
		key(code, false)
	var report := {"suite": "night_street_proto", "status": "passed" if failures.is_empty() else "failed", "checks": checks,
		"failures": failures, "observations": observations}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	var file := FileAccess.open("res://evidence/night_street_proto_results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
