extends Node2D

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const INTERACTIONS = preload("res://scripts/levels/hospital/hospital_interactions.gd")
const SECURITY = preload("res://scripts/levels/hospital/hospital_security.gd")
const GAME_SESSION = preload("res://scripts/core/game_session.gd")
const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const LEVEL_KIT = preload("res://scripts/levels/level_kit.gd")
const INTERIOR_LIGHTING = preload("res://scripts/levels/interior_lighting.gd")
const STORY_STATE = preload("res://scripts/core/story_state.gd")
const HOSPITAL_CHAPTER = preload("res://scripts/levels/hospital/hospital_chapter.gd")
const LAYOUT_PATH := "res://assets/underground_hospital/layout.json"
const DEFAULT_BACKGROUND := "res://assets/underground_hospital/hospital_native.png"
const VIEWPORT_SIZE := Vector2i(320, 180)
const DEFAULT_WORLD_SIZE := Vector2i(640, 360)
# Slack around the side-view stair landings (native px). The flight is taken with the feet within 3 px of a
# landing; it counts as entered 2 px above the lower one; a jump leaves it 0.5 px above the upper one; arriving
# allows float error on the landing line.
const STAIR_ENTRY_SLACK := 3.0
const STAIR_ENTERED_RISE := 2.0
const STAIR_JUMP_CLEARANCE := 0.5
const UPPER_ARRIVAL_SLACK := 0.1
const LOWER_ARRIVAL_SLACK := 0.2

var base_layout: Dictionary = {}
var layout: Dictionary = {}
var world: Node2D
var background: Sprite2D
var player: CharacterBody2D
var camera: Camera2D
var interactions: Node2D
var security: Node2D
var lighting: Node2D
## Chapter mode (scripts/levels/hospital/hospital_chapter.gd) when the story runs; null in the sandbox.
var chapter: Node
var world_size := DEFAULT_WORLD_SIZE
var view_mode := 0
var floor_id := 1
var stairs_busy := false
var shared_room_id := ""
var environment_ticks := 0
var _ambient_clock := 0.0
var _saved_positions: Dictionary = {}
var _title: Label
var _hint: Label
var _route_hint: Label
var _using_stairs := false
var _stair_entered := false
# layout.json stairs.side_flight: landing heights, entry and exit x per landing, jump-off span.
var _flight: Dictionary = {}


