extends "res://tests/support/isolated_suite.gd"
## Real GPU frames of the hit-impact prototype (scripts/core/impact_burst.gd) on the first night's guards, each move
## played twice with real mouse input: prototype on, then off (impact v2 alone). Writes every displayed frame of
## each take to evidence/impact_burst/<take>/NNN.png plus report.json; tools/art_qa/compose_impact_burst.py turns
## the takes into side-by-side GIFs.

const CONTROLS = preload("res://scripts/core/controls.gd")
const STORY_STATE = preload("res://scripts/core/story_state.gd")
const IMPACT_BURST = preload("res://scripts/core/impact_burst.gd")
const OUT := "res://evidence/impact_burst/"
const SIZE := Vector2i(1280, 720)
const HOSPITAL := "res://scenes/underground_hospital.tscn"
var routes: Node
var story: Node
var hospital: Node2D
var fight: Node
var takes: Array[Dictionary] = []


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(240.0).timeout.connect(func() -> void:
		push_error("Impact prototype recorder exceeded its deadline")
		quit(2)
	)
	call_deferred("run")


func frames(count := 1) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func mouse(button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = Vector2(160, 90)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func run() -> void:
	routes = root.get_node("SceneRoutes")
	story = STORY_STATE.ensure(self)
	story.start_chapter()
	routes.travel("d1_night")
	for _index in range(600):
		if current_scene != null and current_scene.scene_file_path == HOSPITAL and not routes.switching:
			break
		await frames(1)
	root.mode = Window.MODE_WINDOWED
	root.size = SIZE
	await frames(30)
	hospital = current_scene
	fight = hospital.chapter.fight
	# The lessons are not what is being looked at.
	fight.lesson = fight.LESSONS.size()
	fight.tutorial.hide_plate()
	await frames(10)
	for on in [true, false]:
		IMPACT_BURST.enabled = on
		var suffix := "on" if on else "off"
		await take("charged_draw_" + suffix, func() -> void:
			mouse(MOUSE_BUTTON_LEFT, true)
			await frames(40)
			mouse(MOUSE_BUTTON_LEFT, false), 70)
		await take("heavy_cleave_" + suffix, func() -> void:
			mouse(MOUSE_BUTTON_RIGHT, true)
			await frames(1)
			mouse(MOUSE_BUTTON_RIGHT, false), 60)
		await take("light_crit_" + suffix, func() -> void:
			for _index in range(3):
				mouse(MOUSE_BUTTON_LEFT, true)
				await frames(1)
				mouse(MOUSE_BUTTON_LEFT, false)
				await frames(19), 40)
	IMPACT_BURST.enabled = true
	var report := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "size": [SIZE.x, SIZE.y], "takes": takes}, "\t"))
	report.close()
	print("recorded %d takes" % takes.size())
	quit(0)


## A fresh guard 26 px ahead of a still hero, the move played by `act`, every displayed frame from the first input
## until `tail` frames after it ends saved.
func take(label: String, act: Callable, tail: int) -> void:
	fight.restart_floor(1)
	await frames(20)
	var guard: Node2D = fight.enemies.filter(func(body: Node2D) -> bool: return body.id == "ward_guard_1")[0]
	for body in fight.living():
		body.held = true
	var hero: CharacterBody2D = hospital.player
	hero.position = Vector2(guard.position.x - 26.0, 286)
	hero.velocity = Vector2.ZERO
	hero.facing = "right"
	hero.critical_roll_override = 0.0
	hero.show_idle()
	hospital.follow_player()
	await frames(20)
	var folder := OUT + label + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var state := {"count": 0, "recording": true}
	var burst: Node = hospital.get_node("GameSession").impact_burst
	var before := {"waves": burst.waves_thrown, "cuts": burst.cuts_made, "tears": burst.tears}
	_record(folder, state)
	await act.call()
	await frames(tail)
	state["recording"] = false
	await frames(2)
	takes.append({"take": label, "frames": state["count"], "guard_hp": guard.hp, "waves": burst.waves_thrown - before["waves"],
		"cuts": burst.cuts_made - before["cuts"], "tears": burst.tears - before["tears"]})


func _record(folder: String, state: Dictionary) -> void:
	while state["recording"]:
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.resize(640, 360, Image.INTERPOLATE_NEAREST)
		image.save_png(folder + "%03d.png" % state["count"])
		state["count"] = int(state["count"]) + 1
