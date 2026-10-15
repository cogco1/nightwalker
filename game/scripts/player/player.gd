extends CharacterBody2D

signal attack_started
signal attack_hit(target: Node)
signal combo_changed(stage: int)
signal hit_resolved(target: Node, damage: int, critical: bool, kind: String)
signal critical_hit(target: Node, damage: int, direction: Vector2)
signal normal_contact_stop(direction: Vector2)
signal special_started(kind: String, direction: Vector2)
signal landing_impact(point: Vector2)

enum ViewMode { TOP_DOWN, SIDE_VIEW }

@export var view_mode: ViewMode = ViewMode.TOP_DOWN
@export var move_speed := 60.0
@export var run_speed := 138.0
@export var crouch_speed := 20.0
@export var gravity := 620.0
@export var jump_velocity := -225.0
@export var attack_damage := 1

const TOP_FRAMES = preload("res://assets/top_down.tres")
const CONTROLS = preload("res://scripts/core/controls.gd")
const SIDE_FRAMES = preload("res://assets/side_view.tres")
const ACTIVE_START := 6
const ACTIVE_END := 9
const STAGE_FPS := [36.0, 40.0, 42.0]
const ATTACK_BUFFER_SECONDS := 0.22
const ACCEL_SECONDS := 0.075
const BRAKE_SECONDS := 0.065
const STAND_SIZE := Vector2(12, 26)
const CROUCH_SIZE := Vector2(12, 14)
const BLADE_TRAIL_SECONDS := 0.14
const MAX_BLADE_PIXELS := 70
const DASH_DISTANCE := 48.0
const LANDING_SECONDS := 2.0 / 60.0
const AIR_HOLD_SECONDS := 0.55
const AIR_DASH_HOLD_SECONDS := 0.30
const AIR_FALL_SPEED := 6.0
const DIVE_SPEED := 360.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var body_shape: CollisionShape2D = $BodyShape

var facing := "down"
var is_attacking := false
var is_crouching := false
var is_running := false
var idle_bob_y := 0
var combo_stage := 0
var queued_attack := false
var pending_new_attack := false
var attack_buffer_left := 0.0
var hit_targets: Dictionary = {}
var attack_direction := Vector2.DOWN
var _attack_crouched := false
var _recovery_left := 0.0
var _crouch_exiting := false
var _crouch_frame := 0.0
var _jump_age := 0.0
var _landing_left := 0.0
var _dust_timer := 0.0
var _braking := false
var _brake_from_speed := 0.0
var _effects: Array[Dictionary] = []
var _blade_trails: Array[Dictionary] = []
var _blade_paths: Dictionary = {}
var _last_blade_frame := -1
var _previous_blade_tip := Vector2.ZERO
var critical_roll_override := -1.0
var critical_rolls := 0
var last_critical_roll := 1.0
var stage_is_critical := false
var special_kind := ""
var dash_start := Vector2.ZERO
var dash_end := Vector2.ZERO
var dash_executed := false
var _critical_stop_emitted := false
var _normal_stop_emitted := false
var _rng := RandomNumberGenerator.new()
var _mouse_attack_pending := false
var _mouse_attack_held := false
var _dash_phasing := false
var _afterimages: Array[Dictionary] = []
var airflow_count := 0
var critical_impact_count := 0
var input_suspended := false
var _jumps_used := 0
var _air_hold_left := 0.0


func _ready() -> void:
	# GUI buttons consume clicks before gameplay receives unhandled input.
	set_process_input(false)
	set_process_unhandled_input(true)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	sprite.centered = false
	sprite.offset = Vector2(-24, -42)
	var shape := RectangleShape2D.new()
	if view_mode == ViewMode.TOP_DOWN:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		sprite.sprite_frames = TOP_FRAMES
		shape.size = Vector2(12, 8)
		body_shape.position = Vector2(0, -4)
		facing = "down"
	else:
		motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
		sprite.sprite_frames = SIDE_FRAMES
		shape.size = STAND_SIZE
		body_shape.position = Vector2(0, -13)
		facing = "right"
	body_shape.shape = shape
	_load_blade_paths()
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_update_sprite_layout)
	sprite.animation_changed.connect(_update_sprite_layout)
	_show_idle()
	_update_sprite_layout()


