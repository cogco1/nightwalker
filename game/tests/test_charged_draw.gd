extends "res://tests/test_air_dash_animation_v14.gd"

func setup_draw(direction:int) -> void:
	await reset()
	arena.player.position=Vector2(100 if direction>0 else 180,160)
	arena.player.facing="right" if direction>0 else "left"
	arena.player.attack_direction=Vector2(direction,0)
	await tick(6)
	arena.session.combat_feedback.played.clear()

func coil_full() -> bool:
	mouse(true)
	for _i in range(400):
		if arena.player.is_charging and arena.player.charge_time>=arena.player.CHARGE_FULL_SECONDS:return true
		await tick()
	return false

func finish_draw() -> void:
	for _i in range(240):
		if not arena.player.is_charging and not arena.player.is_attacking and not paused:return
		await tick()

func wide_case(direction:int) -> void:
	await setup_draw(direction)
	var player:CharacterBody2D=arena.player
	var origin:Vector2=player.position
	var near:=target_at(origin+Vector2(direction*74,0),40)
	var far:=target_at(origin+Vector2(direction*104,0),40)
	var high:=target_at(origin+Vector2(direction*72,-33),40)
	high._air_hold_left=2.5;high.velocity.y=6.0
	var beyond:=target_at(origin+Vector2(direction*180,0),40)
	var behind:=target_at(origin-Vector2(direction*55,0),40)
	check(await coil_full(),"real held input reaches full charge: "+str(direction))
	check(player.sprite.animation==("charged_draw_right" if direction>0 else "charged_draw_left") and player.sprite.frame==6,"full charge holds the new low hip pose")
	check(near.hp==40 and far.hp==40 and high.hp==40,"coiling and the opening light never damage the extended-range targets")
	var before:float=player.combat_time
	mouse(false)
	for _i in range(90):
		if far.hp<40:break
		await tick()
	var latency:float=player.combat_time-before
	check(near.hp==34 and far.hp==34 and high.hp==34,"one charged draw deals 6x damage to near, distant and elevated targets")
	check(latency>=0.033 and latency<=0.10,"charged release is responsive without adding a second long windup")
	check(beyond.hp==40 and behind.hp==40,"wide charged cut remains bounded and forward-facing")
	check(player.attack_box().size==Vector2(120,56),"side charged hitbox expands from 56x28 to 120x56")
	check(paused and arena.hit_stop_requested_frames==10,"multiple targets share one strong heavy pause")
	check(player.fx.draw_cut.cuts.size()==1 and player.fx.draw_cut.cuts[0].reach>=113 and player.fx.contact_fx.contacts[0].crimson,"one black-red cut follows actual release at the expanded reach")
	await finish_draw()
	check(arena.hits==3 and near.hp==34 and far.hp==34 and high.hp==34,"each overlapped target takes charged damage only once")
	check(arena.completed_stop_requests.size()==1 and arena.completed_stop_durations[0]+0.00001>=10.0/60,"multi-target charged hit does not stack extra freezes")
	check(player.state==player.State.RECOVERY and player._recovery_left>0.19,"charged slash still commits to recovery")
	await tick(60)
	check(player.fx.draw_cut.cuts.is_empty(),"brief black-red cut clears after the strike")
	observations["wide_"+str(direction)]={"box":[120,56],"damage":6,"release_to_hit_seconds":latency,"hits":arena.hits,"stops":arena.completed_stop_requests.duplicate()}

func wall_case(direction:int) -> void:
	await setup_draw(direction)
	var player:CharacterBody2D=arena.player
	var x:float=player.position.x
	var target:=target_at(Vector2(x+direction*95,160),40)
	var wall_x:=x+direction*50
	arena.add_wall(Rect2(wall_x-2,90,4,70))
	check(await coil_full(),"wall case reaches full charge")
	mouse(false)
	var saw_cut:=false
	for _i in range(100):
		await tick()
		if not player.fx.draw_cut.cuts.is_empty():
			saw_cut=true
			check(player.fx.draw_cut.cuts[0].reach<60,"ink extension clips to the actual wall")
			break
	await finish_draw()
	check(saw_cut and target.hp==40 and arena.hits==0,"expanded range never damages through a wall")
	check(arena.completed_stop_requests.is_empty(),"a blocked charged slash does not invent a contact pause")
	await tick(60)

func cancel_cases() -> void:
	await setup_draw(1)
	mouse(true)
	for _i in range(240):
		if arena.player.is_charging:break
		await tick()
	await tick(3);mouse(false)
	await tick(35)
	check(not arena.player.is_charging and arena.player.fx.draw_cut.cuts.is_empty() and arena.hits==0,"early release cancels without a black-red wave or bonus hit")
	await setup_draw(1)
	check(await coil_full(),"interrupt case reaches the full coiled pose")
	var result:int=arena.player.receive_attack({"direction":Vector2.LEFT,"contact":true,"knockback":20})
	mouse(false)
	await tick(45)
	check(result==arena.player.AttackResult.HIT and not arena.player.is_charging and arena.hits==0 and arena.player.fx.draw_cut.cuts.is_empty(),"enemy contact still interrupts full charge without delayed damage")

func art_cases() -> void:
	for facing in ["left","right"]:
		var clip:StringName=StringName("charged_draw_"+facing)
		var frames:SpriteFrames=arena.player.SIDE_FRAMES
		check(frames.has_animation(clip) and frames.get_frame_count(clip)==16 and not frames.get_animation_loop(clip),"complete independent charged clip: "+facing)
		var hashes:Dictionary={}
		for i in range(16):
			var im:Image=frames.get_frame_texture(clip,i).get_image()
			check(im.get_size()==Vector2i(112,96),"native charged canvas: "+facing+str(i))
			hashes[hash(im.get_data())]=true
		check(hashes.size()==16,"sixteen distinct charged poses: "+facing)

func run_tests() -> void:
	CONTROLS.install(false)
	arena=MAIN.instantiate();root.add_child(arena)
	await wide_case(1)
	await wide_case(-1)
	await wall_case(1)
	await wall_case(-1)
	await cancel_cases()
	art_cases()
	var report={"suite":"charged_draw","status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations}
	print(JSON.stringify(report))
	FileAccess.open("res://evidence/charged_draw_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	arena.queue_free();await tick(6);quit(0 if failures.is_empty() else 1)
