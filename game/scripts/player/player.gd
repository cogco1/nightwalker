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
## Every contact that shows hit feedback, where it landed (kill folded into weight); the impact prototype reads it.
signal struck(point: Vector2, weight: StringName, direction: Vector2, killed: bool)
## Every attack or special start, with the move id (attack1-3, crouch_stab, air_attack1-3, rising_slash, ...).
signal move_started(move: StringName)
## A blade commits after its wind-up; swing audio follows the animation rather than the button press.
signal swing_released(move: StringName)
signal jump_chase_started(target: Node2D)
signal charge_started
signal charge_ready
signal charge_ended(released: bool)
## An enemy attack reached the hero: AttackResult and the attack (see receive_attack).
signal attack_received(result: int, attack: Dictionary)
## The perfect-dodge counter blinked behind this enemy and swings.
signal counter_started(enemy: Node2D)
signal perfect_dodge_started

enum ViewMode { TOP_DOWN, SIDE_VIEW }
## One combat state at a time; the old flags below are read-only views of it.
enum State { FREE, ATTACK, CHARGE, RECOVERY, HURT, DODGE }
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
const SHIFT_GESTURE = preload("res://scripts/player/shift_gesture.gd")
const ATTACK_BUFFER_SECONDS := 0.22
const ACCEL_SECONDS := 0.075
const BRAKE_SECONDS := 0.065
const STAND_SIZE := Vector2(12, 26)
const CROUCH_SIZE := Vector2(12, 14)
const BLADE_TRAIL_SECONDS := 0.14
const DASH_DISTANCE := 48.0
# Travel is integrated through physics, easing in/out over eleven ticks at 60 Hz.
const DASH_SECONDS := 0.18
const DASH_BLADE_REACH := 35.0
# A successful charged launch opens an optional jump cancel; the combat clock freezes during hit-stop.
const CHASE_WINDOW_SECONDS := 0.50
const CHASE_ASSIST_SECONDS := 0.60
const CHASE_MAX_SPEED := 280.0
const CHASE_ACCELERATION := 1400.0
const CHASE_GAP := 23.0
const LANDING_SECONDS := 2.0 / 60.0
const AIR_FALL_SPEED := 6.0
const DIVE_SPEED := 360.0
# Ground primary input waits without a charge pose until the hold threshold; release taps attack directly.
# A confirmed hold coils without an opening light, and a full hold fires heavy_slash
# move (moves_long_blade.gd), which always resolves as a critical.
const PRIMARY_TAP_SECONDS := 0.24
const CHARGE_POSE_FRAME := 3
const SIDE_CHARGE_POSE_FRAME := 6
const CHARGE_FULL_SECONDS := 0.55
# After a hold is confirmed, coil side poses 0..6 (top-down 0..3) with a small backstep.
const CHARGE_COIL_PORTION := 0.82
const CHARGE_BACKSTEP := 3.0
# Modifier + held direction + fresh attack click buffers a thrust through a light swing's cancel window.
const DASH_BUFFER_SECONDS := 0.15
const DODGE_SECONDS := 0.22
const ROLL_SECONDS := 0.30
const DODGE_DISTANCE := 36.0
# Dodge offset: an attack press this soon after the dash ends gives the offset follow-up, and a dash this soon after a
# string hit ends keeps that string going.
const DODGE_OFFSET_SECONDS := 0.25
# Hit by an enemy: knocked back HURT_KNOCKBACK px over HURT_SLIDE_SECONDS, stunned and blinking red for HURT_SECONDS.
const HURT_SECONDS := 0.3
const HIT_INVULNERABILITY_SECONDS := 0.65
const MELEE_PROTECTION_SECONDS := 0.90
const HURT_SLIDE_SECONDS := 0.25
const HURT_KNOCKBACK := 20.0
const HURT_TINT := Color(1.0, 0.3, 0.3)
# A dash started at most this long before an enemy's hit window opens (or during it) is a perfect dodge.
const PERFECT_LEAD_SECONDS := 0.2
# The counter lands the hero this far past the enemy's centre, on its far side.
const COUNTER_BEHIND := 18.0
const COUNTER_MAX_DISTANCE := 260.0
const COUNTER_WINDOW_SECONDS := 1.2
const PERFECT_POSE_SECONDS := 0.24
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
var _counter_until := -INF
var _perfect_pose_at := -INF
var _perfect_ghost_left := 0.0

var counter_ready: bool:
	get: return combat_time < _counter_until and view_mode == ViewMode.SIDE_VIEW

var perfect_pose_left: float:
	get: return maxf(0.0, PERFECT_POSE_SECONDS - (combat_time - _perfect_pose_at))
var _hurt_brake := 0.0
var _hit_invulnerable_until := -INF
var _melee_protected_until := -INF

var melee_protection_left: float:
	get: return maxf(0.0,_melee_protected_until-combat_time)
var hurt_from_back := false
var _hurt_push := Vector2.ZERO
var _hurt_started_at := -INF
var hurt_pose_shift := Vector2.ZERO

var hit_invulnerability_left: float:
	get: return maxf(0.0, _hit_invulnerable_until - combat_time)
var dash_start := Vector2.ZERO
var dash_end := Vector2.ZERO
## True once the entire rush finishes or a wall stops it; never on its first moving tick.
var dash_executed := false
var _dash_elapsed := 0.0
var _dash_ghost_left := 0.0
var _chase_target: WeakRef
var _chase_window_until := 0.0
var _chase_left := 0.0
var _chase_direction := 1.0
var _chase_speed := 0.0

var is_jump_chasing: bool:
	get: return _chase_left > 0.0
var _critical_stop_emitted := false
var _normal_stop_emitted := false
var _kill_stop_emitted := false
var _swing_release_emitted := false
var _rng := RandomNumberGenerator.new()
var _mouse_attack_held := false
# Mouse edges are recorded during pauses; only physics may start a charge or convert a tap into a swing.
var _primary_press: Dictionary = {}
var _charge_started_at := 0.0
var _followup_from: StringName = &""
var _followup_until := -INF
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
## an attack, or is dropped; thrust chords and released evade taps live DASH_BUFFER_SECONDS; dives run next tick.
var _intents: Dictionary = {}
var _shift_gesture = SHIFT_GESTURE.new()
var _dodge_left := 0.0
var _dodge_duration := DODGE_SECONDS
var _dodge_direction := Vector2.RIGHT
var _dodge_ghost_left := 0.0
var _dodge_low := false