func _physics_process(delta: float) -> void:
	if not CONTROLS.binding_pressed("attack_mouse"):
		_mouse_attack_held = false
	_try_end_dash_phasing()
	var was_grounded := is_on_floor()
	_update_effects(delta)
	_landing_left = maxf(0.0, _landing_left - delta)
	_air_hold_left = maxf(0.0, _air_hold_left - delta)
	_recovery_left = maxf(0.0, _recovery_left - delta)
	if queued_attack or pending_new_attack:
		attack_buffer_left = maxf(0.0, attack_buffer_left - delta)
		if attack_buffer_left <= 0.0:
			queued_attack = false
			pending_new_attack = false
	var direction := _movement_input()
	if view_mode == ViewMode.SIDE_VIEW:
		if not was_grounded:
			velocity.y = DIVE_SPEED if special_kind == "dive_slash" else (AIR_FALL_SPEED if _air_hold_left > 0.0 else velocity.y + gravity * delta)
			_jump_age += delta
		else:
			velocity.y = 0.0
			_jumps_used = 0
		if not is_attacking and _recovery_left <= 0.0:
			_update_crouch(delta)
		if Input.is_action_just_pressed("jump") and not is_crouching and _jumps_used < 2 and special_kind != "dive_slash" and (not was_grounded or not is_attacking):
			_jumps_used = 1 if was_grounded else 2
			_crouch_exiting = false
			velocity.y = jump_velocity
			_jump_age = 0.0
			_landing_left = 0.0
			_air_hold_left = 0.0
			_spawn_dust(global_position, 3)
	if not is_attacking and _recovery_left <= 0.0 and not direction.is_zero_approx():
		_update_facing(direction)
	# Taps are processed while attacking too. Holding a button never auto-chains.
	if _mouse_attack_pending:
		var special := false
		if not is_attacking and _recovery_left <= 0.0 and view_mode == ViewMode.SIDE_VIEW:
			if Input.is_action_pressed("rising_modifier") and was_grounded:
				special = request_rising_slash()
			elif Input.is_action_pressed("dash_modifier") and direction.x != 0.0:
				special = request_dash_stab(int(signf(direction.x)))
		if not special:
			request_attack()
		_mouse_attack_pending = false
	if pending_new_attack and not is_attacking and _recovery_left <= 0.0:
		begin_attack()
	is_running = Input.is_action_pressed("run") and not direction.is_zero_approx() and not is_crouching and not _crouch_exiting and not is_attacking and _recovery_left <= 0.0
	if is_attacking:
		var impulse := _attack_lunge_speed() if was_grounded or view_mode == ViewMode.TOP_DOWN else 0.0
		if view_mode == ViewMode.TOP_DOWN:
			velocity = attack_direction * impulse
		else:
			velocity.x = direction.x * crouch_speed if not was_grounded and special_kind == "" else attack_direction.x * impulse
	elif _recovery_left > 0.0:
		if view_mode == ViewMode.TOP_DOWN:
			velocity = Vector2.ZERO
		else:
			velocity.x = 0.0
	else:
		var speed := crouch_speed if is_crouching or _crouch_exiting else (run_speed if is_running else move_speed)
		_update_move_velocity(direction, speed, delta)
		_update_animation(direction)
	move_and_slide()
	# Physics retains subpixel precision; every drawn pixel uses the same native grid.
	sprite.position = global_position.round() - global_position
	_update_sprite_layout()
	if view_mode == ViewMode.SIDE_VIEW and not was_grounded and is_on_floor():
		_landing_left = LANDING_SECONDS
		_jump_age = 0.0
		_jumps_used = 0
		_air_hold_left = 0.0
		_spawn_dust(global_position, 5)
	if is_attacking and sprite.frame >= _attack_active_start() and (special_kind == "dive_slash" or sprite.frame <= ACTIVE_END):
		if special_kind == "dash_stab":
			if not dash_executed:
				_perform_dash()
		else:
			_apply_attack_hits()
		_update_blade_trail()
		if special_kind == "rising_slash" and airflow_count == 0:
			_spawn_airflow(global_position, true)
	if special_kind == "dive_slash" and is_on_floor():
		_on_animation_finished()
		_recovery_left = LANDING_SECONDS
		_set_manual_frame("dive_slash_" + facing, 14)
		_blade_trails.clear()
		_spawn_sparks(global_position + Vector2(-8, -1))
		_spawn_sparks(global_position + Vector2(8, -1))
		_effects.append({"position": global_position + Vector2(-8, -1), "velocity": Vector2(-100, -4), "tail": Vector2(-4, 0), "life": 0.14, "color": Color("8ebce8")})
		_effects.append({"position": global_position + Vector2(8, -1), "velocity": Vector2(100, -4), "tail": Vector2(4, 0), "life": 0.14, "color": Color("f2f8ff")})
		landing_impact.emit(global_position)
	if is_running and (view_mode == ViewMode.TOP_DOWN or is_on_floor()):
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_spawn_dust(global_position - _facing_vector() * 5.0, 2)
			_dust_timer = 0.09
	else:
		_dust_timer = 0.0
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	_input(event)


