extends StaticBody2D
## Hover drone for the night-street prototype. Same hit API as tests/fixtures/training_target.gd (take_damage,
## damage_point, receive_hit_reaction), so player combos, criticals and hit-stop work unchanged. It fights back with
## scripts/enemies/enemy_attacker.gd: a red blink, then a lunge at the hero (night_street.gd binds the hero).

const EMISSIVE = preload("res://shaders/emissive_add.gdshader")
const ATTACKER = preload("res://scripts/enemies/enemy_attacker.gd")
const RESPAWN_SECONDS := 2.5

@export var max_hp := 3
var hp := 3
var _clock := 0.0
var _flash := 0.0
var _offset := Vector2.ZERO
var _velocity := Vector2.ZERO
var _respawn_left := 0.0
var _sparks: Array[Dictionary] = []
var _shape: CollisionShape2D
var _lights: Node2D
var attacker: Node


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	hp = max_hp
	_clock = position.x * 0.37
	_shape = CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12, 26)
	_shape.shape = rectangle
	_shape.position = Vector2(0, -13)
	add_child(_shape)
	var glow := ShaderMaterial.new()
	glow.shader = EMISSIVE
	glow.set_shader_parameter("gain", 1.8)
	_lights = Node2D.new()
	_lights.name = "SelfLit"
	_lights.material = glow
	add_child(_lights)
	_lights.draw.connect(_draw_lights)
	# The origin is on the floor and the body is drawn 18 px above it: aim the origin at the hero's feet and hit with
	# the box around the drawn body.
	attacker = ATTACKER.new()
	attacker.name = "Attacker"
	attacker.aim_offset = Vector2.ZERO
	attacker.hitbox = Rect2(-7, -23, 14, 10)
	add_child(attacker)


func damage_point() -> Vector2:
	return global_position + Vector2(0, -17)


func take_damage(amount: int) -> bool:
	if hp <= 0 or amount <= 0:
		return false
	hp = maxi(0, hp - amount)
	_flash = 0.09
	if hp == 0:
		_respawn_left = RESPAWN_SECONDS
		_shape.set_deferred("disabled", true)
		for _index in range(12):
			_sparks.append({"p": global_position + _body_origin(), "v": Vector2.from_angle(randf() * TAU) * randf_range(30.0, 95.0), "life": 0.45})
	return true


func receive_hit_reaction(direction: Vector2, launch: bool, _air: bool) -> void:
	_velocity = Vector2(signf(direction.x) * 90.0, -150.0 if launch else -20.0)


func _process(delta: float) -> void:
	_clock += delta
	_flash = maxf(0.0, _flash - delta)
	_velocity += (-_offset * 60.0 - _velocity * 8.0) * delta
	_offset += _velocity * delta
	for spark in _sparks:
		var velocity: Vector2 = spark["v"]
		velocity.y += 140.0 * delta
		spark["v"] = velocity
		spark["p"] += velocity * delta
		spark["life"] -= delta
	_sparks = _sparks.filter(func(spark: Dictionary) -> bool: return spark["life"] > 0.0)
	if _respawn_left > 0.0:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			hp = max_hp
			_offset = Vector2.ZERO
			_velocity = Vector2.ZERO
			_shape.set_deferred("disabled", false)
	queue_redraw()
	_lights.queue_redraw()


func _body_origin() -> Vector2:
	return (Vector2(0.0, -18.0 + roundf(sin(_clock * 3.0) * 1.5)) + _offset).round()


func _draw() -> void:
	if hp <= 0:
		return
	var o := _body_origin()
	var hull := Color("f4f2ff") if _flash > 0.0 else Color("6a5ca8")
	draw_rect(Rect2(o + Vector2(-5, -3), Vector2(10, 6)), hull)
	draw_rect(Rect2(o + Vector2(-5, -3), Vector2(10, 1)), Color("a596e0") if _flash <= 0.0 else hull)
	draw_rect(Rect2(o + Vector2(-5, 2), Vector2(10, 1)), Color("3a3166"))
	draw_rect(Rect2(o + Vector2(-8, -4), Vector2(3, 1)), Color("8a7cc8"))
	draw_rect(Rect2(o + Vector2(5, -4), Vector2(3, 1)), Color("8a7cc8"))
	draw_rect(Rect2(o + Vector2(-2, 3), Vector2(4, 2)), Color("2c2550"))


func _draw_lights() -> void:
	for spark in _sparks:
		_lights.draw_rect(Rect2((spark["p"] - global_position).floor(), Vector2.ONE), Color(1.0, 0.75, 0.4, spark["life"] / 0.45))
	if hp <= 0:
		return
	var o := _body_origin()
	var eye := Color(0.31, 0.94, 1.0) if hp == max_hp else Color(1.0, 0.3, 0.5)
	_lights.draw_rect(Rect2(o + Vector2(-1, 0), Vector2(2, 1)), eye)
	_lights.draw_rect(Rect2(o + Vector2(-4, 5), Vector2(8, 1)), Color(eye, 0.35))
	_lights.draw_rect(Rect2(o + Vector2(-6, -4), Vector2(1, 1)), Color(eye, 0.7))
	_lights.draw_rect(Rect2(o + Vector2(5, -4), Vector2(1, 1)), Color(eye, 0.7))
	for pip in range(hp):
		_lights.draw_rect(Rect2(o + Vector2(-3 + pip * 3, -7), Vector2(2, 1)), Color(eye, 0.8))
