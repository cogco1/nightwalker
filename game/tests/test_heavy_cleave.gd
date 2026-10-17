extends "res://tests/test_air_dash_animation_v14.gd"

func right_click() -> void:
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_RIGHT;event.position=Vector2(160,90);event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events()
	await tick()
	event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;event.pressed=false
	Input.parse_input_event(event);Input.flush_buffered_events()
	await tick()

func stage_heavy(direction:int, distance:=43.0) -> CharacterBody2D:
	await reset()
	arena.player.position=Vector2(150,160)
	arena.player.facing="right" if direction>0 else "left"
	arena.player.attack_direction=Vector2(direction,0)
	var target:=target_at(Vector2(150+direction*distance,160),40)
	await tick(3)
	arena.session.combat_feedback.played.clear()
	return target

func hit_case(direction:int) -> void:
	var target:=await stage_heavy(direction)
	var player:CharacterBody2D=arena.player
	var start:float=player.combat_time
	var origin:Vector2=player.position
	var released:Array[float]=[]
	player.swing_released.connect(func(id:StringName)->void:
		if id==&"rush_cleave":released.append(player.combat_time-start))
	await right_click()
	check(player.move_id==&"rush_cleave" and player.sprite.animation==("heavy_cleave_right" if direction>0 else "heavy_cleave_left"),"right click starts its dedicated heavy animation "+str(direction))
	check(not arena.session.combat_feedback.played.has("swing_heavy"),"heavy sound does not fire during initial preparation")
	key(KEY_A if direction>0 else KEY_D,true)
	await tick(12)
	key(KEY_A if direction>0 else KEY_D,false)
	check(target.hp==40 and player.position.distance_to(origin)<0.01 and player.sprite.frame<8,"coiled anticipation has no early damage or sliding")
	check(player.attack_direction==Vector2(direction,0) and player.facing==("right" if direction>0 else "left"),"committed heavy cannot turn freely during preparation")
	check(not player.request_dodge(Vector2(-direction,0)) and not player.request_dash_stab(-direction),"heavy preparation cannot be cancelled into an evade or thrust")
	for _i in range(50):
		if target.hp<40:break
		await tick()
	var windup:float=player.combat_time-start
	check(target.hp==37 and arena.hits==1 and windup>=0.35 and windup<=0.43,"heavy earns triple damage after readable 0.36s windup")
	check(arena.hit_stop_requested_frames==10 and paused,"heavy contact retains a strong ten-frame pause")
	check(target.knock_back_count==1,"heavy contact applies its directional knockback")
	check(released.size()==1 and released[0]>=0.31 and released[0]<=windup,"one swing cue follows the committed blade release")
	for _i in range(90):
		if not player.is_attacking:break
		await tick()
	check(player.state==player.State.RECOVERY and player._recovery_left>0.14,"heavy ends with a punishable recovery")
	check(target.hp==37 and arena.hits==1 and arena.completed_stop_requests==[10],"sweeping heavy never repeats damage or pause on one target")
	check((player.position.x-origin.x)*direction>19 and (player.position.x-origin.x)*direction<25.5,"planted release uses a bounded forward lunge without a teleport")
	check(arena.session.combat_feedback.played.count("swing_heavy")==1 and arena.session.combat_feedback.played.has("hit_heavy"),"heavy audio matches release and real contact")
	observations["heavy_"+str(direction)]={"windup_seconds":windup,"release_seconds":released,"forward_pixels":(player.position.x-origin.x)*direction,"damage":40-target.hp,"stop_frames":arena.completed_stop_requests.duplicate()}
	await tick(20)

func risk_cases() -> void:
	var target:=await stage_heavy(1,120)
	var player:CharacterBody2D=arena.player
	await right_click();await tick(8)
	var result:int=player.receive_attack({"direction":Vector2.LEFT,"knockback":20,"contact":true})
	check(result==player.AttackResult.HIT and player.state==player.State.HURT and not player.is_attacking,"enemy contact interrupts the windup: heavy has no armour or immunity")
	await tick(60)
	check(target.hp==40 and arena.hits==0,"interrupted heavy never leaves delayed damage")
	await stage_heavy(1,120)
	player=arena.player
	await right_click()
	for _i in range(70):
		if not player.is_attacking:break
		await tick()
	check(player.state==player.State.RECOVERY and player._recovery_left>0.14 and arena.completed_stop_requests.is_empty(),"whiff still commits to recovery and creates no contact pause")
	var at:Vector2=player.position
	key(KEY_D,true);await tick(3);key(KEY_D,false)
	check(player.position==at and player.state==player.State.RECOVERY,"whiff recovery cannot be bypassed by walking")
	await attack()
	for _i in range(30):
		if player.move_id==&"attack1":break
		await tick()
	check(player.move_id==&"attack1","a fresh light click buffered during recovery starts once the commitment ends")
	await tick(60)

func art_cases() -> void:
	var frames:SpriteFrames=arena.player.SIDE_FRAMES
	for facing in ["left","right"]:
		var name:StringName=StringName("heavy_cleave_"+facing)
		check(frames.has_animation(name) and frames.get_frame_count(name)==16 and not frames.get_animation_loop(name),"complete dedicated sixteen-pose heavy clip: "+facing)
		var hashes:Dictionary={}
		for i in range(16):
			var im:Image=frames.get_frame_texture(name,i).get_image()
			check(im.get_size()==Vector2i(112,96) and not im.is_empty(),"native heavy canvas "+facing+" "+str(i))
			hashes[hash(im.get_data())]=true
		check(hashes.size()==16,"all heavy poses are independently drawn: "+facing)

func run_tests() -> void:
	CONTROLS.install(false)
	arena=MAIN.instantiate();root.add_child(arena)
	await hit_case(1)
	await hit_case(-1)
	await risk_cases()
	art_cases()
	var report={"suite":"heavy_cleave","status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations}
	print(JSON.stringify(report))
	FileAccess.open("res://evidence/heavy_cleave_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	arena.queue_free();await tick(6);quit(0 if failures.is_empty() else 1)
