extends "res://tests/support/isolated_suite.gd"
## Night-street prototype (map exploration only): hero material everywhere, street lights on the hero,
## prototype-only controls, hand-placed data from layout.json, binding-aware hints, and the F8 route shared with
## the safe house.

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
	check(table is Array and lights.size() == table.size() and lights.size() >= 10, "Street lights follow the fixtures in lights.json")
	observations["street_lights"] = lights.size()
	verify_layout_and_hint()
	await verify_lamp_on_hero(player, material, lights)
	await verify_prototype_keys(player, material)
	finish()


func verify_layout_and_hint() -> void:
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/night_street/layout.json"))
	var targets := street.get_node("World").get_children().filter(func(node: Node) -> bool: return node.has_method("take_damage"))
	check(targets.is_empty() and not (layout is Dictionary and layout.has("targets")), "The street is map exploration only: no hover drones")
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
	check(routes != null and routes.HOME_PATH == "res://scenes/home_601.tscn", "A directly launched street returns to the safe house")


## The strongest street lamp over the hero's chest lights the reflective straps above their dark floor.
func verify_lamp_on_hero(player: CharacterBody2D, material: ShaderMaterial, lights: Array) -> void:
	var best: PointLight2D = null
	var best_influence := 0.0
	for light: PointLight2D in lights:
		var chest := Vector2(light.global_position.x, street.FLOOR_Y - 16.0)
		var influence := light.energy * clampf(1.0 - light.global_position.distance_to(chest) / float(light.get_meta("radius")), 0.0, 1.0)
		if influence > best_influence:
			best = light
			best_influence = influence
	check(best != null, "At least one street lamp reaches the hero's chest height")
	if best == null:
		return
	player.position = Vector2(best.global_position.x, street.FLOOR_Y)
	player.velocity = Vector2.ZERO
	await frames(6)
	var near := float(material.get_shader_parameter("reflect_strength"))
	observations["lamp_reflect_strength"] = snappedf(near, 0.01)
	check(near > 0.12 + 0.05, "Standing under a street lamp brightens the reflective straps")
	check(float(player.get_node("Sprite/ImplantOverlay").scanned) == 0.0 and not street._scan_label.visible, "No surveillance scan runs on the street")


func verify_prototype_keys(player: CharacterBody2D, material: ShaderMaterial) -> void:
	await tap(KEY_TAB)
	check(player.view_mode == 1 and is_instance_valid(street.player) and street.player == player, "Tab does not switch views in the side-only prototype")
	await tap(KEY_F9)
	check(is_equal_approx(float(material.get_shader_parameter("look")), 0.0), "F9 shows the original hero colours")
	await tap(KEY_F9)
	check(is_equal_approx(float(material.get_shader_parameter("look")), 1.0), "F9 again restores the cyber colours")
	player.position = Vector2(600, 156)
	await tap(KEY_R)
	check(player.position.distance_to(street.START) < 2.0, "R resets the position")


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
