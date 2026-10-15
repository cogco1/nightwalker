extends CharacterBody2D

signal attack_started
signal attack_hit(target: Node)
signal combo_changed(stage: int)
signal hit_resolved(target: Node, damage: int, critical: bool, kind: String)
signal critical_hit(target: Node, damage: int, direction: Vector2)
signal normal_contact_stop(direction: Vector2)
signal special_started(kind: String, direction: Vector2)
signal landing_impact(point: Vector2)
## Once per attack stage on first contact: light / critical / heavy. GameSession maps it to a hit-stop.
signal impact(weight: StringName, direction: Vector2)
## Every attack or special start, with the move id (attack1-3, crouch_stab, air_attack1-3, rising_slash, ...).
signal move_started(move: StringName)
signal charge_started
signal charge_ready
signal charge_ended(released: bool)
## An enemy attack reached the hero: AttackResult and the attack (see receive_attack).
signal attack_received(result: int, attack: Dictionary)
## The perfect-dodge counter blinked behind this enemy and swings.
signal counter_started(enemy: Node2D)

enum ViewMode { TOP_DOWN, SIDE_VIEW }
## One combat state at a time; the old flags below are read-only views of it.
enum State { FREE, ATTACK, CHARGE, RECOVERY, HURT }
enum AttackResult { HIT, EVADE, PERFECT }

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
const PLAYER_FX = preload("res://scripts/player/player_fx.gd")
const MOVESET = preload("res://scripts/player/moves_long_blade.gd")
const ATTACK_BUFFER_SECONDS := 0.22
const ACCEL_SECONDS := 0.075
const BRAKE_SECONDS := 0.065
const STAND_SIZE := Vector2(12, 26)
const CROUCH_SIZE := Vector2(12, 14)
const BLADE_TRAIL_SECONDS := 0.14
const DASH_DISTANCE := 48.0
const LANDING_SECONDS := 2.0 / 60.0
const AIR_FALL_SPEED := 6.0
const DIVE_SPEED := 360.0
# Holding the attack button after a ground swing coils into a charge; releasing it full fires the heavy_slash
# move (moves_long_blade.gd), which always resolves as a critical.
const CHARGE_POSE_FRAME := 3
const CHARGE_FULL_SECONDS := 0.55
# The first part of the charge coils attack3 frames 0..CHARGE_POSE_FRAME and steps back a little.
const CHARGE_COIL_PORTION := 0.6
const CHARGE_BACKSTEP := 3.0
# One press of the dash key stabs towards the held direction (or facing); a press during an attack waits this long.
const DASH_BUFFER_SECONDS := 0.15
# Dodge offset: an attack press this soon after the dash ends gives the offset follow-up, and a dash this soon after a
# string hit ends keeps that string going.
const DODGE_OFFSET_SECONDS := 0.25
# Hit by an enemy: knocked back HURT_KNOCKBACK px over HURT_SLIDE_SECONDS, stunned and blinking red for HURT_SECONDS.
const HURT_SECONDS := 0.3
const HURT_SLIDE_SECONDS := 0.25
const HURT_KNOCKBACK := 20.0
const HURT_TINT := Color(1.0, 0.3, 0.3)
# A dash started at most this long before an enemy's hit window opens (or during it) is a perfect dodge.
const PERFECT_LEAD_SECONDS := 0.2
# The counter lands the hero this far past the enemy's centre, on its far side.
const COUNTER_BEHIND := 18.0
## Attack buttons in the combo graph: left click (light) and right click (heavy).
const ATTACK_INPUTS: Array[StringName] = [&"light", &"heavy"]
# Code-drawn blade circle of spinning moves: radius and centre height above the feet, native px.
const ARC_RADIUS := 20.0
const ARC_HEIGHT := 20.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var body_shape: CollisionShape2D = $BodyShape
## Effects layer (dust, sparks, trails, afterimages); first child, so it draws behind the sprite.
var fx: Node2D

var facing := "down"
var is_crouching := false
var is_running := false
var idle_bob_y := 0
var hit_targets: Dictionary = {}
var attack_direction := Vector2.DOWN
var _recovery_left := 0.0
var _crouch_exiting := false
var _crouch_frame := 0.0
var _jump_age := 0.0
var _landing_left := 0.0
var _dust_timer := 0.0
var _braking := false
var _brake_from_speed := 0.0
var _blade_paths: Dictionary = {}
var _last_blade_frame := -1
var _previous_blade_tip := Vector2.ZERO
var critical_roll_override := -1.0
var critical_rolls := 0
var last_critical_roll := 1.0
var stage_is_critical := false
## Current move id and its data row from MOVESET.MOVES (empty when not attacking).
var move_id: StringName = &""
var move: Dictionary = {}
## The move the current one counts as in the combo graph (itself, its `as`, or the hit a dodge offset resumes).
var _string_id: StringName = &""
var _last_string_id: StringName = &""
var _string_end_time := -INF
var _offset_from: StringName = &""
var _offset_until := 0.0
var _dash_started_at := -INF
## Set by GameSession during the perfect-dodge slow motion: enemy attacks cannot hit.
var invulnerable := false
var _counter_target: Node2D = null
var _hurt_brake := 0.0
var dash_start := Vector2.ZERO
var dash_end := Vector2.ZERO
var dash_executed := false
var _critical_stop_emitted := false
var _normal_stop_emitted := false
var _rng := RandomNumberGenerator.new()
var _mouse_attack_held := false
var _dash_phasing := false
var airflow_count := 0
var critical_impact_count := 0
var input_suspended := false
# freeze() owners by instance id -> halt; the process mode to restore once the last one lets go.
var _freeze_owners: Dictionary = {}
var _process_mode_before_freeze := Node.PROCESS_MODE_INHERIT
var state := State.FREE
## Physics ticks since the current move started.
var move_ticks := 0
## Combat clock: advances only in this player's physics step, so a hit-stop (paused tree) freezes it.
var combat_tick := 0
var combat_time := 0.0
## Button intents: name -> {tick, stage, expires}. A press is recorded as stage &"raw" and handled on the next
## physics tick: a light press becomes a &"queued" follow-up, a &"pending" new chain after the return pose,
## an attack, or is dropped; dash presses live DASH_BUFFER_SECONDS; a dive press runs on the next tick.
var _intents: Dictionary = {}

