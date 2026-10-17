extends Node2D
## Top-down door locks and breaker cover; progress persists only this session.

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const GAME_SESSION = preload("res://scripts/core/game_session.gd")
const LEVEL_KIT = preload("res://scripts/levels/level_kit.gd")
const STORY_NODE_NAME := "NightwalkerStoryState"
const DOOR_TEXTURE_PATH := "res://assets/underground_hospital/security/door_closed.png"
const BREAKER_TEXTURE_PATH := "res://assets/underground_hospital/security/breaker_closed.png"
const BREAKER_OPEN_TEXTURE_PATH := "res://assets/underground_hospital/security/breaker_open.png"
const LEGACY_BREAKER_TEXTURE_PATH := "res://assets/underground_hospital/security/breaker_locked.png"
const OPEN_SECONDS := 0.25
const DOOR_RADIUS := 24.0

var story_state: Node
var keypad_active := false
var active_door_id := ""
var _code_edit: LineEdit
var _status: Label

var _host: Node2D
var _settings: Dictionary = {}
var _interactions: Node2D
var _frozen_player: WeakRef
var _session: WeakRef
var _door_bodies: Dictionary = {}
var _door_progress: Dictionary = {}
var _opening: Dictionary = {}
var _door_texture: Texture2D
var _breaker_texture: Texture2D
var _breaker_open_texture: Texture2D
var _panel: Panel
var _title: Label
var _hint: Label
var _confirm: Button
var _cancel: Button
var _filtering := false


func configure(host: Node2D, settings: Dictionary, interactions: Node2D) -> void:
	_host = host
	_settings = settings.duplicate(true)
	_interactions = interactions


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 1
	_ensure_story_state()
	if ResourceLoader.exists(DOOR_TEXTURE_PATH):
		_door_texture = load(DOOR_TEXTURE_PATH) as Texture2D
	if ResourceLoader.exists(BREAKER_TEXTURE_PATH):
		_breaker_texture = load(BREAKER_TEXTURE_PATH) as Texture2D
	elif ResourceLoader.exists(LEGACY_BREAKER_TEXTURE_PATH):
		_breaker_texture = load(LEGACY_BREAKER_TEXTURE_PATH) as Texture2D
	if ResourceLoader.exists(BREAKER_OPEN_TEXTURE_PATH):
		_breaker_open_texture = load(BREAKER_OPEN_TEXTURE_PATH) as Texture2D
	_create_ui()
	refresh_view()


func _exit_tree() -> void:
	_restore_player()


func _ensure_story_state() -> Node:
	if is_instance_valid(story_state):
		return story_state
	if not is_inside_tree():
		return null
	story_state = get_tree().root.get_node_or_null(STORY_NODE_NAME)
	if story_state == null:
		story_state = STORY_STATE.new()
		story_state.name = STORY_NODE_NAME
		get_tree().root.add_child(story_state)
	return story_state


func _player() -> CharacterBody2D:
	if not is_instance_valid(_host):
		return null
	var candidate: Variant = _host.get("player")
	return candidate as CharacterBody2D if is_instance_valid(candidate) else null


func _is_top_down() -> bool:
	return is_instance_valid(_host) and int(_host.get("view_mode")) == 0


func _floor() -> int:
	return int(_host.get("floor_id")) if is_instance_valid(_host) else -1


func _doors() -> Array:
	var doors: Variant = _settings.get("doors", [])
	return doors if doors is Array else []


func _door(id: String) -> Dictionary:
	for item in _doors():
		if item is Dictionary and String(item.get("id", "")) == id:
			return item
	return {}


func _point(values: Variant, fallback := Vector2.ZERO) -> Vector2:
	if values is Array and values.size() == 2:
		return Vector2(float(values[0]), float(values[1]))
	return fallback


func _rectangle(values: Variant) -> Rect2:
	if values is Array and values.size() == 4:
		return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return Rect2()


func refresh_view() -> void:
	if keypad_active:
		close_keypad()
	for body in _door_bodies.values():
		if is_instance_valid(body):
			body.collision_layer = 0
			body.queue_free()
	_door_bodies.clear()
	_door_progress.clear()
	_opening.clear()
	if _is_top_down():
		var world: Node = _host.get("world")
		if is_instance_valid(world):
			for item in _doors():
				if not item is Dictionary or int(item.get("floor_id", -1)) != _floor():
					continue
				var id := String(item.get("id", ""))
				var rectangle := _rectangle(item.get("rect", []))
				if id.is_empty() or not rectangle.has_area():
					continue
				_door_bodies[id] = LEVEL_KIT.add_box(world, rectangle, "SecurityDoor_" + id, 0 if is_door_unlocked(id) else 1)
				_door_progress[id] = 1.0 if is_door_unlocked(id) else 0.0
			_add_breaker_collision(world)
	_refresh_hint()
	queue_redraw()


