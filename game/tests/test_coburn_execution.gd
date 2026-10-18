extends "res://tests/support/isolated_suite.gd"
## Real F / E input in the day hospital. The fixtures position the hero, then use the shipped input path;
## no test calls the execution method. Rejected inputs must leave both the story and target alive.

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const HOSPITAL := "res://scenes/underground_hospital.tscn"
const BACK := Vector2(492, 64)
const ART := "res://assets/npcs/coburn/"

var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var story: Node
var routes: Node
var hospital: Node2D
var _finished := false


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(80.0, true).timeout.connect(func() -> void:
		check(false, "Coburn execution completes before its deadline")
		finish())
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)


func frames(count := 1) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func key(code: int, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(code: int) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(3)


func place(point: Vector2) -> void:
	CONTROLS.release_actions()
	hospital.player.position = point
	hospital.player.velocity = Vector2.ZERO
	hospital.player.facing = "down"
	hospital.player.show_idle()
	hospital.follow_player()
	await frames(4)


func enter_office(powered := false) -> void:
	story.set_flag("door:office_door")
	hospital.floor_id = 2
	hospital.activate_view(0, "", BACK)
	hospital.interactions.power_states["clinical"] = powered
	await frames(5)
	await place(BACK)


func alive(label: String) -> void:
	check(not story.has_flag("coburn_dead") and story.step == "d1_hospital", label + " leaves the objective unfinished")
	check(not is_instance_valid(hospital.chapter.target) or not hospital.chapter.target.dead, label + " does not kill Coburn")


func art() -> void:
	var target: Node2D = hospital.chapter.target
	check(target.position == Vector2(492, 82) and target.scale == Vector2.ONE, "Coburn keeps the office feet and scale 1")
	var sprites := target.find_children("*", "AnimatedSprite2D", true, false)
	check(sprites.size() == 1, "the detailed doctor is one animated native sprite")
	if sprites.size() != 1:
		return
	var sprite := sprites[0] as AnimatedSprite2D
	check(sprite.scale == Vector2.ONE and not sprite.centered and sprite.offset == Vector2(-24, -40), "all poses share a fixed native-grid foot pivot")
	check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST or target.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"the doctor uses nearest-neighbour pixels")
	for file in ["idle_00.png", "idle_01.png", "collapse_00.png", "dead_00.png"]:
		var image := (load(ART + file) as Texture2D).get_image()
		check(image != null and image.get_size() == Vector2i(48, 48), file + " has the unchanged 48 x 48 canvas")
		if image == null:
			continue
		var hard_alpha := true
		var visible := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var alpha := image.get_pixel(x, y).a
				hard_alpha = hard_alpha and (alpha == 0.0 or alpha == 1.0)
				visible += 1 if alpha == 1.0 else 0
		check(hard_alpha and visible >= 100, file + " contains hard-edged transparent pixel art")
		observations[file] = {"visible_pixels": visible, "bounds": str(image.get_used_rect())}


