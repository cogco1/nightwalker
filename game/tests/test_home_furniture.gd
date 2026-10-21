extends "res://tests/support/isolated_suite.gd"
## Furnished safehouse: actual input travels through the apartment, backed by a
## complete native-pixel foot-space search with a real collision safety margin.

const CONTROLS = preload("res://scripts/core/controls.gd")
const HOME := "res://scenes/home_601.tscn"
const CARDINALS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const FURNITURE := ["bookshelf", "repair_desk", "stool", "storage_box", "folding_chair"]
const VISIT_ORDER := ["computer", "fridge", "bookshelf", "repair_desk", "door", "frame", "television", "bed", "dumbbells", "storage_box"]
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var home: Node2D
var player: CharacterBody2D
var walkable: Dictionary = {}
var _held_key := 0
var _finished := false
var _travel_frames := 0


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(180.0).timeout.connect(func() -> void:
		check(false, "Furnished safehouse completes before its deadline")
		finish()
	)
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)


func frames(count := 1) -> void:
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


func hold(code: int) -> void:
	if code == _held_key:
		return
	if _held_key != 0:
		key(_held_key, false)
	_held_key = code
	if code != 0:
		key(code, true)


func tap(code: int) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(3)


func rectangle(values: Array) -> Rect2:
	return Rect2(values[0], values[1], values[2], values[3])


func can_stand(point: Vector2, margin := 0.25) -> bool:
	var foot := Rect2(point + Vector2(-6, -8), Vector2(12, 8)).grow(margin)
	for item in home.layout["colliders"]:
		if foot.intersects(rectangle(item["rect"])):
			return false
	return true


func physically_clear(point: Vector2) -> bool:
	var shape := player.get_node("BodyShape") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.transform = Transform2D(0, point + shape.position)
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	return home.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func find_item(id: String) -> Dictionary:
	for item in home.layout["interactions"]:
		if item["id"] == id:
			return item
	return {}


func nearest_id(point: Vector2) -> String:
	var closest := ""
	var best := INF
	for item in home.layout["interactions"]:
		var anchor := Vector2(item["anchor"][0], item["anchor"][1])
		var distance := point.distance_to(anchor)
		if distance <= float(item["radius"]) and distance < best:
			closest = String(item["id"])
			best = distance
	return closest


func reachable_from(start: Vector2i, permitted: Dictionary) -> Dictionary:
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var point := queue[cursor]
		cursor += 1
		for direction in CARDINALS:
			var candidate: Vector2i = point + direction
			if permitted.has(candidate) and not visited.has(candidate):
				visited[candidate] = true
				queue.append(candidate)
	return visited


func verify_geometry() -> void:
	var background := home.world.get_node("HomeBackground") as Sprite2D
	check(background.texture.get_size() == Vector2(320, 180) and background.scale == Vector2.ONE,
		"new furniture is drawn on the same 320 by 180 native canvas at scale one")
	check(background.texture.resource_path == home.layout["background"]
		and background.texture.resource_path.ends_with("home_601_furnished_native.png"),
		"the playable safehouse uses the furnished artwork selected by its layout")
	check(FileAccess.file_exists("res://assets/home_601/home_601_native.png"), "the previous original artwork remains available")
	check(root.content_scale_size == Vector2i(320, 180) and player.scale == Vector2.ONE,
		"the character and logical pixel grid retain their original size")
	check(background.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "furniture retains nearest-neighbour pixel drawing")
	verify_material_pixels(background.texture.get_image())
	for id in FURNITURE:
		var body := home.world.get_node_or_null(NodePath(id)) as StaticBody2D
		check(body != null and body.collision_layer == 1, "new furniture is solid in the playable scene: " + id)
	var labels := home.get_node("HomeUI").find_children("*", "Label", true, false)
	check(not labels.is_empty() and labels.all(func(label: Label) -> bool: return label.get_theme_font_size("font_size") == 12),
		"the safehouse keeps its clear 12 pixel Chinese text")
	check(can_stand(player.position) and physically_clear(player.position), "the unchanged spawn is clear of all old and new furniture")
	var bounds := rectangle(home.layout["bounds"])
	for y in range(int(bounds.position.y), int(bounds.end.y) + 1):
		for x in range(int(bounds.position.x), int(bounds.end.x) + 1):
			var point := Vector2i(x, y)
			if can_stand(Vector2(point)):
				walkable[point] = true
	var start := Vector2i(player.position.round())
	var reachable := reachable_from(start, walkable)
	check(reachable.size() == walkable.size(), "every native-pixel standing point remains connected with collision safety clearance")
	observations["foot_space"] = {"standable_points": walkable.size(), "connected_points": reachable.size(), "safety_margin": 0.25}
	for point in [Vector2i(50, 151), Vector2i(221, 70), Vector2i(220, 114), Vector2i(221, 87)]:
		check(walkable.has(point) and reachable.has(point), "kitchen, bedroom and doorway have no newly sealed standing pocket: " + str(point))
	for id in VISIT_ORDER:
		var item := find_item(id)
		var count := 0
		for point in reachable:
			if nearest_id(Vector2(point)) == id:
				count += 1
		check(not item.is_empty() and count > 0, "an accessible foot point can actually select the interaction: " + id)