var is_attacking: bool:
	get: return state == State.ATTACK
var is_charging: bool:
	get: return state == State.CHARGE
var special_kind: String:
	get: return String(move.get("special", "")) if state == State.ATTACK else ""
var combo_stage: int:
	get: return int(MOVESET.MOVES.get(_string_id, move).get("stage", 0)) if state == State.ATTACK else 0
var queued_attack: bool:
	get: return _intent_stage(&"light") == &"queued"
var pending_new_attack: bool:
	get: return _intent_stage(&"light") == &"pending"
var attack_buffer_left: float:
	get: return maxf(0.0, float(_intents[&"light"]["expires"]) - combat_time) if _intent_stage(&"light") in [&"queued", &"pending"] else 0.0
var _mouse_attack_pending: bool:
	get: return _intent_stage(&"light") == &"raw"
var _jumps_used := 0
var _air_hold_left := 0.0
var charge_time := 0.0
var _ghost_frame := -1
var _rehit_frame := -1
var _arc_angle := NAN


func _ready() -> void:
	# GUI buttons consume clicks before gameplay receives unhandled input.
	set_process_input(false)
	set_process_unhandled_input(true)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	fx = PLAYER_FX.new()
	fx.name = "Fx"
	add_child(fx)
	move_child(fx, 0)
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
	show_idle()
	_update_sprite_layout()


