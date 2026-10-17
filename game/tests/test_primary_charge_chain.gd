extends "res://tests/test_air_dash_animation_v14.gd"

class PoseProbe extends Node:
	var player:CharacterBody2D
	var samples:Array[Dictionary]=[]
	func _physics_process(_delta:float) -> void:
		samples.append({"clock":player.combat_time,"animation":String(player.sprite.animation),"charging":player.is_charging,"move":String(player.move_id),"stage":player.combo_stage})

func fresh(mode:int=1,direction:int=1) -> CharacterBody2D:
	await reset()
	if mode==0:
		arena.build_arena(0)
		for t in arena.targets:t.queue_free()
		arena.targets.clear()
	for node in arena.world.get_children():
		if node is StaticBody2D and node.collision_layer==1 and node.position.y>50 and node.position.y<159:node.queue_free()
	var p:CharacterBody2D=arena.player
	p.position=Vector2(70 if direction>0 else 250,160) if mode==1 else Vector2(80,75)
	p.facing="right" if direction>0 else "left";p.attack_direction=Vector2(direction,0)
	p.critical_roll_override=.99
	await tick(6)
	return p

func clock_wait(seconds:float) -> void:
	var until:float=arena.player.combat_time+seconds
	for _i in range(500):
		if arena.player.combat_time>=until:break
		await tick()

func button(which:MouseButton,pressed:bool) -> void:
	var e:=InputEventMouseButton.new();e.button_index=which;e.pressed=pressed;e.position=Vector2(50,140)
	Input.parse_input_event(e);Input.flush_buffered_events()

func click(input:StringName) -> void:
	var which:=MOUSE_BUTTON_LEFT if input==&"light" else MOUSE_BUTTON_RIGHT
	button(which,true);await tick();button(which,false);await tick()

func charge() -> void:
	mouse(true)
	for _i in range(250):
		if arena.player.is_charging and arena.player.charge_time>=.55:break
		await tick()
	mouse(false)
	for _i in range(70):
		if arena.player.move_id==&"heavy_slash":break
		await tick()

func await_move(id:StringName) -> bool:
	for _i in range(200):
		if arena.player.move_id==id:return true
		await tick()
	return false

func tap_pose(mode:int,direction:int,moving:bool=false) -> void:
	var p:=await fresh(mode,direction)
	if moving:
		key(KEY_D if direction>0 else KEY_A,true);await clock_wait(.05)
	var probe:=PoseProbe.new();probe.player=p;probe.process_physics_priority=1000;arena.world.add_child(probe)
	var cues:Array[int]=[0];p.charge_started.connect(func()->void:cues[0]+=1)
	var before:float=p.combat_time
	mouse(true);await clock_wait(.09)
	check(not p.is_charging and not p.is_attacking,"tap interval does not enter charge or attack: %d %d %s"%[mode,direction,moving])
	check(not probe.samples.is_empty() and probe.samples.all(func(s:Dictionary)->bool:return not s.charging and not s.animation.begins_with("charged_draw") and not s.animation.begins_with("attack3")),"every physics pose before tap release stays clear of charge anticipation")
	check(cues[0]==0 and arena.hits==0,"tap interval has no charge announcement or pre-release damage")
	if moving:
		check(String(p.sprite.animation).begins_with("walk_"),"a possible tap preserves the current walking animation")
	mouse(false)
	check(await await_move(&"attack1") and p.combo_stage==1,"tap release goes directly into its own first light animation")
	check(cues[0]==0,"a completed light tap never emits a charge cue")
	observations["tap_%d_%d_%s"%[mode,direction,moving]]={"held_seconds":p.combat_time-before,"physics_samples":probe.samples.size()}
	key(KEY_D if direction>0 else KEY_A,false)

func hold_threshold() -> void:
	var p:=await fresh()
	var starts:Array[float]=[];var full:Array[float]=[]
	p.charge_started.connect(func()->void:starts.append(p.combat_time))
	p.charge_ready.connect(func()->void:full.append(p.combat_time))
	var at:float=p.combat_time
	mouse(true)
	for _i in range(250):
		if not full.is_empty():break
		if p.combat_time-at<p.PRIMARY_TAP_SECONDS-.001:check(not p.is_charging,"short held interval stays out of the charge state")
		await tick()
	check(starts.size()==1 and starts[0]-at>=.24 and starts[0]-at<.28,"confirmed hold announces charge only after the 0.24s threshold")
	check(full.size()==1 and full[0]-at>=.55 and full[0]-at<.59,"total full-charge time remains 0.55s from the original press")
	check(p.is_charging and p.move_id==&"" and arena.hits==0,"confirmed long hold has no mandatory light strike")
	mouse(false)
	check(await await_move(&"heavy_slash") and p.combo_stage==1 and p.stage_is_critical,"charged release is first-stage with its original guaranteed critical")
	observations["hold"]={"charge_started_seconds":starts[0]-at,"full_charge_seconds":full[0]-at}

