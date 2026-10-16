extends Node

const CONTROLS = preload("res://scripts/core/controls.gd")

const HOME_PATH := "res://scenes/home_601.tscn"
const MAIN_PATH := "res://scenes/main.tscn"
const HOSPITAL_PATH := "res://scenes/underground_hospital.tscn"
const STREET_PATH := "res://scenes/night_street_proto.tscn"
const INTERIORS := [HOME_PATH, HOSPITAL_PATH, MAIN_PATH]
var switching := false
var _street_return: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	var current := get_tree().current_scene
	if not event is InputEventKey or not event.pressed or event.echo or not _can_leave(current):
		return
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if CONTROLS.current.values().has(code):
		return
	if code == KEY_F8:
		toggle_street()
	elif code == KEY_F7 and current.scene_file_path in INTERIORS:
		switch_to(HOME_PATH if current.scene_file_path == HOSPITAL_PATH else HOSPITAL_PATH)
	if switching:
		get_viewport().set_input_as_handled()


func _can_leave(current: Node) -> bool:
	if switching or current == null or (current.scene_file_path not in INTERIORS and current.scene_file_path != STREET_PATH):
		return false
	var session := current.get_node_or_null("GameSession")
	if session != null and (session.settings_open or session.has_modal()):
		return false
	if get_tree().paused and (session == null or not session.hit_stop_active):
		return false
	if current.get("stairs_busy") == true or current.get("_using_stairs") == true:
		return false
	var player: Node = current.get("player")
	return is_instance_valid(player) and not player.is_frozen()


## F8 keeps the interior's safe feet position and projection; a directly launched street returns home.
func toggle_street() -> void:
	var current := get_tree().current_scene
	if current != null and current.scene_file_path == STREET_PATH:
		switch_to(String(_street_return.get("path", HOME_PATH)))
	else:
		switch_to(STREET_PATH)


func switch_to(target: String) -> void:
	var current := get_tree().current_scene
	if target not in [HOME_PATH, HOSPITAL_PATH, STREET_PATH] or not _can_leave(current):
		return
	var restore: Dictionary = {}
	if target == STREET_PATH and current.scene_file_path in INTERIORS:
		_street_return = _capture_interior(current)
	elif current.scene_file_path == STREET_PATH and target == _street_return.get("path", ""):
		restore = _street_return.duplicate(true)
	switching = true
	call_deferred("_commit_scene", target, restore)


func _capture_interior(current: Node) -> Dictionary:
	var player: CharacterBody2D = current.get("player")
	var context := {"path": HOME_PATH if current.scene_file_path == MAIN_PATH else current.scene_file_path,
		"position": player.global_position, "facing": player.facing}
	if current.scene_file_path == HOSPITAL_PATH:
		context["floor"] = current.floor_id
		context["view"] = current.view_mode
		context["room"] = current.room_for_position(player.global_position, current.view_mode)
		# A jump is not a landing: return to this floor's existing safe spawn instead of an aerial snapshot.
		if not current.position_is_clear(player.global_position, current.view_mode) or (current.view_mode == 1 and not player.is_on_floor()):
			context["position"] = current.start_position()
	return context


func _commit_scene(target: String, restore: Dictionary) -> void:
	var current := get_tree().current_scene
	if is_instance_valid(current):
		var session := current.get_node_or_null("GameSession")
		if session != null:
			session.cancel_hit_stop()
		var player: Node = current.get("player")
		if is_instance_valid(player):
			player.clear_input_buffer()
	CONTROLS.release_actions()
	get_tree().paused = false
	get_viewport().canvas_transform = Transform2D.IDENTITY
	get_tree().root.content_scale_size = Vector2i(320, 180)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var error := get_tree().change_scene_to_file(target)
	if error != OK:
		push_error("Could not change scene: " + error_string(error))
	else:
		await get_tree().scene_changed
		var arrived := get_tree().current_scene
		if arrived != null and arrived.scene_file_path == target and not restore.is_empty():
			_restore_interior(arrived, restore)
	switching = false


func _restore_interior(current: Node, context: Dictionary) -> void:
	if current.scene_file_path == HOSPITAL_PATH:
		current.floor_id = int(context.get("floor", 1))
		current.activate_view(int(context.get("view", 0)), String(context.get("room", "")), context.get("position"))
	else:
		current.player.position = context["position"]
	var player: CharacterBody2D = current.get("player")
	player.velocity = Vector2.ZERO
	player.facing = String(context.get("facing", player.facing))
	player.clear_input_buffer()
	player.show_idle()
	CONTROLS.release_actions()
