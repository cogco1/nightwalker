extends "res://tests/support/isolated_suite.gd"

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
var arena: Node2D
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var hit_stop_events := 0
var completed_stops: Array[int] = []
var completed_stop_durations: Array[float] = []
const TARGET = preload("res://tests/fixtures/training_target.gd")

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
	mouse(false)
	for code in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_J, KEY_SHIFT, KEY_SPACE, KEY_CAPSLOCK, KEY_TAB, KEY_R]:
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
	arena.player.critical_roll_override = 0.99
	# Keep base damage fixtures at their original three HP; actual nine-HP side targets
	# are exercised by the dedicated air-combat suite.
	for index in range(arena.targets.size()):
		if index < 3:
			arena.targets[index].max_hp = 3
			arena.targets[index].hp = 3
		else:
			arena.targets[index].position = Vector2(282+index,160)

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
	# Keep once-per-target base regression fixtures isolated; new swept tests
	# exercise all additional/default targets and more than16 colliders separately.
	for index in range(3,arena.targets.size()):
		arena.targets[index].position = Vector2(282 + index,160)
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
	var pivot := Vector2i(image.get_width()/2,image.get_height()-12) if image.get_height() >= 64 else Vector2i(24,42)
	for y in range(pivot.y-32,pivot.y-19):
		for x in range(pivot.x-14,pivot.x+14):
			var color := image.get_pixel(x,y)
			var rgb := Vector3i(roundi(color.r * 255),roundi(color.g * 255),roundi(color.b * 255))
			if color.a > 0.5 and rgb in [Vector3i(197,161,138),Vector3i(225,185,153)]:
				signature.append("%d,%d:%s" % [x,y,str(rgb)])
	return signature

