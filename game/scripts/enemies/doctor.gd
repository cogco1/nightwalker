extends "res://scripts/enemies/humanoid.gd"
## 求饶的医生: a surgeon of the organ trade, bloodied scrubs and mask. Asleep he works at his table; active, with the
## hero on his floor, he backs away and, once the hero is within KNEEL px, drops to his knees with his hands up and
## shakes. He never fights. The last doctor of the night (last) cannot be hurt until his three lines have been
## heard (executable, night_fight.gd); then any hit is the execution.

const NOTICE := 90.0
const KNEEL := 56.0
const BACK_SPEED := 22.0
const GOWN := Color("8fb0a6")
const GOWN_HI := Color("b2cdc4")
const GOWN_DARK := Color("68867e")
const STAIN := Color("6a1420")
const MASK := Color("d6e1df")
const CAP := Color("6f978d")
const SKIN := Color("a07a66")
const GLOVE := Color("c3d3dc")
const SHOES := Color("1c2224")
const SCALPEL := Color("d9f6ff")

var last := false
var executable := false
var begging := false


func _ready() -> void:
	max_hp = 2
	kind = "doctor"
	super()


func can_be_hurt() -> bool:
	return not last or executable


func take_damage(amount: int) -> bool:
	return super(maxi(amount, hp) if last and executable else amount)


func think(_step: float) -> void:
	if not hero_on_my_floor():
		velocity.x = 0.0
		return
	face_hero()
	var distance := absf(hero_offset())
	if distance <= KNEEL:
		begging = true
	if begging or distance > NOTICE or blocked(-facing):
		velocity.x = 0.0
	else:
		walk(-facing, BACK_SPEED)


func pose() -> String:
	if dead:
		return "dead"
	if begging and flinch_left <= 0.0 and is_on_floor():
		return "beg"
	if not active and is_on_floor():
		return "work"
	return super()


func shiver_offset(current: String) -> int:
	return (1 if int(clock / 0.06) % 2 == 0 else 0) if current == "beg" else 0


func figure(current: String) -> Array:
	return _parts(current)[0]


func glow_figure(current: String) -> Array:
	return _parts(current)[1]


func _parts(current: String) -> Array:
	match current:
		"dead":
			return [lying(GOWN, GOWN_DARK, SKIN, CAP), []]
		"tumble":
			return [tumbling(GOWN, GOWN_DARK, SKIN, CAP), []]
	var head: Array = [[-2, -26, 5, 5, SKIN], [-3, -28, 7, 3, CAP], [0, -23, 3, 2, MASK]]
	var gown: Array = [[-4, -21, 8, 13, GOWN], [-4, -9, 8, 1, GOWN_DARK], [1, -16, 2, 2, STAIN], [-2, -12, 1, 2, STAIN]]
	match current:
		"beg":
			# On his knees, both hands up and open.
			var raised: Array = gown + head + [[-6, -21, 2, 2, GOWN_HI], [4, -21, 2, 2, GOWN_HI], [-7, -27, 2, 6, GOWN_HI],
				[5, -27, 2, 6, GOWN_HI], [-7, -29, 2, 2, GLOVE], [5, -29, 2, 2, GLOVE]]
			return [legs("kneel", GOWN_DARK, SHOES) + shifted(raised, 0, 5), []]
		"work":
			# Bent over the table, hands forward, the scalpel catching the light.
			var bent: Array = gown + head + [[-5, -20, 2, 7, GOWN_DARK], [2, -18, 7, 2, GOWN_HI], [9, -18, 2, 2, GLOVE]]
			return [legs("stand", GOWN_DARK, SHOES) + shifted(bent, 1, 1), [[12, -17, 2, 1, SCALPEL]]]
	var leg_mode := current if current in ["walk_a", "walk_b"] else "stand"
	var lean := Vector2i(-1, 1) if current == "flinch" else Vector2i.ZERO
	var upper: Array = gown + head + [[-5, -20, 2, 8, GOWN_DARK], [2, -20, 2, 8, GOWN_HI], [2, -12, 2, 2, GLOVE]]
	return [legs(leg_mode, GOWN_DARK, SHOES) + shifted(upper, lean.x, lean.y), []]