func _physics_process(delta: float) -> void:
	if not CONTROLS.binding_pressed("attack_mouse"):
		_mouse_attack_held = false
	_try_end_dash_phasing()
	var was_grounded := is_on_floor()
	fx.step(delta)
	_landing_left = maxf(0.0, _landing_left - delta)
	_air_hold_left = maxf(0.0, _air_hold_left - delta)
	combat_tick += 1
	combat_time += delta
	if state == State.ATTACK:
		move_ticks += 1
	_recovery_left = maxf(0.0, _recovery_left - delta)
	if (state == State.RECOVERY or state == State.HURT) and _recovery_left <= 0.0:
		if state == State.HURT:
			sprite.modulate = Color.WHITE
		state = State.FREE
	_expire_intents()
	if _intents.has(&"dive"):
		_intents.erase(&"dive")
		request_dive_slash()
	var direction := _movement_input()
	if view_mode == ViewMode.SIDE_VIEW:
		if not was_grounded:
			velocity.y = DIVE_SPEED if move.get("dive", false) else (AIR_FALL_SPEED if _air_hold_left > 0.0 else velocity.y + gravity * delta)
			_jump_age += delta
		else:
			# A move with a jump keeps its take-off speed when it started between physics steps.
			velocity.y = float(move.get("jump", 0.0)) if is_attacking and move_ticks <= 1 else 0.0
			_jumps_used = 0
		if not is_attacking and not is_charging and _recovery_left <= 0.0:
			_update_crouch(delta)
		if Input.is_action_just_pressed("jump") and state != State.HURT and not is_crouching and _jumps_used < 2 and not move.get("dive", false) and (not was_grounded or not is_attacking):
			_jumps_used = 1 if was_grounded else 2
			_crouch_exiting = false
			velocity.y = jump_velocity
			_jump_age = 0.0
			_landing_left = 0.0
			_air_hold_left = 0.0
			fx.dust(global_position, 3)
	if not is_attacking and not is_charging and _recovery_left <= 0.0 and not direction.is_zero_approx():
		_update_facing(direction)
	if _intents.has(&"dash") and not is_charging:
		var dash_direction := int(signf(direction.x)) if direction.x != 0.0 else (1 if facing == "right" else -1)
		if request_dash_stab(dash_direction):
			_intents.erase(&"dash")
		elif is_attacking and sprite.frame < int(move.get("dash_cancel", -1)):
			# The press waits for this swing's dodge window.
			_intents[&"dash"]["expires"] = combat_time + DASH_BUFFER_SECONDS
	# During the perfect-dodge slow motion either button is the counter, whatever the hero is doing.
	if is_instance_valid(_counter_target) and (_intent_stage(&"light") == &"raw" or _intent_stage(&"heavy") == &"raw"):
		_start_counter()
	# Taps are processed while attacking too. Holding a button never auto-chains.
	if _mouse_attack_pending:
		var special := false
		if not is_attacking and _recovery_left <= 0.0 and view_mode == ViewMode.SIDE_VIEW:
			if Input.is_action_pressed("rising_modifier") and was_grounded:
				special = request_rising_slash()
		if not special:
			request_attack()
		if _mouse_attack_pending:
			_intents.erase(&"light")
	if _intent_stage(&"heavy") == &"raw":
		request_attack(&"heavy")
		if _intent_stage(&"heavy") == &"raw":
			_intents.erase(&"heavy")
	for input in ATTACK_INPUTS:
		if _intent_stage(input) == &"pending" and not is_attacking and _recovery_left <= 0.0:
			begin_attack(input)
	# New moves open a cancel window after their hit frames; some cut their clip short.
	if is_attacking and sprite.frame >= int(move.get("cancel", 1 << 30)):
		_chain_queued()
	if is_attacking and sprite.frame >= int(move.get("end", 1 << 30)):
		_on_animation_finished()
	is_running = Input.is_action_pressed("run") and not direction.is_zero_approx() and not is_crouching and not _crouch_exiting and not is_attacking and not is_charging and _recovery_left <= 0.0
	if is_attacking:
		var impulse := _attack_lunge_speed() if was_grounded or view_mode == ViewMode.TOP_DOWN else 0.0
		if view_mode == ViewMode.TOP_DOWN:
			velocity = attack_direction * impulse
		else:
			velocity.x = direction.x * crouch_speed if not was_grounded and move.get("steer", false) else attack_direction.x * impulse
	elif state == State.HURT:
		# Knocked back, braking to a stop inside the stun; the hero blinks red.
		if view_mode == ViewMode.TOP_DOWN:
			velocity = velocity.move_toward(Vector2.ZERO, _hurt_brake * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, _hurt_brake * delta)
		sprite.modulate = HURT_TINT if int(_recovery_left * 30.0) % 2 == 0 else Color.WHITE
	elif _recovery_left > 0.0 or is_charging:
		if view_mode == ViewMode.TOP_DOWN:
			velocity = Vector2.ZERO
		else:
			velocity.x = 0.0
		if is_charging:
			_update_charge(delta, was_grounded)
	else:
		var speed := crouch_speed if is_crouching or _crouch_exiting else (run_speed if is_running else move_speed)
		_update_move_velocity(direction, speed, delta)
		_update_animation(direction)
	move_and_slide()
	# Physics retains subpixel precision; every drawn pixel uses the same native grid.
	sprite.position = global_position.round() - global_position
	if is_charging and charge_time >= CHARGE_FULL_SECONDS:
		sprite.position.x += 1.0 if int(charge_time * 30.0) % 2 == 0 else -1.0
	if is_attacking and sprite.frame in move.get("ghosts", []) and sprite.frame != _ghost_frame:
		_ghost_frame = sprite.frame
		fx.ghost(sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame), global_position + sprite.offset, 0.12)
	if is_attacking and sprite.frame in move.get("rehit", []) and sprite.frame != _rehit_frame:
		_rehit_frame = sprite.frame
		hit_targets.clear()
		_normal_stop_emitted = false
		_critical_stop_emitted = false
	if is_attacking and move.has("arc"):
		_update_arc()
	_update_sprite_layout()
	if view_mode == ViewMode.SIDE_VIEW and not was_grounded and is_on_floor():
		_landing_left = LANDING_SECONDS
		_jump_age = 0.0
		_jumps_used = 0
		_air_hold_left = 0.0
		fx.dust(global_position, 5)
	if is_attacking and _in_active_frames():
		if move.get("pierce", false):
			if not dash_executed:
				_perform_dash()
		else:
			_apply_attack_hits()
		_update_blade_trail()
		if move.get("launcher", false) and airflow_count == 0:
			_spawn_airflow(global_position, true)
	if move.get("dive", false) and is_on_floor():
		var landed := move
		if landed.has("shockwave"):
			_shockwave(landed["shockwave"])
		_on_animation_finished()
		_set_recovery(float(landed.get("recovery", LANDING_SECONDS)))
		_set_manual_frame("dive_slash_" + facing, 14)
		fx.clear_trails()
		fx.sparks(global_position + Vector2(-8, -1))
		fx.sparks(global_position + Vector2(8, -1))
		fx.add({"position": global_position + Vector2(-8, -1), "velocity": Vector2(-100, -4), "tail": Vector2(-4, 0), "life": 0.14, "color": PLAYER_FX.BLUE})
		fx.add({"position": global_position + Vector2(8, -1), "velocity": Vector2(100, -4), "tail": Vector2(4, 0), "life": 0.14, "color": PLAYER_FX.WHITE})
		landing_impact.emit(global_position)
	if is_running and (view_mode == ViewMode.TOP_DOWN or is_on_floor()):
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			fx.dust(global_position - _facing_vector() * 5.0, 2)
			_dust_timer = 0.09
	else:
		_dust_timer = 0.0
	fx.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	_input(event)


## Public entry for input forwarded while the tree is paused (hit-stop): only records button edges.
func handle_input(event: InputEvent) -> void:
	_input(event)