func run_tests() -> void:
	# Exercise the current default mouse controls independently of saved bindings.
	preload("res://scripts/core/controls.gd").install(false)
	arena = MAIN.instantiate()
	root.add_child(arena)
	arena.hit_stop_started.connect(func() -> void: hit_stop_events += 1)
	arena.hit_stop_finished.connect(func(frames: int) -> void:
		completed_stops.append(frames)
		completed_stop_durations.append(arena.hit_stop_elapsed_seconds)
	)
	await tick(8)
	for mapping in [[KEY_W,"move_up"], [KEY_S,"move_down"], [KEY_A,"move_left"], [KEY_D,"move_right"], [KEY_SPACE,"jump"], [KEY_CAPSLOCK,"run"]]:
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
	await mouse_tap()
	check(arena.player.is_attacking and arena.player.combo_stage == 1, "single mouse tap begins first strike")
	check(arena.player.idle_bob_y == 0, "idle visual offset clears when attacking")
	check(arena.player.sprite.offset == Vector2(-32,-52) and arena.player.sprite.scale == Vector2.ONE, "first attack canvas uses padded pivot without scaling character")
	check(arena.targets[0].hp == 3, "anticipation frames do not hit")
	check(not arena.player.begin_attack(), "begin_attack cannot restart active strike")
	await tick(36)
	check(arena.targets[0].hp == 2 and arena.hits == 1, "single strike damages target once")
	check(not arena.player.is_attacking and arena.player.combo_stage == 0, "single strike settles without automatic second strike")
	check(arena.player.sprite.animation == "idle_right", "strike recovery returns to breathing")
	await prepare_target(0)
	mouse(true)
	await tick(95)
	check(arena.targets[0].hp == 2 and arena.hits == 1, "holding attack does not create an infinite chain")
	check(not arena.player.is_attacking, "held attack finishes after one strike")
	await prepare_target(0)
	await mouse_tap()
	await mouse_tap()
	await mouse_tap()
	check(arena.player.queued_attack, "quick repeated taps retain one intended follow-up")
	check(await wait_stage(2), "quick double tap chains into second strike")
	await tick(35)
	check(arena.targets[0].hp == 1 and arena.hits == 2 and arena.player.combo_stage == 0, "multiple taps in first strike queue one second strike, not an entire automatic chain")
	check(not arena.player.queued_attack and arena.player.attack_buffer_left <= 0.0, "consumed combo input is cleared")
	await prepare_target(0)
	await mouse_tap()
	await mouse_tap()
	check(await wait_stage(2), "quick input reaches second stage for third-stage test")
	await mouse_tap()
	check(await wait_stage(3), "fresh quick tap in second stage chains third")
	await tick(35)
	check(arena.targets[0].hp == 0 and arena.hits == 3, "quick deliberate taps produce three distinct strikes")
	await prepare_target(0)
	await mouse_tap()
	check(await wait_stage(0), "single strike enters brief recovery")
	check(arena.player._recovery_left > 0.0, "terminal pose has a brief recovery")
	await mouse_tap()
	check(arena.player.pending_new_attack or arena.player.is_attacking, "fresh tap during brief recovery is retained")
	check(await wait_stage(1), "recovery tap starts one new first strike")
	await tick(38)
	check(arena.targets[0].hp == 1 and arena.hits == 2, "buffered recovery tap damages once in a new chain")
	for mode in range(2):
		await prepare_target(mode)
		await mouse_tap()
		check(await wait_attack_frame(9), "first strike reaches chain input window, mode " + str(mode))
		await mouse_tap()
		check(arena.player.queued_attack, "second tap queues one follow-up, mode " + str(mode))
		check(await wait_stage(2), "first strike flows into second, mode " + str(mode))
		check(arena.player.sprite.animation == "attack2_right", "second strike uses distinct animation, mode " + str(mode))
		check(await wait_attack_frame(10), "second strike reaches chain input window, mode " + str(mode))
		await mouse_tap()
		check(await wait_stage(3), "second strike flows into third, mode " + str(mode))
		check(arena.player.sprite.animation == "attack3_right", "third strike uses distinct animation, mode " + str(mode))
		await mouse_tap()
		if mode == 0:
			check(not arena.player.queued_attack, "third strike refuses fourth buffer, mode " + str(mode))
		else:
			# The side-view light string goes on to the thrust and the spin (tests/test_rhythm_combat.gd).
			check(arena.player.queued_attack, "third strike buffers the fourth-hit thrust, mode " + str(mode))
		await tick(40)
		check(arena.targets[0].hp == 0 and arena.hits == 3, "three-hit chain hits same target once per strike, mode " + str(mode))
		check(arena.defeated == 1 and arena.targets[0].body_shape.disabled, "combo defeat disables target collider, mode " + str(mode))
		for _index in range(60):
			if not arena.player.is_attacking:
				break
			await tick(1)
		check(arena.player.combo_stage == 0 and not arena.player.is_attacking, "the light string ends, mode " + str(mode))
	await prepare_target(0)
	await mouse_tap()
	check(await wait_attack_frame(14), "first strike reaches late recovery frame")
	await mouse_tap()
	check(await wait_stage(2), "late input near end is retained")
	await prepare_target(0)
	await mouse_tap()
	key(KEY_A, true)
	await tick(10)
	check(arena.player.facing == "right" and arena.player.attack_direction == Vector2.RIGHT, "movement input cannot turn active strike")
	await wait_attack_frame(9)
	await mouse_tap()
	check(await wait_stage(2), "locked-facing strike still chains")
	check(arena.player.facing == "right", "facing remains locked between strike stages")
	await prepare_target(0, "left")
	await mouse_tap()
	await tick(40)
	check(arena.targets[0].hp == 3, "attack facing away misses target")
	await prepare_target(0)
	arena.player.position = Vector2(48,83)
	await tick(2)
	await mouse_tap()
	await tick(40)
	check(arena.targets[0].hp == 2, "wider drawn swing reaches target from beyond previous short-strike distance")
	await prepare_target(0)
	arena.player.position = Vector2(35,83)
	await tick(2)
	await mouse_tap()
	await tick(40)
	check(arena.targets[0].hp == 3, "wider swing still has a bounded reach")
	await prepare_target(0)
	arena.add_wall(Rect2(79, 69, 3, 23))
	await tick(3)
	await mouse_tap()
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
	check(arena.player.velocity.y < before_velocity and arena.player._jumps_used == 2, "second fresh Space performs one air jump")
	await tick(65)
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
	await mouse_tap()
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
	await mouse_tap()
	await wait_attack_frame(9)
	await mouse_tap()
	check(arena.player.queued_attack, "queued strike exists before view switch")
	await tap(KEY_TAB)
	await tick(4)
	check(arena.view_mode == 0 and not arena.player.is_attacking and arena.player.combo_stage == 0, "Tab changes view and clears active chain")
	check(not arena.player.queued_attack and arena.player.attack_buffer_left <= 0.0 and not arena.player.pending_new_attack, "Tab clears buffered attack")
	await mouse_tap()
	await wait_attack_frame(9)
	await mouse_tap()
	await tap(KEY_R)
	await tick(4)
	check(arena.hits == 0 and arena.targets[0].hp == 3, "R restores training target state")
	check(not arena.player.is_attacking and not arena.player.queued_attack and not arena.player.pending_new_attack and arena.player.combo_stage == 0, "R clears chain and input buffer")
	await run_feature_tests()
	await run_contact_tests()
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
			if path.ends_with("side_view.tres"):
				expected_size = Vector2(80,80) if (String(animation).begins_with("air_") and not String(animation).begins_with("air_dash_stab_")) or String(animation).begins_with("dive_slash_") else Vector2(112,96)
			elif String(animation).begins_with("attack"):
				expected_size = Vector2(80,64) if String(animation) in ["attack3_left","attack3_right"] else Vector2(64,64)
			elif String(animation).begins_with("rising_slash_"):
				expected_size = Vector2(80,80)
			elif String(animation).begins_with("dash_stab_"):
				expected_size = Vector2(80,64)
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
	check(clip_count == 64 and frame_count == 1024, "64 clips and1024 imported frames including separate aerial and dive poses")
	check(root.content_scale_size == Vector2i(320,180), "320x180 native viewport")
	check(arena.player.sprite.scale == Vector2.ONE, "character native scale")
	check(arena.player.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST or arena.player.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "nearest pixel filtering")
	check((arena.player.global_position + arena.player.sprite.position).is_equal_approx((arena.player.global_position + arena.player.sprite.position).round()), "rendered character on global integer pixel grid")
	observations["clips"] = clip_count
	observations["frames"] = frame_count
	release_keys()
	var result := {"checks":checks, "failures":failures, "observations":observations, "engine":Engine.get_version_info()["string"], "status":"passed" if failures.is_empty() else "failed"}
	var file := FileAccess.open("res://evidence/test_results_v07.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)


func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse_tap() -> void:
	mouse(true)
	await tick(1)
	mouse(false)
	await tick(1)

func double_tap(code: Key) -> void:
	await tap(code)
	await tick(3)
	await tap(code)

func dash_press(code: Key) -> void:
	key(code,true)
	await tap(KEY_SHIFT)
	key(code,false)

func observe_hits() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	arena.player.hit_resolved.connect(func(target: Node, damage: int, critical: bool, kind: String) -> void:
		events.append({"target_id":target.get_instance_id(),"damage":damage,"critical":critical,"kind":kind})
	)
	return events

func third_stage() -> void:
	await mouse_tap()
	await wait_attack_frame(9)
	await mouse_tap()
	check(await wait_stage(2), "feature fixture reaches combo stage2")
	await wait_attack_frame(9)
	await mouse_tap()
	check(await wait_stage(3), "feature fixture reaches combo stage3")

func clear_targets() -> void:
	for target in arena.targets:
		arena.world.remove_child(target)
		target.queue_free()
	arena.targets.clear()
	await tick(2)

func add_target(point: Vector2, health := 6) -> CharacterBody2D:
	var target := TARGET.new()
	target.side_view = arena.view_mode == 1
	target.max_hp = health
	target.position = point
	target.destroyed.connect(arena._on_target_destroyed)
	arena.world.add_child(target)
	arena.targets.append(target)
	return target

func run_feature_tests() -> void:
	var critical_cases: Array[Dictionary] = []
	for roll in [0.0,0.299999,0.30,0.999999]:
		await prepare_target(0)
		arena.targets[0].max_hp = 12
		arena.targets[0].hp = 12
		arena.player.critical_roll_override = roll
		var events := observe_hits()
		var stop_before := hit_stop_events
		var completion_start := completed_stops.size()
		await third_stage()
		check(arena.player.critical_rolls == 1, "third stage rolls exactly once: " + str(roll))
		check(is_equal_approx(arena.player.last_critical_roll,roll), "forced critical roll seam: " + str(roll))
		check(arena.player.stage_is_critical == (roll < 0.30), "strict30percent threshold: " + str(roll))
		await tick(42)
		check(events.size() == 3, "each stage damages target once: " + str(roll))
		if events.size() == 3:
			check(events[0]["damage"] == 1 and events[1]["damage"] == 1 and not events[0]["critical"] and not events[1]["critical"], "first two stages never crit: " + str(roll))
			check(events[2]["damage"] == (3 if roll < 0.30 else 1), "third damage is3x only on crit: " + str(roll))
		check(arena.targets[0].hp == (7 if roll < 0.30 else 9), "critical health delta matches damage: " + str(roll))
		check(hit_stop_events - stop_before == 3, "one contact stop per confirmed attack stage: " + str(roll))
		check(completed_stops.slice(completion_start) == [4,4,6 if roll < 0.30 else 4], "normal and critical contact stop arbitration: " + str(roll))
		check(not arena.hit_stop_active and not paused, "hit stop resumes gameplay: " + str(roll))
		if roll < 0.30:
			check(arena.hit_stop_displayed_frames == 6, "headless critical stop completes six display steps")
		check(not arena.player.stage_is_critical, "critical stage flag clears at recovery")
		critical_cases.append({"roll":roll,"health":arena.targets[0].hp,"rolls":arena.player.critical_rolls,"events":events,"stop_events":hit_stop_events-stop_before})
	await prepare_target(1)
	arena.targets[0].max_hp = 24
	arena.targets[0].hp = 24
	arena.player.attack_damage = 2
	arena.player.critical_roll_override = 0.0
	var events := observe_hits()
	await third_stage()
	await tick(42)
	check(events.size() == 3 and events[2]["damage"] == 6 and arena.targets[0].hp == 14, "critical multiplier scales base damage rather than hardcoding3")
	await prepare_target(0,"left")
	arena.player.critical_roll_override = 0.0
	var stop_before := hit_stop_events
	await third_stage()
	await tick(42)
	check(arena.player.critical_rolls == 1 and arena.hits == 0, "missed third strike still rolls once and hits nothing")
	check(hit_stop_events == stop_before and arena.player.critical_impact_count == 0, "missed critical does not freeze/flash")
	await prepare_target(0)
	arena.targets[0].hp = 0
	arena.player.critical_roll_override = 0.0
	stop_before = hit_stop_events
	await third_stage()
	await tick(42)
	check(hit_stop_events == stop_before and arena.hits == 0, "already defeated target cannot trigger critical stop")
	await prepare_target(0)
	arena.targets[0].max_hp = 12
	arena.targets[0].hp = 12
	var second := add_target(Vector2(92,83),12)
	await tick(2)
	arena.player.critical_roll_override = 0.0
	events = observe_hits()
	stop_before = hit_stop_events
	await third_stage()
	await tick(42)
	check(arena.targets[0].hp == 7 and second.hp == 7, "one critical stage applies3x to each successfully struck target")
	check(hit_stop_events-stop_before == 3 and arena.player.critical_impact_count == 1, "multiple victims produce one shared stop per attack stage and one critical impact")
	check(events.filter(func(event: Dictionary) -> bool: return event["critical"]).size() == 2, "critical hit resolution identifies both victims")
	observations["critical_cases"] = critical_cases
	await prepare_target(1)
	var target: CharacterBody2D = arena.targets[0]
	target.max_hp = 9
	target.hp = 9
	arena.player.critical_roll_override = 0.0
	var specials: Array[String] = []
	arena.player.special_started.connect(func(kind: String, _direction: Vector2) -> void: specials.append(kind))
	key(KEY_W,true)
	await mouse_tap()
	check(arena.player.special_kind == "rising_slash" and arena.player.sprite.animation == "rising_slash_right", "side W+freshLMB starts rising slash")
	check(arena.player.velocity.y < -190.0 and arena.player.position.y < 160.0, "rising slash starts a real player jump")
	var repeated: bool = arena.player.request_rising_slash()
	check(not repeated, "active rising slash cannot restart itself")
	var smallest_y: float = target.position.y
	var player_smallest_y: float = arena.player.position.y
	for _index in range(35):
		await tick(1)
		smallest_y = minf(smallest_y,target.position.y)
		player_smallest_y = minf(player_smallest_y,arena.player.position.y)
	check(target.hp == 8 and target.knock_count == 1, "rising contact damages and launches target once")
	check(target.last_knock_velocity.y == -300.0 and target.last_knock_velocity.x == 55.0, "rising gives the higher upward target impulse")
	check(smallest_y < 154.0 and player_smallest_y < 125.0, "target and player actually rise in physics")
	check(arena.player.airflow_count >= 3, "rising generates pixel airflow")
	check(arena.player.critical_rolls == 0, "rising never consumes a third-stage crit roll")
	await mouse_tap()
	check(specials.size() == 1, "fresh mouse in air cannot create a second rising special")
	key(KEY_W,false)
	await tick(65)
	check(target.is_on_floor() and target.position.y <= 160.2, "higher launched target lands on a real floor or platform")
	check(arena.player.is_on_floor(), "rising player lands normally")
	target.respawn()
	await tick(2)
	check(target.hp == 9 and target.position.distance_to(target.spawn_position) < 0.2 and target.velocity.is_zero_approx(), "target respawn restores health, position and velocity")
	observations["rising_physics"] = {"target_min_y":smallest_y,"player_min_y":player_smallest_y,"knock_count":target.knock_count}
	await prepare_target(1)
	key(KEY_W,true)
	await tap(KEY_J)
	check(not arena.player.is_attacking, "W+J has no attack operation")
	key(KEY_W,false)
	await prepare_target(1)
	key(KEY_S,true)
	await tick(14)
	key(KEY_W,true)
	await mouse_tap()
	check(arena.player.special_kind == "" and arena.player.is_crouching, "crouching rejects rising special")
	await reset(0)
	key(KEY_W,true)
	await mouse_tap()
	check(arena.player.special_kind == "" and not arena.player.sprite.animation.begins_with("rising_"), "top view W+LMB remains ordinary movement/attack")
	await prepare_target(1)
	arena.add_wall(Rect2(85,60,3,100))
	await tick(3)
	key(KEY_W,true)
	await mouse_tap()
	await tick(28)
	check(arena.targets[0].hp == 3 and arena.targets[0].knock_count == 0, "wall blocks rising damage and launch")
	await reset(1)
	await double_tap(KEY_D)
	await mouse_tap()
	check(arena.player.special_kind == "" and arena.player.is_attacking, "double D plus LMB is now an ordinary attack")
	await reset(1)
	var facing_x := 1.0 if arena.player.facing == "right" else -1.0
	await tap(KEY_SHIFT)
	check(arena.player.special_kind == "dash_stab" and arena.player.attack_direction.x == facing_x, "Shift alone dashes towards the current facing")
	await reset(1)
	key(KEY_D,true)
	await mouse_tap()
	check(arena.player.special_kind == "", "direction plus LMB without Shift cannot dash")
	await reset(1)
	key(KEY_D,true)
	key(KEY_SHIFT,true)
	await tick(2)
	check(arena.player.special_kind == "dash_stab" and arena.player.attack_direction.x == 1.0, "Shift with a held direction dashes at once, without a click")
	key(KEY_SHIFT,false)
	key(KEY_D,false)
	for _index in range(60):
		if not arena.player.is_attacking and arena.player._recovery_left <= 0.0:
			break
		await tick(1)
	await mouse_tap()
	check(arena.player.special_kind == "" and arena.player.is_attacking, "a click after the dash is an ordinary attack, not another dash")
	await reset(1)
	facing_x = 1.0 if arena.player.facing == "right" else -1.0
	key(KEY_A,true)
	key(KEY_D,true)
	await tap(KEY_SHIFT)
	check(arena.player.special_kind == "dash_stab" and arena.player.attack_direction.x == facing_x, "opposing held directions dash towards the facing")
	await reset(1)
	mouse(true)
	await tick(45)
	key(KEY_SHIFT,true)
	key(KEY_D,true)
	await tick(2)
	check(not arena.player.is_attacking and arena.player.special_kind == "", "Shift during a held-mouse charge neither dashes nor starts a fresh attack")
	await reset(1)
	key(KEY_W,true)
	await mouse_tap()
	check(arena.player.special_kind == "rising_slash", "W+LMB still rises now that the dash has its own key")
	await reset(1)
	key(KEY_W,true)
	await tap(KEY_SHIFT)
	check(arena.player.special_kind == "dash_stab", "holding W does not block the Shift dash")
	await reset(0)
	await tap(KEY_SHIFT)
	check(not arena.player.is_attacking and arena.player.special_kind == "", "top view Shift does not dash")
	await mouse_tap()
	check(arena.player.is_attacking and arena.player.special_kind == "", "top view click stays an ordinary attack")
	var dash_cases: Array[Dictionary] = []
	for direction in [-1,1]:
		await reset(1)
		await clear_targets()
		arena.player.position = Vector2(170,160) if direction < 0 else Vector2(60,160)
		await tick(2)
		arena.player.facing = "right" if direction < 0 else "left"
		await dash_press(KEY_A if direction < 0 else KEY_D)
		check(arena.player.special_kind == "dash_stab" and arena.player.attack_direction.x == direction, "dash uses the held direction rather than stale facing: " + str(direction))
		await tick(12)
		var displacement: float = arena.player.dash_end.x-arena.player.dash_start.x
		check(arena.player.dash_executed and absf(displacement-direction*48.0) < 0.1, "dash moves48px in one swept step: " + str(direction))
		check(not arena.player.request_dash_stab(direction), "active dash cannot restart itself: " + str(direction))
		check(arena.player.airflow_count >= 3, "dash has airflow and afterimage generation")
		await tick(28)
		check(arena.player.collision_mask == 3, "empty dash endpoint restores normal collision mask")
		await mouse_tap()
		check(arena.player.special_kind == "", "a new click after the dash remains an ordinary attack")
		dash_cases.append({"direction":direction,"distance":displacement})
	await reset(1)
	await clear_targets()
	arena.player.position = Vector2(60,160)
	var victims: Array[CharacterBody2D] = []
	for index in range(22):
		victims.append(add_target(Vector2(78+index,160),6))
	var outside := add_target(Vector2(149,160),6)
	await tick(3)
	var dash_stop_start := hit_stop_events
	var dash_completion_start := completed_stops.size()
	await dash_press(KEY_D)
	await tick(35)
	check(hit_stop_events-dash_stop_start == 1 and completed_stops.slice(dash_completion_start) == [4], "22 simultaneous pierced targets share one normal contact freeze")
	check(victims.all(func(victim: CharacterBody2D) -> bool: return victim.hp == 5), "dash pierces every one of22 targets, beyond a16-result cap")
	check(arena.hits == 22 and outside.hp == 6, "dash hits swept segment once each and leaves distant target unchanged")
	check(arena.player.critical_rolls == 0, "dash cannot critically roll")
	await reset(1)
	await clear_targets()
	arena.player.position = Vector2(60,160)
	var before_wall := add_target(Vector2(80,160),6)
	var behind_wall := add_target(Vector2(122,160),6)
	arena.add_wall(Rect2(100,125,3,35))
	await tick(3)
	await dash_press(KEY_D)
	await tick(35)
	check(arena.player.dash_end.x <= 94.1 and arena.player.dash_end.x > arena.player.dash_start.x, "dash stops short at the real wall")
	check(before_wall.hp == 5 and behind_wall.hp == 6, "wall-clipped dash hits near victim and leaves enemy behind wall untouched")
	observations["wall_dash_endpoint"] = {"player_x":arena.player.position.x,"near_enemy_x":before_wall.position.x,"collision_mask":arena.player.collision_mask}
	check(arena.player.position.x <= 94.1 and (arena.player.collision_mask & 1) != 0, "dash endpoint remains blocked by the wall after recovery")
	# Weak knockback can move the near enemy into the wall-clipped endpoint.
	# Retain enemy phasing until separation, then restore ordinary collisions.
	if arena.player.collision_mask != 3:
		key(KEY_A,true)
		await tick(30)
		key(KEY_A,false)
		await tick(5)
	check(arena.player.collision_mask == 3, "wall-clipped dash restores enemy collisions after leaving a knocked enemy overlap")
	await reset(1)
	await clear_targets()
	arena.player.position = Vector2(60,160)
	var endpoint := add_target(Vector2(109,160),6)
	await tick(3)
	var dash_starts: Array[int] = [0]
	arena.player.special_started.connect(func(kind: String, _direction: Vector2) -> void:
		if kind == "dash_stab":
			dash_starts[0] += 1
	)
	key(KEY_SHIFT,true)
	key(KEY_D,true)
	await tick(1)
	mouse(true)
	await tick(2)
	key(KEY_D,false)
	key(KEY_SHIFT,false)
	await tick(48)
	# The click during the dash is the dodge offset: one shadow slash, then the held button coils into the charge.
	check(dash_starts[0] == 1 and arena.player.position.x >= arena.player.dash_end.x - arena.player.CHARGE_BACKSTEP - 0.01, "holding mouse does not repeat dash or snap backward at occupied endpoint")
	mouse(false)
	await tick(4)
	key(KEY_A,true)
	await tick(30)
	key(KEY_A,false)
	await tick(6)
	check(arena.player.collision_mask == 3 and arena.player.position.x < endpoint.position.x-12.0, "leaving overlapping enemy safely restores normal collisions")
	observations["dash_cases"] = dash_cases

func run_contact_tests() -> void:
	var cases: Array[Dictionary] = []
	for mode in [0,1]:
		for direction in [-1,1]:
			await reset(mode)
			await clear_targets()
			var origin := Vector2(146,160) if mode == 1 else Vector2(146,83)
			arena.player.position = origin
			arena.player.facing = "left" if direction < 0 else "right"
			var target := add_target(origin+Vector2(direction*26,0),6)
			await tick(3)
			var target_start := target.global_position
			var stop_start := hit_stop_events
			var completion_start := completed_stops.size()
			mouse(true)
			var found := false
			for _index in range(40):
				await tick(1)
				if target.hp < 6:
					found = true
					break
			check(found and target.hp == 5, "ordinary contact damages once, mode/direction " + str([mode,direction]))
			check(target.slash_flash_left > 0.0 and target.slash_flash_pixels().size() > 0, "ordinary contact adds enemy white/blue slashlight, mode/direction " + str([mode,direction]))
			var pixels_are_native := true
			for point in target.slash_flash_pixels():
				pixels_are_native = pixels_are_native and Vector2(point) == Vector2(point).round()
			check(pixels_are_native, "enemy slashlight uses integer native pixels")
			var peak_flash: float = target.slash_flash_left
			var max_forward := 0.0
			var min_y: float = target.global_position.y
			for _index in range(42):
				await tick(1)
				max_forward = maxf(max_forward,(target.global_position.x-target_start.x)*direction)
				min_y = minf(min_y,target.global_position.y)
			check(max_forward > 0.4 and max_forward < 12.0, "ordinary contact causes a small real forward knockback")
			if mode == 1:
				check(min_y < target_start.y-0.2 and min_y > target_start.y-8.0, "ordinary side contact makes a small physical hop")
				check(absf(target.global_position.y-160.0) < 0.1 and target.is_on_floor(), "weakly hit enemy lands on the real floor")
			check(target.slash_flash_left <= 0.0 and target.slash_flash_pixels().is_empty(), "brief enemy slashlight expires")
			check(target.hp == 5 and hit_stop_events-stop_start == 1, "held attack and repeated overlap do not repeat damage or freeze")
			check(completed_stops.slice(completion_start) == [4] and not paused, "ordinary hit completes four display steps and resumes")
			cases.append({"mode":mode,"direction":direction,"displacement_forward":max_forward,"upward_displacement":target_start.y-min_y,"initial_slash_flash_left":peak_flash,"stop_frames":completed_stops.slice(completion_start)})
			mouse(false)
	await reset(1)
	await clear_targets()
	arena.player.position = Vector2(70,160)
	await tick(3)
	var stop_start := hit_stop_events
	await mouse_tap()
	await tick(42)
	check(hit_stop_events == stop_start and arena.hits == 0, "ordinary whiff does not freeze")
	var dead := add_target(Vector2(96,160),6)
	dead.hp = 0
	await tick(2)
	await mouse_tap()
	await tick(42)
	check(hit_stop_events == stop_start and arena.hits == 0 and dead.slash_flash_left <= 0.0, "dead enemy does not create damage, slashlight or hit stop")
	await reset(1)
	await clear_targets()
	arena.player.position = Vector2(70,160)
	var lethal := add_target(Vector2(96,160),1)
	await tick(3)
	var lethal_start := lethal.global_position
	stop_start = hit_stop_events
	await mouse_tap()
	var lethal_flash := false
	var lethal_displacement := 0.0
	for _index in range(45):
		await tick(1)
		lethal_flash = lethal_flash or (lethal.hp == 0 and lethal.slash_flash_left > 0.0 and not lethal.slash_flash_pixels().is_empty())
		lethal_displacement = maxf(lethal_displacement,lethal.global_position.x-lethal_start.x)
	check(lethal.hp == 0 and lethal.body_shape.disabled, "lethal contact disables enemy collider")
	check(lethal_flash and lethal_displacement > 0.2 and lethal_displacement < 12.0, "lethal contact still renders brief slashlight and actual small knockback")
	check(hit_stop_events-stop_start == 1, "lethal confirmed hit gets one shared contact stop")
	for mode in [0,1]:
		await reset(mode)
		await clear_targets()
		arena.player.position = Vector2(78,160) if mode == 1 else Vector2(78,83)
		arena.player.facing = "right"
		var against_wall := add_target(Vector2(104,160) if mode == 1 else Vector2(104,83),6)
		arena.add_wall(Rect2(112,110,3,50) if mode == 1 else Rect2(112,60,3,40))
		await tick(3)
		await mouse_tap()
		await tick(45)
		check(against_wall.hp == 5 and against_wall.global_position.x <= 106.1, "ordinary enemy knockback respects the real wall, mode " + str(mode))
	await reset(1)
	await clear_targets()
	arena.player.position = Vector2(70,160)
	var buffered_target := add_target(Vector2(96,160),12)
	await tick(3)
	stop_start = hit_stop_events
	var completion_start := completed_stops.size()
	mouse(true)
	mouse(false)
	var in_stop := false
	for _index in range(50):
		await process_frame
		if arena.hit_stop_active:
			in_stop = true
			break
	check(in_stop, "input buffer fixture observes the actual contact pause")
	mouse(true)
	mouse(false)
	var pending: bool = arena.player._mouse_attack_pending
	check(paused and (arena.player.queued_attack or pending), "fresh press/release within hit stop is buffered")
	await tick(85)
	check(buffered_target.hp == 10 and hit_stop_events-stop_start == 2, "paused fresh input causes one second strike without extra repeats")
	check(completed_stops.slice(completion_start) == [4,4], "buffered normal follow-up uses two separate four-frame stops")
	for index in range(completed_stops.size()):
		check(completed_stop_durations[index]+0.00001 >= completed_stops[index]/60.0, "contact pause has minimum visible time at fixed60: " + str(index))
	observations["ordinary_contact_cases"] = cases
	observations["completed_stop_frames"] = completed_stops
	observations["completed_stop_durations_seconds"] = completed_stop_durations
