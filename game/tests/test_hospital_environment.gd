extends "res://tests/support/isolated_suite.gd"

const HOSPITAL = preload("res://scenes/underground_hospital.tscn")
const HOSPITAL_PATH := "res://scenes/underground_hospital.tscn"
const HOME_PATH := "res://scenes/home_601.tscn"
var environment: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("Hospital integration suite timed out")
		quit(2)
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


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func release() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_SPACE, KEY_R, KEY_TAB, KEY_F7]:
		key(code, false)


func tap(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(4)


func walk_to(code: Key, target_x: float, direction: int) -> void:
	key(code, true)
	for _step in range(330):
		await frames(1)
		if (environment.player.position.x - target_x) * direction >= 0.0:
			break
	key(code, false)
	await frames(6)


func count_characters(node: Node) -> int:
	var result := 1 if node is CharacterBody2D else 0
	for child in node.get_children():
		result += count_characters(child)
	return result


func fixtures_in_bounds(config: Dictionary, native_size: Vector2i) -> bool:
	var bounds := Rect2i(Vector2i.ZERO, native_size)
	for list_name in ["monitors", "fluorescents"]:
		for item in config.get(list_name, []):
			var values: Array = item.get("rect", [])
			if values.size() != 4:
				return false
			var rectangle := Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))
			if not rectangle.has_area() or not bounds.encloses(rectangle):
				return false
	return true


func segment_is_clear(point: Vector2, direction: Vector2, distance: float) -> bool:
	var body := Rect2(point + Vector2(-8, -10), Vector2(16, 12))
	var destination := Rect2(body.position + direction * distance, body.size)
	var swept := body.merge(destination)
	if not Rect2(Vector2.ZERO, Vector2(environment.world_size)).encloses(swept):
		return false
	for item in environment.layout.get("colliders", []):
		var values: Array = item["rect"]
		if swept.intersects(Rect2(values[0], values[1], values[2], values[3])):
			return false
	return true


func movement_fixture(direction: Vector2, distance: float) -> Vector2:
	var start: Array = environment.layout.get("player_start", [110, 300])
	var origin := Vector2(start[0], start[1])
	if segment_is_clear(origin, direction, distance):
		return origin
	for y in range(24, environment.world_size.y - 16, 12):
		for x in range(16, environment.world_size.x - 16, 12):
			var candidate := Vector2(x, y)
			if segment_is_clear(candidate, direction, distance):
				return candidate
	return Vector2(-1, -1)


func place(point: Vector2) -> void:
	release()
	environment.player.position = point
	environment.player.velocity = Vector2.ZERO


func west_wall_fixture() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for item in environment.layout.get("colliders", []):
		var values: Array = item["rect"]
		var rectangle := Rect2(values[0], values[1], values[2], values[3])
		if rectangle.size.y >= environment.world_size.y * 0.8:
			candidates.append({"rectangle": rectangle, "id": String(item["id"])})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return left["rectangle"].position.x < right["rectangle"].position.x
	)
	for item in candidates:
		var rectangle: Rect2 = item["rectangle"]
		for y in range(maxi(16, ceili(rectangle.position.y) + 12), mini(environment.world_size.y - 8, floori(rectangle.end.y)), 12):
			var point := Vector2(rectangle.end.x + 8, y)
			if segment_is_clear(point, Vector2.ZERO, 0.0):
				return {"point": point, "minimum_x": rectangle.end.x + 6.0, "id": item["id"]}
	return {}


func expected_camera() -> Vector2:
	return environment.player.global_position.round().clamp(Vector2(160, 90), Vector2(environment.world_size) - Vector2(160, 90))


