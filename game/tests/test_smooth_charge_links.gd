extends "res://tests/test_primary_charge_chain.gd"

func ordinary_click(seconds:float,mode:int,direction:int) -> void:
	var p:=await fresh(mode,direction)
	var enemy:=TARGET.new();enemy.side_view=mode==1;enemy.max_hp=30
	enemy.position=p.position+Vector2(direction*30,-12 if mode==0 else 0)
	arena.world.add_child(enemy);enemy.set_physics_process(false)
	await tick(3)
	var poses:=PoseProbe.new();poses.player=p;poses.process_physics_priority=1000;arena.world.add_child(poses)
	var stamps:Dictionary={};var charge_cues:Array[int]=[0]
	p.move_started.connect(func(_id:StringName)->void:stamps["move"]=p.combat_time)
	p.attack_hit.connect(func(_target:Node)->void:stamps["hit"]=p.combat_time)
	p.charge_started.connect(func()->void:charge_cues[0]+=1)
	mouse(true);await clock_wait(seconds)
	check(not p.is_charging and poses.samples.all(func(s:Dictionary)->bool:return not s.charging),"ordinary %.2fs click has no charge state or coiled pose, view%d side%d"%[seconds,mode,direction])
	mouse(false)
	check(await await_move(&"attack1"),"ordinary longer click still releases one first light attack")
	for _i in range(120):
		if stamps.has("hit"):break
		await tick()
	var windup:float=stamps.get("hit",1000.0)-stamps.get("move",0.0)
	check(enemy.hp==29 and charge_cues[0]==0,"ordinary longer click has one light damage and zero charge cues")
	check(windup>=.07 and windup<=.14,"actual light animation reaches contact in about a tenth of a second")
	observations["click_%s_%d_%d"%[seconds,mode,direction]]={"hold_seconds":seconds,"animation_to_contact_seconds":windup,"charge_cues":charge_cues[0]}

func resource_links() -> void:
	var frames:SpriteFrames=load("res://assets/side_view.tres")
	var paths:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/blade_paths.json"))["side_view"]
	for prefix in ["charge_link_light","charge_link_heavy"]:
		for facing in ["left","right"]:
			var clip:String=prefix+"_"+facing
			check(frames.has_animation(clip) and frames.get_frame_count(clip)==16 and not frames.get_animation_loop(clip),"complete nonlooping link clip: "+clip)
			check(frames.get_frame_texture(clip,0)==frames.get_frame_texture("charged_draw_"+facing,11) and frames.get_frame_texture(clip,1)==frames.get_frame_texture("charged_draw_"+facing,12),"link carries the next two exact authored recovery poses without a neutral reset: "+clip)
			check(paths.has(clip) and paths[clip].size()==16 and paths[clip][0]==paths["charged_draw_"+facing][11] and paths[clip][1]==paths["charged_draw_"+facing][12],"drawn blade paths follow the same recovery poses: "+clip)
			var units:=0.0
			var first:=6 if prefix=="charge_link_light" else 8
			for i in range(first):units+=frames.get_frame_duration(clip,i)
			var windup:=units/frames.get_animation_speed(clip)
			check(windup<=.11 if first==6 else windup>=.15 and windup<=.19,"link removes repeated wind-up while keeping the heavy slower: "+clip)
			check(frames.get_frame_duration(clip,0)/frames.get_animation_speed(clip)>=1.0/60.0 and frames.get_frame_duration(clip,1)/frames.get_animation_speed(clip)>=1.0/60.0,"both bridge poses have at least a full 60Hz display interval: "+clip)

