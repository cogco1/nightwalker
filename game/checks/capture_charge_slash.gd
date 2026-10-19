extends SceneTree
## Record real charged inputs in the normal whitebox scene; used for the preview, never normal startup.
const SPACE = preload("res://scenes/blank_space.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
var world: Node2D
var output := ""
var frame_index := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			output = argument.trim_prefix("--capture-dir=")
	_run.call_deferred()

func physics_tick(count: int) -> void:
	for _frame in range(count):
		await physics_frame
		await process_frame

func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)

func capture() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output.path_join("%03d.png" % frame_index))
	frame_index += 1

func _run() -> void:
	if output.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	CONTROLS.install(false)
	world = SPACE.instantiate()
	root.add_child(world)
	current_scene = world
	await physics_tick(12)
	for facing in ["right", "left"]:
		world.reset_player(1)
		world.player.position = Vector2(112 if facing == "right" else 208, 156)
		world.player.facing = facing
		world.player.show_idle()
		await physics_tick(12)
		mouse(true)
		for index in range(38):
			await physics_tick(1)
			if index >= 22 and index % 2 == 0:
				await capture()
		mouse(false)
		for index in range(36):
			await physics_tick(1)
			if index < 18 or index % 2 == 0:
				await capture()
	CONTROLS.release_actions()
	print("Captured %s frames" % frame_index)
	quit()
