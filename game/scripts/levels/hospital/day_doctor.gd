extends CharacterBody2D
## Noncombat day staff. A small collision footprint follows short room patrols; layer 0 lets the hero pass.
## Movement stays continuous, while the four facing drawings and breathing render on the native pixel grid.

const SIGHT = preload("res://scripts/levels/hospital/doctor_sight.gd")
const WALK_SPEED := 18.0
const BODY_HEIGHT := 28
const GROUP := &"hospital_day_staff"
const OUTLINE := Color("101923")
const COAT := Color("c7ccc1")
const COAT_LIGHT := Color("e0e0cf")
const COAT_SHADE := Color("869e99")
const SCRUBS := Color("426b70")
const PANTS := Color("263b4a")
const SHOES := Color("141e29")
const SKIN := Color("b78c73")
const MASK := Color("b9d8d3")
const MASK_SHADE := Color("719b9b")
const GLOVE := Color("b2c9c3")
const METAL := Color("8bb8bd")
const HAIR := [Color("514b48"), Color("777f7b"), Color("303d48")]

var staff_id := ""
var floor_id := 1
var face_direction := Vector2.DOWN
var appearance := 0
var breath_frame := 0
var walk_frame := 0
var patrol_points: Array[Vector2] = []
var patrol_clock := 0.0
var hospital: Node2D
var sight: Node2D
var _next_point := 1
var _patrol_step := 1
var _pause_left := 0.6
var _walk_distance := 0.0
var _moving := false


func configure(record: Dictionary, floor_number: int, host: Node2D) -> void:
	staff_id = String(record["id"])
	floor_id = floor_number
	hospital = host
	for point: Vector2 in record["points"]:
		patrol_points.append(point)
	position = patrol_points[0]
	scale = Vector2.ONE
	appearance = int(record.get("appearance", 0))
	_pause_left += appearance * 0.2
	if patrol_points.size() > 1:
		_face(patrol_points[1] - position)
	name = "Doctor_" + staff_id
	z_index = 1
	process_physics_priority = 105
	collision_layer = 0
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	add_to_group(GROUP)
	var footprint := CollisionShape2D.new()
	footprint.name = "Footprint"
	footprint.position = Vector2(0, -4)
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12, 8)
	footprint.shape = rectangle
	add_child(footprint)
	sight = SIGHT.new()
	sight.name = "Sight"
	sight.configure(self)
	add_child(sight)


func context_active() -> bool:
	if not is_inside_tree() or not is_instance_valid(hospital) or hospital.view_mode != 0 or hospital.floor_id != floor_id:
		return false
	var chapter: Node = hospital.get("chapter")
	return is_instance_valid(chapter) and chapter.story.chapter_active and not chapter.story.is_night()


func motion_blocked() -> bool:
	return not context_active() or hospital.chapter._input_blocked()


func sees_player(hero: Node2D) -> bool:
	return is_instance_valid(sight) and sight.sees_player(hero)


