extends "res://tests/test_air_dash_animation_v14.gd"
## Observe real physics steps, rather than assuming that one rendered frame equals one physics tick.
class MotionProbe extends Node:
	var player: CharacterBody2D
	var samples: Array[Dictionary] = []
	func _physics_process(_delta: float) -> void:
		samples.append({"x": player.position.x, "y": player.position.y,
			"animation": String(player.sprite.animation), "pose": player.sprite.frame,
			"dodging": player.is_dodging, "clock": player.combat_time,
			"elapsed": player._dash_elapsed, "done": player.dash_executed})


func probe() -> MotionProbe:
	var monitor := MotionProbe.new()
	monitor.player = arena.player
	monitor.process_mode = Node.PROCESS_MODE_PAUSABLE
	monitor.process_physics_priority = 1000
	arena.world.add_child(monitor)
	return monitor


func motion_check(direction: int, hz: int, airborne: bool) -> void:
	Engine.physics_ticks_per_second = hz
	await reset()
	arena.player.position = Vector2(60 if direction > 0 else 120, 80 if airborne else 160)
	await tick(4)
	var monitor := probe()
	await dash_input(direction)
	await tick(55)
	var positive: Array[float] = []
	var backwards := false
	for i in range(1, monitor.samples.size()):
		var step := direction * (float(monitor.samples[i].x) - float(monitor.samples[i-1].x))
		if step > 0.001: positive.append(step)
		if step < -0.001: backwards = true
	var label := "%s %dHz %s" % ["air" if airborne else "ground", hz, direction]
	check(arena.player.dash_executed and absf(arena.player.dash_end.x-arena.player.dash_start.x-direction*48.0)<0.1, label+": completes exactly 48px")
	check(not backwards and positive.size() >= ceili(0.18*hz)-2, label+": travels over multiple forward physics steps")
	check(not positive.is_empty() and positive.max() <= 400.0/hz+0.1, label+": no teleport-sized step")
	check(positive.size()>2 and positive[0]<positive.max()*0.75 and positive[-1]<positive.max()*0.75, label+": speed eases into and out of rush")
	check(absf(arena.player._dash_elapsed-0.18)<0.00001, label+": exact duration independent of tick rate")
	check(arena.player.collision_mask == 3, label+": restores ordinary collision after travel")
	observations[label]={"moving_steps":positive.size(),"largest_step":positive.max() if positive else 0.0,"distance":arena.player.dash_end.x-arena.player.dash_start.x}


func roll_check(direction: int, airborne: bool) -> void:
	Engine.physics_ticks_per_second = 60
	await reset()
	arena.player.position=Vector2(60 if direction>0 else 120, 80 if airborne else 160)
	await tick(4)
	arena.player.facing="right" if direction>0 else "left"
	var target := target_at(arena.player.position+Vector2(direction*24,0))
	var monitor := probe()
	var start: Vector2 = arena.player.position
	await tap(KEY_SHIFT)
	await tick(20)
	var poses: Dictionary = {}
	var correct_clip := true
	for sample in monitor.samples:
		if String(sample.animation).begins_with("roll_"):
			correct_clip = correct_clip and sample.animation == "roll_"+arena.player.facing
			poses[int(sample.pose)] = true
	var label := "roll %s %s"%["air" if airborne else "ground",direction]
	check(correct_clip and poses.size()==16 and poses.has(7) and poses.has(15),label+": authored tuck, inversion and recovery are displayed")
	var active_steps := 1
	var largest_step := 0.0
	for i in range(1, monitor.samples.size()):
		if monitor.samples[i].dodging: active_steps += 1
		largest_step = maxf(largest_step, absf(float(monitor.samples[i].x)-float(monitor.samples[i-1].x)))
	check(absf(active_steps/60.0-0.30)<0.017,label+": slower roll lasts about 0.30 seconds")
	check(largest_step<=2.01,label+": roll moves at the reduced 120px/s speed")
	check(absf(arena.player.dash_end.x-start.x-direction*36.0)<0.1,label+": preserves 36px evade distance")
	check(target.hp==30 and arena.hits==0,label+": roll never becomes a weapon attack")
	check(not arena.player.is_dodging and arena.player.body_shape.shape.size==Vector2(12,26),label+": restores body after roll")
	observations[label]={"poses_seen":poses.keys(),"distance":arena.player.dash_end.x-start.x,"duration_seconds":active_steps/60.0,"largest_step":largest_step}


func paused_rush_check() -> void:
	await reset()
	arena.player.position=Vector2(60,160)
	var victim:=target_at(Vector2(84,160))
	await tick(3)
	await dash_input(1)
	for _i in range(50):
		if arena.player._dash_elapsed>0: break
		await tick()
	# A contact pause freezes the continuous rush without changing its remaining distance.
	arena.session._on_impact(&"light",Vector2.RIGHT)
	check(paused and arena.player._dash_elapsed>0 and not arena.player.dash_executed,"an external world hit-stop freezes an unfinished rush")
	var point:Vector2=arena.player.position
	var elapsed:float=arena.player._dash_elapsed
	var pose:int=arena.player.sprite.frame
	await tick()
	check(paused and arena.player.position==point and arena.player._dash_elapsed==elapsed and arena.player.sprite.frame==pose,"hit-stop freezes position, rush clock and pose together")
	await tick(60)
	check(victim.hp==29 and arena.hits==1 and arena.completed_stop_requests==[2],"overlapping swept steps hit once and coalesce with an existing contact pause")
	check(arena.player.dash_executed and absf(arena.player.dash_end.x-arena.player.dash_start.x-48.0)<0.1,"rush resumes its remaining distance after hit-stop")


func cancel_check() -> void:
	await reset()
	arena.player.position=Vector2(60,80)
	await tick(3)
	await dash_input(1)
	for _i in range(30):
		if arena.player._dash_elapsed>0.0: break
		await tick()
	var point:Vector2=arena.player.position
	key(KEY_S,true)
	await tick(3)
	key(KEY_S,false)
	check(arena.player.special_kind=="dive_slash" and absf(arena.player.position.x-point.x)<0.1,"S cancels an airborne rush without a delayed horizontal teleport")
	await tick(40)
	check(arena.player.is_on_floor() and arena.player.collision_mask==3,"cancelled rush and dive restore floor and enemy collision")


func falling_target_check() -> void:
	await reset()
	arena.player.position=Vector2(60,80)
	var falling:=target_at(Vector2(116,80))
	falling._air_hold_left=0.0
	falling.velocity.y=180.0
	await tick(3)
	await dash_input(1)
	await tick(40)
	check(falling.hp==30 and arena.hits==0,"a target that falls out before physical contact is not hit at its old position")
	check(arena.player.dash_executed and absf(arena.player.dash_end.x-arena.player.dash_start.x-48.0)<0.1,"missing a falling target never changes the rush distance")


func run_tests() -> void:
	CONTROLS.install(false)
	arena=MAIN.instantiate()
	root.add_child(arena)
	for hz in [30,60,120]:
		for direction in [-1,1]: await motion_check(direction,hz,false)
	Engine.physics_ticks_per_second=60
	for direction in [-1,1]:
		await motion_check(direction,60,true)
		await roll_check(direction,false)
		await roll_check(direction,true)
	await paused_rush_check()
	await cancel_check()
	await falling_target_check()
	var report={"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations}
	var file:=FileAccess.open("res://evidence/roll_thrust_motion_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print(JSON.stringify(report))
	arena.queue_free()
	await tick(6)
	quit(0 if failures.is_empty() else 1)