var is_dodging: bool:
	get: return state == State.DODGE

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
var _charge_announced := false
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
	_update_hit_feedback()
	_expire_intents()
	if _intents.has(&"dive"):
		_intents.erase(&"dive")
		request_dive_slash()
	var direction := _movement_input()
	var chase_takeoff := false
	if view_mode == ViewMode.SIDE_VIEW:
		if not was_grounded:
			velocity.y = DIVE_SPEED if move.get("dive", false) else (AIR_FALL_SPEED if _air_hold_left > 0.0 else velocity.y + gravity * delta)
			_jump_age += delta
		else:
			# A move with a jump keeps its take-off speed when it started between physics steps.
			velocity.y = float(move.get("jump", 0.0)) if is_attacking and move_ticks <= 1 else 0.0
			_jumps_used = 0
		if not is_attacking and not is_charging and not is_dodging and _recovery_left <= 0.0:
			_update_crouch(delta)
		var chase_started := _intents.has(&"chase_jump") and request_jump_chase()
		chase_takeoff = chase_started
		if chase_started:
			_intents.erase(&"chase_jump")
		if not chase_started and Input.is_action_just_pressed("jump") and state != State.HURT and not is_dodging and not is_crouching and _jumps_used < 2 and not move.get("dive", false) and (not was_grounded or not is_attacking):
			_jumps_used = 1 if was_grounded else 2
			_crouch_exiting = false
			velocity.y = jump_velocity
			_jump_age = 0.0
			_landing_left = 0.0
			_air_hold_left = 0.0
			fx.dust(global_position, 3)
	if not is_attacking and not is_charging and not is_dodging and _recovery_left <= 0.0 and not direction.is_zero_approx():
		_update_facing(direction)
	# Perfect-dodge counter takes priority over both a buffered evade and a modifier thrust.
	if counter_ready and (_intent_stage(&"light") == &"raw" or _intent_stage(&"heavy") == &"raw"):
		if is_dodging:
			_end_dodge()
		_start_counter()
	if _intents.has(&"dodge"):
		if request_dodge(direction):
			_intents.erase(&"dodge")
		elif is_attacking and sprite.frame < int(move.get("dash_cancel", -1)):
			_intents[&"dodge"]["expires"] = combat_time + DASH_BUFFER_SECONDS
	if is_dodging:
		_step_dodge(delta)
		_step_perfect_feedback(delta)
		return
	if _intents.has(&"dash") and not is_charging:
		var dash_direction := int(_intents[&"dash"].get("direction", signf(direction.x)))
		if request_dash_stab(dash_direction):
			_intents.erase(&"dash")
		elif is_attacking and sprite.frame < int(move.get("dash_cancel", -1)):
			# The press waits for this swing's dodge window.
			_intents[&"dash"]["expires"] = combat_time + DASH_BUFFER_SECONDS
	# A possible tap keeps its locomotion pose. Only a confirmed hold enters the charge animation.
	if not chase_takeoff and not _primary_press.is_empty() and _mouse_attack_held and state==State.FREE and not is_crouching and (view_mode==ViewMode.TOP_DOWN or (was_grounded and velocity.y>=0.0)):
		if combat_time-float(_primary_press.at)>=PRIMARY_TAP_SECONDS:
			_begin_charge(combat_time-float(_primary_press.at))
	# Released taps are processed while attacking too; holding never auto-chains.
	if not chase_takeoff and _mouse_attack_pending:
		var tap: bool=_intents[&"light"].get("primary_tap",false)
		var followup: StringName=_intents[&"light"].get("followup",&"")
		if tap and is_charging:
			charge_time=0.0
			charge_ended.emit(false)
			_set_recovery(0.0)
		if tap and followup!=&"" and not is_attacking and state!=State.HURT and not is_dodging:
			_set_recovery(0.0)
			_clear_attack_intents()
			_start_move(followup)
		var special := false
		if not is_attacking and _recovery_left <= 0.0 and view_mode == ViewMode.SIDE_VIEW:
			if Input.is_action_pressed("rising_modifier") and was_grounded:
				special = request_rising_slash()
		if not special and _mouse_attack_pending:
			request_attack()
		if _mouse_attack_pending:
			_intents.erase(&"light")
	if not chase_takeoff and _intent_stage(&"heavy") == &"raw":
		if is_charging:
			_cancel_charge()
			_set_recovery(0.0)
		# W + right click on the floor leaps (as W + left click rises); otherwise the combo graph decides.
		var leapt := false
		if not is_attacking and _recovery_left <= 0.0 and view_mode == ViewMode.SIDE_VIEW and was_grounded and Input.is_action_pressed("rising_modifier"):
			leapt = request_leap_cleave()
		if not leapt:
			request_attack(&"heavy")
		if _intent_stage(&"heavy") == &"raw":
			_intents.erase(&"heavy")
	for input in ATTACK_INPUTS:
		if not chase_takeoff and _intent_stage(input) == &"pending" and not is_attacking and _recovery_left <= 0.0:
			begin_attack(input)
	# New moves open a cancel window after their hit frames; some cut their clip short.
	if is_attacking and (not move.get("pierce", false) or dash_executed) and sprite.frame >= int(move.get("cancel", 1 << 30)):
		_chain_queued()
	if is_attacking and sprite.frame >= int(move.get("end", 1 << 30)):
		_on_animation_finished()
	if is_attacking and not _swing_release_emitted and sprite.frame >= maxi(int(move.get("start_frame", 0)), _attack_active_start()-1):
		_swing_release_emitted = true
		swing_released.emit(move_id)
	is_running = _run_requested() and not direction.is_zero_approx() and not is_crouching and not _crouch_exiting and not is_attacking and not is_charging and _recovery_left <= 0.0
	if is_attacking:
		var impulse := _attack_lunge_speed() if was_grounded or view_mode == ViewMode.TOP_DOWN else 0.0
		if view_mode == ViewMode.TOP_DOWN:
			velocity = attack_direction * impulse
		else:
			velocity.x = direction.x * crouch_speed if not was_grounded and move.get("steer", false) else attack_direction.x * (impulse if was_grounded else float(move.get("carry", 0.0)))
	elif state == State.HURT:
		# Recoil only moves the physical body; the directional pose keeps its foot pivot.
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
	if is_jump_chasing:
		_step_jump_chase(delta, direction)
	_step_perfect_feedback(delta)
	# A thrust uses this same collision step as walking. Its swept hit is tested on each travelled segment.
	var dash_step: bool = is_attacking and move.get("pierce", false) and not dash_executed and sprite.frame >= _attack_active_start()
	var dash_from := global_position
	if dash_step:
		_step_dash_velocity(delta)
	move_and_slide()
	if is_jump_chasing:
		_chase_speed = velocity.x
	if dash_step:
		dash_end = global_position
		for index in range(get_slide_collision_count()):
			if get_slide_collision(index).get_normal().dot(attack_direction) < -0.5:
				dash_executed = true
		if _dash_elapsed >= DASH_SECONDS:
			dash_executed = true
		if dash_executed:
			velocity.x = 0.0
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
		_kill_stop_emitted = false
	if is_attacking and move.has("arc"):
		_update_arc()
	_update_sprite_layout()
	if view_mode == ViewMode.SIDE_VIEW and not was_grounded and is_on_floor():
		_landing_left = LANDING_SECONDS
		_jump_age = 0.0
		_jumps_used = 0
		_air_hold_left = 0.0
		_clear_jump_chase()
		fx.dust(global_position, 5)
	if dash_step:
		_apply_dash_hits(dash_from, dash_end)
	if is_attacking and _in_active_frames():
		if not move.get("pierce", false):
			_apply_attack_hits()
		_update_blade_trail()
		if move.get("launcher", false) and airflow_count == 0:
			_spawn_airflow(global_position, true)
	if (move.get("dive", false) or move.get("lands", false)) and is_on_floor():
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
	_primary_press.clear()
	_clear_followup()
	_clear_jump_chase()
	_shift_gesture.clear()


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
			if not _primary_press.is_empty():
				if combat_time-float(_primary_press.at)<PRIMARY_TAP_SECONDS:
					_press(&"light")
					_intents[&"light"]["primary_tap"]=true
					_intents[&"light"]["followup"]=_primary_press.followup
				_primary_press.clear()
		elif not _mouse_attack_held:
			_mouse_attack_held = true
			if _shift_gesture.held:
				_shift_gesture.consume()
			var direction := _movement_input()
			if view_mode == ViewMode.SIDE_VIEW and _shift_gesture.held and not is_instance_valid(_counter_target) and not is_crouching and direction.x != 0.0:
				_shift_gesture.consume()
				_press(&"dash", DASH_BUFFER_SECONDS)
				_intents[&"dash"]["direction"] = signf(direction.x)
				_primary_press.clear()
				_clear_attack_intents()
			elif can_jump_chase():
				_primary_press.clear()
				_press(&"light")
			elif is_instance_valid(_counter_target) or is_dodging or combat_time<_offset_until or is_crouching or (view_mode==ViewMode.SIDE_VIEW and (not is_on_floor() or Input.is_action_pressed("crouch") or (Input.is_action_pressed("rising_modifier") and not is_attacking))):
				_primary_press.clear()
				_press(&"light")
			else:
				_primary_press={"at":combat_time,"followup":_next_move(_string_id,&"light") if is_attacking else _followup_move(&"light")}
	if event is InputEventMouseButton and event.pressed and event.is_action("heavy_mouse"):
		if _shift_gesture.held:
			_shift_gesture.consume()
		_primary_press.clear()
		_press(&"heavy")
	if event is InputEventKey and not event.echo and event.is_action("dash_modifier"):
		if event.pressed:
			_shift_gesture.press(combat_time)
		elif _shift_gesture.release(combat_time):
			var buffer := maxf(DASH_BUFFER_SECONDS,_recovery_left+0.10) if state==State.HURT else DASH_BUFFER_SECONDS
			_press(&"dodge", buffer)
	if view_mode != ViewMode.SIDE_VIEW or not event is InputEventKey or event.echo:
		return
	if event.is_action_pressed("jump") and (can_jump_chase() or move.get("charged_launch", false)):
		_press(&"chase_jump", ATTACK_BUFFER_SECONDS)
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