func clear_input_buffer() -> void:
	_mouse_attack_pending = false
	_mouse_attack_held = false
	queued_attack = false
	pending_new_attack = false
	attack_buffer_left = 0.0


func _input(event: InputEvent) -> void:
	if input_suspended:
		return
	if event is InputEventMouseButton and event.is_action("attack"):
		if not event.pressed:
			_mouse_attack_held = false
		elif not _mouse_attack_held:
			_mouse_attack_held = true
			_mouse_attack_pending = true
	if view_mode != ViewMode.SIDE_VIEW or not event is InputEventKey or event.echo:
		return
	if event.is_action_pressed("crouch"):
		request_dive_slash()


func _update_move_velocity(direction: Vector2, speed: float, delta: float) -> void:
	var movement := velocity if view_mode == ViewMode.TOP_DOWN else Vector2(velocity.x, 0)
	var desired := direction * speed
	var seconds := BRAKE_SECONDS if direction.is_zero_approx() else ACCEL_SECONDS
	var acceleration := maxf(speed, movement.length()) / seconds
	if direction.is_zero_approx():
		if not _braking:
			_braking = true
			_brake_from_speed = movement.length()
		# Fix the initial braking rate so a run stops in the same short time as a walk.
		acceleration = maxf(1.0, _brake_from_speed) / BRAKE_SECONDS
	else:
		_braking = false
	if not direction.is_zero_approx() and movement.dot(direction) < 0.0:
		acceleration *= 1.35
	movement = movement.move_toward(desired, acceleration * delta)
	if direction.is_zero_approx() and movement.length() < 0.4:
		movement = Vector2.ZERO
	if view_mode == ViewMode.TOP_DOWN:
		velocity = movement
	else:
		velocity.x = movement.x


func _movement_input() -> Vector2:
	if view_mode == ViewMode.TOP_DOWN:
		return Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return Vector2(Input.get_axis("move_left", "move_right"), 0)


func _update_facing(direction: Vector2) -> void:
	# Keep the previous compatible direction on diagonals instead of toggling poses.
	if view_mode == ViewMode.TOP_DOWN and absf(absf(direction.x) - absf(direction.y)) < 0.12:
		if facing == "right" and direction.x > 0.0 or facing == "left" and direction.x < 0.0:
			return
		if facing == "down" and direction.y > 0.0 or facing == "up" and direction.y < 0.0:
			return
	if absf(direction.x) >= absf(direction.y):
		facing = "right" if direction.x > 0.0 else "left"
	else:
		facing = "down" if direction.y > 0.0 else "up"


func _facing_vector() -> Vector2:
	match facing:
		"up":
			return Vector2.UP
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
	return Vector2.DOWN


func _set_body_size(size: Vector2) -> void:
	(body_shape.shape as RectangleShape2D).size = size
	body_shape.position = Vector2(0, -size.y / 2.0)


func can_stand() -> bool:
	if view_mode != ViewMode.SIDE_VIEW:
		return true
	var shape := RectangleShape2D.new()
	# Inset excludes mere contact with the floor from ceiling checks.
	shape.size = STAND_SIZE - Vector2(0.2, 0.2)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position + Vector2(0, -13))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _update_crouch(delta: float) -> void:
	var wants_crouch := Input.is_action_pressed("crouch") and is_on_floor()
	if wants_crouch:
		if not is_crouching:
			is_crouching = true
			_crouch_exiting = false
			_crouch_frame = 0.0
			_set_body_size(CROUCH_SIZE)
		_crouch_frame = minf(7.0, _crouch_frame + delta * 28.0)
	elif is_crouching:
		if can_stand():
			is_crouching = false
			_crouch_exiting = true
			_crouch_frame = 10.0
			_set_body_size(STAND_SIZE)
		else:
			_crouch_frame = 7.0
	elif _crouch_exiting:
		_crouch_frame += delta * 32.0
		if _crouch_frame >= 16.0:
			_crouch_exiting = false


