extends Node

const CONTROLS = preload("res://scripts/controls.gd")

const HOME_PATH := "res://scenes/home_601.tscn"
const MAIN_PATH := "res://scenes/main.tscn"
const HOSPITAL_PATH := "res://scenes/underground_hospital.tscn"
var switching := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	var current := get_tree().current_scene
	if current == null or current.scene_file_path not in [HOME_PATH, HOSPITAL_PATH, MAIN_PATH]:
		return
	var session := current.get_node_or_null("GameSession")
	if session != null and session.settings_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F7 or event.keycode == KEY_F7:
			if CONTROLS.current.values().has(KEY_F7):
				return
			switch_to(HOME_PATH if current != null and current.scene_file_path == HOSPITAL_PATH else HOSPITAL_PATH)
			get_viewport().set_input_as_handled()


func switch_to(target: String) -> void:
	if switching or target not in [HOME_PATH, HOSPITAL_PATH]:
		return
	switching = true
	call_deferred("_commit_scene", target)


func _commit_scene(target: String) -> void:
	var current := get_tree().current_scene
	if is_instance_valid(current):
		var session := current.get_node_or_null("GameSession")
		if session != null:
			session.cancel_hit_stop()
	get_tree().paused = false
	get_viewport().canvas_transform = Transform2D.IDENTITY
	get_tree().root.content_scale_size = Vector2i(320, 180)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var error := get_tree().change_scene_to_file(target)
	if error != OK:
		push_error("Could not change scene: " + error_string(error))
	switching = false
