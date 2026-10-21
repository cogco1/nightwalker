extends "res://tests/support/isolated_suite.gd"
## Real input/projectiles, dedicated perfect evasion, consumable counter, safe travel and mild hurt-camera feedback.
const ARENA = preload("res://scenes/drone_combat_test.tscn")
const ROUND = preload("res://scripts/enemies/ballistic_round.gd")
var arena: Node2D
var rate := 60
var checks := 0
var failures: Array[String] = []
var observed: Dictionary = {}
var counters := 0

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--perfect-30"):
		rate=30
	elif OS.get_cmdline_user_args().has("--perfect-144"):
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

func until(condition: Callable, duration := 3.0) -> bool:
	for index in range(ceili(duration*rate)):
		if condition.call():
			return true
		await frames(1)
	return condition.call()

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index=button
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func fresh(distance := 100.0) -> void:
	arena.session.end_slowmo()
	arena._spawn()
	arena.drone.active=false
	arena.place_player(distance)
	counters=0
	arena.player.counter_started.connect(func(_enemy: Node2D) -> void: counters+=1)
	await frames(4)

func perfect(with_source := true) -> bool:
	key(KEY_SHIFT,true)
	await frames(1)
	key(KEY_SHIFT,false)
	await frames(1)
	var round: Node2D=ROUND.new()
	round.setup(arena.drone if with_source else null,arena.player,arena.player.hurtbox().get_center()+Vector2(18,0),Vector2.LEFT,ROUND.Weapon.DRONE_CANNON)
	arena.add_child(round)
	return await until(func() -> bool: return arena.session.slowmo_active,0.5)

func click(button: MouseButton) -> void:
	mouse(button,true)
	await frames(1)
	mouse(button,false)
	await frames(2)

