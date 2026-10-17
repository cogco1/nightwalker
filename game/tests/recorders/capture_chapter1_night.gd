extends "res://tests/support/isolated_suite.gd"
## Real GPU captures of chapter 1 milestone 2 for review, writes evidence/chapter1_night/. First a staged pass:
## the hero goes down (red wash, black) and the floor starts over, and the overheal strip on the health plate.
## Then the night from the top, played by tests/support/night_bot.gd with real input, captured as it happens: each
## lesson's icons, a guard's red wind-up, the perfect dodge's slow motion and the counter, a hit on the health
## plate, the gunner's laser sight and bullet, the cowering buyer, the begging doctor, the climb, the last doctor's
## three lines, the execution's white frame and black, and the held breath.

const CONTROLS = preload("res://scripts/core/controls.gd")
const STORY_STATE = preload("res://scripts/core/story_state.gd")
const NIGHT_BOT = preload("res://tests/support/night_bot.gd")
const OUT := "res://evidence/chapter1_night/"
const SIZE := Vector2i(1280, 720)
const HOSPITAL := "res://scenes/underground_hospital.tscn"
var story: Node
var routes: Node
var shots: Array[Dictionary] = []
var taken: Dictionary = {}


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(240.0).timeout.connect(func() -> void:
		push_error("Chapter 1 night recorder exceeded its deadline")
		quit(2)
	)
	call_deferred("run")


func frames(count := 4) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func shot(label: String) -> void:
	if root.mode != Window.MODE_WINDOWED or root.size != SIZE:
		root.mode = Window.MODE_WINDOWED
		root.size = SIZE
		await frames(2)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var filename := "%02d_%s.png" % [shots.size() + 1, label]
	image.save_png(OUT + filename)
	var scene := current_scene
	var hero: Variant = scene.get("player") if scene != null else null
	var fight: Variant = scene.chapter.get("fight") if scene != null and scene.get("chapter") != null else null
	shots.append({"file": filename, "scene": scene.scene_file_path if scene != null else "", "step": story.step,
		"hero": [hero.position.x, hero.position.y] if hero != null else [],
		"health": fight.vitals.hp if fight != null else -1, "lesson": fight.tutorial.lesson if fight != null else ""})


## A capture the first time `label` comes true.
func once(label: String, condition: bool) -> void:
	if condition and not taken.has(label):
		taken[label] = true
		await shot(label)


func open_night() -> Node2D:
	routes.travel("d1_night")
	for _index in range(600):
		if current_scene != null and current_scene.scene_file_path == HOSPITAL and not routes.switching:
			break
		await frames(1)
	await frames(50)
	return current_scene


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	routes = root.get_node("SceneRoutes")
	story = STORY_STATE.ensure(self)
	story.start_chapter()
	await staged_pass()
	await played_pass()
	var report := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "size": [SIZE.x, SIZE.y], "shots": shots}, "\t"))
	report.close()
	print("captured %d shots" % shots.size())
	quit(0)


## Going down and starting over; the overheal strip.
func staged_pass() -> void:
	var hospital := await open_night()
	var fight: Node = hospital.chapter.fight
	var hero: CharacterBody2D = hospital.player
	var guard: Node2D = fight.enemies[0]
	fight.vitals.grant_overheal(30)
	hero.position = Vector2(guard.position.x - 60.0, 286)
	hospital.follow_player()
	await frames(20)
	await shot("overheal_strip")
	fight.vitals.overheal = 0
	fight.vitals.hp = 6
	hero.position = Vector2(guard.position.x - 22.0, 286)
	for _index in range(400):
		if fight.busy:
			break
		await frames(1)
	await frames(6)
	await shot("going_down_red_wash")
	for _index in range(200):
		if not fight.busy:
			break
		await frames(1)
	await frames(2)
	await shot("floor_starts_over")


func played_pass() -> void:
	story.start_chapter()
	var hospital := await open_night()
	var fight: Node = hospital.chapter.fight
	var bot: RefCounted = NIGHT_BOT.new(self)
	bot.bind(hospital)
	var session: Node = hospital.get_node("GameSession")
	var box: Panel = hospital.interactions.dialogue
	var counter_at := -1
	hospital.player.counter_started.connect(func(_enemy: Node2D) -> void: counter_at = bot.frames_run)
	var hit_at := -1
	hospital.player.attack_received.connect(func(result: int, _attack: Dictionary) -> void:
		if result == 0 and hit_at < 0:
			hit_at = bot.frames_run)
	var lesson_seen := ""
	var lesson_frames := 0
	await shot("night_starts_move_lesson")
	for _index in range(9000):
		if story.step == "d1_breath" or not is_instance_valid(fight):
			break
		await bot.tick()
		bot.frames_run += 1
		if not is_instance_valid(fight):
			break
		var lesson: String = fight.tutorial.lesson
		if lesson != lesson_seen:
			lesson_seen = lesson
			lesson_frames = 0
		lesson_frames += 1
		if lesson_frames == 20 and lesson in ["light", "heavy", "dodge", "perfect"]:
			await once("lesson_" + lesson, true)
		var winding := false
		for body in fight.living(false):
			if body.kind == "guard" and body.attacker.phase == body.attacker.Phase.TELEGRAPH and body.attacker.phase_time > 0.3:
				winding = true
		await once("guard_winds_up_red", winding)
		await once("perfect_dodge_slow_motion", session.slowmo_active)
		await once("counter_blink_slash", counter_at >= 0 and bot.frames_run == counter_at + 4)
		await once("hit_red_trail", hit_at >= 0 and bot.frames_run == hit_at + 3)
		var locked := false
		for body in fight.living(false):
			if body.kind == "gunner" and body.locked():
				locked = true
		await once("gunner_laser_locked", locked)
		var coming: Array = bot.bullet_coming()
		await once("bullet_in_flight", not coming.is_empty() and coming[1] < 70.0 and coming[1] > 30.0)
		var cowering := false
		var begging := false
		for body in fight.living(false):
			cowering = cowering or (body.kind == "buyer" and body.cowering)
			begging = begging or (body.kind == "doctor" and body.begging)
		await once("buyer_cowers", cowering)
		await once("doctor_begs", begging)
		await once("climbing_stairs", hospital._using_stairs and hospital.player.position.y < 230.0)
		await once("floor2_arrival", hospital.floor_id == 2 and hospital.player.is_on_floor() and not hospital._using_stairs)
		if box.active and box.body.visible_characters < 0 or box.active and box.body.visible_characters >= box.body.text.length():
			await once("last_words_%d" % (box.page_index + 1), true)
		await once("execute_prompt", is_instance_valid(fight.last_doctor) and fight.last_doctor.executable and not fight.busy)
		await once("execution_white", hospital.chapter.overlay.tint.color.a >= 0.99 and hospital.chapter.overlay.tint.color.r >= 0.99)
		await once("execution_black", fight.executed and hospital.chapter.overlay.shade.color.a >= 0.99)
	bot.release_all()
	for _index in range(600):
		if current_scene != null and current_scene.scene_file_path == "res://scenes/breath_interlude.tscn" and not routes.switching:
			break
		await frames(1)
	var interlude := current_scene
	for _index in range(600):
		if interlude.shown_lines.size() >= 1:
			break
		await frames(1)
	await frames(18)
	await shot("breath_after_the_night")