func verify_material_pixels(picture: Image) -> void:
	# Sample open floor in the kitchen, living room and bedroom. A majority must
	# read as warm brown without fixing a palette or rejecting dark grain marks.
	var floor_samples := {
		"kitchen": Rect2i(52, 84, 28, 28),
		"living_room": Rect2i(118, 136, 36, 12),
		"bedroom": Rect2i(239, 143, 42, 7),
	}
	var material_observations: Dictionary = {}
	for room in floor_samples:
		var area: Rect2i = floor_samples[room]
		var warm_pixels := 0
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var colour: Color = picture.get_pixel(x, y)
				if colour.r > colour.g + 2.0 / 255.0 and colour.g > colour.b + 2.0 / 255.0 and colour.r - colour.b >= 8.0 / 255.0:
					warm_pixels += 1
		var fraction := float(warm_pixels) / float(area.size.x * area.size.y)
		check(fraction >= 0.60, "the actual floor artwork is predominantly warm brown in the " + String(room))
		material_observations[room] = {"warm_pixel_fraction": fraction, "sample_rect": str(area)}
	var original_texture := load("res://assets/home_601/home_601_native.png") as Texture2D
	var original: Image = original_texture.get_image()
	var screen_samples := {"computer": Rect2i(52, 44, 14, 8), "television": Rect2i(178, 48, 16, 10)}
	for id in screen_samples:
		var area: Rect2i = screen_samples[id]
		var unchanged := true
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				unchanged = unchanged and picture.get_pixel(x, y).is_equal_approx(original.get_pixel(x, y))
		check(unchanged, "the room repaint preserves the original screen pixels at the live animation's coordinates: " + String(id))
	observations["material_pixels"] = material_observations


func closest_walkable(point: Vector2) -> Vector2i:
	var chosen := Vector2i.ZERO
	var best := INF
	for candidate in walkable:
		if not can_stand(Vector2(candidate), 0.8):
			continue
		var distance := point.distance_squared_to(Vector2(candidate))
		if distance < best:
			best = distance
			chosen = candidate
	return chosen


func interaction_point(id: String) -> Vector2i:
	var item := find_item(id)
	if item.is_empty():
		return Vector2i.ZERO
	var anchor := Vector2(item["anchor"][0], item["anchor"][1])
	var chosen := Vector2i.ZERO
	var best := INF
	for candidate in walkable:
		if not can_stand(Vector2(candidate), 0.8) or nearest_id(Vector2(candidate)) != id:
			continue
		var distance := anchor.distance_squared_to(Vector2(candidate))
		if distance < best:
			best = distance
			chosen = candidate
	return chosen


func path_to(destination: Vector2i) -> Array[Vector2i]:
	var start := closest_walkable(player.position)
	var parents := {start: start}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size() and not parents.has(destination):
		var point := queue[cursor]
		cursor += 1
		for direction in CARDINALS:
			var candidate: Vector2i = point + direction
			if not walkable.has(candidate) or parents.has(candidate) or not can_stand(Vector2(candidate), 0.8):
				continue
			parents[candidate] = point
			queue.append(candidate)
	if not parents.has(destination):
		return []
	var path: Array[Vector2i] = [destination]
	while path[-1] != start:
		path.append(parents[path[-1]])
	path.reverse()
	var corners: Array[Vector2i] = []
	for index in range(1, path.size() - 1):
		if path[index] - path[index - 1] != path[index + 1] - path[index]:
			corners.append(path[index])
	if corners.is_empty() or corners[-1] != destination:
		corners.append(destination)
	return corners


func move_to(point: Vector2i) -> bool:
	# This drives the real action map; positions, velocities and colliders are never
	# rewritten to make a path pass. Short taps settle each corner before turning.
	for _attempt in range(55):
		var delta: Vector2 = Vector2(point) - player.position
		if delta.length() <= 0.48:
			return true
		var horizontal := absf(delta.x) >= absf(delta.y)
		var distance := absf(delta.x) if horizontal else absf(delta.y)
		var code := (KEY_D if delta.x > 0 else KEY_A) if horizontal else (KEY_S if delta.y > 0 else KEY_W)
		hold(code)
		if distance > 3.0:
			var still := 0
			var previous: Vector2 = player.position
			for _tick in range(400):
				await frames()
				_travel_frames += 1
				still = still + 1 if player.position.distance_to(previous) < 0.01 else 0
				previous = player.position
				if still >= 12:
					hold(0)
					await frames(6)
					return false
				var remaining: float = absf(point.x - player.position.x) if horizontal else absf(point.y - player.position.y)
				if remaining <= 2.0:
					break
		else:
			var ticks := 1 if distance < 1.4 else 2
			await frames(ticks)
			_travel_frames += ticks
		hold(0)
		await frames(6)
		_travel_frames += 6
	return false