func _run_requested() -> bool:
	if not Input.is_action_pressed("run"):
		return false
	return CONTROLS.current["run"] != CONTROLS.current["dash_modifier"] or _shift_gesture.running(combat_time)


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
	if _show_perfect_pose():
		return
	if view_mode == ViewMode.SIDE_VIEW:
		if is_crouching or _crouch_exiting:
			var crouch_idle := "crouch_idle_" + facing
			if is_crouching and _crouch_frame >= 7.0 and absf(velocity.x) >= 4.0 and sprite.sprite_frames.has_animation("crouch_walk_" + facing):
				_play_loop("crouch_walk_" + facing, true)
			elif is_crouching and _crouch_frame >= 7.0 and sprite.sprite_frames.has_animation(crouch_idle):
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
	if preserve_phase and (old_name.begins_with("walk_") or old_name.begins_with("run_") or old_name.begins_with("crouch_walk_")):
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
	if is_dodging:
		_buffer_attack(input, &"raw", ATTACK_BUFFER_SECONDS)
		return true
	if not is_attacking:
		if _recovery_left > 0.0 and _followup_move(input) == &"":
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
	if is_attacking or is_dodging or (_recovery_left > 0.0 and _followup_move(input) == &""):
		return false
	var first := &""
	if combat_time < _offset_until:
		first = _next_move(&"dash_stab", input)
	if first == &"":
		first = _followup_move(input)
	if first == &"":
		first = _next_move(&"", input)
	if is_crouching:
		first = &"crouch_stab" if input == &"light" else &""
	if first == &"":
		return false
	attack_direction = _facing_vector()
	_clear_attack_intents()
	_set_recovery(0.0)
	_start_move(first)
	return true


