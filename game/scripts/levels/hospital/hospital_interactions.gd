extends Node2D

const PAGE_CHARACTERS := 32
const TYPE_SPEED := 36.0
const DEFAULT_RADIUS := 22.0
const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")

var dialogue_active := false
var current_interaction := ""
var nearest_id := ""
var last_interaction := ""
var interaction_counts: Dictionary = {}
var power_states: Dictionary = {}

var _host: Node2D
var _base_layout: Dictionary = {}
var _pages: Array[String] = []
var _page_speakers: Array[String] = []
var _context_title := ""
var _page_index := 0
var _typing_clock := 0.0
var _frozen_player: WeakRef
var _feedback_position := Vector2.ZERO
var _feedback_remaining := 0.0
var _panel: Panel
var _body: Label
var _title: Label
var _footer: Label
var _hint: Label
var _font: FontFile
var _portrait: TextureRect


func configure(host: Node2D, base_layout: Dictionary = {}) -> void:
	_host = host
	_base_layout = base_layout
	if _base_layout.is_empty() and is_instance_valid(_host):
		var candidate: Variant = _host.get("base_layout")
		if candidate is Dictionary:
			_base_layout = candidate
	var sections: Variant = _base_layout.get("power_sections", {})
	var story: Node = _host.get_tree().root.get_node_or_null("NightwalkerStoryState") if is_instance_valid(_host) and _host.is_inside_tree() else null
	if sections is Dictionary:
		for id in sections:
			if not power_states.has(String(id)):
				power_states[String(id)] = bool(story.flags.get("power:" + String(id), true)) if story != null else true
	for item in _base_layout.get("interactions", []):
		if not item is Dictionary or String(item.get("kind", "inspect")) != "toggle_power":
			continue
		var section := String(item.get("power_section", ""))
		if not section.is_empty() and not power_states.has(section):
			power_states[section] = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 1
	_create_ui()
	_refresh_nearest()
	queue_redraw()


func _exit_tree() -> void:
	_restore_player()


func _process(delta: float) -> void:
	if dialogue_active and _body != null:
		_typing_clock += delta
		_body.visible_characters = mini(int(_typing_clock * TYPE_SPEED), _body.text.length())
	else:
		_refresh_nearest()
	if _feedback_remaining > 0.0:
		_feedback_remaining = maxf(0.0, _feedback_remaining - delta)
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
		if dialogue_active:
			close_dialogue()
			get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_E or event.keycode == KEY_E:
		if dialogue_active:
			_advance_dialogue()
		else:
			interact_nearest()
		get_viewport().set_input_as_handled()


func _player() -> CharacterBody2D:
	if not is_instance_valid(_host):
		return null
	var candidate: Variant = _host.get("player")
	return candidate as CharacterBody2D if is_instance_valid(candidate) else null


func _view_key() -> String:
	if not is_instance_valid(_host):
		return "top_down"
	return "top_down" if int(_host.get("view_mode")) == 0 else "side_view"


func _anchor(item: Dictionary) -> Variant:
	var anchors: Variant = item.get("anchors", {})
	if not anchors is Dictionary:
		return null
	var coordinates: Variant = anchors.get(_view_key(), [])
	if not coordinates is Array or coordinates.size() != 2:
		return null
	if not (coordinates[0] is int or coordinates[0] is float):
		return null
	if not (coordinates[1] is int or coordinates[1] is float):
		return null
	var point := Vector2(float(coordinates[0]), float(coordinates[1]))
	return point if point.is_finite() else null


func _refresh_nearest() -> void:
	nearest_id = ""
	var player := _player()
	if player == null:
		_update_hint()
		return
	var room_id := ""
	if _host.has_method("_room_for_position"):
		room_id = String(_host.call("_room_for_position", player.global_position, int(_host.get("view_mode"))))
	var best := INF
	for item in _base_layout.get("interactions", []):
		if not item is Dictionary:
			continue
		if item.has("floor_id") and int(item["floor_id"]) != int(_host.get("floor_id")):
			continue
		var id := String(item.get("id", ""))
		if id.is_empty():
			continue
		var item_room := String(item.get("room_id", ""))
		if String(item.get("kind", "")) != "stairs" and not item_room.is_empty() and not room_id.is_empty() and item_room != room_id:
			continue
		var point: Variant = _anchor(item)
		if not point is Vector2:
			continue
		var radius_value: Variant = item.get("radius", DEFAULT_RADIUS)
		var view_radii: Variant = item.get("radii", {})
		if view_radii is Dictionary:
			radius_value = view_radii.get(_view_key(), radius_value)
		if not (radius_value is int or radius_value is float):
			continue
		var radius := float(radius_value)
		if not is_finite(radius) or radius <= 0.0:
			continue
		var distance := player.global_position.distance_to(point)
		if distance <= radius and distance < best:
			best = distance
			nearest_id = id
	_update_hint()


