extends "res://tests/test_air_dash_animation_v14.gd"
## The hit-impact prototype (scripts/core/impact_burst.gd) in the combat fixture: on by default and switched by a real
## F10 (unless an action is bound to F10); a full charge's release throws one sword-qi crescent that speeds up, grows,
## keeps flying through a hit-stop and breaks out of the screen edge, while light swings and top-down throw none; a
## critical, heavy or killing contact cuts the frozen frame from its second frame and the cut's split ends with the
## freeze, a light one does not; the prototype's layers stay out of the freeze's photograph and its shift; the
## tremor shakes the camera in both axes within impact v2's bounds and returns, and switching off restores the
## plain recoil; effects keep to their budgets.

const BURST = preload("res://scripts/core/impact_burst.gd")
var camera: Camera2D
var burst: Node


func stage(health := 40) -> CharacterBody2D:
	await reset()
	BURST.enabled = true
	burst = arena.session.impact_burst
	arena.player.position = Vector2(60, 160)
	arena.player.facing = "right"
	arena.player.attack_direction = Vector2.RIGHT
	camera = Camera2D.new()
	camera.position = Vector2(160, 90)
	camera.offset = Vector2(2, -1)
	arena.world.add_child(camera)
	camera.make_current()
	var enemy := target_at(Vector2(98, 160), health)
	await tick(3)
	return enemy


