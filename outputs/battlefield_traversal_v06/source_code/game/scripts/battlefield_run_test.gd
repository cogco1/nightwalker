extends Node2D
## Standalone native-pixel art check. Launch this scene directly; the chapter routes stay unchanged.
## -- --battlefield-smoke walks the real hero across the entire terrain, records evidence, then exits.

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const LEVEL_KIT = preload("res://scripts/levels/level_kit.gd")
const BACKGROUND_PATH := "res://assets/battlefield_layer_01/battlefield_layer_01_native.png"
const FAR_BACKGROUND_PATH := "res://assets/battlefield_far_background/battlefield_far_native.png"
const MID_BACKGROUND_PATH := "res://assets/battlefield_mid_background/battlefield_mid_native.png"
const FOREGROUND_PATH := "res://assets/battlefield_traversal/foreground_native.png"
const TRAVERSAL_LAYOUT_PATH := "res://assets/battlefield_traversal/layout.json"
const FAR_SCROLL_RATIO := 0.28
const MID_SCROLL_RATIO := 0.58
const GROUND_PATH := "res://assets/battlefield_layer_01/ground_profile.json"
const VIEWPORT_SIZE := Vector2i(320, 180)
const WORLD_TERRAIN_SIZE := Vector2i(6144, 256)
const ART_SIZE := Vector2i(6144, 512)
const ART_ORIGIN := Vector2(0, -256)
const ART_RENDER_LAYERS := ["foreground", "near", "mid", "far"]
const OUTPUT := "res://evidence/battlefield_run_test/"
const EDGE_MARGIN := 12.0
const START_X := 40.0

var player: CharacterBody2D
var camera: Camera2D
var background: Sprite2D
var far_background: Sprite2D
var mid_background: Sprite2D
var foreground: Sprite2D
var traversal_terrain: Node2D
var traversal_layout: Dictionary = {}
var traversal_colliders: Dictionary = {}
var route_waypoints: Array[Dictionary] = []
var terrain: StaticBody2D
var ground_points := PackedVector2Array()
var world_size := WORLD_TERRAIN_SIZE
var art_size := Vector2i.ZERO
var ground_source := ""
var ready_for_test := false
var smoke_report: Dictionary = {}
var _smoke := false
var _smoke_layer_totals: Dictionary = {}


func _ready() -> void:
	process_physics_priority = 100
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var window := get_tree().root
	window.content_scale_size = VIEWPORT_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	DisplayServer.window_set_title("夜行者 · 超长战场跑步试玩")
	_smoke = OS.get_cmdline_user_args().has("--battlefield-smoke")
	if _smoke:
		CONTROLS.settings_path = "user://battlefield_smoke_keybindings.cfg"
		CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install()
	if not _build_background() or not _load_ground() or not _build_traversal():
		if _smoke:
			get_tree().quit(2)
		return
	_build_terrain()
	_build_player()
	_build_camera()
	_follow_player()
	ready_for_test = true
	print("战场跑步试玩 | %s/%s 左右移动 | 长按 %s 奔跑 | %s 跳跃 | %s 返回起点 | Esc 退出" % [
		CONTROLS.hint_text("move_left"), CONTROLS.hint_text("move_right"),
		CONTROLS.hint_text("run"), CONTROLS.hint_text("jump"), CONTROLS.hint_text("reset_arena")])
	print("原生像素: 背景 %d×%d / y=-256 / scale 1；地形 %d×%d；主角 scale 1；视口 320×180。" % [art_size.x, art_size.y, world_size.x, world_size.y])
	print("远景: 同宽长图 / scale 1；水平视差 %.2f；天空覆盖完整镜头高度。" % FAR_SCROLL_RATIO)
	print("中景: 同宽透明楼群与工厂 / scale 1；水平视差 %.2f。" % MID_SCROLL_RATIO)
	print("可踩地形: 破车、二楼与楼顶；沿用原跳跃 / 二段跳；镜头可向上跟随至 y=-256。")
	if _smoke:
		_run_smoke.call_deferred()


