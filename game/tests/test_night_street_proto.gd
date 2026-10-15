extends SceneTree
## Night-street prototype: hero material everywhere, surveillance exposure, combat and hit-stop on hover
## drones, prototype-only controls, and no route into it from the shipped safe house / hospital flow.

const STREET = preload("res://scenes/night_street_proto.tscn")
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
	verify_not_routed()
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
	await verify_exposure(player)
	await verify_combat(player)
	await verify_prototype_keys(player, material)
	finish()


func verify_material_everywhere() -> void:
	var player := PLAYER.instantiate()
	var material := player.get_node("Sprite").material as ShaderMaterial
	check(material != null and material.shader.resource_path == HERO_SHADER, "player.tscn carries the hero shader, so every scene uses it")
	check(material != null and material.resource_local_to_scene, "Each player instance gets its own hero material")
	var palette: Texture2D = material.get_shader_parameter("palette") if material != null else null
	check(palette != null and palette.get_width() == 18 and palette.get_height() == 3, "The hero lookup is 18 x 3")
	if palette != null:
		var image := palette.get_image()
		var found: Array[String] = []
		for index in range(image.get_width()):
			found.append(image.get_pixel(index, 0).to_html(false))
		check(found == PALETTE_SOURCE, "Lookup row 0 lists the 18 colours used by the shipped frames")
		check(is_equal_approx(image.get_pixel(17, 2).a, 1.0) and image.get_pixel(0, 2).a == 0.0, "Blade edge is emissive and the outline is not")
	player.free()


func verify_not_routed() -> void:
	for path in ["res://scripts/core/scene_routes.gd", "res://scripts/levels/home_601/home_601.gd",
			"res://scripts/levels/hospital/hospital_interactions.gd", "res://scripts/levels/hospital/underground_hospital.gd"]:
		check(not FileAccess.get_file_as_string(path).contains("night_street"), path.get_file() + " has no route to the prototype")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn", "The game still starts in the safe house")


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
	player.position = Vector2(820, 156)
	player.velocity = Vector2.ZERO
	await frames(10)
	var after_leaving: float = street.exposure
	check(not street.in_beam and after_leaving < 1.0, "Leaving the beam lowers exposure")
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
	player.position = Vector2(target.global_position.x - 18.0, 156)
	player.velocity = Vector2.ZERO
	player.facing = "right"
	player.call("_show_idle")
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
