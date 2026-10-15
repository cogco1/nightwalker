extends SceneTree

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
var arena: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}

func _initialize() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		push_error("Integration suite did not complete within 180 simulated seconds")
		quit(2)
	)
	call_deferred("run_tests")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func tick(count: int) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func release_keys() -> void:
	for code in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_J, KEY_SPACE, KEY_CAPSLOCK, KEY_TAB, KEY_R]:
		key(code, false)

func tap(code: Key) -> void:
	key(code, true)
	await tick(1)
	key(code, false)
	await tick(1)

func reset(mode: int) -> void:
	release_keys()
	arena.build_arena(mode)
	await tick(6)

func wait_stage(stage: int, limit := 75) -> bool:
	for _index in range(limit):
		if arena.player.combo_stage == stage:
			return true
		await tick(1)
	return false

func wait_attack_frame(frame_number: int, limit := 50) -> bool:
	for _index in range(limit):
		if arena.player.is_attacking and arena.player.sprite.frame >= frame_number:
			return true
		await tick(1)
	return false

func prepare_target(mode: int, direction := "right") -> void:
	await reset(mode)
	arena.player.position = Vector2(67, 83) if mode == 0 else Vector2(73, 160)
	arena.player.facing = direction
	await tick(2)

func animation_phase() -> float:
	var sprite: AnimatedSprite2D = arena.player.sprite
	return (sprite.frame + sprite.frame_progress) / float(sprite.sprite_frames.get_frame_count(sprite.animation))

func phase_distance(left: float, right: float) -> float:
	var difference := absf(left - right)
	return minf(difference, 1.0 - difference)

func face_signature(image: Image) -> Array[String]:
	# Skin colors under the hood, excluding brown coat tears and gloved hands.
	var signature: Array[String] = []
	for y in range(10,23):
		for x in range(10,38):
			var color := image.get_pixel(x,y)
			var rgb := Vector3i(roundi(color.r * 255),roundi(color.g * 255),roundi(color.b * 255))
			if color.a > 0.5 and rgb in [Vector3i(197,161,138),Vector3i(225,185,153)]:
				signature.append("%d,%d:%s" % [x,y,str(rgb)])
	return signature