func _build_background() -> bool:
	var texture := load(BACKGROUND_PATH) as Texture2D
	if texture == null:
		push_error("Battlefield background is missing: " + BACKGROUND_PATH)
		return false
	art_size = Vector2i(texture.get_width(), texture.get_height())
	if art_size != ART_SIZE:
		push_error("Battlefield artwork must be 6144x512; terrain bounds remain 6144x256.")
		return false
	var far_texture := load(FAR_BACKGROUND_PATH) as Texture2D
	if far_texture == null:
		push_error("Battlefield far background is missing: " + FAR_BACKGROUND_PATH)
		return false
	if Vector2i(far_texture.get_width(), far_texture.get_height()) != art_size:
		push_error("Battlefield far background must share the native panorama dimensions.")
		return false
	far_background = Sprite2D.new()
	far_background.name = "BattlefieldFarBackground"
	far_background.texture = far_texture
	far_background.centered = false
	far_background.position = ART_ORIGIN
	far_background.z_index = -20
	far_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(far_background)
	var mid_texture := load(MID_BACKGROUND_PATH) as Texture2D
	if mid_texture == null:
		push_error("Battlefield middle background is missing: " + MID_BACKGROUND_PATH)
		return false
	if Vector2i(mid_texture.get_width(), mid_texture.get_height()) != art_size:
		push_error("Battlefield middle background must share the native panorama dimensions.")
		return false
	mid_background = Sprite2D.new()
	mid_background.name = "BattlefieldMidBackground"
	mid_background.texture = mid_texture
	mid_background.centered = false
	mid_background.position = ART_ORIGIN
	mid_background.z_index = -15
	mid_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(mid_background)
	background = Sprite2D.new()
	background.name = "BattlefieldBackground"
	background.texture = texture
	background.centered = false
	background.position = ART_ORIGIN
	background.z_index = -10
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(background)
	return true


func _build_traversal() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRAVERSAL_LAYOUT_PATH))
	if not parsed is Dictionary or not parsed.get("colliders", null) is Array:
		push_error("Battlefield traversal layout needs a colliders array: " + TRAVERSAL_LAYOUT_PATH)
		return false
	traversal_layout = parsed
	var texture := load(FOREGROUND_PATH) as Texture2D
	if texture == null or Vector2i(texture.get_size()) != art_size:
		push_error("Battlefield traversal foreground must share the 6144x512 native canvas.")
		return false
	foreground = Sprite2D.new()
	foreground.name = "TraversalForeground"
	foreground.texture = texture
	foreground.centered = false
	foreground.position = ART_ORIGIN
	foreground.z_index = 0
	foreground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(foreground)
	traversal_terrain = Node2D.new()
	traversal_terrain.name = "TraversalTerrain"
	add_child(traversal_terrain)
	for item: Variant in traversal_layout.colliders:
		if not item is Dictionary or String(item.get("id", "")).is_empty():
			push_error("Battlefield traversal collider needs an id.")
			return false
		var id := String(item.id)
		if traversal_colliders.has(id) or (not item.has("rect") and not item.has("polygon")):
			push_error("Invalid or duplicate battlefield traversal collider: " + id)
			return false
		var body := LEVEL_KIT.add_layout_collider(traversal_terrain, item)
		body.set_meta("surface_id", id)
		traversal_colliders[id] = body
	var waypoints: Variant = traversal_layout.get("waypoints", [])
	var route: Variant = traversal_layout.get("route", {})
	if waypoints is Array and waypoints.is_empty() and route is Dictionary:
		waypoints = route.get("waypoints", [])
	if not waypoints is Array:
		push_error("Battlefield traversal waypoints must be an array.")
		return false
	for point: Variant in waypoints:
		var surface_id := String(point.get("surface_id", "")) if point is Dictionary else ""
		if not point is Dictionary or not point.get("position", null) is Array or point.position.size() != 2 \
				or (surface_id != "ground" and not traversal_colliders.has(surface_id)):
			push_error("Battlefield traversal waypoint needs a position and an existing surface_id.")
			return false
		route_waypoints.append(point)
	return true