func _add_breaker_collision(world: Node) -> void:
	var settings: Dictionary = _settings.get("breaker", {})
	if int(settings.get("floor_id", -1)) != _floor():
		return
	var rectangle := _rectangle(settings.get("collision_rect", []))
	if not rectangle.has_area() or world.get_node_or_null("SecurityBreakerCover") != null:
		return
	LEVEL_KIT.add_box(world, rectangle, "SecurityBreakerCover")


func is_position_blocked(point: Vector2, floor: int) -> bool:
	if not _is_top_down():
		return false
	var footprint := Rect2(point - Vector2(6, 8), Vector2(12, 8))
	for item in _doors():
		if not item is Dictionary or int(item.get("floor_id", -1)) != floor:
			continue
		var id := String(item.get("id", ""))
		var still_closed := not is_door_unlocked(id) or _opening.has(id)
		if still_closed and footprint.intersects(_rectangle(item.get("rect", []))):
			return true
	var breaker: Dictionary = _settings.get("breaker", {})
	return int(breaker.get("floor_id", -1)) == floor and footprint.intersects(_rectangle(breaker.get("collision_rect", [])))


func is_door_unlocked(id: String) -> bool:
	var state := _ensure_story_state()
	return state != null and bool(state.call("has_flag", "door:" + id))


func _nearest_locked_door() -> String:
	if not _is_top_down() or keypad_active:
		return ""
	if is_instance_valid(_interactions) and bool(_interactions.get("dialogue_active")):
		return ""
	var player := _player()
	if player == null:
		return ""
	var nearest := ""
	var best := DOOR_RADIUS + 0.001
	for item in _doors():
		if not item is Dictionary or int(item.get("floor_id", -1)) != _floor():
			continue
		var id := String(item.get("id", ""))
		if id.is_empty() or is_door_unlocked(id):
			continue
		var distance := player.global_position.distance_to(_point(item.get("anchor", [])))
		if distance <= DOOR_RADIUS and distance < best:
			best = distance
			nearest = id
	return nearest


func open_keypad(id: String) -> bool:
	if keypad_active or not _is_top_down() or is_door_unlocked(id):
		return false
	if is_instance_valid(_interactions) and bool(_interactions.get("dialogue_active")):
		return false
	var player := _player()
	var item := _door(id)
	if player == null or item.is_empty() or int(item.get("floor_id", -1)) != _floor():
		return false
	if player.global_position.distance_to(_point(item.get("anchor", []))) > DOOR_RADIUS:
		return false
	if _panel == null:
		return false
	keypad_active = true
	active_door_id = id
	player.freeze(self)
	_frozen_player = weakref(player)
	var session := GAME_SESSION.of(self)
	if session != null:
		session.push_modal(self)
		_session = weakref(session)
	_title.text = String(item.get("title", "密码门"))
	_code_edit.text = ""
	_status.text = "请输入四位数字"
	_status.modulate = Color("9ab9c4")
	_panel.show()
	_code_edit.grab_focus()
	_refresh_hint()
	_refresh_host_hint()
	return true


func submit_code(code: String) -> bool:
	if not keypad_active or active_door_id.is_empty() or not _is_top_down():
		return false
	var item := _door(active_door_id)
	if item.is_empty() or int(item.get("floor_id", -1)) != _floor():
		return false
	if code != String(item.get("code", "1010")):
		_status.text = "密码错误，请重试"
		_status.modulate = Color("d18e83")
		return false
	var state := _ensure_story_state()
	if state == null:
		return false
	var id := active_door_id
	state.call("set_flag", "door:" + id, true)
	_door_progress[id] = 0.0
	_opening[id] = 0.0
	close_keypad()
	queue_redraw()
	return true


func close_keypad() -> void:
	keypad_active = false
	active_door_id = ""
	_restore_player()
	if _panel != null:
		_panel.hide()
	if _code_edit != null:
		_code_edit.release_focus()
	_refresh_hint()
	_refresh_host_hint()


func _restore_player() -> void:
	if _session != null:
		var session: Variant = _session.get_ref()
		if is_instance_valid(session):
			session.pop_modal(self)
		_session = null
	if _frozen_player == null:
		return
	var player: Variant = _frozen_player.get_ref()
	if is_instance_valid(player):
		player.unfreeze(self)
	_frozen_player = null


func grant_item(id: String) -> void:
	var state := _ensure_story_state()
	if state != null:
		state.call("grant_item", id)


func has_item(id: String) -> bool:
	var state := _ensure_story_state()
	return state != null and bool(state.call("has_item", id))


