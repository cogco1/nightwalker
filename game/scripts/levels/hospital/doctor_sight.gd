extends Node2D
## The same native-grid cone is used for sight and its faint floor overlay. Live hero checks cast one ray;
## the cosmetic fan clips seventeen rays against actual walls/furniture at 10Hz, or immediately on turning.

const RADIUS := 64.0
const HALF_ANGLE := PI * 0.25
const EYE_OFFSET := Vector2(0, -4)
const UPDATE_SECONDS := 0.1
const RAYS := 17
const FILL := Color("d2d8ae16")
const EDGE := Color("d2d8ae32")

var doctor: CharacterBody2D
var polygon := PackedVector2Array()
var _elapsed := UPDATE_SECONDS
var _last_direction := Vector2.ZERO


func configure(owner_doctor: CharacterBody2D) -> void:
	doctor = owner_doctor
	position = EYE_OFFSET
	z_index = -1
	process_physics_priority = 106
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func origin() -> Vector2:
	return doctor.global_position.round() + EYE_OFFSET


func _ray(to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(origin(), to, 1, [doctor.get_rid()])
	return doctor.get_world_2d().direct_space_state.intersect_ray(query)


## The query remains usable when a fixture pauses only the doctor's patrol physics.
func sees_player(hero: Node2D) -> bool:
	if not is_instance_valid(hero) or not doctor.context_active():
		return false
	var to := hero.global_position.round() + EYE_OFFSET
	var offset := to - origin()
	if offset.length_squared() > RADIUS * RADIUS:
		return false
	if not offset.is_zero_approx() and offset.normalized().dot(doctor.face_direction) < cos(HALF_ANGLE):
		return false
	return _ray(to).is_empty()


func _physics_process(delta: float) -> void:
	if not doctor.context_active():
		hide()
		return
	show()
	if doctor.motion_blocked():
		return
	# Snap the overlay every displayed step; only its expensive occlusion rays use the slower cadence.
	queue_redraw()
	_elapsed += delta
	if _elapsed >= UPDATE_SECONDS or _last_direction != doctor.face_direction:
		refresh()


func refresh() -> void:
	if not is_inside_tree() or not is_instance_valid(doctor):
		return
	_elapsed = 0.0
	_last_direction = doctor.face_direction
	polygon = PackedVector2Array([Vector2.ZERO])
	var start: Vector2 = origin()
	var forward: float = doctor.face_direction.angle()
	for index in range(RAYS):
		var angle := forward - HALF_ANGLE + (2.0 * HALF_ANGLE * index) / (RAYS - 1)
		var direction := Vector2.from_angle(angle)
		var end := start + direction * RADIUS
		var hit := _ray(end)
		if not hit.is_empty():
			end = Vector2(hit["position"]) - direction * 0.75
		var point := end.round() - start
		if polygon[-1] != point:
			polygon.append(point)
	queue_redraw()


func _draw() -> void:
	if polygon.size() < 3:
		return
	draw_set_transform(global_position.round() - global_position)
	draw_colored_polygon(polygon, FILL)
	var border := polygon.duplicate()
	border.append(Vector2.ZERO)
	draw_polyline(border, EDGE, 1.0, false)