func walk_to(point: Vector2i, label: String) -> bool:
	var path := path_to(point)
	if path.is_empty():
		check(false, "real input has a route to " + label)
		return false
	for corner in path:
		if not await move_to(corner):
			check(false, "real input reaches " + label + " without sticking at " + str(corner) + "; actual " + str(player.position))
			return false
	check(player.position.distance_to(Vector2(point)) <= 0.6 and physically_clear(player.position),
		"real directional input reaches a clear foot point at " + label)
	return true


func verify_travel() -> void:
	var visited: Array[String] = []
	for id in VISIT_ORDER:
		var point := interaction_point(id)
		if not await walk_to(point, id):
			continue
		await frames(2)
		check(home.nearest_interaction == id, "the actual nearby-item selector chooses " + id)
		visited.append(id)
		await tap(KEY_E)
		check(home.dialogue_active and home.current_interaction == id, "E opens the old or new furniture dialogue: " + id)
		await tap(KEY_ESCAPE)
		check(not home.dialogue_active and not player.is_frozen(), "closing the dialogue restores movement: " + id)
	await walk_to(Vector2i(50, 151), "the strip below the kitchen counter")
	await walk_to(Vector2i(221, 70), "the passage between the partition and bedside cabinet")
	await walk_to(Vector2i(110, 104), "the original spawn, after leaving the bedroom")
	observations["real_input_tour"] = {"visited": visited, "physics_frames": _travel_frames,
		"ending_position": [player.position.x, player.position.y]}


func lights(scene: Node) -> Array[PointLight2D]:
	var result: Array[PointLight2D] = []
	for node in scene.find_children("*", "PointLight2D", true, false):
		result.append(node as PointLight2D)
	return result


func active(light: PointLight2D) -> bool:
	return light.enabled and light.is_visible_in_tree() and light.energy > 0.001


func hero_light() -> Dictionary:
	var material := (player.get_node("Sprite") as AnimatedSprite2D).material as ShaderMaterial
	return {"colour": Color(material.get_shader_parameter("rim_a_color")),
		"reflection": float(material.get_shader_parameter("reflect_strength")),
		"direction": Vector2(material.get_shader_parameter("rim_a_dir"))}


func verify_warm_light() -> void:
	var warm := lights(home).filter(func(light: PointLight2D) -> bool: return String(light.get_meta("kind", "")) == "lamp")
	var cool := lights(home).filter(func(light: PointLight2D) -> bool: return String(light.get_meta("kind", "")) == "screen")
	check(warm.size() >= 2 and warm.all(func(light: PointLight2D) -> bool: return active(light) and light.color.r > light.color.b + 0.15),
		"two real amber lamps contrast with the cold interior")
	check(cool.size() >= 2 and cool.all(func(light: PointLight2D) -> bool: return active(light) and light.color.b > light.color.r),
		"both original cold screens still illuminate the safehouse")
	home.set_device_power("computer", false)
	home.set_device_power("television", false)
	await frames(6)
	check(cool.all(func(light: PointLight2D) -> bool: return not active(light))
		and warm.all(func(light: PointLight2D) -> bool: return active(light)),
		"switching off both screens leaves the warm lamps independently powered")
	if not warm.is_empty():
		var selected: PointLight2D = warm[0]
		for light in warm:
			home.lighting.set_source_power(String(light.get_meta("source_id", "")), light == selected)
		var near := closest_walkable(selected.global_position + Vector2(0, 22))
		if await walk_to(near, "the warm desk lamp"):
			await frames(8)
			var lit := hero_light()
			home.lighting.set_source_power(String(selected.get_meta("source_id", "")), false)
			await frames(8)
			var dark := hero_light()
			var tint: Color = lit["colour"]
			check(tint.r > tint.b and tint.a > Color(dark["colour"]).a + 0.01,
				"the warm lamp actually gives the nearby hero an amber rim, removed when switched off")
			check(float(lit["reflection"]) > float(dark["reflection"]), "the same warm lamp brightens the character's reflective details")
			observations["warm_hero"] = {"lamp": selected.get_meta("source_id"), "lit": lit, "dark": dark}
	for light in warm:
		home.lighting.set_source_power(String(light.get_meta("source_id", "")), true)
	home.set_device_power("computer", true)
	home.set_device_power("television", true)
	await frames(6)
	check(warm.all(func(light: PointLight2D) -> bool: return active(light)) and cool.all(func(light: PointLight2D) -> bool: return active(light)),
		"cold screens and warm lamps can all operate together after independent power changes")


func run() -> void:
	check(change_scene_to_file(HOME) == OK, "the furnished playable safehouse opens")
	await frames(12)
	home = current_scene as Node2D
	player = home.get("player") as CharacterBody2D
	verify_geometry()
	await verify_travel()
	await verify_warm_light()
	hold(0)
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	hold(0)
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_ESCAPE]:
		key(code, false)
	print(JSON.stringify({"suite": "home_furniture", "status": "passed" if failures.is_empty() else "failed",
		"checks": checks, "failures": failures, "observations": observations}))
	quit(0 if failures.is_empty() else 1)