func _followup_move(input: StringName) -> StringName:
	return _next_move(_followup_from, input) if _followup_from != &"" and combat_time < _followup_until else &""


func _clear_followup() -> void:
	_followup_from = &""
	_followup_until = -INF


## First follow-up the combo graph allows from here: side_only moves need the side view, ground moves the floor,
## air_only moves the air.
func _next_move(current: StringName, input: StringName) -> StringName:
	var airborne := view_mode == ViewMode.SIDE_VIEW and not is_on_floor()
	for id in MOVESET.next_moves(current, input):
		var row: Dictionary = MOVESET.MOVES[id]
		if row.get("side_only", false) and view_mode != ViewMode.SIDE_VIEW:
			continue
		if row.get("ground", false) and airborne or row.get("air_only", false) and not airborne:
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
	_perfect_pose_at = -INF
	# Carry the charged cut's next drawn recovery pose into a buffered second hit.
	var charged_source := (move_id == &"heavy_slash" and is_attacking) or (_followup_from == &"attack1" and combat_time < _followup_until)
	var charged_pose := view_mode == ViewMode.SIDE_VIEW and is_on_floor() and String(sprite.animation) == _charge_animation()
	var charge_exit := sprite.frame if charged_source and charged_pose else -1
	_clear_followup()
	move_id = id
	move = MOVESET.MOVES[id]
	if move.get("pierce", false) or move.get("dive", false):
		_clear_jump_chase()
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
	if airborne and air.has("hold") and not is_jump_chasing:
		_air_hold_left = air["hold"]
		velocity.y = air["fall"]
	hit_targets.clear()
	stage_is_critical = false
	_critical_stop_emitted = false
	_normal_stop_emitted = false
	_kill_stop_emitted = false
	_swing_release_emitted = false
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
	var prefix: String = move["air_anim"] if airborne and move.has("air_anim") else (move.get("side_anim",move["anim"]) if view_mode==ViewMode.SIDE_VIEW else move["anim"])
	var link_entry := -1
	if charge_exit >= 11 and move.has("charge_link"):
		prefix = move.charge_link
		link_entry = mini(2, charge_exit-11)
	var animation := prefix + "_" + facing
	# Compatibility keeps the project loadable while new drawn clips are imported.
	if not sprite.sprite_frames.has_animation(animation):
		animation = "stab_" + facing
	sprite.stop()
	sprite.speed_scale = float(move["fps"]) / sprite.sprite_frames.get_animation_speed(animation)
	sprite.play(animation)
	if link_entry >= 0:
		sprite.set_frame_and_progress(link_entry, 0.0)
	elif move.has("start_frame"):
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
	var window := 0.0
	var elapsed := 0.0
	for frame in range(first, last+1):
		var units := sprite.sprite_frames.get_frame_duration(sprite.animation, frame)
		window += units
		if frame < sprite.frame:
			elapsed += units
		elif frame == sprite.frame:
			elapsed += units*sprite.frame_progress
	var phase := elapsed/window
	var duration := window / float(move["fps"])
	# Authored anticipation and the fast swing have different frame durations; lunge follows both continuously.
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
	if row.get("charged_launch",false) and view_mode==ViewMode.SIDE_VIEW and target.has_method("receive_charged_launch"):
		target.call("receive_charged_launch",attack_direction)
		_offer_jump_chase(target)
	elif target.has_method("receive_hit_reaction"):
		target.call("receive_hit_reaction", attack_direction, row.get("launch", false), view_mode == ViewMode.SIDE_VIEW and not is_on_floor() and row.get("juggle", false))
	elif row.get("launch", false) and target.has_method("knock_up"):
		target.call("knock_up", attack_direction)
	if row.has("knockback") and target.has_method("knock_back") and not (row.get("launch",false) and view_mode==ViewMode.SIDE_VIEW):
		target.call("knock_back", attack_direction, float(row["knockback"]))
	if is_jump_chasing and row.get("juggle", false) and _live_chase_target() == target:
		# Preserve the jump arc through the first swing's wind-up; only contact begins shared hang time.
		_air_hold_left = float(row.get("air", {}).get("hold", 0.55))
		velocity.y = AIR_FALL_SPEED
		_clear_jump_chase()
	var enabled: bool = move.get("hit_feedback", true)
	if not enabled and target.has_method("suppress_contact_feedback"):
		target.call("suppress_contact_feedback")
	attack_hit.emit(target)
	hit_resolved.emit(target, damage, stage_is_critical, special_kind)
	if not enabled:
		return true
	var weight := _impact_weight(row)
	var health: Variant = target.get("hp")
	var killed: bool = health != null and int(health) <= 0
	var substance: StringName = target.get_meta("hit_material", &"flesh")
	fx.impact(point, weight, attack_direction, global_position, killed, substance, row.get("charged",false))
	struck.emit(point, &"kill" if killed else weight, attack_direction, killed)
	var first_critical := stage_is_critical and not _critical_stop_emitted
	var first_normal := not stage_is_critical and not _normal_stop_emitted
	if first_critical:
		_critical_stop_emitted = true
		critical_impact_count += 1
		critical_hit.emit(target, damage, attack_direction)
	if first_normal:
		_normal_stop_emitted = true
		normal_contact_stop.emit(attack_direction)
	if killed and not _kill_stop_emitted:
		_kill_stop_emitted = true
		impact.emit(&"kill", attack_direction)
	elif first_critical or first_normal:
		impact.emit(weight, attack_direction)
	return true


func _live_chase_target() -> Node2D:
	var target: Node2D = _chase_target.get_ref() if _chase_target != null else null
	if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.is_inside_tree():
		return null
	var health: Variant = target.get("hp")
	return target if health != null and int(health) > 0 else null


