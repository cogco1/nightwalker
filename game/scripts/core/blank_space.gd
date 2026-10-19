extends Node2D
## Empty space for the retained player. No story, enemies, scenery or old scene routes.

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const SESSION = preload("res://scripts/core/game_session.gd")
const FONT = preload("res://assets/fonts/fusion-pixel-10px-proportional-zh_hans.otf")
const SIDE_VIEW := 1
const FLOOR_Y := 156.0

var player: CharacterBody2D
var session: Node
var view_mode := SIDE_VIEW
var _hint: Label
var _changing := false


func _ready() -> void:
	DisplayServer.window_set_title("夜行者 · 空白工程")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	CONTROLS.install()
	_build_bounds()
	_spawn_player()
	session = SESSION.new()
	session.name = "GameSession"
	add_child(session)
	session.keybindings_closed.connect(func(_saved: bool) -> void: _refresh_hint())
	var ui := CanvasLayer.new()
	ui.name = "Controls"
	add_child(ui)
	_hint = Label.new()
	_hint.position = Vector2(8, 6)
	_hint.add_theme_font_override("font", FONT)
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.add_theme_color_override("font_color", Color("b4c0cc"))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_hint)
	_refresh_hint()


func _build_bounds() -> void:
	var bounds := StaticBody2D.new()
	bounds.name = "Bounds"
	bounds.collision_layer = 1
	bounds.collision_mask = 0
	add_child(bounds)
	for rect in [Rect2(-16, FLOOR_Y, 352, 32), Rect2(-16, -16, 16, 204),
			Rect2(320, -16, 16, 204), Rect2(0, -16, 320, 16)]:
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = rect.get_center()
		bounds.add_child(collision)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	player.view_mode = view_mode
	player.position = Vector2(160, FLOOR_Y if view_mode == SIDE_VIEW else 96)
	add_child(player)


func _unhandled_input(event: InputEvent) -> void:
	if _changing or session.settings_open or session.hit_stop_active or not event is InputEventKey or event.echo:
		return
	if event.is_action_pressed("switch_view"):
		_changing = true
		reset_player.call_deferred(1 - view_mode)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_arena"):
		_changing = true
		reset_player.call_deferred(view_mode)
		get_viewport().set_input_as_handled()


func reset_player(mode: int) -> void:
	CONTROLS.release_actions()
	session.cancel_hit_stop()
	session.end_slowmo()
	if is_instance_valid(player):
		player.free()
	view_mode = mode
	_spawn_player()
	session.bind_player(player)
	_refresh_hint()
	queue_redraw()
	_changing = false


func _refresh_hint() -> void:
	var move := "%s/%s 移动  %s 跳跃" % [CONTROLS.binding_text("move_left"),
		CONTROLS.binding_text("move_right"), CONTROLS.binding_text("jump")] if view_mode == SIDE_VIEW else "%s/%s/%s/%s 移动" % [
		CONTROLS.binding_text("move_up"), CONTROLS.binding_text("move_left"),
		CONTROLS.binding_text("move_down"), CONTROLS.binding_text("move_right")]
	_hint.text = "%s · 空白场景\n%s\n%s 切换视角  %s 复位  Esc 设置" % [
		"侧视" if view_mode == SIDE_VIEW else "俯视", move,
		CONTROLS.binding_text("switch_view"), CONTROLS.binding_text("reset_arena")]


func _draw() -> void:
	if view_mode == SIDE_VIEW:
		draw_rect(Rect2(0, FLOOR_Y, 320, 24), Color("232b34"))
		draw_line(Vector2(0, FLOOR_Y), Vector2(320, FLOOR_Y), Color("526273"), 1.0)
