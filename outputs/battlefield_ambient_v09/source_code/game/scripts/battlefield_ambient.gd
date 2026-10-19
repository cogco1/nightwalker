extends Node
## A small, reusable ambient pool. All coordinates stay on the original native grid.

const SETTINGS_PATH := "res://assets/battlefield_ambient/ambient.json"

class PixelMark extends Node2D:
	var size := Vector2.ONE
	var tint := Color.WHITE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), tint)

var host: Node2D
var settings: Dictionary = {}
var effects: Array[Dictionary] = []
var elapsed := 0.0
var updates := 0
var update_hz := 16.0
var steam_frame_size := Vector2i.ZERO
var steam_grid := Vector2i.ZERO
var _update_step := 1.0 / 16.0
var _accumulator := 0.0
var _steam_used: Array[Rect2] = []


func configure(scene: Node2D) -> bool:
	host = scene
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if not parsed is Dictionary:
		push_error("Battlefield ambient settings must be a dictionary.")
		return false
	settings = parsed
	update_hz = clampf(float(settings.get("update_hz", 16.0)), 1.0, 30.0)
	_update_step = 1.0 / update_hz
	var frame_size: Array = settings.get("steam_frame_size", [64, 64])
	var frames: Array = settings.get("steam_frames", [3, 2])
	steam_frame_size = Vector2i(int(frame_size[0]), int(frame_size[1]))
	steam_grid = Vector2i(int(frames[0]), int(frames[1]))
	if steam_frame_size.x <= 0 or steam_frame_size.y <= 0 or steam_grid.x <= 0 or steam_grid.y <= 0:
		push_error("Battlefield steam frame size and grid must be positive native pixels.")
		return false
	var steam_texture := load(String(settings.get("steam_texture", ""))) as Texture2D
	if steam_texture == null or Vector2i(steam_texture.get_size()) != steam_frame_size * steam_grid:
		push_error("Battlefield steam sheet must match the configured native frame size and grid.")
		return false
	var steam_image := steam_texture.get_image()
	for frame in range(steam_grid.x * steam_grid.y):
		var origin := Vector2i((frame % steam_grid.x) * steam_frame_size.x, int(frame / steam_grid.x) * steam_frame_size.y)
		_steam_used.append(Rect2(steam_image.get_region(Rect2i(origin, steam_frame_size)).get_used_rect()))
	for kind in ["lights", "steam", "stars"]:
		for data: Dictionary in settings.get(kind, []):
			var layer := String(data.get("layer", "far"))
			var parent := _layer(layer)
			if parent == null:
				push_error("Invalid ambient depth layer: " + layer)
				return false
			var node: Node2D
			var bounds := Rect2()
			if kind == "lights":
				var raw: Array = data.rect
				bounds = Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
				var lamp := Sprite2D.new()
				lamp.texture = parent.texture
				lamp.centered = false
				lamp.region_enabled = true
				lamp.region_filter_clip_enabled = true
				lamp.region_rect = bounds
				lamp.position = bounds.position
				node = lamp
			elif kind == "steam":
				var plume := Sprite2D.new()
				plume.texture = steam_texture
				plume.centered = false
				plume.hframes = steam_grid.x
				plume.vframes = steam_grid.y
				node = plume
			else:
				node = PixelMark.new()
			var anchor: Array = data.get("position", [bounds.position.x, bounds.position.y])
			if kind == "steam":
				var emitter: Array = settings.get("steam_anchor", [24, 59])
				node.position = Vector2(float(anchor[0]) - float(emitter[0]), float(anchor[1]) - float(emitter[1])).round()
			node.name = String(data.id)
			node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			parent.add_child(node)
			effects.append({"id": String(data.id), "kind": kind, "layer": layer, "node": node,
				"data": data, "anchor": Vector2(float(anchor[0]), float(anchor[1])), "rect": bounds})
	var dust: Dictionary = settings.get("dust", {})
	var dust_lengths: Array = dust.get("lengths", [1, 2, 3])
	if dust_lengths.is_empty():
		dust_lengths = [1]
	for index in range(clampi(int(dust.get("count", 10)), 0, 16)):
		var grain := PixelMark.new()
		grain.name = "WindSand%02d" % index
		grain.size = Vector2(clampi(int(dust_lengths[index % dust_lengths.size()]), 1, 3), 1)
		grain.tint = Color(0.52, 0.46, 0.34, float(dust.get("opacity", 0.16)))
		grain.z_index = 0
		host.add_child(grain)
		effects.append({"id": grain.name, "kind": "dust", "layer": "world", "node": grain,
			"data": dust, "index": index, "rect": Rect2()})
	return true


