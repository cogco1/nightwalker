extends SceneTree
const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
var arena: Node2D
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run_tests")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
		push_error(text)
func tick(n: int) -> void:
	for i in range(n): await physics_frame
	await process_frame
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code;event.keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func release_keys() -> void:
	for code in [KEY_W,KEY_S,KEY_A,KEY_D,KEY_J,KEY_SPACE,KEY_CAPSLOCK,KEY_TAB,KEY_R]: key(code,false)
func hold(code: Key,n: int) -> void:
	key(code,true);await tick(n);key(code,false);await tick(1)
func reset(mode: int) -> void:
	release_keys();arena.build_arena(mode);await tick(4)
func attack() -> void:
	await hold(KEY_J,1);await tick(29)
func run_tests() -> void:
	arena=MAIN.instantiate();root.add_child(arena);await tick(4)
	for mapping in [[KEY_W,"move_up"],[KEY_S,"move_down"],[KEY_A,"move_left"],[KEY_D,"move_right"],[KEY_SPACE,"jump"],[KEY_CAPSLOCK,"run"],[KEY_J,"attack"]]:
		var event := InputEventKey.new();event.physical_keycode=mapping[0]
		check(InputMap.event_is_action(event,mapping[1]),"physical mapping "+mapping[1])
	for movement in [[KEY_W,Vector2.UP,"up"],[KEY_S,Vector2.DOWN,"down"],[KEY_A,Vector2.LEFT,"left"],[KEY_D,Vector2.RIGHT,"right"]]:
		await reset(0)
		var start: Vector2=arena.player.position
		await hold(movement[0],12)
		var diff: Vector2=arena.player.position-start
		check(diff.dot(movement[1])>10,"top movement "+movement[2])
		check(absf(diff.cross(movement[1]))<0.1,"no axis drift "+movement[2])
		check(arena.player.facing==movement[2],"facing "+movement[2])
		start=arena.player.position;await tick(4)
		check(arena.player.position.distance_to(start)<0.1,"release stops "+movement[2])
	await reset(0)
	var straight_start: Vector2=arena.player.position
	key(KEY_D,true);await tick(12)
	var straight_distance: float=arena.player.position.distance_to(straight_start)
	await reset(0)
	straight_start=arena.player.position
	key(KEY_D,true);key(KEY_W,true);await tick(12)
	check(absf(arena.player.position.distance_to(straight_start)-straight_distance)<1.0,"diagonal speed normalized")
	await reset(0)
	key(KEY_D,true);key(KEY_CAPSLOCK,true);await tick(12)
	check(arena.player.is_running and arena.player.sprite.animation=="run_right","Caps hold runs")
	check(arena.player.velocity.x>130,"run speed")
	key(KEY_CAPSLOCK,false);await tick(2)
	check(not arena.player.is_running and arena.player.velocity.x==60,"Caps release restores walk")
	await reset(0)
	arena.player.position=Vector2(18,130);await hold(KEY_A,25)
	check(arena.player.position.x>13.5,"boundary blocks motion")
	arena.player.position=Vector2(110,110);await hold(KEY_D,25)
	check(arena.player.position.x<120.5,"obstacle blocks motion")
	await reset(0)
	arena.player.position=Vector2(67,83);await hold(KEY_D,1)
	key(KEY_J,true);await tick(2)
	check(arena.player.is_attacking,"J begins attack")
	check(arena.targets[0].hp==3,"anticipation no hit")
	check(not arena.player.begin_attack(),"attack cannot restart")
	key(KEY_J,false);await tick(29)
	check(arena.targets[0].hp==2 and arena.hits==1,"one hit per attack")
	check(not arena.player.is_attacking,"attack finishes")
	await attack();await attack();await tick(2)
	check(arena.targets[0].hp==0 and arena.defeated==1,"three hits defeat")
	check(arena.targets[0].body_shape.disabled,"defeated collider disabled")
	await reset(0)
	arena.player.position=Vector2(67,83);await hold(KEY_A,1);await attack()
	check(arena.targets[0].hp==3,"wrong direction misses")
	await reset(0)
	arena.player.position=Vector2(67,83);await hold(KEY_D,1)
	arena.add_wall(Rect2(79,69,3,23));await tick(2);await attack()
	check(arena.targets[0].hp==3,"wall blocks attack")
	await reset(0)
	arena.player.position=Vector2(67,83);await hold(KEY_D,1)
	var mouse := InputEventMouseButton.new()
	mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true
	Input.parse_input_event(mouse);Input.flush_buffered_events();await tick(2)
	check(arena.player.is_attacking,"left mouse begins attack")
	mouse=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=false
	Input.parse_input_event(mouse);Input.flush_buffered_events();await tick(29)
	check(arena.targets[0].hp==2,"left mouse hits")
	await reset(1)
	check(absf(arena.player.position.y-160)<0.2,"side floor")
	await hold(KEY_D,12)
	check(arena.player.position.x>52 and arena.player.facing=="right","side right")
	await hold(KEY_A,12)
	check(arena.player.position.x<44 and arena.player.facing=="left","side left")
	var before: Vector2=arena.player.position
	await hold(KEY_W,6)
	check(arena.player.position.distance_to(before)<0.1,"W no side flight")
	key(KEY_S,true);await tick(17)
	check(arena.player.is_crouching and arena.player.body_shape.shape.size.y==14,"crouch shrinks collider")
	check(arena.player.sprite.animation=="crouch_left","crouch animation")
	await hold(KEY_SPACE,4)
	check(arena.player.is_on_floor(),"no jump while crouched")
	key(KEY_S,false);await tick(9)
	check(not arena.player.is_crouching and arena.player.body_shape.shape.size.y==26,"stand after S release")
	await hold(KEY_SPACE,1);await tick(12)
	check(arena.player.position.y<133,"Space jumps")
	check(arena.player.sprite.animation=="jump_left","jump animation")
	var velocity_before: float=arena.player.velocity.y
	await hold(KEY_SPACE,1)
	check(arena.player.velocity.y>velocity_before,"no midair jump reset")
	await tick(45)
	check(arena.player.is_on_floor() and absf(arena.player.position.y-160)<0.2,"jump lands")
	await reset(1)
	arena.player.position=Vector2(185,160);await tick(2)
	key(KEY_D,true);await tick(12)
	check(arena.player.position.x<190.5,"stand blocked by tunnel")
	key(KEY_S,true);await tick(75)
	check(arena.player.position.x>207 and arena.player.is_crouching,"crouch traverses tunnel")
	key(KEY_D,false);key(KEY_S,false);await tick(8)
	check(arena.player.is_crouching and not arena.player.can_stand(),"head clearance prevents standing")
	key(KEY_D,true);await tick(110);key(KEY_D,false);await tick(10)
	check(not arena.player.is_crouching and arena.player.can_stand(),"stands outside tunnel")
	await reset(1)
	arena.player.position=Vector2(73,160);await hold(KEY_D,1)
	key(KEY_S,true);await tick(16);await attack()
	check(arena.targets[0].hp==2,"crouched attack")
	await reset(1)
	arena.player.position=Vector2(73,160);await hold(KEY_D,1);await attack()
	check(arena.targets[0].hp==2,"side right attack")
	await reset(1)
	arena.player.position=Vector2(125,160);await hold(KEY_A,1);await attack()
	check(arena.targets[0].hp==2,"side left attack")
	await reset(1)
	arena.player.position=Vector2(110,160);await tick(2)
	key(KEY_D,true);await hold(KEY_SPACE,1);await tick(35)
	key(KEY_D,false);await tick(8)
	check(arena.player.is_on_floor() and absf(arena.player.position.y-122)<0.3,"jump reaches raised platform")
	await reset(1)
	key(KEY_D,true);key(KEY_CAPSLOCK,true);await tick(6)
	check(arena.player.is_running and arena.player.sprite.animation=="run_right","side run animation")
	key(KEY_CAPSLOCK,false);await tick(2)
	check(not arena.player.is_running and arena.player.velocity.x==60,"side Caps release restores walk")
	await reset(1)
	key(KEY_J,true);await tick(2);key(KEY_TAB,true);await tick(2)
	key(KEY_TAB,false);key(KEY_J,false);await tick(3)
	check(arena.view_mode==0 and not arena.player.is_attacking,"switch during attack")
	key(KEY_R,true);await tick(2);key(KEY_R,false);await tick(2)
	check(arena.hits==0 and arena.targets[0].hp==3,"R resets")
	var clips := 0
	var count := 0
	for path in ["res://assets/top_down.tres","res://assets/side_view.tres"]:
		var frames := load(path) as SpriteFrames
		for animation in frames.get_animation_names():
			clips+=1;count+=frames.get_frame_count(animation)
			check(frames.get_frame_count(animation)==16,"16 frames "+animation)
			check(frames.get_frame_texture(animation,0).get_size()==Vector2(48,48),"48px "+animation)
	check(clips==24 and count==384,"24 clips 384 frames")
	check(root.content_scale_size==Vector2i(320,180),"320 x 180 viewport")
	check(arena.player.sprite.scale==Vector2.ONE,"native sprite scale")
	release_keys()
	var result={"checks":checks,"failures":failures,"engine":Engine.get_version_info()["string"],"status":"passed" if failures.is_empty() else "failed"}
	var file := FileAccess.open("res://evidence/test_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
