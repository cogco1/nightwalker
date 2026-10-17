extends "res://tests/support/isolated_suite.gd"
const STREET=preload("res://scenes/night_street_proto.tscn")
const HOVER=preload("res://scripts/levels/night_street/hover_target.gd")
const TARGET=preload("res://tests/fixtures/training_target.gd")
const CONTROLS=preload("res://scripts/core/controls.gd")
const OUTPUT="res://evidence/direct_charge_capture"
var street:Node2D
var session:Node
var index:=0
var section:="intro"
var states:Array=[]
var events:Array=[]
var metal:Node2D
var flesh:CharacterBody2D

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func()->void:quit(2))
	call_deferred("run")

func mouse(pressed:bool) -> void:
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.position=Vector2(160,100)
	Input.parse_input_event(e);Input.flush_buffered_events()

func record(count:int,label:String) -> void:
	section=label
	for _i in range(count):
		await process_frame;await RenderingServer.frame_post_draw
		var p:CharacterBody2D=street.player
		root.get_texture().get_image().save_png(OUTPUT+"/%04d.png"%index)
		states.append({"frame":index,"section":section,"move":String(p.move_id),"pose":p.sprite.frame,"animation":String(p.sprite.animation),
			"position":[p.position.x,p.position.y],"camera_kick":[street.camera.offset.x,street.camera.offset.y],"paused":paused,
			"charging":p.is_charging,"charge_time":p.charge_time,"metal_position":[metal.position.x,metal.position.y],"metal_airborne":metal._charged_airborne,"draw_cuts":p.fx.draw_cut.cuts.size(),
			"draw_reach":p.fx.draw_cut.cuts[0].reach if not p.fx.draw_cut.cuts.is_empty() else 0,
			"splatter":p.fx.contact_fx.chips.size(),"stop_frames":session.hit_stop_requested_frames,"hp":[metal.hp,flesh.hp]})
		index+=1

func charge(label:String) -> void:
	mouse(true)
	for _i in range(180):
		if street.player.is_charging and street.player.charge_time>=0.60:break
		await record(1,label)

func run() -> void:
	CONTROLS.settings_path="user://direct_charge_capture_bindings.cfg";CONTROLS.current=CONTROLS.defaults();CONTROLS.install(false)
	root.size=Vector2i(320,180)
	street=STREET.instantiate();root.add_child(street);current_scene=street
	session=street.get_node("GameSession")
	# Controlled targets exist only in this capture instance. Shipped levels and AI stay unchanged.
	for node in street.get_node("World").get_children():
		if node is Node2D and node.has_method("take_damage"):
			node.position.x+=5000;node.process_mode=Node.PROCESS_MODE_DISABLED
	street.player.position=Vector2(180,156);street.player.critical_roll_override=0.99;street._follow_player()
	metal=HOVER.new();metal.max_hp=12;metal.position=Vector2(208,156)
	street.get_node("World").add_child(metal);metal.attacker.process_mode=Node.PROCESS_MODE_DISABLED
	flesh=TARGET.new();flesh.side_view=true;flesh.max_hp=6;flesh.position=Vector2(284,156)
	street.get_node("World").add_child(flesh)
	street.player.hit_resolved.connect(func(target:Node,damage:int,critical:bool,kind:String)->void:
		events.append({"frame":index,"event":"damage","damage":damage,"hp":target.hp,"kind":kind,"critical":critical,"target":"metal" if target==metal else "flesh","section":section}))
	street.player.impact.connect(func(weight:StringName,_dir:Vector2)->void:
		events.append({"frame":index,"event":"impact","weight":String(weight),"section":section}))
	street.player.swing_released.connect(func(id:StringName)->void:
		events.append({"frame":index,"event":"release","move":String(id),"section":section}))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for _i in range(12):await physics_frame
	await record(16,"intro")
	await charge("first_charge")
	await record(12,"full_hold")
	mouse(false);await record(65,"first_draw")
	await charge("second_charge")
	mouse(false);await record(65,"second_draw")
	await record(25,"end")
	var file:=FileAccess.open(OUTPUT+"/states.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":states,"events":events,"sounds":session.combat_feedback.played},"\t"));file.close()
	print("Direct charge and launch rendered: ",index," frames; target hp ",[metal.hp,flesh.hp])
	current_scene=null;street.queue_free();street=null
	for _i in range(6):await process_frame
	quit()
