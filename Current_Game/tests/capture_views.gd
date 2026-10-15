extends SceneTree

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")


func _initialize() -> void:
	call_deferred("capture_views")


func capture_views() -> void:
	var arena := MAIN.instantiate()
	root.add_child(arena)
	for mode in range(2):
		arena.build_arena(mode)
		for _index in range(20):
			await physics_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var filename := "res://evidence/top_down.png" if mode == 0 else "res://evidence/side_view.png"
		if image.is_empty() or image.save_png(filename) != OK:
			push_error("Could not capture " + filename)
			quit(1)
			return
	print("PASS: captured both playable views")
	quit(0)
