extends RefCounted
## Building blocks every level shares: static colliders from rectangles or layout.json entries, and the
## pixel-snapped camera that follows the hero inside the world bounds. Static functions only; levels preload it.


## A StaticBody2D covering rectangle (centred on it, collision mask 0) added to parent. An empty body_name keeps
## Godot's generated name.
static func add_box(parent: Node, rectangle: Rect2, body_name := "", layer := 1, one_way := false) -> StaticBody2D:
	var body := StaticBody2D.new()
	if not body_name.is_empty():
		body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = rectangle.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rectangle.size
	collision.shape = shape
	collision.one_way_collision = one_way
	body.add_child(collision)
	parent.add_child(body)
	return body


## A collider from a layout.json entry: {id, rect} or {id, polygon}, optional one_way, and stair_only (no layer
## until the level switches the stairs on).
static func add_layout_collider(parent: Node, item: Dictionary) -> StaticBody2D:
	var layer := 0 if bool(item.get("stair_only", false)) else 1
	var one_way := bool(item.get("one_way", false))
	if not item.has("polygon"):
		return add_box(parent, rect(item["rect"]), String(item["id"]), layer, one_way)
	var body := StaticBody2D.new()
	body.name = String(item["id"])
	body.collision_layer = layer
	body.collision_mask = 0
	var polygon := CollisionPolygon2D.new()
	polygon.polygon = points(item["polygon"])
	polygon.one_way_collision = one_way
	body.add_child(polygon)
	parent.add_child(body)
	return body


## [x, y, width, height] from layout.json as a Rect2.
static func rect(values: Array) -> Rect2:
	return Rect2(values[0], values[1], values[2], values[3])


## [[x, y], ...] from layout.json as polygon points.
static func points(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in values:
		result.append(Vector2(point[0], point[1]))
	return result


## Centres camera on target rounded to whole pixels, kept half a view inside bounds so it never shows past the
## world's edges.
static func follow(camera: Camera2D, target: Vector2, bounds: Rect2, view_size: Vector2) -> void:
	var half_view := view_size * 0.5
	camera.global_position = target.round().clamp(bounds.position + half_view, bounds.end - half_view)
	camera.force_update_scroll()
