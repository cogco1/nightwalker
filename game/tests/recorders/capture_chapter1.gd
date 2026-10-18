extends "res://tests/support/isolated_suite.gd"
## Real GPU captures of chapter 1 milestone 1 for review: title card, opening subtitles, the dark-web terminal
## and its bold line, the hospital's dark arrival, the hero in lamp light with the scan readout, the lock,
## the floor-2 corridor before and after the breaker, Coburn from behind and after the kill, the shop, the
## 22:00 rampage, the night hospital, the held-breath lines and the second morning. Writes evidence/chapter1/.

const CONTROLS = preload("res://scripts/core/controls.gd")
const STORY_STATE = preload("res://scripts/core/story_state.gd")
const OUT := "res://evidence/chapter1/"
const SIZE := Vector2i(1280, 720)
var story: Node
var routes: Node
var shots: Array[Dictionary] = []


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(150.0).timeout.connect(func() -> void:
		push_error("Chapter 1 recorder exceeded its deadline")
		quit(2)
	)
	call_deferred("run")


func frames(count := 4) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func seconds(value: float) -> void:
	await frames(int(value * 60.0))


func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func shot(label: String) -> void:
	if root.mode != Window.MODE_WINDOWED or root.size != SIZE:
		root.mode = Window.MODE_WINDOWED
		root.size = SIZE
		await frames(2)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var filename := "%02d_%s.png" % [shots.size() + 1, label]
	image.save_png(OUT + filename)
	var hero: Variant = current_scene.get("player") if current_scene != null else null
	shots.append({"file": filename, "scene": current_scene.scene_file_path if current_scene != null else "",
		"step": story.step, "clock": story.clock_text(),
		"hero": [hero.position.x, hero.position.y] if hero != null else []})


func arrive(path: String) -> void:
	for _index in range(600):
		if current_scene != null and current_scene.scene_file_path == path and not routes.switching:
			break
		await frames(1)
	await frames(8)


func type_out(box: Panel) -> void:
	box.advance()
	await frames(2)


func page_to(box: Panel, text: String) -> void:
	for _index in range(60):
		if box.active and box.pages[box.page_index] == text:
			break
		box.advance()
		box.advance()
		await frames(1)
	await type_out(box)


func place(point: Vector2, facing := "up") -> void:
	var hero: CharacterBody2D = current_scene.player
	hero.position = point
	hero.velocity = Vector2.ZERO
	hero.facing = facing
	hero.show_idle()
	if current_scene.has_method("follow_player"):
		current_scene.follow_player()
	await frames(6)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	routes = root.get_node("SceneRoutes")
	change_scene_to_file("res://scenes/boot.tscn")
	await arrive("res://scenes/main.tscn")
	story = STORY_STATE.ensure(self)
	var home := current_scene
	await seconds(1.2)
	await shot("title_card")
	while not home.dialogue.active:
		await frames(1)
	await type_out(home.dialogue)
	await shot("opening_tv_subtitle")
	await page_to(home.dialogue, "咚咚 咚咚")
	await shot("knock_caption")
	while home.chapter.busy:
		if home.dialogue.active:
			home.dialogue.advance()
		await frames(2)
	await frames(6)
	await shot("free_in_601_noon")
	home._open_interaction("computer")
	await frames(6)
	await shot("terminal_menu_unread")
	home.chapter._on_menu_chosen(0)
	await frames(2)
	await page_to(home.dialogue, "甚至连他们为什么要死都不知道……")
	await shot("joren_job_bold_line")
	home.dialogue.close()

	routes.travel("d1_hospital")
	await arrive("res://scenes/underground_hospital.tscn")
	var hospital := current_scene
	await seconds(0.6)
	await shot("hospital_day_arrival_dark_entry")
	await place(Vector2(112, 62))
	await seconds(0.7)
	await shot("lamp_light_scan_and_meter")
	while hospital.chapter.locks == 0:
		await frames(1)
	await frames(8)
	await shot("surveillance_lock")
	while hospital.chapter.busy:
		await frames(1)
	hospital.floor_id = 2
	hospital.activate_view(0)
	await frames(6)
	await place(Vector2(300, 172), "right")
	hospital.chapter.exposure = 0.0
	await seconds(0.3)
	await shot("floor2_corridor_powered")
	hospital.interactions.power_states["clinical"] = false
	await place(Vector2(300, 172), "right")
	await seconds(0.3)
	await shot("floor2_corridor_breaker_cut")
	story.set_flag("door:office_door")
	hospital.activate_view(0)
	await place(Vector2(492, 64), "down")
	await seconds(0.3)
	await shot("behind_coburn_in_the_dark")
	key(KEY_F, true)
	await frames(2)
	key(KEY_F, false)
	await frames(4)
	await shot("coburn_kill_flash")
	for _tick in range(180):
		if not hospital.chapter.busy:
			break
		await frames(1)
	await shot("coburn_down")

	routes.travel("d1_return")
	await arrive("res://scenes/home_601.tscn")
	home = current_scene
	await seconds(0.6)
	home._open_interaction("computer")
	home.chapter._on_menu_chosen(0)
	await frames(2)
	await type_out(home.dialogue)
	await shot("contract_receipt_and_resupply_guidance")
	for _page in range(80):
		if not home.dialogue.active:
			break
		home.dialogue.advance()
		await frames(2)
	await frames(6)
	await shot("dark_web_shop")
	home.chapter._on_menu_chosen(1)
	await frames(2)
	await type_out(home.dialogue)
	await shot("shop_order_placed")
	home.dialogue.close()
	await frames(2)
	home.chapter.sleep_to("d1_night")
	await seconds(1.35)
	await shot("rampage_2200")
	await arrive("res://scenes/underground_hospital.tscn")
	await seconds(1.0)
	await shot("night_hospital_side_view")
	await place(Vector2(400, 164), "right")
	await seconds(0.3)
	await shot("night_hospital_upper_floor")

	routes.travel("d1_breath")
	await arrive("res://scenes/breath_interlude.tscn")
	var interlude := current_scene
	while interlude.shown_lines.size() < 1:
		await frames(1)
	await seconds(0.3)
	await shot("breath_line_1")
	while interlude.shown_lines.size() < 3:
		await frames(1)
	await seconds(0.3)
	await shot("breath_line_3")
	await arrive("res://scenes/home_601.tscn")
	home = current_scene
	while not home.dialogue.active:
		await frames(1)
	await type_out(home.dialogue)
	await shot("day2_wake_line")
	while home.chapter.busy:
		if home.dialogue.active:
			home.dialogue.advance()
		await frames(2)
	home._open_interaction("television")
	await frames(2)
	await type_out(home.dialogue)
	await shot("day2_tv_hospital_news")
	var report := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "size": [SIZE.x, SIZE.y], "shots": shots}, "\t"))
	report.close()
	print("captured %d shots" % shots.size())
	quit(0)
