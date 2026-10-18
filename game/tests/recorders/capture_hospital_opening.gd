extends "res://tests/test_hospital_opening.gd"
## Runs the same live-input checks on the actual GPU and records the native framebuffer.

const OUT := "res://evidence/hospital_opening/"
var shots: Array[Dictionary] = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	super()


func observe(label: String) -> void:
	var at_home: bool = current_scene.scene_file_path == HOME
	var box: Panel = current_scene.dialogue if at_home else hospital.interactions.dialogue
	if label.begins_with("floor_two"):
		for _tick in range(600):
			if not hospital.chapter.chapter_hud.toast_panel.visible:
				break
			await frames()
	if box.active:
		for _tick in range(120):
			if box.body.visible_characters < 0 or box.body.visible_characters >= box.body.text.length():
				break
			await frames()
	await RenderingServer.frame_post_draw
	var filename := "%02d_%s.png" % [shots.size() + 1, label]
	var image := root.get_texture().get_image()
	check(image.save_png(OUT + filename) == OK, "the GPU framebuffer saves " + filename)
	shots.append({"file": filename, "scene": current_scene.scene_file_path, "step": story.step,
		"floor": 0 if at_home else hospital.floor_id,
		"player": [player().position.x, player().position.y], "patrol_count": 0 if at_home else hospital.lighting.patrols.size(),
		"dialogue": box.body.text if box.active else ""})


func finish() -> void:
	if _finished:
		return
	var report := {"suite": "capture_hospital_opening", "checks": checks, "failures": failures,
		"status": "passed" if failures.is_empty() else "failed", "shots": shots,
		"renderer": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name(),
		"native_size": [root.content_scale_size.x, root.content_scale_size.y], "window_size": [root.size.x, root.size.y]}
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	super()