func clear_input_buffer() -> void:
	if is_charging:
		_cancel_charge()
	_intents.clear()
	_mouse_attack_held = false


## Stops the player for a dialogue, a keypad or the settings menu. Each owner holds one freeze and the player
## resumes when the last owner calls unfreeze(owner). halt also zeroes the velocity at both ends; the settings
## menu passes false so a jump opened mid-air keeps its arc.
func freeze(owner: Object, halt := true) -> void:
	var id := owner.get_instance_id()
	if _freeze_owners.has(id):
		return
	if _freeze_owners.is_empty():
		_process_mode_before_freeze = process_mode
	_freeze_owners[id] = halt
	if halt:
		velocity = Vector2.ZERO
	input_suspended = true
	clear_input_buffer()
	CONTROLS.release_actions()
	process_mode = Node.PROCESS_MODE_DISABLED


func unfreeze(owner: Object) -> void:
	var id := owner.get_instance_id()
	if not _freeze_owners.has(id):
		return
	var halt: bool = _freeze_owners[id]
	_freeze_owners.erase(id)
	if not _freeze_owners.is_empty():
		return
	process_mode = _process_mode_before_freeze
	if halt:
		velocity = Vector2.ZERO
	input_suspended = false
	clear_input_buffer()
	CONTROLS.release_actions()


func is_frozen() -> bool:
	return not _freeze_owners.is_empty()


func _input(event: InputEvent) -> void:
	if input_suspended:
		return
	if event is InputEventMouseButton and event.is_action("attack"):
		if not event.pressed:
			_mouse_attack_held = false
		elif not _mouse_attack_held:
			_mouse_attack_held = true
			_press(&"light")
	if event is InputEventMouseButton and event.pressed and event.is_action("heavy_mouse"):
		_press(&"heavy")
	if event is InputEventKey and not event.echo and event.is_action_pressed("dash_modifier"):
		_press(&"dash", DASH_BUFFER_SECONDS)
	if view_mode != ViewMode.SIDE_VIEW or not event is InputEventKey or event.echo:
		return
	if event.is_action_pressed("crouch"):
		if get_tree().paused:
			# Forwarded during the hit-stop: recorded only, so the frozen frame never changes; acts after it.
			_press(&"dive")
		else:
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
		show_idle()
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


func request_attack(input: StringName = &"light") -> bool:
	if not is_attacking:
		if _recovery_left > 0.0:
			# A fresh tap during the short return pose starts one new chain after it.
			_buffer_attack(input, &"pending", maxf(ATTACK_BUFFER_SECONDS, _recovery_left + 0.05))
			return true
		return begin_attack(input)
	if _next_move(_string_id, input) == &"":
		return false
	var fps: float = sprite.sprite_frames.get_animation_speed(sprite.animation) * sprite.speed_scale
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	var remaining := (float(count - sprite.frame) - sprite.frame_progress) / maxf(1.0, fps)
	# Early double taps are deliberate inputs too, so keep one tap until this hit ends.
	_buffer_attack(input, &"queued", clampf(maxf(ATTACK_BUFFER_SECONDS, remaining + 0.05), ATTACK_BUFFER_SECONDS, 0.55))
	return true


func begin_attack(input: StringName = &"light") -> bool:
	if is_attacking or _recovery_left > 0.0:
		return false
	var first := &""
	if combat_time < _offset_until:
		first = _next_move(&"dash_stab", input)
	if first == &"":
		first = _next_move(&"", input)
	if is_crouching:
		first = &"crouch_stab" if input == &"light" else &""
	if first == &"":
		return false
	attack_direction = _facing_vector()
	_clear_attack_intents()
	_start_move(first)
	return true


## First follow-up the combo graph allows from here: side_only moves need the side view, ground moves the floor.
func _next_move(current: StringName, input: StringName) -> StringName:
	for id in MOVESET.next_moves(current, input):
		var row: Dictionary = MOVESET.MOVES[id]
		if row.get("side_only", false) and view_mode != ViewMode.SIDE_VIEW:
			continue
		if row.get("ground", false) and view_mode == ViewMode.SIDE_VIEW and not is_on_floor():
			continue
		return id
	return &""


## Starts the buffered follow-up (light or heavy) when the combo graph has one from the current move.
func _chain_queued() -> bool:
	for input in ATTACK_INPUTS:
		if _intent_stage(input) == &"queued" and float(_intents[input]["expires"]) > combat_time:
			var next := _next_move(_string_id, input)
			if next != &"":
				_clear_attack_intents()
				_start_move(next)
				return true
	return false


