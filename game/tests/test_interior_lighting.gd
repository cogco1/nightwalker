extends "res://tests/support/isolated_suite.gd"
## Regression from the safehouse interior: real fixtures, power interactions and visual-only character light.

const CONTROLS = preload("res://scripts/core/controls.gd")
const HOME := "res://scenes/home_601.tscn"
const STREET := "res://scenes/night_street_proto.tscn"
const HERO_SHADER := "res://shaders/character_cyber.gdshader"
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var _finished := false


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(90.0).timeout.connect(func() -> void:
		check(false, "Interior lighting finishes before its deadline")
		finish()
	)
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)


func frames(count := 4) -> void:
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
	await frames(3)


func open_scene(path: String) -> Node2D:
	check(change_scene_to_file(path) == OK, "Playable scene opens: " + path)
	await frames(12)
	return current_scene as Node2D


func lights(scene: Node) -> Array[PointLight2D]:
	var result: Array[PointLight2D] = []
	var world: Node = scene.get("world")
	if is_instance_valid(world):
		for candidate in world.find_children("*", "PointLight2D", true, false):
			result.append(candidate as PointLight2D)
	return result


func source(scene: Node, id: String) -> PointLight2D:
	for light in lights(scene):
		if String(light.get_meta("source_id", "")) == id:
			return light
	return null


func active(light: PointLight2D) -> bool:
	return is_instance_valid(light) and light.enabled and light.is_visible_in_tree() and light.energy > 0.001


func collider_signature(world: Node) -> Array[String]:
	var result: Array[String] = []
	for body in world.find_children("*", "StaticBody2D", true, false):
		var entry := "%s:%s:%d:%d" % [body.name, body.transform, body.collision_layer, body.collision_mask]
		for shape in body.get_children():
			if shape is CollisionShape2D:
				entry += ":%s:%s:%s:%s" % [shape.transform, shape.shape.get_class(), shape.shape.get_rect(), shape.one_way_collision]
			elif shape is CollisionPolygon2D:
				entry += ":%s:%s:%s" % [shape.transform, shape.polygon, shape.one_way_collision]
		result.append(entry)
	return result


func hud_signature(scene: Node) -> Array[String]:
	var result: Array[String] = []
	for child in scene.get_children():
		if not child is CanvasLayer or child.layer < 20:
			continue
		for label in child.get_children():
			if label is Label:
				result.append("%s:%d:%s:%s:%s:%d" % [child.name, child.layer, label.position,
					label.size, label.modulate, label.get_theme_font_size("font_size")])
	return result


func verify_environment(scene: Node, label: String) -> void:
	var component: Node = scene.get("lighting")
	check(is_instance_valid(component) and component.get_parent() == scene, label + ": lighting belongs to the persistent scene root")
	if not is_instance_valid(component):
		return
	var ambients := scene.find_children("*", "CanvasModulate", true, false)
	var environments := scene.find_children("*", "WorldEnvironment", true, false)
	check(ambients.size() == 1, label + ": there is one ambient treatment")
	check(environments.size() == 1, label + ": there is one world environment")
	if ambients.size() == 1:
		check((ambients[0] as CanvasModulate).color != Color.WHITE, label + ": ambient actually changes the interior light")
	if environments.size() == 1:
		var environment := (environments[0] as WorldEnvironment).environment
		check(environment != null and environment.glow_enabled, label + ": emissive glow is enabled")
	var rigs := (scene.get("world") as Node).find_children("InteriorLightRig", "Node2D", true, false)
	check(rigs.size() == 1, label + ": exactly one light rig belongs to the current world")
	check(root.content_scale_size == Vector2i(320, 180), label + ": the logical pixel grid is unchanged")
	var player: CharacterBody2D = scene.get("player")
	var sprite := player.get_node("Sprite") as AnimatedSprite2D
	var material := sprite.material as ShaderMaterial
	check(player.scale == Vector2.ONE and sprite.scale == Vector2.ONE, label + ": character scale remains one")
	check(material != null and material.shader.resource_path == HERO_SHADER, label + ": the existing hero material is retained")
	check((player.get_node("BodyShape") as CollisionShape2D).shape.get_rect().size == (Vector2(12, 8) if player.view_mode == 0 else Vector2(12, 26)), label + ": lighting does not resize the player collider")
	check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST or player.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, label + ": character textures retain nearest filtering")
	check(lights(scene).all(func(light: PointLight2D) -> bool: return light.get_parent().name == "Lights" and float(light.get_meta("radius", 0.0)) > 0.0), label + ": actual lights have bounded reach in the world")


func hero_sample(player: CharacterBody2D) -> Dictionary:
	var material := (player.get_node("Sprite") as AnimatedSprite2D).material as ShaderMaterial
	return {"direction": Vector2(material.get_shader_parameter("rim_a_dir")),
		"rim": Color(material.get_shader_parameter("rim_a_color")).a,
		"reflection": float(material.get_shader_parameter("reflect_strength"))}


func effective_z(item: CanvasItem) -> int:
	var value := item.z_index
	var parent := item.get_parent()
	while item.z_as_relative and parent is CanvasItem:
		item = parent as CanvasItem
		value += item.z_index
		parent = item.get_parent()
	return value