func _update_animation(direction: Vector2) -> void:
	if _recovery_left > 0.0:
		return
	if view_mode == ViewMode.SIDE_VIEW:
		if is_crouching or _crouch_exiting:
			var crouch_idle := "crouch_idle_" + facing
			if is_crouching and _crouch_frame >= 7.0 and sprite.sprite_frames.has_animation(crouch_idle):
				_play_loop(crouch_idle, false)
			else:
				_set_manual_frame("crouch_" + facing, int(_crouch_frame))
			return
		if not is_on_floor() or velocity.y < 0.0:
			if _air_hold_left > 0.0 or absf(velocity.y) <= 35.0:
				_play_loop("air_idle_" + facing, false)
				return
			var frame := 0
			if velocity.y < -35.0:
				frame = clampi(int(_jump_age * 25.0), 0, 6)
			else:
				frame = clampi(9 + int((velocity.y - 35.0) / 45.0), 9, 12)
			_set_manual_frame("jump_" + facing, frame)
			return
		if _landing_left > 0.0:
			_set_manual_frame("jump_" + facing, clampi(13 + int((LANDING_SECONDS - _landing_left) * 90.0), 13, 15))
			return
	var moving_speed := velocity.length() if view_mode == ViewMode.TOP_DOWN else absf(velocity.x)
	if direction.is_zero_approx() and moving_speed < 4.0:
		_show_idle()
	else:
		_play_loop(("run_" if is_running else "walk_") + facing, true)


func _play_loop(animation: String, preserve_phase: bool) -> void:
	if sprite.animation == animation and sprite.is_playing():
		return
	var phase := 0.0
	var old_name := String(sprite.animation)
	if preserve_phase and (old_name.begins_with("walk_") or old_name.begins_with("run_")):
		var old_count := sprite.sprite_frames.get_frame_count(sprite.animation)
		phase = (float(sprite.frame) + sprite.frame_progress) / maxf(1.0, float(old_count))
	sprite.speed_scale = 1.0
	sprite.play(animation)
	if preserve_phase:
		var count := sprite.sprite_frames.get_frame_count(animation)
		var progress := phase * float(count)
		sprite.set_frame_and_progress(clampi(int(progress), 0, count - 1), fposmod(progress, 1.0))


func _set_manual_frame(animation: String, frame: int) -> void:
	if sprite.animation != animation:
		sprite.animation = animation
	sprite.set_frame_and_progress(clampi(frame, 0, sprite.sprite_frames.get_frame_count(animation) - 1), 0.0)
	sprite.pause()
	_update_sprite_layout()


func _update_sprite_layout() -> void:
	var animation := String(sprite.animation)
	var pivot := Vector2(24, 42)
	if sprite.sprite_frames.has_animation(sprite.animation) and sprite.sprite_frames.get_frame_count(sprite.animation) > 0:
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		if (view_mode == ViewMode.SIDE_VIEW or animation.begins_with("attack") or animation.begins_with("rising_slash_") or animation.begins_with("dash_stab_")) and texture != null and texture.get_height() >= 64:
			# Extra attack canvas is padding for the wider arm sweep, at the same pixel size.
			pivot = Vector2(texture.get_width() / 2.0, texture.get_height() - 12.0)
	# The restored breathing frames keep their drawn motion; the visual anchor stays fixed.
	idle_bob_y = 0
	sprite.offset = -pivot


func request_attack() -> bool:
	if not is_attacking:
		if _recovery_left > 0.0:
			# A fresh tap during the short return pose starts one new chain after it.
			pending_new_attack = true
			attack_buffer_left = maxf(ATTACK_BUFFER_SECONDS, _recovery_left + 0.05)
			return true
		return begin_attack()
	if _attack_crouched or special_kind != "" or combo_stage >= 3:
		return false
	queued_attack = true
	var fps: float = sprite.sprite_frames.get_animation_speed(sprite.animation) * sprite.speed_scale
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	var remaining := (float(count - sprite.frame) - sprite.frame_progress) / maxf(1.0, fps)
	# Early double taps are deliberate inputs too, so keep one tap until this hit ends.
	attack_buffer_left = clampf(maxf(ATTACK_BUFFER_SECONDS, remaining + 0.05), ATTACK_BUFFER_SECONDS, 0.55)
	return true


func begin_attack() -> bool:
	if is_attacking or _recovery_left > 0.0:
		return false
	_attack_crouched = is_crouching
	special_kind = ""
	attack_direction = _facing_vector()
	queued_attack = false
	pending_new_attack = false
	attack_buffer_left = 0.0
	_start_attack_stage(1)
	return true