func run() -> void:
	arena=ARENA.instantiate()
	root.add_child(arena)
	current_scene=arena
	await frames(5)
	for face in ["left","right"]:
		var clip: String = "perfect_dodge_"+face
		check(arena.player.SIDE_FRAMES.has_animation(clip) and arena.player.SIDE_FRAMES.get_frame_count(clip)==6,
			"The perfect evade has its own six-pose clip: "+face)
		check(not arena.player.SIDE_FRAMES.get_animation_loop(clip) and arena.player.SIDE_FRAMES.get_frame_texture(clip,0)!=arena.player.SIDE_FRAMES.get_frame_texture("roll_"+face,0),
			"The successful evade uses a distinct silhouette rather than replaying the ordinary roll")
	for face in ["up","down","left","right"]:
		check(arena.player.TOP_FRAMES.has_animation("perfect_dodge_"+face),"The top-down facing also has a dedicated successful-evade clip: "+face)
	await fresh()
	key(KEY_SHIFT,true)
	await frames(1)
	key(KEY_SHIFT,false)
	await frames(2)
	check(arena.player.is_dodging and String(arena.player.sprite.animation)=="roll_right" and not arena.player.counter_ready,
		"An ordinary real-input dodge keeps its roll and grants no counter")
	await fresh()
	var start: Vector2=arena.player.position
	var shakes: int=arena.session.hurt_shake_count
	check(await perfect(),"A real Shift dodge against a real cannon round opens perfect evasion")
	check(arena.vitals.hp==100 and arena.player.counter_ready and arena.session.world_time_scale==0.25,
		"Success grants a safe 1.2-second counter window and quarter-speed world")
	check(String(arena.player.sprite.animation)=="perfect_dodge_right" and arena.player.perfect_pose_left>0.0,
		"The success event immediately changes to the exclusive low slip-step animation")
	await seconds(0.05)
	check(not arena.player.fx.afterimages.is_empty(),"The special evade leaves visible cyan afterimages")
	check(arena.session.hurt_shake_count==shakes,"A perfect evade never triggers the hurt-camera shake")
	await seconds(0.36)
	check(arena.player.position.distance_to(start)<=36.1 and not arena.player.is_dodging,
		"The special animation does not add travel or extend the physical dodge")
	check(not String(arena.player.sprite.animation).begins_with("perfect_dodge_"),"The exclusive clip returns to normal locomotion")
	for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		await fresh(70.0)
		check(await perfect(),"Stage a real perfect dodge before the mouse counter")
		await click(button)
		check(counters==1 and arena.player.move_id==&"counter_slash" and not arena.player.counter_ready,
			"Either attack button consumes exactly one counter opportunity")
		check(absf(arena.player.position.x-arena.drone.position.x)<=19.0,"A clear nearby target is reached at the controlled counter offset")
		check(await until(func() -> bool: return arena.drone.hp<12,1.0),"The counter reaches and hits the real moving drone")
		check(arena.drone.hp==9 and not arena.session.slowmo_active,"The hit deals triple damage and ends slow motion")
		observed["counter_"+str(button)]={"damage":12-arena.drone.hp,"events":counters}
	await fresh()
	check(await perfect(),"Stage the window-expiry case")
	await seconds(1.35)
	check(not arena.player.counter_ready and not arena.session.slowmo_active,"An unused counter expires with its slow-motion window")
	await click(MOUSE_BUTTON_LEFT)
	check(counters==0 and arena.player.move_id==&"attack1","After expiry a fresh click is an ordinary attack")
	await fresh()
	check(await perfect(false),"A source-free real projectile can still be perfectly evaded")
	start=arena.player.position
	await click(MOUSE_BUTTON_RIGHT)
	check(counters==1 and arena.player.move_id==&"counter_slash" and absf(arena.player.position.x-start.x)<8.0,
		"A missing source grants an empowered in-place counter without teleporting")
	await fresh()
	await perfect()
	arena.drone.take_damage(100)
	start=arena.player.position
	await click(MOUSE_BUTTON_RIGHT)
	check(counters==1 and absf(arena.player.position.x-start.x)<8.0,"A destroyed source never becomes a teleport destination")
	await fresh()
	await perfect()
	arena.drone.position.x=620.0
	start=arena.player.position
	await click(MOUSE_BUTTON_RIGHT)
	check(counters==1 and absf(arena.player.position.x-start.x)<8.0,"A source beyond 260 pixels gives an in-place counter")
	await fresh()
	await perfect()
	var wall: StaticBody2D=arena.KIT.add_box(arena,Rect2(350,55,8,85),"CounterWall")
	await frames(2)
	await click(MOUSE_BUTTON_RIGHT)
	check(arena.player.position.x<344.0 and counters==1,"The real body sweep prevents counter travel through solid cover")
	await seconds(0.3)
	check(arena.drone.hp==12,"The fallback counter cannot damage the source through that cover")
	wall.queue_free()
	await frames(2)
	await fresh()
	await perfect()
	var pose_left: float=arena.player.perfect_pose_left
	var counter_left: float=arena.player._counter_until-arena.player.combat_time
	arena.session.open_keybindings()
	await seconds(0.2)
	check(arena.player.perfect_pose_left==pose_left and arena.player._counter_until-arena.player.combat_time==counter_left,
		"Settings pause the special animation and counter window together")
	arena.session._close_keybindings(false)
	await frames(2)
	check(arena.player.perfect_pose_left<pose_left,"The dedicated pose resumes after settings close")
	await fresh()
	var rest := Vector2(3,2)
	arena.camera.offset=rest
	arena.camera.force_update_scroll()
	shakes=arena.session.hurt_shake_count
	check(arena.player.receive_attack({"direction":Vector2.LEFT,"damage":10,"knockback":0.0})==arena.player.AttackResult.HIT,
		"A real hurt event starts camera feedback")
	check(arena.session.hurt_shake_count==shakes+1 and arena.camera.offset.distance_to(rest)>0.0,
		"One accepted hit starts one camera nudge")
	var maximum: float = arena.camera.offset.distance_to(rest)
	for index in range(ceili(rate*0.2)):
		await frames(1)
		maximum=maxf(maximum,arena.camera.offset.distance_to(rest))
	check(maximum<=1.42 and arena.camera.offset==rest,"The mild nudge stays within 1.42 native pixels and restores the exact camera offset")
	arena.player.receive_attack({"direction":Vector2.RIGHT,"damage":10})
	check(arena.session.hurt_shake_count==shakes+1,"An attack rejected by hit protection cannot stack another camera shake")
	observed["camera"]={"max_offset":maximum,"restored":arena.camera.offset==rest}
	var report := {"suite":"perfect_dodge_v05","passed":failures.is_empty(),"checks":checks,"physics_rate":rate,"failures":failures,"observed":observed}
	DirAccess.make_dir_recursive_absolute("res://evidence/perfect_dodge_v05/")
	var file := FileAccess.open("res://evidence/perfect_dodge_v05/test_%d.json"%rate,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
