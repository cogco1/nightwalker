extends Node2D

const REFERENCE_SIZE := Vector2(160, 90)
const CONE_LENGTH := 40.0

var layout: Dictionary = {}
var background_texture: Texture2D
var native_size := Vector2i(320, 180)
var clock := 0.0
var animation_ticks := 0
var tv_frame := 0
var pc_frame := 0
var last_interaction := ""
var interaction_counts: Dictionary = {}
var reactions: Dictionary = {}
var cone_sources: Dictionary = {}
var fridge_frame_index := -1
var _fridge_frames: Array[Texture2D] = []
var _fridge_origin := Vector2(6, 86)
var _cone_pixels: Array[Dictionary] = []
var _redraw_tick := -1
var _world_per_native := Vector2.ONE
var _reference_scale := Vector2(2, 2)


func configure(data: Dictionary) -> void:
	layout = data


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 1
	background_texture = load("res://assets/home_601/home_601_native.png") as Texture2D
	if layout.is_empty():
		layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/home_601/layout.json"))
	native_size = Vector2i(background_texture.get_size())
	var world_size: Array = layout.get("world_size", [320, 180])
	_world_per_native = Vector2(float(world_size[0]) / native_size.x, float(world_size[1]) / native_size.y)
	_reference_scale = Vector2(native_size) / REFERENCE_SIZE
	_load_fridge_frames()
	# Origins follow the monitor pixels; both shortened beams point straight down.
	_cache_cone(Vector2(_reference_pixel(Vector2(30, 26))), Vector2.DOWN, CONE_LENGTH, "computer")
	_cache_cone(Vector2(_reference_pixel(Vector2(93, 29))), Vector2.DOWN, CONE_LENGTH, "television")
	queue_redraw()


func play_interaction(id: String) -> void:
	last_interaction = id
	interaction_counts[id] = int(interaction_counts.get(id, 0)) + 1
	reactions[id] = 0.0
	if id == "fridge":
		fridge_frame_index = 0
	queue_redraw()


func _process(delta: float) -> void:
	clock += delta
	for id in reactions.keys():
		reactions[id] = float(reactions[id]) + delta
		var duration := 1.2 if id == "fridge" else (0.8 if id in ["bed", "dumbbells"] else 0.55)
		if float(reactions[id]) >= duration:
			reactions.erase(id)
			if id == "fridge":
				fridge_frame_index = -1
	if reactions.has("fridge") and not _fridge_frames.is_empty():
		fridge_frame_index = mini(int(float(reactions["fridge"]) / 1.2 * _fridge_frames.size()), _fridge_frames.size() - 1)
	var tick := int(clock * 12.0)
	if tick != _redraw_tick:
		_redraw_tick = tick
		animation_ticks += 1
		tv_frame = int(clock * 8.0) % 16
		pc_frame = int(clock * 2.0) % 4
		queue_redraw()


func _load_fridge_frames() -> void:
	var file := "res://assets/home_601/fridge_animation.json"
	if not FileAccess.file_exists(file):
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	var origin: Array = data.get("world_top_left", [6, 86])
	_fridge_origin = _snap_world(Vector2(origin[0], origin[1]))
	for path in data.get("frames", []):
		var texture := load(String(path)) as Texture2D
		if texture != null:
			_fridge_frames.append(texture)


func _cache_cone(origin: Vector2, direction: Vector2, length: float, source_id: String) -> void:
	cone_sources[source_id] = {"origin": origin, "direction": direction, "length": length}
	var right := Vector2(-direction.y, direction.x)
	var bounds: Array = layout.get("bounds", [0, 0, 320, 180])
	var first := Vector2(bounds[0], bounds[1]) / _world_per_native
	var last := Vector2(bounds[0] + bounds[2], bounds[1] + bounds[3]) / _world_per_native
	for y in range(maxi(0, floori(first.y)), mini(native_size.y, ceili(last.y))):
		for x in range(maxi(0, floori(first.x)), mini(native_size.x, ceili(last.x))):
			var point := Vector2(x + 0.5, y + 0.5)
			var difference := point - origin
			var distance := difference.dot(direction)
			if distance <= 0.0 or distance >= length:
				continue
			var width := 2.0 + distance * 0.23
			var spread := absf(difference.dot(right)) / width
			if spread > 1.0 or _blocked(point, source_id):
				continue
			var blocked := false
			var steps := int(ceil(difference.length()))
			# Keep seven world pixels clear beneath the screen housing.
			for step in range(7, steps):
				if _blocked(origin.lerp(point, float(step) / steps), source_id):
					blocked = true
					break
			if blocked:
				continue
			var tier := 2 if spread < 0.40 else (1 if spread < 0.75 else 0)
			if distance / length > 0.82:
				tier = maxi(0, tier - 1)
			_cone_pixels.append({"pixel": Vector2i(x, y), "tier": tier, "source": source_id})


