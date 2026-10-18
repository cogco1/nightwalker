extends "res://tests/test_coburn_reward_flow.gd"
## Actual GPU evidence of the paid withdrawal and mainline transition. The doctor-room setup is a fixture;
## F executes, held WASD reaches the exit/home interactions, and E / Enter turn the real menus and readings.

const CONTROLS = preload("res://scripts/core/controls.gd")
const OUT := "res://evidence/coburn_reward/"
const SIZE := Vector2i(1280, 720)
var shots: Array[Dictionary] = []


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(120.0, true).timeout.connect(func() -> void:
		check(false, "the reward GPU recorder completes before its deadline")
		finish())
	call_deferred("run")


func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var filename := "%02d_%s.png" % [shots.size() + 1, label]
	check(image.save_png(OUT + filename) == OK, "the actual framebuffer writes " + filename)
	var scene: Node = current_scene
	var hud: Node = scene.chapter.hud if scene.has_method("_find_item") else scene.chapter.chapter_hud
	shots.append({"file": filename, "scene": scene.scene_file_path, "step": story.step,
		"time": story.clock_text(), "balance": story.balance, "account": hud.balance_label.text,
		"goal": hud.goal_label.text, "player": [player().position.x, player().position.y],
		"view": scene.view_mode if scene.get("view_mode") != null else "top_down",
		"walk_seconds": snappedf(_walk_frames / 60.0, 0.1)})


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("The reward recorder requires the actual GPU renderer")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.mode = Window.MODE_WINDOWED
	root.size = SIZE
	routes = root.get_node("SceneRoutes")
	story = STORY_STATE.ensure(self)
	story.start_chapter()
	routes.travel("d1_hospital")
	if not await arrive(HOSPITAL, "The capture fixture"):
		finish()
		return
	var hospital := current_scene
	story.set_flag("door:office_door")
	hospital.floor_id = 2
	hospital.activate_view(0, "", Vector2(492, 64))
	hospital.interactions.power_states["clinical"] = false
	# The real arrival fade owns input until it ends. Wait for the offered execution rather than pressing F
	# under its modal (GPU rendering can arrive while the headless fixture has already faded).
	var ready := false
	for _tick in range(180):
		var hud: Node = hospital.chapter.chapter_hud
		if hud.prompt.visible and hud.key_label.text == "F" and hud.prompt_label.text.contains("处决"):
			ready = true
			break
		await frames()
	check(ready, "the actual execution prompt is ready after the hospital arrival fade")
	if not ready:
		finish()
		return
	await tap(KEY_F)
	for _tick in range(180):
		if not hospital.chapter.busy:
			break
		await frames()
	check(hospital.chapter.target.dead and story.balance == 0, "the executed doctor is still unpaid inside the hospital")
	await shot("coburn_down_unpaid_until_exit")
	if not await walk_hospital("exit_panel", Vector2(590, 175), 16.0):
		finish()
		return
	await tap(KEY_E)
	if not await arrive(HOME, "The actual captured withdrawal"):
		finish()
		return
	var home := current_scene
	check(story.balance == 50 and home.chapter.hud.balance_change_label.visible, "the actual home arrival displays the 50 yuan payment")
	await shot("home_arrival_account_plus50")
	if not await walk_home("computer"):
		finish()
		return
	await tap(KEY_E)
	await tap(KEY_ENTER)
	await tap(KEY_E)
	check(home.dialogue.active and story.step == "d1_return", "the captured settlement waits for its full reading")
	await shot("computer_settlement_mainline_reading")
	await read_all(home.dialogue)
	check(home.chapter.menu.active and story.step == "d1_resupply", "reading the settlement opens the resupply menu")
	await shot("resupply_prices_and_50_yuan_account")
	await tap(KEY_ENTER)
	check(story.balance == 10 and story.has_item("throwing_spike"), "the captured paid order costs 40")
	await tap(KEY_E)
	await shot("purchase_confirmation_account_10")
	await read_all(home.dialogue)
	if not await walk_home("bed"):
		finish()
		return
	await shot("bed_prompt_and_sleep_objective")
	await tap(KEY_E)
	if not await arrive(HOSPITAL, "The captured 22:00 night"):
		finish()
		return
	var night_overlay: CanvasLayer = current_scene.chapter.overlay
	for _tick in range(180):
		if not night_overlay.busy and night_overlay.shade.color.a <= 0.01:
			break
		await frames()
	check(not night_overlay.busy and night_overlay.shade.color.a <= 0.01, "the actual night arrival fade finishes before the screenshot")
	check(story.step == "d1_night" and current_scene.view_mode == 1 and story.balance == 10,
		"the recorded night uses side view and keeps the remaining account")
	await shot("2200_mainline_side_view_night")
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	hold(0)
	var report := {"suite": "capture_reward_flow", "renderer": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "size": [SIZE.x, SIZE.y],
		"native_size": [root.content_scale_size.x, root.content_scale_size.y], "checks": checks,
		"shots": shots, "failures": failures, "status": "passed" if failures.is_empty() else "failed"}
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
