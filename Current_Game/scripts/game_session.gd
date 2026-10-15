extends Node
## Shared settings and impact pause for the two environment scenes.

const CONTROLS = preload("res://scripts/controls.gd")
const MENU = preload("res://scripts/keybindings_menu.gd")

signal stop_clock_step
var settings_open := false
var keybindings_menu: CanvasLayer
var hit_stop_active := false
var completed_stop_frames: Array[int] = []
var _player: CharacterBody2D
var _host: Node
var _overlay: TextureRect
var _overlay_layer: CanvasLayer
var _saved_pause := false
var _menu_saved_pause := false
var _saved_canvas := Transform2D.IDENTITY
var _layer_offsets: Dictionary = {}
var _elapsed := 0.0
var _token := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_host = get_parent()
	keybindings_menu = MENU.new()
	keybindings_menu.name = "KeybindingsMenu"
	add_child(keybindings_menu)
	keybindings_menu.closed.connect(_close_keybindings)
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 100
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay_layer)
	_overlay = TextureRect.new()
	_overlay.size = Vector2(320, 180)
	_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.hide()
	_overlay_layer.add_child(_overlay)
	bind_player(_host.get("player"))


func bind_player(player: CharacterBody2D) -> void:
	_player = player
	if not is_instance_valid(_player):
		return
	if not _player.normal_contact_stop.is_connected(_on_normal_contact):
		_player.normal_contact_stop.connect(_on_normal_contact)
	if not _player.critical_hit.is_connected(_on_critical_hit):
		_player.critical_hit.connect(_on_critical_hit)


func _process(delta: float) -> void:
	if hit_stop_active:
		_elapsed += delta
		stop_clock_step.emit()


func _story_modal() -> bool:
	if _host.has_method("close_dialogue") and bool(_host.get("dialogue_active")):
		return true
	var interactions := _host.get_node_or_null("HospitalInteractions")
	var security := _host.get_node_or_null("HospitalSecurity")
	return (interactions != null and bool(interactions.get("dialogue_active"))) or (security != null and bool(security.get("keypad_active")))


func _input(event: InputEvent) -> void:
	if settings_open:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode in [KEY_F1, KEY_ESCAPE] or event.physical_keycode in [KEY_F1, KEY_ESCAPE]):
		if not _story_modal():
			open_keybindings()
			get_viewport().set_input_as_handled()
		return
	if hit_stop_active and is_instance_valid(_player):
		_player.call("_input", event)


func open_keybindings() -> void:
	if settings_open or _story_modal() or not is_instance_valid(_player):
		return
	cancel_hit_stop()
	_menu_saved_pause = get_tree().paused
	settings_open = true
	_player.input_suspended = true
	_player.clear_input_buffer()
	CONTROLS.release_actions()
	get_tree().paused = true
	keybindings_menu.open()


func _close_keybindings(_saved: bool) -> void:
	CONTROLS.release_actions()
	if is_instance_valid(_player):
		_player.clear_input_buffer()
		_player.input_suspended = false
	settings_open = false
	get_tree().paused = _menu_saved_pause
	if _host.has_method("_refresh_ui"):
		_host.call("_refresh_ui")


func _on_normal_contact(direction: Vector2) -> void:
	if not hit_stop_active:
		_run_hit_stop(direction, 4)


func _on_critical_hit(_target: Node, _damage: int, direction: Vector2) -> void:
	if not hit_stop_active:
		_run_hit_stop(direction, 6)


func _display_frame() -> void:
	if DisplayServer.get_name() == "headless":
		await stop_clock_step
	else:
		await RenderingServer.frame_post_draw


func _run_hit_stop(direction: Vector2, requested: int) -> void:
	_token += 1
	var token := _token
	hit_stop_active = true
	_elapsed = 0.0
	_saved_pause = get_tree().paused
	_saved_canvas = get_viewport().canvas_transform
	var shake := Vector2(signf(direction.x), 0) if direction.x != 0 else Vector2(0, signf(direction.y))
	var shifted := _saved_canvas
	shifted.origin += shake
	get_viewport().canvas_transform = shifted
	_layer_offsets.clear()
	for layer in _host.find_children("*", "CanvasLayer", true, false):
		if layer != _overlay_layer:
			_layer_offsets[layer] = layer.offset
			layer.offset += shake
	get_tree().paused = true
	await _display_frame()
	if token != _token:
		return
	var frames := 1
	if DisplayServer.get_name() != "headless":
		var snapshot := get_viewport().get_texture().get_image()
		if snapshot != null and not snapshot.is_empty():
			_overlay.texture = ImageTexture.create_from_image(snapshot)
			_overlay.show()
	# Retain the source game's frame and time guarantees on every refresh rate.
	while frames < requested or _elapsed + 0.000001 < requested / 60.0:
		await _display_frame()
		if token != _token:
			return
		frames += 1
	completed_stop_frames.append(frames)
	_finish_hit_stop()


func _finish_hit_stop() -> void:
	_overlay.hide()
	get_viewport().canvas_transform = _saved_canvas
	for layer in _layer_offsets:
		if is_instance_valid(layer):
			layer.offset = _layer_offsets[layer]
	_layer_offsets.clear()
	get_tree().paused = _saved_pause
	hit_stop_active = false


func cancel_hit_stop() -> void:
	_token += 1
	if hit_stop_active:
		_finish_hit_stop()


func _exit_tree() -> void:
	cancel_hit_stop()
	if settings_open:
		_close_keybindings(false)