func run() -> void:
	environment = HOSPITAL.instantiate()
	root.add_child(environment)
	current_scene = environment
	await frames(5)
	var dimensions: Array = environment.layout.get("native_size", [640, 224])
	var native_size := Vector2i(int(dimensions[0]), int(dimensions[1]))
	check(current_scene.scene_file_path == HOSPITAL_PATH, "hospital loads as its own scene")
	check(root.content_scale_size == Vector2i(320, 180), "viewport retains the original320x180 pixel grid")
	check(environment.background.texture != null, "top-down hospital artwork exists")
	if environment.background.texture != null:
		check(environment.background.texture.get_size() == Vector2(native_size), "top-down artwork matches the shared map size")
	check(environment.background.scale == Vector2.ONE and environment.background.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "background stays sharp at1:1 scale")
	check(environment.camera.zoom == Vector2.ONE, "camera shows a local view without overview downsampling")
	check(not environment.camera.position_smoothing_enabled, "follow camera has no fractional smoothing")
	check(environment.view_mode == 0 and environment.player.view_mode == 0, "hospital begins in top-down mode")
	check(count_characters(root) == 1, "only the approved player exists; noNPCs or enemies")
	check(environment.player.scene_file_path == "res://scenes/player.tscn", "hospital reuses the original player scene")
	check(environment.player.get_node("Sprite").sprite_frames == load("res://assets/top_down.tres"), "top-down uses the approved original animation resource")
	check(environment.player.scale == Vector2.ONE and environment.player.get_node("Sprite").scale == Vector2.ONE, "player pixels retain their original1:1 scale")
	check(environment.base_layout.get("rooms", []).size() > 1 and not environment.shared_room_id.is_empty(), "shared hospital rooms and current room are registered")
	check(environment.interactions != null and environment.interactions.get_parent() == environment, "environment interactions live outside the replaceable view world")
	var interactions_id: int = environment.interactions.get_instance_id()
	check(environment.layout.get("colliders", []).size() >= 4, "top-down hospital provides solid architecture")
	var valid_bodies := true
	for item in environment.layout.get("colliders", []):
		var body: Node = environment.world.get_node_or_null(NodePath(String(item["id"])))
		if not body is StaticBody2D or body.collision_layer != 1 or body.collision_mask != 0:
			valid_bodies = false
	check(valid_bodies, "architectural colliders block the original player collision mask")
	check(fixtures_in_bounds(environment.layout, native_size), "top-down ambient fixtures are inside the artwork")
	check(environment.layout.get("monitors", []).size() > 0 and environment.layout.get("fluorescents", []).size() > 0, "hospital has monitor and fluorescent ambience")
	check(environment.camera.position == expected_camera(), "initial camera follows the player and clamps near map edges")
	for sample in [{"code": KEY_W, "direction": Vector2.UP}, {"code": KEY_A, "direction": Vector2.LEFT}, {"code": KEY_S, "direction": Vector2.DOWN}, {"code": KEY_D, "direction": Vector2.RIGHT}]:
		var fixture := movement_fixture(sample["direction"], 20.0)
		if fixture.x < 0:
			check(false, "safe movement fixture exists for " + str(sample["code"]))
			continue
		place(fixture)
		await frames(2)
		key(sample["code"], true)
		await frames(12)
		key(sample["code"], false)
		var end: Vector2 = environment.player.position
		check((end - fixture).dot(sample["direction"]) > 5.0, "physical WASD moves the original player " + str(sample["code"]))
		await frames(3)
	var run_fixture := movement_fixture(Vector2.RIGHT, 48.0)
	check(run_fixture.x >= 0, "hospital has a clear movement stretch for run verification")
	if run_fixture.x >= 0:
		place(run_fixture)
		await frames(2)
		key(KEY_D, true)
		await frames(16)
		key(KEY_D, false)
		var walked: float = environment.player.position.x - run_fixture.x
		place(run_fixture)
		await frames(2)
		key(KEY_SHIFT, true)
		await frames(12)
		key(KEY_D, true)
		await frames(16)
		release()
		var ran: float = environment.player.position.x - run_fixture.x
		check(ran > walked * 1.5, "holding Shift keeps the approved faster run")
		observations["walk_run_distance"] = [walked, ran]
	var boundary := west_wall_fixture()
	check(not boundary.is_empty(), "a safe fixture exists beside the outer west wall")
	if not boundary.is_empty():
		place(boundary["point"])
		await frames(2)
		key(KEY_A, true)
		await frames(40)
		key(KEY_A, false)
		check(environment.player.position.x >= float(boundary["minimum_x"]) - 0.25 and environment.player.position.x >= 0.0, "walking cannot cross the solid outer hospital wall")
		observations["wall_collision"] = {"id": boundary["id"], "position": str(environment.player.position)}
	await frames(3)
	check(environment.camera.position == expected_camera(), "camera follows completed player movement")
	check(environment.camera.position == environment.camera.position.round(), "follow camera stays on integer native pixels")
	environment.player.set_physics_process(false)
	environment.player.position = Vector2.ZERO
	await frames(3)
	check(environment.camera.position == Vector2(160, 90), "camera clamps at the top-left map edge")
	environment.player.position = Vector2(native_size)
	await frames(3)
	check(environment.camera.position == Vector2(native_size) - Vector2(160, 90), "camera clamps at the bottom-right map edge")
	check(environment.camera.zoom == Vector2.ONE, "edge following preserves the local1:1 camera scale")
	environment.player.set_physics_process(true)
	environment.reset_view()
	await frames(3)
	await tap(KEY_R)
	var start: Array = environment.layout.get("player_start", [110, 300])
	check(environment.player.position.distance_to(Vector2(start[0], start[1])) < 0.5, "R resets the player to the current view spawn")
	var top_position: Vector2 = environment.player.position
	var room_before: String = environment.shared_room_id
	var previous_ticks: int = environment.environment_ticks
	await frames(18)
	check(environment.environment_ticks > previous_ticks, "monitor scans and fluorescent flicker advance")
	await tap(KEY_TAB)
	check(environment.view_mode == 1 and environment.player.view_mode == 1, "physical Tab switches to the original side-view controller")
	check(environment.player.get_node("Sprite").sprite_frames == load("res://assets/side_view.tres"), "side view uses the approved original animation resource")
	check(environment.shared_room_id == room_before, "switching views preserves the same semantic room")
	check(count_characters(root) == 1, "view replacement keeps exactly one player and noNPCs")
	check(environment.background.texture != null and environment.background.texture.get_size() == Vector2(environment.world_size), "side view has its corresponding cutaway artwork")
	check(fixtures_in_bounds(environment.layout, environment.world_size), "side-view ambient fixtures match cutaway bounds")
	check(environment.camera.zoom == Vector2.ONE and environment.camera.position == expected_camera(), "side view keeps the same local camera scale and follow behavior")
	environment.reset_view()
	await frames(16)
	check(environment.player.is_on_floor(), "side-view spawn settles on a real hospital platform")
	var side_start: Vector2 = environment.player.position
	key(KEY_D, true)
	await frames(12)
	key(KEY_D, false)
	check(environment.player.position.x > side_start.x + 4.0, "side-view D walks along the hospital floor")
	environment.reset_view()
	await frames(8)
	side_start = environment.player.position
	key(KEY_A, true)
	await frames(12)
	key(KEY_A, false)
	check(environment.player.position.x < side_start.x - 4.0, "side-view A walks in the opposite direction")
	environment.reset_view()
	await frames(8)
	key(KEY_S, true)
	await frames(10)
	check(environment.player.is_crouching and environment.player.get_node("BodyShape").shape.size.y < 26.0, "side-view S preserves approved crouching")
	key(KEY_S, false)
	await frames(18)
	check(not environment.player.is_crouching, "releasing S restores standing")
	var ground_y: float = environment.player.position.y
	key(KEY_SPACE, true)
	await frames(2)
	key(KEY_SPACE, false)
	var highest_y: float = environment.player.position.y
	for _index in range(12):
		await frames(1)
		highest_y = minf(highest_y, environment.player.position.y)
	check(highest_y < ground_y - 8.0, "side-view Space jumps above the floor")
	await frames(75)
	check(environment.player.is_on_floor(), "side-view jump lands on hospital collision geometry")
	check(environment.camera.position == expected_camera(), "camera follows side-view jumping and landing")
	environment.reset_view()
	await frames(6)
	await tap(KEY_TAB)
	check(environment.view_mode == 0 and environment.player.get_node("Sprite").sprite_frames == load("res://assets/top_down.tres"), "another Tab restores the original top-down character")
	check(environment.shared_room_id == room_before, "returning views retains the matching hospital room")
	check(environment.player.position.distance_to(top_position) < 1.0, "returning to a safe room restores its cached top-down position")
	check(count_characters(root) == 1, "round-trip switching does not accumulate players")
	check(environment.interactions.get_instance_id() == interactions_id, "switching hospital views preserves the same interaction component")
	observations["native_size"] = [native_size.x, native_size.y]
	observations["room_id"] = environment.shared_room_id
	observations["environment_ticks"] = environment.environment_ticks
	# Actual staircase transitions and floor isolation in both projections.
	check(environment.floor_id == 1 and environment.world_size == Vector2i(640, 224), "top-down starts on its isolated first-floor map")
	environment.player.position = Vector2(74, 174)
	environment.player.velocity = Vector2.ZERO
	await frames(2)
	key(KEY_E, true)
	await frames(2)
	key(KEY_E, false)
	await frames(3)
	check(environment.floor_id == 2, "E at the first-floor stair actually goes upstairs")
	check(environment.background.texture.resource_path.ends_with("hospital_floor_2_native.png"), "upstairs shows only the second-floor artwork")
	check(environment.room_for_position(environment.player.position, 0) == "reception", "upstairs arrives at the matching reception landing")
	check(environment.world_size == Vector2i(640, 224) and environment.camera.zoom == Vector2.ONE, "upstairs remains local pixel-perfect rather than whole-building overview")
	await tap(KEY_TAB)
	check(environment.view_mode == 1 and environment.floor_id == 2, "Tab from upstairs maps to the upper side-view level")
	check(environment.shared_room_id == "reception", "upper side view retains the same hospital room")
	environment.player.position = Vector2(30, 164)
	environment.player.velocity = Vector2.ZERO
	await frames(3)
	key(KEY_E, true)
	await frames(2)
	key(KEY_E, false)
	check(not environment.stairs_busy and environment.player.is_physics_processing(), "side-view stair entry keeps the original controller freely active")
	await walk_to(KEY_D, 166.0, 1)
	check(environment.player.is_on_floor() and environment.floor_id == 1, "physically walking down the selected straight stair reaches the lower floor")
	check(absf(environment.player.position.y - 286.0) < 1.0, "side-view protagonist stands on the real lower floor")
	check(environment.camera.position == expected_camera(), "camera follows the entire stair traversal")
	key(KEY_W, true)
	await frames(2)
	key(KEY_W, false)
	await walk_to(KEY_A, 22.0, -1)
	check(environment.player.is_on_floor() and absf(environment.player.position.y - 164.0) < 1.0 and environment.floor_id == 2, "W selects stairs and A physically walks back upstairs")
	await tap(KEY_TAB)
	check(environment.view_mode == 0 and environment.floor_id == 2, "side-to-top switching shows only the current upper floor")
	environment.player.position = Vector2(71, 124)
	environment.player.velocity = Vector2.ZERO
	await frames(2)
	key(KEY_E, true)
	await frames(2)
	key(KEY_E, false)
	await frames(3)
	check(environment.floor_id == 1 and environment.background.texture.resource_path.ends_with("hospital_floor_1_native.png"), "top-down staircase returns to the independent lower-floor map")
	check(count_characters(root) == 1, "stairs and both projections keep one original player and noNPCs")
	if root.has_node("SceneRoutes"):
		await tap(KEY_F7)
		check(current_scene.scene_file_path == HOME_PATH, "F7 returns from hospital to the existing home")
		await tap(KEY_F7)
		check(current_scene.scene_file_path == HOSPITAL_PATH, "F7 reopens the hospital from home")
		check(current_scene.view_mode == 0 and root.content_scale_size == Vector2i(320, 180), "returning to hospital starts top-down with the approved native grid")
		check(count_characters(root) == 1, "scene routing keeps one player without leftover home actors")
	release()
	var report := {"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "observations": observations}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	var file := FileAccess.open("res://evidence/hospital_test_results_v11.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
