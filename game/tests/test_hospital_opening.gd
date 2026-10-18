extends "res://tests/test_chapter_flow.gd"
## The public boot, exact requested captions, harmless staff, and independently powered moving surveillance.
## Fixture placements below isolate light/NPC behavior; chapter_flow walks the complete live stealth route.

const CONTROLS = preload("res://scripts/core/controls.gd")
const SPAWN := Vector2(566, 78)
var hospital: Node2D


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(100.0, true).timeout.connect(func() -> void:
		check(false, "the hospital opening completes before its deadline")
		finish())
	call_deferred("run")


## The GPU recorder overrides this hook, without changing the assertions or input sequence.
func observe(_label: String) -> void:
	await frames(1)


func staff_on_floor(expected: int) -> void:
	var staff: Node = hospital.world.get_node_or_null("DayStaff")
	check(staff != null and staff.get_child_count() == expected, "the current floor has its own small doctor roster")
	if staff == null:
		return
	for doctor: Node2D in staff.get_children():
		check(doctor.scale == Vector2.ONE and doctor.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"a moving doctor keeps the native pixel drawing and scale")
		check(doctor is CharacterBody2D and doctor.collision_layer == 0 and doctor.collision_mask == 1,
			"a doctor respects walls without blocking or attacking the player")
		check(not doctor.is_in_group("enemies") and not doctor.has_method("take_damage"),
			"a doctor never joins hostile AI or attack targets")
		check(hospital.position_is_clear(doctor.position, 0), "the doctor stands on clear floor")
		for point: Vector2 in doctor.patrol_points:
			check(hospital.position_is_clear(point, 0), "the doctor's whole footprint fits at its patrol endpoint " + str(point))


func opening() -> void:
	# Reuse the complete public safehouse opening, real computer interaction and E at the exit.
	await day_one_home()
	if not await arrive(HOSPITAL, "The safehouse door"):
		return
	hospital = current_scene
	story = STORY_STATE.ensure(self)
	check(story.step == "d1_hospital" and story.clock_text() == "12:30" and hospital.floor_id == 1 and hospital.view_mode == 0,
		"leaving the safehouse contract enters the day hospital at 12:30, without a developer step override")
	check(hospital.player.position == SPAWN and hospital.chapter.checkpoint == SPAWN, "the screenshot's pharmacy corridor is the spawn and checkpoint")
	check(hospital.position_is_clear(SPAWN, 0) and hospital.lighting.light_level(SPAWN) < hospital.chapter.LIT_THRESHOLD,
		"the new spawn is clear and safe from surveillance")
	for _tick in range(120):
		if hospital.interactions.dialogue_active:
			break
		await frames()
	var box: Panel = hospital.interactions.dialogue
	check(box.active and box.pages == ["光粒子监控，真是麻烦..."], "arrival displays the requested exact monologue")
	check(box.page_speakers == ["protagonist"] and box.portrait.visible, "the monologue uses the protagonist portrait")
	check(hospital.chapter.busy and player().is_frozen(), "the arrival reading owns its input freeze")
	key(KEY_A, true)
	await frames(12)
	key(KEY_A, false)
	check(player().position == SPAWN and hospital.chapter.exposure == 0.0, "the opening cannot drift or accumulate exposure")
	await observe("opening_monologue")
	await read_all(box)
	await frames(3)
	var hud: Node = hospital.chapter.chapter_hud
	check(hud.toast_panel.visible and hud.toast_label.text == "请尽快躲避光线，shift奔跑。", "the requested avoidance and Shift subtitle follows the monologue")
	check(not hospital.chapter.busy and not player().is_frozen() and not hospital.get_node("GameSession").has_modal(),
		"the tutorial caption leaves normal movement available")
	await observe("avoid_light_shift_caption")
	staff_on_floor(3)
	check(hospital.lighting.patrols.is_empty(), "moving surveillance is reserved for floor two")
	await frames(90)
	check(hospital.chapter.locks == 0 and hospital.chapter.exposure == 0.0, "waiting at the arrival is safe")
	# Real held keys verify the caption's action, rather than only checking a binding dictionary.
	key(KEY_SHIFT, true)
	key(KEY_A, true)
	await frames(18)
	check(player().is_running and absf(player().velocity.x) > player().move_speed * 1.5,
		"held Shift and A actually run faster in top-down view")
	key(KEY_A, false)
	key(KEY_SHIFT, false)
	await frames(10)
	await tap(KEY_R)
	check(player().position == SPAWN and not box.active and story.has_flag("sequence:hospital_opening"),
		"reset returns to the new checkpoint without repeating the monologue")
	# The presentation fixture shows the simple daytime staff in the ward.
	player().position = Vector2(268, 178)
	player().velocity = Vector2.ZERO
	hospital.follow_player()
	await frames(6)
	await observe("daytime_ward_doctors")