func _blocked(native_point: Vector2, source_id: String) -> bool:
	var point := native_point * _world_per_native
	for collider in layout.get("colliders", []):
		if String(collider["id"]) == source_id:
			continue
		var values: Array = collider["rect"]
		if Rect2(values[0], values[1], values[2], values[3]).has_point(point):
			return true
	return false


func _draw() -> void:
	if background_texture == null:
		return
	# Every cell maps to exactly one320x180 output pixel at the original character scale.
	for entry in _cone_pixels:
		var opacity: float = [0.10, 0.17, 0.26][int(entry["tier"])]
		if int(clock * 3.0) % 9 == 0:
			opacity *= 0.88
		var tone := Color(0.23, 0.63, 0.75, opacity) if entry["source"] == "computer" else Color(0.27, 0.68, 0.79, opacity)
		_native_pixel(entry["pixel"], tone)
	_draw_tv()
	_draw_computer()
	if reactions.has("frame"):
		var elapsed: float = reactions["frame"]
		var shift := 1 if int(elapsed * 12.0) % 2 == 0 else -1
		_copy_native(_reference_rect(Rect2i(75, 11, 11, 11)), Vector2i(shift, 0))
	if reactions.has("bed"):
		var shift := -1 if float(reactions["bed"]) < 0.4 else 0
		_copy_native(_reference_rect(Rect2i(123, 34, 17, 20)), Vector2i(0, shift))
	if reactions.has("dumbbells"):
		var shift := -1 if int(float(reactions["dumbbells"]) * 10.0) % 2 == 0 else 0
		_copy_native(_reference_rect(Rect2i(124, 61, 15, 10)), Vector2i(0, shift))
	if reactions.has("door"):
		_native_pixel(_reference_pixel(Vector2(69, 24)), Color("8abcc9"))
	if fridge_frame_index >= 0 and fridge_frame_index < _fridge_frames.size():
		var frame := _fridge_frames[fridge_frame_index]
		draw_texture_rect(frame, Rect2(_fridge_origin, frame.get_size() * _world_per_native), false)


func _draw_tv() -> void:
	var screen := _reference_rect(Rect2i(89, 24, 8, 5))
	_copy_native(screen, Vector2i.ZERO)
	var line := tv_frame % screen.size.y
	for x in range(screen.size.x):
		if (x + tv_frame) % 3 != 0:
			_native_pixel(screen.position + Vector2i(x, line), Color(0.08, 0.26, 0.32, 0.68))
	# A two-pixel news strip crawls while isolated static flecks change at 8fps.
	var strip_x := tv_frame % (screen.size.x - 1)
	_native_pixel(Vector2i(screen.position.x + strip_x, screen.end.y - 1), Color("83bdca"))
	_native_pixel(Vector2i(screen.position.x + strip_x + 1, screen.end.y - 1), Color("356071"))
	_native_pixel(screen.position + Vector2i((tv_frame * 3 + 1) % screen.size.x, (tv_frame + 1) % (screen.size.y - 1)), Color("c0dbe0"))
	if reactions.has("television"):
		for x in range(screen.size.x):
			_native_pixel(screen.position + Vector2i(x, screen.size.y >> 1), Color(0.75, 0.90, 0.95, 0.45))


func _draw_computer() -> void:
	var screen := _reference_rect(Rect2i(26, 22, 7, 4))
	_copy_native(screen, Vector2i.ZERO)
	if pc_frame % 2 == 0:
		_native_pixel(_reference_pixel(Vector2(27, 24)), Color("b7dce0"))
	if pc_frame in [0, 1]:
		_native_pixel(_reference_pixel(Vector2(33, 26)), Color("6cb1be"))
	if reactions.has("computer"):
		var row := int(float(reactions["computer"]) * 8.0) % (screen.size.y - 1)
		for x in range(maxi(1, screen.size.x - 3)):
			_native_pixel(screen.position + Vector2i(1 + x, row), Color("8bbcc7"))


func _reference_pixel(pixel: Vector2) -> Vector2i:
	var scaled := pixel * _reference_scale
	return Vector2i(roundi(scaled.x), roundi(scaled.y))


func _reference_rect(region: Rect2i) -> Rect2i:
	var first := _reference_pixel(Vector2(region.position))
	var last := _reference_pixel(Vector2(region.end))
	return Rect2i(first, last - first)


func _snap_world(point: Vector2) -> Vector2:
	return (point / _world_per_native).round() * _world_per_native


func _copy_native(region: Rect2i, shift: Vector2i) -> void:
	draw_texture_rect_region(background_texture, Rect2(Vector2(region.position + shift) * _world_per_native, Vector2(region.size) * _world_per_native), Rect2(region))


func _native_pixel(pixel: Vector2i, color: Color) -> void:
	draw_rect(Rect2(Vector2(pixel) * _world_per_native, _world_per_native), color, true)
