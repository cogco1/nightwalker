extends "res://tests/support/isolated_suite.gd"
## Windowed captures of the safehouse and both hospital views, every dialogue page, the door keypad and the
## side-view stair hint. Run before and after a level refactor and compare the PNGs pixel for pixel:
##   Godot --path game --fixed-fps 60 --script res://tests/recorders/capture_levels.gd
## Output: res://evidence/level_captures/*.png at window resolution.

const OUT := "res://evidence/level_captures/"
const WINDOW_SIZE := Vector2i(1280, 720)

var _count := 0


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(code: int) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)


func shot(name: String) -> void:
	# Comparisons need one window size; undo a maximise or resize that happened while capturing.
	if root.mode != Window.MODE_WINDOWED or root.size != WINDOW_SIZE:
		root.mode = Window.MODE_WINDOWED
		root.size = WINDOW_SIZE
		await frames(2)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_count += 1
	var path := OUT + "%02d_%s.png" % [_count, name]
	if image.is_empty() or image.save_png(path) != OK:
		push_error("Could not capture " + path)


func open_scene(path: String) -> Node:
	change_scene_to_file(path)
	await frames(30)
	return current_scene


func view(hospital: Node, mode: int, room: String, point: Vector2) -> void:
	hospital.activate_view(mode, room, point)
	await frames(10)


# Opens a dialogue with E, then captures it mid-typing, fully typed and after every further E until it closes.
func read_dialogue(owner: Node, prefix: String) -> void:
	await tap(KEY_E)
	await frames(8)
	await shot(prefix + "_typing")
	for page in range(12):
		if not bool(owner.get("dialogue_active")):
			break
		await frames(60)
		await shot(prefix + "_page%d" % page)
		await tap(KEY_E)
	await frames(4)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var home := await open_scene("res://scenes/home_601.tscn")
	await shot("home_idle")
	for item in home.layout["interactions"]:
		var id := String(item["id"])
		if id == "door":
			continue
		home.player.position = Vector2(item["anchor"][0], item["anchor"][1])
		home.player.velocity = Vector2.ZERO
		await frames(6)
		await shot("home_near_" + id)
		await read_dialogue(home, "home_" + id)
	var hospital := await open_scene("res://scenes/underground_hospital.tscn")
	await shot("hospital_top_idle")
	for item in hospital.base_layout["interactions"]:
		var id := String(item["id"])
		if id in ["exit_panel", "stairs_up", "stairs_down"]:
			continue
		hospital.floor_id = int(item.get("floor_id", 1))
		var anchor: Array = item["anchors"]["top_down"]
		await view(hospital, 0, String(item.get("room_id", "")), Vector2(anchor[0], anchor[1]))
		await shot("hospital_top_near_" + id)
		await read_dialogue(hospital.interactions, "hospital_top_" + id)
	for door in hospital.base_layout["security"]["doors"]:
		hospital.floor_id = int(door["floor_id"])
		await view(hospital, 0, "", Vector2(door["anchor"][0], door["anchor"][1]))
		hospital.player.global_position = Vector2(door["anchor"][0], door["anchor"][1])
		await frames(4)
		await shot("hospital_door_near_" + String(door["id"]))
		await tap(KEY_E)
		await frames(20)
		await shot("hospital_keypad_" + String(door["id"]))
		await tap(KEY_ESCAPE)
		await frames(6)
	hospital.floor_id = 1
	await view(hospital, 1, "entry", Vector2(110, 286))
	await shot("hospital_side_idle")
	for item in hospital.base_layout["interactions"]:
		var id := String(item["id"])
		if id in ["exit_panel", "stairs_up", "stairs_down"]:
			continue
		var anchor: Array = item["anchors"]["side_view"]
		await view(hospital, 1, String(item.get("room_id", "")), Vector2(anchor[0], anchor[1]))
		await shot("hospital_side_near_" + id)
		await read_dialogue(hospital.interactions, "hospital_side_" + id)
	await view(hospital, 1, "entry", Vector2(160, 286))
	await shot("hospital_side_stair_foot")
	await tap(KEY_W)
	await frames(10)
	await shot("hospital_side_stairs_active")
	print("PASS: captured %d level views" % _count)
	quit(0)
