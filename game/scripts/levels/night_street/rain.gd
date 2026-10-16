extends Node2D
## Screen-space rain with kerb splashes. scroll_x is the camera's left edge in world pixels; drops shift
## against it so the rain stays in the world while the camera pans.

const DROP_COUNT := 150

var floor_y := 156.0
var scroll_x := 0.0
var _last_scroll := 0.0
var _drops: Array[Vector4] = []  # x, y, fall speed, length
var _splashes: Array[Vector3] = []  # x, y, life
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_last_scroll = scroll_x
	for _index in range(DROP_COUNT):
		_drops.append(_new_drop(_rng.randf_range(-20.0, 180.0)))


func _new_drop(y: float) -> Vector4:
	return Vector4(_rng.randf_range(-10.0, 340.0), y, _rng.randf_range(210.0, 290.0), float(_rng.randi_range(3, 6)))


func _process(delta: float) -> void:
	var shift := scroll_x - _last_scroll
	_last_scroll = scroll_x
	for index in range(_drops.size()):
		var drop := _drops[index]
		drop.x += -shift - drop.z * 0.18 * delta
		drop.y += drop.z * delta
		drop.x = wrapf(drop.x, -12.0, 340.0)
		var land_y := floor_y + fmod(index * 7.0, 22.0)
		if drop.y > land_y:
			if _rng.randf() < 0.6:
				_splashes.append(Vector3(drop.x, land_y, 0.12))
			drop = _new_drop(_rng.randf_range(-30.0, -4.0))
		_drops[index] = drop
	for index in range(_splashes.size()):
		var splash := _splashes[index]
		_splashes[index] = Vector3(splash.x - shift, splash.y, splash.z - delta)
	_splashes = _splashes.filter(func(splash: Vector3) -> bool: return splash.z > 0.0)
	queue_redraw()


func _draw() -> void:
	for drop in _drops:
		var colour := Color(0.62, 0.69, 1.0, 0.16 + 0.04 * drop.w)
		var half := floorf(drop.w * 0.5)
		draw_rect(Rect2(floorf(drop.x), floorf(drop.y), 1.0, half), colour)
		draw_rect(Rect2(floorf(drop.x) - 1.0, floorf(drop.y) + half, 1.0, drop.w - half), colour)
	for splash in _splashes:
		var colour := Color(0.75, 0.82, 1.0, splash.z / 0.12 * 0.5)
		draw_rect(Rect2(floorf(splash.x) - 1.0, splash.y - 1.0, 1.0, 1.0), colour)
		draw_rect(Rect2(floorf(splash.x) + 1.0, splash.y - 1.0, 1.0, 1.0), colour)
		draw_rect(Rect2(floorf(splash.x), splash.y, 1.0, 1.0), colour)