func _start_attack_stage(stage: int) -> void:
	combo_stage = stage
	is_attacking = true
	is_running = false
	var aerial := view_mode == ViewMode.SIDE_VIEW and not is_on_floor() and special_kind == ""
	if aerial:
		_air_hold_left = AIR_HOLD_SECONDS
		velocity.y = AIR_FALL_SPEED
	hit_targets.clear()
	stage_is_critical = false
	_critical_stop_emitted = false
	_normal_stop_emitted = false
	if stage == 3 and not _attack_crouched and special_kind == "":
		critical_rolls += 1
		last_critical_roll = critical_roll_override if critical_roll_override >= 0.0 else _rng.randf()
		stage_is_critical = last_critical_roll < 0.30
	_last_blade_frame = -1
	_previous_blade_tip = Vector2.ZERO
	var animation := "crouch_stab_" + facing if _attack_crouched else "attack%d_%s" % [stage, facing]
	if aerial:
		animation = "air_attack%d_%s" % [stage, facing]
	# Compatibility keeps the project loadable while new drawn clips are imported.
	if not sprite.sprite_frames.has_animation(animation):
		animation = ("crouch_stab_" if _attack_crouched else "stab_") + facing
	sprite.stop()
	sprite.speed_scale = (40.0 if _attack_crouched else STAGE_FPS[stage - 1]) / sprite.sprite_frames.get_animation_speed(animation)
	sprite.play(animation)
	combo_changed.emit(stage)
	attack_started.emit()


func _attack_lunge_speed() -> float:
	if _attack_crouched or special_kind != "" or sprite.frame < ACTIVE_START or sprite.frame > ACTIVE_END:
		return 0.0
	var phase := (float(sprite.frame - ACTIVE_START) + sprite.frame_progress) / float(ACTIVE_END - ACTIVE_START + 1)
	var duration: float = float(ACTIVE_END - ACTIVE_START + 1) / STAGE_FPS[combo_stage - 1]
	var distance := 6.8 if combo_stage == 3 else 5.5
	# The wider drawn swing advances a few native pixels, easing in and out safely.
	return sin(phase * PI) * distance * PI / (2.0 * duration)


func attack_origin() -> Vector2:
	var height := 4.0 if view_mode == ViewMode.TOP_DOWN else (9.0 if _attack_crouched else 17.0)
	return global_position + Vector2(0, -height)


func _attack_active_start() -> int:
	if special_kind == "dive_slash":
		return 0
	if special_kind == "rising_slash":
		return 3
	if view_mode == ViewMode.SIDE_VIEW and special_kind == "" and not _attack_crouched and combo_stage == 1:
		# The long blade is still behind the shoulder in frame 6; frame 7 crosses forward.
		return 7
	return ACTIVE_START


func attack_box() -> Rect2:
	if special_kind == "dive_slash":
		return Rect2(global_position + Vector2(-13, -24), Vector2(26, 42))
	if special_kind == "rising_slash":
		return Rect2(global_position + attack_direction * 19.0 + Vector2(-18, -36), Vector2(36, 48))
	var length := 27.0 if _attack_crouched else 34.0
	var width := 16.0 if _attack_crouched else 20.0
	var extra_reach := 12.0 if view_mode == ViewMode.SIDE_VIEW else 0.0
	length += extra_reach
	var size := Vector2(length, width)
	if view_mode == ViewMode.TOP_DOWN and attack_direction.x == 0.0:
		size = Vector2(width, length)
	var center := attack_origin() + attack_direction * ((17.0 if _attack_crouched else 21.0) + extra_reach / 2.0)
	return Rect2(center - size / 2.0, size)


func _apply_attack_hits() -> void:
	var box := attack_box()
	var shape := RectangleShape2D.new()
	shape.size = box.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, box.get_center())
	query.collision_mask = 2
	query.exclude = [get_rid()]
	var space := get_world_2d().direct_space_state
	for result in space.intersect_shape(query, maxi(32, get_tree().get_node_count())):
		var target: Node = result["collider"]
		if not target.has_method("take_damage"):
			continue
		var target_id := target.get_instance_id()
		if hit_targets.has(target_id):
			continue
		var point: Vector2 = target.call("damage_point")
		if view_mode == ViewMode.SIDE_VIEW:
			point.y = clampf(attack_origin().y, target.global_position.y - 26.0, target.global_position.y - 1.0)
		var ray := PhysicsRayQueryParameters2D.create(attack_origin(), point, 1)
		if not space.intersect_ray(ray).is_empty():
			continue
		_resolve_hit(target, point)


