extends "res://scripts/enemies/humanoid.gd"
## 近战安保: hospital security with a stun baton. Active, it walks up to the hero on its floor and swings through
## EnemyAttacker (enemy_attacker.gd): the body blinks red while the baton goes up (0.5 s), then a short lunge along
## the floor that stops just short of the hero; the hero's dodge, perfect dodge and counter work as against the
## practice drone. A hit while the baton is going up calls the swing off.

const ATTACKER = preload("res://scripts/enemies/enemy_attacker.gd")
const WALK_SPEED := 40.0
## Stops walking this close to the hero (px, horizontally); the swing reaches 32.
const ENGAGE := 24.0
const DAMAGE := 10
const COOLDOWN := 1.2
const UNIFORM := Color("2e3d57")
const UNIFORM_HI := Color("4a618a")
const UNIFORM_DARK := Color("1e2839")
const VEST := Color("434a55")
const PANTS := Color("252d3b")
const BOOTS := Color("15181e")
const SKIN := Color("8b6a5e")
const HELMET := Color("2a313d")
const BATON := Color("67717d")
const VISOR := Color("ff4a68")
const SPARK := Color("6fe8ff")

var attacker: Node
## Seconds between swings; the night lengthens it while the first lessons run.
var cooldown := COOLDOWN


func _ready() -> void:
	max_hp = 8
	kind = "guard"
	super()
	attacker = ATTACKER.new()
	attacker.name = "Attacker"
	attacker.horizontal = true
	attacker.returns = false
	attacker.mirror_hitbox = true
	attacker.reach = Vector2(32, 24)
	attacker.standoff = 12.0
	attacker.lunge_overshoot = 4.0
	attacker.lunge_seconds = 0.16
	attacker.active_seconds = 0.1
	attacker.hitbox = Rect2(-2, -26, 22, 22)
	attacker.aim_offset = Vector2.ZERO
	attacker.knockback = 22.0
	attacker.damage = DAMAGE
	attacker.cooldown_seconds = cooldown
	add_child(attacker)


func bind_hero(next: CharacterBody2D) -> void:
	super(next)
	attacker.bind_target(next)


func _physics_process(delta: float) -> void:
	attacker.armed = can_act() and hero_on_my_floor()
	attacker.cooldown_seconds = cooldown
	if attacker.phase in [attacker.Phase.LUNGE, attacker.Phase.RECOVER]:
		facing = attacker.lunge_heading()
	super(delta)


func moved_by_attack() -> bool:
	return attacker.phase == attacker.Phase.LUNGE


func think(_step: float) -> void:
	if attacker.phase == attacker.Phase.TELEGRAPH:
		face_hero()
	if attacker.phase != attacker.Phase.IDLE and attacker.phase != attacker.Phase.COOLDOWN:
		velocity.x = 0.0
		return
	face_hero()
	var offset := hero_offset()
	if hero_on_my_floor() and absf(offset) > ENGAGE:
		walk(signf(offset), WALK_SPEED)
	else:
		velocity.x = 0.0


func on_flinch() -> void:
	attacker.stagger(0.6)


func receive_charged_launch(direction: Vector2) -> void:
	# A charged launch cancels even a committed lunge; can_act keeps new swings off until landing.
	stand_down()
	attacker.armed = false
	super(direction)


## Story moments: any swing in progress is called off where the body stands.
func stand_down() -> void:
	attacker.post = global_position
	attacker.reset()


func _die() -> void:
	super()
	stand_down()
	attacker.set_physics_process(false)


func pose() -> String:
	if dead:
		return "dead"
	if attacker.phase == attacker.Phase.TELEGRAPH:
		return "windup"
	if attacker.phase == attacker.Phase.LUNGE or attacker.phase == attacker.Phase.RECOVER:
		return "strike"
	return super()


func figure(current: String) -> Array:
	return _parts(current)[0]


func glow_figure(current: String) -> Array:
	return _parts(current)[1]


## [body rectangles, glowing rectangles] of a pose.
func _parts(current: String) -> Array:
	match current:
		"dead":
			return [lying(UNIFORM, PANTS, SKIN, HELMET), []]
		"tumble":
			return [tumbling(UNIFORM, PANTS, SKIN, HELMET), []]
	var leg_mode := current if current in ["walk_a", "walk_b"] else ("lunge" if current == "strike" else "stand")
	var arm := "down"
	var lean := Vector2i.ZERO
	match current:
		"windup":
			arm = "raised"
			lean = Vector2i(-1, 0)
		"strike":
			arm = "forward"
			lean = Vector2i(1, 0)
		"flinch":
			lean = Vector2i(-1, 1)
	var upper: Array = [[-4, -21, 8, 10, UNIFORM], [-3, -20, 6, 6, VEST], [-4, -12, 8, 1, BOOTS],
		[-5, -20, 2, 8, UNIFORM_DARK], [-2, -26, 5, 5, SKIN], [-3, -28, 7, 3, HELMET], [-3, -25, 1, 3, HELMET]]
	var lights: Array = [[1, -25, 3, 1, VISOR]]
	match arm:
		"raised":
			upper.append_array([[1, -28, 2, 8, UNIFORM_HI], [1, -30, 2, 2, SKIN], [0, -37, 1, 7, BATON]])
			lights.append([0, -38, 1, 2, VISOR])
		"forward":
			upper.append_array([[2, -19, 7, 2, UNIFORM_HI], [9, -19, 2, 2, SKIN], [11, -19, 9, 1, BATON]])
			lights.append([19, -19, 2, 1, SPARK])
		_:
			upper.append_array([[2, -20, 2, 8, UNIFORM_HI], [2, -12, 2, 2, SKIN], [3, -11, 1, 6, BATON]])
			lights.append([3, -6, 1, 1, SPARK])
	return [legs(leg_mode, PANTS, BOOTS) + shifted(upper, lean.x, lean.y), shifted(lights, lean.x, lean.y)]
