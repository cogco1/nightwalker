extends "res://tests/test_air_dash_animation_v14.gd"
var chase_events: Array[Node2D] = []
class FlightProbe extends Node:
	var player:CharacterBody2D
	var points:Array[Vector2]=[]
	var jump_poses:Dictionary={}
	func _physics_process(_delta:float) -> void:
		points.append(player.position)
		if String(player.sprite.animation).begins_with("jump_"):jump_poses[player.sprite.frame]=true


func flat_reset() -> void:
	await reset()
	for node in arena.world.get_children():
		if node is StaticBody2D and node.collision_layer == 1:
			var bounds: Rect2 = Rect2(node.position, node.get_child(0).shape.size)
			if bounds.position.y > 50.0 and bounds.position.y < 159.0:
				node.queue_free()
	await tick(4)
	chase_events.clear()
	arena.player.jump_chase_started.connect(func(target: Node2D) -> void: chase_events.append(target))

func launch(target: Node2D) -> void:
	mouse(true)
	for _i in range(200):
		if arena.player.is_charging and arena.player.charge_time >= .55: break
		await tick()
	mouse(false)
	for _i in range(100):
		if target.hp < target.max_hp: break
		await tick()

func chase_combo(direction: int, distance: float) -> void:
	await flat_reset()
	var p: CharacterBody2D = arena.player
	p.position = Vector2(66 if direction>0 else 254,160)
	p.facing = "right" if direction>0 else "left"
	p.attack_direction = Vector2(direction,0)
	var target: Node2D
	target=target_at(p.position+Vector2(direction*distance,0),30)
	await tick(4)
	await launch(target)
	check(target.hp==24 and paused and p.can_jump_chase(),"charged contact opens a chase only after the real hit")
	var monitor:=FlightProbe.new();monitor.player=p;monitor.process_physics_priority=1000;arena.world.add_child(monitor)
	var origin: Vector2=p.position
	key(KEY_SPACE,true); key(KEY_SPACE,false)
	await tick()
	check(p.position==origin and chase_events.is_empty(),"jump buffered in hit-stop never moves the frozen frame")
	for _i in range(90):
		if not chase_events.is_empty():break
		await tick()
	check(chase_events==[target] and p.velocity.y<0,"buffered Space starts exactly one physical chase toward the survivor")
	var jump_poses: Dictionary={}
	var positions: Array[Vector2]=[p.position]
	for _i in range(150):
		await tick()
		positions.append(p.position)
		if String(p.sprite.animation).begins_with("jump_"):jump_poses[p.sprite.frame]=true
		if p._jump_age>=.10 and absf(target.position.x-p.position.x)<49.0 and absf(target.position.y-p.position.y)<18.0 and not p.is_on_floor():break
	check(not p.is_on_floor() and absf(target.position.y-p.position.y)<22.0,"jump reaches the airborne enemy at a usable combo height")
	check(monitor.jump_poses.size()>=2,"chase shows successive authored jump poses")
	await attack()
	for _i in range(140):
		positions.append(p.position)
		if target.hp<24:break
		await tick()
	check(target.hp==23 and String(p.sprite.animation).begins_with("air_attack2_"),"first air slash connects after the continuous chase")
	check(p._air_hold_left>0.0 and target._air_hold_left>0.0,"contact gives hero and target matching air-combo hang time")
	await attack()
	for _i in range(180):
		if target.hp<23:break
		await tick()
	check(target.hp==22 and String(p.sprite.animation).begins_with("air_attack3_"),"second air slash chains without recharging or a ground animation")
	var max_step:=0.0
	for i in range(1,monitor.points.size()):max_step=maxf(max_step,monitor.points[i].distance_to(monitor.points[i-1]))
	check(max_step<8.0,"every sampled chase step is continuous, with no teleport")
	await tick(210)
	check(p.is_on_floor() and not p.is_jump_chasing and not p.can_jump_chase(),"landing clears the chase and returns to normal controls")
	observations["%d_%d"%[direction,distance]]={"largest_step":max_step,"jump_poses":jump_poses.size(),"target_hp":target.hp}

