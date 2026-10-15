extends Node2D

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const PROP_EFFECTS = preload("res://scripts/levels/home_601/home_prop_fx.gd")
const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const GAME_SESSION = preload("res://scripts/core/game_session.gd")
const DIALOGUE_BOX = preload("res://scripts/ui/dialogue_box.gd")
# Safehouse reading pace; the hospital keeps its own 32 / 36.
const PAGE_CHARACTERS := 24
const TYPE_SPEED := 28.0

var layout: Dictionary = {}
var world: Node2D
var player: CharacterBody2D
var prop_effects: Node2D
var dialogue: Panel
var dialogue_active: bool:
	get: return dialogue != null and dialogue.active
var current_interaction := ""
var nearest_interaction := ""
var _hint: Label


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
	player.show_idle()
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
	session.keybindings_closed.connect(func(_saved: bool) -> void: _refresh_nearest())
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
		if CONTROLS.is_interact(event):
			if dialogue_active:
				dialogue.advance()
			else:
				interact_nearest()
			get_viewport().set_input_as_handled()
			return
		if not dialogue_active and event.is_action_pressed("reset_arena"):
			reset_home()
			get_viewport().set_input_as_handled()
	if dialogue_active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dialogue.advance()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not dialogue_active:
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
	if _hint == null:
		return
	var interact := CONTROLS.interact_text()
	if nearest_interaction.is_empty():
		_hint.text = "%s%s%s%s移动  %s交互" % [CONTROLS.hint_text("move_up"), CONTROLS.hint_text("move_left"),
			CONTROLS.hint_text("move_down"), CONTROLS.hint_text("move_right"), interact]
	else:
		_hint.text = interact + " · " + String(_find_item(nearest_interaction)["name"])


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
	prop_effects.call("play_interaction", id)
	# Props low in the room read at the top so the box never covers them.
	dialogue.position.y = 16 if id in ["fridge", "bed", "dumbbells"] else 116
	dialogue.open(item.get("lines", []), String(item["name"]), player, item.get("speakers", []))
	_hint.hide()


func close_dialogue() -> void:
	dialogue.close()
	current_interaction = ""
	_hint.show()
	_refresh_nearest()


func reset_home() -> void:
	if dialogue_active:
		close_dialogue()
	var spawn: Array = layout["spawn"]
	player.position = Vector2(spawn[0], spawn[1])
	player.velocity = Vector2.ZERO
	player.facing = String(layout.get("facing", "up"))
	player.show_idle()


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HomeUI"
	canvas.layer = 20
	add_child(canvas)
	var title := PIXEL_UI.label(canvas, Vector2(6, 3), Vector2(308, 16), "C区 · 601  12:00", PIXEL_UI.FONT_SIZE, true)
	title.modulate = Color("98adb9")
	_hint = PIXEL_UI.label(canvas, Vector2(6, 162), Vector2(308, 16), "", PIXEL_UI.FONT_SIZE, true)
	_hint.modulate = Color("bac9d1")
	dialogue = DIALOGUE_BOX.new()
	dialogue.name = "DialogueBox"
	canvas.add_child(dialogue)
	dialogue.setup(Vector2(18, 116), {"background": Color("101b24"), "border": Color("52717f"),
		"title": Color("82b9ca"), "footer": Color("81949e")}, PAGE_CHARACTERS, TYPE_SPEED)
	dialogue.finished.connect(close_dialogue)