func continuous_link(input:StringName,direction:int) -> void:
	var p:=await fresh(1,direction)
	var enemy:=target_at(p.position+Vector2(direction*27,0),40);enemy.set_physics_process(false)
	await tick(3)
	var hits:Array[Dictionary]=[];var entry:Dictionary={}
	p.hit_resolved.connect(func(_t:Node,damage:int,_critical:bool,_kind:String)->void:hits.append({"at":p.combat_time,"damage":damage,"move":String(p.move_id)}))
	p.move_started.connect(func(id:StringName)->void:
		if id in [&"attack2",&"rush_cleave"]:
			entry.merge({"pose":p.sprite.frame,"clip":String(p.sprite.animation),"texture":p.sprite.sprite_frames.get_frame_texture(p.sprite.animation,p.sprite.frame),"foot":p.sprite.offset,"at":p.combat_time,"stage":p.combo_stage}))
	await charge()
	for _i in range(120):
		if hits.size()==1:break
		await tick()
	check(paused and hits.size()==1 and hits[0].damage==6,"real charged cut hits first and opens its strong pause")
	await click(input)
	var next:=&"attack2" if input==&"light" else &"rush_cleave"
	check(await await_move(next),"buffered charge continues into the requested second stage")
	var prefix:="charge_link_light_" if input==&"light" else "charge_link_heavy_"
	var facing:="right" if direction>0 else "left"
	check(entry.get("clip","")==prefix+facing and entry.get("stage",0)==2,"real gameplay chooses the dedicated grounded continuation")
	check(entry.get("pose",-1) in [0,1] and entry.texture==p.SIDE_FRAMES.get_frame_texture("charged_draw_"+facing,11+int(entry.pose)),"the continuation begins on the exact next charged recovery texture")
	check(entry.foot==Vector2(-56,-84) and p.sprite.scale==Vector2.ONE and p.body_shape.shape.size==Vector2(12,26),"bridge keeps the registered foot, body scale and collider")
	for _i in range(150):
		if hits.size()>=2:break
		await tick()
	var gap:float=hits[1].at-hits[0].at if hits.size()>=2 else 1000.0
	check(hits.size()==2 and hits[1].damage==(1 if input==&"light" else 3),"bridges do not hit, duplicate damage, or change second-stage strength")
	check(gap<=.23 if input==&"light" else gap<=.31,"next contact follows promptly without replaying the old full anticipation")
	await tick(90)
	check(hits.size()==2 and arena.completed_stop_requests.size()==2 and arena.completed_stop_durations[0]+.00001>=10.0/60.0 and arena.completed_stop_durations[1]+.00001>=(2.0/60.0 if input==&"light" else 10.0/60.0) and (arena.completed_stop_durations[1]<.06 if input==&"light" else true),"light follows fluidly and charged/heavy impacts retain their strong carving pauses")
	observations["link_%s_%d"%[input,direction]]={"first_to_second_combat_seconds":gap,"entry_clip":entry.clip,"entry_pose":entry.pose,"hit_damage":hits.map(func(h:Dictionary)->int:return h.damage),"stops":arena.completed_stop_requests.duplicate()}

func recovery_entry() -> void:
	for input in [&"light",&"heavy"]:
		var p:=await fresh();await charge()
		for _i in range(180):
			if p.state==p.State.RECOVERY:break
			await tick()
		var source:Dictionary={}
		p.move_started.connect(func(id:StringName)->void:
			if id in [&"attack2",&"rush_cleave"]:source.merge({"pose":p.sprite.frame,"clip":String(p.sprite.animation)}))
		await click(input)
		var next:=&"attack2" if input==&"light" else &"rush_cleave"
		check(await await_move(next),"click during charged recovery still uses the short linked continuation")
		check(source.get("pose",-1)==2 and String(source.get("clip","")).begins_with("charge_link"),"later recovery joins the upright entry instead of replaying lower charged poses")

func late_entry() -> void:
	for input in [&"light",&"heavy"]:
		var p:=await fresh();await charge()
		for _i in range(180):
			if p.state==p.State.FREE:break
			await tick()
		await clock_wait(.03);await click(input)
		var next:=&"attack2" if input==&"light" else &"rush_cleave"
		check(await await_move(next),"late input still continues the correct combo identity")
		check(not String(p.sprite.animation).begins_with("charge_link"),"late input from idle never jumps backward into a crouched charged recovery")

func run_tests() -> void:
	CONTROLS.install(false);arena=MAIN.instantiate();root.add_child(arena)
	await resource_links()
	for seconds in [.08,.18,.22]:
		for direction in [-1,1]:await ordinary_click(seconds,1,direction)
	for direction in [-1,1]:await ordinary_click(.18,0,direction)
	for input in [&"light",&"heavy"]:
		for direction in [-1,1]:await continuous_link(input,direction)
	await recovery_entry()
	await late_entry()
	var report={"suite":"smooth_charge_links","status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations}
	print(JSON.stringify(report));FileAccess.open("res://evidence/smooth_charge_links_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	arena.queue_free();await tick(6);quit(0 if failures.is_empty() else 1)
