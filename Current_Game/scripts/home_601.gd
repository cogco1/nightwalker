extends Node2D

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CONTROLS = preload("res://scripts/controls.gd")
const PROP_EFFECTS = preload("res://scripts/home_prop_fx.gd")
const PIXEL_UI = preload("res://scripts/pixel_ui.gd")
const GAME_SESSION = preload("res://scripts/game_session.gd")

var layout: Dictionary = {}
var world: Node2D
var player: CharacterBody2D
var prop_effects: Node2D
var dialogue_active := false
var current_interaction := ""
var nearest_interaction := ""
var _pages: Array[String] = []
var _page_speakers: Array[String] = []
var _page_index := 0
var _typing_clock := 0.0
var _body: Label
var _dialogue_title: Label
var _footer: Label
var _hint: Label
var _dialogue_panel: Panel
var _font: FontFile
var _portrait: TextureRect


func _ready() -> void:
	DisplayServer.window_set_title("夜行者 · 601安全屋 v14")
	get_tree().root.content_scale_size = Vector2i(320, 180)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	CONTROLS.install()
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/home_601/layout.json"))
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	var background := Sprite2D.new()
	background.name = "HomeBackground"
	background.centered = false
	background.texture = load("res://assets/home_601/home_601_native.png")
	background.scale = Vector2.ONE
	background.z_index = -10
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(background)
	for item in layout["colliders"]:
		_add_obstacle(item)
	player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	player.view_mode = 0
	var spawn: Array = layout["spawn"]
	player.position = Vector2(spawn[0], spawn[1])
	player.z_index = 2
	world.add_child(player)
	player.facing = String(layout.get("facing", "up"))
	player.call("_show_idle")
	var camera := Camera2D.new()
	camera.name = "HomeCamera"
	camera.position = Vector2(160, 90)
	camera.zoom = Vector2.ONE
	camera.position_smoothing_enabled = false
	camera.limit_smoothed = false
	add_child(camera)
	camera.make_current()
	prop_effects = PROP_EFFECTS.new()
	prop_effects.name = "PropEffects"
	prop_effects.call("configure", layout)
	add_child(prop_effects)
	_create_ui()
	var session := GAME_SESSION.new()
	session.name = "GameSession"
	add_child(session)
	_refresh_nearest()


func _add_obstacle(item: Dictionary) -> void:
	var values: Array = item["rect"]
	var rectangle := Rect2(values[0], values[1], values[2], values[3])
	var obstacle := StaticBody2D.new()
	obstacle.name = String(item["id"])
	obstacle.collision_layer = 1
	obstacle.collision_mask = 0
	obstacle.position = rectangle.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rectangle.size
	collision.shape = shape
	obstacle.add_child(collision)
	world.add_child(obstacle)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
			if dialogue_active:
				close_dialogue()
				get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_E or event.keycode == KEY_E:
			if dialogue_active:
				_advance_dialogue()
			else:
				interact_nearest()
			get_viewport().set_input_as_handled()
			return
		if not dialogue_active and event.is_action_pressed("reset_arena"):
			reset_home()
			get_viewport().set_input_as_handled()
	if dialogue_active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance_dialogue()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if dialogue_active:
		_typing_clock += delta
		_body.visible_characters = mini(int(_typing_clock * 28.0), _body.text.length())
	else:
		_refresh_nearest()


func _refresh_nearest() -> void:
	nearest_interaction = ""
	var best := INF
	for item in layout.get("interactions", []):
		var coordinates: Array = item["anchor"]
		var distance := player.global_position.distance_to(Vector2(coordinates[0], coordinates[1]))
		if distance <= float(item["radius"]) and distance < best:
			best = distance
			nearest_interaction = String(item["id"])
	if _hint != null:
		_hint.text = "WASD移动  E交互" if nearest_interaction.is_empty() else "E · " + String(_find_item(nearest_interaction)["name"])


func _find_item(id: String) -> Dictionary:
	for item in layout.get("interactions", []):
		if String(item["id"]) == id:
			return item
	return {}


func interact_nearest() -> String:
	if dialogue_active:
		return ""
	_refresh_nearest()
	if nearest_interaction.is_empty():
		return ""
	_open_interaction(nearest_interaction)
	return nearest_interaction


