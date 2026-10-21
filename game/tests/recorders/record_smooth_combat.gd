extends "res://tests/support/isolated_suite.gd"
const STREET=preload("res://scenes/night_street_proto.tscn")
const CONTROLS=preload("res://scripts/core/controls.gd")
const OUTPUT="res://evidence/smooth_combat_capture"
var street:Node2D
var session:Node
var index:=0
var section:="intro"
var states:Array=[]
var events:Array=[]
var caption:Label

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func()->void:quit(2))
	call_deferred("run")

func mouse(which:MouseButton,pressed:bool) -> void:
	var e:=InputEventMouseButton.new();e.button_index=which;e.pressed=pressed;e.position=Vector2(160,100)
	Input.parse_input_event(e);Input.flush_buffered_events()

func record(count:int,label:String) -> void:
	section=label
	caption.text="普通点按：快速轻击，无蓄力起手" if label in ["intro","tap_held","tap_light"] else ("蓄力收势 → 顺势轻击二段 → 三段" if label.begins_with("light_") else "蓄力收势 → 连贯重击二段 → 上挑")
	for _i in range(count):
		await process_frame;await RenderingServer.frame_post_draw
		var p:CharacterBody2D=street.player
		root.get_texture().get_image().save_png(OUTPUT+"/%04d.png"%index)
		states.append({"frame":index,"section":section,"move":String(p.move_id),"stage":p.combo_stage,"pose":p.sprite.frame,"animation":String(p.sprite.animation),"texture":p.sprite.sprite_frames.get_frame_texture(p.sprite.animation,p.sprite.frame).resource_path,
			"position":[p.position.x,p.position.y],"velocity":[p.velocity.x,p.velocity.y],"clock":p.combat_time,"paused":paused,
			"charging":p.is_charging,"primary_pending":not p._primary_press.is_empty(),"charge_time":p.charge_time,"camera_kick":[street.camera.offset.x,street.camera.offset.y]})
		index+=1

func click(which:MouseButton,label:String) -> void:
	mouse(which,true);await record(1,label);mouse(which,false);await record(1,label)

func charge(label:String) -> void:
	mouse(MOUSE_BUTTON_LEFT,true)
	for _i in range(160):
		if street.player.is_charging and street.player.charge_time>=.60:break
		await record(1,label)
	mouse(MOUSE_BUTTON_LEFT,false)
	for _i in range(120):
		await record(1,label)
		if street.player.move_id==&"heavy_slash" and street.player.sprite.frame>=10:break

func wait_move(id:StringName,label:String) -> void:
	for _i in range(180):
		if street.player.move_id==id:return
		await record(1,label)

func wait_free(label:String) -> void:
	for _i in range(180):
		await record(1,label)
		if street.player.state==street.player.State.FREE:return

func run() -> void:
	CONTROLS.settings_path="user://smooth_combat_capture_bindings.cfg";CONTROLS.current=CONTROLS.defaults();CONTROLS.install(false)
	root.size=Vector2i(320,180)
	street=STREET.instantiate();root.add_child(street);current_scene=street
	session=street.get_node("GameSession")
	for node in street.get_node("World").get_children():
		if node is Node2D and node.has_method("take_damage"):
			node.position.x+=5000;node.process_mode=Node.PROCESS_MODE_DISABLED
	street.player.position=Vector2(180,156);street.player.critical_roll_override=.99;street._follow_player()
	var layer:=CanvasLayer.new();layer.layer=110;street.add_child(layer)
	caption=Label.new();caption.position=Vector2(6,18);caption.add_theme_font_override("font",load("res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.otf"));caption.add_theme_font_size_override("font_size",10)
	caption.add_theme_color_override("font_shadow_color",Color("070b17"));caption.add_theme_constant_override("shadow_offset_x",1);caption.add_theme_constant_override("shadow_offset_y",1);layer.add_child(caption)
	street.player.move_started.connect(func(id:StringName)->void:events.append({"frame":index,"event":"move","move":String(id),"stage":street.player.combo_stage,"animation":String(street.player.sprite.animation),"pose":street.player.sprite.frame,"section":section}))
	street.player.charge_started.connect(func()->void:events.append({"frame":index,"event":"charge_started","section":section}))
	street.player.charge_ready.connect(func()->void:events.append({"frame":index,"event":"charge_ready","section":section}))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for _i in range(12):await physics_frame
	await record(15,"intro")
	mouse(MOUSE_BUTTON_LEFT,true);await record(11,"tap_held")
	mouse(MOUSE_BUTTON_LEFT,false);await wait_free("tap_light");await record(12,"tap_light")
	await charge("light_charge")
	await click(MOUSE_BUTTON_LEFT,"light_second")
	await wait_move(&"attack2","light_second")
	await record(9,"light_second")
	await click(MOUSE_BUTTON_LEFT,"light_third")
	await wait_move(&"attack3","light_third")
	await wait_free("light_third");await record(12,"light_end")
	await charge("heavy_charge")
	await click(MOUSE_BUTTON_RIGHT,"heavy_second")
	await wait_move(&"rush_cleave","heavy_second")
	await record(14,"heavy_second")
	await click(MOUSE_BUTTON_RIGHT,"heavy_third")
	await wait_move(&"launch_slash","heavy_third")
	await wait_free("heavy_third")
	for _i in range(130):
		await record(1,"end")
		if street.player.is_on_floor():break
	await record(18,"end")
	var file:=FileAccess.open(OUTPUT+"/states.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":states,"events":events,"sounds":session.combat_feedback.played},"\t"));file.close()
	print("Smooth charge links and ordinary light clicks rendered: ",index," frames; move sequence ",events.filter(func(e:Dictionary)->bool:return e.event=="move"))
	current_scene=null;street.queue_free();street=null
	for _i in range(6):await process_frame
	quit()
