extends Node2D
## Ambient clinic staff, separate from the night enemies. Feet stay on the native grid; a two-pose coat
## breathes by one pixel while the face and shoes stay fixed. No combat, collision or interaction interface.

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
var facing := 1
var appearance := 0
var breath_frame := 0
var breath_timer: Timer


func configure(record: Dictionary, floor_number: int) -> void:
	staff_id = String(record["id"])
	floor_id = floor_number
	var feet: Vector2i = record["feet"]
	position = Vector2(feet)
	scale = Vector2.ONE
	facing = int(record.get("facing", 1))
	appearance = int(record.get("appearance", 0))
	name = "Doctor_" + staff_id
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	add_to_group(GROUP)
	breath_timer = Timer.new()
	breath_timer.name = "Breath"
	breath_timer.wait_time = 1.1 + appearance * 0.15
	breath_timer.timeout.connect(func() -> void:
		breath_frame = 1 - breath_frame
		queue_redraw())
	add_child(breath_timer)
	breath_timer.start()


## Solid integer rectangles, matching the existing code-drawn humans' approximate 28px proportions.
func figure() -> Array:
	var b := -breath_frame
	var hair: Color = HAIR[posmod(appearance, HAIR.size())]
	return [
		[-3, -8, 3, 6, PANTS], [1, -8, 3, 6, PANTS],
		[-4, -2, 4, 2, SHOES], [1, -2, 4, 2, SHOES],
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
	return Rect2(-x - width if facing < 0 else x, int(part[1]), width, int(part[3]))


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
