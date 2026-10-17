extends "res://tests/support/isolated_suite.gd"
const STREET=preload("res://scenes/night_street_proto.tscn")
const HOVER=preload("res://scripts/levels/night_street/hover_target.gd")
const TARGET=preload("res://tests/fixtures/training_target.gd")
const CONTROLS=preload("res://scripts/core/controls.gd")
const OUTPUT="res://evidence/combat_impact_v2_capture"
var street:Node2D
var session:Node
var index:=0
var section:="intro"
var states:Array=[]
var events:Array=[]

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func()->void:quit(2))
	call_deferred("run")

func key(code:int,pressed:bool) -> void:
	var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed
	Input.parse_input_event(e);Input.flush_buffered_events()

func mouse(pressed:bool) -> void:
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.position=Vector2(160,100)
	Input.parse_input_event(e);Input.flush_buffered_events()

func record(count:int,label:String) -> void:
	section=label
	for _i in range(count):
		await process_frame
		await RenderingServer.frame_post_draw
		var p:CharacterBody2D=street.player
		root.get_texture().get_image().save_png(OUTPUT+"/%04d.png"%index)
		states.append({"frame":index,"section":section,"move":String(p.move_id),"pose":p.sprite.frame,
			"animation":String(p.sprite.animation),"position":[p.position.x,p.position.y],
			"camera":[street.camera.position.x,street.camera.position.y],"camera_kick":[street.camera.offset.x,street.camera.offset.y],
			"paused":paused,"contact_cuts":p.fx.contact_fx.contacts.size(),"splatter":p.fx.contact_fx.chips.size(),
			"stop_frames":session.hit_stop_requested_frames})
		index+=1

func walk_to(x:float) -> void:
	key(KEY_D,true)
	for _i in range(100):
		if street.player.position.x>=x:break
		await record(1,"approach")
	key(KEY_D,false)
	await record(8,"approach")

func run() -> void:
	CONTROLS.settings_path="user://combat_impact_capture_bindings.cfg"
	CONTROLS.current=CONTROLS.defaults();CONTROLS.install(false)
	root.size=Vector2i(320,180)
	street=STREET.instantiate();root.add_child(street);current_scene=street
	session=street.get_node("GameSession")
	# Only this capture scene replaces active AI with controlled material/health targets.
	# Shipped level layouts and enemy behaviour are untouched.
	for node in street.get_node("World").get_children():
		if node is Node2D and node.has_method("take_damage"):
			node.position.x+=5000;node.process_mode=Node.PROCESS_MODE_DISABLED
	street.player.position=Vector2(180,156)
	street.player.critical_roll_override=0.0
	street._follow_player()
	var metal:=HOVER.new();metal.max_hp=8;metal.position=Vector2(223,156)
	street.get_node("World").add_child(metal);metal.attacker.process_mode=Node.PROCESS_MODE_DISABLED
	var silent:=HOVER.new();silent.max_hp=1;silent.position=Vector2(338,156)
	street.get_node("World").add_child(silent);silent.attacker.process_mode=Node.PROCESS_MODE_DISABLED
	var flesh:=TARGET.new();flesh.side_view=true;flesh.max_hp=1;flesh.position=Vector2(458,156)
	street.get_node("World").add_child(flesh)
	street.player.impact.connect(func(weight:StringName,direction:Vector2)->void:
		events.append({"frame":index,"event":"impact","weight":String(weight),"direction":[direction.x,direction.y],"section":section}))
	street.player.swing_released.connect(func(id:StringName)->void:
		events.append({"frame":index,"event":"release","move":String(id),"section":section}))
	street.player.hit_resolved.connect(func(target:Node,damage:int,_critical:bool,kind:String)->void:
		events.append({"frame":index,"event":"damage","damage":damage,"hp":target.hp,"kind":kind,"section":section}))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for _i in range(12):await physics_frame
	await record(12,"intro")
	mouse(true);await record(2,"light_combo");mouse(false)
	await record(9,"light_combo")
	mouse(true);await record(2,"light_combo");mouse(false)
	for _i in range(65):
		if street.player.move_id==&"attack2":break
		await record(1,"light_combo")
	await record(8,"light_combo")
	mouse(true);await record(2,"light_combo");mouse(false)
	await record(90,"light_combo")
	# A complete held light -> coil -> release uses the actual input/charge pipeline.
	mouse(true)
	for _i in range(120):
		if street.player.is_charging and street.player.charge_time>=0.56:break
		await record(1,"heavy_charge")
	mouse(false);await record(60,"heavy_kill")
	await walk_to(302)
	key(KEY_D,true);key(KEY_SHIFT,true);mouse(true)
	await record(2,"silent_thrust")
	mouse(false);key(KEY_SHIFT,false);key(KEY_D,false)
	await record(45,"silent_thrust")
	await walk_to(422)
	mouse(true);await record(2,"flesh_kill");mouse(false)
	await record(55,"flesh_kill")
	await record(20,"end")
	var file:=FileAccess.open(OUTPUT+"/states.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":states,"events":events,"sounds":session.combat_feedback.played,
		"target_hp":[metal.hp,silent.hp,flesh.hp]},"\t"));file.close()
	print("Combat impact v2 rendered: ",index," frames; target health ",[metal.hp,silent.hp,flesh.hp])
	current_scene=null;street.queue_free();street=null
	for _i in range(6):await process_frame
	quit(0)