# Starts a move from MOVESET.MOVES: state, hang time, critical roll, animation, rate and start frame.
func _start_move(id: StringName) -> void:
	move_id = id
	move = MOVESET.MOVES[id]
	_string_id = move.get("as", id)
	if move.get("resumes", false):
		# Dodge offset: stands in for the next light hit of the string the dash interrupted.
		var resumed := _next_move(_offset_from, &"light")
		_string_id = resumed if resumed != &"" else &"attack1"
	_offset_until = 0.0
	state = State.ATTACK
	move_ticks = 0
	is_running = false
	var airborne := view_mode == ViewMode.SIDE_VIEW and not is_on_floor()
	var air: Dictionary = move.get("air", {})
	if airborne and air.has("hold"):
		_air_hold_left = air["hold"]
		velocity.y = air["fall"]
	hit_targets.clear()
	stage_is_critical = false
	_critical_stop_emitted = false
	_normal_stop_emitted = false
	match move.get("crit", &"none"):
		&"roll":
			critical_rolls += 1
			last_critical_roll = critical_roll_override if critical_roll_override >= 0.0 else _rng.randf()
			stage_is_critical = last_critical_roll < MOVESET.CRIT_CHANCE
		&"always":
			stage_is_critical = true
	_last_blade_frame = -1
	_previous_blade_tip = Vector2.ZERO
	_ghost_frame = -1
	_rehit_frame = -1
	_arc_angle = NAN
	if move.has("jump") and view_mode == ViewMode.SIDE_VIEW and is_on_floor():
		velocity.y = float(move["jump"])
		_jumps_used = 1
		_jump_age = 0.0
		_landing_left = 0.0
		_crouch_exiting = false
	if move.get("dive", false):
		# Dives pass through targets until the hero stands clear of them again.
		_dash_phasing = true
		collision_mask = 1
	if move.get("launcher", false):
		airflow_count = 0
	var prefix: String = move["air_anim"] if airborne and move.has("air_anim") else move["anim"]
	var animation := prefix + "_" + facing
	# Compatibility keeps the project loadable while new drawn clips are imported.
	if not sprite.sprite_frames.has_animation(animation):
		animation = "stab_" + facing
	sprite.stop()
	sprite.speed_scale = float(move["fps"]) / sprite.sprite_frames.get_animation_speed(animation)
	sprite.play(animation)
	if move.has("start_frame"):
		sprite.set_frame_and_progress(int(move["start_frame"]), 0.0)
	combo_changed.emit(combo_stage)
	attack_started.emit()
	move_started.emit(move_id)


func _attack_lunge_speed() -> float:
	var lunge: Dictionary = move.get("lunge", {})
	if lunge.is_empty():
		return 0.0
	var first := int(lunge["from"])
	var last := _active_last()
	if sprite.frame < first or sprite.frame > last:
		return 0.0
	var window := float(last - first + 1)
	var phase := (float(sprite.frame - first) + sprite.frame_progress) / window
	var duration := window / float(move["fps"])
	# The drawn swing advances a few native pixels, easing in and out safely.
	return sin(phase * PI) * float(lunge["px"]) * PI / (2.0 * duration)


func attack_origin() -> Vector2:
	var height := 4.0 if view_mode == ViewMode.TOP_DOWN else float(move.get("box", MOVESET.BLADE).get("height", MOVESET.ORIGIN_HEIGHT))
	return global_position + Vector2(0, -height)


func _attack_active_start() -> int:
	if view_mode == ViewMode.SIDE_VIEW and move.has("side_first"):
		return int(move["side_first"])
	return move.get("active", Vector2i(6, 9)).x


## Last frame that hits; negative keeps hitting until the move ends.
func _active_last() -> int:
	return move.get("active", Vector2i(6, 9)).y


func _in_active_frames() -> bool:
	if not move.has("active"):
		return false
	return sprite.frame >= _attack_active_start() and (_active_last() < 0 or sprite.frame <= _active_last())


func attack_box() -> Rect2:
	var box: Dictionary = move.get("box", MOVESET.BLADE)
	if box.has("rect"):
		var rectangle: Rect2 = box["rect"]
		return Rect2(global_position + attack_direction * float(box.get("forward", 0.0)) + rectangle.position, rectangle.size)
	var extra_reach := MOVESET.SIDE_EXTRA_REACH if view_mode == ViewMode.SIDE_VIEW else 0.0
	var length := float(box["length"]) + extra_reach
	var width := float(box["width"])
	var size := Vector2(length, width)
	if view_mode == ViewMode.TOP_DOWN and attack_direction.x == 0.0:
		size = Vector2(width, length)
	var center := attack_origin() + attack_direction * (float(box["reach"]) + extra_reach / 2.0)
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