func _resolve_hit(target: Node, point: Vector2) -> bool:
	var damage := attack_damage * (3 if stage_is_critical else 1)
	if not target.call("take_damage", damage):
		return false
	hit_targets[target.get_instance_id()] = true
	if target.has_method("receive_hit_reaction"):
		target.call("receive_hit_reaction", attack_direction, special_kind == "rising_slash", view_mode == ViewMode.SIDE_VIEW and not is_on_floor() and special_kind in ["", "dash_stab"])
	elif special_kind == "rising_slash" and target.has_method("knock_up"):
		target.call("knock_up", attack_direction)
	_spawn_sparks(point)
	attack_hit.emit(target)
	hit_resolved.emit(target, damage, stage_is_critical, special_kind)
	if stage_is_critical and not _critical_stop_emitted:
		_critical_stop_emitted = true
		critical_impact_count += 1
		for axis in [Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
			_blade_trails.append({"pixels": _pixel_line(point, point + axis), "edge": Vector2i(0, 1), "life": BLADE_TRAIL_SECONDS})
		critical_hit.emit(target, damage, attack_direction)
	elif not stage_is_critical and not _normal_stop_emitted:
		_normal_stop_emitted = true
		normal_contact_stop.emit(attack_direction)
	return true


func request_rising_slash() -> bool:
	if view_mode != ViewMode.SIDE_VIEW or is_attacking or _recovery_left > 0.0 or is_crouching or not is_on_floor():
		return false
	_crouch_exiting = false
	_jump_age = 0.0
	_landing_left = 0.0
	_jumps_used = 1
	velocity.y = -280.0
	_start_special("rising_slash")
	return true


func request_dive_slash() -> bool:
	if view_mode != ViewMode.SIDE_VIEW or is_on_floor() or special_kind == "dive_slash":
		return false
	_air_hold_left = 0.0
	velocity.y = DIVE_SPEED
	_dash_phasing = true
	collision_mask = 1
	_start_special("dive_slash")
	queue_redraw()
	return true


func request_dash_stab(direction: int) -> bool:
	if view_mode != ViewMode.SIDE_VIEW or is_attacking or _recovery_left > 0.0 or is_crouching:
		return false
	if direction == 0 or not Input.is_action_pressed("dash_modifier"):
		return false
	facing = "right" if direction > 0 else "left"
	_crouch_exiting = false
	dash_executed = false
	dash_start = global_position
	dash_end = global_position
	if not is_on_floor():
		_air_hold_left = AIR_HOLD_SECONDS
		velocity.y = AIR_FALL_SPEED
	_start_special("dash_stab")
	return true


func _start_special(kind: String) -> void:
	special_kind = kind
	_attack_crouched = false
	attack_direction = Vector2.DOWN if kind == "dive_slash" else _facing_vector()
	queued_attack = false
	pending_new_attack = false
	attack_buffer_left = 0.0
	airflow_count = 0
	_start_attack_stage(1)
	var animation := kind + "_" + facing
	if kind == "dash_stab" and not is_on_floor():
		animation = "air_dash_stab_" + facing
	if sprite.sprite_frames.has_animation(animation):
		sprite.stop()
		sprite.speed_scale = 40.0 / sprite.sprite_frames.get_animation_speed(animation)
		sprite.play(animation)
	special_started.emit(kind, attack_direction)


func _perform_dash() -> void:
	dash_executed = true
	dash_start = global_position
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	_afterimages.append({"texture": texture, "position": dash_start + sprite.offset, "life": 0.12})
	_dash_phasing = true
	collision_mask = 1
	move_and_collide(attack_direction * DASH_DISTANCE, false, 0.001)
	dash_end = global_position
	_afterimages.append({"texture": texture, "position": dash_start.lerp(dash_end, 0.5) + sprite.offset, "life": 0.09})
	_spawn_airflow(dash_start, false)
	sprite.position = global_position.round() - global_position
	var start := dash_start + Vector2(0, -17)
	var end := dash_end + Vector2(0, -17)
	var rectangle := Rect2(Vector2(minf(start.x, end.x) - 4.0, start.y - 10.0), Vector2(absf(end.x - start.x) + 8.0, 20.0))
	var shape := RectangleShape2D.new()
	shape.size = rectangle.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, rectangle.get_center())
	query.collision_mask = 2
	query.exclude = [get_rid()]
	var space := get_world_2d().direct_space_state
	for result in space.intersect_shape(query, maxi(32, get_tree().get_node_count())):
		var target: Node = result["collider"]
		if not target.has_method("take_damage") or hit_targets.has(target.get_instance_id()):
			continue
		var point: Vector2 = target.call("damage_point")
		point.y = clampf(start.y, target.global_position.y - 26.0, target.global_position.y - 1.0)
		var ray := PhysicsRayQueryParameters2D.create(start, point, 1)
		if space.intersect_ray(ray).is_empty():
			_resolve_hit(target, point)


