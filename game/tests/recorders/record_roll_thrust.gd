extends "res://tests/support/isolated_suite.gd"
const STREET=preload("res://scenes/night_street_proto.tscn")
const CONTROLS=preload("res://scripts/core/controls.gd")
const OUTPUT="res://evidence/roll_thrust_capture"
var street:Node2D
var index:=0
var states:Array=[]
var physics_samples:Array=[]
var section:="setup"

class Probe extends Node:
	var owner_tree:SceneTree
	func _physics_process(_delta:float) -> void:
		owner_tree.sample_physics()

func _initialize() -> void:
	call_deferred("run")

func sample_physics() -> void:
	var p:CharacterBody2D=street.player
	physics_samples.append({"section":section,"position":[p.position.x,p.position.y],
		"camera":[street.camera.position.x,street.camera.position.y],
		"move":String(p.move_id),"rush_elapsed":p._dash_elapsed,"dodging":p.is_dodging})

func key(code:int,pressed:bool) -> void:
	var e:=InputEventKey.new()
	e.keycode=code;e.physical_keycode=code;e.pressed=pressed
	Input.parse_input_event(e);Input.flush_buffered_events()

func mouse(pressed:bool) -> void:
	var e:=InputEventMouseButton.new()
	e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.position=Vector2(160,100)
	Input.parse_input_event(e);Input.flush_buffered_events()

func record(count:int,label:String) -> void:
	section=label
	for _i in range(count):
		await process_frame
		await RenderingServer.frame_post_draw
		var p:CharacterBody2D=street.player
		root.get_texture().get_image().save_png(OUTPUT+"/%04d.png"%index)
		states.append({"frame":index,"section":section,"animation":String(p.sprite.animation),
			"pose":p.sprite.frame,"move":String(p.move_id),"position":[p.position.x,p.position.y],
			"camera":[street.camera.position.x,street.camera.position.y],"dodging":p.is_dodging})
		index+=1

func roll(direction:int) -> void:
	key(KEY_D if direction>0 else KEY_A,true)
	await record(2,"face")
	key(KEY_D if direction>0 else KEY_A,false)
	await record(6,"idle")
	key(KEY_SHIFT,true)
	await record(2,"tap")
	key(KEY_SHIFT,false)
	await record(22,"roll_right" if direction>0 else "roll_left")

func rush(direction:int,label:String) -> void:
	key(KEY_D if direction>0 else KEY_A,true)
	key(KEY_SHIFT,true);mouse(true)
	await record(2,label)
	mouse(false);key(KEY_SHIFT,false);key(KEY_D if direction>0 else KEY_A,false)
	await record(30,label)

func run() -> void:
	CONTROLS.settings_path="user://roll_capture_bindings.cfg"
	CONTROLS.current=CONTROLS.defaults();CONTROLS.install(false)
	root.size=Vector2i(320,180)
	street=STREET.instantiate();root.add_child(street);current_scene=street
	# Only this recording instance uses an empty demonstration stretch.
	for node in street.get_node("World").get_children():
		if node is Node2D and node.has_method("take_damage"):
			node.position.x+=5000;node.process_mode=Node.PROCESS_MODE_DISABLED
	for _i in range(12):await physics_frame
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var probe:=Probe.new();probe.owner_tree=self;probe.process_physics_priority=1000
	street.add_child(probe)
	key(KEY_D,true);await record(50,"walk");key(KEY_D,false)
	await record(8,"idle")
	await roll(1)
	await rush(1,"rush_right")
	await roll(-1)
	await rush(-1,"rush_left")
	key(KEY_SPACE,true);await record(2,"jump");key(KEY_SPACE,false)
	await record(6,"jump")
	key(KEY_SHIFT,true);await record(2,"tap");key(KEY_SHIFT,false)
	await record(18,"air_roll")
	await rush(1,"air_rush")
	await record(22,"land")
	var file:=FileAccess.open(OUTPUT+"/states.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"rendered":states,"physics":physics_samples},"\t"));file.close()
	print("Rendered roll and continuous thrust: ",index," frames, ",physics_samples.size()," physics samples")
	probe.set_physics_process(false);current_scene=null;street.queue_free();street=null
	for _i in range(6):await process_frame
	quit(0)
