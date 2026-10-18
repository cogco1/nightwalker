extends "res://tests/test_hospital_opening.gd"
## Real E/password input plus isolated vision fixtures. The full paid route lives in chapter_flow.


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(150.0, true).timeout.connect(func() -> void:
		check(false, "hospital layout and surveillance complete before their deadline")
		finish())
	call_deferred("run")


func place_at(point: Vector2) -> void:
	CONTROLS.release_actions()
	for _tick in range(180):
		if not hospital.chapter.busy:
			break
		await frames()
	player().position = point
	player().velocity = Vector2.ZERO
	hospital.follow_player()
	await frames(3)


func stairs_and_clue() -> void:
	await place_at(Vector2(48, 132))
	var hud: Node = hospital.chapter.chapter_hud
	check(hospital.position_is_clear(player().position, 0), "the photographed upper stair approach is clear floor")
	check(hospital.interactions.nearest_id == "stairs_up" and hud.prompt.visible and hud.prompt_label.text.contains("上二楼"),
		"the upper stair approach already offers E to go upstairs")
	await observe("upper_stair_prompt")
	await tap(KEY_E)
	await frames(5)
	check(hospital.floor_id == 2, "E from the upper approach actually reaches floor two")
	check(hospital.security.is_door_unlocked("storage_door") and hospital.security.is_door_unlocked("treatment_door")
		and not hospital.security.is_door_unlocked("office_door"), "only Coburn's office starts password-locked")
	var body: StaticBody2D = hospital.security.get("_door_bodies").get("treatment_door")
	check(body != null and body.collision_layer == 0, "the open treatment door has no blocking collision")
	# These feet are below the actual north wall. Furniture must fill its back edge instead of leaving a
	# playable gap that lets the character appear to stand on chair backs, countertops or cabinet tops.
	for point: Vector2 in [Vector2(69, 60), Vector2(132, 60), Vector2(181, 60), Vector2(235, 60),
		Vector2(261, 60), Vector2(436, 60), Vector2(465, 60), Vector2(575, 60)]:
		check(not hospital.position_is_clear(point, 0), "wall-side furniture blocks the misleading rear gap at " + str(point))
	check(hospital.position_is_clear(Vector2(510, 64), 0) and hospital.position_is_clear(Vector2(492, 64), 0),
		"the office rearrangement preserves a real approach behind Coburn")
	# The reception computer no longer leaks the door code.
	var computer: Dictionary = hospital.interactions._find_interaction("reception_pc")
	var computer_at: Array = computer.anchors.top_down
	await place_at(Vector2(computer_at[0], computer_at[1]))
	await tap(KEY_E)
	check(hospital.interactions.dialogue_active, "E still reads the reception computer")
	var pages := await read_all(hospital.interactions.dialogue)
	check(not str(pages).contains("1010"), "the computer contains no password")
	var drawer: Dictionary = hospital.interactions._find_interaction("treatment_drawer")
	check(not drawer.is_empty() and drawer.has("drawer_rect"), "the actual treatment cabinet has its own drawer interaction")
	if drawer.is_empty():
		return
	var anchor: Array = drawer.anchors.top_down
	await place_at(Vector2(anchor[0], anchor[1]))
	check(hospital.position_is_clear(player().position, 0), "the drawer's south approach is reachable floor")
	await tap(KEY_E)
	check(hospital.interactions.dialogue_active and hospital.interactions.current_interaction == "treatment_drawer",
		"E opens the requested drawer reading")
	check(float(hospital.interactions.get("_feedback_remaining")) > 0.0, "the drawer also starts its short opening animation")
	check(str(hospital.interactions.dialogue.pages).contains("1010"), "the drawer note provides the office code 1010")
	await observe("drawer_note_and_animation")
	await read_all(hospital.interactions.dialogue)
	# Read and enter the code through the shipped keypad path, keeping the other doors open.
	await place_at(Vector2(502, 160))
	await tap(KEY_E)
	check(hospital.security.keypad_active, "only the office door offers a keypad")
	for digit in "1011":
		await tap(KEY_0 + int(digit), digit.unicode_at(0))
	await tap(KEY_ENTER)
	check(not hospital.security.is_door_unlocked("office_door") and hospital.security.keypad_active,
		"a wrong code leaves the office shut")
	for _digit in range(4):
		await tap(KEY_BACKSPACE)
	for digit in "1010":
		await tap(KEY_0 + int(digit), digit.unicode_at(0))
	await tap(KEY_ENTER)
	await frames(18)
	check(hospital.security.is_door_unlocked("office_door") and not hospital.security.keypad_active,
		"the drawer's code opens the real office door")


