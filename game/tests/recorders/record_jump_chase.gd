extends "res://tests/support/isolated_suite.gd"
const STREET=preload("res://scenes/night_street_proto.tscn")
const HOVER=preload("res://scripts/levels/night_street/hover_target.gd")
const TARGET=preload("res://tests/fixtures/training_target.gd")
const CONTROLS=preload("res://scripts/core/controls.gd")
const OUTPUT="res://evidence/jump_chase_capture"
var street:Node2D
var session:Node
var index:=0
var section:="intro"
var states:Array=[]
var events:Array=[]
var metal:Node2D
var victims:Array[Node2D]=[]

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func()->void:quit(2))
	call_deferred("run")

func key(code:Key,pressed:bool) -> void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.keycode=code;e.pressed=pressed
	Input.parse_input_event(e);Input.flush_buffered_events()

func mouse(pressed:bool) -> void:
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.position=Vector2(160,100)
	Input.parse_input_event(e);Input.flush_buffered_events()

func record(count:int,label:String) -> void:
	section=label
	for _i in range(count):
		await process_frame;await RenderingServer.frame_post_draw
		var p:CharacterBody2D=street.player
		root.get_texture().get_image().save_png(OUTPUT+"/%04d.png"%index)
		var targets:Array=[]
		for t in victims:targets.append({"hp":t.hp,"position":[t.position.x,t.position.y]})
		states.append({"frame":index,"section":section,"move":String(p.move_id),"pose":p.sprite.frame,"animation":String(p.sprite.animation),
			"position":[p.position.x,p.position.y],"velocity":[p.velocity.x,p.velocity.y],"clock":p.combat_time,"camera_kick":[street.camera.offset.x,street.camera.offset.y],"paused":paused,
			"charging":p.is_charging,"chasing":p.is_jump_chasing,"charge_time":p.charge_time,"metal_position":[metal.position.x,metal.position.y],"metal_airborne":metal._charged_airborne,
			"cuts":p.fx.contact_fx.contacts.size(),"splatter":p.fx.contact_fx.chips.size(),"stop_frames":session.hit_stop_requested_frames,"metal_hp":metal.hp,"targets":targets})
		index+=1

func click(label:String) -> void:
	mouse(true);await record(1,label);mouse(false);await record(1,label)

func run() -> void:
	CONTROLS.settings_path="user://jump_chase_capture_bindings.cfg";CONTROLS.current=CONTROLS.defaults();CONTROLS.install(false)
	root.size=Vector2i(320,180)
	street=STREET.instantiate();root.add_child(street);current_scene=street
	session=street.get_node("GameSession")
	for node in street.get_node("World").get_children():
		if node is Node2D and node.has_method("take_damage"):
			node.position.x+=5000;node.process_mode=Node.PROCESS_MODE_DISABLED
	street.player.position=Vector2(180,156);street.player.critical_roll_override=0.99;street._follow_player()
	metal=HOVER.new();metal.max_hp=9;metal.position=Vector2(218,156)
	street.get_node("World").add_child(metal);metal.attacker.process_mode=Node.PROCESS_MODE_DISABLED
	street.player.hit_resolved.connect(func(target:Node,damage:int,critical:bool,kind:String)->void:
		events.append({"frame":index,"event":"damage","damage":damage,"hp":target.hp,"kind":kind,"critical":critical,"target":"metal" if target==metal else target.name,"section":section}))
	street.player.impact.connect(func(weight:StringName,_dir:Vector2)->void:
		events.append({"frame":index,"event":"impact","weight":String(weight),"section":section}))
	street.player.jump_chase_started.connect(func(target:Node2D)->void:
		events.append({"frame":index,"event":"jump_chase","target":target.name,"section":section}))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for _i in range(12):await physics_frame
	await record(20,"intro")
	mouse(true)
	for _i in range(160):
		if street.player.is_charging and street.player.charge_time>=.60:break
		await record(1,"charge")
	mouse(false)
	for _i in range(100):
		if metal.hp<9:break
		await record(1,"charged_hit")
	key(KEY_SPACE,true);key(KEY_SPACE,false)
	for _i in range(120):
		await record(1,"jump_chase")
		if street.player._jump_age>=.16 and not street.player.is_on_floor():break
	await click("air_combo_1")
	for _i in range(120):
		if metal.hp<3:break
		await record(1,"air_combo_1")
	await click("air_combo_2")
	for _i in range(150):
		if metal.hp<2:break
		await record(1,"air_combo_2")
	await click("air_combo_3")
	for _i in range(180):
		if metal.hp<1:break
		await record(1,"air_combo_3")
	for _i in range(180):
		await record(1,"landing")
		if street.player.is_on_floor() and not street.player.is_attacking and not paused:break
	await record(20,"between")
	# Spawn only capture-instance targets ahead, outside the completed charge's range. Player never warps.
	var origin:Vector2=street.player.position
	for i in range(4):
		var t:=TARGET.new();t.name="PathTarget"+str(i+1);t.side_view=true;t.max_hp=1 if i==3 else 3
		t.position=origin+Vector2(18+i*20,0);street.get_node("World").add_child(t);victims.append(t)
	await record(15,"thrust_ready")
	key(KEY_D,true);key(KEY_SHIFT,true)
	await click("thrust")
	key(KEY_SHIFT,false);key(KEY_D,false)
	await record(70,"thrust")
	await record(25,"end")
	var file:=FileAccess.open(OUTPUT+"/states.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":states,"events":events,"sounds":session.combat_feedback.played},"\t"));file.close()
	print("Chase and path thrust rendered: ",index," frames; drone hp ",metal.hp,"; path hp ",victims.map(func(t:Node2D)->int:return t.hp))
	current_scene=null;street.queue_free();street=null
	for _i in range(6):await process_frame
	quit()