func _offer_jump_chase(target: Node2D) -> void:
	if int(target.get("hp")) <= 0 or is_jump_chasing:
		return
	var previous := _live_chase_target()
	# A wide charged cut can launch several bodies. Follow the nearest survivor, never a corpse.
	if combat_time < _chase_window_until and previous != null and global_position.distance_squared_to(previous.global_position) <= global_position.distance_squared_to(target.global_position):
		return
	_chase_target = weakref(target)
	_chase_window_until = combat_time + CHASE_WINDOW_SECONDS


func can_jump_chase() -> bool:
	if view_mode != ViewMode.SIDE_VIEW or combat_time >= _chase_window_until or is_jump_chasing or state == State.HURT or is_dodging or is_charging or is_crouching:
		return false
	if is_attacking and not move.get("charged_launch", false):
		return false
	var target := _live_chase_target()
	return target != null and absf(target.global_position.x-global_position.x) <= 170.0 and target.global_position.y <= global_position.y+5.0


func request_jump_chase() -> bool:
	if not can_jump_chase():
		return false
	var target := _live_chase_target()
	var target_velocity := Vector2(attack_direction.x*105.0, -300.0)
	if target is CharacterBody2D:
		target_velocity = target.velocity
	elif target.has_method("chase_velocity"):
		target_velocity = target.call("chase_velocity")
	_chase_direction = 1.0 if target.global_position.x >= global_position.x else -1.0
	facing = "right" if _chase_direction > 0.0 else "left"
	attack_direction = Vector2(_chase_direction, 0)
	_chase_window_until = 0.0
	_chase_left = CHASE_ASSIST_SECONDS
	_chase_speed = clampf(velocity.x, -CHASE_MAX_SPEED, CHASE_MAX_SPEED)
	move_id = &""
	move = {}
	_string_id = &"attack1"
	_followup_from = &"attack1"
	_followup_until = combat_time + CHASE_ASSIST_SECONDS
	for input in ATTACK_INPUTS:
		if _intent_stage(input) == &"queued":
			_intents[input]["stage"] = &"raw"
	stage_is_critical = false
	_set_recovery(0.0)
	_primary_press.clear()
	_jumps_used = 1
	_jump_age = 0.0
	_landing_left = 0.0
	_air_hold_left = 0.0
	_crouch_exiting = false
	is_running = false
	# Meet the target's ballistic arc in ~0.24s; this assigns velocity only, with normal world collision.
	velocity.y = clampf((target.global_position.y-global_position.y)/0.24+target_velocity.y, -360.0, -225.0)
	fx.dust(global_position, 5)
	_set_manual_frame("jump_"+facing, 0)
	combo_changed.emit(0)
	jump_chase_started.emit(target)
	return true


func _step_jump_chase(delta: float, direction: Vector2) -> void:
	var target := _live_chase_target()
	_chase_left = maxf(0.0, _chase_left-delta)
	if target == null or _chase_left <= 0.0 or state == State.HURT or is_dodging or move.get("dive", false) or move.get("pierce", false) or direction.x*_chase_direction < 0.0:
		_clear_jump_chase()
		return
	var target_speed := 0.0
	if target is CharacterBody2D:
		target_speed = target.velocity.x
	elif target.has_method("chase_velocity"):
		target_speed = target.call("chase_velocity").x
	var gap := target.global_position.x-global_position.x-_chase_direction*CHASE_GAP
	var desired := clampf(target_speed+gap*8.0, -CHASE_MAX_SPEED, CHASE_MAX_SPEED)
	_chase_speed = move_toward(_chase_speed, desired, CHASE_ACCELERATION*delta)
	velocity.x = _chase_speed
	if is_attacking and move.get("juggle", false):
		var target_fall := 0.0
		if target is CharacterBody2D:
			target_fall = target.velocity.y
		elif target.has_method("chase_velocity"):
			target_fall = target.call("chase_velocity").y
		# A late pursuit meets a falling target. Ease into its vertical speed through the wind-up.
		var follow_fall := target_fall + clampf((target.global_position.y-global_position.y)*6.0, -140.0, 140.0)
		velocity.y = move_toward(velocity.y, clampf(follow_fall, -360.0, 260.0), 1800.0*delta)


func _clear_jump_chase() -> void:
	_chase_left = 0.0
	_chase_window_until = 0.0
	_chase_target = null


## W + right click on the floor: leap_cleave, a forward leap that chops down and lands with a shockwave.
func request_leap_cleave() -> bool:
	if view_mode != ViewMode.SIDE_VIEW or is_attacking or _recovery_left > 0.0 or is_crouching or not is_on_floor() or state == State.HURT:
		return false
	_crouch_exiting = false
	_start_special("leap_cleave")
	return true


func request_rising_slash() -> bool:
	if view_mode != ViewMode.SIDE_VIEW or is_attacking or is_dodging or _recovery_left > 0.0 or is_crouching or not is_on_floor():
		return false
	# The move's jump field lifts the hero.
	_start_special("rising_slash")
	return true


func request_dive_slash() -> bool:
	if view_mode != ViewMode.SIDE_VIEW or is_on_floor() or move.get("dive", false) or state == State.HURT or is_dodging:
		return false
	_air_hold_left = 0.0
	velocity.y = DIVE_SPEED
	_start_special("dive_slash")
	fx.queue_redraw()
	return true


func request_dash_stab(direction: int) -> bool:
	var cancelling := is_attacking and sprite.frame >= int(move.get("dash_cancel", 1 << 30))
	if view_mode != ViewMode.SIDE_VIEW or (is_attacking and not cancelling) or _recovery_left > 0.0 or is_crouching or is_dodging:
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
	_dash_elapsed = 0.0
	_dash_ghost_left = 0.0
	dash_start = global_position
	dash_end = global_position
	_start_special("dash_stab")
	return true