func _face(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	face_direction = Vector2(signf(direction.x), 0) if absf(direction.x) >= absf(direction.y) else Vector2(0, signf(direction.y))


func _reach_point() -> void:
	var endpoint := _next_point == 0 or _next_point == patrol_points.size() - 1
	if endpoint:
		_patrol_step *= -1
	_next_point += _patrol_step
	_pause_left = 1.2 if endpoint else 0.3


func _physics_process(delta: float) -> void:
	if motion_blocked():
		velocity = Vector2.ZERO
		return
	var session: Node = hospital.get_node_or_null("GameSession")
	var scale := float(session.world_time_scale) if session != null else 1.0
	var step := delta * scale
	patrol_clock += step
	breath_frame = int(patrol_clock / (1.1 + appearance * 0.15)) % 2
	_moving = false
	velocity = Vector2.ZERO
	if patrol_points.size() > 1:
		var offset := patrol_points[_next_point] - position
		if _pause_left > 0.0:
			_pause_left -= step
			if _pause_left <= 0.4:
				_face(offset)
		elif offset.length() <= 0.25:
			_reach_point()
		else:
			_face(offset)
			velocity = offset.normalized() * minf(WALK_SPEED * scale, offset.length() / delta)
			var previous := position
			move_and_slide()
			var distance := position.distance_to(previous)
			_moving = distance > 0.01
			_walk_distance += distance
			walk_frame = int(_walk_distance / 1.5) % 4
			if get_slide_collision_count() > 0 and not _moving:
				# If furniture changes, turn back along the last clear leg; never walk through the obstacle.
				_patrol_step *= -1
				_next_point = clampi(_next_point + _patrol_step, 0, patrol_points.size() - 1)
				_pause_left = 0.8
	queue_redraw()


## Solid integer rectangles, matching the existing code-drawn humans' approximate 28px proportions.
func figure() -> Array:
	var b := -1 if _moving and walk_frame % 2 == 1 else -breath_frame
	var hair: Color = HAIR[posmod(appearance, HAIR.size())]
	var stride: int = [0, 1, 0, -1][walk_frame] if _moving else 0
	var legs: Array
	if face_direction.x != 0:
		legs = [[-2 - stride, -8, 3, 6, PANTS], [1 + stride, -8, 3, 6, PANTS],
			[-3 - stride, -2, 4, 2, SHOES], [1 + stride, -2, 4, 2, SHOES]]
	else:
		legs = [[-3, -8, 3, 6, PANTS], [1, -8, 3, 6, PANTS],
			[-4, -2 - maxi(stride, 0), 4, 2, SHOES], [1, -2 - maxi(-stride, 0), 4, 2, SHOES]]
	if face_direction.x != 0:
		return legs + [
			[-4, -20 + b, 8, 13, COAT_SHADE], [-3, -20 + b, 6, 13, COAT], [1, -19 + b, 2, 11, COAT_LIGHT],
			[-5, -18 + b, 2, 8, COAT_SHADE], [3, -18 + b, 2, 8, COAT_LIGHT], [3, -10 + b, 2, 2, GLOVE],
			[1, -18 + b, 1, 4, OUTLINE], [1, -14 + b, 2, 1, METAL], [-1, -17 + b, 2, 2, COAT_LIGHT],
			[-2, -26, 5, 6, SKIN], [-3, -27, 5, 4, hair], [-2, -27, 3, 1, COAT_SHADE],
			[2, -25, 1, 1, OUTLINE], [2, -23, 2, 2, MASK_SHADE], [2, -23, 2, 1, MASK],
		]
	if face_direction.y < 0:
		return legs + [
			[-4, -20 + b, 9, 13, COAT_SHADE], [-3, -20 + b, 7, 13, COAT], [-3, -20 + b, 7, 2, COAT_LIGHT],
			[-5, -19 + b, 2, 9, COAT_SHADE], [4, -19 + b, 2, 9, COAT_LIGHT],
			[-5, -10 + b, 2, 2, GLOVE], [4, -10 + b, 2, 2, GLOVE], [0, -18 + b, 1, 10, COAT_SHADE],
			[-2, -26, 5, 6, SKIN], [-3, -27, 6, 5, hair], [-2, -27, 4, 1, COAT_SHADE],
			[-3, -24, 1, 2, SKIN], [3, -24, 1, 2, SKIN],
		]
	return legs + [
		[-4, -20 + b, 9, 13, COAT_SHADE], [-3, -20 + b, 7, 13, COAT],
		[-5, -19 + b, 2, 9, COAT_SHADE], [4, -19 + b, 2, 9, COAT_LIGHT],
		[-5, -10 + b, 2, 2, GLOVE], [4, -10 + b, 2, 2, GLOVE],
		[-1, -19 + b, 2, 10, SCRUBS], [-2, -20 + b, 2, 3, COAT_LIGHT],
		[1, -20 + b, 2, 3, COAT_LIGHT], [-1, -10 + b, 2, 3, PANTS],
		[-3, -9 + b, 1, 1, COAT_SHADE], [3, -8 + b, 1, 1, COAT_SHADE],
		# A clipped badge and a dark stethoscope with its single bright metal bell.
		[-3, -17 + b, 2, 3, COAT_LIGHT], [-3, -17 + b, 2, 1, SCRUBS],
		[-1, -19 + b, 1, 4, OUTLINE], [1, -19 + b, 1, 4, OUTLINE],
		[-1, -15 + b, 3, 1, OUTLINE], [1, -15 + b, 2, 1, METAL],
		# Hair, eyes and mask do not change between the two breathing poses.
		[-2, -26, 5, 6, SKIN], [-3, -27, 6, 3, hair], [-2, -27, 4, 1, COAT_SHADE],
		[-3, -24, 1, 2, SKIN], [-1, -24, 1, 1, OUTLINE], [2, -24, 1, 1, OUTLINE],
		[-2, -23, 5, 2, MASK_SHADE], [-1, -23, 4, 1, MASK],
	]


func _rect(part: Array) -> Rect2:
	var x := int(part[0])
	var width := int(part[2])
	return Rect2(-x - width if face_direction.x < 0 else x, int(part[1]), width, int(part[3]))


func _draw() -> void:
	draw_set_transform(global_position.round() - global_position)
	draw_rect(Rect2(-6, 0, 12, 1), Color("10192380"))
	var parts := figure()
	for part: Array in parts:
		var border := _rect(part).grow(1.0)
		# Keep the sole baseline and the 28px silhouette, including its outline, fixed.
		border.position.y = maxf(border.position.y, -BODY_HEIGHT)
		border.end.y = minf(border.end.y, 0.0)
		draw_rect(border, OUTLINE)
	for part: Array in parts:
		draw_rect(_rect(part), part[4])
