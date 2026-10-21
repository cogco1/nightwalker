extends Node
## Telegraphed straight-line lunge for an enemy body (the parent, a Node2D in the world). Once the hero is in reach
## the parent blinks red for telegraph_seconds, aiming at the hero until lock_lead seconds before the end, then
## rushes at the locked point in lunge_seconds. Shared minima keep both the tell and recovery at 0.55 s.
## The hit window is the last active_seconds of the rush: the first
## overlap with the hero's hurtbox calls hero.receive_attack(attack); a window that closes without contact still
## reports once (contact = false), so a dash that took the hero out of the line of fire can count as a perfect
## dodge. Then the body hangs for recover_seconds, drifts back to its post and waits cooldown_seconds.
##
## Time runs on the world clock: delta times GameSession.world_time_scale, and the paused tree of a hit-stop
## stops it.
##
## Floor-bound bodies (the chapter's guards, scripts/enemies/guard.gd) set horizontal (the lunge keeps to the
## floor), standoff (it stops short of the hero), returns = false (no drift back: the post is where it stopped),
## mirror_hitbox (the box is drawn facing right) and damage; armed = false holds the next attack back.

signal telegraph_started
signal lunge_started(aim: Vector2)
signal attack_resolved(result: int)
const RHYTHM = preload("res://scripts/enemies/melee_rhythm.gd")

enum Phase { IDLE, TELEGRAPH, LUNGE, RECOVER, RETURN, COOLDOWN }

@export var reach := Vector2(96, 40)
@export var telegraph_seconds := RHYTHM.WINDUP_SECONDS
@export var lock_lead := 0.2
@export var lunge_seconds := 0.18
@export var lunge_overshoot := 10.0
@export var active_seconds := RHYTHM.ACTIVE_SECONDS
@export var recover_seconds := RHYTHM.RECOVERY_SECONDS
@export var return_speed := 70.0
@export var cooldown_seconds := 1.2
## Attack box around the parent's origin, native px.
@export var hitbox := Rect2(-8, -8, 16, 12)
## Where the parent's origin aims, from the hero's feet: (0, -13) for a body centred on its origin, (0, 0) for a body
## drawn above an origin on the floor.
@export var aim_offset := Vector2(0, -13)
@export var knockback := 20.0
@export var warning_color := Color(1.0, 0.25, 0.25)
## The lunge keeps the body's height instead of aiming at the hero's.
@export var horizontal := false
## The lunge stops this far short of the aim point (before the overshoot).
@export var standoff := 0.0
## After the recovery the body drifts back to its post; false leaves it where the lunge ended.
@export var returns := true
## hitbox is drawn facing right and is mirrored for a lunge to the left.
@export var mirror_hitbox := false
## Hit points a HIT takes from the hero (attack.damage); the sandbox hero has none.
@export var damage := 0
## While false a hero in reach does not start a telegraph (the host's own state: staggered, airborne, held).
var armed := true

var phase := Phase.IDLE
var phase_time := 0.0
var aim := Vector2.ZERO
var post := Vector2.ZERO
var resolved := false
var last_result := -1
var target: Node2D
var _body: Node2D
var _start := Vector2.ZERO
var _base_modulate := Color.WHITE


func _ready() -> void:
	telegraph_seconds=maxf(telegraph_seconds,RHYTHM.WINDUP_SECONDS)
	recover_seconds=maxf(recover_seconds,RHYTHM.RECOVERY_SECONDS)
	cooldown_seconds=maxf(cooldown_seconds,RHYTHM.MIN_COOLDOWN_SECONDS)
	_body = get_parent()
	post = _body.global_position
	_base_modulate = _body.modulate


## The hero to attack (anything with hurtbox() and receive_attack(attack)). The body flies through the hero rather
## than shoving it; attacks and hit queries still find both.
func bind_target(hero: Node2D) -> void:
	target = hero
	if _body is PhysicsBody2D and hero is PhysicsBody2D:
		(_body as PhysicsBody2D).add_collision_exception_with(hero)


func world_scale() -> float:
	var session := get_tree().get_first_node_in_group(&"game_session")
	return float(session.world_time_scale) if session != null else 1.0