## A short released modifier is an evade, never a weapon hit. Motion uses normal wall/floor collision.
func request_dodge(direction: Vector2 = Vector2.ZERO) -> bool:
	var cancelling := is_attacking and sprite.frame >= int(move.get("dash_cancel", 1 << 30))
	if is_dodging or state == State.HURT or _recovery_left > 0.0 or (is_attacking and not cancelling):
		return false
	if is_charging:
		_cancel_charge()
	_perfect_pose_at = -INF
	_clear_jump_chase()
	_clear_followup()
	_offset_from = _string_id if cancelling else (_last_string_id if combat_time - _string_end_time <= DODGE_OFFSET_SECONDS else &"")
	_dodge_direction = direction.normalized() if not direction.is_zero_approx() else _facing_vector()
	if view_mode == ViewMode.SIDE_VIEW:
		_dodge_direction = Vector2(signf(_dodge_direction.x), 0)
		if _dodge_direction.x == 0.0:
			_dodge_direction.x = 1.0 if facing == "right" else -1.0
	_update_facing(_dodge_direction)
	_clear_attack_intents()
	move_id = &""
	move = {}
	state = State.DODGE
	is_running = false
	_dodge_duration = ROLL_SECONDS if view_mode == ViewMode.SIDE_VIEW else DODGE_SECONDS
	_dodge_left = _dodge_duration
	_dodge_ghost_left = 0.0
	_dodge_low = view_mode == ViewMode.SIDE_VIEW and is_on_floor()
	if _dodge_low:
		_set_body_size(CROUCH_SIZE)
	_dash_started_at = combat_time
	_dash_phasing = true
	collision_mask = 1
	dash_start = global_position
	special_started.emit("dodge", _dodge_direction)
	return true


func _step_dodge(delta: float) -> void:
	var step_seconds := minf(delta, _dodge_left)
	var speed := DODGE_DISTANCE / _dodge_duration * step_seconds / delta
	if view_mode == ViewMode.TOP_DOWN:
		velocity = _dodge_direction * speed
		_set_manual_frame("run_" + facing, int((_dodge_duration - _dodge_left) * 40.0) % 16)
	else:
		velocity.x = _dodge_direction.x * speed
		var phase := (_dodge_duration - _dodge_left) / _dodge_duration
		_set_manual_frame("roll_" + facing, mini(15, int(phase * 16.0)))
	_show_perfect_pose()
	move_and_slide()
	sprite.position = global_position.round() - global_position
	_dodge_ghost_left -= delta
	if _dodge_ghost_left <= 0.0 and view_mode == ViewMode.TOP_DOWN:
		fx.ghost(sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame), global_position + sprite.offset, 0.10)
		_dodge_ghost_left = 0.06
	_dodge_left = maxf(0.0, _dodge_left - delta)
	dash_end = global_position
	fx.queue_redraw()
	if _dodge_left > 0.0:
		return
	_end_dodge()


func _end_dodge() -> void:
	state = State.FREE
	_offset_until = combat_time + DODGE_OFFSET_SECONDS
	if view_mode == ViewMode.TOP_DOWN:
		velocity = Vector2.ZERO
	else:
		velocity.x = 0.0
		is_crouching = is_on_floor() and (Input.is_action_pressed("crouch") or not can_stand())
		_crouch_frame = 7.0 if is_crouching else 10.0
		_crouch_exiting = false
		_set_body_size(CROUCH_SIZE if is_crouching else STAND_SIZE)


func _start_special(kind: String) -> void:
	attack_direction = Vector2.DOWN if kind == "dive_slash" else _facing_vector()
	_clear_attack_intents()
	airflow_count = 0
	_start_move(StringName(kind))
	special_started.emit(kind, attack_direction)


## Smoothstep's difference is an exact travelled distance, independent of the physics tick rate.
## The paused tree freezes both this clock and the attack animation during contact hit-stop.
func _step_dash_velocity(delta: float) -> void:
	if _dash_elapsed == 0.0:
		dash_start = global_position
		_dash_phasing = true
		collision_mask = 1
		_spawn_airflow(dash_start, false)
	var before := smoothstep(0.0, 1.0, _dash_elapsed / DASH_SECONDS)
	_dash_elapsed = minf(DASH_SECONDS, _dash_elapsed + delta)
	var after := smoothstep(0.0, 1.0, _dash_elapsed / DASH_SECONDS)
	velocity.x = attack_direction.x * DASH_DISTANCE * (after - before) / delta
	_dash_ghost_left -= delta
	if _dash_ghost_left <= 0.0:
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		fx.ghost(texture, global_position + sprite.offset, 0.06)
		_dash_ghost_left = 0.06


func _apply_dash_hits(from: Vector2, to: Vector2) -> void:
	var start := from + Vector2(0, -17)
	var end := to + Vector2(0, -17)
	# Sweep the whole extended blade, including the space between physics ticks and vertical air motion.
	var left := -4.0 if attack_direction.x > 0.0 else -DASH_BLADE_REACH
	var right := DASH_BLADE_REACH if attack_direction.x > 0.0 else 4.0
	var corners := PackedVector2Array([Vector2(left,-10), Vector2(right,-10), Vector2(right,10), Vector2(left,10)])
	var points := corners.duplicate()
	for corner in corners:
		points.append(corner+end-start)
	var shape := ConvexPolygonShape2D.new()
	shape.points = Geometry2D.convex_hull(points)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, start)
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
	if not _dash_phasing or is_attacking or is_dodging:
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
	if (move.get("dive", false) or move.get("lands", false)) and not is_on_floor():
		_set_manual_frame(String(move["anim"]) + "_" + facing, int(move.get("hold_frame", 11)))
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
	if move.has("followup_seconds"):
		_followup_from = _string_id
		_followup_until = combat_time + recovery + float(move.followup_seconds)
	var coil: bool = not _primary_press.is_empty() and _mouse_attack_held and combat_time-float(_primary_press.at)>=PRIMARY_TAP_SECONDS and move.get("chain", false) and (view_mode == ViewMode.TOP_DOWN or is_on_floor())
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


func _charge_animation() -> String:
	return (String(MOVESET.MOVES[&"heavy_slash"].side_anim) if view_mode==ViewMode.SIDE_VIEW else "attack3")+"_"+facing


func _charge_pose_limit() -> int:
	return SIDE_CHARGE_POSE_FRAME if view_mode==ViewMode.SIDE_VIEW else CHARGE_POSE_FRAME


func _begin_charge(held_seconds := 0.0) -> void:
	_clear_followup()
	state = State.CHARGE
	_charge_started_at = combat_time-held_seconds
	charge_time = held_seconds
	_charge_announced=false
	is_running = false
	_set_manual_frame(_charge_animation(), 0)