func _load_ground() -> bool:
	var raw_points: Variant
	if FileAccess.file_exists(GROUND_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GROUND_PATH))
		if parsed is Dictionary:
			raw_points = parsed.get("points", parsed.get("ground_points", parsed.get("surface_points", [])))
			if int(parsed.get("width", world_size.x)) != world_size.x or int(parsed.get("height", world_size.y)) != world_size.y:
				push_error("Battlefield ground profile dimensions do not match the unchanged terrain bounds.")
				return false
		else:
			raw_points = parsed
		ground_source = GROUND_PATH
	else:
		raw_points = [[0, 224], [96, 224], [320, 168], [world_size.x, 168]]
		ground_source = "native-layout fallback"
	if not raw_points is Array or raw_points.size() < 2:
		push_error("Battlefield ground profile needs at least two ordered points.")
		return false
	for item: Variant in raw_points:
		var point := Vector2.ZERO
		if item is Array and item.size() == 2:
			point = Vector2(float(item[0]), float(item[1]))
		elif item is Dictionary and item.has("x") and item.has("y"):
			point = Vector2(float(item.x), float(item.y))
		else:
			push_error("Invalid battlefield ground point: " + str(item))
			return false
		if not is_finite(point.x) or not is_finite(point.y) or point.y < 0.0 or point.y > world_size.y:
			push_error("Battlefield ground point is outside the native image.")
			return false
		if not ground_points.is_empty() and point.x <= ground_points[-1].x:
			push_error("Battlefield ground x coordinates must increase strictly.")
			return false
		ground_points.append(point)
	if not is_zero_approx(ground_points[0].x) or not is_equal_approx(ground_points[-1].x, float(world_size.x)):
		push_error("Battlefield ground profile must cover the entire native width.")
		return false
	return true


func _build_terrain() -> void:
	terrain = StaticBody2D.new()
	terrain.name = "ContinuousGround"
	terrain.collision_layer = 1
	terrain.collision_mask = 0
	add_child(terrain)
	# One closed polygon follows every surface point. There are no separate box edges at segment seams.
	var polygon := PackedVector2Array([Vector2(-128, ground_points[0].y)])
	polygon.append_array(ground_points)
	polygon.append(Vector2(world_size.x + 128, ground_points[-1].y))
	polygon.append(Vector2(world_size.x + 128, world_size.y + 96))
	polygon.append(Vector2(-128, world_size.y + 96))
	var collision := CollisionPolygon2D.new()
	collision.name = "Surface"
	collision.polygon = polygon
	terrain.add_child(collision)


func _build_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	player.view_mode = 1
	player.scale = Vector2.ONE
	player.floor_snap_length = 10.0
	player.floor_max_angle = deg_to_rad(65.0)
	player.position = Vector2(START_X, ground_y_at(START_X) - 1.0)
	player.z_index = 1
	add_child(player)


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "BattlefieldCamera"
	camera.zoom = Vector2.ONE
	camera.position_smoothing_enabled = false
	camera.limit_left = 0
	camera.limit_top = int(ART_ORIGIN.y)
	camera.limit_right = world_size.x
	camera.limit_bottom = world_size.y
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)
	camera.make_current()


func ground_y_at(x: float) -> float:
	if ground_points.is_empty():
		return 0.0
	for index in range(ground_points.size() - 1):
		var left := ground_points[index]
		var right := ground_points[index + 1]
		if x <= right.x:
			return lerpf(left.y, right.y, clampf((x - left.x) / (right.x - left.x), 0.0, 1.0))
	return ground_points[-1].y


func _physics_process(_delta: float) -> void:
	if not ready_for_test:
		return
	# Only the two map edges stop movement; all interior traversal uses the surface collider.
	var limited_x := clampf(player.position.x, EDGE_MARGIN, world_size.x - EDGE_MARGIN)
	if not is_equal_approx(limited_x, player.position.x):
		player.position.x = limited_x
		player.velocity.x = 0.0
	_follow_player()


func _follow_player() -> void:
	var half := Vector2(VIEWPORT_SIZE) / 2.0
	var target := player.position + Vector2(48, -64)
	camera.position = Vector2(
		clampf(target.x, half.x, world_size.x - half.x),
		clampf(target.y, ART_ORIGIN.y + half.y, world_size.y - half.y)).round()
	camera.force_update_scroll()
	# One integer translation per layer keeps every pixel native-sized. Both 6144px
	# panoramas cover this map without short repeats or runtime tile loops.
	far_background.position.x = roundf((camera.position.x - half.x) * (1.0 - FAR_SCROLL_RATIO))
	mid_background.position.x = roundf((camera.position.x - half.x) * (1.0 - MID_SCROLL_RATIO))


