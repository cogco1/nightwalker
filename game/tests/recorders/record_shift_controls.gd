extends "res://tests/support/isolated_suite.gd"
const STREET = preload("res://scenes/night_street_proto.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const OUTPUT := "res://evidence/shift_controls_capture"
var street: Node2D
var index := 0
var states: Array = []


func _initialize() -> void:
	call_deferred("run")


func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2(160, 100)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func record(count: int, section: String) -> void:
	for _i in range(count):
		await process_frame
		await RenderingServer.frame_post_draw
		var player: CharacterBody2D = street.player
		root.get_texture().get_image().save_png(OUTPUT + "/%04d.png" % index)
		states.append({"frame": index, "section": section, "animation": player.sprite.animation,
			"pose": player.sprite.frame, "running": player.is_running, "dodging": player.is_dodging,
			"move": player.move_id, "position": [player.position.x, player.position.y],
			"collision_height": player.body_shape.shape.size.y})
		index += 1


func run() -> void:
	CONTROLS.settings_path = "user://shift_capture_bindings.cfg"
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	root.size = Vector2i(320, 180)
	street = STREET.instantiate()
	root.add_child(street)
	current_scene = street
	# Demonstrate inputs on an empty stretch; keep combat AI from replacing the thrust with a perfect counter.
	# This affects only this recorder's scene instance, never the shipped level or target layout.
	for node in street.get_node("World").get_children():
		if node is Node2D and node.has_method("take_damage"):
			node.position.x += 5000.0
			node.process_mode = Node.PROCESS_MODE_DISABLED
	for _i in range(12):
		await physics_frame
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await record(3, "idle")
	key(KEY_D, true)
	await record(20, "walk")
	key(KEY_SHIFT, true)
	await record(40, "hold_shift_run")
	key(KEY_SHIFT, false)
	key(KEY_D, false)
	await record(8, "release_after_run")
	key(KEY_SHIFT, true)
	await record(2, "tap_shift")
	key(KEY_SHIFT, false)
	await record(16, "evade")
	key(KEY_D, true)
	key(KEY_SHIFT, true)
	mouse(true)
	await record(2, "shift_direction_click")
	mouse(false)
	key(KEY_D, false)
	key(KEY_SHIFT, false)
	await record(30, "thrust")
	key(KEY_S, true)
	await record(20, "crouch")
	key(KEY_D, true)
	await record(40, "crouch_walk_right")
	key(KEY_D, false)
	key(KEY_A, true)
	await record(40, "crouch_walk_left")
	key(KEY_A, false)
	await record(8, "crouch_stopped")
	key(KEY_S, false)
	await record(18, "stand_up")
	var file := FileAccess.open(OUTPUT + "/states.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(states, "\t"))
	file.close()
	print("Rendered input sequence: ", index, " frames")
	current_scene = null
	street.queue_free()
	street = null
	for _i in range(6):
		await process_frame
	quit(0)