func locked_breaker() -> void:
	player().position = Vector2(116, 157)
	player().velocity = Vector2.ZERO
	hospital.follow_player()
	await frames(4)
	await tap(KEY_E)
	check(hospital.interactions.dialogue_active and hospital.interactions.power_states["clinical"],
		"E at the cabinet gives feedback and leaves power on")
	check(not story.has_flag("breaker_unlocked"), "the day chapter cannot unlock the monitored circuit")
	await observe("breaker_cannot_be_cut")
	await read_all(hospital.interactions.dialogue)
	story.grant_item("breaker_key")
	story.set_flag("breaker_unlocked")
	await tap(KEY_E)
	check(hospital.interactions.power_states["clinical"] and story.has_item("breaker_key"),
		"a key and an old unlocked flag cannot cut power or consume the key")
	check(not hospital.security.try_unlock_breaker(), "the security entry point also rejects the override")
	await read_all(hospital.interactions.dialogue)


func surveillance() -> void:
	hospital.change_floor(2)
	await frames(6)
	check(hospital.floor_id == 2 and not hospital.interactions.dialogue_active, "floor two does not repeat the opening")
	staff_on_floor(2)
	var lighting: Node = hospital.lighting
	check(lighting.patrols.size() == 3, "floor two has three moving surveillance lights")
	var positions: Dictionary = {}
	var textures: Dictionary = {}
	for source: Dictionary in lighting.patrols:
		var light: PointLight2D = source.light
		positions[source.id] = light.position
		textures[source.id] = light.texture.get_instance_id()
		check(light.enabled and source.section == "", "a patrol has independent power")
		check(light.position == light.position.round() and light.texture_scale == 1.0, "a patrol draws at native integer positions")
		check(lighting.light_level(light.position) >= hospital.chapter.LIT_THRESHOLD, "standing in the visible beam counts as exposed")
	player().position = Vector2(610, 186)
	player().velocity = Vector2.ZERO
	hospital.follow_player()
	await frames(90)
	await observe("floor_two_moving_lights_a")
	for source: Dictionary in lighting.patrols:
		check(source.light.position != positions[source.id], "the visible patrol changes position over time")
		check(source.light.texture.get_instance_id() == textures[source.id], "movement reuses the cached light texture")
	var before: float = lighting._patrol_clock
	player().freeze(self)
	await frames(45)
	check(lighting._patrol_clock == before, "patrols pause while the player is frozen")
	player().unfreeze(self)
	await tap(KEY_F1)
	before = lighting._patrol_clock
	await frames(45)
	check(hospital.get_node("GameSession").settings_open and lighting._patrol_clock == before,
		"the settings modal pauses moving surveillance")
	await tap(KEY_ESCAPE)
	check(not hospital.get_node("GameSession").settings_open and not paused, "closing settings restores normal play")
	# A stationary feet probe sees the actual moving pool arrive and leave; the live meter must react too.
	player().position = Vector2(290, 168)
	player().velocity = Vector2.ZERO
	hospital.follow_player()
	var dim := false
	var bright := false
	var peak := 0.0
	var office_dim := false
	var office_bright := false
	for _tick in range(800):
		var level: float = lighting.light_level(Vector2(290, 168))
		dim = dim or level < hospital.chapter.LIT_THRESHOLD
		bright = bright or level >= hospital.chapter.LIT_THRESHOLD
		peak = maxf(peak, hospital.chapter.exposure)
		var office_level: float = lighting.light_level(Vector2(492, 64))
		office_dim = office_dim or office_level < hospital.chapter.LIT_THRESHOLD
		office_bright = office_bright or office_level >= hospital.chapter.LIT_THRESHOLD
		await frames()
	check(dim and bright and peak > 0.15, "a real moving beam changes exposure at stationary feet")
	check(office_dim and office_bright, "the office approach has both monitored and dark execution windows")
	observations["moving_beam_peak_exposure"] = peak
	player().position = Vector2(470, 186)
	player().velocity = Vector2.ZERO
	hospital.follow_player()
	await frames(5)
	await observe("floor_two_moving_lights_b")
	check(hospital.interactions.power_states["clinical"], "the surveillance journey leaves the circuit powered")
	routes.travel("d1_night")
	if not await arrive(HOSPITAL, "The existing side-view night"):
		return
	check(current_scene.view_mode == 1 and current_scene.lighting.patrols.is_empty()
		and current_scene.world.get_node_or_null("DayStaff") == null,
		"side-view night has neither daytime staff nor roaming lights")
	check(current_scene.chapter.fight.enemies.size() == 11, "the night keeps its existing enemy roster")


func run() -> void:
	routes = root.get_node("SceneRoutes")
	await opening()
	if not is_instance_valid(hospital):
		finish()
		return
	await locked_breaker()
	await surveillance()
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	CONTROLS.release_actions()
	print(JSON.stringify({"suite": "hospital_opening", "checks": checks, "failures": failures,
		"observations": observations, "status": "passed" if failures.is_empty() else "failed"}))
	quit(0 if failures.is_empty() else 1)
