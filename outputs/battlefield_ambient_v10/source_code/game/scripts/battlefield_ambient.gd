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
var _atlases: Dictionary = {}
var vehicle_seed := 0
var vehicle_assignments: Array[Dictionary] = []


func configure(scene: Node2D) -> bool:
	host = scene
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if not parsed is Dictionary:
		push_error("Battlefield ambient settings must be a dictionary.")
		return false
	settings = parsed
	update_hz = clampf(float(settings.get("update_hz", 16.0)), 1.0, 30.0)
	_update_step = 1.0 / update_hz
	var steam_atlas := _load_atlas({"texture": settings.get("steam_texture", ""),
		"frame_size": settings.get("steam_frame_size", [64, 64]), "frames": settings.get("steam_frames", [3, 2]),
		"anchor": settings.get("steam_anchor", [24, 59])})
	if steam_atlas.is_empty():
		return false
	steam_frame_size = steam_atlas.frame_size
	steam_grid = steam_atlas.grid
	_steam_used = steam_atlas.used
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
				node = _atlas_sprite(steam_atlas)
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
				"data": data, "anchor": Vector2(float(anchor[0]), float(anchor[1])), "rect": bounds,
				"atlas": steam_atlas if kind == "steam" else {}})
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
	return _build_vehicle_effects()


func _load_atlas(data: Dictionary) -> Dictionary:
	var path := String(data.get("texture", ""))
	if _atlases.has(path):
		return _atlases[path]
	var frame_size: Array = data.get("frame_size", [64, 64])
	var frames: Array = data.get("frames", [3, 2])
	var size := Vector2i(int(frame_size[0]), int(frame_size[1]))
	var grid := Vector2i(int(frames[0]), int(frames[1]))
	var texture := load(path) as Texture2D
	if size.x <= 0 or size.y <= 0 or grid.x <= 0 or grid.y <= 0 or texture == null \
			or Vector2i(texture.get_size()) != size * grid:
		push_error("Ambient atlas must match its positive native frame size and grid: " + path)
		return {}
	var raw_anchor: Array = data.get("anchor", [size.x / 2, size.y - 1])
	var atlas := {"texture": texture, "frame_size": size, "grid": grid,
		"anchor": Vector2(float(raw_anchor[0]), float(raw_anchor[1]))}
	var image := texture.get_image()
	var used: Array[Rect2] = []
	for frame in range(grid.x * grid.y):
		var origin := Vector2i((frame % grid.x) * size.x, int(frame / grid.x) * size.y)
		used.append(Rect2(image.get_region(Rect2i(origin, size)).get_used_rect()))
	atlas["used"] = used
	_atlases[path] = atlas
	return atlas


func _atlas_sprite(atlas: Dictionary) -> Sprite2D:
	var node := Sprite2D.new()
	node.texture = atlas.texture
	node.centered = false
	node.hframes = atlas.grid.x
	node.vframes = atlas.grid.y
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return node


func _build_vehicle_effects() -> bool:
	var config: Dictionary = settings.get("vehicle_effects", {})
	var emitters: Array = config.get("emitters", [])
	if emitters.is_empty():
		return true
	var variants: Array = config.get("variants", [])
	if variants.size() < 3:
		push_error("Vehicle smoke/fire needs at least three distinct native variants.")
		return false
	var rng := RandomNumberGenerator.new()
	if int(config.get("random_seed", 0)) == 0:
		rng.randomize()
		# Keep the recorded seed exactly representable when JSON is parsed as a double.
		rng.seed = maxi(1, int(rng.randi()))
	else:
		rng.seed = int(config.random_seed)
	vehicle_seed = rng.seed
	var order: Array[int] = []
	for index in range(variants.size()):
		order.append(index)
	var jitter: Array = config.get("jitter", [1, 0])
	for index in range(emitters.size()):
		# A shuffled bag guarantees variety; phase, speed and offsets are chosen only here.
		if index % order.size() == 0:
			for swap_index in range(order.size() - 1, 0, -1):
				var other := rng.randi_range(0, swap_index)
				var saved := order[swap_index]
				order[swap_index] = order[other]
				order[other] = saved
		var emitter: Dictionary = emitters[index]
		var variant: Dictionary = variants[order[index % order.size()]]
		var offset := Vector2(rng.randi_range(-absi(int(jitter[0])), absi(int(jitter[0]))),
			rng.randi_range(-absi(int(jitter[1])), absi(int(jitter[1]))))
		var assignment := {"vehicle_id": String(emitter.vehicle_id), "variant_id": String(variant.id),
			"offset": [offset.x, offset.y]}
		for kind in ["smoke", "fire"]:
			var atlas := _load_atlas(variant[kind])
			if atlas.is_empty():
				return false
			var period_range: Array = config.get(kind + "_period", [1.8, 2.8] if kind == "smoke" else [0.55, 0.9])
			var data := {"period": rng.randf_range(float(period_range[0]), float(period_range[1])),
				"phase": rng.randf(), "opacity": float(emitter.get(kind + "_opacity", 0.55 if kind == "smoke" else 0.9)),
				"min_alpha": float(config.get("smoke_min_alpha", 0.35))}
			var raw_position: Array = emitter.get(kind + "_position", emitter.get("position", [0, 0]))
			var anchor := Vector2(float(raw_position[0]), float(raw_position[1])) + offset
			var node := _atlas_sprite(atlas)
			node.name = String(emitter.get("id", emitter.vehicle_id)) + "_" + kind
			node.position = (anchor - Vector2(atlas.anchor)).round()
			host.add_child(node)
			effects.append({"id": String(node.name), "kind": "vehicle_" + kind, "layer": "world", "node": node,
				"data": data, "anchor": anchor, "atlas": atlas, "vehicle_id": String(emitter.vehicle_id), "variant_id": String(variant.id)})
			assignment[kind + "_phase"] = data.phase
			assignment[kind + "_period"] = data.period
			assignment[kind + "_anchor"] = [anchor.x, anchor.y]
		vehicle_assignments.append(assignment)
	return true


func _layer(layer: String) -> Node2D:
	if layer == "world":
		return host
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
		elif kind in ["steam", "vehicle_smoke", "vehicle_fire"]:
			var atlas: Dictionary = item.atlas
			node.position = (anchor - Vector2(atlas.anchor)).round()
			(node as Sprite2D).frame = mini(atlas.used.size() - 1, int(phase * atlas.used.size()))
			if kind == "vehicle_fire":
				node.modulate.a = float(data.opacity) * (0.85 + 0.15 * sin(phase * TAU))
			else:
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
		"steam", "vehicle_smoke", "vehicle_fire":
			if node.modulate.a < 0.002:
				return Rect2()
			var used: Rect2 = item.atlas.used[(node as Sprite2D).frame]
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
