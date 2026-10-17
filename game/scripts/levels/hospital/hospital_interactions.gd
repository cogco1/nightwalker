extends Node2D

# Hospital reading pace; the safehouse keeps its own 24 / 28.
const PAGE_CHARACTERS := 32
const TYPE_SPEED := 36.0
const DEFAULT_RADIUS := 22.0
const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const DIALOGUE_BOX = preload("res://scripts/ui/dialogue_box.gd")

var dialogue: Panel
var dialogue_active: bool:
	get: return dialogue != null and dialogue.active
var current_interaction := ""
var nearest_id := ""
var last_interaction := ""
var interaction_counts: Dictionary = {}
var power_states: Dictionary = {}

var _host: Node2D
var _base_layout: Dictionary = {}
var _feedback_position := Vector2.ZERO
var _feedback_remaining := 0.0
var _hint: Label


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


func _process(delta: float) -> void:
	if not dialogue_active:
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
	elif CONTROLS.is_interact(event):
		if dialogue_active:
			dialogue.advance()
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
	if _host.has_method("room_for_position"):
		room_id = String(_host.room_for_position(player.global_position, int(_host.get("view_mode"))))
	var best := INF
	for item in _all_interactions():
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
	# Inside the chapter the HUD key cap shows it instead (hospital_chapter.gd).
	_hint.visible = not dialogue_active and not nearest_id.is_empty() and _host.get("chapter") == null
	if _hint.visible:
		var item := _find_interaction(nearest_id)
		_hint.text = CONTROLS.interact_text() + " · " + String(item.get("title", nearest_id))


## The door keypad hides this hint while it is open.
func hide_hint() -> void:
	if _hint != null:
		_hint.hide()


func _find_interaction(id: String) -> Dictionary:
	for item in _all_interactions():
		if item is Dictionary and String(item.get("id", "")) == id:
			return item
	return {}


## Layout interactions plus the chapter's story targets (Coburn) while the story runs.
func _all_interactions() -> Array:
	var items: Array = _base_layout.get("interactions", [])
	var chapter: Variant = _host.get("chapter") if is_instance_valid(_host) else null
	return items + chapter.story_targets() if chapter != null else items


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
	if item.is_empty() or player == null or dialogue == null:
		return
	var chapter: Variant = _host.get("chapter")
	var story_lines: Array = []
	if String(item.get("id", "")) == "exit_panel":
		if chapter == null:
			get_tree().root.get_node("SceneRoutes").call("switch_to", "res://scenes/home_601.tscn")
			return
		story_lines = chapter.exit_requested()
		if story_lines.is_empty():
			return
	elif String(item.get("kind", "")) == "story":
		story_lines = chapter.story_interact(String(item["id"]))
		if story_lines.is_empty():
			return
	current_interaction = String(item["id"])
	last_interaction = current_interaction
	interaction_counts[current_interaction] = int(interaction_counts.get(current_interaction, 0)) + 1
	if String(item.get("kind", "inspect")) == "stairs":
		current_interaction = ""
		_host.call("change_floor", int(item.get("target_floor", 1)))
		return
	var point: Variant = _anchor(item)
	if point is Vector2:
		_feedback_position = point.round()
		_feedback_remaining = 0.3
	var lines: Array = story_lines.duplicate()
	var raw_lines: Variant = item.get("lines", [])
	if chapter != null and chapter.line_override(current_interaction) is Array:
		raw_lines = chapter.line_override(current_interaction)
	if raw_lines is Array and lines.is_empty():
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
	dialogue.open(lines, String(item.get("title", current_interaction)), player, item.get("speakers", []),
		String(item.get("speaker", "protagonist")))
	_hint.hide()
	_refresh_host_ui()
	queue_redraw()


func close_dialogue() -> void:
	current_interaction = ""
	if dialogue != null:
		dialogue.close()
	_refresh_host_ui()
	_refresh_nearest()


func _refresh_host_ui() -> void:
	if is_instance_valid(_host) and _host.has_method("refresh_ui"):
		_host.refresh_ui()


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
	var canvas := CanvasLayer.new()
	canvas.name = "HospitalInteractionUI"
	canvas.layer = 30
	add_child(canvas)
	_hint = PIXEL_UI.label(canvas, Vector2(18, 144), Vector2(284, 16), "", PIXEL_UI.FONT_SIZE, true)
	_hint.modulate = Color("b4d6df")
	_hint.hide()
	dialogue = DIALOGUE_BOX.new()
	dialogue.name = "InspectionPanel"
	canvas.add_child(dialogue)
	dialogue.setup(Vector2(18, 118), {"background": Color("101923"), "border": Color("4e747f"),
		"title": Color("8ac7d4"), "footer": Color("809aa7")}, PAGE_CHARACTERS, TYPE_SPEED)
	dialogue.finished.connect(close_dialogue)