func _update_charge(delta: float, grounded: bool) -> void:
	if view_mode == ViewMode.SIDE_VIEW and not grounded:
		_cancel_charge()
		return
	if _mouse_attack_held:
		var was_full := charge_time >= CHARGE_FULL_SECONDS
		charge_time = combat_time-_charge_started_at
		if not _charge_announced and charge_time>=PRIMARY_TAP_SECONDS:
			_charge_announced=true
			fx.dust(global_position,4)
			charge_started.emit()
		var coil := clampf((charge_time-PRIMARY_TAP_SECONDS) / (CHARGE_FULL_SECONDS * CHARGE_COIL_PORTION-PRIMARY_TAP_SECONDS), 0.0, 1.0)
		var pose := mini(_charge_pose_limit(), int(coil * (_charge_pose_limit() + 1)))
		if sprite.frame != pose:
			_set_manual_frame(_charge_animation(), pose)
		if coil < 1.0 and _charge_announced:
			# Settle back into the stance while coiling.
			var back := -_facing_vector() * CHARGE_BACKSTEP / (CHARGE_FULL_SECONDS * CHARGE_COIL_PORTION-PRIMARY_TAP_SECONDS)
			if view_mode == ViewMode.TOP_DOWN:
				velocity = back
			else:
				velocity.x = back.x
		var tip := _blade_tip_for_frame(sprite.frame)
		var tick := int(charge_time * 20.0) != int((charge_time - delta) * 20.0)
		if tick and _charge_announced:
			# Light rises off the body while the charge builds.
			fx.mote(global_position, was_full)
		if not was_full and charge_time >= CHARGE_FULL_SECONDS:
			fx.sparks(tip)
			fx.dust(global_position, 6)
			charge_ready.emit()
		elif was_full and int(charge_time * 10.0) != int((charge_time - delta) * 10.0):
			# Full: a blinking white star on the tip says "release now".
			fx.star(tip)
		elif not was_full and tick and _charge_announced:
			# Coiling: light gathers onto the blade from a ring that tightens as the charge fills.
			fx.gather(tip, lerpf(14.0, 4.0, charge_time / CHARGE_FULL_SECONDS), charge_time * 11.0)
		return
	if charge_time >= CHARGE_FULL_SECONDS:
		_release_heavy_slash()
	else:
		_cancel_charge()


func _cancel_charge() -> void:
	_primary_press.clear()
	charge_time = 0.0
	_set_recovery(2.0 / float(MOVESET.MOVES[&"attack3"]["fps"]))
	charge_ended.emit(false)


func _release_heavy_slash() -> void:
	_primary_press.clear()
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
	elif hit_invulnerability_left > 0.0 or (_is_melee_attack(attack) and melee_protection_left>0.0):
		result = AttackResult.EVADE
	elif not attack.get("contact", true) or is_dodging or (state == State.ATTACK and move.get("dodge", false)):
		result = AttackResult.EVADE
	if result == AttackResult.HIT:
		_take_hit(attack)
	elif result == AttackResult.PERFECT:
		_perfect_pose_at = combat_time
		_perfect_ghost_left = 0.0
		_show_perfect_pose()
		fx.speed_lines(global_position, _dodge_direction, false)
		fx.star(global_position + Vector2(0, -19))
		perfect_dodge_started.emit()
	attack_received.emit(result, attack)
	return result


func _is_melee_attack(attack: Dictionary) -> bool:
	return attack.get("attack_kind","")=="melee" or str(attack.get("weapon","")) in ["melee","rifle_butt","baton"]


func can_receive_melee_windup(windup: float) -> bool:
	return state!=State.HURT and melee_protection_left<=windup-0.05


## Seconds on the combat clock since the last dash started (INF before the first).
func seconds_since_dash() -> float:
	return combat_time - _dash_started_at


## GameSession opens the counter on a perfect dodge (the enemy that missed) and closes it when the slow motion ends.
func open_counter(enemy: Node2D) -> void:
	_counter_target = enemy
	_counter_until = combat_time + COUNTER_WINDOW_SECONDS


func close_counter() -> void:
	_counter_target = null
	_counter_until = -INF


# Perfect-dodge counter: blinks to the far side of the enemy (the near side if a wall is there) and cuts it with
# counter_slash, a sure critical with the heavy freeze.
func _start_counter() -> void:
	var enemy := _counter_target
	close_counter()
	_clear_attack_intents()
	if is_charging:
		_cancel_charge()
	var from := global_position
	var to := from
	var side := 0.0
	# A missing/dead/distant source still grants one empowered slash, without an unsafe teleport.
	if _counter_target_alive(enemy) and from.distance_to(enemy.global_position) <= COUNTER_MAX_DISTANCE:
		side = 1.0 if from.x <= enemy.global_position.x else -1.0
		var candidate := Vector2(enemy.global_position.x + side * COUNTER_BEHIND, from.y)
		if _counter_path_clear(candidate):
			to = candidate
		else:
			side = -side
			candidate = Vector2(enemy.global_position.x + side * COUNTER_BEHIND, from.y)
			if _counter_path_clear(candidate):
				to = candidate
			else:
				side = 0.0
	fx.ghost(sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame), from + sprite.offset, 0.2)
	for lane in range(3):
		var y := -10.0 - lane * 6.0
		fx.add({"position": to + Vector2(0, y), "velocity": Vector2.ZERO, "tail": (to - from) * (1.0 - lane * 0.25),
			"life": 0.12, "color": PLAYER_FX.WHITE if lane == 1 else PLAYER_FX.BLUE})
	global_position = to
	if side != 0.0:
		facing = "left" if side > 0.0 else "right"
	attack_direction = _facing_vector()
	_start_move(&"counter_slash")
	counter_started.emit(enemy)


func _counter_target_alive(enemy: Node2D) -> bool:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return false
	return enemy.get("dead") != true and enemy.get("hp") != 0


