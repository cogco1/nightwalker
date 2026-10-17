extends CharacterBody2D

signal destroyed

@export var side_view := false
@export var max_hp := 3

var hp := 3
var flash_left := 0.0
var body_shape: CollisionShape2D
var spawn_position := Vector2.ZERO
var knock_count := 0
var last_knock_velocity := Vector2.ZERO
var weak_knock_count := 0
var knock_back_count := 0
var slash_flash_left := 0.0
var last_hit_direction := Vector2.RIGHT
var _death_reaction_left := 0.0
var _air_hold_left := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	spawn_position = global_position
	hp = max_hp
	body_shape = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 26) if side_view else Vector2(12, 8)
	body_shape.position = Vector2(0, -13) if side_view else Vector2(0, -4)
	body_shape.shape = shape
	add_child(body_shape)
	queue_redraw()


func damage_point() -> Vector2:
	return global_position + Vector2(0, -17 if side_view else -4)


func take_damage(amount: int) -> bool:
	if hp <= 0 or amount <= 0:
		return false
	hp = maxi(0, hp - amount)
	flash_left = 0.10
	if hp == 0:
		_death_reaction_left = 0.18
		body_shape.set_deferred("disabled", true)
		destroyed.emit()
	queue_redraw()
	return true


func suppress_contact_feedback() -> void:
	flash_left = 0.0
	slash_flash_left = 0.0
	queue_redraw()


func knock_up(direction: Vector2) -> void:
	if not side_view:
		return
	_air_hold_left = 0.0
	velocity = Vector2(signf(direction.x) * 55.0, -300.0)
	last_knock_velocity = velocity
	knock_count += 1


func receive_charged_launch(direction: Vector2) -> void:
	receive_hit_reaction(direction,true,false)
	if side_view:
		velocity=Vector2(signf(direction.x)*105.0,-300.0)
		last_knock_velocity=velocity


func receive_hit_reaction(direction: Vector2, strong: bool = false, air_combo: bool = false) -> void:
	last_hit_direction = direction
	slash_flash_left = 0.08
	if strong and side_view:
		knock_up(direction)
	elif air_combo and side_view and not is_on_floor():
		_air_hold_left = 0.55
		velocity = Vector2(0, 6.0)
		weak_knock_count += 1
		last_knock_velocity = velocity
	else:
		_air_hold_left = 0.0
		knock_small(direction)
	queue_redraw()


## Pushes a grounded target about `distance` native px away (ground friction 280 px/s^2 brakes it).
func knock_back(direction: Vector2, distance: float) -> void:
	if not side_view or not is_on_floor():
		return
	velocity = Vector2(signf(direction.x) * sqrt(2.0 * 280.0 * distance), 0.0)
	last_knock_velocity = velocity
	knock_back_count += 1


func knock_small(direction: Vector2) -> void:
	weak_knock_count += 1
	if side_view:
		velocity = Vector2(signf(direction.x) * 25.0, 360.0 if direction == Vector2.DOWN else -50.0)
		last_knock_velocity = velocity
	else:
		move_and_collide(direction.normalized() * 2.5, false, 0.001)
		last_knock_velocity = direction.normalized() * 2.5


func slash_flash_pixels() -> Array[Vector2i]:
	var pixels: Array[Vector2i] = []
	if slash_flash_left <= 0.0:
		return pixels
	for step in range(15):
		var x := -7 + step if last_hit_direction.x >= 0.0 else 7 - step
		pixels.append(Vector2i(x, -23 + step))
	return pixels


func respawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	hp = max_hp
	flash_left = 0.0
	slash_flash_left = 0.0
	_death_reaction_left = 0.0
	_air_hold_left = 0.0
	body_shape.set_deferred("disabled", false)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_death_reaction_left = maxf(0.0, _death_reaction_left - delta)
	_air_hold_left = maxf(0.0, _air_hold_left - delta)
	if not side_view:
		return
	if hp <= 0:
		_update_dead_motion(delta)
		return
	if not is_on_floor() or velocity.y < 0.0:
		velocity.y = 6.0 if _air_hold_left > 0.0 else velocity.y + 620.0 * delta
	else:
		velocity.x = move_toward(velocity.x, 0.0, 280.0 * delta)
		velocity.y = 0.0
	move_and_slide()
	queue_redraw()


func _update_dead_motion(delta: float) -> void:
	if velocity.is_zero_approx():
		return
	velocity.y += 620.0 * delta
	# The defeated collider stays disabled. Sweep a temporary shape against world walls.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(11.8, 25.8)
	for motion in [Vector2(velocity.x * delta, 0), Vector2(0, velocity.y * delta)]:
		if motion.is_zero_approx():
			continue
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0.0, global_position + Vector2(0, -13))
		query.motion = motion
		query.collision_mask = 1
		query.exclude = [get_rid()]
		var safe: float = get_world_2d().direct_space_state.cast_motion(query)[0]
		global_position += motion * safe
		if safe < 0.999:
			if motion.x != 0.0:
				velocity.x = 0.0
			else:
				velocity.y = 0.0
				velocity.x = move_toward(velocity.x, 0.0, 280.0 * delta)
	queue_redraw()


func _process(delta: float) -> void:
	if slash_flash_left > 0.0:
		slash_flash_left = maxf(0.0, slash_flash_left - delta)
		queue_redraw()
	if flash_left > 0.0:
		flash_left = maxf(0.0, flash_left - delta)
		queue_redraw()


func _draw() -> void:
	draw_set_transform(global_position.round() - global_position)
	if hp <= 0 and _death_reaction_left <= 0.0:
		draw_rect(Rect2(-7, -3, 14, 3), Color("51454b"))
		draw_rect(Rect2(-2, -7, 3, 4), Color("9e7967"))
		return
	var wood := Color("ba987b") if flash_left == 0.0 else Color("f0e8d8")
	draw_rect(Rect2(-2, -11, 4, 11), Color("745b59"))
	draw_rect(Rect2(-6, -24, 12, 13), wood)
	draw_rect(Rect2(-4, -31, 8, 6), wood)
	draw_rect(Rect2(-9, -20, 18, 3), wood)
	draw_rect(Rect2(-2, -21, 4, 7), Color("b75b57"))
	draw_rect(Rect2(-4, -19, 8, 2), Color("b75b57"))
	draw_rect(Rect2(-6, -1, 12, 1), Color("745b59"))
	for index in range(max_hp):
		var color := Color("d7bd72") if index < hp else Color("44464c")
		draw_rect(Rect2(-int(max_hp * 1.5) + index * 3, -37, 2, 2), color)
	for pixel in slash_flash_pixels():
		draw_rect(Rect2(Vector2(pixel + Vector2i(1, 0)), Vector2.ONE), Color("8ebce8"))
		draw_rect(Rect2(Vector2(pixel), Vector2.ONE), Color("f2f8ff") if slash_flash_left > 0.035 else Color("8ebce8"))
