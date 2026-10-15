extends SceneTree
## Real-GPU capture of light vs heavy attacks through the shipped GameSession path (hit-stop, heavy flash,
## after-shock, combat sounds): hospital side view with one fixture target dropped next to the hero.
## Run windowed:
##   godot --path game --fixed-fps 60 --script res://tests/recorders/record_charged_slash.gd
## Output: res://evidence/charged_slash/ (stills, frames/NNNN.png every second physics tick, capture_report.json
## with the sound timeline). tools/art_qa/compose_combat_capture.py turns it into an MP4 with the sounds mixed in.

const HOSPITAL = preload("res://scenes/underground_hospital.tscn")
const TARGET = preload("res://tests/fixtures/training_target.gd")
const OUTPUT := "res://evidence/charged_slash/"
var hospital: Node2D
var feedback: Node
var frame_number := 0
var physics_count := 0
var _sounds_seen := 0
var report: Dictionary = {"stills": [], "sounds": []}


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
		while _sounds_seen < feedback.played.size():
			report["sounds"].append({"sound": feedback.played[_sounds_seen], "seconds": physics_count / 60.0})
			_sounds_seen += 1
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
	hospital = HOSPITAL.instantiate()
	root.add_child(hospital)
	current_scene = hospital
	for _index in range(10):
		await physics_frame
	hospital.call("switch_view")
	for _index in range(20):
		await physics_frame
	feedback = hospital.get_node("GameSession/CombatFeedback")
	var player: CharacterBody2D = hospital.player
	player.facing = "right"
	player.call("_show_idle")
	player.critical_roll_override = 0.99
	var target := TARGET.new()
	target.side_view = true
	target.max_hp = 40
	target.position = player.global_position + Vector2(34, 0)
	hospital.world.add_child(target)
	target.hp = 40
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
	report["hp_after_light"] = target.hp
	await tick(24)
	player.position = target.global_position - Vector2(46, 0)
	await tick(10)
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
	await tick(5)
	await still("charge_full")
	mouse(false)
	for _index in range(30):
		if hospital.get_node("GameSession").hit_stop_active:
			break
		await tick()
	await tick(1)
	await still("heavy_impact")
	for _index in range(80):
		if not player.is_attacking:
			break
		await tick()
	await tick(36)
	report["hp_after_heavy"] = target.hp
	report["frames"] = frame_number
	report["fps"] = 30
	report["stops"] = hospital.get_node("GameSession").completed_stop_frames
	var file := FileAccess.open(OUTPUT + "capture_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	quit(0)