func rejection_paths() -> void:
	var hud: Node = hospital.chapter.chapter_hud
	check(not hospital.chapter.in_light, "the breaker-off office approach is actually dark")
	check(hud.prompt.visible and hud.key_label.text == "F" and hud.prompt_label.text.contains("科伯恩"),
		"behind the target the prompt names Coburn and the F execution key")
	await tap(KEY_E)
	alive("E from the valid approach")
	if hospital.interactions.dialogue_active:
		hospital.interactions.close_dialogue()
		await frames(2)
	key(KEY_F, true, true)
	await frames(4)
	key(KEY_F, false)
	alive("an F auto-repeat without a fresh press")
	# Put a real wall in the short path, keeping both actor feet and input unchanged.
	var barrier := StaticBody2D.new()
	barrier.collision_layer = 1
	barrier.position = Vector2(492, 66)
	var barrier_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(18, 1)
	barrier_shape.shape = rectangle
	barrier.add_child(barrier_shape)
	hospital.world.add_child(barrier)
	await frames(2)
	await tap(KEY_F)
	alive("F through a solid obstruction")
	check(hud.prompt_label.text.contains("挡住"), "the obstructed path is explained in the live prompt")
	barrier.queue_free()
	await frames(3)

	await place(Vector2(458, 64))
	await tap(KEY_F)
	alive("F beyond 24 native pixels")
	check(not hud.prompt.visible or hud.key_label.text != "F", "the execution key cap disappears outside its reach")
	await place(Vector2(510, 84))
	await tap(KEY_F)
	alive("F from the front")
	check(hud.prompt_label.text.contains("背后"), "the front explains the missing behind-target approach")

	hospital.interactions.power_states["clinical"] = true
	await place(Vector2(480, 74))
	check(hospital.chapter.in_light, "the bright refusal fixture stands inside the real office-screen light")
	await tap(KEY_F)
	alive("F in monitor light")
	hospital.interactions.power_states["clinical"] = false
	await place(BACK)

	hospital.interactions.dialogue.open(["测试中的调查内容。"], "调查", hospital.player)
	await frames(2)
	await tap(KEY_F)
	alive("F while reading")
	check(hospital.interactions.dialogue_active, "F does not advance or dismiss ordinary E dialogue")
	hospital.interactions.close_dialogue()
	await frames(3)

	await tap(KEY_ESCAPE)
	var session: Node = hospital.get_node("GameSession")
	check(session.settings_open and paused, "the real settings key opens and pauses the scene")
	await tap(KEY_F)
	alive("F while the settings are open")
	await tap(KEY_ESCAPE)
	check(not session.settings_open and not paused and not hospital.player.is_frozen(), "closing settings restores the player")

	story.set_flag("door:office_door", false)
	hospital.security.refresh_view()
	await place(Vector2(502, 152))
	await tap(KEY_E)
	check(hospital.security.keypad_active, "ordinary E opens the real office keypad for the modal refusal")
	await place(BACK)
	await tap(KEY_F)
	alive("F while entering the office password")
	hospital.security.close_keypad()
	story.set_flag("door:office_door")
	hospital.security.refresh_view()
	await frames(2)
	hospital.stairs_busy = true
	await tap(KEY_F)
	alive("F during a staircase transition")
	hospital.stairs_busy = false

	story.set_step("d1_return")
	await tap(KEY_F)
	check(not story.has_flag("coburn_dead") and story.step == "d1_return", "F outside the assassination step cannot advance the story")
	story.set_step("d1_hospital")
	hospital.floor_id = 1
	hospital.activate_view(0)
	await frames(4)
	await place(BACK)
	await tap(KEY_F)
	alive("F at identical coordinates on floor 1")
	check(not is_instance_valid(hospital.chapter.target), "Coburn is only instantiated on floor 2")

	hospital.floor_id = 2
	hospital.activate_view(1)
	await frames(5)
	await tap(KEY_F)
	alive("F in side view")
	check(not is_instance_valid(hospital.chapter.target), "the day-only target has no side-view copy")
	await enter_office()


func rebound_movement() -> void:
	var profile := CONTROLS.defaults()
	profile["move_left"] = KEY_J
	check(CONTROLS.validate(profile).is_empty(), "the ordinary movement profile can still be customized")
	CONTROLS.current = profile
	CONTROLS.install(false)
	await place(BACK)
	var before: Vector2 = hospital.player.position
	key(KEY_J, true)
	await frames(4)
	key(KEY_J, false)
	await frames(4)
	check(hospital.player.position.x < before.x - 1.0, "a rebound movement key uses the real hospital input path")
	await tap(KEY_E)
	alive("reserved E with customized movement")
	if hospital.interactions.dialogue_active:
		hospital.interactions.close_dialogue()
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	await place(BACK)


