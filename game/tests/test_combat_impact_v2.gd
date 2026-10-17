extends "res://tests/test_air_dash_animation_v14.gd"
const LEGACY = preload("res://scripts/player/legacy_dash_hit_feedback.gd")
const INK = preload("res://scripts/player/impact_v2.gd")
var camera: Camera2D


func stage(health := 40, substance: StringName = &"flesh") -> CharacterBody2D:
	await reset()
	arena.player.position=Vector2(60,160)
	arena.player.facing="right"
	arena.player.attack_direction=Vector2.RIGHT
	camera=Camera2D.new()
	camera.position=Vector2(160,90)
	camera.offset=Vector2(2,-1)
	arena.world.add_child(camera)
	camera.make_current()
	var enemy:=target_at(Vector2(98,160),health)
	enemy.set_meta("hit_material",substance)
	await tick(3)
	arena.session.combat_feedback.played.clear()
	return enemy


func wait_end(limit:=100) -> void:
	for _i in range(limit):
		if not arena.player.is_attacking and not paused:return
		await tick()


func single_stop(minimum:int) -> bool:
	return arena.completed_stop_requests.size()==1 and arena.completed_stop_requests[0]>=minimum and arena.completed_stop_durations[0]+0.00001>=minimum/60.0


func thrust_feedback() -> void:
	var enemy:=await stage(1)
	var second:=target_at(Vector2(108,160),6)
	await tick(2)
	await dash_input(1)
	var peak_chips:=0
	var peak_contacts:=0
	var camera_moved:=false
	for _i in range(150):
		peak_chips=maxi(peak_chips,arena.player.fx.contact_fx.chips.size())
		peak_contacts=maxi(peak_contacts,arena.player.fx.contact_fx.contacts.size())
		camera_moved=camera_moved or camera.offset!=Vector2(2,-1)
		if not arena.player.is_attacking and not paused:break
		await tick()
	await tick(10)
	check(enemy.hp==0 and second.hp==5 and arena.hits==2,"thrust damages, pierces and kills each target exactly once")
	check(absf(arena.player.dash_end.x-arena.player.dash_start.x-48.0)<0.1,"contact feedback preserves continuous 48px thrust travel")
	check(single_stop(10),"a thrust kill has one strong pause instead of repeated per-target freezes")
	check(arena.session.combat_feedback.played.has("hit_kill"),"thrust kill restores dedicated contact audio")
	check(peak_chips>0 and peak_contacts>0,"thrust restores short contact cuts and material splatter")
	check(camera_moved and camera.offset==Vector2(2,-1),"thrust contact moves the camera and restores its exact resting offset")
	check(arena.player.MOVESET.MOVES[&"dash_stab"].hit_feedback,"thrust feedback is enabled explicitly")
	LEGACY.emit_visual(arena.player,arena.player.position+Vector2(10,-17))
	check(not arena.player.fx.bursts.is_empty() and LEGACY.HIT_SOUND.get_length()>0.0,"preserved legacy thrust VFX and audio remain callable")


func normal_contact() -> void:
	var enemy:=await stage()
	var releases:Array[float]=[]
	var contacts:Array[float]=[]
	var start:float=arena.player.combat_time
	arena.player.swing_released.connect(func(_id:StringName)->void:releases.append(arena.player.combat_time-start))
	arena.player.attack_hit.connect(func(_enemy:Node)->void:contacts.append(arena.player.combat_time-start))
	await attack()
	check(enemy.hp==40 and not arena.session.combat_feedback.played.has("swing_light"),"ordinary attack begins with visible preparation and no premature swing sound")
	for _i in range(50):
		if enemy.hp<40:break
		await tick()
	check(enemy.hp==39 and not contacts.is_empty() and contacts[0]>=0.10 and contacts[0]<=0.18,"light reaches contact after brief preparation without charge-like waiting")
	check(releases.size()==1 and releases[0]>0.07 and releases[0]<=contacts[0],"one swing cue follows the blade's release before contact")
	check(paused and arena.hit_stop_requested_frames==2 and arena.hit_stop_shake.length()>0,"ordinary hit uses a brief two-frame catch with camera displacement")
	var ink:Node2D=arena.player.fx.contact_fx
	check(ink.contacts.size()==1 and ink.chips.size()==9 and not ink.chips[0].metal,"ordinary damage spawns one short broad cut and flesh splatter")
	check(float(ink.contacts[0].life)<=0.0651 and float(ink.contacts[0].reach)>=38,"ordinary cut is broad but short lived")
	await wait_end()
	await tick(8)
	check(arena.session.combat_feedback.played.has("swing_light") and arena.session.combat_feedback.played.has("hit_light"),"ordinary release and contact sounds both play")
	check(single_stop(2) and arena.completed_stop_durations[0]<0.05,"ordinary contact freezes only once for under 50ms at either refresh rate")
	check(arena.player.position.x>66.0 and arena.player.position.x<71.0,"enlarged light swing advances naturally with a bounded lunge")
	check(camera.offset==Vector2(2,-1),"ordinary camera recoil returns exactly to its original offset")
	observations["light"]={"windup_seconds":contacts[0],"swing_cue_seconds":releases[0],"forward_pixels":arena.player.position.x-60.0,"stop_frames":arena.completed_stop_requests.duplicate(),"stop_seconds":arena.completed_stop_durations.duplicate()}