func _layer(layer: String) -> Sprite2D:
	if layer == "far":
		return host.far_background
	if layer == "mid":
		return host.mid_background
	if layer == "near":
		return host.background
	return null


func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < _update_step or host.camera == null:
		return
	# Retain the fractional remainder so 60fps rendering still averages 16 updates/second.
	var advance := floorf(_accumulator / _update_step) * _update_step
	_accumulator -= advance
	update_at(elapsed + advance)


func update_at(time: float) -> void:
	# Also used by evidence capture to select reproducible moments without touching physics.
	elapsed = time
	updates += 1
	var viewport := Rect2(host.camera.position - Vector2(160, 90), Vector2(320, 180))
	for item: Dictionary in effects:
		var node: Node2D = item.node
		var data: Dictionary = item.data
		var kind := String(item.kind)
		if kind == "dust":
			var index := int(item.index)
			var x := viewport.position.x + fposmod(index * 31.7 + time * float(data.get("speed", 5.0)) - viewport.position.x, 320.0)
			node.position = Vector2(roundf(x), roundf(host.ground_y_at(x) - 3.0 - fposmod(index * 7.0 + sin(time * 0.55 + index) * 1.5, 19.0)))
			node.visible = viewport.has_point(node.position)
			continue
		var anchor: Vector2 = item.anchor
		var source_view := Rect2(viewport.position - node.get_parent().global_position, viewport.size)
		node.visible = source_view.grow(float(maxi(steam_frame_size.x, steam_frame_size.y))).has_point(anchor)
		if not node.visible:
			continue
		var phase := fposmod(time / maxf(0.1, float(data.get("period", 3.0))) + float(data.get("phase", 0.0)), 1.0)
		if kind == "lights":
			# Warm lamp pixels come directly from their exact window region in the source panorama.
			var flicker := 0.5 + 0.5 * sin(phase * TAU)
			if phase > 0.73 and phase < 0.82:
				flicker *= 0.2
			var gain := lerpf(float(data.get("min_gain", 0.65)), float(data.get("max_gain", 1.25)), flicker)
			node.modulate = Color(gain, gain, gain, 1.0)
		elif kind == "steam":
			var emitter: Array = settings.get("steam_anchor", [24, 59])
			node.position = (anchor - Vector2(float(emitter[0]), float(emitter[1]))).round()
			(node as Sprite2D).frame = mini(_steam_used.size() - 1, int(phase * _steam_used.size()))
			var minimum := clampf(float(data.get("min_alpha", settings.get("steam_min_alpha", 0.30))), 0.0, 1.0)
			node.modulate.a = float(data.get("opacity", 0.18)) * lerpf(minimum, 1.0, sin(phase * PI))
		else:
			node.position = anchor.round()
			(node as PixelMark).tint = Color(0.63, 0.68, 0.69, float(data.get("opacity", 0.25)) * (0.22 + 0.78 * pow(0.5 + 0.5 * sin(phase * TAU), 2.0)))
			node.queue_redraw()


func effect_rect(item: Dictionary) -> Rect2:
	var node: Node2D = item.node
	if not node.visible:
		return Rect2()
	match String(item.kind):
		"lights":
			return Rect2(node.global_position, item.rect.size)
		"steam":
			if node.modulate.a < 0.002:
				return Rect2()
			var used: Rect2 = _steam_used[(node as Sprite2D).frame]
			return Rect2(node.global_position + used.position, used.size)
		_:
			return Rect2(node.global_position, (node as PixelMark).size)


func visible_effects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var viewport := Rect2(host.camera.position - Vector2(160, 90), Vector2(320, 180))
	for item: Dictionary in effects:
		var rect := effect_rect(item)
		if rect.has_area() and rect.intersects(viewport):
			result.append({"id": item.id, "kind": item.kind, "layer": item.layer,
				"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	return result
