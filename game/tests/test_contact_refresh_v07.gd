extends SceneTree

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
var arena: Node2D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(12.0).timeout.connect(func() -> void: quit(2))
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func run() -> void:
	arena = MAIN.instantiate()
	root.add_child(arena)
	arena.build_arena(1)
	arena.player.position = Vector2(73,160)
	arena.player.critical_roll_override = 0.0
	arena.targets[0].max_hp = 12
	arena.targets[0].hp = 12
	for index in range(3,arena.targets.size()):
		arena.targets[index].position = Vector2(285+index,160)
	for _index in range(5):
		await physics_frame
	check(arena.player.request_attack(), "refresh fixture begins a standing chain")
	var second := false
	var third := false
	for _index in range(700):
		await process_frame
		if not paused and arena.player.combo_stage == 1 and arena.player.sprite.frame >= 9 and not second:
			arena.player.request_attack()
			second = true
		elif not paused and arena.player.combo_stage == 2 and arena.player.sprite.frame >= 9 and not third:
			arena.player.request_attack()
			third = true
		if arena.completed_stop_requests.size() == 3 and not arena.player.is_attacking:
			break
	check(arena.hits == 3 and arena.targets[0].hp == 7, "high-refresh chain preserves ordinary/critical damage")
	check(arena.completed_stop_requests.size() == 3, "high-refresh chain groups one pause per attack stage")
	if arena.completed_stop_requests.size() == 3:
		for index in range(3):
			var required_frames := 6 if index == 2 else 4
			var required_seconds := required_frames/60.0
			check(arena.completed_stop_requests[index] >= required_frames and arena.completed_stop_durations[index]+0.00001 >= required_seconds,
				"high-refresh pause keeps minimum frames AND visible duration, stage " + str(index+1))
	var result := {"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,
		"stop_frames":arena.completed_stop_requests,"stop_durations_seconds":arena.completed_stop_durations,
		"engine":Engine.get_version_info()["string"],"execution":"Headless, fixed 144 process frames/sec; normal 60 physics ticks/sec"}
	var file := FileAccess.open("res://evidence/contact_refresh_results_v07.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
