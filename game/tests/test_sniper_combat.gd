extends "res://tests/support/isolated_suite.gd"
## Real physics, damage, range transitions, swept ballistics, collision and native artwork.
const ARENA = preload("res://scenes/sniper_combat_test.tscn")
const ROUND = preload("res://scripts/enemies/ballistic_round.gd")
var checks := 0
var failures: Array[String] = []
var arena: Node2D
var rate := 60
var observed: Dictionary = {}
var counter_events := 0

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--sniper-144"):
		rate=144
	elif OS.get_cmdline_user_args().has("--sniper-30"):
		rate=30
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

func fresh(distance := 240.0) -> void:
	arena.session.end_slowmo()
	arena.cover.collision_layer=0
	arena._spawn()
	arena.place_player(distance)
	await frames(4)

func round_at(type: int, start: Vector2, direction := Vector2.RIGHT) -> Node2D:
	var round: Node2D=ROUND.new()
	round.setup(null,arena.player,start,direction,type)
	arena.add_child(round)
	return round

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	arena=ARENA.instantiate()
	root.add_child(arena)
	current_scene=arena
	await frames(5)
	check(arena.ready_for_test and arena.player.is_on_floor(),"The playable range loads the real hero on solid ground")
	check(arena.sniper.sprite.scale==Vector2.ONE and arena.sniper.scale==Vector2.ONE,"The enemy uses native pixels at scale one")
	check(ProjectSettings.get_setting("application/run/main_scene")=="res://scenes/boot.tscn","The chapter entry remains intact")
	await fresh()
	check(await until(func() -> bool: return arena.sniper.posture==arena.sniper.Posture.LOWER),"Far target triggers the actual lowering animation")
	var feet_y: float=arena.sniper.position.y
	var transitions: Array = []
	while arena.sniper.posture==arena.sniper.Posture.LOWER:
		transitions.append(arena.sniper.sprite.frame)
		check(absf(arena.sniper.position.y-feet_y)<0.05,"The lowering animation retains a grounded fixed foot anchor")
		await frames(1)
	check(transitions.has(0) and transitions.has(7),"Lowering plays through its first and final frames")
	check(arena.sniper.posture==arena.sniper.Posture.PRONE,"A distant target settles into prone")
	check(await until(func() -> bool: return arena.sniper.aiming()),"The prone sniper acquires the player")
	check(arena.sniper.sight_end.distance_to(arena.sniper.muzzle())>150.0,"The aiming laser visibly spans the long engagement")
	check((arena.sniper.body_shape.shape as RectangleShape2D).size.y==10.0,"Prone hit collision follows the low silhouette")
	check(await until(func() -> bool: return arena.sniper.locked()),"A readable final lock interval precedes a shot")
	var locked_heading: Vector2=arena.sniper.shot_direction
	arena.player.position.y-=20.0
	await frames(2)
	check(arena.sniper.shot_direction.is_equal_approx(locked_heading),"Moving after lock does not bend the committed shot")
	check(await until(func() -> bool: return arena.sniper.shot_count>0),"The prone animation releases an actual projectile")
	var rounds := get_nodes_in_group(&"ballistic_rounds")
	check(not rounds.is_empty(),"The long-range round exists in the scene")
	if not rounds.is_empty():
		check(rounds[0].heading.is_equal_approx(locked_heading),"The projectile travels along the locked laser direction")
		check(rounds[0].trail_length>=20.0 and rounds[0].knockback>0.0,"The sniper profile has a visible tracer and heavy impact push")
	await fresh()
	check(await until(func() -> bool: return arena.sniper.posture==arena.sniper.Posture.PRONE),"Far posture can be reproduced")
	arena.place_player(160.0)
	await seconds(0.15)
	check(arena.sniper.posture==arena.sniper.Posture.PRONE,"Distance jitter in the far hysteresis band does not cause repeated rising")
	arena.place_player(110.0)
	check(await until(func() -> bool: return arena.sniper.posture==arena.sniper.Posture.RISE),"Approaching makes the prone sniper rise")
	var before: int=arena.sniper.shot_count
	while arena.sniper.posture==arena.sniper.Posture.RISE:
		check(arena.sniper.shot_count==before,"Rising never fires a round before the standing pose is ready")
		await frames(1)
	check(await until(func() -> bool: return arena.sniper.phase==arena.sniper.Phase.AIM),"The standing enemy raises the rifle and reacquires")
	check(arena.sniper.posture==arena.sniper.Posture.STAND and arena.sniper.mode==arena.sniper.Mode.MIDDLE,"Mid range selects standing fire")
	check(await until(func() -> bool: return arena.sniper.shot_count>before),"Standing fire releases a real sniper round")
	await fresh(30.0)
	var hero_x: float=arena.player.position.x
	check(await until(func() -> bool: return arena.sniper.phase==arena.sniper.Phase.MELEE),"A close target selects a rifle-butt windup")
	check(arena.sniper.shot_count==0 and not arena.sniper.aiming(),"Close combat cancels the gun aim and laser")
	check(await until(func() -> bool: return arena.vitals.hp<100),"The close-range strike deals actual health damage")
	await seconds(0.30)
	check(arena.vitals.hp==90,"One melee swing cannot hit repeatedly during its active window")
	check(arena.player.position.x<hero_x-12.0,"Melee visibly pushes the real player away")
	observed.melee_push=hero_x-arena.player.position.x
	await fresh(30.0)
	check(await until(func() -> bool: return arena.sniper.phase==arena.sniper.Phase.MELEE),"A fresh close attacker starts a new strike")
	await seconds(arena.sniper.MELEE_WINDUP-0.16)
	key(KEY_SHIFT,true)
	await frames(2)
	key(KEY_SHIFT,false)
	await seconds(0.5)
	check(arena.vitals.hp==100,"Real Shift dodge avoids the telegraphed melee strike")
	check(arena.session.slowmo_active,"A correctly timed real dodge opens the existing perfect-counter slow motion")
	arena.player.counter_started.connect(func(_enemy: Node2D) -> void: counter_events+=1)
	var click := InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	await frames(2)
	click=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=false
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	await frames(5)
	check(counter_events==1,"A real attack click after perfect dodge executes the existing counter against the sniper")
	await fresh()
	arena.cover.collision_layer=1
	await seconds(4.0)
	check(arena.sniper.shot_count==0 and not arena.sniper.aiming(),"A solid wall prevents target acquisition and shooting")
	arena.cover.collision_layer=0
	check(await until(func() -> bool: return arena.sniper.aiming()),"Removing cover lets the enemy acquire again")
	var initial_time: float=arena.sniper.phase_time
	arena.session.world_time_scale=0.25
	await seconds(0.4)
	var slowed: float=arena.sniper.phase_time-initial_time
	check(slowed>0.06 and slowed<0.15,"Aim and native animation share the existing quarter-speed world clock")
	arena.session.world_time_scale=1.0
	arena.sniper.held=true
	await seconds(0.35)
	check(not arena.sniper.aiming() and arena.sniper.shot_count==0,"Holding the encounter clears its laser and pending shot")
	arena.sniper.held=false
	await fresh()
	arena.sniper.active=false
	var anchor: float=arena.sniper.home_position.x
	arena.sniper.knock_back(Vector2.RIGHT,200.0)
	await seconds(1.0)
	check(absf(arena.sniper.position.x-anchor)<=arena.sniper.region_radius+0.01,"Even a strong external knockback cannot leave the spawn region")
	arena.sniper.active=true
	arena.place_player(500.0)
	var out_x: float=arena.sniper.position.x
	await seconds(5.0)
	check(absf(arena.sniper.position.x-out_x)<0.1 and arena.sniper.shot_count==0,"An out-of-range player is never chased over long distances")
	await fresh(100.0)
	arena.sniper.held=true
	for type in [ROUND.Weapon.SNIPER,ROUND.Weapon.DRONE_CANNON,ROUND.Weapon.RIFLE,ROUND.Weapon.SHOTGUN]:
		await fresh(100.0)
		arena.sniper.held=true
		var start_x: float=arena.player.position.x
		var bullet: Node2D=round_at(type,arena.player.hurtbox().get_center()-Vector2(60,0))
		var expected_damage: int=bullet.damage
		check(await until(func() -> bool: return arena.vitals.hp<100,1.0),"The weapon projectile really contacts the hero: "+str(type))
		await seconds(0.35)
		var moved: float=arena.player.position.x-start_x
		observed["weapon_"+str(type)]={"push":moved,"damage":100-arena.vitals.hp}
		check(arena.vitals.hp==100-expected_damage,"Each projectile resolves damage once: "+str(type))
		if type in [ROUND.Weapon.SNIPER,ROUND.Weapon.DRONE_CANNON]:
			check(moved>10.0,"Large-caliber rounds physically push the real hero: "+str(type))
		else:
			check(absf(moved)<0.05,"Rifle and shotgun damage creates no displacement: "+str(type))
	await fresh(100.0)
	arena.sniper.held=true
	var wall: StaticBody2D=arena.KIT.add_box(arena,Rect2(arena.player.position.x-30,100,4,40),"SweepWall")
	var fast: Node2D=round_at(ROUND.Weapon.SNIPER,arena.player.hurtbox().get_center()-Vector2(80,0))
	fast.speed=10000.0
	await seconds(0.08)
	check(arena.vitals.hp==100,"A swept high-speed bullet stops at the nearer wall before reaching the player")
	wall.queue_free()
	await frames(2)
	var impact: Node2D=round_at(ROUND.Weapon.SNIPER,arena.player.hurtbox().get_center()-Vector2(80,0))
	impact.speed=10000.0
	check(await until(func() -> bool: return arena.vitals.hp<100,0.3),"Without the wall the same high-speed round cannot tunnel through the hurtbox")
	await fresh(100.0)
	check(await until(func() -> bool: return arena.sniper.aiming()),"Acquire a target for interruption testing")
	arena.sniper.receive_hit_reaction(Vector2.RIGHT)
	check(not arena.sniper.aiming() and not arena.sniper.laser.visible,"Taking a hit immediately interrupts aim and removes the laser")
	arena.sniper.take_damage(100)
	await seconds(1.0)
	check(arena.sniper.dead and arena.sniper.shot_count==0,"A defeated sniper never finishes a queued shot")
	# Native art remains transparent, nearest-neighbour and registered to a shared feet row.
	for name in ["stand_fire","melee"]:
		var texture := load("res://assets/sniper_combat_v02/"+name+".png") as Texture2D
		var image := texture.get_image()
		check(image.get_size()==Vector2i(384,128),"New motion sheets retain eight exact native cells: "+name)
		var hard_alpha := true
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var alpha := image.get_pixel(x,y).a
				if alpha!=0.0 and alpha!=1.0:
					hard_alpha=false
		check(hard_alpha,"New pixel sprites have only hard transparent edges: "+name)
	finish()

func finish() -> void:
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"physics_rate":rate,"observed":observed}
	DirAccess.make_dir_recursive_absolute("res://evidence/sniper_combat/")
	var file := FileAccess.open("res://evidence/sniper_combat/test_%d.json"%rate,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
