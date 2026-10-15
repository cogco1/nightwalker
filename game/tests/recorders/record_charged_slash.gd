extends SceneTree
## Real-GPU capture of light vs heavy attacks in the side-view combat fixture (it has training targets;
## the shipped safe house and hospital have none): a tapped three-hit light chain, then hold, charge,
## release into the heavy slash. Run windowed:
##   godot --path game --fixed-fps 60 --script res://tests/recorders/record_charged_slash.gd
## Output: res://evidence/charged_slash/ (stills, frames/NNNN.png every second physics tick, capture_report.json).

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
const OUTPUT := "res://evidence/charged_slash/"
var arena: Node2D
var frame_number := 0
var physics_count := 0
var report: Dictionary = {"stills": []}


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
	call_deferred("run")


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
		if physics_count % 2 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + "frames/%04d.png" % frame_number)
			frame_number += 1


func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + name + ".png")
	report["stills"].append(name)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "frames"))
	arena = MAIN.instantiate()
	root.add_child(arena)
	current_scene = arena
	arena.build_arena(1)
	var player: CharacterBody2D = arena.player
	player.position = Vector2(70, 160)
	player.critical_roll_override = 0.99
	arena.targets[0].position = Vector2(112, 160)
	arena.targets[0].max_hp = 30
	arena.targets[0].hp = 30
	for index in range(1, arena.targets.size()):
		arena.targets[index].position = Vector2(290, 160)
	await tick(20)
	# light: three taps
	for _stage in range(3):
		mouse(true)
		await tick(2)
		mouse(false)
		for _index in range(40):
			if player.sprite.frame >= 10 or not player.is_attacking:
				break
			await tick()
	for _index in range(60):
		if not player.is_attacking:
			break
		await tick()
	report["hp_after_light"] = arena.targets[0].hp
	await tick(24)
	# heavy: hold through the swing into the charge, wait until full, release
	mouse(true)
	for _index in range(60):
		if player.is_charging:
			break
		await tick()
	await tick(12)
	await still("charging")
	for _index in range(60):
		if player.charge_time >= player.CHARGE_FULL_SECONDS:
			break
		await tick()
	await tick(6)
	await still("charge_full")
	mouse(false)
	for _index in range(30):
		if player.is_attacking and player.sprite.frame >= 7:
			break
		await tick()
	await still("heavy_slash")
	for _index in range(80):
		if not player.is_attacking:
			break
		await tick()
	await tick(30)
	report["hp_after_heavy"] = arena.targets[0].hp
	report["frames"] = frame_number
	report["stops"] = arena.completed_stop_requests
	var file := FileAccess.open(OUTPUT + "capture_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	quit(0)
