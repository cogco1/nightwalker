extends "res://tests/test_air_dash_animation_v14.gd"

func held_charge(direction:int) -> void:
	await reset()
	var p:CharacterBody2D=arena.player
	p.position=Vector2(80 if direction>0 else 120,160)
	p.facing="right" if direction>0 else "left"
	p.attack_direction=Vector2(direction,0)
	var target:=target_at(p.position+Vector2(direction*27,0),20)
	await tick(6)
	var moves:Array[StringName]=[]
	p.move_started.connect(func(id:StringName)->void:moves.append(id))
	var start:float=p.combat_time
	mouse(true)
	for _i in range(180):
		if p.is_charging and p.charge_time>=p.CHARGE_FULL_SECONDS:break
		await tick()
	var elapsed:float=p.combat_time-start
	check(p.is_charging and p.charge_time>=.55 and elapsed<.62,"held primary reaches full charge directly in about 0.55s")
	check(moves.is_empty() and target.hp==20 and arena.hits==0,"holding next to an enemy never starts or lands an opening light attack")
	check(not arena.session.combat_feedback.played.has("swing_light"),"direct charge has no stray light swing sound")
	mouse(false)
	for _i in range(90):
		if target.hp<20:break
		await tick()
	check(target.hp==14 and moves==[&"heavy_slash"] and arena.hits==1,"release performs exactly one six-damage charged attack")
	check(target.knock_count==1 and target.last_knock_velocity==Vector2(direction*105.0,-300.0),"charged contact launches once with upward and forward velocity")
	check(paused and arena.hit_stop_requested_frames==10,"charged launch retains its strong carving pause")
	var at:Vector2=target.position
	await tick()
	check(target.position==at,"launch motion freezes with the contact pause")
	var min_y:float=at.y
	for _i in range(220):
		await tick()
		min_y=minf(min_y,target.position.y)
		if target.is_on_floor() and target.position.y>=159 and not paused:break
	check(at.y-min_y>45,"launched target follows a substantial real upward arc")
	check(target.is_on_floor() and absf(target.position.y-160)<.3,"launched target returns to the actual floor")
	check(target.hp==14 and arena.hits==1,"flight and landing do not repeat charged damage")
	observations["charge_"+str(direction)]={"charge_seconds":elapsed,"upward_pixels":at.y-min_y,"damage":20-target.hp,"moves":moves}

func short_taps() -> void:
	await reset()
	var p:CharacterBody2D=arena.player
	p.position=Vector2(60,160)
	await tick(6)
	var cues:Array[int]=[0]
	p.charge_started.connect(func()->void:cues[0]+=1)
	mouse(true);await tick()
	check(not p.is_attacking and arena.hits==0,"initial ground press is harmless anticipation")
	mouse(false);await tick(3)
	check(p.move_id==&"attack1" and cues[0]==0,"short release starts one light swing without charge audio")
	await attack()
	for _i in range(100):
		if p.move_id==&"attack2":break
		await tick()
	check(p.move_id==&"attack2","released taps retain the ordinary combo buffer")
	await tick(100)
	check(not p.is_attacking and not p.is_charging,"taps finish without an automatic charge")
	# A complete press/release between physics steps must also register once.
	mouse(true);mouse(false);await tick(3)
	check(p.move_id==&"attack1","same-frame short click is preserved")
	await tick(100)
	# Input clearing while the button is held must suppress any later release action.
	mouse(true);await tick(8);p.clear_input_buffer();mouse(false);await tick(100)
	check(not p.is_attacking and not p.is_charging,"cancelled gesture never becomes a delayed light or charged attack")

func run_tests() -> void:
	CONTROLS.install(false);arena=MAIN.instantiate();root.add_child(arena)
	await held_charge(1)
	await held_charge(-1)
	await short_taps()
	var report={"suite":"direct_charge","status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations}
	print(JSON.stringify(report));FileAccess.open("res://evidence/direct_charge_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	arena.queue_free();await tick(6);quit(0 if failures.is_empty() else 1)
