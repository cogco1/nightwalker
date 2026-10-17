extends "res://scripts/enemies/humanoid.gd"
## 逃跑的买家: an organ buyer with a cooler box. Once woken, with the hero on his floor, he runs the other way to the
## end of the floor and cowers against the wall, shaking, the box dropped at his feet. He never fights; if the hero
## gets round him and the way opens again he runs on.

const RUN_SPEED := 52.0
const COAT := Color("6b5a48")
const COAT_HI := Color("8a7660")
const PANTS := Color("2d2a29")
const SHOES := Color("17130f")
const SKIN := Color("a07a66")
const HAIR := Color("77736f")
const BOX := Color("c8d3d6")
const BOX_BAND := Color("b3263a")

var cowering := false
var fled := 0.0


func _ready() -> void:
	max_hp = 3
	kind = "buyer"
	super()


func think(_step: float) -> void:
	var offset := hero_offset()
	if not hero_on_my_floor():
		velocity.x = 0.0
		return
	var away := -signf(offset) if offset != 0.0 else -facing
	if blocked(away, 4.0):
		cowering = true
		facing = -away
		velocity.x = 0.0
		return
	cowering = false
	facing = away
	walk(away, RUN_SPEED)
	fled += absf(velocity.x) * get_physics_process_delta_time()


func pose() -> String:
	if dead:
		return "dead"
	if cowering and flinch_left <= 0.0 and is_on_floor():
		return "cower"
	var base := super()
	if base == "walk_a" or base == "walk_b":
		return "run_a" if int(clock / 0.1) % 2 == 0 else "run_b"
	return base


func shiver_offset(current: String) -> int:
	return (1 if int(clock / 0.05) % 2 == 0 else 0) if current == "cower" else 0


func figure(current: String) -> Array:
	match current:
		"dead":
			return lying(COAT, PANTS, SKIN, HAIR) + [[10, -4, 6, 4, BOX], [10, -3, 6, 1, BOX_BAND]]
		"tumble":
			return tumbling(COAT, PANTS, SKIN, HAIR)
		"cower":
			# Crouched against the wall, arms over the head; the box on the floor in front.
			return legs("crouch", PANTS, SHOES) + [[-4, -14, 8, 9, COAT], [-3, -18, 5, 5, SKIN], [-4, -19, 6, 2, HAIR],
				[-4, -19, 8, 2, COAT_HI], [3, -17, 2, 4, COAT_HI], [7, -4, 6, 4, BOX], [7, -3, 6, 1, BOX_BAND]]
	var leg_mode := "stand"
	var lean := Vector2i.ZERO
	match current:
		"run_a":
			leg_mode = "walk_a"
			lean = Vector2i(1, 0)
		"run_b":
			leg_mode = "walk_b"
			lean = Vector2i(1, 1)
		"walk_a", "walk_b":
			leg_mode = current
		"flinch":
			lean = Vector2i(-1, 1)
	var upper: Array = [[-4, -21, 8, 11, COAT], [-4, -12, 8, 2, COAT_HI], [-2, -26, 5, 5, SKIN], [-3, -27, 6, 2, HAIR],
		[-3, -26, 1, 3, HAIR], [-5, -20, 2, 8, COAT_HI], [2, -20, 2, 7, COAT_HI], [2, -13, 2, 2, SKIN],
		[3, -14, 6, 5, BOX], [3, -12, 6, 1, BOX_BAND], [5, -15, 2, 1, PANTS]]
	return legs(leg_mode, PANTS, SHOES) + shifted(upper, lean.x, lean.y)
