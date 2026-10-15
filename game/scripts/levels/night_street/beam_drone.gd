extends Node2D
## Patrol drone above the street. Its cone is the surveillance light: anything inside it is being watched.
## Micro-light particles drift down inside the cone. When marked it stops sweeping and tracks target_x.

const EMISSIVE = preload("res://shaders/emissive_add.gdshader")
const WATCH := Color(0.31, 0.94, 1.0)
const MARKED := Color(1.0, 0.24, 0.43)
const APEX_DROP := 5.0
const FLOOR_HALF_WIDTH := 24.0
const PARTICLE_COUNT := 110

var floor_y := 156.0
var patrol_min := 180.0
var patrol_max := 820.0
var patrol_speed := 22.0
var marked := false
var target_x := -1.0
var cone := PackedVector2Array()
var _direction := 1.0
var _pause_left := 0.0
var _clock := 0.0
var _particles: Array[Vector4] = []  # t along the cone, u across it, fall speed, twinkle phase
var _hull: Node2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 2040
	var glow := ShaderMaterial.new()
	glow.shader = EMISSIVE
	glow.set_shader_parameter("gain", 1.5)
	material = glow
	for _index in range(PARTICLE_COUNT):
		_particles.append(Vector4(_rng.randf(), _rng.randf_range(-1.0, 1.0), _rng.randf_range(0.04, 0.12), _rng.randf() * TAU))
	_hull = Node2D.new()
	_hull.name = "Hull"
	add_child(_hull)
	_hull.draw.connect(_draw_hull)
	_update_cone()


func _process(delta: float) -> void:
	_clock += delta
	_move(delta)
	for index in range(_particles.size()):
		var particle := _particles[index]
		particle.x += particle.z * delta
		particle.y = clampf(particle.y + _rng.randf_range(-0.6, 0.6) * delta, -1.0, 1.0)
		if particle.x > 1.0:
			particle = Vector4(0.04, _rng.randf_range(-1.0, 1.0), particle.z, particle.w)
		_particles[index] = particle
	_update_cone()
	queue_redraw()
	_hull.queue_redraw()


func _move(delta: float) -> void:
	if marked and target_x >= 0.0:
		position.x = move_toward(position.x, clampf(target_x, patrol_min, patrol_max), 40.0 * delta)
		return
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	position.x += _direction * patrol_speed * delta
	if position.x > patrol_max or position.x < patrol_min:
		position.x = clampf(position.x, patrol_min, patrol_max)
		_direction = -_direction
		_pause_left = 1.4


func _update_cone() -> void:
	var apex := global_position + Vector2(0.0, APEX_DROP)
	var sweep := 0.0 if marked else 0.14 * sin(_clock * TAU / 5.5)
	var hit_x := apex.x + tan(sweep) * (floor_y - apex.y)
	cone = PackedVector2Array([apex, Vector2(hit_x - FLOOR_HALF_WIDTH, floor_y), Vector2(hit_x + FLOOR_HALF_WIDTH, floor_y)])


func contains(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, cone)


func ground_spot() -> Vector2:
	return (cone[1] + cone[2]) * 0.5


func light_color() -> Color:
	return MARKED if marked else WATCH


func _draw() -> void:
	var colour := light_color()
	var apex := to_local(cone[0])
	var left := to_local(cone[1])
	var right := to_local(cone[2])
	var centre := (left + right) * 0.5
	draw_colored_polygon(PackedVector2Array([apex, left, right]), Color(colour, 0.075))
	draw_colored_polygon(PackedVector2Array([apex, centre.lerp(left, 0.45), centre.lerp(right, 0.45)]), Color(colour, 0.075))
	for row in range(3):
		var half := FLOOR_HALF_WIDTH * (1.0 - row * 0.3)
		draw_rect(Rect2(Vector2(centre.x - half, centre.y - 1.0 + row).floor(), Vector2(half * 2.0, 1.0)), Color(colour, 0.22 - row * 0.06))
	for particle in _particles:
		var along := apex.lerp(centre, particle.x)
		var spread := FLOOR_HALF_WIDTH * particle.x * 0.92
		var point := (along + Vector2(particle.y * spread, 0.0)).floor()
		var twinkle := 0.3 + 0.7 * maxf(0.0, sin(_clock * 3.0 + particle.w))
		draw_rect(Rect2(point, Vector2.ONE), Color(colour.lightened(0.55), twinkle))
	# lens and status light belong to the self-lit pass
	draw_rect(Rect2(Vector2(-1.0, 2.0), Vector2(2.0, 1.0)), Color(colour, 1.0))
	if fmod(_clock, 1.0) < 0.15:
		draw_rect(Rect2(Vector2(4.0, -3.0), Vector2.ONE), Color(1.0, 0.2, 0.25))


func _draw_hull() -> void:
	_hull.draw_rect(Rect2(-6.0, -2.0, 12.0, 4.0), Color("2b2448"))
	_hull.draw_rect(Rect2(-6.0, -2.0, 12.0, 1.0), Color("4a3f78"))
	_hull.draw_rect(Rect2(-3.0, 2.0, 6.0, 1.0), Color("1b1630"))
	var blade := 3.0 if int(_clock * 30.0) % 2 == 0 else 4.0
	for side in [-1.0, 1.0]:
		_hull.draw_rect(Rect2(side * 6.0 - (2.0 if side < 0.0 else 0.0), -3.0, 2.0, 1.0), Color("3e3266"))
		_hull.draw_rect(Rect2(side * 7.0 - blade * 0.5, -4.0, blade, 1.0), Color("6a5f98"))