func try_unlock_breaker() -> bool:
	if not _is_top_down():
		return false
	if is_breaker_unlocked():
		return true
	var breaker: Dictionary = _settings.get("breaker", {})
	var state := _ensure_story_state()
	# Chapter 1 cuts the lights with this breaker, so the story opens the cabinet without the key.
	var chapter := state != null and bool(state.get("chapter_active"))
	if not chapter and not has_item(String(breaker.get("required_item", "breaker_key"))):
		return false
	if state == null:
		return false
	state.call("set_flag", "breaker_unlocked", true)
	queue_redraw()
	return true


func is_breaker_unlocked() -> bool:
	var state := _ensure_story_state()
	return state != null and bool(state.call("has_flag", "breaker_unlocked"))


func _process(delta: float) -> void:
	var redraw := false
	for id in _opening.keys():
		var elapsed := float(_opening[id]) + delta
		var progress := minf(elapsed / OPEN_SECONDS, 1.0)
		_opening[id] = elapsed
		_door_progress[id] = progress
		if progress >= 1.0:
			var body: Variant = _door_bodies.get(id)
			if is_instance_valid(body):
				body.collision_layer = 0
			_opening.erase(id)
		redraw = true
	_refresh_hint()
	if redraw:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not keypad_active:
		return
	if event is InputEventKey:
		if event.pressed:
			_handle_keypad_key(event)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if keypad_active:
		if event is InputEventKey:
			_input(event)
		else:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if CONTROLS.is_interact(event):
			var nearest := _nearest_locked_door()
			if not nearest.is_empty() and open_keypad(nearest):
				get_viewport().set_input_as_handled()


func _handle_keypad_key(event: InputEventKey) -> void:
	var code := event.keycode if event.keycode != 0 else event.physical_keycode
	if code == KEY_ESCAPE:
		close_keypad()
		return
	if code == KEY_ENTER or code == KEY_KP_ENTER:
		if not event.echo:
			submit_code(_code_edit.text)
		return
	var caret := _code_edit.caret_column
	var text := _code_edit.text
	if code == KEY_BACKSPACE:
		if caret > 0:
			_code_edit.text = text.substr(0, caret - 1) + text.substr(caret)
			_code_edit.caret_column = caret - 1
	elif code == KEY_DELETE:
		_code_edit.text = text.substr(0, caret) + text.substr(caret + 1)
		_code_edit.caret_column = caret
	elif code == KEY_LEFT:
		_code_edit.caret_column = maxi(caret - 1, 0)
	elif code == KEY_RIGHT:
		_code_edit.caret_column = mini(caret + 1, text.length())
	elif code == KEY_HOME:
		_code_edit.caret_column = 0
	elif code == KEY_END:
		_code_edit.caret_column = text.length()
	elif not event.ctrl_pressed and not event.alt_pressed:
		var digit := ""
		if event.unicode >= 48 and event.unicode <= 57:
			digit = String.chr(event.unicode)
		elif code >= KEY_0 and code <= KEY_9:
			digit = String.chr(48 + code - KEY_0)
		if not digit.is_empty() and text.length() < 4:
			_code_edit.text = text.substr(0, caret) + digit + text.substr(caret)
			_code_edit.caret_column = caret + 1


func _filter_digits(text: String) -> void:
	if _filtering:
		return
	var filtered := ""
	for character in text:
		if character >= "0" and character <= "9" and filtered.length() < 4:
			filtered += character
	if text != filtered:
		_filtering = true
		_code_edit.text = filtered
		_code_edit.caret_column = filtered.length()
		_filtering = false


# The hospital's refresh_ui hides its control hint while a dialogue or this keypad is open.
func _refresh_host_hint() -> void:
	if not is_instance_valid(_host):
		return
	if _host.has_method("refresh_ui"):
		_host.refresh_ui()
	if is_instance_valid(_interactions) and keypad_active:
		_interactions.hide_hint()


func _refresh_hint() -> void:
	if _hint == null:
		return
	var id := _nearest_locked_door()
	# Inside the chapter the HUD key cap names the door (hospital_chapter.gd reads nearest_door_title()).
	_hint.visible = not id.is_empty() and not keypad_active and _host.get("chapter") == null
	if _hint.visible:
		_hint.text = CONTROLS.interact_text() + " · " + String(_door(id).get("title", "密码门"))


## The locked door E would open a keypad for, or "".
func nearest_door_title() -> String:
	var id := _nearest_locked_door()
	return "" if id.is_empty() else String(_door(id).get("title", "密码门"))


func _draw() -> void:
	if not _is_top_down():
		return
	for item in _doors():
		if item is Dictionary and int(item.get("floor_id", -1)) == _floor():
			_draw_door(item)
	_draw_breaker()