## Waits about `seconds` of game time, whatever the refresh rate.
func wait_seconds(seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		await tick()
		waited += root.get_process_delta_time()


func wait_free(limit := 600) -> void:
	for _index in range(limit):
		if not arena.player.is_attacking and not paused and not arena.player.is_charging:
			return
		await tick()


func toggle() -> void:
	await stage()
	check(BURST.enabled and burst != null and burst.get_parent() == arena.session, "every scene's session carries the prototype, on by default")
	await tap(KEY_F10)
	check(not BURST.enabled and burst.toast.visible and burst.toast_label.text.contains("关"), "F10 switches it off and says so")
	await tap(KEY_F10)
	check(BURST.enabled and burst.toast_label.text.contains("开"), "F10 again switches it back on")
	var saved: Dictionary = CONTROLS.current.duplicate()
	CONTROLS.current["reset_arena"] = KEY_F10
	await tap(KEY_F10)
	check(BURST.enabled, "an action bound to F10 keeps the key; the prototype stays as it was")
	CONTROLS.current = saved


func sword_qi() -> void:
	await stage()
	var thrown: int = burst.waves_thrown
	await attack()
	await wait_free()
	check(burst.waves_thrown == thrown, "a light swing throws no sword qi")
	# A full charge: hold past 0.55 s, release.
	mouse(true)
	await wait_seconds(0.7)
	mouse(false)
	var released := false
	for _index in range(120):
		if burst.waves_thrown > thrown:
			released = true
			break
		await tick()
	check(released and arena.player.move_id == &"heavy_slash", "the charged draw's release throws one crescent of sword qi")
	if not released:
		return
	var wave: Dictionary = burst.waves[-1]
	var first: Vector2 = burst._wave_center(wave)
	var first_radius: float = burst._wave_radius(wave)
	check(first.x > arena.player.global_position.x and absf(first.y - (arena.player.global_position.y + burst.QI_HEIGHT)) < 0.01,
		"it leaves the blade forward at chest height")
	var steps: Array[float] = []
	var previous := first
	for _index in range(6):
		await wait_seconds(1.0 / 60.0)
		if burst.waves.is_empty():
			break
		var at: Vector2 = burst._wave_center(burst.waves[-1])
		steps.append(at.x - previous.x)
		previous = at
	check(steps.size() >= 4 and steps[-1] > steps[0] and steps.all(func(step: float) -> bool: return step > 0.0),
		"it flies forward and speeds up: " + str(steps))
	check(not burst.waves.is_empty() and burst._wave_radius(burst.waves[-1]) > first_radius * 1.5, "it swells as it goes, as if coming at the viewer")
	for _index in range(200):
		if burst.waves.is_empty():
			break
		await tick()
	check(burst.waves.is_empty() and burst.tears >= 1, "it leaves through the screen edge and tears it")
	await wait_free()
	# Through a freeze: a heavy hit-stop pauses the world; the qi keeps flying.
	burst._on_swing(&"rush_cleave")
	var age: float = burst.waves[-1]["age"]
	arena.session._on_impact(&"heavy", Vector2.RIGHT)
	await tick(3)
	check(paused and float(burst.waves[-1]["age"]) > age, "the sword qi keeps flying while the hit-stop holds the world")
	await wait_free()
	# Top-down throws none.
	arena.player.view_mode = 0
	var before: int = burst.waves_thrown
	burst._on_swing(&"heavy_slash")
	check(burst.waves_thrown == before, "top-down swings throw no sword qi")
	arena.player.view_mode = 1
	for _index in range(8):
		burst._on_swing(&"heavy_slash")
	check(burst.waves.size() <= burst.MAX_WAVES, "at most three crescents fly at once")
	for _index in range(4):
		burst._tear(Vector2(319, 90), Vector2.RIGHT, 30)
	check(burst.splinters.size() <= burst.MAX_SPLINTERS, "splinters keep to their budget")


func screen_cut() -> void:
	var enemy := await stage(40)
	var hidden_on_start := [false]
	var start_check := func() -> void: hidden_on_start[0] = not burst.draw_layer.visible
	arena.session.hit_stop_started.connect(start_check)
	arena.player._start_move(&"heavy_slash")
	arena.player._resolve_hit(enemy, enemy.damage_point())
	check(not burst.last_strike.is_empty() and Vector2(burst.last_strike["point"]).distance_to(enemy.damage_point()) < 30.0,
		"the hero's contact reports where it landed")
	check(hidden_on_start[0], "the prototype's layer hides for the frame the freeze photographs")
	await tick(2)
	check(not burst.cut.is_empty() and burst.split_rect.visible and burst.draw_layer.visible, "a heavy blow cuts the frozen frame from its second frame")
	check(float(burst.split_material.get_shader_parameter("strength")) == 1.0, "the two halves slide apart along the cut")
	var origin: Vector2 = burst.cut["origin"]
	var ends: Array[Vector2] = burst._edge_points(origin, burst.cut["axis"])
	check(ends.size() == 2 and ends.all(func(point: Vector2) -> bool: return point.x <= 0.5 or point.x >= 318.5 or point.y <= 0.5 or point.y >= 178.5),
		"the cut runs out past the screen at both ends: " + str(ends))
	var layer_offsets_steady := true
	for _index in range(100):
		layer_offsets_steady = layer_offsets_steady and burst.draw_layer.offset == Vector2.ZERO and burst.split_layer.offset == Vector2.ZERO
		if not paused:
			break
		await tick()
	check(layer_offsets_steady, "the freeze's shake does not drag the prototype's layers")
	await tick(1)
	check(not burst.split_rect.visible and float(burst.split_material.get_shader_parameter("strength")) == 0.0, "the split closes when the freeze ends")
	await wait_seconds(burst.CUT_FADE + 0.05)
	check(burst.cut.is_empty(), "the ink cut fades out shortly after")
	arena.session.hit_stop_started.disconnect(start_check)
	await wait_free()
	# Light contact: no cut.
	var cuts: int = burst.cuts_made
	arena.player._start_move(&"attack1")
	arena.player.stage_is_critical = false
	arena.player._resolve_hit(enemy, enemy.damage_point())
	await tick(4)
	check(burst.cuts_made == cuts and burst.cut.is_empty(), "a light contact does not cut the screen")
	await wait_free()
	# Critical: cut.
	arena.player._start_move(&"attack3")
	arena.player.stage_is_critical = true
	arena.player._resolve_hit(enemy, enemy.damage_point())
	await tick(3)
	check(burst.cuts_made == cuts + 1, "a critical contact cuts the screen")
	await wait_free()
	# Off: nothing.
	BURST.enabled = false
	cuts = burst.cuts_made
	var thrown: int = burst.waves_thrown
	burst._on_swing(&"heavy_slash")
	arena.player._start_move(&"heavy_slash")
	arena.player._resolve_hit(enemy, enemy.damage_point())
	await tick(3)
	check(burst.cuts_made == cuts and burst.waves_thrown == thrown, "switched off it throws and cuts nothing")
	await wait_free()
	BURST.enabled = true


func tremor() -> void:
	await stage()
	for weight in [&"tick", &"light", &"critical", &"heavy", &"kill"]:
		var rest: Vector2 = camera.offset
		var seen: Dictionary = {}
		arena.session._on_impact(weight, Vector2.RIGHT)
		var waited := 0.0
		while waited < 0.6:
			await tick()
			waited += root.get_process_delta_time()
			seen[camera.offset] = true
		var within: bool = seen.keys().all(func(point: Vector2) -> bool: return absf(point.x - rest.x) <= 3.0 and absf(point.y - rest.y) <= 1.0)
		var both_ways := seen.keys().any(func(point: Vector2) -> bool: return point.x < rest.x) and seen.keys().any(func(point: Vector2) -> bool: return point.x > rest.x)
		check(within and seen.has(rest) and camera.offset == rest, String(weight) + ": the tremor stays within 3 px across, 1 down, and returns")
		check(both_ways, String(weight) + ": it shakes both ways, not just a recoil")
		if weight in [&"critical", &"heavy", &"kill"]:
			check(seen.keys().any(func(point: Vector2) -> bool: return point.y != rest.y), String(weight) + ": strong blows also shake up and down")
	BURST.enabled = false
	var plain: Dictionary = {}
	arena.session._on_impact(&"critical", Vector2.RIGHT)
	var plain_waited := 0.0
	while plain_waited < 0.6:
		await tick()
		plain_waited += root.get_process_delta_time()
		plain[camera.offset] = true
	check(not plain.keys().any(func(point: Vector2) -> bool: return point.y != camera.offset.y), "switched off, a critical has impact v2's level recoil again")
	BURST.enabled = true


func run_tests() -> void:
	CONTROLS.install(false)
	arena = MAIN.instantiate()
	root.add_child(arena)
	await toggle()
	await sword_qi()
	await screen_cut()
	await tremor()
	BURST.enabled = true
	var report := {"suite": "impact_burst", "status": "passed" if failures.is_empty() else "failed", "checks": checks,
		"failures": failures, "observations": observations}
	print(JSON.stringify(report))
	arena.queue_free()
	await tick(6)
	quit(0 if failures.is_empty() else 1)
