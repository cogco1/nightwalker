extends "res://tests/support/isolated_suite.gd"
## Fast native-pixel and terrain integration checks. The scene's --battlefield-smoke covers the full map.

const SCENE = preload("res://scenes/battlefield_run_test.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const OUTPUT := "res://evidence/battlefield_run_test/"
var scene: Node2D
var checks := 0
var failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	create_timer(35.0).timeout.connect(func() -> void:
		check(false, "Battlefield regression finishes before its deadline")
		finish())
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func ticks(count: int) -> void:
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


func run() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	scene = SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await ticks(12)
	check(scene.ready_for_test, "The delivered panorama and ground profile load")
	if not scene.ready_for_test:
		finish()
		return
	var player: CharacterBody2D = scene.player
	var mid_image := Image.new()
	var mid_load_status := mid_image.load_png_from_buffer(FileAccess.get_file_as_bytes(scene.MID_BACKGROUND_PATH))
	var near_image := Image.new()
	var near_load_status := near_image.load_png_from_buffer(FileAccess.get_file_as_bytes(scene.BACKGROUND_PATH))
	var far_image := Image.new()
	var far_load_status := far_image.load_png_from_buffer(FileAccess.get_file_as_bytes(scene.FAR_BACKGROUND_PATH))
	var foreground_image := Image.new()
	var foreground_load_status := foreground_image.load_png_from_buffer(FileAccess.get_file_as_bytes(scene.FOREGROUND_PATH))
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/boot.tscn", "The normal chapter entry point is unchanged")
	check(player.view_mode == 1 and player.is_on_floor(), "The shipped side-view player stands on the new lowland")
	check(is_equal_approx(player.floor_max_angle, deg_to_rad(65.0)) and player.gravity == 620.0
		and player.jump_velocity == -225.0 and player.move_speed == 60.0 and player.run_speed == 138.0,
		"Only this playground accepts 65-degree stairs; existing jump and movement parameters stay unchanged")
	check(player.scale == Vector2.ONE and scene.foreground.scale == Vector2.ONE and scene.background.scale == Vector2.ONE and scene.far_background.scale == Vector2.ONE
		and scene.mid_background.scale == Vector2.ONE and scene.camera.zoom == Vector2.ONE,
		"Hero, all three panoramas and camera preserve the native pixel grid")
	check(scene.world_size == Vector2i(6144, 256) and scene.art_size == Vector2i(6144, 512)
		and scene.background.texture.get_size() == Vector2(scene.art_size),
		"The taller art canvas is separate from the original terrain dimensions")
	check(scene.background.position == Vector2(0, -256) and scene.mid_background.position.y == -256.0
		and scene.far_background.position.y == -256.0 and scene.foreground.position == Vector2(0, -256),
		"All three native art layers extend upward without moving the ground or hero")
	check(scene.near_covers_view() and scene.near_visible_rect().position.y == scene.camera.position.y - 90.0 + 256.0,
		"Near-source sampling includes the negative art origin and stays inside the tall canvas")
	check(scene.far_background.texture.resource_path == scene.FAR_BACKGROUND_PATH
		and scene.far_background.texture.get_size() == Vector2(scene.art_size),
		"The distant city uses its own full-width native panorama")
	check(scene.mid_background.texture.resource_path == scene.MID_BACKGROUND_PATH
		and scene.mid_background.texture.get_size() == Vector2(scene.art_size)
		and mid_load_status == OK and mid_image.detect_alpha() == Image.ALPHA_BIT,
		"The middle buildings use their own transparent full-width native panorama")
	check(near_load_status == OK and near_image.detect_alpha() == Image.ALPHA_BIT
		and far_load_status == OK and far_image.detect_alpha() == Image.ALPHA_NONE,
		"Near buildings preserve binary cutout edges and the tall far sky remains opaque")
	check(scene.foreground.texture.resource_path == scene.FOREGROUND_PATH
		and scene.foreground.texture.get_size() == Vector2(scene.art_size)
		and foreground_load_status == OK and foreground_image.detect_alpha() == Image.ALPHA_BIT,
		"The playable buildings and cars use a native transparent foreground")
	check(not scene.traversal_colliders.is_empty() and scene.traversal_terrain.get_child_count() == scene.traversal_layout.colliders.size(),
		"Traversal colliders are built once from the delivered layout")
	check(scene.elevator != null, "The delivered dense battlefield includes the giant building's industrial elevator")
	if scene.elevator != null:
		var lift: AnimatableBody2D = scene.elevator
		check(lift.sync_to_physics and lift.process_physics_priority < player.process_physics_priority
			and lift.collision_layer == 1 and lift.collision_mask == 0,
			"The industrial cage uses synchronized moving-body physics before the unchanged hero")
		check(lift.position.y == lift.bottom_y and lift.target_y == lift.bottom_y
			and lift.top_y < lift.bottom_y and lift.speed > 0.0 and not lift.moving,
			"The elevator begins docked at the bottom with distinct ordered landings")
		check(lift.cage.scale == Vector2.ONE and lift.cage.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
			and lift.drawn_rect().position == lift.drawn_rect().position.round(),
			"The moving cage preserves native scale, nearest sampling and integer drawing")
		check(lift.get_child(0) is CollisionShape2D and lift.get_child(0).one_way_collision
			and is_equal_approx(lift.get_child(0).shape.size.x, lift.width),
			"The visible cage deck is backed by a matching one-way moving collision surface")
		key(KEY_E, true)
		await ticks(1)
		key(KEY_E, false)
		check(not lift.moving and lift.hint(player).is_empty(), "The dedicated E input cannot start an elevator outside either landing range")
	check(scene.far_background.z_index < scene.mid_background.z_index and scene.mid_background.z_index < scene.background.z_index
		and scene.background.z_index < scene.foreground.z_index and scene.foreground.z_index < player.z_index
		and scene.far_background.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		and scene.mid_background.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		and scene.foreground.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"Playable foreground renders above the three background layers with nearest filtering")
	check(scene.far_covers_view() and scene.far_background.position == scene.far_background.position.round(),
		"The far skyline covers the initial viewport on whole pixels")
	check(scene.mid_covers_view() and scene.mid_background.position == scene.mid_background.position.round(),
		"The middle panorama covers the initial viewport on whole pixels")
	var ambient: Node = scene.ambient
	check(ambient != null and not ambient.effects.is_empty(), "The standalone battlefield loads a finite ambient pool")
	var kind_counts := {"lights": 0, "steam": 0, "stars": 0, "dust": 0, "vehicle_smoke": 0, "vehicle_fire": 0}
	var layered := true
	var native := true
	var lamp_regions := true
	var before: Array = []
	var steam_roots_fixed := true
	for effect: Dictionary in ambient.effects:
		kind_counts[effect.kind] += 1
		var node: Node2D = effect.node
		native = native and node.scale == Vector2.ONE and node.position == node.position.round()
		if effect.kind != "dust":
			layered = layered and node.get_parent() == ambient._layer(effect.layer) and node.z_index == 0
		if effect.kind == "lights":
			var lamp := node as Sprite2D
			lamp_regions = lamp_regions and lamp.texture == lamp.get_parent().texture and lamp.region_enabled \
				and lamp.region_filter_clip_enabled and lamp.region_rect == effect.rect and not lamp.centered
		if effect.kind == "steam":
			var emitter: Array = ambient.settings.get("steam_anchor", [24, 59])
			steam_roots_fixed = steam_roots_fixed and node.position == (effect.anchor - Vector2(float(emitter[0]), float(emitter[1]))).round()
		if effect.kind == "stars":
			layered = layered and effect.layer == "far" and node.size == Vector2.ONE
		before.append([node.position, node.modulate, (node as Sprite2D).frame if node is Sprite2D else -1])
	check(int(kind_counts.lights) > 0 and int(kind_counts.steam) > 0 and int(kind_counts.stars) > 0 \
		and int(kind_counts.dust) == 16 and int(kind_counts.vehicle_smoke) == 7 and int(kind_counts.vehicle_fire) == 7 and ambient.effects.size() == 64,
		"The ambient pool contains 64 objects including exactly seven paired vehicle smoke/fire emitters")
	check(layered, "Lights and steam inherit their panorama depth; one-pixel stars belong only to the far sky")
	check(native and lamp_regions, "Ambient coordinates stay integer and lamps reuse exact source window regions")
	var chosen_variants: Dictionary = {}
	var chosen_phases: Dictionary = {}
	var chosen_speeds: Dictionary = {}
	for choice: Dictionary in ambient.vehicle_assignments:
		chosen_variants[choice.variant_id] = true
		chosen_phases[choice.smoke_phase] = true
		chosen_speeds[choice.fire_period] = true
	check(ambient.vehicle_seed > 0 and ambient.vehicle_seed <= 4294967295 and ambient.vehicle_assignments.size() == 7 and chosen_variants.size() >= 3 and chosen_phases.size() >= 6 and chosen_speeds.size() >= 6,
		"Seven cars really choose at least three art variants and independently randomized phases and speeds")
	var vehicle_anchor_ok := true
	var vehicle_depth_ok := true
	var vehicle_art_ok := true
	var vehicle_textures := {"vehicle_smoke": {}, "vehicle_fire": {}}
	for effect: Dictionary in ambient.effects:
		if not String(effect.kind).begins_with("vehicle_"):
			continue
		var node := effect.node as Sprite2D
		vehicle_depth_ok = vehicle_depth_ok and node.get_parent() == scene and node.z_index == scene.foreground.z_index \
			and node.get_index() > scene.foreground.get_index() and node.z_index < player.z_index
		var fixture: Dictionary = {}
		for candidate: Dictionary in scene.traversal_layout.fixtures:
			if String(candidate.id) == String(effect.vehicle_id):
				fixture = candidate
		if fixture.is_empty():
			vehicle_anchor_ok = false
		else:
			var raw: Array = fixture.rect
			vehicle_anchor_ok = vehicle_anchor_ok and Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3])).has_point(effect.anchor) \
				and node.position == (effect.anchor - Vector2(effect.atlas.anchor)).round()
		vehicle_textures[effect.kind][node.texture.resource_path] = true
		vehicle_art_ok = vehicle_art_ok and node.texture.get_image().detect_alpha() == Image.ALPHA_BIT and node.hframes * node.vframes >= 6
		for used: Rect2 in effect.atlas.used:
			vehicle_art_ok = vehicle_art_ok and used.has_area()
			if effect.kind == "vehicle_fire":
				vehicle_art_ok = vehicle_art_ok and used.size.y <= 28.0
	check(vehicle_anchor_ok, "Vehicle smoke and fire stay fixed to real car bodies without moving their collision or art")
	check(vehicle_depth_ok, "Vehicle smoke/fire draw above the car source and below the unchanged hero")
	check(vehicle_art_ok and vehicle_textures.vehicle_smoke.size() >= 3 and vehicle_textures.vehicle_fire.size() >= 3,
		"Cars use at least three real transparent six-frame smoke/fire atlases with low native flames")
	var assignment_snapshot := JSON.stringify(ambient.vehicle_assignments)
	var node_count := scene.get_tree().get_node_count()
	ambient.update_at(ambient.elapsed + 0.8)
	var changes := 0
	for index in range(ambient.effects.size()):
		var effect: Dictionary = ambient.effects[index]
		var node: Node2D = effect.node
		if before[index] != [node.position, node.modulate, (node as Sprite2D).frame if node is Sprite2D else -1]:
			changes += 1
		native = native and node.position == node.position.round() and not node is CollisionObject2D
		if effect.kind == "steam":
			steam_roots_fixed = steam_roots_fixed and node.position == before[index][0]
	check(changes > 0 and scene.get_tree().get_node_count() == node_count and native,
		"Ambient time really changes existing pixels without creating nodes, fractional positions or collisions")
	check(JSON.stringify(ambient.vehicle_assignments) == assignment_snapshot, "Vehicle variants, phase offsets and speeds remain fixed while time advances")
	check(steam_roots_fixed, "Steam stays anchored at every real chimney mouth through different animation phases")
	var steam_continuous := true
	for effect: Dictionary in ambient.effects:
		if effect.kind == "steam" and effect.node.visible:
			steam_continuous = steam_continuous and effect.node.modulate.a >= float(effect.data.opacity) * 0.299
	check(steam_continuous, "The stronger steam keeps a visible base instead of disappearing between cycles")
	var steam_image: Image = load(String(ambient.settings.steam_texture)).get_image()
	check(steam_image.get_size() == Vector2i(192, 128) and ambient.steam_frame_size == Vector2i(64, 64) and ambient.steam_grid == Vector2i(3, 2) and steam_image.detect_alpha() == Image.ALPHA_BIT \
		and ambient._steam_used.size() == 6,
		"Larger steam uses six new native 64px frames with binary transparent edges and scale one")
	var timing_saved: float = ambient.elapsed
	var timing_updates: int = ambient.updates
	var timing_fraction: float = ambient._accumulator
	ambient._accumulator = 0.0
	for _frame in range(60):
		ambient._process(1.0 / 60.0)
	check(ambient.updates - timing_updates == 16 and is_equal_approx(ambient.update_hz, 16.0),
		"At 60 rendered frames per second the ambient pool retains its remainder and really updates 16 times")
	ambient._accumulator = timing_fraction
	ambient.update_at(timing_saved)
	var grain_lengths: Dictionary = {}
	var wind: Dictionary = {}
	for effect: Dictionary in ambient.effects:
		if effect.kind == "dust":
			grain_lengths[int(effect.node.size.x)] = true
			wind = effect
	check(grain_lengths.has(1) and grain_lengths.has(2) and grain_lengths.has(3),
		"Stronger wind uses one-, two- and three-pixel marks without scaling art")
	var wind_x: float = wind.node.position.x
	scene.camera.position.x += 13.0
	ambient.update_at(timing_saved)
	var wind_dx: float = wind.node.position.x - wind_x
	check(is_zero_approx(wind_dx) or is_equal_approx(absf(wind_dx), 320.0),
		"Moving the camera leaves world-space sand in place until it wraps at the viewport edge")
	scene.camera.position.x -= 13.0
	ambient.update_at(timing_saved)
	var initial_camera_x: float = scene.camera.position.x
	var initial_far_x: float = scene.far_visible_rect().position.x
	var initial_mid_x: float = scene.mid_visible_rect().position.x
	check(root.content_scale_size == Vector2i(320, 180) and root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER,
		"The original 320x180 integer viewport is preserved")
	check(scene.ground_source == scene.GROUND_PATH, "Collision follows the delivered surface profile")
	check(scene.ground_y_at(40.0) == 224.0 and scene.ground_y_at(400.0) == 168.0
		and scene.camera.limit_top == -256 and scene.camera.limit_bottom == 256,
		"The original ground heights remain while the camera can reveal the upper building canvas")
	var grounded_position: Vector2 = player.position
	player.position.y = -180.0
	scene._follow_player()
	check(scene.camera.position.y == -166.0 and scene.far_covers_view() and scene.mid_covers_view()
		and scene.near_covers_view() and scene.foreground_covers_view(),
		"The camera reaches y=-256 without sampling outside any native art layer")
	player.position = grounded_position
	scene._follow_player()
	check(player.get_node("Sprite").sprite_frames.resource_path == "res://assets/side_view.tres", "The existing side-view animation library is reused")
	check(player.get_node("Sprite").material != null, "The existing hero material is preserved")
	for code in [KEY_F7, KEY_F8]:
		key(code, true)
		await ticks(1)
		key(code, false)
	check(current_scene == scene, "Interior debug routes leave the standalone playground in place")
	key(KEY_D, true)
	key(KEY_SHIFT, true)
	await ticks(7)
	check(not player.is_running and not player.is_dodging, "The existing short Shift hold waits for the run gesture")
	await ticks(20)
	check(player.is_running and player.velocity.x > 125.0, "Holding Shift enters the existing run at its normal speed")
	var airborne := 0
	var max_ground_error := 0.0
	for _index in range(180):
		await ticks(1)
		if not player.is_on_floor():
			airborne += 1
		max_ground_error = maxf(max_ground_error, absf(player.position.y - scene.ground_y_at(player.position.x)))
		if player.position.x >= 370.0:
			break
	check(player.position.x >= 370.0 and airborne <= 3 and max_ground_error <= 6.0, "Original collision and running climb the drawn slope onto the ridge")
	var camera_distance: float = scene.camera.position.x - initial_camera_x
	var far_distance: float = scene.far_visible_rect().position.x - initial_far_x
	var mid_distance: float = scene.mid_visible_rect().position.x - initial_mid_x
	check(camera_distance > 100.0 and absf(far_distance - camera_distance * 0.28) <= 1.0,
		"The far skyline moves at 0.28 of the foreground speed within one native pixel")
	check(absf(mid_distance - camera_distance * 0.58) <= 1.0 and mid_distance > far_distance and mid_distance < camera_distance,
		"Middle buildings move at 0.58, between the distant and foreground speeds")
	check(scene.far_covers_view() and scene.far_background.position == scene.far_background.position.round(),
		"The skyline and sky cover the full camera while climbing the slope")
	check(scene.mid_covers_view() and scene.mid_background.position == scene.mid_background.position.round(),
		"The middle panorama covers the full camera while climbing the slope")
	key(KEY_SHIFT, false)
	key(KEY_D, false)
	await ticks(12)
	check(not player.is_running and not player.is_dodging and absf(player.velocity.x) < 0.1, "Releasing a run stops normally without a dodge")
	key(KEY_A, true)
	key(KEY_SHIFT, true)
	for _index in range(200):
		await ticks(1)
		if player.position.x <= 70.0:
			break
	key(KEY_SHIFT, false)
	key(KEY_A, false)
	await ticks(12)
	check(player.position.x < 80.0 and player.is_on_floor() and absf(player.position.y - scene.ground_y_at(player.position.x)) <= 2.0,
		"Floor snapping lets the unchanged player run back down to the lowland")
	var grounded_y := player.position.y
	key(KEY_SPACE, true)
	await ticks(2)
	key(KEY_SPACE, false)
	await ticks(8)
	check(player.position.y < grounded_y - 12.0 and not player.is_on_floor(), "The original jump works on the continuous terrain")
	var half := Vector2(160, 90)
	check(scene.camera.position.x >= half.x and scene.camera.position.y >= half.y - 256.0
		and scene.camera.position.x <= scene.world_size.x - half.x and scene.camera.position.y <= scene.world_size.y - half.y,
		"The camera stays inside the complete native art bounds during a jump")
	check(scene.far_covers_view() and scene.far_background.position.y == -256.0,
		"The 512px far sky covers the full jump viewport from its negative origin")
	check(scene.mid_covers_view() and scene.mid_background.position.y == -256.0,
		"The middle panorama preserves native vertical alignment during a jump")
	check(scene.near_covers_view() and scene.near_visible_rect().position.y >= 256.0,
		"Near-source sampling remains inside the taller canvas during a jump")
	await ticks(65)
	check(player.is_on_floor() and absf(player.position.y - grounded_y) <= 2.0, "The original jump lands on the same native surface")
	key(KEY_A, true)
	key(KEY_SHIFT, true)
	await ticks(50)
	key(KEY_SHIFT, false)
	key(KEY_A, false)
	await ticks(12)
	check(player.position.x >= scene.EDGE_MARGIN and player.is_on_floor(), "Running into the first edge stays inside the terrain")
	player.position = Vector2(scene.world_size.x - 40.0, scene.ground_y_at(scene.world_size.x - 40.0) - 1.0)
	player.velocity = Vector2.ZERO
	await ticks(6)
	check(absf(scene.camera.position.x - (scene.world_size.x - 160.0)) <= 1.0, "The camera shows the last local 320px portion of the panorama")
	check(scene.far_covers_view() and scene.far_visible_rect().end.x < scene.art_size.x,
		"The full-length far panorama covers the map end without a short repeat")
	check(scene.mid_covers_view() and scene.mid_visible_rect().end.x < scene.art_size.x,
		"The full-length middle panorama covers the map end without a short repeat")
	check(scene.near_covers_view() and scene.near_visible_rect().end.x == scene.art_size.x,
		"The final near viewport reaches the art edge without sampling past its bounds")
	key(KEY_D, true)
	key(KEY_SHIFT, true)
	await ticks(40)
	key(KEY_SHIFT, false)
	key(KEY_D, false)
	await ticks(12)
	check(player.position.x <= scene.world_size.x - scene.EDGE_MARGIN and player.is_on_floor(), "Running into the final edge stays inside the terrain")
	key(KEY_R, true)
	await ticks(1)
	key(KEY_R, false)
	await ticks(6)
	check(absf(player.position.x - scene.START_X) <= 1.0 and player.is_on_floor(), "Reset returns to the lowland without changing scenes")
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	for code in [KEY_A, KEY_D, KEY_SHIFT, KEY_SPACE, KEY_R, KEY_E]:
		key(code, false)
	CONTROLS.release_actions()
	var report := {"suite": "battlefield_run_test", "checks": checks, "failures": failures, "passed": failures.is_empty()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + "test_report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