# row: the move data that hit (the current move, or a part of it such as its landing shockwave).
func _resolve_hit(target: Node, point: Vector2, row: Dictionary = {}) -> bool:
	if row.is_empty():
		row = move
	var damage := attack_damage * int(row.get("dmg_mult", 1)) * (MOVESET.CRIT_MULT if stage_is_critical else 1)
	if not target.call("take_damage", damage):
		return false
	hit_targets[target.get_instance_id()] = true
	if target.has_method("receive_hit_reaction"):
		target.call("receive_hit_reaction", attack_direction, row.get("launch", false), view_mode == ViewMode.SIDE_VIEW and not is_on_floor() and row.get("juggle", false))
	elif row.get("launch", false) and target.has_method("knock_up"):
		target.call("knock_up", attack_direction)
	if row.has("knockback") and target.has_method("knock_back"):
		target.call("knock_back", attack_direction, float(row["knockback"]))
	var weight := _impact_weight(row)
	fx.sparks(point)
	fx.impact(point, weight, attack_direction, global_position)
	attack_hit.emit(target)
	hit_resolved.emit(target, damage, stage_is_critical, special_kind)
	if stage_is_critical and not _critical_stop_emitted:
		_critical_stop_emitted = true
		critical_impact_count += 1
		for axis in [Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
			fx.trail(PLAYER_FX.pixel_line(point, point + axis), Vector2i(0, 1), BLADE_TRAIL_SECONDS)
		critical_hit.emit(target, damage, attack_direction)
		impact.emit(weight, attack_direction)
	elif not stage_is_critical and not _normal_stop_emitted:
		_normal_stop_emitted = true
		normal_contact_stop.emit(attack_direction)
		impact.emit(weight, attack_direction)
	return true


func request_rising_slash() -> bool:
	if view_mode != ViewMode.SIDE_VIEW or is_attacking or _recovery_left > 0.0 or is_crouching or not is_on_floor():
		return false
	# The move's jump field lifts the hero.
	_start_special("rising_slash")
	return true


func request_dive_slash() -> bool:
	if view_mode != ViewMode.SIDE_VIEW or is_on_floor() or move.get("dive", false) or state == State.HURT:
		return false
	_air_hold_left = 0.0
	velocity.y = DIVE_SPEED
	_start_special("dive_slash")
	fx.queue_redraw()
	return true


func request_dash_stab(direction: int) -> bool:
	var cancelling := is_attacking and sprite.frame >= int(move.get("dash_cancel", 1 << 30))
	if view_mode != ViewMode.SIDE_VIEW or (is_attacking and not cancelling) or _recovery_left > 0.0 or is_crouching:
		return false
	if direction == 0:
		return false
	# The string the dash cuts short (or that just ended) resumes after it.
	if cancelling:
		_offset_from = _string_id
	elif combat_time - _string_end_time <= DODGE_OFFSET_SECONDS:
		_offset_from = _last_string_id
	else:
		_offset_from = &""
	facing = "right" if direction > 0 else "left"
	_crouch_exiting = false
	_dash_started_at = combat_time
	dash_executed = false
	dash_start = global_position
	dash_end = global_position
	_start_special("dash_stab")
	return true


func _start_special(kind: String) -> void:
	attack_direction = Vector2.DOWN if kind == "dive_slash" else _facing_vector()
	_clear_attack_intents()
	airflow_count = 0
	_start_move(StringName(kind))
	special_started.emit(kind, attack_direction)


func _perform_dash() -> void:
	dash_executed = true
	dash_start = global_position
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	fx.ghost(texture, dash_start + sprite.offset, 0.12)
	_dash_phasing = true
	collision_mask = 1
	move_and_collide(attack_direction * DASH_DISTANCE, false, 0.001)
	dash_end = global_position
	fx.ghost(texture, dash_start.lerp(dash_end, 0.5) + sprite.offset, 0.09)
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
	if move.get("dive", false) and not is_on_floor():
		_set_manual_frame(String(move["anim"]) + "_" + facing, 11)
		return
	if move.has("then"):
		_start_move(move["then"])
		return
	if _chain_queued():
		return
	var air: Dictionary = move.get("air", {})
	if air.has("end_hold") and not is_on_floor():
		_air_hold_left = air["end_hold"]
		velocity.y = air["fall"]
	var airborne := view_mode == ViewMode.SIDE_VIEW and not is_on_floor()
	var recovery := float(move["recovery"]) if move.has("recovery") else (1.0 if airborne else 2.0) / float(move["fps"])
	var coil: bool = _mouse_attack_held and move.get("chain", false) and (view_mode == ViewMode.TOP_DOWN or is_on_floor())
	stage_is_critical = false
	_clear_attack_intents()
	if move.get("dodge", false):
		_offset_until = combat_time + DODGE_OFFSET_SECONDS
	else:
		_last_string_id = _string_id
		_string_end_time = combat_time
	move_id = &""
	move = {}
	_set_recovery(recovery)
	sprite.pause()
	combo_changed.emit(0)
	if coil:
		_set_recovery(0.0)
		_begin_charge()


func _begin_charge() -> void:
	state = State.CHARGE
	charge_time = 0.0
	is_running = false
	_set_manual_frame("attack3_" + facing, 0)
	fx.dust(global_position, 4)
	charge_started.emit()


func _update_charge(delta: float, grounded: bool) -> void:
	if view_mode == ViewMode.SIDE_VIEW and not grounded:
		_cancel_charge()
		return
	if _mouse_attack_held:
		var was_full := charge_time >= CHARGE_FULL_SECONDS
		charge_time += delta
		var coil := clampf(charge_time / (CHARGE_FULL_SECONDS * CHARGE_COIL_PORTION), 0.0, 1.0)
		var pose := mini(CHARGE_POSE_FRAME, int(coil * (CHARGE_POSE_FRAME + 1)))
		if sprite.frame != pose:
			_set_manual_frame("attack3_" + facing, pose)
		if coil < 1.0:
			# Settle back into the stance while coiling.
			var back := -_facing_vector() * CHARGE_BACKSTEP / (CHARGE_FULL_SECONDS * CHARGE_COIL_PORTION)
			if view_mode == ViewMode.TOP_DOWN:
				velocity = back
			else:
				velocity.x = back.x
		var tip := _blade_tip_for_frame(sprite.frame)
		var tick := int(charge_time * 20.0) != int((charge_time - delta) * 20.0)
		if tick:
			# Light rises off the body while the charge builds.
			fx.mote(global_position, was_full)
		if not was_full and charge_time >= CHARGE_FULL_SECONDS:
			fx.sparks(tip)
			fx.dust(global_position, 6)
			charge_ready.emit()
		elif was_full and int(charge_time * 10.0) != int((charge_time - delta) * 10.0):
			# Full: a blinking white star on the tip says "release now".
			fx.star(tip)
		elif not was_full and tick:
			# Coiling: light gathers onto the blade from a ring that tightens as the charge fills.
			fx.gather(tip, lerpf(14.0, 4.0, charge_time / CHARGE_FULL_SECONDS), charge_time * 11.0)
		return
	if charge_time >= CHARGE_FULL_SECONDS:
		_release_heavy_slash()
	else:
		_cancel_charge()


func _cancel_charge() -> void:
	charge_time = 0.0
	_set_recovery(2.0 / float(MOVESET.MOVES[&"attack3"]["fps"]))
	charge_ended.emit(false)


func _release_heavy_slash() -> void:
	charge_time = 0.0
	charge_ended.emit(true)
	attack_direction = _facing_vector()
	airflow_count = 0
	_start_move(&"heavy_slash")
	_spawn_airflow(global_position, false)
	special_started.emit("heavy_slash", attack_direction)


func _press(intent: StringName, seconds := INF) -> void:
	_intents[intent] = {"tick": combat_tick, "stage": &"raw", "expires": combat_time + seconds}


func _buffer(intent: StringName, stage: StringName, seconds: float) -> void:
	_intents[intent] = {"tick": combat_tick, "stage": stage, "expires": combat_time + seconds}


# A light or heavy follow-up replaces any other buffered one: the latest press wins.
func _buffer_attack(input: StringName, stage: StringName, seconds: float) -> void:
	_clear_attack_intents()
	_buffer(input, stage, seconds)


func _clear_attack_intents() -> void:
	for input in ATTACK_INPUTS:
		_intents.erase(input)


func _intent_stage(intent: StringName) -> StringName:
	return _intents[intent]["stage"] if _intents.has(intent) else &""


func _expire_intents() -> void:
	for intent in _intents.keys():
		if combat_time >= float(_intents[intent]["expires"]):
			_intents.erase(intent)


## Return pose (or none): RECOVERY until the timer runs out in the physics step.
func _set_recovery(seconds: float) -> void:
	_recovery_left = seconds
	state = State.RECOVERY if seconds > 0.0 else State.FREE


## Body rectangle enemy attacks test against.
func hurtbox() -> Rect2:
	var size := (body_shape.shape as RectangleShape2D).size
	return Rect2(body_shape.global_position - size / 2.0, size)


## An enemy attack reaches the hero (scripts/enemies/enemy_attacker.gd). attack: {source, direction (the push),
## contact (false: the hit window closed without touching the hero), window_age (seconds since the attacker's hit
## window opened), knockback (px)}. A dash started at most PERFECT_LEAD_SECONDS before the window opened, or inside
## it, is PERFECT; otherwise a dash's invulnerability or being out of the way is EVADE; else HIT, into HURT.
func receive_attack(attack: Dictionary) -> int:
	var result := AttackResult.HIT
	if invulnerable:
		result = AttackResult.EVADE
	elif combat_time - _dash_started_at <= float(attack.get("window_age", 0.0)) + PERFECT_LEAD_SECONDS:
		result = AttackResult.PERFECT
	elif not attack.get("contact", true) or (state == State.ATTACK and move.get("dodge", false)):
		result = AttackResult.EVADE
	if result == AttackResult.HIT:
		_take_hit(attack)
	attack_received.emit(result, attack)
	return result


## GameSession opens the counter on a perfect dodge (the enemy that missed) and closes it when the slow motion ends.
func open_counter(enemy: Node2D) -> void:
	_counter_target = enemy


func close_counter() -> void:
	_counter_target = null


# Perfect-dodge counter: blinks to the far side of the enemy (the near side if a wall is there) and cuts it with
# counter_slash, a sure critical with the heavy freeze.
func _start_counter() -> void:
	var enemy := _counter_target
	_counter_target = null
	_clear_attack_intents()
	if is_charging:
		_cancel_charge()
	var from := global_position
	var side := 1.0 if from.x <= enemy.global_position.x else -1.0
	var to := Vector2(enemy.global_position.x + side * COUNTER_BEHIND, from.y)
	if not _clear_at(to):
		side = -side
		to = Vector2(enemy.global_position.x + side * COUNTER_BEHIND, from.y)
		if not _clear_at(to):
			to = from
	fx.ghost(sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame), from + sprite.offset, 0.2)
	for lane in range(3):
		var y := -10.0 - lane * 6.0
		fx.add({"position": to + Vector2(0, y), "velocity": Vector2.ZERO, "tail": (to - from) * (1.0 - lane * 0.25),
			"life": 0.12, "color": PLAYER_FX.WHITE if lane == 1 else PLAYER_FX.BLUE})
	global_position = to
	facing = "left" if side > 0.0 else "right"
	attack_direction = _facing_vector()
	_start_move(&"counter_slash")
	counter_started.emit(enemy)


