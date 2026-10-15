extends SceneTree
## Real-GPU capture of the night-street prototype: stills plus every second frame of a scripted run
## (walk, beam exposure until marked, ground combo on a hover drone, jump, air dash).
## Run windowed: godot --path game --script res://tests/recorders/record_night_street_proto.gd
## Output: res://evidence/night_street_proto/ (stills and frames/NNNN.png; tools/art_qa/compose_night_street_gif.py makes the GIF).

const SCENE = preload("res://scenes/night_street_proto.tscn")
const OUTPUT := "res://evidence/night_street_proto/"
var street: Node2D
var recording := false
var frame_number := 0
var physics_count := 0
var report: Dictionary = {"stills": [], "max_exposure": 0.0, "marked_seen": false, "hits": 0, "hit_stops": 0}


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(2))
	call_deferred("run")


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(160, 90)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tick(count := 1) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame
		physics_count += 1
		report["max_exposure"] = maxf(report["max_exposure"], street.exposure)
		report["marked_seen"] = report["marked_seen"] or street.marked
		if recording and physics_count % 2 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + "frames/%04d.png" % frame_number)
			frame_number += 1


func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(OUTPUT + name + ".png")
	report["stills"].append(name)


func attack() -> void:
	mouse(true)
	await tick()
	mouse(false)
	await tick()


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "frames"))
	street = SCENE.instantiate()
	root.add_child(street)
	current_scene = street
	var player: CharacterBody2D = street.player
	player.hit_resolved.connect(func(_t: Node, _d: int, _c: bool, _k: String) -> void: report["hits"] += 1)
	player.normal_contact_stop.connect(func(_d: Vector2) -> void: report["hit_stops"] += 1)
	player.critical_hit.connect(func(_t: Node, _d: int, _v: Vector2) -> void: report["hit_stops"] += 1)
	street.drone.position.x = 200.0
	await tick(30)
	await still("night_street_overview")
	recording = true
	# walk, then run, to the noodle kiosk (magenta back light)
	key(KEY_D, true)
	await tick(70)
	key(KEY_CAPSLOCK, true)
	await tick(50)
	key(KEY_CAPSLOCK, false)
	key(KEY_D, false)
	await tick(12)
	await still("night_street_kiosk_rim")
	# stand in the patrol cone until the drone marks the player
	for _index in range(260):
		if street.marked:
			break
		street.drone.position.x = player.global_position.x
		await tick()
	await tick(20)
	await still("night_street_marked")
	# walk out of the light to the first hover drone and run the ground combo
	street.drone.position.x = 860.0
	key(KEY_D, true)
	for _index in range(120):
		if player.global_position.x >= 300.0:
			break
		await tick()
	key(KEY_D, false)
	await tick(6)
	for _stage in range(3):
		await attack()
		await tick(9)
	await still("night_street_combo")
	await tick(30)
	# jump, air combo and air dash towards the second drone
	key(KEY_SPACE, true)
	await tick(2)
	key(KEY_SPACE, false)
	await tick(10)
	await attack()
	await tick(12)
	key(KEY_D, true)
	key(KEY_SHIFT, true)
	await tick()
	key(KEY_SHIFT, false)
	await tick()
	key(KEY_D, false)
	await tick(8)
	await still("night_street_air_dash")
	await tick(50)
	recording = false
	report["frames"] = frame_number
	# A/B: the same moment with the original hero colours (F9)
	key(KEY_F9, true)
	await tick()
	key(KEY_F9, false)
	await tick(2)
	await still("night_street_original_palette")
	key(KEY_F9, true)
	await tick()
	key(KEY_F9, false)
	await tick(2)
	await still("night_street_cyber_palette")
	report["player_x"] = player.global_position.x
	report["glow_enabled"] = (street.get_node("Glow") as WorldEnvironment).environment.glow_enabled
	report["renderer"] = RenderingServer.get_current_rendering_method()
	var file := FileAccess.open(OUTPUT + "capture_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	quit(0)