func _draw_door(item: Dictionary) -> void:
	var id := String(item.get("id", ""))
	var position := _point(item.get("sprite_position", []))
	var progress := float(_door_progress.get(id, 1.0 if is_door_unlocked(id) else 0.0))
	var travel := int(roundf(progress * 16.0))
	if _door_texture != null:
		var remaining := 16 - travel
		if remaining > 0:
			draw_texture_rect_region(_door_texture, Rect2(position, Vector2(remaining, 16)), Rect2(travel, 0, remaining, 16))
			draw_texture_rect_region(_door_texture, Rect2(position + Vector2(16 + travel, 0), Vector2(remaining, 16)), Rect2(16, 0, remaining, 16))
	else:
		var remaining := 16 - travel
		if remaining > 0:
			draw_rect(Rect2(position, Vector2(remaining, 16)), Color("394c59"))
			draw_rect(Rect2(position + Vector2(16 + travel, 0), Vector2(remaining, 16)), Color("465b65"))
			draw_rect(Rect2(position + Vector2(remaining - 1, 2), Vector2(1, 12)), Color("7596a0"))
			draw_rect(Rect2(position + Vector2(16 + travel, 2), Vector2(1, 12)), Color("7596a0"))
	draw_rect(Rect2(position, Vector2(32, 1)), Color("607a84"))
	var light := Color("79c4b3") if is_door_unlocked(id) else Color("b57569")
	draw_rect(Rect2(position + Vector2(29, 2), Vector2(2, 2)), light)


func _draw_breaker() -> void:
	var breaker: Dictionary = _settings.get("breaker", {})
	if int(breaker.get("floor_id", -1)) != _floor():
		return
	var position := _point(breaker.get("sprite_position", []), Vector2(102, 104))
	var texture := _breaker_open_texture if is_breaker_unlocked() and _breaker_open_texture != null else _breaker_texture
	if texture != null:
		draw_texture(texture, position)
	else:
		draw_rect(Rect2(position, Vector2(24, 30)), Color("2a3c48"))
		draw_rect(Rect2(position + Vector2(1, 1), Vector2(22, 28)), Color("40525d"), false, 1.0)
	var lock_position := position + Vector2(17, 18)
	var color := Color("7bc2b1") if is_breaker_unlocked() else Color("c48e74")
	draw_rect(Rect2(lock_position + Vector2(1, -2), Vector2(3, 3)), color, false, 1.0)
	draw_rect(Rect2(lock_position, Vector2(5, 4)), color)
	if is_breaker_unlocked():
		draw_rect(Rect2(lock_position + Vector2(1, -2), Vector2(2, 2)), Color("263a45"))


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HospitalSecurityUI"
	canvas.layer = 31
	add_child(canvas)
	_hint = PIXEL_UI.label(canvas, Vector2(10, 146), Vector2(300, 16))
	_hint.modulate = Color("b4d6df")
	_hint.hide()
	_panel = Panel.new()
	_panel.name = "DoorKeypadPanel"
	_panel.position = Vector2(72, 44)
	_panel.size = Vector2(220, 116)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101923")
	style.border_color = Color("527883")
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(_panel)
	PIXEL_UI.shrink_dialogue(_panel)
	_title = PIXEL_UI.label(_panel, Vector2(8, 5), Vector2(204, 16), "密码门")
	_title.modulate = Color("91c8d4")
	var instructions := PIXEL_UI.label(_panel, Vector2(8, 24), Vector2(204, 16), "Enter确认 · Esc取消")
	instructions.modulate = Color("849da8")
	_code_edit = LineEdit.new()
	_code_edit.name = "CodeEntry"
	_code_edit.position = Vector2(8, 43)
	_code_edit.add_theme_font_override("font", PIXEL_UI.font())
	_code_edit.add_theme_font_size_override("font_size", 12)
	_code_edit.max_length = 4
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.context_menu_enabled = false
	_code_edit.size = Vector2(204, 22)
	_panel.add_child(_code_edit)
	_code_edit.text_changed.connect(_filter_digits)
	_code_edit.text_submitted.connect(func(code: String) -> void: submit_code(code))
	_status = PIXEL_UI.label(_panel, Vector2(8, 66), Vector2(204, 16), "请输入四位数字")
	_confirm = _button(_panel, Vector2(8, 89), "确认")
	_cancel = _button(_panel, Vector2(116, 89), "取消")
	_confirm.pressed.connect(func() -> void: submit_code(_code_edit.text))
	_cancel.pressed.connect(close_keypad)
	_panel.hide()


func _button(parent: Node, position: Vector2, text: String) -> Button:
	var button := Button.new()
	button.position = position
	button.add_theme_font_override("font", PIXEL_UI.font())
	button.add_theme_font_size_override("font_size", 12)
	button.text = text
	button.size = Vector2(96, 20)
	parent.add_child(button)
	return button