func far_visible_rect() -> Rect2:
	return Rect2(camera.position - Vector2(VIEWPORT_SIZE) / 2.0 - far_background.position, Vector2(VIEWPORT_SIZE))


func far_covers_view() -> bool:
	return Rect2(Vector2.ZERO, far_background.texture.get_size()).encloses(far_visible_rect())


func mid_visible_rect() -> Rect2:
	return Rect2(camera.position - Vector2(VIEWPORT_SIZE) / 2.0 - mid_background.position, Vector2(VIEWPORT_SIZE))


func mid_covers_view() -> bool:
	return Rect2(Vector2.ZERO, mid_background.texture.get_size()).encloses(mid_visible_rect())


func near_visible_rect() -> Rect2:
	return Rect2(camera.position - Vector2(VIEWPORT_SIZE) / 2.0 - background.position, Vector2(VIEWPORT_SIZE))


func near_covers_view() -> bool:
	return Rect2(Vector2.ZERO, background.texture.get_size()).encloses(near_visible_rect())


func foreground_visible_rect() -> Rect2:
	return Rect2(camera.position - Vector2(VIEWPORT_SIZE) / 2.0 - foreground.position, Vector2(VIEWPORT_SIZE))


func foreground_covers_view() -> bool:
	return Rect2(Vector2.ZERO, foreground.texture.get_size()).encloses(foreground_visible_rect())


func _unhandled_key_input(event: InputEvent) -> void:
	if _smoke or not event.is_pressed() or event.is_echo():
		return
	var key_event := event as InputEventKey
	var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
	if code == KEY_ESCAPE:
		get_tree().quit()
	elif event.is_action_pressed("reset_arena") and ready_for_test:
		player.clear_input_buffer()
		CONTROLS.release_actions()
		player.position = Vector2(START_X, ground_y_at(START_X) - 1.0)
		player.velocity = Vector2.ZERO
		_follow_player()