func _clear_at(point: Vector2) -> bool:
	var shape := RectangleShape2D.new()
	# Inset, so standing on the floor is not a collision.
	shape.size = (body_shape.shape as RectangleShape2D).size - Vector2(0.2, 0.2)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point + body_shape.position)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


# Interrupts the move or charge, knocks the hero back and stuns it (HURT) for HURT_SECONDS.
func _take_hit(attack: Dictionary) -> void:
	if is_charging:
		_cancel_charge()
	_clear_attack_intents()
	stage_is_critical = false
	move_id = &""
	move = {}
	_string_id = &""
	_air_hold_left = 0.0
	is_running = false
	state = State.HURT
	_recovery_left = HURT_SECONDS
	var push: Vector2 = attack.get("direction", -_facing_vector())
	var speed := 2.0 * float(attack.get("knockback", HURT_KNOCKBACK)) / HURT_SLIDE_SECONDS
	_hurt_brake = speed / HURT_SLIDE_SECONDS
	if view_mode == ViewMode.SIDE_VIEW:
		velocity.x = signf(push.x) * speed
		velocity.y = minf(velocity.y, 0.0)
		_set_manual_frame("jump_" + facing, 13)
	else:
		velocity = push.normalized() * speed
	sprite.modulate = HURT_TINT
	fx.clear_trails()
	fx.sparks(global_position + Vector2(0, -15))
	combo_changed.emit(0)