func _try_end_dash_phasing() -> void:
	if not _dash_phasing or is_attacking:
		return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body_shape.shape
	query.transform = body_shape.global_transform
	query.collision_mask = 2
	query.exclude = [get_rid()]
	if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		_dash_phasing = false
		collision_mask = 3


func _on_animation_finished() -> void:
	if not is_attacking:
		return
	if special_kind == "dive_slash" and not is_on_floor():
		_set_manual_frame("dive_slash_" + facing, 11)
		return
	if queued_attack and attack_buffer_left > 0.0 and combo_stage < 3 and not _attack_crouched and special_kind == "":
		queued_attack = false
		attack_buffer_left = 0.0
		_start_attack_stage(combo_stage + 1)
		return
	if special_kind == "dash_stab" and not is_on_floor():
		_air_hold_left = AIR_DASH_HOLD_SECONDS
		velocity.y = AIR_FALL_SPEED
	var finished_fps: float = 40.0 if _attack_crouched or special_kind != "" else STAGE_FPS[combo_stage - 1]
	is_attacking = false
	stage_is_critical = false
	combo_stage = 0
	queued_attack = false
	pending_new_attack = false
	attack_buffer_left = 0.0
	_recovery_left = (1.0 if view_mode == ViewMode.SIDE_VIEW and not is_on_floor() else 2.0) / finished_fps
	special_kind = ""
	sprite.pause()
	combo_changed.emit(0)


func _show_idle() -> void:
	var animation := "idle_" + facing
	if sprite.sprite_frames.has_animation(animation):
		_play_loop(animation, false)
	else:
		_set_manual_frame("stab_" + facing, 0)


func _spawn_dust(point: Vector2, count: int) -> void:
	for index in range(count):
		_effects.append({"position": point.round() + Vector2(index * 2 - count, -1), "velocity": Vector2((index - count / 2.0) * 9.0, -10.0 - index * 2.0), "life": 0.18, "color": Color("82717c")})


func _spawn_sparks(point: Vector2) -> void:
	for index in range(5):
		_effects.append({"position": point.round(), "velocity": Vector2(-32 + index * 16, -35 + abs(index - 2) * 16), "life": 0.14, "color": Color("f2f8ff") if index % 2 == 0 else Color("8ebce8")})


func _spawn_airflow(point: Vector2, rising: bool) -> void:
	airflow_count += 3
	for index in range(3):
		var location := point + Vector2(-attack_direction.x * (5 + index * 3), -7 - index * 8)
		var drift := Vector2(attack_direction.x * 8, -50) if rising else Vector2(-attack_direction.x * 30, 0)
		var tail := Vector2(attack_direction.x * 2, 5) if rising else attack_direction * 8.0
		_effects.append({"position": location.round(), "velocity": drift, "tail": tail, "life": 0.14, "color": Color("8ebce8")})


func _load_blade_paths() -> void:
	var path := "res://assets/blade_paths.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		var key := "top_down" if view_mode == ViewMode.TOP_DOWN else "side_view"
		var paths: Variant = data.get(key, {})
		if paths is Dictionary:
			_blade_paths = paths


func _blade_tip_for_frame(frame: int) -> Vector2:
	var animation := String(sprite.animation)
	if _blade_paths.has(animation):
		var frames: Variant = _blade_paths[animation]
		if frames is Array and frame >= 0 and frame < frames.size():
			var tip: Variant = frames[frame]
			if tip is Array and tip.size() >= 2:
				# The atlas pipeline stores the drawn steel tip relative to the foot pivot.
				return global_position.round() + Vector2(float(tip[0]), float(tip[1])).round()
	var step := clampi(frame - _attack_active_start(), 0, 3)
	var forward := 12.0
	var lateral := 0.0
	if _attack_crouched:
		forward = [12.0, 17.0, 23.0, 28.0][step]
		lateral = [1.0, 0.0, -1.0, 0.0][step]
	elif combo_stage == 3:
		forward = [15.0, 23.0, 31.0, 38.0][step]
		lateral = [2.0, 1.0, -1.0, 0.0][step]
	elif combo_stage == 2:
		forward = [17.0, 28.0, 32.0, 23.0][step]
		lateral = [13.0, 7.0, 0.0, -13.0][step]
	else:
		forward = [13.0, 24.0, 31.0, 23.0][step]
		lateral = [-13.0, -8.0, 1.0, 14.0][step]
	var perpendicular := Vector2(-attack_direction.y, attack_direction.x)
	return (attack_origin() + attack_direction * forward + perpendicular * lateral).round()


