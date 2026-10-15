extends Node
## Telegraphed straight-line lunge for an enemy body (the parent, a Node2D in the world). Once the hero is in reach
## the parent blinks red for telegraph_seconds, aiming at the hero until lock_lead seconds before the end, then
## rushes at the locked point in lunge_seconds. The hit window is the last active_seconds of the rush: the first
## overlap with the hero's hurtbox calls hero.receive_attack(attack); a window that closes without contact still
## reports once (contact = false), so a dash that took the hero out of the line of fire can count as a perfect
## dodge. Then the body hangs for recover_seconds, drifts back to its post and waits cooldown_seconds.
##
## Time runs on the world clock: delta times GameSession.world_time_scale, and the paused tree of a hit-stop
## stops it.

signal telegraph_started
signal lunge_started(aim: Vector2)
signal attack_resolved(result: int)

enum Phase { IDLE, TELEGRAPH, LUNGE, RECOVER, RETURN, COOLDOWN }

@export var reach := Vector2(96, 40)
@export var telegraph_seconds := 0.5
@export var lock_lead := 0.2
@export var lunge_seconds := 0.18
@export var lunge_overshoot := 10.0
@export var active_seconds := 0.12
@export var recover_seconds := 0.25
@export var return_speed := 70.0
@export var cooldown_seconds := 1.2
## Attack box around the parent's origin, native px.
@export var hitbox := Rect2(-8, -8, 16, 12)
@export var knockback := 20.0
@export var warning_color := Color(1.0, 0.25, 0.25)

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
	phase_time += delta * world_scale()
	match phase:
		Phase.IDLE:
			# The post follows the body while it idles, so a scene can still move or bob the enemy.
			post = _body.global_position
			if _in_reach():
				_enter(Phase.TELEGRAPH)
				telegraph_started.emit()
		Phase.TELEGRAPH:
			if phase_time <= telegraph_seconds - lock_lead:
				aim = target.global_position + Vector2(0, -13)
			_body.modulate = warning_color if int(phase_time / 0.06) % 2 == 0 else _base_modulate
			if phase_time >= telegraph_seconds:
				_body.modulate = _base_modulate
				_start = _body.global_position
				resolved = false
				_enter(Phase.LUNGE)
				lunge_started.emit(aim)
		Phase.LUNGE:
			var goal := aim + (aim - _start).normalized() * lunge_overshoot
			_body.global_position = _start.lerp(goal, minf(1.0, phase_time / lunge_seconds))
			if not resolved and window_age() >= 0.0:
				if hit_rect().intersects(target.call("hurtbox")):
					_resolve(true)
				elif phase_time >= lunge_seconds:
					_resolve(false)
			if phase_time >= lunge_seconds:
				_enter(Phase.RECOVER)
		Phase.RECOVER:
			if phase_time >= recover_seconds:
				_enter(Phase.RETURN)
		Phase.RETURN:
			_body.global_position = _body.global_position.move_toward(post, return_speed * delta * world_scale())
			if _body.global_position.distance_to(post) < 0.5:
				_enter(Phase.COOLDOWN)
		Phase.COOLDOWN:
			if phase_time >= cooldown_seconds:
				_enter(Phase.IDLE)


func hit_rect() -> Rect2:
	return Rect2(_body.global_position + hitbox.position, hitbox.size)


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
	var direction := Vector2(signf(aim.x - _start.x), 0.0)
	if direction.x == 0.0:
		direction.x = 1.0
	last_result = int(target.call("receive_attack", {"source": _body, "direction": direction, "contact": contact,
		"window_age": clampf(window_age(), 0.0, active_seconds), "knockback": knockback}))
	attack_resolved.emit(last_result)
