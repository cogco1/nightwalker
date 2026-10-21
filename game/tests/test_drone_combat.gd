extends "res://tests/support/isolated_suite.gd"
## Physical hover, real cannon hits/push, dodge, interruptions and world collision at three rates.
const ARENA = preload("res://scenes/drone_combat_test.tscn")
var arena: Node2D
var rate := 60
var checks := 0
var failures: Array[String] = []
var observed: Dictionary = {}
var shots: Array[Dictionary] = []

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--drone-30"):
		rate=30
	elif OS.get_cmdline_user_args().has("--drone-144"):
		rate=144
	Engine.physics_ticks_per_second=rate
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func seconds(duration: float) -> void:
	await frames(ceili(duration*rate))

func until(condition: Callable, duration := 5.0) -> bool:
	for index in range(ceili(duration*rate)):
		if condition.call():
			return true
		await frames(1)
	return condition.call()

func fresh(distance := 220.0) -> void:
	arena.session.end_slowmo()
	arena.cover.collision_layer=0
	arena._spawn()
	arena.place_player(distance)
	shots.clear()
	arena.drone.fired.connect(func(bullet: Node2D) -> void:
		shots.append({"time":arena.drone.clock,"heading":bullet.heading,"damage":bullet.damage,
			"push":bullet.knockback,"trail":bullet.trail_length,"weapon":bullet.weapon})
	)
	await frames(4)

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	arena=ARENA.instantiate()
	root.add_child(arena)
	current_scene=arena
	await frames(5)
	check(arena.ready_for_test and arena.player.is_on_floor(),"The real hero and cannon drone load into a playable scene")
	check(ProjectSettings.get_setting("application/run/main_scene")=="res://scenes/boot.tscn","The chapter entry stays intact")
	check(arena.drone.sprite.scale==Vector2.ONE and arena.drone.sprite.sprite_frames.get_frame_count("right_hover")==8,
		"The chosen drone retains all eight existing native hover frames")
	check(arena.drone.body_shape.position==Vector2.ZERO and arena.drone.damage_point()==arena.drone.global_position,
		"The physical body, visible centre and damage point share one moving root")
	await fresh()
	arena.drone.active=false
	var previous: Vector2=arena.drone.position
	var previous_velocity := Vector2.ZERO
	var max_step := 0.0
	var max_speed := 0.0
	var max_accel := 0.0
	var min_x := previous.x
	var max_x := previous.x
	var min_y := previous.y
	var max_y := previous.y
	for index in range(rate*8):
		await frames(1)
		var at: Vector2=arena.drone.position
		var speed := (at-previous)*float(rate)
		max_step=maxf(max_step,at.distance_to(previous))
		max_speed=maxf(max_speed,speed.length())
		if index>2:
			max_accel=maxf(max_accel,(speed-previous_velocity).length()*float(rate))
		previous=at
		previous_velocity=speed
		min_x=minf(min_x,at.x)
		max_x=maxf(max_x,at.x)
		min_y=minf(min_y,at.y)
		max_y=maxf(max_y,at.y)
	observed.hover={"max_step":max_step,"max_speed":max_speed,"max_accel":max_accel,"horizontal_span":max_x-min_x,"vertical_span":max_y-min_y}
	check(max_step<1.3 and max_speed<25.0,"Patrol motion is continuous with no snapped hover offsets")
	check(max_accel<100.0,"Cruising smoothly accelerates and reverses rather than changing velocity instantly")
	check(max_x-min_x>30.0 and max_y-min_y>3.0,"The drone visibly drifts horizontally and breathes vertically")
	check(min_x>arena.drone.home_position.x-65.0 and max_x<arena.drone.home_position.x+65.0,"Patrol remains inside its local airspace")
	await fresh()
	check(await until(func() -> bool: return arena.drone.aiming()),"A visible player triggers an acquisition windup")
	check(arena.drone.shot_count==0,"The first cannon round is preceded by a readable aim period")
	check(await until(func() -> bool: return arena.drone.locked()),"The drone locks its final aim before firing")
	var heading: Vector2=arena.drone.shot_direction
	arena.player.position.x-=30.0
	await frames(2)
	check(arena.drone.shot_direction.is_equal_approx(heading),"Late player movement does not redirect a locked aim")
	check(await until(func() -> bool: return arena.drone.shot_count==3),"The drone releases a three-round cannon burst")
	arena.drone.active=false
	check(shots.size()==3 and shots[0].heading.is_equal_approx(shots[1].heading) and shots[1].heading.is_equal_approx(shots[2].heading),
		"All rounds of one committed burst keep the same firing direction")
	check(absf(float(shots[1].time)-float(shots[0].time)-0.22)<1.5/float(rate)
		and absf(float(shots[2].time)-float(shots[1].time)-0.22)<1.5/float(rate),"Burst spacing stays consistent across physics rates")
	check(shots[0].damage==20 and shots[0].push==22.0 and shots[0].trail>=30.0,
		"The actual fired cannon round uses the heavy caliber damage, push and bright tracer profile")
	await fresh()
	arena.player.invulnerable=true
	check(await until(func() -> bool: return arena.drone.shot_count==1),"Stage a committed burst before crossing behind")
	arena.place_player(-140.0)
	await until(func() -> bool: return arena.drone.shot_count==3)
	check(arena.drone.facing<0.0 and shots.size()==3 and shots[0].heading.is_equal_approx(shots[2].heading),
		"Crossing behind cannot make a firing drone swivel and home its burst onto the player")
	check(await until(func() -> bool: return arena.drone.facing>0.0),"After finishing the burst the drone turns and reacquires on the other side")
	var previous_attack: Vector2=arena.drone.position
	var attack_step := 0.0
	for index in range(rate*5):
		await frames(1)
		attack_step=maxf(attack_step,arena.drone.position.distance_to(previous_attack))
		previous_attack=arena.drone.position
	check(attack_step<2.0,"Recoil, recovery and station keeping stay continuous during live cannon attacks")
	observed.attack_max_step=attack_step
	await fresh(160.0)
	var start_x: float=arena.player.position.x
	check(await until(func() -> bool: return arena.drone.shot_count==1),"Stage one real cannon projectile")
	arena.drone.active=false
	check(await until(func() -> bool: return arena.vitals.hp<100),"The fired projectile actually hits and damages the hero")
	for bullet in get_nodes_in_group(&"ballistic_rounds"):
		if not bullet.spent:
			bullet.queue_free()
	await seconds(0.35)
	observed.cannon_hit={"damage":100-arena.vitals.hp,"push":start_x-arena.player.position.x}
	check(arena.vitals.hp==80,"One cannon round deals damage exactly once")
	check(arena.player.position.x<start_x-12.0,"A cannon hit visibly knocks the real hero backwards")
	await fresh(160.0)
	check(await until(func() -> bool: return arena.drone.shot_count==1),"Stage a cannon round for real-input dodge")
	arena.drone.active=false
	var bullet: Node2D=get_nodes_in_group(&"ballistic_rounds")[0]
	check(await until(func() -> bool:
		return (arena.player.hurtbox().get_center()-bullet.global_position).dot(bullet.heading)<42.0,1.0),
		"The round visibly approaches the player before the dodge")
	key(KEY_SHIFT,true)
	await frames(2)
	key(KEY_SHIFT,false)
	await seconds(0.35)
	check(arena.vitals.hp==100,"Real Shift input can dodge the incoming cannon round")
	check(arena.session.slowmo_active,"A well-timed cannon dodge opens the original perfect-dodge window")
	await fresh()
	arena.cover.collision_layer=1
	await seconds(4.0)
	check(arena.drone.shot_count==0,"Solid cover prevents acquisition and shooting through the wall")
	arena.cover.collision_layer=0
	check(await until(func() -> bool: return arena.drone.aiming()),"Clearing cover lets the drone reacquire")
	var time_before: float=arena.drone.phase_time
	arena.session.world_time_scale=0.25
	await seconds(0.4)
	var slow_advance: float=arena.drone.phase_time-time_before
	check(slow_advance>0.06 and slow_advance<0.15,"Aim advances at the same quarter-speed world clock as hovering")
	arena.session.world_time_scale=1.0
	await fresh()
	check(await until(func() -> bool: return arena.drone.shot_count==1),"Stage a live burst for encounter hold")
	arena.drone.held=true
	var body_before: Vector2=arena.drone.position
	var phase_before: float=arena.drone.phase_time
	var round: Node2D=get_nodes_in_group(&"ballistic_rounds")[0]
	var round_before: Vector2=round.position
	await seconds(0.4)
	check(arena.drone.position.is_equal_approx(body_before) and arena.drone.phase_time==phase_before,
		"Encounter hold freezes both the physical hover and burst clock")
	check(round.position.is_equal_approx(round_before) and arena.drone.shot_count==1,"Holding also freezes in-flight cannon rounds")
	arena.drone.held=false
	check(await until(func() -> bool: return arena.drone.shot_count==2),"The paused burst resumes at its original interval")
	await fresh()
	check(await until(func() -> bool: return arena.drone.shot_count==1),"Stage a burst for interruption")
	arena.drone.take_damage(1)
	arena.drone.receive_hit_reaction(Vector2.RIGHT)
	await seconds(0.45)
	check(arena.drone.shot_count==1 and arena.drone.hp==11,"A real hit cancels the remaining cannon burst")
	await fresh()
	arena.drone.active=false
	var wall: StaticBody2D=arena.KIT.add_box(arena,Rect2(420,60,8,80),"HoverWall")
	await seconds(3.0)
	check(arena.drone.position.x+12.0<=420.1,"The floating body's collider stops at solid world geometry")
	wall.queue_free()
	await frames(2)
	await fresh(55.0)
	arena.drone.active=false
	arena.player.facing="right"
	mouse(true)
	await seconds(0.65)
	mouse(false)
	check(await until(func() -> bool: return arena.drone.hp<12,1.0),"The real player's charged attack hits the metal drone")
	check(arena.drone.stun_left>0.0 and arena.drone._impulse.y<0.0,"A charged hit interrupts fire and launches the actual floating body")
	await fresh()
	check(await until(func() -> bool: return arena.drone.aiming()),"Acquire before lethal interruption")
	arena.drone.take_damage(100)
	await seconds(2.0)
	check(arena.drone.dead and arena.drone.shot_count==0 and arena.drone.collision_layer==0,"A defeated drone falls and never finishes a queued attack")
	check(arena.drone.position.y>125.0 and arena.drone.position.y<=134.2,"The wreck settles on the real floor")
	await fresh(40.0)
	arena.drone.take_damage(8)
	check(arena.drone.hp==4 and not arena.drone.self_destructing,"Health above one quarter does not start a self-destruct fuse")
	arena.drone.take_damage(1)
	arena.drone.receive_hit_reaction(Vector2.RIGHT)
	check(arena.drone.self_destructing and arena.drone.phase==arena.drone.Phase.FUSE,
		"Crossing the critical threshold starts the fuse even after the normal hit reaction")
	var blast_start: float=arena.player.position.x
	await seconds(0.30)
	check(arena.drone.shot_count==0 and not arena.drone.exploded,"The critical drone stops its cannon and gives a warning interval")
	var fuse_before: float=arena.drone.phase_time
	arena.drone.held=true
	await seconds(0.35)
	check(arena.drone.phase_time==fuse_before and not arena.drone.exploded,"Encounter hold pauses the self-destruct countdown")
	arena.drone.held=false
	check(await until(func() -> bool: return arena.drone.exploded,2.0),"After the warning the critical drone self-destructs")
	await seconds(0.35)
	observed.self_destruct={"damage":100-arena.vitals.hp,"push":blast_start-arena.player.position.x}
	check(arena.vitals.hp==65 and arena.player.position.x<blast_start-18.0,"The real blast deals one heavy hit and visibly knocks the player away")
	await seconds(0.7)
	check(arena.vitals.hp==65 and not arena.drone.sprite.visible,"An exploded drone disappears and cannot deal repeated blast damage")
	await fresh(40.0)
	arena.drone.take_damage(9)
	await seconds(0.3)
	arena.place_player(140.0)
	check(await until(func() -> bool: return arena.drone.exploded,2.0),"The fuse continues after the player leaves its danger circle")
	check(arena.vitals.hp==100,"Leaving the blast radius during the warning avoids all damage")
	await fresh(40.0)
	var blast_wall: StaticBody2D=arena.KIT.add_box(arena,Rect2(375,70,5,70),"BlastWall")
	arena.drone.take_damage(9)
	await until(func() -> bool: return arena.drone.exploded,2.0)
	check(arena.vitals.hp==100,"Solid cover blocks the explosion even inside its geometric radius")
	blast_wall.queue_free()
	await frames(2)
	await fresh(40.0)
	arena.drone.take_damage(9)
	await seconds(0.25)
	arena.drone.take_damage(3)
	await seconds(1.5)
	check(arena.drone.dead and not arena.drone.exploded and arena.vitals.hp==100,
		"Finishing the critical drone during its warning cancels self-destruction")
	await fresh(40.0)
	arena.drone.take_damage(9)
	await until(func() -> bool: return arena.drone.phase_time>=arena.drone.FUSE_SECONDS-0.16,2.0)
	key(KEY_SHIFT,true)
	await frames(2)
	key(KEY_SHIFT,false)
	check(await until(func() -> bool: return arena.drone.exploded,1.0),"A real dodge can be timed against the final fuse pulse")
	check(arena.vitals.hp==100,"The original real-input dodge protection also evades the blast")
	await fresh(140.0)
	arena.drone.active=false
	arena.drone.hp=3
	await frames(2)
	check(arena.drone.self_destructing,"A scripted low-health change automatically starts the same fuse without a demo key")
	check(await until(func() -> bool: return arena.drone.exploded,2.0),"Low health alone leads to automatic detonation")
	finish()

func finish() -> void:
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"physics_rate":rate,"observed":observed}
	DirAccess.make_dir_recursive_absolute("res://evidence/drone_combat/")
	var file := FileAccess.open("res://evidence/drone_combat/test_%d.json"%rate,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