func _update_hint() -> void:
	if _hint == null:
		return
	_hint.visible = not dialogue_active and not nearest_id.is_empty()
	if _hint.visible:
		var item := _find_interaction(nearest_id)
		_hint.text = "E · " + String(item.get("title", nearest_id))


func _find_interaction(id: String) -> Dictionary:
	for item in _base_layout.get("interactions", []):
		if item is Dictionary and String(item.get("id", "")) == id:
			return item
	return {}


func interact_nearest() -> String:
	if dialogue_active or _player() == null:
		return ""
	if bool(_host.get("stairs_busy")):
		return ""
	_refresh_nearest()
	if nearest_id.is_empty():
		return ""
	var id := nearest_id
	_open_interaction(_find_interaction(id))
	return id


func _open_interaction(item: Dictionary) -> void:
	var player := _player()
	if item.is_empty() or player == null or _panel == null:
		return
	if String(item.get("id", "")) == "exit_panel":
		get_tree().root.get_node("SceneRoutes").call("switch_to", "res://scenes/home_601.tscn")
		return
	current_interaction = String(item["id"])
	last_interaction = current_interaction
	interaction_counts[current_interaction] = int(interaction_counts.get(current_interaction, 0)) + 1
	if String(item.get("kind", "inspect")) == "stairs":
		current_interaction = ""
		_host.call("change_floor", int(item.get("target_floor", 1)))
		return
	dialogue_active = true
	player.velocity = Vector2.ZERO
	if player.has_method("clear_input_buffer"):
		player.set("input_suspended", true)
		player.call("clear_input_buffer")
		CONTROLS.release_actions()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_frozen_player = weakref(player)
	var point: Variant = _anchor(item)
	if point is Vector2:
		_feedback_position = point.round()
		_feedback_remaining = 0.3
	var lines: Array = []
	var raw_lines: Variant = item.get("lines", [])
	if raw_lines is Array:
		lines = raw_lines.duplicate()
	if String(item.get("kind", "inspect")) == "toggle_power":
		var locked := false
		# Only this projection uses the new key lock; generic interactions retain their behavior.
		var required := String(item.get("top_down_required_item", ""))
		if _view_key() == "top_down" and not required.is_empty():
			var security: Variant = _host.get("security")
			locked = not is_instance_valid(security) or not bool(security.call("try_unlock_breaker"))
		if locked:
			lines = ["配电柜锁着。得先找到钥匙。"]
		var section := String(item.get("power_section", ""))
		if not locked and not section.is_empty():
			var powered := not bool(power_states.get(section, true))
			power_states[section] = powered
			var story := get_tree().root.get_node_or_null("NightwalkerStoryState")
			if story != null:
				story.call("set_flag", "power:" + section, powered)
			var state_key := "power_on_lines" if powered else "power_off_lines"
			var state_lines: Variant = item.get(state_key, [])
			if state_lines is Array and not state_lines.is_empty():
				lines = state_lines.duplicate()
			else:
				lines.append("该分区电源已接通。" if powered else "该分区电源已切断。")
	_pages.clear()
	_page_speakers.clear()
	var speaker := String(item.get("speaker", "protagonist"))
	for line in lines:
		var remaining := String(line)
		while remaining.length() > PAGE_CHARACTERS:
			_pages.append(remaining.substr(0, PAGE_CHARACTERS))
			_page_speakers.append(speaker)
			remaining = remaining.substr(PAGE_CHARACTERS)
		if not remaining.is_empty():
			_pages.append(remaining)
			_page_speakers.append(speaker)
	if _pages.is_empty():
		_pages.append("……")
		_page_speakers.append(speaker)
	_page_index = 0
	_context_title = String(item.get("title", current_interaction))
	_panel.show()
	_hint.hide()
	_show_page()
	if is_instance_valid(_host) and _host.has_method("_refresh_ui"):
		_host.call("_refresh_ui")
	queue_redraw()