func run_tests() -> void:
	arena = MAIN.instantiate()
	root.add_child(arena)
	await tick(8)
	for mapping in [[KEY_W,"move_up"], [KEY_S,"move_down"], [KEY_A,"move_left"], [KEY_D,"move_right"], [KEY_SPACE,"jump"], [KEY_CAPSLOCK,"run"], [KEY_J,"attack"]]:
		var event := InputEventKey.new()
		event.physical_keycode = mapping[0]
		check(InputMap.event_is_action(event, mapping[1]), "physical key mapping: " + mapping[1])
	await reset(0)
	check(arena.player.sprite.animation == "idle_down", "standing uses drawn breathing clip")
	check(arena.player.sprite.is_playing(), "breathing plays while standing")
	var idle_samples: Array[int] = []
	var idle_bob_samples: Array[int] = []
	var idle_visual_positions: Array[Vector2] = []
	var idle_start: Vector2 = arena.player.position
	for _sample in range(16):
		await tick(9)
		idle_samples.append(arena.player.sprite.frame)
		idle_bob_samples.append(arena.player.idle_bob_y)
		idle_visual_positions.append(arena.player.sprite.global_position + arena.player.sprite.offset + Vector2(24,42))
	check(idle_samples.max() >= 12, "idle advances through the loop without physics restarting it")
	check(idle_samples[0] != idle_samples[7], "breathing frame changes over time")
	check(arena.player.position.distance_to(idle_start) < 0.01, "breathing does not move collision root")
	check(idle_bob_samples.min() == 0 and idle_bob_samples.max() == 0, "drawn cloth breathing keeps whole-body sprite offset fixed")
	var idle_visual_is_correct := true
	for index in range(idle_visual_positions.size()):
		var desired := idle_start.round()
		idle_visual_is_correct = idle_visual_is_correct and idle_visual_positions[index].is_equal_approx(desired)
	check(idle_visual_is_correct, "idle does not bob whole sprite or move physics root")
	observations["idle_samples"] = idle_samples
	observations["idle_bob_samples"] = idle_bob_samples
	for movement in [[KEY_W,Vector2.UP,"up"], [KEY_S,Vector2.DOWN,"down"], [KEY_A,Vector2.LEFT,"left"], [KEY_D,Vector2.RIGHT,"right"]]:
		await reset(0)
		var start: Vector2 = arena.player.position
		key(movement[0], true)
		await tick(14)
		var difference: Vector2 = arena.player.position - start
		check(arena.player.idle_bob_y == 0, "idle visual offset clears during movement: " + movement[2])
		check(difference.dot(movement[1]) > 8.0, "top-down direction moves: " + movement[2])
		check(absf(difference.cross(movement[1])) < 0.1, "no unintended axis drift: " + movement[2])
		check(arena.player.facing == movement[2], "correct movement facing: " + movement[2])
		key(movement[0], false)
		await tick(8)
		check(arena.player.velocity.length() < 0.01, "braking settles promptly: " + movement[2])
		start = arena.player.position
		await tick(5)
		check(arena.player.position.distance_to(start) < 0.01, "stopped root remains stationary: " + movement[2])
		check(arena.player.sprite.animation == "idle_" + movement[2], "released movement returns to breathing: " + movement[2])
	await reset(0)
	key(KEY_D, true)
	await tick(12)
	var straight_speed: float = arena.player.velocity.length()
	await reset(0)
	key(KEY_D, true)
	key(KEY_W, true)
	await tick(12)
	check(absf(arena.player.velocity.length() - straight_speed) < 0.2, "diagonal walking speed normalized after acceleration")
	var diagonal_facing: String = arena.player.facing
	var diagonal_is_stable := true
	for _index in range(10):
		await tick(1)
		diagonal_is_stable = diagonal_is_stable and arena.player.facing == diagonal_facing
	check(diagonal_is_stable, "held diagonal does not oscillate character facing")
	await reset(0)
	var acceleration_samples: Array[float] = []
	key(KEY_D, true)
	for _index in range(6):
		await tick(1)
		acceleration_samples.append(arena.player.velocity.x)
	check(acceleration_samples[0] > 0.0 and acceleration_samples[0] < 30.0, "movement starts promptly with a short acceleration")
	var accelerates_monotonically := true
	for index in range(1, acceleration_samples.size()):
		accelerates_monotonically = accelerates_monotonically and acceleration_samples[index] >= acceleration_samples[index - 1]
	check(accelerates_monotonically, "acceleration approaches desired speed monotonically")
	key(KEY_D, false)
	var braking_samples: Array[float] = []
	for _index in range(6):
		await tick(1)
		braking_samples.append(arena.player.velocity.x)
	check(braking_samples[0] > 0.0 and braking_samples[-1] == 0.0, "release brakes briefly and reaches complete stop")
	observations["acceleration_samples"] = acceleration_samples
	observations["braking_samples"] = braking_samples
	await reset(0)
	key(KEY_D, true)
	await tick(21)
	var phase_before := animation_phase()
	key(KEY_CAPSLOCK, true)
	await tick(1)
	var phase_after := animation_phase()
	check(phase_distance(phase_before, phase_after) < 0.12, "walk-to-run keeps leg cycle phase")
	await tick(7)
	check(arena.player.is_running and arena.player.sprite.animation == "run_right", "held Caps runs")
	check(arena.player.velocity.x > 130.0, "running reaches faster speed")
	phase_before = animation_phase()
	key(KEY_CAPSLOCK, false)
	await tick(1)
	phase_after = animation_phase()
	check(phase_distance(phase_before, phase_after) < 0.12, "run-to-walk keeps leg cycle phase")
	await tick(6)
	check(not arena.player.is_running and absf(arena.player.velocity.x - 60.0) < 0.1, "Caps release settles to walking speed")
	phase_before = animation_phase()
	key(KEY_D, false)
	key(KEY_S, true)
	await tick(1)
	phase_after = animation_phase()
	check(phase_distance(phase_before, phase_after) < 0.12, "direction change preserves gait phase")
	observations["gait_transition_phase"] = {"before":phase_before,"after":phase_after}
	await reset(0)
	arena.player.position = Vector2(18, 130)
	key(KEY_A, true)
	await tick(25)
	check(arena.player.position.x > 13.5, "boundary blocks eased movement")
	await reset(0)
	arena.player.position = Vector2(110, 110)
	key(KEY_D, true)
	await tick(25)
	check(arena.player.position.x < 120.5, "obstacle blocks eased movement")
	await prepare_target(0)
	await tap(KEY_J)
	check(arena.player.is_attacking and arena.player.combo_stage == 1, "single J tap begins first strike")
	check(arena.player.idle_bob_y == 0, "idle visual offset clears when attacking")
	check(arena.player.sprite.offset == Vector2(-32,-52) and arena.player.sprite.scale == Vector2.ONE, "first attack canvas uses padded pivot without scaling character")
	check(arena.targets[0].hp == 3, "anticipation frames do not hit")
	check(not arena.player.begin_attack(), "begin_attack cannot restart active strike")
	await tick(36)
	check(arena.targets[0].hp == 2 and arena.hits == 1, "single strike damages target once")
	check(not arena.player.is_attacking and arena.player.combo_stage == 0, "single strike settles without automatic second strike")
	check(arena.player.sprite.animation == "idle_right", "strike recovery returns to breathing")
	await prepare_target(0)
	key(KEY_J, true)
	await tick(95)
	check(arena.targets[0].hp == 2 and arena.hits == 1, "holding attack does not create an infinite chain")
	check(not arena.player.is_attacking, "held attack finishes after one strike")
	await prepare_target(0)
	await tap(KEY_J)
	await tap(KEY_J)
	await tap(KEY_J)
	check(arena.player.queued_attack, "quick repeated taps retain one intended follow-up")
	check(await wait_stage(2), "quick double tap chains into second strike")
	await tick(35)
	check(arena.targets[0].hp == 1 and arena.hits == 2 and arena.player.combo_stage == 0, "multiple taps in first strike queue one second strike, not an entire automatic chain")
	check(not arena.player.queued_attack and arena.player.attack_buffer_left <= 0.0, "consumed combo input is cleared")
	await prepare_target(0)
	await tap(KEY_J)
	await tap(KEY_J)
	check(await wait_stage(2), "quick input reaches second stage for third-stage test")
	await tap(KEY_J)
	check(await wait_stage(3), "fresh quick tap in second stage chains third")
	await tick(35)
	check(arena.targets[0].hp == 0 and arena.hits == 3, "quick deliberate taps produce three distinct strikes")
	await prepare_target(0)
	await tap(KEY_J)
	check(await wait_stage(0), "single strike enters brief recovery")
	check(arena.player._recovery_left > 0.0, "terminal pose has a brief recovery")
	await tap(KEY_J)
	check(arena.player.pending_new_attack or arena.player.is_attacking, "fresh tap during brief recovery is retained")
	check(await wait_stage(1), "recovery tap starts one new first strike")
	await tick(38)
	check(arena.targets[0].hp == 1 and arena.hits == 2, "buffered recovery tap damages once in a new chain")
	for mode in range(2):
		await prepare_target(mode)
		await tap(KEY_J)
		check(await wait_attack_frame(9), "first strike reaches chain input window, mode " + str(mode))
		await tap(KEY_J)
		check(arena.player.queued_attack, "second tap queues one follow-up, mode " + str(mode))
		check(await wait_stage(2), "first strike flows into second, mode " + str(mode))
		check(arena.player.sprite.animation == "attack2_right", "second strike uses distinct animation, mode " + str(mode))
		check(await wait_attack_frame(10), "second strike reaches chain input window, mode " + str(mode))
		await tap(KEY_J)
		check(await wait_stage(3), "second strike flows into third, mode " + str(mode))
		check(arena.player.sprite.animation == "attack3_right", "third strike uses distinct animation, mode " + str(mode))
		await tap(KEY_J)
		check(not arena.player.queued_attack, "third strike refuses fourth buffer, mode " + str(mode))
		await tick(40)
		check(arena.targets[0].hp == 0 and arena.hits == 3, "three-hit chain hits same target once per strike, mode " + str(mode))
		check(arena.defeated == 1 and arena.targets[0].body_shape.disabled, "combo defeat disables target collider, mode " + str(mode))
		check(arena.player.combo_stage == 0 and not arena.player.is_attacking, "three-hit chain ends, mode " + str(mode))
	await prepare_target(0)
	await tap(KEY_J)
	check(await wait_attack_frame(14), "first strike reaches late recovery frame")
	await tap(KEY_J)
	check(await wait_stage(2), "late input near end is retained")
	await prepare_target(0)
	await tap(KEY_J)
	key(KEY_A, true)
	await tick(10)
	check(arena.player.facing == "right" and arena.player.attack_direction == Vector2.RIGHT, "movement input cannot turn active strike")
	await wait_attack_frame(9)
	await tap(KEY_J)
	check(await wait_stage(2), "locked-facing strike still chains")
	check(arena.player.facing == "right", "facing remains locked between strike stages")
	await prepare_target(0, "left")
	await tap(KEY_J)
	await tick(40)
	check(arena.targets[0].hp == 3, "attack facing away misses target")
	await prepare_target(0)
	arena.player.position = Vector2(48,83)
	await tick(2)
	await tap(KEY_J)
	await tick(40)
	check(arena.targets[0].hp == 2, "wider drawn swing reaches target from beyond previous short-strike distance")
	await prepare_target(0)
	arena.player.position = Vector2(35,83)
	await tick(2)
	await tap(KEY_J)
	await tick(40)
	check(arena.targets[0].hp == 3, "wider swing still has a bounded reach")
	await prepare_target(0)
	arena.add_wall(Rect2(79, 69, 3, 23))
	await tick(3)
	await tap(KEY_J)
	await tick(40)
	check(arena.targets[0].hp == 3, "wall blocks attack damage")
	await prepare_target(0)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	await tick(2)
	check(arena.player.is_attacking, "left mouse starts strike")
	mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = false
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	await tick(40)
	check(arena.targets[0].hp == 2, "left mouse strike damages once")
	await reset(1)
	check(absf(arena.player.position.y - 160.0) < 0.2, "side view grounded at floor")
	key(KEY_D, true)
	await tick(14)
	check(arena.player.position.x > 51.0 and arena.player.facing == "right", "side view right movement")
	key(KEY_D, false)
	key(KEY_A, true)
	await tick(20)
	check(arena.player.velocity.x < -59.0 and arena.player.facing == "left", "side view left reverses smoothly")
	release_keys()
	await tick(10)
	var grounded_position: Vector2 = arena.player.position
	await tap(KEY_W)
	await tick(6)
	check(arena.player.position.distance_to(grounded_position) < 0.1, "W does not cause side view flight")
	key(KEY_S, true)
	await tick(18)
	check(arena.player.is_crouching and arena.player.body_shape.shape.size.y == 14.0, "S crouches and reduces collider")
	check(arena.player.sprite.animation == "crouch_left", "S uses crouching clip")
	await tap(KEY_SPACE)
	check(arena.player.is_on_floor(), "Space while holding S does not jump")
	key(KEY_S, false)
	await tick(1)
	await tap(KEY_SPACE)
	check(arena.player.velocity.y < -100.0, "S release then Space jumps immediately")
	await tick(11)
	check(arena.player.position.y < 133.0, "jump rises to expected height")
	check(arena.player.sprite.animation == "jump_left", "airborne uses jump animation")
	var before_velocity: float = arena.player.velocity.y
	await tap(KEY_SPACE)
	check(arena.player.velocity.y > before_velocity, "jump button cannot reset velocity in air")
	await tick(50)
	check(arena.player.is_on_floor() and absf(arena.player.position.y - 160.0) < 0.2, "jump lands without floating")
	await reset(1)
	arena.player.position = Vector2(185, 160)
	await tick(3)
	key(KEY_D, true)
	await tick(14)
	check(arena.player.position.x < 190.5, "standing blocked by low tunnel")
	key(KEY_S, true)
	await tick(75)
	check(arena.player.position.x > 207.0 and arena.player.is_crouching, "crouching traverses low tunnel")
	key(KEY_D, false)
	key(KEY_S, false)
	await tick(10)
	check(arena.player.is_crouching and not arena.player.can_stand(), "head clearance keeps player crouched under tunnel")
	key(KEY_D, true)
	await tick(110)
	key(KEY_D, false)
	await tick(15)
	check(not arena.player.is_crouching and arena.player.can_stand(), "player stands after clearing tunnel")
	await prepare_target(1)
	key(KEY_S, true)
	await tick(18)
	await tap(KEY_J)
	await tick(40)
	check(arena.targets[0].hp == 2 and arena.hits == 1, "crouching attack remains one strike")
	check(arena.player.is_crouching and arena.player.sprite.animation == "crouch_right", "crouched strike returns to crouch")
	await reset(1)
	arena.player.position = Vector2(110, 160)
	await tick(3)
	key(KEY_D, true)
	await tap(KEY_SPACE)
	await tick(24)
	key(KEY_D, false)
	await tick(35)
	check(arena.player.is_on_floor() and absf(arena.player.position.y - 122.0) < 0.3, "jump reaches elevated platform")
	await reset(1)
	key(KEY_D, true)
	key(KEY_CAPSLOCK, true)
	await tick(10)
	check(arena.player.is_running and arena.player.velocity.x > 130.0, "side running reaches run speed")
	key(KEY_CAPSLOCK, false)
	await tick(7)
	check(not arena.player.is_running and absf(arena.player.velocity.x - 60.0) < 0.1, "side Caps release returns to walking")
	await prepare_target(1)
	await tap(KEY_J)
	await wait_attack_frame(9)
	await tap(KEY_J)
	check(arena.player.queued_attack, "queued strike exists before view switch")
	await tap(KEY_TAB)
	await tick(4)
	check(arena.view_mode == 0 and not arena.player.is_attacking and arena.player.combo_stage == 0, "Tab changes view and clears active chain")
	check(not arena.player.queued_attack and arena.player.attack_buffer_left <= 0.0 and not arena.player.pending_new_attack, "Tab clears buffered attack")
	await tap(KEY_J)
	await wait_attack_frame(9)
	await tap(KEY_J)
	await tap(KEY_R)
	await tick(4)
	check(arena.hits == 0 and arena.targets[0].hp == 3, "R restores training target state")
	check(not arena.player.is_attacking and not arena.player.queued_attack and not arena.player.pending_new_attack and arena.player.combo_stage == 0, "R clears chain and input buffer")
	var clip_count := 0
	var frame_count := 0
	for path in ["res://assets/top_down.tres", "res://assets/side_view.tres"]:
		var frames := load(path) as SpriteFrames
		var directions := ["up", "down", "left", "right"] if path.ends_with("top_down.tres") else ["left", "right"]
		for direction in directions:
			for action in ["idle", "attack1", "attack2", "attack3"]:
				check(frames.has_animation(action + "_" + direction), "required new clip: " + action + "_" + direction)
		for animation in frames.get_animation_names():
			clip_count += 1
			frame_count += frames.get_frame_count(animation)
			check(frames.get_frame_count(animation) == 16, "16-frame clip: " + animation)
			var first_texture: Texture2D = frames.get_frame_texture(animation, 0)
			var expected_size := Vector2(48,48)
			if String(animation).begins_with("attack"):
				expected_size = Vector2(80,64) if String(animation) in ["attack3_left","attack3_right"] else Vector2(64,64)
			check(first_texture != null and first_texture.get_size() == expected_size, "native canvas matches action padding: " + animation)
			if animation.begins_with("idle_"):
				check(frames.get_animation_loop(animation) and is_equal_approx(frames.get_animation_speed(animation), 8.0), "breathing loops at 8fps: " + animation)
				var idle_pixels: PackedByteArray = first_texture.get_image().get_data()
				var idle_has_drawn_motion := false
				var idle_face_is_fixed := true
				var first_face := face_signature(first_texture.get_image())
				for index in range(frames.get_frame_count(animation)):
					var drawing := frames.get_frame_texture(animation,index).get_image()
					idle_has_drawn_motion = idle_has_drawn_motion or drawing.get_data() != idle_pixels
					idle_face_is_fixed = idle_face_is_fixed and face_signature(drawing) == first_face
				check(idle_has_drawn_motion, "cloth/shoulder breathing is drawn inside sprite: " + animation)
				check(idle_face_is_fixed, "breathing keeps exposed face pixels fixed: " + animation)
				check(first_face.size() <= 3 and (first_face.is_empty() if String(animation).ends_with("_up") else not first_face.is_empty()), "hood exposes only a few face pixels: " + animation)
	check(clip_count == 48 and frame_count == 768, "48 clips and 768 imported frames")
	check(root.content_scale_size == Vector2i(320,180), "320x180 native viewport")
	check(arena.player.sprite.scale == Vector2.ONE, "character native scale")
	check(arena.player.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST or arena.player.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "nearest pixel filtering")
	check((arena.player.global_position + arena.player.sprite.position).is_equal_approx((arena.player.global_position + arena.player.sprite.position).round()), "rendered character on global integer pixel grid")
	observations["clips"] = clip_count
	observations["frames"] = frame_count
	release_keys()
	var result := {"checks":checks, "failures":failures, "observations":observations, "engine":Engine.get_version_info()["string"], "status":"passed" if failures.is_empty() else "failed"}
	var file := FileAccess.open("res://evidence/test_results_v05.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