func eligibility() -> void:
	await flat_reset()
	var p: CharacterBody2D=arena.player
	p.position=Vector2(60,160);await tick(3)
	check(not p.request_jump_chase(),"no launch grants no assisted jump")
	var corpse:=target_at(Vector2(90,160),6)
	await tick(3);await launch(corpse)
	check(corpse.hp==0 and not p.can_jump_chase(),"a killed target cannot grant a chase")
	await flat_reset();p=arena.player;p.position=Vector2(60,160)
	var enemy:=target_at(Vector2(90,160),30)
	await tick(3);await launch(enemy);await tick(105)
	check(not p.request_jump_chase(),"expired window cannot chase a landed enemy")
	await flat_reset();p=arena.player;p.position=Vector2(60,160)
	enemy=target_at(Vector2(90,160),30)
	await tick(3);await launch(enemy)
	p.clear_input_buffer()
	check(not p.can_jump_chase() and not p.is_jump_chasing,"menus/input clearing discard the old chase")
	await flat_reset();p=arena.player;p.position=Vector2(60,160)
	enemy=target_at(Vector2(90,160),30)
	await tick(3);await launch(enemy)
	enemy.queue_free();await tick(3)
	check(not p.request_jump_chase(),"freed launch targets are handled safely")

func buffered_first_swing() -> void:
	await flat_reset()
	var p:CharacterBody2D=arena.player;p.position=Vector2(60,160)
	var target:=target_at(Vector2(94,160),30)
	await tick(3);await launch(target)
	key(KEY_SPACE,true);key(KEY_SPACE,false);mouse(true);mouse(false)
	for _i in range(160):
		if target.hp<24:break
		await tick()
	check(chase_events==[target] and target.hp==23,"Space and the first light click can both be buffered in the charged hit-stop")
	check(String(p.sprite.animation).begins_with("air_attack2_"),"buffered first swing selects the air clip after physical take-off")

func survivor_choice_and_late_jump() -> void:
	await flat_reset()
	var p:CharacterBody2D=arena.player;p.position=Vector2(60,160)
	var doomed:=target_at(Vector2(82,160),6)
	var nearest:=target_at(Vector2(104,160),30)
	var farther:=target_at(Vector2(145,160),30)
	await tick(3);await launch(nearest)
	for _i in range(80):
		if farther.hp==24 and not paused:break
		await tick()
	check(doomed.hp==0 and nearest.hp==24 and farther.hp==24 and p._live_chase_target()==nearest,"multi-target charge chooses the nearest living victim regardless of collider query order")
	var deadline:float=p.combat_time+.27
	for _i in range(120):
		if p.combat_time>=deadline:break
		await tick()
	key(KEY_SPACE,true);key(KEY_SPACE,false)
	for _i in range(120):
		await tick()
		if not p.is_on_floor() and p._jump_age>=.13 and absf(p.position.x-nearest.position.x)<49 and absf(p.position.y-nearest.position.y)<20:break
	check(chase_events==[nearest] and not p.is_on_floor(),"late Space within the window still starts a physical chase")
	await attack()
	for _i in range(120):
		if nearest.hp<24:break
		await tick()
	check(nearest.hp==23,"late chase can still connect an air attack")

func blockers() -> void:
	await flat_reset()
	var p: CharacterBody2D=arena.player
	p.position=Vector2(60,160)
	var target:=target_at(Vector2(88,160),30)
	await tick(3);await launch(target)
	arena.add_wall(Rect2(100,30,8,130))
	arena.add_wall(Rect2(30,105,70,6))
	key(KEY_SPACE,true);key(KEY_SPACE,false)
	var min_y:=160.0
	var max_x:=p.position.x
	for _i in range(150):
		await tick();min_y=minf(min_y,p.position.y);max_x=maxf(max_x,p.position.x)
	check(chase_events.size()==1,"blocked chase still starts as a real jump")
	check(min_y>=136.5 and max_x<=94.1,"chase respects both ceiling and wall collision")
	check(p.is_on_floor() and p.collision_mask==3,"blocked chase returns safely to the floor")

func run_tests() -> void:
	CONTROLS.install(false);arena=MAIN.instantiate();root.add_child(arena)
	for direction in [-1,1]:await chase_combo(direction,34.0)
	await chase_combo(1,96.0)
	await buffered_first_swing()
	await survivor_choice_and_late_jump()
	await eligibility()
	await blockers()
	var report={"suite":"jump_chase","status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations}
	print(JSON.stringify(report));FileAccess.open("res://evidence/jump_chase_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	arena.queue_free();await tick(6);quit(0 if failures.is_empty() else 1)
