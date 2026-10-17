extends "res://tests/support/isolated_suite.gd"
## Render the four real SpriteFrames locomotion loops with the shared character shader.
const SIDE = preload("res://assets/side_view.tres")
const MATERIAL = preload("res://assets/fx/character_cyber.tres")
const OUTPUT := "res://evidence/locomotion_blade_capture"
var sprites: Array[AnimatedSprite2D] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 180)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(320, 180)
	background.color = Color("171c28")
	viewport.add_child(background)
	for index in range(4):
		var clip: String = ["walk_right", "walk_left", "run_right", "run_left"][index]
		var position := Vector2(80 + (index % 2) * 160, 70 + floori(float(index) / 2.0) * 85)
		var floor_line := ColorRect.new()
		floor_line.position = Vector2(position.x - 60, position.y)
		floor_line.size = Vector2(120, 1)
		floor_line.color = Color("394156")
		viewport.add_child(floor_line)
		var label := Label.new()
		label.position = position + Vector2(-56, -59)
		label.text = clip
		label.add_theme_font_size_override("font_size", 10)
		viewport.add_child(label)
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = SIDE
		sprite.centered = false
		sprite.offset = Vector2(-56, -84)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.material = MATERIAL.duplicate()
		sprite.position = position
		viewport.add_child(sprite)
		sprite.play(clip)
		sprites.append(sprite)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var states: Array = []
	for index in range(64):
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		picture.save_png(OUTPUT + "/%03d.png" % index)
		var frames: Array = []
		for sprite in sprites:
			frames.append({"animation": sprite.animation, "frame": sprite.frame})
		states.append(frames)
	var file := FileAccess.open(OUTPUT + "/states.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(states, "\t"))
	file.close()
	viewport.queue_free()
	await process_frame
	print("Captured 64 rendered locomotion frames.")
	quit(0)