func _update_blade_trail() -> void:
	if sprite.frame == _last_blade_frame:
		return
	var tip := _blade_tip_for_frame(sprite.frame)
	var previous := _previous_blade_tip
	if _last_blade_frame < _attack_active_start():
		previous = _blade_tip_for_frame(_attack_active_start() - 1) if _blade_paths.has(String(sprite.animation)) else tip - attack_direction * 4.0
	var direction := tip - previous
	var edge := Vector2i(0, 1) if absf(direction.x) >= absf(direction.y) else Vector2i(1, 0)
	_blade_trails.append({"pixels": _pixel_line(previous, tip), "edge": edge, "life": BLADE_TRAIL_SECONDS})
	_previous_blade_tip = tip
	_last_blade_frame = sprite.frame


func _pixel_line(start: Vector2, end: Vector2) -> Array[Vector2i]:
	# Integer Bresenham segments keep a thin blade path on the native pixel grid.
	var pixels: Array[Vector2i] = []
	var a := Vector2i(start.round())
	var b := Vector2i(end.round())
	var dx := absi(b.x - a.x)
	var sx := 1 if a.x < b.x else -1
	var dy := -absi(b.y - a.y)
	var sy := 1 if a.y < b.y else -1
	var error := dx + dy
	while true:
		pixels.append(a)
		if a == b:
			break
		var twice := 2 * error
		if twice >= dy:
			error += dy
			a.x += sx
		if twice <= dx:
			error += dx
			a.y += sy
	return pixels


func _update_effects(delta: float) -> void:
	for index in range(_afterimages.size() - 1, -1, -1):
		_afterimages[index]["life"] = float(_afterimages[index]["life"]) - delta
		if float(_afterimages[index]["life"]) <= 0.0:
			_afterimages.remove_at(index)
	for index in range(_effects.size() - 1, -1, -1):
		var effect := _effects[index]
		effect["life"] = float(effect["life"]) - delta
		if float(effect["life"]) <= 0.0:
			_effects.remove_at(index)
		else:
			effect["position"] = Vector2(effect["position"]) + Vector2(effect["velocity"]) * delta
	for index in range(_blade_trails.size() - 1, -1, -1):
		_blade_trails[index]["life"] = float(_blade_trails[index]["life"]) - delta
		if float(_blade_trails[index]["life"]) <= 0.0:
			_blade_trails.remove_at(index)


func _blade_effect_pixels() -> Dictionary:
	var pixels: Dictionary = {}
	# Prefer the newest white core and limit the sweep to a crisp, readable footprint.
	for index in range(_blade_trails.size() - 1, -1, -1):
		var trail := _blade_trails[index]
		var core := Color("f2f8ff") if float(trail["life"]) > 0.085 else Color("8ebce8")
		var edge: Vector2i = trail.get("edge", Vector2i(0, 1))
		for pixel in trail["pixels"]:
			var point: Vector2i = pixel
			if not pixels.has(point) and pixels.size() < MAX_BLADE_PIXELS:
				pixels[point] = core
			var outside := point + edge
			if not pixels.has(outside) and pixels.size() < MAX_BLADE_PIXELS:
				pixels[outside] = Color("8ebce8")
	return pixels


func _draw() -> void:
	for ghost in _afterimages:
		draw_texture(ghost["texture"], Vector2(ghost["position"]).round() - global_position, Color(0.55, 0.75, 0.95, 0.30))
	for effect in _effects:
		var point := Vector2(effect["position"]).round() - global_position
		if effect.has("tail"):
			for pixel in _pixel_line(Vector2(effect["position"]), Vector2(effect["position"]) - Vector2(effect["tail"])):
				draw_rect(Rect2(Vector2(pixel) - global_position, Vector2.ONE), effect["color"])
		else:
			draw_rect(Rect2(point, Vector2.ONE), effect["color"])
	var blade_pixels := _blade_effect_pixels()
	for pixel in blade_pixels:
		draw_rect(Rect2(Vector2(pixel) - global_position, Vector2.ONE), blade_pixels[pixel])