func execute_and_leave() -> void:
	var chapter: Node = hospital.chapter
	var victim: Node2D = chapter.target
	var sprite: AnimatedSprite2D = victim.find_children("*", "AnimatedSprite2D", true, false)[0]
	var foot: Vector2 = victim.position
	var transitions: Array[String] = []
	story.step_changed.connect(func(value: String) -> void: transitions.append(value))
	# The last three pixels of the approach use real movement rather than a direct call to the kill logic.
	await place(Vector2(492, 61))
	key(KEY_S, true)
	await frames(3)
	key(KEY_S, false)
	await frames(6)
	check(hospital.player.position.y > 61.0 and hospital.player.position.distance_to(foot) <= 24.0,
		"held S walks into assassination range on the real colliders")
	check(chapter.chapter_hud.key_label.text == "F", "the approach advertises the actual execution key")
	key(KEY_F, true)
	await frames(1)
	check(chapter.busy and hospital.player.is_frozen(), "a fresh F press starts a bounded execution and holds the hero")
	var held_at: Vector2 = hospital.player.position
	key(KEY_R, true)
	key(KEY_TAB, true)
	await frames(1)
	key(KEY_R, false)
	key(KEY_TAB, false)
	check(hospital.view_mode == 0 and hospital.chapter.target == victim and hospital.player.position == held_at,
		"R and Tab cannot reset the scene or projection during the execution")
	key(KEY_F, true, true)
	await frames(2)
	key(KEY_F, false)
	await tap(KEY_E)
	await tap(KEY_F1)
	check(not hospital.get_node("GameSession").settings_open, "the execution owns its modal; F1 cannot interrupt it")
	for _tick in range(180):
		if not chapter.busy:
			break
		await frames()
	check(not chapter.busy and not hospital.player.is_frozen() and not paused, "the execution releases its freeze without leaving the scene paused")
	check(victim.dead and story.has_flag("coburn_dead") and story.step == "d1_target_down", "F executes Coburn and advances to the scripted withdrawal")
	check(story.balance == 0, "executing the target does not pay before leaving the hospital")
	check(transitions.count("d1_target_down") == 1, "held F, repeats and E produce only one story transition")
	check(chapter.overlay.shown.has("strike") and not hospital.interactions.dialogue_active, "the execution strikes without inventing spoken lines")
	check(victim.position == foot and victim.scale == Vector2.ONE and sprite.scale == Vector2.ONE,
		"collapse and death never move the target's feet or resize the actor")
	check(sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame).resource_path.ends_with("dead_00.png"),
		"the completed execution displays the dedicated dead pose")
	check(not hospital.get_node("GameSession").has_modal(), "the finished execution removes its modal lock")
	var before: Vector2 = hospital.player.position
	key(KEY_D, true)
	await frames(5)
	key(KEY_D, false)
	await frames(5)
	check(hospital.player.position.x > before.x + 1.0, "real movement resumes after the execution")
	await tap(KEY_F)
	check(transitions.count("d1_target_down") == 1 and victim.dead, "F on the body cannot execute or advance twice")

	# Re-entering a built floor restores the same dead pose and keeps the exit objective.
	hospital.activate_view(0, "", Vector2(590, 175))
	await frames(6)
	check(hospital.chapter.target.dead and story.step == "d1_target_down", "floor reconstruction retains the completed execution")
	await place(Vector2(590, 175))
	await tap(KEY_E)
	for _tick in range(120):
		if current_scene != null and current_scene.scene_file_path == "res://scenes/home_601.tscn" and not routes.switching:
			break
		await frames()
	check(current_scene != null and current_scene.scene_file_path == "res://scenes/home_601.tscn" and story.step == "d1_return",
		"ordinary E at the exit still withdraws to 601 at the next script step")
	check(story.balance == 50, "the real exit settles exactly 50 yuan upon reaching 601")
	observations["execution_transitions"] = transitions


func run() -> void:
	routes = root.get_node("SceneRoutes")
	story = STORY_STATE.ensure(self)
	story.start_chapter()
	routes.travel("d1_hospital")
	for _tick in range(120):
		if current_scene != null and current_scene.scene_file_path == HOSPITAL and not routes.switching:
			break
		await frames()
	hospital = current_scene
	check(hospital != null and hospital.scene_file_path == HOSPITAL, "the real chapter route opens the day hospital")
	if hospital == null or hospital.scene_file_path != HOSPITAL:
		finish()
		return
	await frames(36)
	await enter_office()
	art()
	await rejection_paths()
	await rebound_movement()
	await execute_and_leave()
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	CONTROLS.release_actions()
	key(KEY_F, false)
	print(JSON.stringify({"suite": "coburn_execution", "checks": checks, "failures": failures,
		"observations": observations, "status": "passed" if failures.is_empty() else "failed"}))
	quit(0 if failures.is_empty() else 1)
