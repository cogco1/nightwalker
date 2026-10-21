extends "res://tests/support/isolated_suite.gd"
const BOOT = preload("res://scenes/boot.tscn")
var checks := 0
var failures: Array[String] = []
var arena: Node2D
var capture := false

func _initialize() -> void:
	capture=OS.get_cmdline_user_args().has("--map-smoke")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for index in range(count):await physics_frame
	await process_frame

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func photo(label: String) -> void:
	if not capture:return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://evidence/whitebox_v07/")
	root.get_texture().get_image().save_png("res://evidence/whitebox_v07/"+label+".png")

func click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position=at
	motion.global_position=at
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new()
	event.position=at
	event.global_position=at
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(1)
	event=event.duplicate()
	event.pressed=false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	root.size=Vector2i(320,180)
	var boot := BOOT.instantiate()
	root.add_child(boot)
	current_scene=boot
	await frames(4)
	check(boot.has_node("EntryUI/EnterWhitebox"),"The default entry exposes the requested whitebox button")
	await photo("entry")
	await click(Vector2(160,128))
	await frames(8)
	check(is_instance_valid(current_scene) and current_scene.scene_file_path=="res://scenes/whitebox_test.tscn","Clicking the whitebox entry opens the real scene")
	if current_scene.scene_file_path!="res://scenes/whitebox_test.tscn":quit(1);return
	arena=current_scene
	check(arena.ready_for_test and arena.player.is_on_floor(),"The player spawns safely on the whitebox floor")
	check(arena.sniper.kind=="sniper" and arena.drone.get_script().resource_path=="res://scripts/enemies/cannon_drone.gd","Only the two requested enemy types spawn")
	check(arena.sniper.hero==arena.player and arena.drone.hero==arena.player,"Both enemies bind to the actual player")
	check(arena.session.get_node_or_null("ImpactBurst")==null and arena.player.fx.get_node_or_null("ChargedDraw")==null,"The map cannot instantiate deleted screen or sword-qi effects")
	for path in ["res://scenes/underground_hospital.tscn","res://scripts/levels/hospital/underground_hospital.gd",
		"res://scripts/enemies/guard.gd","res://scripts/enemies/gunner.gd","res://scripts/enemies/buyer.gd","res://scripts/enemies/doctor.gd",
		"res://scripts/levels/night_street/beam_drone.gd","res://scripts/levels/night_street/hover_target.gd"]:
		check(not FileAccess.file_exists(path),"Deleted map or enemy is absent: "+path)
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/enemy_animations_v01/manifest.json"))
	check(manifest.units.size()==2,"The art viewer cannot offer an unrequested enemy")
	await photo("whitebox_start")
	var origin: Vector2=arena.player.position
	key(KEY_D,true);await frames(12);key(KEY_D,false)
	check(arena.player.position.x>origin.x+5,"Normal movement works after entering through the UI")
	key(KEY_SPACE,true);await frames(1);key(KEY_SPACE,false);await frames(5)
	check(arena.player.position.y<origin.y-5,"The whitebox uses real jump physics")
	key(KEY_R,true);await frames(1);key(KEY_R,false);await frames(5)
	check(arena.vitals.hp==100 and arena.sniper.hp==12 and arena.drone.hp==12,"Reset restores the hero and both requested enemies")
	check(arena.get_children().filter(func(node: Node) -> bool: return node.name in ["Player","Sniper","CannonDrone"]).size()==3,"Reset does not duplicate combat actors")
	key(KEY_1,true);await frames(1);key(KEY_1,false)
	for index in range(180):
		if arena.sniper.phase==arena.sniper.Phase.MELEE and arena.sniper.phase_time>=0.25:break
		await frames(1)
	await photo("sniper_windup")
	for index in range(90):
		if arena.vitals.hp<100:break
		await frames(1)
	check(arena.vitals.hp<100,"The real sniper melee can damage the whitebox player")
	await photo("sniper_recovery")
	key(KEY_R,true);await frames(1);key(KEY_R,false);await frames(5)
	key(KEY_2,true);await frames(1);key(KEY_2,false);await frames(100)
	check(arena.drone.shot_count>0,"The real cannon drone attacks in its whitebox region")
	await photo("drone_combat")
	key(KEY_F1,true);await frames(1);key(KEY_F1,false);await frames(2)
	check(arena.session.settings_open and paused,"Settings can pause the whitebox")
	var before: float=arena.drone.phase_time
	await frames(10)
	check(arena.drone.phase_time==before,"No enemy attack advances while settings are open")
	key(KEY_ESCAPE,true);await frames(1);key(KEY_ESCAPE,false);await frames(3)
	check(not paused and not arena.session.settings_open,"Closing settings resumes the map")
	arena.get_node("WhiteboxUI/BackToEntry").pressed.emit()
	await frames(8)
	check(current_scene.scene_file_path=="res://scenes/boot.tscn" and not paused,"Return-to-entry clears combat state and reloads the button")
	await photo("returned_entry")
	key(KEY_ENTER,true);await frames(1);key(KEY_ENTER,false);await frames(10)
	check(current_scene.scene_file_path=="res://scenes/battlefield_run_test.tscn","The prologue button opens Factory/Sand from the repository")
	if current_scene.scene_file_path=="res://scenes/battlefield_run_test.tscn":
		var map: Node2D=current_scene
		check(map.ready_for_test and map.player.is_on_floor(),"The merged prologue has its real terrain and player")
		check(map.far_covers_view() and map.mid_covers_view() and map.near_covers_view() and map.foreground_covers_view(),"Far, middle, near and foreground layers are merged together and cover the camera")
		check(is_instance_valid(map.elevator) and is_instance_valid(map.ambient),"The existing lift and map animation survive integration")
		await photo("prologue_start")
		for x in [1540.0,3420.0,6020.0]:
			map.player.position=Vector2(x,map.ground_y_at(x)-1)
			map.player.velocity=Vector2.ZERO
			await frames(4)
			check(map.far_covers_view() and map.mid_covers_view() and map.near_covers_view() and map.foreground_covers_view(),"All map layers cover the camera at "+str(x))
			await photo("prologue_"+str(int(x)))
		map.get_node("PrologueUI/BackToEntry").pressed.emit()
		await frames(8)
		check(current_scene.has_node("EntryUI/EnterWhitebox"),"Returning from the prologue still offers the whitebox entrance")
	print(JSON.stringify({"suite":"map_entry_v07","checks":checks,"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