func _show_page() -> void:
	PIXEL_UI.set_speaker(_portrait, _title, _body, _footer,
		_page_speakers[_page_index], _context_title)
	_body.text = _pages[_page_index]
	_body.visible_characters = 0
	_typing_clock = 0.0
	_footer.text = "E继续  Esc关闭  %d/%d" % [_page_index + 1, _pages.size()]


func _advance_dialogue() -> void:
	if not dialogue_active:
		return
	if _body.visible_characters >= 0 and _body.visible_characters < _body.text.length():
		_typing_clock = _body.text.length() / TYPE_SPEED + 1.0
		_body.visible_characters = -1
		return
	_page_index += 1
	if _page_index >= _pages.size():
		close_dialogue()
	else:
		_show_page()


func _restore_player() -> void:
	if _frozen_player == null:
		return
	var player: Variant = _frozen_player.get_ref()
	if is_instance_valid(player):
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.velocity = Vector2.ZERO
		if player.has_method("clear_input_buffer"):
			player.set("input_suspended", false)
			player.call("clear_input_buffer")
			CONTROLS.release_actions()
	_frozen_player = null


func close_dialogue() -> void:
	dialogue_active = false
	current_interaction = ""
	_restore_player()
	if _panel != null:
		_panel.hide()
	if is_instance_valid(_host) and _host.has_method("_refresh_ui"):
		_host.call("_refresh_ui")
	_refresh_nearest()


func on_view_change() -> void:
	close_dialogue()
	_feedback_remaining = 0.0
	_refresh_nearest()
	queue_redraw()


func _draw() -> void:
	var sections: Variant = _base_layout.get("power_sections", {})
	if sections is Dictionary:
		for section_id in power_states:
			if bool(power_states[section_id]):
				continue
			var section: Variant = sections.get(section_id, {})
			if not section is Dictionary:
				continue
			var view: Variant = section.get(_view_key(), {})
			if not view is Dictionary:
				continue
			if view.has("floor_id") and _view_key() == "top_down" and int(view["floor_id"]) != int(_host.get("floor_id")):
				continue
			_draw_rectangles(view.get("darken_rects", []), Color(0.015, 0.025, 0.045, 0.46))
			_draw_rectangles(view.get("screen_rects", []), Color(0.025, 0.045, 0.065, 0.96))
	if _feedback_remaining <= 0.0:
		return
	var tick := int((0.3 - _feedback_remaining) * 20.0)
	var spread := 2 + tick
	var color := Color("b8e7ed") if tick % 2 == 0 else Color("75baca")
	for offset in [Vector2(-spread, 0), Vector2(spread, -1), Vector2(0, -spread)]:
		draw_rect(Rect2(_feedback_position + offset, Vector2.ONE), color)


func _draw_rectangles(rectangles: Variant, color: Color) -> void:
	if not rectangles is Array:
		return
	for coordinates in rectangles:
		if not coordinates is Array or coordinates.size() != 4:
			continue
		var values_valid := true
		for value in coordinates:
			if not (value is int or value is float):
				values_valid = false
		if not values_valid:
			continue
		var rectangle := Rect2i(int(coordinates[0]), int(coordinates[1]), int(coordinates[2]), int(coordinates[3]))
		if rectangle.has_area():
			draw_rect(Rect2(rectangle), color)


func _create_ui() -> void:
	_font = PIXEL_UI.font()
	var canvas := CanvasLayer.new()
	canvas.name = "HospitalInteractionUI"
	canvas.layer = 30
	add_child(canvas)
	_hint = _label(canvas, Vector2(18, 144), Vector2(284, 16), 12)
	_hint.modulate = Color("b4d6df")
	_hint.hide()
	_panel = Panel.new()
	_panel.name = "InspectionPanel"
	_panel.position = Vector2(18, 118)
	_panel.size = Vector2(284, 72)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101923")
	style.border_color = Color("4e747f")
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(_panel)
	PIXEL_UI.shrink_dialogue(_panel)
	_portrait = PIXEL_UI.add_portrait(_panel)
	_title = _label(_panel, Vector2(60, 2), Vector2(218, 16), 12)
	_title.modulate = Color("8ac7d4")
	_body = _label(_panel, Vector2(60, 20), Vector2(218, 32), 12)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.clip_text = true
	_footer = _label(_panel, Vector2(60, 54), Vector2(218, 16), 12)
	_footer.modulate = Color("809aa7")
	_panel.hide()


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
