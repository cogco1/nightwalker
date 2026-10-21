extends "res://tests/support/isolated_suite.gd"
## Shared pursuit bounds and the drone-only retreat rush, with actual moving bodies and blast damage.
const ARENA = preload("res://scenes/drone_combat_test.tscn")
const TERRITORY = preload("res://scripts/enemies/enemy_territory.gd")
var arena: Node2D
var rate := 60
var checks := 0
var failures: Array[String] = []
var observed: Dictionary = {}

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--territory-30"):
		rate=30
	elif OS.get_cmdline_user_args().has("--territory-144"):
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

func fresh(distance := 120.0) -> void:
	arena.session.end_slowmo()
	arena._spawn()
	arena.place_player(distance)
	await frames(4)

func run() -> void:
	arena=ARENA.instantiate()
	root.add_child(arena)
	current_scene=arena
	await frames(5)
	var common := TERRITORY.new(Vector2(10,20),100.0,14.0)
	check(common.update_target(Vector2(80,20)) and not common.update_target(Vector2(111,20)),"The shared policy acquires only targets inside the fixed spawn region")
	for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2.ONE.normalized()]:
		var bounded: Vector2=common.bounded_goal(common.anchor+direction*10000.0)
		check(common.inside_body(bounded) and absf(bounded.distance_to(common.anchor)-86.0)<0.01,"The shared component clips a far goal while reserving the whole collider margin")
	check(common.return_goal()==Vector2(10,20),"The return point stays at the original spawn anchor")
	await fresh(220.0)
	arena.drone.cooldown_left=100.0
	var start: Vector2=arena.drone.position
	var previous: Vector2=start
	var maximum_step := 0.0
	var all_inside := true
	for index in range(rate*5):
		await frames(1)
		maximum_step=maxf(maximum_step,arena.drone.position.distance_to(previous))
		previous=arena.drone.position
		all_inside=all_inside and arena.drone.territory.inside_body(arena.drone.position)
	check(start.x-arena.drone.position.x>70.0,"The active drone follows the player across a larger region rather than staying on its tiny patrol")
	check(all_inside and maximum_step*rate<65.0,"Normal pursuit remains smooth and inside the shared collider boundary")
	check(not arena.drone.rushing() and not arena.drone.exploded,"Approaching a distant player is normal pursuit, not an immediate spawn-time suicide")
	observed["pursuit"]={"travel":start.x-arena.drone.position.x,"max_speed":maximum_step*rate,"radius":arena.drone.territory_radius}
	await fresh(390.0)
	await seconds(3.0)
	check(arena.drone.returning_home and arena.drone.shot_count==0 and not arena.drone.rushing(),"A player never encountered inside the territory is neither chased across the map nor suicidally targeted")
	check(arena.drone.position.distance_to(arena.drone.home_position)<12.0,"The unengaged drone remains near its spawn anchor")
	await fresh()
	await seconds(0.12)
	check(arena.drone._seen_close,"A nearby player establishes an actual encounter before retreat logic arms")
	arena.player.position.x=60.0
	check(await until(func() -> bool: return arena.drone.phase==arena.drone.Phase.RUSH_WARNING,1.2),"A sustained retreat triggers the distinct rush warning")
	check(arena.drone.hp==12 and not arena.drone.self_destructing and arena.drone.shot_count==0,"Full-health retreat suicide is separate from critical-health fuse logic and stops the cannon")
	var warning: float=arena.drone.phase_time
	var at: Vector2=arena.drone.position
	arena.drone.held=true
	await seconds(0.25)
	check(arena.drone.phase_time==warning and arena.drone.position==at,"Encounter hold freezes both the rush warning and its moving body")
	arena.drone.held=false
	check(await until(func() -> bool: return arena.drone.phase==arena.drone.Phase.RUSH,1.0),"The readable warning commits to a directional charge")
	var first_speed: float=arena.drone.rush_speed
	await seconds(0.15)
	check(arena.drone.rush_speed>first_speed+25.0 and arena.drone.rush_speed<arena.drone.RUSH_MAX_SPEED,"The charge ramps up its actual speed instead of teleporting")
	var peak_speed: float=arena.drone.rush_speed
	all_inside=true
	while not arena.drone.exploded:
		await frames(1)
		all_inside=all_inside and arena.drone.territory.inside_body(arena.drone.position)
		peak_speed=maxf(peak_speed,arena.drone.rush_speed)
	check(all_inside and arena.drone.position.x>=134.0-0.01,"Even the suicide charge cannot cross the territory's physical limit")
	check(arena.vitals.hp==100,"A player who gets beyond both the leash and blast radius is safe")
	check(peak_speed>200.0 and peak_speed<=220.01,"The later charge is visibly faster than ordinary pursuit and respects its speed cap")
	observed["escape"]={"charge_peak":peak_speed,"detonation_x":arena.drone.position.x,"player_hp":arena.vitals.hp}
	await fresh()
	await seconds(0.12)
	arena.player.position.x=150.0
	check(await until(func() -> bool: return arena.drone.phase==arena.drone.Phase.RUSH_WARNING,1.3),"Retreating far inside the large territory also triggers the warning")
	check(await until(func() -> bool: return arena.drone.exploded,3.0),"The accelerating body reaches the player and detonates")
	check(arena.vitals.hp==65,"An actual collision suicide deals the same single heavy explosion hit")
	await seconds(0.65)
	check(arena.vitals.hp==65 and arena.player.position.x<140.0,"The collision blast knocks back once without repeated damage")
	await fresh()
	await seconds(0.12)
	arena.player.position.x=150.0
	await until(func() -> bool: return arena.drone.phase==arena.drone.Phase.RUSH_WARNING,1.3)
	arena.drone.take_damage(100)
	await seconds(2.5)
	check(arena.drone.dead and not arena.drone.exploded and arena.vitals.hp==100,"Finishing the warning drone cancels its queued collision suicide")
	await fresh()
	await seconds(0.12)
	arena.player.position.x=150.0
	await until(func() -> bool: return arena.drone.phase==arena.drone.Phase.RUSH_WARNING,1.3)
	var wall: StaticBody2D=arena.KIT.add_box(arena,Rect2(340,60,8,80),"RushWall")
	check(await until(func() -> bool: return arena.drone.exploded,2.0),"A solid obstacle also ends the committed charge in an explosion")
	check(arena.drone.position.x>=360.0-0.1 and arena.vitals.hp==100,"The rush collider cannot tunnel through cover or hurt a distant sheltered player")
	wall.queue_free()
	await frames(2)
	var report := {"suite":"enemy_territory_v05","passed":failures.is_empty(),"checks":checks,"physics_rate":rate,"failures":failures,"observed":observed}
	DirAccess.make_dir_recursive_absolute("res://evidence/enemy_territory_v05/")
	var file := FileAccess.open("res://evidence/enemy_territory_v05/test_%d.json"%rate,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
