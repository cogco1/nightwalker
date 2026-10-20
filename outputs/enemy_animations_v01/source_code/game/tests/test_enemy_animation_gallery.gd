extends "res://tests/support/isolated_suite.gd"
## Focused checks for the standalone enemy art gallery; unrelated chapter logic is not exercised.

const SCENE = preload("res://scenes/enemy_animation_gallery.tscn")
const OUTPUT := "res://evidence/enemy_animation_gallery/"
var checks := 0
var failures: Array[String] = []
var scene: Node2D


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func run() -> void:
	scene = SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	check(scene.ready_for_test, "The standalone gallery loads its final art manifest")
	if not scene.ready_for_test:
		finish()
		return
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/boot.tscn", "The original game entry remains unchanged")
	check(scene.units.size() == 8, "Eight selected enemy variants are delivered")
	check(Vector2i(int(scene.manifest.cell_size[0]), int(scene.manifest.cell_size[1])) == Vector2i(96, 64)
		and Vector2i(int(scene.manifest.foot_anchor[0]), int(scene.manifest.foot_anchor[1])) == Vector2i(48, 57), "All poses use the same native cell and fixed floor anchor")
	check(scene.scale == Vector2.ONE and scene.actor.scale == Vector2.ONE and scene.sprite.scale == Vector2.ONE, "The viewer never scales character sprites")
	check(root.content_scale_size == Vector2i(320, 180) and root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "The viewer retains a 320×180 nearest-neighbor integer viewport")
	var frame_total := 0
	var action_total := 0
	var expected := ["laser_drone_B", "sniper_B", "rifle_guard_A", "rifle_guard_C", "shield_guard_B", "blade_assault_C", "breacher_A", "tether_guard_B"]
	for unit_index in range(scene.units.size()):
		var unit: Dictionary = scene.units[unit_index]
		check(unit.unit == expected[unit_index], "The chosen variant is preserved: " + expected[unit_index])
		check(scene.select_unit(unit_index), "The unit's SpriteFrames loads: " + unit.unit)
		var frames: SpriteFrames = scene.sprite.sprite_frames
		check(frames.has_animation("right_idle") and frames.get_frame_count("right_idle") == 1, "The exact selected standing artwork is retained: " + unit.unit)
		for action: Dictionary in unit.actions:
			var animation := "right_" + str(action.name)
			action_total += 1
			frame_total += int(action.frames)
			check(frames.has_animation(animation) and scene.select_action(action.name), "The selected action is available: " + unit.unit + "/" + action.name)
			check(frames.get_frame_count(animation) == 8, "The action contains eight native poses: " + unit.unit + "/" + action.name)
			check(is_equal_approx(frames.get_animation_speed(animation), float(action.fps)) and frames.get_animation_loop(animation) == bool(action.loop), "Timing and looping follow the art manifest: " + unit.unit + "/" + action.name)
			for frame_index in range(frames.get_frame_count(animation)):
				var atlas := frames.get_frame_texture(animation, frame_index) as AtlasTexture
				check(atlas != null and atlas.region.size == Vector2(96, 64)
					and atlas.region.position == Vector2((frame_index % 4) * 96, (frame_index / 4) * 64), "Each frame selects its exact native atlas cell: %s/%s/%d" % [unit.unit, action.name, frame_index])
		scene.set_facing(false)
		var right_pos: Vector2 = scene.sprite.position
		scene.set_facing(true)
		check(scene.sprite.flip_h and scene.sprite.position == right_pos and right_pos == Vector2(-48, -57), "Mirroring retains the identical floor pivot: " + unit.unit)
		check(scene.actor.position == Vector2(160, 125), "Changing units starts at the same stage floor: " + unit.unit)
		scene.select_action("hover" if unit_index == 0 else "walk")
		await create_timer(0.22).timeout
		check(scene.sprite.is_playing() and scene.sprite.frame > 0, "Selecting a walk or hover action plays continuously in place: " + unit.unit)
	check(frame_total == 144 and action_total == 18, "All 18 requested actions and 144 new native frames are delivered")
	scene.select_unit(1)
	scene.select_action("idle")
	scene.trigger_attack()
	check(scene.current_action == "prone_down", "A standing sniper first lowers into prone before firing")
	scene.sprite.set_frame_and_progress(2, 0.25)
	scene.trigger_attack()
	check(scene.current_action == "prone_down" and scene.sprite.frame == 2, "Repeated fire input waits for the lowering pose instead of snapping directly to prone fire")
	scene.toggle_prone()
	check(scene.current_action == "prone_down" and scene.sprite.frame == 2, "Repeated posture input does not restart or skip a lowering transition")
	scene._on_animation_finished()
	check(scene.current_action == "prone_fire", "The sniper transitions naturally from lowering to prone fire")
	scene._on_animation_finished()
	check(scene.current_action == "prone_idle" and scene.prone, "The sniper holds a stable prone pose after firing")
	scene.toggle_prone()
	check(scene.current_action == "prone_up", "The sniper can rise using the reverse lowering sequence")
	scene._on_animation_finished()
	check(scene.current_action == "idle" and not scene.prone, "Rising returns to the exact standing artwork")
	var sniper_frames: SpriteFrames = scene.sprite.sprite_frames
	for index in range(8):
		check(sniper_frames.get_frame_texture("right_prone_up", index) == sniper_frames.get_frame_texture("right_prone_down", 7 - index), "Rising reuses the lowering artwork in reverse: %d" % index)
	for unit_index in [0, 2, 3, 4, 5, 6, 7]:
		scene.select_unit(unit_index)
		scene.trigger_attack()
		var wanted := "laser" if unit_index == 0 else ("attack" if unit_index in [5, 6] else "fire")
		check(scene.current_action == wanted, "The attack shortcut selects the correct weapon animation: " + str(unit_index))
		scene._on_animation_finished()
		check(scene.current_action == ("hover" if unit_index == 0 else "idle"), "A completed attack returns to the correct resting pose: " + str(unit_index))
	scene.select_unit(2)
	key(KEY_D, true)
	await create_timer(0.13).timeout
	check(scene.actor.position.x > 160 and scene.actor.position.x == roundf(scene.actor.position.x) and scene.current_action == "walk", "D moves the native sprite along the stage on integer coordinates")
	key(KEY_D, false)
	key(KEY_A, true)
	await create_timer(0.13).timeout
	check(scene.sprite.flip_h and scene.current_action == "walk", "A walks to the left using the same mirrored native artwork")
	key(KEY_A, false)
	await process_frame
	await process_frame
	check(scene.current_action == "idle", "Releasing movement returns to the selected standing pose")
	scene.select_unit(1)
	scene.select_action("prone_idle")
	key(KEY_D, true)
	await create_timer(0.1).timeout
	check(scene.current_action == "prone_crawl" and scene.prone, "A prone sniper moves with the dedicated crawling animation")
	key(KEY_D, false)
	await process_frame
	await process_frame
	check(scene.current_action == "prone_idle", "The sniper remains prone when crawling stops")
	finish()


func finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "units": 8, "actions": 18, "native_action_frames": 144}
	var file := FileAccess.open(OUTPUT + "headless_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("ENEMY_GALLERY_TEST " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