func followup(input:StringName,when:String,direction:int=1,mode:int=1) -> void:
	var p:=await fresh(mode,direction)
	var seen:Array[StringName]=[];var stages:Array[int]=[]
	p.move_started.connect(func(id:StringName)->void:seen.append(id);stages.append(p.combo_stage))
	await charge()
	check(p.combo_stage==1 and p._string_id==&"attack1","charged slash counts as first stage before %s %s"%[input,when])
	if when!="queued":
		for _i in range(200):
			if not p.is_attacking:break
			await tick()
		if when=="grace":await clock_wait(.24)
		check(p._followup_move(input)!=&"","charged continuation remains available during "+when)
	var expected:=&"attack2" if input==&"light" else &"rush_cleave"
	await click(input)
	check(await await_move(expected),"charged slash continues into second %s from %s %d"%[input,when,direction])
	check(seen==[&"heavy_slash",expected] and stages==[1,2],"follow-up never restarts first light or skips to third stage")
	check(not p.is_charging and not String(p.sprite.animation).begins_with("charged_draw"),"second-stage animation has no charge prefix")
	if input==&"light":
		await click(&"light")
		check(await await_move(&"attack3") and p.combo_stage==3,"charged first plus light second continues into the normal third light")
	else:
		await click(&"heavy")
		check(await await_move(&"launch_slash") and p.combo_stage==3,"charged first plus heavy second continues into the normal third heavy")
	observations["chain_%s_%s_%d_%d"%[input,when,direction,mode]]={"moves":seen.duplicate(),"stages":stages.duplicate()}

func contact_buffer(input:StringName) -> void:
	var p:=await fresh()
	var enemy:=target_at(p.position+Vector2(27,0),30)
	await tick(4);await charge()
	for _i in range(100):
		if enemy.hp==24:break
		await tick()
	check(paused and enemy.hp==24 and p.combo_stage==1,"real charged hit opens a first-stage carving pause")
	# A stationary practice target isolates combo damage from the independently tested launch flight.
	enemy.set_physics_process(false)
	var pose:int=p.sprite.frame;var point:Vector2=p.position
	await click(input)
	check(paused and p.sprite.frame==pose and p.position==point,"second input in hit-stop leaves the frozen contact frame intact")
	var expected:=&"attack2" if input==&"light" else &"rush_cleave"
	check(await await_move(expected) and p.combo_stage==2,"buffered hit-stop input becomes the matching second-stage attack")
	for _i in range(200):
		if enemy.hp<24:break
		await tick()
	check(enemy.hp==(23 if input==&"light" else 21) and arena.hits==2,"charged and second-stage contacts each damage once with their correct damage")
	await tick(80)
	check(not p.is_attacking and arena.hits==2,"released follow-up does not create an automatic extra swing")

func expiry_and_clear() -> void:
	for clear in [false,true]:
		var p:=await fresh();await charge()
		for _i in range(200):
			if not p.is_attacking:break
			await tick()
		if clear:p.clear_input_buffer()
		else:await clock_wait(.55)
		await click(&"light")
		check(await await_move(&"attack1") and p.combo_stage==1,"cleared or expired continuation starts a fresh first light: "+str(clear))

func rebound_tap() -> void:
	var p:=await fresh()
	CONTROLS.current["attack_mouse"]=MOUSE_BUTTON_MIDDLE;CONTROLS.install(false)
	button(MOUSE_BUTTON_MIDDLE,true);await clock_wait(.07)
	check(not p.is_charging and not String(p.sprite.animation).begins_with("charged_draw"),"rebound primary tap also avoids charge anticipation")
	button(MOUSE_BUTTON_MIDDLE,false)
	check(await await_move(&"attack1"),"rebound short release performs the intended light attack")
	CONTROLS.current=CONTROLS.defaults();CONTROLS.install(false)

func run_tests() -> void:
	CONTROLS.install(false);arena=MAIN.instantiate();root.add_child(arena)
	for mode in [0,1]:
		for direction in [-1,1]:await tap_pose(mode,direction)
	for direction in [-1,1]:await tap_pose(1,direction,true)
	await hold_threshold()
	for input in [&"light",&"heavy"]:
		for direction in [-1,1]:await followup(input,"queued",direction)
		for when in ["recovery","grace"]:await followup(input,when)
		await contact_buffer(input)
	await followup(&"light","queued",1,0)
	await expiry_and_clear()
	await rebound_tap()
	var report={"suite":"primary_charge_chain","status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations}
	print(JSON.stringify(report));FileAccess.open("res://evidence/primary_charge_chain_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	arena.queue_free();await tick(6);quit(0 if failures.is_empty() else 1)