func _open_interaction(id: String) -> void:
	var item := _find_item(id)
	if item.is_empty():
		return
	if id == "door":
		get_tree().root.get_node("SceneRoutes").call("switch_to", "res://scenes/underground_hospital.tscn")
		return
	current_interaction = id
	dialogue_active = true
	player.velocity = Vector2.ZERO
	player.input_suspended = true
	player.clear_input_buffer()
	CONTROLS.release_actions()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	prop_effects.call("play_interaction", id)
	_pages.clear()
	_page_speakers.clear()
	var lines: Array = item.get("lines", [])
	for line_index in range(lines.size()):
		var speaker := _line_speaker(id, line_index)
		var remaining := String(lines[line_index])
		while remaining.length() > 24:
			_pages.append(remaining.substr(0, 24))
			_page_speakers.append(speaker)
			remaining = remaining.substr(24)
		if not remaining.is_empty():
			_pages.append(remaining)
			_page_speakers.append(speaker)
	if _pages.is_empty():
		_pages.append("……")
		_page_speakers.append("protagonist")
	_page_index = 0
	_dialogue_title.text = String(item["name"])
	_dialogue_panel.position.y = 16 if id in ["fridge", "bed", "dumbbells"] else 116
	_dialogue_panel.show()
	_hint.hide()
	_show_page()


func _line_speaker(id: String, line_index: int) -> String:
	if id == "television" and line_index < 2:
		return "television"
	if id == "computer":
		if line_index < 2:
			return "qiaolun"
		if line_index == 3:
			return "terminal"
	return "protagonist"


func _show_page() -> void:
	PIXEL_UI.set_speaker(_portrait, _dialogue_title, _body, _footer,
		_page_speakers[_page_index], String(_find_item(current_interaction)["name"]))
	_body.text = _pages[_page_index]
	_body.visible_characters = 0
	_typing_clock = 0.0
	_footer.text = "E继续  Esc关闭  %d/%d" % [_page_index + 1, _pages.size()]


func _advance_dialogue() -> void:
	if _body.visible_characters >= 0 and _body.visible_characters < _body.text.length():
		_typing_clock = _body.text.length() / 28.0 + 1.0
		_body.visible_characters = -1
		return
	_page_index += 1
	if _page_index >= _pages.size():
		close_dialogue()
	else:
		_show_page()


func close_dialogue() -> void:
	dialogue_active = false
	current_interaction = ""
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.input_suspended = false
	player.clear_input_buffer()
	CONTROLS.release_actions()
	player.velocity = Vector2.ZERO
	_dialogue_panel.hide()
	_hint.show()
	_refresh_nearest()


func reset_home() -> void:
	if dialogue_active:
		close_dialogue()
	var spawn: Array = layout["spawn"]
	player.position = Vector2(spawn[0], spawn[1])
	player.velocity = Vector2.ZERO
	player.facing = String(layout.get("facing", "up"))
	player.call("_show_idle")


func _create_ui() -> void:
	_font = PIXEL_UI.font()
	var canvas := CanvasLayer.new()
	canvas.name = "HomeUI"
	canvas.layer = 20
	add_child(canvas)
	var title := _label(canvas, Vector2(6, 3), Vector2(308, 16), 12)
	title.text = "C区 · 601  12:00"
	title.modulate = Color("98adb9")
	_hint = _label(canvas, Vector2(6, 162), Vector2(308, 16), 12)
	_hint.modulate = Color("bac9d1")
	_dialogue_panel = Panel.new()
	_dialogue_panel.position = Vector2(18, 116)
	_dialogue_panel.size = Vector2(284, 72)
	_dialogue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("101b24")
	panel_style.border_color = Color("52717f")
	panel_style.set_border_width_all(1)
	_dialogue_panel.add_theme_stylebox_override("panel", panel_style)
	canvas.add_child(_dialogue_panel)
	PIXEL_UI.shrink_dialogue(_dialogue_panel)
	_portrait = PIXEL_UI.add_portrait(_dialogue_panel)
	_dialogue_title = _label(_dialogue_panel, Vector2(60, 2), Vector2(218, 16), 12)
	_dialogue_title.modulate = Color("82b9ca")
	_body = _label(_dialogue_panel, Vector2(60, 20), Vector2(218, 32), 12)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.clip_text = true
	_footer = _label(_dialogue_panel, Vector2(60, 54), Vector2(218, 16), 12)
	_footer.modulate = Color("81949e")
	_dialogue_panel.hide()


func _label(parent: Node, location: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	parent.add_child(label)
	label.position = location
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("line_spacing", 0)
	label.size = dimensions
	return label
