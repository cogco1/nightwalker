extends "res://tests/support/isolated_suite.gd"
## Captures the actual rendered hospital and a real F press. No screenshots are composited or art enlarged.

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const HOSPITAL := "res://scenes/underground_hospital.tscn"
const OUT := "res://evidence/coburn/"
const SIZE := Vector2i(1280, 720)

var story: Node
var hospital: Node2D
var shots: Array[Dictionary] = []
var failures: Array[String] = []


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(45.0, true).timeout.connect(func() -> void:
		push_error("Coburn GPU recorder exceeded its deadline")
		quit(2))
	call_deferred("run")


func frames(count := 1) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func place(point: Vector2, facing := "down") -> void:
	hospital.player.position = point
	hospital.player.velocity = Vector2.ZERO
	hospital.player.facing = facing
	hospital.player.show_idle()
	hospital.follow_player()
	await frames(5)


func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var filename := "%02d_%s.png" % [shots.size() + 1, label]
	if image.save_png(OUT + filename) != OK:
		failures.append("Could not write " + filename)
	var target: Node2D = hospital.chapter.target
	var hud: Node = hospital.chapter.chapter_hud
	shots.append({"file": filename, "step": story.step, "view": hospital.view_mode, "floor": hospital.floor_id,
		"player": [hospital.player.position.x, hospital.player.position.y], "busy": hospital.chapter.busy,
		"target_dead": target.dead if is_instance_valid(target) else false, "in_light": hospital.chapter.in_light,
		"prompt_key": hud.key_label.text if hud.prompt.visible else "", "prompt": hud.prompt_label.text if hud.prompt.visible else ""})


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This recorder requires the actual GPU renderer")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.mode = Window.MODE_WINDOWED
	root.size = SIZE
	story = STORY_STATE.ensure(self)
	story.start_chapter()
	var routes: Node = root.get_node("SceneRoutes")
	routes.travel("d1_hospital")
	for _tick in range(120):
		if current_scene != null and current_scene.scene_file_path == HOSPITAL and not routes.switching:
			break
		await frames()
	hospital = current_scene
	await frames(40)
	story.set_flag("door:office_door")
	hospital.floor_id = 2
	hospital.activate_view(0)
	hospital.interactions.power_states["clinical"] = true
	await place(Vector2(540, 127), "up")
	await shot("detailed_doctor_at_his_office_desk")
	hospital.interactions.power_states["clinical"] = false
	await place(Vector2(510, 84), "left")
	await shot("front_approach_needs_the_back")
	await place(Vector2(492, 64))
	await shot("dark_approach_F_execution_prompt")
	key(KEY_E, true)
	await frames(2)
	key(KEY_E, false)
	if hospital.interactions.dialogue_active:
		hospital.interactions.close_dialogue()
	await frames(3)
	if hospital.chapter.target.dead:
		failures.append("E unexpectedly killed the target")
	key(KEY_F, true)
	await frames(1)
	key(KEY_F, false)
	await shot("F_execution_anticipation")
	for _tick in range(30):
		if hospital.chapter.target.dead:
			break
		await frames()
	await shot("F_execution_contact_flash")
	for _tick in range(180):
		if not hospital.chapter.busy:
			break
		await frames()
	await frames(8)
	await shot("coburn_down_with_withdrawal_objective")
	if not hospital.chapter.target.dead or story.step != "d1_target_down" or hospital.player.is_frozen():
		failures.append("The execution did not finish and hand control back")
	hospital.activate_view(1)
	await frames(12)
	key(KEY_F, true)
	await frames(2)
	key(KEY_F, false)
	await shot("side_view_F_has_no_execution")
	if story.step != "d1_target_down":
		failures.append("F in side view changed the story")
	var report := {"renderer": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name(),
		"size": [SIZE.x, SIZE.y], "native_size": [root.content_scale_size.x, root.content_scale_size.y],
		"shots": shots, "failures": failures, "status": "passed" if failures.is_empty() else "failed"}
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