func _counter_path_clear(to: Vector2) -> bool:
	if not _clear_at(to):
		return false
	# Sweep the real body past world geometry; an enemy can be crossed, a wall cannot.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body_shape.shape
	query.transform = body_shape.global_transform
	query.motion = to - global_position
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var safe := get_world_2d().direct_space_state.cast_motion(query)
	return safe[0] >= 0.999


func _show_perfect_pose() -> bool:
	if perfect_pose_left <= 0.0 or is_attacking or is_charging or state == State.HURT:
		return false
	var clip := "perfect_dodge_" + facing
	if not sprite.sprite_frames.has_animation(clip):
		return false
	var progress := clampf((combat_time - _perfect_pose_at) / PERFECT_POSE_SECONDS, 0.0, 0.999)
	_set_manual_frame(clip, int(progress * 6.0))
	sprite.modulate = Color(0.75, 1.0, 1.15)
	return true


func _step_perfect_feedback(delta: float) -> void:
	if perfect_pose_left <= 0.0 or is_attacking or state == State.HURT:
		return
	_perfect_ghost_left -= delta
	if _perfect_ghost_left <= 0.0:
		fx.ghost(sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame), global_position + sprite.offset, 0.16)
		_perfect_ghost_left = 0.04
		fx.queue_redraw()


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
	close_counter()
	_perfect_pose_at = -INF
	_clear_followup()
	_clear_jump_chase()
	_primary_press.clear()
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
	if push.is_zero_approx():
		push = -_facing_vector()
	hurt_from_back = push.normalized().dot(_facing_vector()) > 0.0
	_hurt_push = push.normalized()
	_hurt_started_at = combat_time
	_hit_invulnerable_until = combat_time + HIT_INVULNERABILITY_SECONDS
	if _is_melee_attack(attack):
		_melee_protected_until=combat_time+MELEE_PROTECTION_SECONDS
	var speed := 2.0 * float(attack.get("knockback", HURT_KNOCKBACK)) / HURT_SLIDE_SECONDS
	_hurt_brake = speed / HURT_SLIDE_SECONDS
	if view_mode == ViewMode.SIDE_VIEW:
		velocity.x = signf(push.x) * speed
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity = push.normalized() * speed
	# A neutral blade-low silhouette bends at the waist: front hit recoils, rear hit folds forward.
	_set_manual_frame("idle_" + facing, 0)
	_update_hit_feedback()
	sprite.modulate = HURT_TINT
	fx.clear_trails()
	fx.sparks(global_position + Vector2(0, -15))
	combo_changed.emit(0)


func _update_hit_feedback() -> void:
	var age := combat_time - _hurt_started_at
	hurt_pose_shift = Vector2.ZERO
	if state == State.HURT and age < HURT_SECONDS:
		# Fast impact, brief follow-through, then a smooth return; no automatic turn toward the attacker.
		var peak := 0.095 if hurt_from_back else 0.065
		var settle := 0.145 if hurt_from_back else 0.12
		var amount := lerpf(0.25, 1.0, smoothstep(0.0, peak, age)) if age < peak else 1.0 - smoothstep(settle, HURT_SECONDS, age)
		var reach := 13.0 if hurt_from_back else 11.0
		hurt_pose_shift = _hurt_push * reach * amount
		if view_mode == ViewMode.SIDE_VIEW:
			hurt_pose_shift.y = (4.0 if hurt_from_back else -2.0) * amount
	var material := sprite.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("hurt_shift", hurt_pose_shift)
		material.set_shader_parameter("hurt_foot_y", -sprite.offset.y)
	# The protection outlasts the stun, so movement/attacks resume while a pale pulse remains visible.
	if state != State.HURT:
		sprite.modulate = Color(0.65, 0.9, 1.0, 0.7) if hit_invulnerability_left > 0.0 and int(age * 20.0) % 2 == 0 else Color.WHITE
		if hit_invulnerability_left<=0.0 and melee_protection_left>0.0 and int(age*20.0)%2==0:
			sprite.modulate=Color(1.0,0.9,0.65,0.85)
	var implant := sprite.get_node_or_null("ImplantOverlay")
	if implant != null:
		implant.set("hurt_shift", hurt_pose_shift)


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
	if wave.get("again", true):
		hit_targets.clear()
	_normal_stop_emitted = false
	_critical_stop_emitted = false
	_kill_stop_emitted = false
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
	if wave.get("ring", false):
		# A flat ring running out along the floor and columns of dust thrown up on both sides.
		for index in range(16):
			var out := Vector2(cos(TAU * index / 16.0), sin(TAU * index / 16.0) * 0.3)
			fx.add({"position": global_position + out * 4.0 + Vector2(0, -2), "velocity": out * 150.0, "tail": out * 4.0,
				"life": 0.16, "color": PLAYER_FX.WHITE if index % 2 == 0 else PLAYER_FX.BLUE})
		for x in [-20.0, -11.0, 11.0, 20.0]:
			for step in range(3):
				fx.add({"position": global_position + Vector2(x, -1.0), "velocity": Vector2(0, -45.0 - step * 25.0),
					"life": 0.2 + step * 0.04, "color": PLAYER_FX.DUST})


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
	if move.get("charged",false):return
	if sprite.frame == _last_blade_frame:
		return
	var tip := _blade_tip_for_frame(sprite.frame)
	var previous := _previous_blade_tip
	if _last_blade_frame < _attack_active_start():
		previous = _blade_tip_for_frame(_attack_active_start() - 1) if _blade_paths.has(String(sprite.animation)) else tip - attack_direction * 4.0
	var ribbon_life := BLADE_TRAIL_SECONDS
	if move_id in [&"attack1", &"attack2", &"attack3", &"heavy_slash"]:
		var shoulder := attack_origin()
		tip = shoulder+(tip-shoulder)*1.2
		previous = shoulder+(previous-shoulder)*1.2
		ribbon_life = 0.075
	var direction := tip - previous
	var edge := Vector2i(0, 1) if absf(direction.x) >= absf(direction.y) else Vector2i(1, 0)
	fx.trail(PLAYER_FX.pixel_line(previous, tip), edge, ribbon_life)
	_previous_blade_tip = _blade_tip_for_frame(sprite.frame)
	_last_blade_frame = sprite.frame