func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _ticks(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	smoke_report["checks"] += 1
	if not ok:
		smoke_report["failures"].append(label)
		push_error("Battlefield smoke: " + label)


func _pixel_matches(actual: Color, expected: Color, tolerance: float = 1.5 / 255.0) -> bool:
	return absf(actual.r - expected.r) <= tolerance and absf(actual.g - expected.g) <= tolerance \
		and absf(actual.b - expected.b) <= tolerance


func _layer_pixel_evidence(rendered: Image) -> Dictionary:
	# Smoke-only: compare the top exposed source layer with the GPU frame. Mask just
	# the hero's drawn frame and glow, so character pixels cannot count as art errors.
	var images := {"foreground": foreground.texture.get_image(), "near": background.texture.get_image(), "mid": mid_background.texture.get_image(), "far": far_background.texture.get_image()}
	var origins := {"foreground": Vector2i(foreground_visible_rect().position), "near": Vector2i(near_visible_rect().position), "mid": Vector2i(mid_visible_rect().position), "far": Vector2i(far_visible_rect().position)}
	var evidence: Dictionary = {}
	var colors := {"foreground": {}, "near": {}, "mid": {}, "far": {}}
	for layer in ART_RENDER_LAYERS:
		evidence[layer] = {"exposed_samples": 0, "matched_samples": 0, "matched_detail_samples": 0}
	var frame_texture: Texture2D = player.sprite.sprite_frames.get_frame_texture(player.sprite.animation, player.sprite.frame)
	var hero_pixels := Rect2(frame_texture.get_image().get_used_rect())
	var camera_origin := camera.position - Vector2(VIEWPORT_SIZE) / 2.0
	var hero_rect := Rect2(player.sprite.global_position + player.sprite.offset - camera_origin + hero_pixels.position, hero_pixels.size).grow(4.0)
	var excluded := 0
	for y in range(0, VIEWPORT_SIZE.y, 4):
		for x in range(0, VIEWPORT_SIZE.x, 4):
			if hero_rect.has_point(Vector2(x, y)):
				excluded += 1
				continue
			for layer in ART_RENDER_LAYERS:
				var source: Image = images[layer]
				var point: Vector2i = origins[layer] + Vector2i(x, y)
				var expected := source.get_pixelv(point)
				if expected.a <= 0.0:
					continue
				# Binary source alpha is separately checked; never compare through a translucent occluder.
				if expected.a < 0.99:
					break
				evidence[layer]["exposed_samples"] += 1
				if _pixel_matches(rendered.get_pixel(x, y), expected):
					evidence[layer]["matched_samples"] += 1
					colors[layer][expected.to_rgba32()] = true
					var right := source.get_pixel(mini(point.x + 1, source.get_width() - 1), point.y)
					var below := source.get_pixel(point.x, mini(point.y + 1, source.get_height() - 1))
					if (right.a >= 0.99 and not _pixel_matches(right, expected, 6.0 / 255.0)) \
							or (below.a >= 0.99 and not _pixel_matches(below, expected, 6.0 / 255.0)):
						evidence[layer]["matched_detail_samples"] += 1
				break
	for layer in ART_RENDER_LAYERS:
		evidence[layer]["matched_colors"] = colors[layer].size()
	evidence["sample_stride"] = 4
	evidence["hero_excluded_samples"] = excluded
	evidence["hero_exclusion_rect"] = [hero_rect.position.x, hero_rect.position.y, hero_rect.size.x, hero_rect.size.y]
	return evidence


func _capture(label: String) -> void:
	var entry := {"name": label, "player": [player.position.x, player.position.y],
		"ground_y": ground_y_at(player.position.x), "camera": [camera.position.x, camera.position.y],
		"running": bool(player.is_running), "animation": String(player.sprite.animation),
		"foreground_source_rect": [foreground_visible_rect().position.x, foreground_visible_rect().position.y, VIEWPORT_SIZE.x, VIEWPORT_SIZE.y],
		"near_source_rect": [near_visible_rect().position.x, near_visible_rect().position.y, VIEWPORT_SIZE.x, VIEWPORT_SIZE.y],
		"far_position": [far_background.position.x, far_background.position.y],
		"far_source_rect": [far_visible_rect().position.x, far_visible_rect().position.y, VIEWPORT_SIZE.x, VIEWPORT_SIZE.y],
		"mid_position": [mid_background.position.x, mid_background.position.y],
		"mid_source_rect": [mid_visible_rect().position.x, mid_visible_rect().position.y, VIEWPORT_SIZE.x, VIEWPORT_SIZE.y]}
	_check(far_covers_view(), "Far panorama covers the full viewport at " + label)
	_check(far_background.position == far_background.position.round(), "Far panorama stays on whole native pixels at " + label)
	_check(mid_covers_view(), "Middle panorama covers the full viewport at " + label)
	_check(mid_background.position == mid_background.position.round(), "Middle panorama stays on whole native pixels at " + label)
	_check(near_covers_view(), "Near panorama covers the full viewport at " + label)
	_check(foreground_covers_view(), "Traversal foreground covers the full viewport at " + label)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := OUTPUT + label + ".png"
		_check(image != null and image.get_size() == VIEWPORT_SIZE, "Screenshot uses the 320x180 native viewport")
		if image != null:
			var layer_evidence := _layer_pixel_evidence(image)
			entry["layer_render_evidence"] = layer_evidence
			for layer in ART_RENDER_LAYERS:
				var samples: Dictionary = layer_evidence[layer]
				var exposed := int(samples.exposed_samples)
				var matched := int(samples.matched_samples)
				_check(exposed == 0 or float(matched) / exposed >= 0.995,
					"Exposed %s pixels match their native source at %s" % [layer, label])
				_smoke_layer_totals[layer]["exposed_samples"] += exposed
				_smoke_layer_totals[layer]["matched_samples"] += matched
				_smoke_layer_totals[layer]["matched_detail_samples"] += int(samples.matched_detail_samples)
				_smoke_layer_totals[layer]["max_matched_colors"] = maxi(int(_smoke_layer_totals[layer].max_matched_colors), int(samples.matched_colors))
				if exposed > 0:
					_smoke_layer_totals[layer]["visible_checkpoints"] += 1
			_check(image.save_png(path) == OK, "Write screenshot " + label)
			entry["png"] = ProjectSettings.globalize_path(path)
	smoke_report["checkpoints"].append(entry)


func _run_smoke() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	smoke_report = {"checks": 0, "failures": [], "checkpoints": [], "world_size": [world_size.x, world_size.y],
		"art_size": [art_size.x, art_size.y], "art_origin": [ART_ORIGIN.x, ART_ORIGIN.y],
		"ground_source": ground_source, "max_ground_error": 0.0, "airborne_ticks": 0, "running_ticks": 0,
		"far_background": FAR_BACKGROUND_PATH, "far_scroll_ratio": FAR_SCROLL_RATIO,
		"mid_background": MID_BACKGROUND_PATH, "mid_scroll_ratio": MID_SCROLL_RATIO,
		"foreground": FOREGROUND_PATH, "traversal_layout": TRAVERSAL_LAYOUT_PATH,
		"stair_floor_max_degrees": rad_to_deg(player.floor_max_angle),
		"renderer": RenderingServer.get_current_rendering_method(), "headless": DisplayServer.get_name() == "headless"}
	for layer in ART_RENDER_LAYERS:
		_smoke_layer_totals[layer] = {"exposed_samples": 0, "matched_samples": 0, "matched_detail_samples": 0,
			"max_matched_colors": 0, "visible_checkpoints": 0}
	await _ticks(12)
	_check(player.view_mode == 1 and player.is_on_floor(), "Existing side-view hero starts grounded")
	_check(player.scale == Vector2.ONE and foreground.scale == Vector2.ONE and background.scale == Vector2.ONE and far_background.scale == Vector2.ONE
		and mid_background.scale == Vector2.ONE and camera.zoom == Vector2.ONE, "All world art uses native scale 1")
	_check(far_background.z_index < mid_background.z_index and mid_background.z_index < background.z_index
		and background.z_index < foreground.z_index and foreground.z_index < player.z_index,
		"Traversal foreground renders above the three background layers and below the hero")
	_check(get_tree().root.content_scale_size == VIEWPORT_SIZE, "Viewport stays 320x180")
	_check(ground_source == GROUND_PATH, "Terrain comes from the delivered ground profile")
	_check(world_size == WORLD_TERRAIN_SIZE and art_size == ART_SIZE, "Tall artwork preserves the original 6144x256 terrain bounds")
	_check(background.position.y == ART_ORIGIN.y and mid_background.position.y == ART_ORIGIN.y
		and far_background.position.y == ART_ORIGIN.y and foreground.position == ART_ORIGIN,
		"Every native art layer extends upward from y=-256")
	await _capture("00_start")
	var traversal_driver: Variant = load("res://tests/support/battlefield_traversal_driver.gd").new(self)
	var start_x := player.position.x
	var start_camera_x := camera.position.x
	var start_far_x := far_visible_rect().position.x
	var start_mid_x := mid_visible_rect().position.x
	_key(int(CONTROLS.current["move_right"]), true)
	_key(int(CONTROLS.current["run"]), true)
	var targets: Array[Dictionary] = [{"x": 200.0, "name": "01_slope"}, {"x": 400.0, "name": "02_ridge"}]
	for index in range(1, int(ceilf(float(world_size.x) / 768.0))):
		targets.append({"x": float(index * 768 + 160), "name": "%02d_segment_%02d" % [index + 2, index + 1]})
	var target_index := 0
	var stalled_ticks := 0
	var previous_x := player.position.x
	var elapsed_ticks := 0
	var timeout_ticks := int((float(world_size.x) / player.run_speed + 15.0) * 60.0)
	while player.position.x < world_size.x - 32.0 and elapsed_ticks < timeout_ticks:
		# Desktop focus changes may clear synthetic held keys. Reassert the same real key edges;
		# the existing Shift gesture ignores repeated presses while already held.
		_key(int(CONTROLS.current["move_right"]), true)
		_key(int(CONTROLS.current["run"]), true)
		traversal_driver.before_ground_tick()
		await _ticks(1)
		traversal_driver.after_ground_tick()
		elapsed_ticks += 1
		if player.is_running:
			smoke_report["running_ticks"] += 1
		if not player.is_on_floor():
			smoke_report["airborne_ticks"] += 1
		smoke_report["max_ground_error"] = traversal_driver.max_ground_error
		stalled_ticks = stalled_ticks + 1 if player.position.x - previous_x < 0.05 else 0
		previous_x = player.position.x
		if stalled_ticks > 90 or player.position.y > world_size.y + 40:
			smoke_report["stalled_state"] = {"position": [player.position.x, player.position.y],
				"velocity": [player.velocity.x, player.velocity.y], "state": int(player.state),
				"move_right": Input.is_action_pressed("move_right"), "run": Input.is_action_pressed("run"),
				"is_running": bool(player.is_running), "slide_collisions": player.get_slide_collision_count()}
			_check(false, "Traversal remains continuous without falling or an interior wall")
			break
		if target_index < targets.size() and player.position.x >= float(targets[target_index].x):
			await _capture(String(targets[target_index].name))
			target_index += 1
	_key(int(CONTROLS.current["run"]), false)
	_key(int(CONTROLS.current["move_right"]), false)
	await _ticks(20)
	await _capture("99_end")
	_check(player.position.x >= world_size.x - 32.0, "Hero runs from the first lowland to the far end")
	_check(target_index == targets.size(), "Every background segment is reached")
	smoke_report["ground_traversal"] = traversal_driver.finish_ground_run()
	_check(int(smoke_report["running_ticks"]) > 60 and not player.is_running, "Held original run input runs, then releases normally")
	_check(absf(player.velocity.x) < 0.1, "Hero stops normally at the end")
	_check(absf(camera.position.x - (world_size.x - VIEWPORT_SIZE.x / 2.0)) <= 1.0, "Camera follows to the final native viewport")
	_check(player.scale == Vector2.ONE and foreground.scale == Vector2.ONE and background.scale == Vector2.ONE and far_background.scale == Vector2.ONE
		and mid_background.scale == Vector2.ONE and camera.zoom == Vector2.ONE, "Traversal preserves native art scales")
	var camera_distance := camera.position.x - start_camera_x
	var far_distance := far_visible_rect().position.x - start_far_x
	var mid_distance := mid_visible_rect().position.x - start_mid_x
	_check(absf(far_distance - camera_distance * FAR_SCROLL_RATIO) <= 1.0, "Distant skyline scrolls at 0.28 of foreground speed within one native pixel")
	_check(absf(mid_distance - camera_distance * MID_SCROLL_RATIO) <= 1.0, "Middle buildings scroll at 0.58 of foreground speed within one native pixel")
	smoke_report["camera_distance"] = camera_distance
	smoke_report["far_source_distance"] = far_distance
	smoke_report["mid_source_distance"] = mid_distance
	smoke_report["measured_far_scroll_ratio"] = far_distance / camera_distance if camera_distance > 0.0 else 0.0
	smoke_report["measured_mid_scroll_ratio"] = mid_distance / camera_distance if camera_distance > 0.0 else 0.0
	smoke_report["ground_final_player"] = [player.position.x, player.position.y]
	smoke_report["ground_distance"] = player.position.x - start_x
	smoke_report["ground_physics_ticks"] = elapsed_ticks
	smoke_report["course"] = await traversal_driver.run_course()
	if DisplayServer.get_name() != "headless":
		for layer in ART_RENDER_LAYERS:
			var totals: Dictionary = _smoke_layer_totals[layer]
			_check(int(totals.matched_samples) >= 256 and int(totals.matched_detail_samples) >= 64
				and int(totals.max_matched_colors) >= 8,
				"Route visibly renders sufficient varied native details from the " + layer + " layer")
		smoke_report["layer_render_totals"] = _smoke_layer_totals
	smoke_report["distance"] = smoke_report["ground_distance"]
	smoke_report["physics_ticks"] = elapsed_ticks
	smoke_report["final_player"] = [player.position.x, player.position.y]
	smoke_report["final_camera"] = [camera.position.x, camera.position.y]
	smoke_report["passed"] = smoke_report["failures"].is_empty()
	var report_file := FileAccess.open(OUTPUT + "smoke_report.json", FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(smoke_report, "  "))
	print("BATTLEFIELD_SMOKE " + JSON.stringify(smoke_report))
	get_tree().quit(0 if smoke_report["passed"] else 1)