func show_idle() -> void:
	var animation := "idle_" + facing
	if sprite.sprite_frames.has_animation(animation):
		_play_loop(animation, false)
	else:
		_set_manual_frame("stab_" + facing, 0)


# Hit-stop / impact weight of the current attack stage, from the move data (or the part of it that hit).
func _impact_weight(row: Dictionary = {}) -> StringName:
	if row.is_empty():
		row = move
	return row.get("crit_stop", &"critical") if stage_is_critical else row.get("stop", &"light")


## Landing wave of a dive move: hits every grounded target within half_width of the feet once more.
func _shockwave(wave: Dictionary) -> void:
	hit_targets.clear()
	_normal_stop_emitted = false
	_critical_stop_emitted = false
	stage_is_critical = wave.get("crit", false)
	var half := float(wave["half_width"])
	var origin := global_position + Vector2(0, -8)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(half * 2.0, 16.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, origin)
	query.collision_mask = 2
	query.exclude = [get_rid()]
	var space := get_world_2d().direct_space_state
	for result in space.intersect_shape(query, maxi(32, get_tree().get_node_count())):
		var target: Node = result["collider"]
		if not target.has_method("take_damage") or hit_targets.has(target.get_instance_id()):
			continue
		var point: Vector2 = target.call("damage_point")
		if space.intersect_ray(PhysicsRayQueryParameters2D.create(origin, point, 1)).is_empty():
			_resolve_hit(target, point, wave)
	fx.dust(global_position, 8)
	for side in [-1.0, 1.0]:
		for lane in range(3):
			fx.add({"position": global_position + Vector2(side * 6.0, -1.0 - lane * 2.0), "velocity": Vector2(side * (240.0 - lane * 50.0), -lane * 10.0),
				"tail": Vector2(side * 5.0, 0), "life": 0.15, "color": PLAYER_FX.WHITE if lane == 0 else PLAYER_FX.BLUE})


## Code-drawn blade circle of spinning moves: the move's arc {from, to} (degrees from forward, negative is up) is
## swept with the move's progress as white-core, blue-edge segments through the effects layer.
func _update_arc() -> void:
	var arc: Dictionary = move["arc"]
	var first := int(move.get("start_frame", 0))
	var last := int(move.get("end", sprite.sprite_frames.get_frame_count(sprite.animation)))
	var progress := clampf((float(sprite.frame - first) + sprite.frame_progress) / float(maxi(1, last - first)), 0.0, 1.0)
	var angle := lerpf(float(arc["from"]), float(arc["to"]), progress)
	if is_nan(_arc_angle):
		_arc_angle = float(arc["from"])
	var center := global_position + Vector2(0, -ARC_HEIGHT)
	var side := 1.0 if attack_direction.x >= 0.0 else -1.0
	var steps := ceili(absf(angle - _arc_angle) / 15.0)
	for index in range(steps):
		var a := deg_to_rad(lerpf(_arc_angle, angle, float(index) / steps))
		var b := deg_to_rad(lerpf(_arc_angle, angle, float(index + 1) / steps))
		for ring in [[ARC_RADIUS, PLAYER_FX.WHITE], [ARC_RADIUS + 1.0, PLAYER_FX.BLUE]]:
			var start: Vector2 = center + Vector2(cos(a) * side, sin(a)) * float(ring[0])
			var end: Vector2 = center + Vector2(cos(b) * side, sin(b)) * float(ring[0])
			fx.add({"position": end, "velocity": Vector2.ZERO, "tail": end - start, "life": 0.12, "color": ring[1]})
	_arc_angle = angle


func _spawn_airflow(point: Vector2, rising: bool) -> void:
	airflow_count += 3
	fx.airflow(point, attack_direction, rising)


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
	if move.get("crouched", false):
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
	fx.trail(PLAYER_FX.pixel_line(previous, tip), edge, BLADE_TRAIL_SECONDS)
	_previous_blade_tip = tip
	_last_blade_frame = sprite.frame