func kill_contact(substance:StringName) -> void:
	var enemy:=await stage(1,substance)
	arena.player._start_move(&"attack1")
	arena.player._resolve_hit(enemy,enemy.damage_point())
	check(enemy.hp==0 and paused and arena.hit_stop_requested_frames==10,"kill recognition pauses on the same contact tick: "+String(substance))
	var ink:Node2D=arena.player.fx.contact_fx
	check(ink.contacts.size()==1 and ink.contacts[0].kill and ink.chips.size()==28,"kill adds a distinct cut and burst: "+String(substance))
	check(ink.chips[0].metal==(substance==&"metal"),"damage splatter follows target material: "+String(substance))
	check(float(ink.contacts[0].life)<=0.0901 and float(ink.contacts[0].reach)>=100,"kill silhouette is wide and brief: "+String(substance))
	await wait_end()
	await tick(8)
	check(single_stop(10) and arena.session.combat_feedback.played.count("hit_kill")==1,"kill has one pause and one dedicated sound: "+String(substance))
	check(not arena.session.combat_feedback.played.has("hit_light"),"kill replaces the normal contact cue: "+String(substance))
	check(camera.offset==Vector2(2,-1),"kill recoil never leaves camera drift: "+String(substance))


func mixed_contacts() -> void:
	var survivor:=await stage(40)
	var victim:=target_at(Vector2(100,160),1)
	var other:=target_at(Vector2(104,160),1)
	await tick(2)
	var pauses:Array[int]=[0]
	arena.hit_stop_started.connect(func()->void:pauses[0]+=1)
	arena.player._start_move(&"attack1")
	arena.player._resolve_hit(survivor,survivor.damage_point())
	arena.player._resolve_hit(victim,victim.damage_point())
	arena.player._resolve_hit(other,other.damage_point())
	check(pauses[0]==1 and arena.hit_stop_requested_frames==10,"same-tick mixed hit upgrades to one kill pause instead of stacking freezes")
	await wait_end()
	await tick(8)
	check(survivor.hp==39 and victim.hp==0 and other.hp==0,"mixed multi-target hit keeps independent once-per-target damage")
	check(arena.session.combat_feedback.played.count("hit_kill")==1 and not arena.session.combat_feedback.played.has("hit_light"),"same-tick kill wins audio arbitration without a double transient")
	check(camera.offset==Vector2(2,-1),"upgraded pause and aftershock restore the camera")


func repeated_wave_kills() -> void:
	var first:=await stage(1)
	var second:=target_at(Vector2(260,160),1)
	await tick(3)
	arena.player._start_move(&"spin_cleave_a")
	for _i in range(100):
		if first.hp==0 and not paused and arena.player.sprite.frame>=7:break
		await tick()
	second.position=Vector2(98,160)
	await wait_end(180)
	await tick(8)
	check(first.hp==0 and second.hp==0,"independent spin hit waves can each confirm a kill")
	check(arena.completed_stop_requests.size()==2 and arena.completed_stop_requests.all(func(n:int)->bool:return n>=10) and arena.session.combat_feedback.played.count("hit_kill")==2,"new hit wave resets kill feedback without duplicating a wave's pause or sound")


func camera_and_cleanup() -> void:
	await stage()
	for weight in [&"tick",&"light",&"critical",&"heavy",&"kill"]:
		var rest:Vector2=camera.offset
		var observed:Dictionary={}
		arena.session._on_impact(weight,Vector2.RIGHT)
		for _i in range(40):
			await tick()
			observed[camera.offset]=true
		check(observed.size()>=2 and observed.has(rest),String(weight)+": every carving pause includes real camera motion and recenters")
		check(observed.keys().all(func(p:Vector2)->bool:return absf(p.x-rest.x)<=3 and absf(p.y-rest.y)<=1),String(weight)+": recoil stays within three native pixels")
		check(not arena.session.STOPS[weight].has("negative_frames") and not arena.session.STOPS[weight].has("flash"),String(weight)+": no global white flash or negative frame")
	arena.session._on_impact(&"heavy",Vector2.LEFT)
	for _i in range(30):
		if not arena.hit_stop_active:break
		await tick()
	arena.session.open_keybindings()
	check(camera.offset==Vector2(2,-1),"opening a menu cancels an in-flight recoil without offset drift")
	arena.session._close_keybindings(false)
	var ink:Node2D=arena.player.fx.contact_fx
	for i in range(30):ink.contact(Vector2(80,140),&"heavy",Vector2.RIGHT,true,&"metal")
	check(ink.contacts.size()<=8 and ink.chips.size()<=96,"crowded contacts have fixed cut and particle budgets")
	ink.step(0.5)
	check(ink.contacts.is_empty() and ink.chips.is_empty(),"all new hit and kill effects expire without lingering overlays")
	for cue in ["hit_light","hit_critical","hit_heavy","hit_kill"]:
		check(arena.session.combat_feedback.SOUNDS[cue].get_length()<=0.251 and arena.session.combat_feedback.VOLUME_DB[cue]<=-6.0,cue+": brief audio with mixer headroom")


func run_tests() -> void:
	CONTROLS.install(false)
	arena=MAIN.instantiate();root.add_child(arena)
	await thrust_feedback()
	await normal_contact()
	await kill_contact(&"flesh")
	await kill_contact(&"metal")
	await mixed_contacts()
	await repeated_wave_kills()
	await camera_and_cleanup()
	var report={"suite":"combat_impact_v2","status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations}
	var file:=FileAccess.open("res://evidence/combat_impact_v2_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report))
	arena.queue_free();await tick(6)
	quit(0 if failures.is_empty() else 1)