func patrol_and_light() -> Node2D:
	await place_at(Vector2(610, 186))
	var lighting: Node = hospital.lighting
	check(lighting.patrols.size() == 3, "the three surveillance pools remain")
	for source: Dictionary in lighting.patrols:
		check(float(source.radius) >= (38.0 if source.id == "patrol_office" else 32.0), "the moving pool radius is larger than the previous version")
		check(source.emission == null, "the moving light has no central white marker")
		var reach := Rect2(source.reach)
		check(minf(source.from.x, source.to.x) - float(source.radius) >= reach.position.x
			and maxf(source.from.x, source.to.x) + float(source.radius) <= reach.end.x,
			"the moving texture never crosses a side wall")
	await observe("larger_pools_without_white_centres")
	var doctors: Array[Node] = hospital.chapter.day_staff.get_children()
	var doctor: Node2D
	for candidate: Node2D in doctors:
		if candidate.staff_id == "treatment_staff":
			doctor = candidate
	check(doctor != null, "the photographed treatment doctor has a patrol")
	if doctor == null:
		return null
	var start: Vector2 = doctor.position
	var moved := 0.0
	var directions: Dictionary = {}
	for _tick in range(150):
		directions[str(doctor.face_direction)] = true
		moved = maxf(moved, doctor.position.distance_to(start))
		await frames(6)
	check(moved >= 8.0 and directions.size() >= 2, "the doctor walks and turns instead of remaining a fixed cutout")
	check(doctor.sight != null and doctor.sight.visible, "the doctor's field of view is drawn")
	var before: Vector2 = doctor.position
	var clock: float = doctor.patrol_clock
	player().freeze(self)
	await frames(45)
	check(doctor.position == before and doctor.patrol_clock == clock, "doctor movement pauses with a reading or player freeze")
	player().unfreeze(self)
	# Isolate one observer for the wall/front/back tests; the live full route keeps every doctor present.
	for other: Node in doctors:
		if other != doctor:
			other.queue_free()
	doctor.set_physics_process(false)
	await frames(2)
	return doctor


func vision(doctor: Node2D) -> void:
	doctor.position = Vector2(226, 112)
	doctor.face_direction = Vector2.LEFT
	await place_at(Vector2(180, 112))
	check(not doctor.sees_player(player()), "the actual reception partition blocks the doctor's sight")
	await place_at(Vector2(260, 112))
	check(not doctor.sees_player(player()), "standing behind the doctor stays outside the viewing angle")
	# The treatment doorway is open, so its label cannot act as an invisible vision wall.
	doctor.position = Vector2(299, 130)
	doctor.face_direction = Vector2.DOWN
	await place_at(Vector2(299, 166))
	check(doctor.sees_player(player()), "an open doorway transmits a real unobstructed view")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = Vector2(299, 140)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(32, 10)
	shape.shape = rectangle
	wall.add_child(shape)
	hospital.world.add_child(wall)
	await frames(2)
	check(not doctor.sees_player(player()), "a solid obstruction in that doorway stops sight")
	wall.queue_free()
	await frames(2)
	# A stationary observer in a dark part of the treatment room proves that sight itself raises the meter.
	doctor.position = Vector2(348, 128)
	doctor.face_direction = Vector2.LEFT
	await place_at(Vector2(316, 128))
	hospital.chapter.exposure = 0.0
	var locks: int = hospital.chapter.locks
	check(hospital.lighting.light_level(player().position) < hospital.chapter.LIT_THRESHOLD and doctor.sees_player(player()),
		"this witness fixture is dark but lies inside the real viewing angle")
	await frames(24)
	check(hospital.chapter.in_sight and not hospital.chapter.in_light and hospital.chapter.exposure > 0.25,
		"the doctor alone notices a player who lingers in the cone")
	check(hospital.chapter.hud.meter_label.text == "目击", "the HUD identifies the witness exposure")
	await observe("doctor_view_and_witness_meter")
	for _tick in range(180):
		if hospital.chapter.locks > locks:
			break
		await frames()
	check(hospital.chapter.locks == locks + 1 and hospital.chapter.overlay.shown.has("lock:医生发现了你"),
		"lingering in the cone triggers the doctor's discovery feedback")
	for _tick in range(180):
		if not hospital.chapter.busy:
			break
		await frames()
	check(player().position.distance_to(hospital.chapter.checkpoint) < 1.0 and hospital.chapter.exposure == 0.0,
		"being discovered restores the current floor checkpoint")
	check(not doctor.is_in_group("enemies") and not doctor.has_method("take_damage"), "the observer still has no hostile combat role")


func run() -> void:
	routes = root.get_node("SceneRoutes")
	await opening()
	if not is_instance_valid(hospital):
		finish()
		return
	await stairs_and_clue()
	var doctor := await patrol_and_light()
	if is_instance_valid(doctor):
		await vision(doctor)
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	CONTROLS.release_actions()
	print(JSON.stringify({"suite": "hospital_revision", "checks": checks, "failures": failures,
		"observations": observations, "status": "passed" if failures.is_empty() else "failed"}))
	quit(0 if failures.is_empty() else 1)