func _ready() -> void:
	get_tree().root.content_scale_size = VIEWPORT_SIZE
	DisplayServer.window_set_title("夜行者 · 地下医院 v14")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The existing player runs at priority0; follow its completed physics movement.
	process_physics_priority = 100
	CONTROLS.install()
	if FileAccess.file_exists(LAYOUT_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
		if parsed is Dictionary:
			base_layout = parsed
	var dimensions: Array = base_layout.get("native_size", [DEFAULT_WORLD_SIZE.x, DEFAULT_WORLD_SIZE.y])
	world_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	floor_id = int(base_layout.get("initial_floor", 1))
	_flight = base_layout.get("stairs", {}).get("side_flight", {})
	camera = Camera2D.new()
	camera.name = "HospitalCamera"
	camera.zoom = Vector2.ONE
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position_smoothing_enabled = false
	camera.limit_smoothed = false
	add_child(camera)
	camera.make_current()
	lighting = INTERIOR_LIGHTING.new()
	lighting.name = "InteriorLighting"
	add_child(lighting)
	var start := {"view": 0, "room": ""}
	if STORY_STATE.ensure(get_tree()).chapter_active:
		chapter = HOSPITAL_CHAPTER.new(self)
		start = chapter.start_context()
		floor_id = int(start.get("floor", floor_id))
	activate_view(int(start["view"]), String(start["room"]))
	interactions = INTERACTIONS.new()
	interactions.name = "HospitalInteractions"
	interactions.call("configure", self, base_layout)
	add_child(interactions)
	interactions.call("on_view_change")
	security = SECURITY.new()
	security.name = "HospitalSecurity"
	security.call("configure", self, base_layout.get("security", {}), interactions)
	add_child(security)
	lighting.call("set_power_states", interactions.power_states)
	_create_ui()
	var session := GAME_SESSION.new()
	session.name = "GameSession"
	add_child(session)
	session.keybindings_closed.connect(func(_saved: bool) -> void: refresh_ui())
	if chapter != null:
		add_child(chapter)
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if is_instance_valid(player):
		if view_mode == 1:
			_update_stair_access()
		shared_room_id = room_for_position(player.global_position, view_mode)
		if view_mode == 1 and not stairs_busy:
			var detected_floor := int(_room_record(shared_room_id).get("floor_id", floor_id))
			if detected_floor != floor_id:
				floor_id = detected_floor
				refresh_ui()
		follow_player()
		if view_mode == 0:
			queue_redraw()


func _process(delta: float) -> void:
	if is_instance_valid(lighting) and is_instance_valid(interactions):
		lighting.call("set_power_states", interactions.power_states)
	_ambient_clock += delta
	var tick := int(_ambient_clock * 12.0)
	if tick != environment_ticks:
		environment_ticks = tick
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(security) and security.keypad_active:
		get_viewport().set_input_as_handled()
		return
	if stairs_busy:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("switch_view"):
			# Inside the chapter the step fixes the projection; Tab is a developer key (-- --nw-debug).
			if STORY_STATE.ensure(get_tree()).allows_debug_routes():
				switch_view()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("reset_arena"):
			reset_view()
			get_viewport().set_input_as_handled()


func _configuration(mode: int) -> Dictionary:
	var configuration := base_layout.duplicate(true)
	var views: Dictionary = base_layout.get("views", {})
	var key := "top_down" if mode == 0 else "side_view"
	configuration.merge(views.get(key, {}), true)
	if mode == 0:
		var floors: Dictionary = configuration.get("floors", {})
		configuration.merge(floors.get(str(floor_id), {}), true)
	return configuration


## Rebuilds the world for a view (0 top-down, 1 side) with a new player: in room_id at its anchor or the
## position saved when last leaving it, or at forced_position; a blocked spot falls back to start_position().
func activate_view(mode: int, room_id := "", forced_position: Variant = null) -> void:
	if is_instance_valid(security):
		security.call("close_keypad")
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	view_mode = mode
	_using_stairs = false
	_stair_entered = false
	var selected_room := _room_record(room_id)
	if not selected_room.is_empty():
		floor_id = int(selected_room.get("floor_id", floor_id))
	layout = _configuration(mode)
	var dimensions: Array = layout.get("native_size", [640, 360])
	world_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	background = Sprite2D.new()
	background.name = "HospitalBackground"
	background.centered = false
	background.scale = Vector2.ONE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.z_index = -10
	var path := String(layout.get("background", DEFAULT_BACKGROUND))
	if ResourceLoader.exists(path):
		background.texture = load(path) as Texture2D
	else:
		push_error("Hospital background is missing: " + path)
	world.add_child(background)
	for item in layout.get("colliders", []):
		LEVEL_KIT.add_layout_collider(world, item)
	var spawn_position := start_position()
	var record := _room_record(room_id)
	var anchor_key := "top_down_anchor" if mode == 0 else "side_view_anchor"
	if record.has(anchor_key):
		var anchor: Array = record[anchor_key]
		spawn_position = Vector2(anchor[0], anchor[1])
	var cache_key := "%d:%s" % [mode, room_id]
	if _saved_positions.has(cache_key) and position_is_clear(_saved_positions[cache_key], mode):
		spawn_position = _saved_positions[cache_key]
	if forced_position is Vector2:
		spawn_position = forced_position
	if not position_is_clear(spawn_position, mode):
		spawn_position = start_position()
	player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	player.view_mode = mode
	player.position = spawn_position
	player.scale = Vector2.ONE
	if mode == 1:
		player.floor_snap_length = 6.0
		player.floor_max_angle = deg_to_rad(48.0)
	player.z_index = 2
	world.add_child(player)
	var session := get_node_or_null("GameSession")
	if session != null:
		session.bind_player(player)
	shared_room_id = room_for_position(player.global_position, mode)
	if is_instance_valid(interactions):
		interactions.call("on_view_change")
	if is_instance_valid(security):
		security.call("refresh_view")
	lighting.call("refresh_context", world, player, {"profile": "hospital", "layout": layout,
		"base_layout": base_layout, "view_mode": view_mode, "floor_id": floor_id})
	if is_instance_valid(interactions):
		lighting.call("set_power_states", interactions.power_states)
	follow_player()
	if chapter != null:
		chapter.on_view_activated()
	refresh_ui()
	queue_redraw()


func switch_view() -> void:
	if stairs_busy:
		return
	if is_instance_valid(interactions):
		interactions.call("close_dialogue")
	var room_id := room_for_position(player.global_position, view_mode)
	if not _using_stairs and position_is_clear(player.global_position, view_mode):
		_saved_positions["%d:%s" % [view_mode, room_id]] = player.global_position
	activate_view(1 - view_mode, room_id)


func reset_view() -> void:
	if not is_instance_valid(player) or stairs_busy:
		return
	if is_instance_valid(interactions):
		interactions.call("close_dialogue")
	# Inside the chapter R goes back to where this floor was entered (the start point may be in the light).
	player.position = chapter.checkpoint if chapter != null else start_position()
	player.velocity = Vector2.ZERO
	_finish_stairs()
	shared_room_id = room_for_position(player.global_position, view_mode)
	follow_player()


func start_position() -> Vector2:
	var fallback := [110, 300] if view_mode == 0 else [110, 344]
	var values: Array = layout.get("player_start", fallback)
	if view_mode == 1:
		values = layout.get("floor_spawns", {}).get(str(floor_id), values)
	return Vector2(values[0], values[1])


func change_floor(target_floor: int) -> void:
	if stairs_busy or target_floor == floor_id or target_floor not in [1, 2]:
		return
	if is_instance_valid(interactions):
		interactions.call("close_dialogue")
	var stair: Dictionary = base_layout.get("stairs", {})
	if view_mode == 0:
		var position_data: Array = stair.get("top_down_spawns", {}).get(str(target_floor), [])
		if position_data.size() != 2:
			return
		floor_id = target_floor
		var target_room := String(stair.get("room_ids", {}).get(str(target_floor), ""))
		activate_view(0, target_room, Vector2(position_data[0], position_data[1]))
		return
	# E selects the rear stair plane; AD still performs every movement.
	_begin_stairs(target_floor == 1)


func _set_stair_surface(id: String, enabled: bool) -> void:
	var surface := world.get_node_or_null(NodePath(id)) as StaticBody2D
	if surface != null:
		surface.collision_layer = 1 if enabled else 0


func _begin_stairs(descending: bool) -> void:
	if _using_stairs or not player.is_on_floor() or player.is_attacking:
		return
	var point := player.position
	var landing := "upper" if descending else "lower"
	var on_landing := absf(point.y - float(_flight[landing + "_landing_y"])) < STAIR_ENTRY_SLACK
	if not (on_landing and _within(point.x, _flight[landing + "_entry_x"])):
		return
	_using_stairs = true
	_stair_entered = descending
	_set_stair_surface("stair_ramp", true)
	_set_stair_surface("stair_entry", false)
	refresh_ui()


func _finish_stairs() -> void:
	_using_stairs = false
	_stair_entered = false
	_set_stair_surface("stair_entry", true)
	_set_stair_surface("stair_ramp", false)
	refresh_ui()


func _within(value: float, span: Array) -> bool:
	return value >= float(span[0]) and value <= float(span[1])


func _update_stair_access() -> void:
	var point := player.position
	if interactions.dialogue_active:
		return
	if not _using_stairs:
		if Input.is_action_just_pressed("move_up"):
			_begin_stairs(false)
		elif Input.is_action_just_pressed("crouch"):
			_begin_stairs(true)
		return
	var upper := float(_flight["upper_landing_y"])
	var lower := float(_flight["lower_landing_y"])
	if point.y < lower - STAIR_ENTERED_RISE:
		_stair_entered = true
	# Jumping above the upper landing selects that floor before coming down.
	if not player.is_on_floor() and point.y < upper - STAIR_JUMP_CLEARANCE and player.velocity.y < -0.1 and _within(point.x, _flight["jump_off_x"]):
		_finish_stairs()
		return
	if not player.is_on_floor():
		return
	if point.y <= upper + UPPER_ARRIVAL_SLACK and (player.velocity.x < -0.1 or point.x <= float(_flight["upper_exit_x"])):
		_finish_stairs()
	elif point.y >= lower - LOWER_ARRIVAL_SLACK and (_stair_entered or point.x > float(_flight["lower_exit_x"])):
		_finish_stairs()


func follow_player() -> void:
	if camera == null or not is_instance_valid(player):
		return
	LEVEL_KIT.follow(camera, player.global_position, Rect2(Vector2.ZERO, Vector2(world_size)), Vector2(VIEWPORT_SIZE))


## Whether the player's footprint at point stays inside the world and clear of colliders and closed doors.
func position_is_clear(point: Vector2, mode: int) -> bool:
	if mode == 0 and is_instance_valid(security) and security.call("is_position_blocked", point, floor_id):
		return false
	var size := Vector2(12, 8) if mode == 0 else Vector2(12, 26)
	var footprint := Rect2(point - Vector2(size.x * 0.5, size.y), size)
	if not Rect2(Vector2.ZERO, Vector2(world_size)).encloses(footprint):
		return false
	for item in layout.get("colliders", []):
		if mode == 1 and bool(item.get("stair_only", false)):
			continue
		if item.has("polygon"):
			var box := PackedVector2Array([footprint.position, Vector2(footprint.end.x, footprint.position.y), footprint.end, Vector2(footprint.position.x, footprint.end.y)])
			if not Geometry2D.intersect_polygons(box, LEVEL_KIT.points(item["polygon"])).is_empty():
				return false
			continue
		if footprint.intersects(LEVEL_KIT.rect(item["rect"])):
			return false
	return true


func _room_record(id: String) -> Dictionary:
	for room in base_layout.get("rooms", []):
		if String(room["id"]) == id:
			return room
	return {}


## The room containing point in a view, else the room whose anchor is closest.
func room_for_position(point: Vector2, mode: int) -> String:
	var rectangle_key := "top_down_rect" if mode == 0 else "side_view_rect"
	var anchor_key := "top_down_anchor" if mode == 0 else "side_view_anchor"
	var closest := ""
	var best := INF
	for room in base_layout.get("rooms", []):
		if mode == 0 and int(room.get("floor_id", floor_id)) != floor_id:
			continue
		var values: Array = room.get(rectangle_key, [])
		if values.size() == 4 and Rect2(values[0], values[1], values[2], values[3]).has_point(point):
			return String(room["id"])
		var anchor: Array = room.get(anchor_key, [])
		if anchor.size() == 2:
			var distance := point.distance_squared_to(Vector2(anchor[0], anchor[1]))
			if distance < best:
				best = distance
				closest = String(room["id"])
	return closest


func _draw() -> void:
	if view_mode == 0 and is_instance_valid(player):
		# A small shadow anchors the feet to the flat floor on the native grid.
		var feet := player.position.round()
		draw_rect(Rect2(feet + Vector2(-4, 0), Vector2(8, 1)), Color(0.0, 0.01, 0.02, 0.36))
		draw_rect(Rect2(feet + Vector2(-3, 1), Vector2(6, 1)), Color(0.0, 0.01, 0.02, 0.28))
	for item in layout.get("monitors", []):
		var rectangle := _fixture_rect(item)
		if not rectangle.has_area():
			continue
		var color := Color(String(item.get("color", "72b7c3")))
		var scan_y := rectangle.position.y + environment_ticks % rectangle.size.y
		color.a = 0.34
		draw_rect(Rect2(rectangle.position.x, scan_y, rectangle.size.x, 1), color)
		if environment_ticks % 12 < 6:
			color.a = 0.65
			draw_rect(Rect2(rectangle.position.x, rectangle.end.y - 1, 1, 1), color)
	var index := 0
	for item in layout.get("fluorescents", []):
		var rectangle := _fixture_rect(item)
		if rectangle.has_area() and (environment_ticks + index * 7) % 53 in [0, 1, 17]:
			draw_rect(Rect2(rectangle), Color(0.02, 0.04, 0.06, 0.64))
		index += 1


func _fixture_rect(item: Dictionary) -> Rect2i:
	var values: Array = item.get("rect", [0, 0, 0, 0])
	return Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "EnvironmentUI"
	canvas.layer = 20
	add_child(canvas)
	_title = PIXEL_UI.label(canvas, Vector2(5, 3), Vector2(310, 16))
	_title.modulate = Color("9aafb7")
	_route_hint = PIXEL_UI.label(canvas, Vector2(252, 3), Vector2(62, 16), "F8夜街")
	_route_hint.modulate = Color("9aafb7")
	_hint = PIXEL_UI.label(canvas, Vector2(5, 162), Vector2(310, 16))
	_hint.modulate = Color("8da3ad")
	refresh_ui()


## Floor / view title and the control hint, written from the current key bindings.
func refresh_ui() -> void:
	if _title == null:
		return
	if chapter != null:
		# The chapter HUD replaces the sandbox title and control line (hospital_chapter.gd).
		for item: Label in [_title, _route_hint, _hint]:
			item.hide()
		if chapter.is_inside_tree():
			chapter.refresh()
		return
	_route_hint.text = "" if CONTROLS.current.values().has(KEY_F8) else "F8夜街"
	_hint.visible = not ((is_instance_valid(interactions) and interactions.dialogue_active)
		or (is_instance_valid(security) and security.keypad_active))
	_title.text = "地下医院 · %d楼 · %s" % [floor_id, "俯视" if view_mode == 0 else "侧视"]
	var left := CONTROLS.hint_text("move_left")
	var right := CONTROLS.hint_text("move_right")
	var interact := CONTROLS.interact_text()
	var view := CONTROLS.hint_text("switch_view")
	var jump := CONTROLS.hint_text("jump")
	var crouch := CONTROLS.hint_text("crouch")
	if view_mode == 0:
		# F7 only travels home while no action is bound to it (SceneRoutes).
		var home := "" if CONTROLS.current.values().has(KEY_F7) else " F7家中"
		_hint.text = "%s%s%s%s移动 %s交互/楼梯 %s视角 %s跑%s" % [CONTROLS.hint_text("move_up"), left,
			CONTROLS.hint_text("move_down"), right, interact, view, CONTROLS.hint_text("run"), home]
	elif _using_stairs:
		_hint.text = "楼梯：%s上行 %s下行 %s跳 %s蹲 %s视角" % [left, right, jump, crouch, view]
	else:
		_hint.text = "%s%s直走 %s上楼 %s蹲/下楼 %s交互 %s跳 %s视角" % [left, right, CONTROLS.hint_text("move_up"),
			crouch, interact, jump, view]
