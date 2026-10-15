extends "res://tests/support/isolated_suite.gd"
## Real-GPU capture of enemy attacks and the hero's reactions: hospital side view, one attack drone (the
## combat_lab fixture) hovering in front of the hero. Five lunges: standing still (HIT), a dash 0.26 s early
## (EVADE), a dash 0.14 s before the hit window (PERFECT), a jump over it (EVADE), and a perfect dodge followed by the
## counter in the slow motion. Run windowed:
##   godot --path game --fixed-fps 60 --script res://tests/recorders/record_enemy_attack.gd
## Output: res://evidence/enemy_attack/ (stills, frames/NNNN.png every second physics tick, capture_report.json with
## the sound timeline and results). tools/art_qa/compose_combat_capture.py makes the MP4.

const HOSPITAL = preload("res://scenes/underground_hospital.tscn")
const DRONE = preload("res://tests/fixtures/attack_drone.gd")
const L := MOUSE_BUTTON_LEFT
const OUTPUT := "res://evidence/enemy_attack/"
# name, action, telegraph seconds at which to act
const CASES := [["stand", "", 0.0], ["early_dash", "dash", 0.30], ["perfect_dash", "dash", 0.42], ["jump", "jump", 0.31],
	["counter", "counter", 0.42]]
var hospital: Node2D
var feedback: Node
var player: CharacterBody2D
var drone: CharacterBody2D
var frame_number := 0
var physics_count := 0
var _sounds_seen := 0
var report: Dictionary = {"stills": [], "sounds": [], "cases": []}


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
	event.button_index = L
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


func wait_for(condition: Callable, limit: int) -> bool:
	for _index in range(limit):
		if condition.call():
			return true
		await tick()
	return condition.call()


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
	player = hospital.player
	player.facing = "right"
	player.show_idle()
	var base := player.global_position
	var results: Array[int] = []
	player.attack_received.connect(func(result: int, _attack: Dictionary) -> void: results.append(result))
	for entry in CASES:
		hospital.get_node("GameSession").end_slowmo()
		player.position = base
		player.velocity = Vector2.ZERO
		player.facing = "right"
		player.show_idle()
		drone = DRONE.new()
		drone.position = base + Vector2(40, -13)
		hospital.world.add_child(drone)
		drone.attacker.bind_target(player)
		results.clear()
		var attacker: Node = drone.attacker
		await wait_for(func() -> bool: return attacker.phase == attacker.Phase.TELEGRAPH, 20)
		await tick(12)
		await still(entry[0] + "_telegraph")
		if entry[1] != "":
			await wait_for(func() -> bool: return attacker.phase_time >= entry[2] or attacker.phase != attacker.Phase.TELEGRAPH, 60)
			var code := KEY_SPACE if entry[1] == "jump" else KEY_SHIFT
			key(code, true)
			await tick(2)
			key(code, false)
		await wait_for(func() -> bool: return not results.is_empty(), 60)
		await still(entry[0] + "_result")
		if entry[1] == "counter":
			# slow motion: let it read for a moment, then counter
			await tick(16)
			await still("counter_slowmo")
			mouse(true)
			await tick(2)
			mouse(false)
			await wait_for(func() -> bool: return hospital.get_node("GameSession").hit_stop_active, 40)
			await tick(1)
			await still("counter_hit")
			report["counter_damage"] = drone.max_hp - drone.hp
		await wait_for(func() -> bool: return player.state == player.State.FREE and player.is_on_floor(), 120)
		await tick(40)
		report["cases"].append({"name": entry[0], "result": ["HIT", "EVADE", "PERFECT"][results[0]] if not results.is_empty() else "none"})
		drone.queue_free()
		await tick(10)
	report["frames"] = frame_number
	report["fps"] = 30
	var file := FileAccess.open(OUTPUT + "capture_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	quit(0)