## Seconds since the hit window opened (negative before it).
func window_age() -> float:
	return phase_time - (lunge_seconds - active_seconds) if phase == Phase.LUNGE else -INF


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or not is_instance_valid(_body):
		return
	# A destroyed body (hit points used up) stands down until it has them again.
	if _body.get("hp") != null and int(_body.get("hp")) <= 0:
		if phase != Phase.COOLDOWN:
			reset()
		phase_time = 0.0
		return
	phase_time += delta * world_scale()
	if phase==Phase.TELEGRAPH and not armed:
		stagger(RHYTHM.MIN_COOLDOWN_SECONDS)
	match phase:
		Phase.IDLE:
			# The post follows the body while it idles, so a scene can still move or bob the enemy.
			post = _body.global_position
			if armed and _in_reach() and RHYTHM.can_begin(target,telegraph_seconds):
				_enter(Phase.TELEGRAPH)
				aim=target.global_position+aim_offset
				if horizontal:
					aim.y=_body.global_position.y
				telegraph_started.emit()
		Phase.TELEGRAPH:
			if phase_time <= telegraph_seconds - lock_lead:
				aim = target.global_position + aim_offset
				if horizontal:
					aim.y = _body.global_position.y
			_body.modulate = warning_color if int(phase_time / 0.06) % 2 == 0 else _base_modulate
			if phase_time >= telegraph_seconds:
				_body.modulate = _base_modulate
				_start = _body.global_position
				resolved = false
				_enter(Phase.LUNGE)
				lunge_started.emit(aim)
		Phase.LUNGE:
			var heading := (aim - _start).normalized()
			var goal := aim + heading * (lunge_overshoot - standoff)
			if (goal - _start).dot(heading) < 0.0:
				goal = _start
			# Ease the physical step into and out of the swing; collision still resolves each tick.
			var next := _start.lerp(goal, smoothstep(0.0, lunge_seconds, phase_time))
			if _body is PhysicsBody2D:
				(_body as PhysicsBody2D).move_and_collide(next-_body.global_position)
			else:
				_body.global_position=next
			if not resolved and window_age() >= 0.0:
				if hit_rect().intersects(target.call("hurtbox")):
					_resolve(true)
				elif phase_time >= lunge_seconds:
					_resolve(false)
			if phase_time >= lunge_seconds:
				_enter(Phase.RECOVER)
		Phase.RECOVER:
			if phase_time >= maxf(recover_seconds,RHYTHM.RECOVERY_SECONDS):
				if returns:
					_enter(Phase.RETURN)
				else:
					post = _body.global_position
					_enter(Phase.COOLDOWN)
		Phase.RETURN:
			_body.global_position = _body.global_position.move_toward(post, return_speed * delta * world_scale())
			if _body.global_position.distance_to(post) < 0.5:
				_enter(Phase.COOLDOWN)
		Phase.COOLDOWN:
			if phase_time >= maxf(cooldown_seconds,RHYTHM.MIN_COOLDOWN_SECONDS):
				_enter(Phase.IDLE)


func hit_rect() -> Rect2:
	var box := hitbox
	if mirror_hitbox and lunge_heading() < 0.0:
		box.position.x = -box.end.x
	return Rect2(_body.global_position + box.position, box.size)


## -1 when the current (or last) lunge goes left, else 1.
func lunge_heading() -> float:
	return -1.0 if aim.x < _start.x else 1.0


## The body was hit while winding up: the telegraph is called off and the next one waits `seconds`. A lunge in
## progress is committed and carries on.
func stagger(seconds: float) -> void:
	if phase == Phase.TELEGRAPH:
		_body.modulate = _base_modulate
		_enter(Phase.COOLDOWN)
		phase_time = maxf(0.0, cooldown_seconds - seconds)


## Calls off any attack in progress and puts the body back on its post (destroyed, reset or countered).
func reset() -> void:
	_body.modulate = _base_modulate
	_body.global_position = post
	_enter(Phase.COOLDOWN)


func _enter(next: Phase) -> void:
	phase = next
	phase_time = 0.0


func _in_reach() -> bool:
	var offset := target.global_position - _body.global_position
	return absf(offset.x) <= reach.x and absf(offset.y) <= reach.y


func _resolve(contact: bool) -> void:
	resolved = true
	var origin := _body.global_position+Vector2(0,-13) if horizontal else _body.global_position
	var ray := PhysicsRayQueryParameters2D.create(origin,target.hurtbox().get_center(),1)
	if not _body.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
		return
	var direction := Vector2(signf(aim.x - _start.x), 0.0)
	if direction.x == 0.0:
		direction.x = 1.0
	last_result = int(target.call("receive_attack", {"source": _body, "direction": direction, "contact": contact,
		"window_age": clampf(window_age(), 0.0, active_seconds), "knockback": knockback, "damage": damage,"attack_kind":"melee"}))
	attack_resolved.emit(last_result)
