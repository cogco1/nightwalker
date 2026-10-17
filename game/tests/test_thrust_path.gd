extends "res://tests/test_air_dash_animation_v14.gd"

func path_check(direction:int, hz:int, crowded:bool=false) -> void:
	Engine.physics_ticks_per_second=hz
	await reset()
	# Test an open, flat lane without the fixture's unrelated low tunnel and platform.
	for node in arena.world.get_children():
		if node is StaticBody2D and node.collision_layer==1 and node.position.y>50 and node.position.y<159:node.queue_free()
	var p:CharacterBody2D=arena.player
	p.position=Vector2(60 if direction>0 else 260,160)
	var camera:=Camera2D.new();camera.position=Vector2(160,90);camera.offset=Vector2(2,-1);arena.world.add_child(camera);camera.make_current()
	var victims:Array[CharacterBody2D]=[]
	if crowded:
		for i in range(64):victims.append(target_at(p.position+Vector2(direction*(14.0+67.0*i/63.0),0),20))
	else:
		for offset in [15,35,55,80,88]:victims.append(target_at(p.position+Vector2(direction*offset,0),20))
	var behind:=target_at(p.position-Vector2(direction*28,0),20)
	var outside:=target_at(p.position+Vector2(direction*108,0),20)
	var above:=target_at(p.position+Vector2(direction*30,-70),20)
	await tick(4)
	arena.session.combat_feedback.played.clear()
	await dash_input(direction)
	var moved_camera:=false
	var max_contacts:=0
	for _i in range(180):
		moved_camera=moved_camera or camera.offset!=Vector2(2,-1)
		max_contacts=maxi(max_contacts,p.fx.contact_fx.contacts.size())
		if p.dash_executed and not p.is_attacking and not paused:break
		await tick()
	await tick(15)
	var label:="%dHz %d crowded=%s"%[hz,direction,crowded]
	check(victims.all(func(t:CharacterBody2D)->bool:return t.hp==19),label+": every enemy along the blade path is damaged exactly once")
	check(arena.hits==victims.size(),label+": overlapping sweeps never duplicate damage")
	check(behind.hp==20 and outside.hp==20 and above.hp==20,label+": finite blade path excludes behind, beyond and vertically separated enemies")
	check(p.dash_executed and absf(p.dash_end.x-p.dash_start.x-direction*48.0)<.1,label+": all contacts preserve the full physical rush distance")
	check(arena.completed_stop_requests==[2],label+": many contacts share exactly one tiny hit-stop")
	check(moved_camera and camera.offset==Vector2(2,-1),label+": tiny carving pause includes camera movement and clean restoration")
	check(max_contacts>0 and max_contacts<=8 and arena.session.combat_feedback.played.count("hit_light")==1,label+": visible contact ink stays capped and audio does not stack per target")
	observations[label]={"targets":victims.size(),"damage_events":arena.hits,"distance":p.dash_end.x-p.dash_start.x,"stops":arena.completed_stop_requests.duplicate(),"max_contact_effects":max_contacts}

func wall_check(direction:int) -> void:
	Engine.physics_ticks_per_second=60;await reset()
	var p:CharacterBody2D=arena.player;p.position=Vector2(60 if direction>0 else 260,160)
	var at:Vector2=p.position
	arena.add_wall(Rect2(at.x+50 if direction>0 else at.x-58,40,8,120))
	var near:=target_at(at+Vector2(direction*20,0),20)
	var blocked:=target_at(at+Vector2(direction*72,0),20)
	await tick(4);await dash_input(direction);await tick(100)
	check(near.hp==19 and blocked.hp==20,"swept blade stops its damage at a real wall: "+str(direction))
	check(absf(p.dash_end.x-p.dash_start.x)<=44.2,"hero cannot rush through the same wall: "+str(direction))

func run_tests() -> void:
	CONTROLS.install(false);arena=MAIN.instantiate();root.add_child(arena)
	for hz in [30,60,120]:
		for direction in [-1,1]:await path_check(direction,hz)
	for direction in [-1,1]:
		await path_check(direction,60,true)
		await wall_check(direction)
	var report={"suite":"thrust_path","status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations}
	print(JSON.stringify(report));FileAccess.open("res://evidence/thrust_path_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	arena.queue_free();await tick(6);quit(0 if failures.is_empty() else 1)