func verify_screen_layers(home: Node2D, id: String, powered: bool) -> void:
	var holder: Node = home.world.get_node_or_null("InteriorLightRig/FixtureEmission")
	var emission: CanvasItem = holder.get_node_or_null("Emission_" + id) as CanvasItem if holder != null else null
	var cover: CanvasItem = holder.get_node_or_null("Off_" + id) as CanvasItem if holder != null else null
	check(emission != null and cover != null, "home: screen has an actual emissive image and off cover: " + id)
	if emission == null or cover == null:
		return
	check(emission.visible == powered and cover.visible != powered, "home: screen image and dark cover follow the real device state: " + id)
	check(effective_z(emission) > effective_z(home.prop_effects) and effective_z(cover) > effective_z(home.prop_effects), "home: animated screen copying cannot paint over emission or the off cover: " + id)


func verify_position_response(scene: Node2D, chosen: PointLight2D, label: String) -> void:
	check(chosen != null, label + ": a real source is available for position checks")
	if chosen == null:
		return
	var component: Node = scene.get("lighting")
	var player: CharacterBody2D = scene.get("player")
	var previous := player.position
	player.freeze(self)
	for light in lights(scene):
		component.call("set_source_power", String(light.get_meta("source_id", "")), light == chosen)
	player.position = chosen.global_position + Vector2(-14, 16)
	await frames(6)
	var left := hero_sample(player)
	player.position = chosen.global_position + Vector2(14, 16)
	await frames(6)
	var right := hero_sample(player)
	player.position = chosen.global_position + Vector2(400, 240)
	await frames(6)
	var far := hero_sample(player)
	check(Vector2(left["direction"]).x > 0.4 and Vector2(right["direction"]).x < -0.4, label + ": the rim changes sides when the player crosses the source")
	check(float(left["rim"]) > float(far["rim"]) + 0.02 and float(right["rim"]) > float(far["rim"]) + 0.02, label + ": the rim fades beyond the source reach")
	check(float(left["reflection"]) > float(far["reflection"]), label + ": reflective straps brighten near the source")
	observations[label] = {"left": left, "right": right, "far": far}
	player.position = previous
	player.unfreeze(self)
	for light in lights(scene):
		component.call("set_source_power", String(light.get_meta("source_id", "")), true)
	await frames()


func verify_home(home: Node2D) -> void:
	verify_environment(home, "home")
	var before_colliders := collider_signature(home.world)
	var before_hud := hud_signature(home)
	var previous_x: float = home.player.position.x
	key(KEY_D, true)
	await frames(10)
	key(KEY_D, false)
	await frames(6)
	check(home.player.position.x > previous_x + 4.0, "home: ordinary movement works under the light treatment")
	home.reset_home()
	for id in ["computer", "television"]:
		var light := source(home, id)
		check(light != null and active(light), "home: the powered screen emits light: " + id)
		if light == null:
			continue
		var prop: Dictionary = {}
		for item in home.layout["colliders"]:
			if item["id"] == id:
				prop = item
		var values: Array = prop.get("rect", [0, 0, 0, 0])
		check(Rect2(values[0], values[1], values[2], values[3]).has_point(light.global_position), "home: screen light originates inside its existing prop: " + id)
		home.call("set_device_power", id, false)
		await frames(6)
		check(not active(light), "home: switching off the screen removes its light: " + id)
		verify_screen_layers(home, id, false)
		home.call("set_device_power", id, true)
		await frames(6)
		check(active(light), "home: switching the screen back on restores its light: " + id)
		verify_screen_layers(home, id, true)
	var tv_frame: int = home.prop_effects.tv_frame
	await frames(10)
	check(home.prop_effects.tv_frame != tv_frame, "home: the television's original animated image continues")
	await verify_position_response(home, source(home, "computer"), "home_position")
	check(collider_signature(home.world) == before_colliders, "home: screen switching and character illumination leave all solid geometry unchanged")
	check(hud_signature(home) == before_hud, "home: the existing HUD retains its layout, font and colour")
	var component: Node = home.lighting
	var first_id := component.get_instance_id()
	for _index in range(3):
		component.call("refresh_context", home.world, home.player, {"profile": "home"})
		await frames(3)
	check(home.lighting.get_instance_id() == first_id and home.world.find_children("InteriorLightRig", "Node2D", true, false).size() == 1, "home: refreshing the same scene cannot stack lighting")


func run() -> void:
	var home := await open_scene(HOME)
	check(home.get("lighting") != null, "home exposes the interior light treatment")
	if home.get("lighting") == null:
		finish()
		return
	await verify_home(home)
	await open_scene(STREET)
	home = await open_scene(HOME)
	verify_environment(home, "home_after_return")
	check(root.find_children("*", "CanvasModulate", true, false).size() == 1 and root.find_children("*", "WorldEnvironment", true, false).size() == 1, "scene travel frees the previous scene's ambient and glow")
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	for code in [KEY_E, KEY_ESCAPE, KEY_D]:
		key(code, false)
	var report := {"suite": "interior_lighting", "status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "observations": observations}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
