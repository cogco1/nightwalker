extends AnimatableBody2D
## The standalone battlefield's open industrial cage. Motion is real platform physics;
## the rider keeps normal movement and jump control throughout the journey.

var bottom_y := 168.0
var top_y := -104.0
var width := 64.0
var speed := 40.0
var call_range := 28.0
var target_y := 168.0
var cage: Sprite2D
var _sprite_offset := Vector2.ZERO

var moving: bool:
	get: return not is_equal_approx(position.y, target_y)


func configure(data: Dictionary) -> bool:
	var texture := load(String(data.get("sprite", ""))) as Texture2D
	width = float(data.get("width", 64.0))
	bottom_y = float(data.get("bottom_y", 168.0))
	top_y = float(data.get("top_y", -104.0))
	speed = float(data.get("speed", 40.0))
	call_range = float(data.get("call_range", 28.0))
	var offset: Array = data.get("sprite_offset", [0, -60])
	if texture == null or width <= 12.0 or top_y >= bottom_y or speed <= 0.0 or offset.size() != 2:
		push_error("Battlefield elevator needs a sprite, positive width/speed and ordered stops.")
		return false
	name = String(data.get("id", "IndustrialElevator"))
	set_meta("surface_id", String(data.get("id", "industrial_elevator")))
	position = Vector2(float(data.get("x", 0.0)), bottom_y)
	target_y = bottom_y
	process_physics_priority = -100
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	var deck_height := maxf(1.0, float(data.get("deck_height", 4.0)))
	shape.size = Vector2(width, deck_height)
	collision.shape = shape
	collision.position = Vector2(width / 2.0, deck_height / 2.0)
	collision.one_way_collision = true
	add_child(collision)
	cage = Sprite2D.new()
	cage.name = "Cage"
	cage.texture = texture
	cage.centered = false
	cage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite_offset = Vector2(float(offset[0]), float(offset[1]))
	cage.position = _sprite_offset
	add_child(cage)
	return true


func nearby_stop(rider: Node2D) -> float:
	if rider.global_position.x < global_position.x - call_range \
			or rider.global_position.x > global_position.x + width + call_range:
		return INF
	for stop in [bottom_y, top_y]:
		if absf(rider.global_position.y - stop) <= call_range:
			return stop
	return INF


func activate(rider: Node2D) -> bool:
	if moving:
		return false
	var stop := nearby_stop(rider)
	if not is_finite(stop):
		return false
	# A distant cage is called to this landing; a docked cage travels to the other.
	target_y = stop if not is_equal_approx(position.y, stop) else (top_y if stop == bottom_y else bottom_y)
	return true


func hint(rider: Node2D) -> String:
	if moving or not is_finite(nearby_stop(rider)):
		return ""
	return "E  工业电梯 · 出发" if is_equal_approx(position.y, nearby_stop(rider)) else "E  呼叫工业电梯"


func _physics_process(delta: float) -> void:
	position.y = move_toward(position.y, target_y, speed * delta)
	# Continuous collision movement carries the hero smoothly; the bitmap remains
	# aligned to the same integer world grid as the existing player artwork.
	cage.position = (position + _sprite_offset).round() - position


func drawn_rect() -> Rect2:
	return Rect2(cage.global_position, cage.texture.get_size())
