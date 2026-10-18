extends "res://tests/support/isolated_suite.gd"
## Top-down stealth light: every hospital source lights its own room or corridor and nothing past a wall, the
## gameplay light level uses the same bands and reach as the light textures, the breaker darkens the floor-2
## corridor, the exposure meter fills in light and drains in the dark, and a full meter locks on and returns
## the hero to the floor's entry point. The sandbox hospital has none of it.

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const CHAPTER = preload("res://scripts/levels/hospital/hospital_chapter.gd")
const LIGHTING = preload("res://scripts/levels/interior_lighting.gd")
const HOSPITAL := "res://scenes/underground_hospital.tscn"

var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var hospital: Node2D
var story: Node
var _finished := false


func _initialize() -> void:
	create_timer(120.0, true).timeout.connect(func() -> void:
		check(false, "Light sense completes before the deadline")
		finish()
	)
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)


func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func tap(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(2)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(3)


func close_day_opening() -> void:
	# This suite measures the exposure meter after the actual first-arrival reading releases the hero.
	for _tick in range(180):
		if hospital.interactions.dialogue_active:
			break
		await frames(1)
	check(hospital.interactions.dialogue_active, "the first clinic arrival opens its story reading")
	for _page in range(30):
		if not hospital.interactions.dialogue_active and not hospital.chapter.busy:
			break
		if hospital.interactions.dialogue_active:
			await tap(KEY_E)
		else:
			await frames(1)
	await frames(2)
	check(story.has_flag("sequence:hospital_opening") and not hospital.chapter.busy and not hospital.player.is_frozen(),
		"reading the day arrival releases the hero before exposure is measured")


func open_hospital() -> void:
	if is_instance_valid(hospital):
		hospital.queue_free()
		await frames(2)
	hospital = load(HOSPITAL).instantiate()
	root.add_child(hospital)
	current_scene = hospital
	await frames(6)


func sources() -> Array:
	return hospital.lighting.get("_sources")


func source_rect(entry: Dictionary) -> Rect2:
	return Rect2(entry["reach"])


func only(entry_id: String) -> void:
	for entry in sources():
		hospital.lighting.set_source_power(String(entry["id"]), String(entry["id"]) == entry_id)


func all_on() -> void:
	for entry in sources():
		hospital.lighting.set_source_power(String(entry["id"]), true)


## A floor point near the source inside its zone, and the nearest point across the zone's wall at the same x.
func inside_point(entry: Dictionary) -> Vector2:
	var light: PointLight2D = entry["light"]
	var zone := source_rect(entry)
	return light.global_position.clamp(zone.position + Vector2(2, 2), zone.end - Vector2(2, 2))


func verify_floor(floor_id: int) -> void:
	hospital.floor_id = floor_id
	hospital.activate_view(0)
	await frames(4)
	var zones: Array = hospital.layout.get("light_zones", [])
	check(zones.size() == 4, "floor %d: four light zones (corridor and three rooms)" % floor_id)
	for entry in sources():
		var id := String(entry["id"])
		var light: PointLight2D = entry["light"]
		var zone := source_rect(entry)
		var named := false
		for item: Dictionary in zones:
			named = named or Rect2(item["rect"][0], item["rect"][1], item["rect"][2], item["rect"][3]) == zone
		check(named, "floor %d: %s lights exactly one room or corridor" % [floor_id, id])
		only(id)
		var near := inside_point(entry)
		check(hospital.lighting.light_level(near) >= CHAPTER.LIT_THRESHOLD, "floor %d: standing by %s is lit" % [floor_id, id])
		# Across the wall: straight up or down out of the zone at the same x.
		var above := Vector2(near.x, zone.position.y - 12.0)
		var below := Vector2(near.x, zone.end.y + 12.0)
		check(hospital.lighting.light_level(above) == 0.0 and hospital.lighting.light_level(below) == 0.0,
			"floor %d: %s does not light through its walls" % [floor_id, id])
		var far := light.global_position + Vector2(float(entry["radius"]) + 2.0, 0.0)
		check(hospital.lighting.light_level(far) == 0.0, "floor %d: %s ends at its radius" % [floor_id, id])
		# The picture agrees: texels outside the zone are black, texels inside follow the same bands.
		var image := light.texture.get_image()
		var radius := image.get_width() * 0.5
		var agree := true
		var outside_black := true
		for y in range(0, image.get_height(), 3):
			for x in range(0, image.get_width(), 3):
				var world := light.global_position + Vector2(x + 0.5 - radius, y + 0.5 - radius)
				var texel := image.get_pixel(x, y).r
				if not zone.has_point(world):
					outside_black = outside_black and texel == 0.0
					continue
				var expected := LIGHTING.band(Vector2(x + 0.5 - radius, y + 0.5 - radius).length() / radius)
				agree = agree and absf(texel - expected) < 0.01
				var level: float = hospital.lighting.light_level(world)
				agree = agree and absf(level - float(entry["energy"]) * expected) < 0.02
		check(outside_black, "floor %d: %s texture is black outside its zone" % [floor_id, id])
		check(agree, "floor %d: %s gameplay light equals its drawn bands" % [floor_id, id])
	all_on()


func verify_breaker() -> void:
	hospital.floor_id = 2
	hospital.activate_view(0)
	await frames(4)
	var corridor := [Vector2(111, 170), Vector2(246, 170), Vector2(372, 170), Vector2(508, 170)]
	for point in corridor:
		check(hospital.lighting.light_level(point) >= CHAPTER.LIT_THRESHOLD, "powered floor-2 corridor is lit at " + str(point))
	var covers: Array = hospital.world.find_children("PoolOff_*", "Sprite2D", true, false)
	check(covers.size() == 4 and covers.all(func(cover: Sprite2D) -> bool: return not cover.visible), "the four painted lamp pools show while powered")
	hospital.interactions.power_states["clinical"] = false
	await frames(3)
	for point in corridor:
		check(hospital.lighting.light_level(point) == 0.0, "the cut breaker darkens the floor-2 corridor at " + str(point))
	check(covers.all(func(cover: Sprite2D) -> bool: return cover.visible and cover.texture != null), "with the breaker cut the painted pools are covered too")
	check(hospital.lighting.light_level(Vector2(487, 100)) == 0.0, "the cut breaker also turns off Coburn's screen light")
	hospital.interactions.power_states["clinical"] = true
	await frames(3)


func hold_still(count: int) -> void:
	await frames(count)


func verify_exposure() -> void:
	var chapter: Node = hospital.chapter
	check(chapter != null and chapter.stealth(), "the day job is a stealth step on the top-down floor")
	hospital.floor_id = 1
	hospital.activate_view(0, "entry")
	await frames(4)
	var checkpoint: Vector2 = chapter.checkpoint
	check(checkpoint.distance_to(Vector2(108, 174)) < 1.0, "arriving on floor 1 sets the entry room as the checkpoint")
	check(not chapter.in_light and hospital.lighting.light_level(checkpoint) < CHAPTER.LIT_THRESHOLD, "the entry room arrival is dark")
	var hud: Node = chapter.hud
	check(hud.plate.visible and hud.meter_label.text == "暴露", "the exposure meter shows during stealth")
	# Under the first corridor lamp.
	hospital.player.position = Vector2(112, 62)
	var frames_to_lock := 0
	while chapter.locks == 0 and frames_to_lock < 200:
		await frames(1)
		frames_to_lock += 1
	observations["seconds_to_lock"] = snappedf(frames_to_lock / 60.0, 0.01)
	check(chapter.locks == 1 and frames_to_lock >= 70 and frames_to_lock <= 80, "standing in lamp light locks on after about 1.25 s")
	check(hud.scan_label.visible or chapter.busy, "the scan readout reads the hero while the lock lands")
	check(chapter.overlay.shown.has("lock:微光粒子监控已锁定") and chapter.overlay.played.has("lock"), "the lock flashes its notice and sound")
	while chapter.busy:
		await frames(1)
	await frames(2)
	check(hospital.player.position.distance_to(checkpoint) < 1.0 and chapter.exposure == 0.0, "the lock returns the hero to the floor's entry point with a clean meter")
	# Drain: a short exposure falls back in the dark.
	hospital.player.position = Vector2(112, 62)
	await frames(30)
	var peak: float = chapter.exposure
	hospital.player.position = checkpoint
	await frames(60)
	check(peak > 0.35 and peak < 0.45, "half a second in light fills about 40%")
	check(absf(chapter.exposure - (peak - 0.3)) < 0.03, "a second in the dark drains 0.3")
	observations["exposure_after_drain"] = snappedf(chapter.exposure, 0.01)
	hospital.player.position = Vector2(300, 150)
	hospital.reset_view()
	await frames(2)
	check(hospital.player.position.distance_to(checkpoint) < 1.0, "R in the chapter returns to the floor's entry point, not the lit start spot")


func verify_sandbox() -> void:
	story.end_chapter()
	await open_hospital()
	check(hospital.chapter == null and hospital.get_node_or_null("HospitalChapter") == null, "the sandbox hospital has no chapter")
	check(hospital.get_node("EnvironmentUI").find_child("ExposurePlate", true, false) == null, "the sandbox hospital has no exposure meter")
	check(String(hospital._title.text).ends_with("俯视"), "the sandbox title still names the projection")


func run() -> void:
	story = STORY_STATE.ensure(self)
	# Keep the existing static-source/zone/texture and breaker assertions in the unchanged sandbox. Chapter
	# floor 2 now adds moving lights, which are covered separately by hospital_opening instead of changing
	# this suite's one-source-at-a-time picture/gameplay equivalence checks.
	await verify_sandbox()
	await verify_floor(1)
	await verify_floor(2)
	await verify_breaker()
	story.start_chapter()
	story.set_step("d1_hospital")
	await open_hospital()
	check(hospital.view_mode == 0 and hospital.floor_id == 1, "the day job opens top-down on floor 1")
	check(hospital.player.position.distance_to(Vector2(566, 78)) < 1.0, "the day job starts at the new northeast clinic arrival")
	check(hospital.chapter.chapter_hud.clock_label.text == "12:30", "the status plate carries the story clock")
	await close_day_opening()
	await verify_exposure()
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	var report := {"suite": "light_sense", "checks": checks, "failures": failures, "observations": observations,
		"status": "passed" if failures.is_empty() else "failed"}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
