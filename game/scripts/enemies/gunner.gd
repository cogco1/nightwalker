extends "res://scripts/enemies/humanoid.gd"
## 持枪保镖: a buyer's armed bodyguard. Active, it keeps 64-150 px from the hero on its floor and shoots: a red laser
## sight tracks the hero for AIM_SECONDS (the last LOCK_SECONDS it holds still and blinks fast), then a bullet
## (enemy_bullet.gd) flies along the sight at chest height. The bullet can be dashed through, jumped or ducked; a
## dash just before it arrives is a perfect dodge whose counter blinks the hero to this gunner. A hit while aiming
## spoils the shot.

signal fired(bullet: Node2D)

const BULLET = preload("res://scripts/enemies/enemy_bullet.gd")
enum Shot { READY, AIM, RECOIL }
const AIM_SECONDS := 0.8
const LOCK_SECONDS := 0.25
const RECOIL_SECONDS := 0.3
const COOLDOWN := 1.5
const FIRST_SHOT_DELAY := 0.6
const NEAR := 64.0
const FAR := 150.0
const RANGE := 200.0
const WALK_SPEED := 38.0
const BACK_SPEED := 30.0
## Muzzle facing right, from the feet: the bullet's height.
const MUZZLE := Vector2(14, -19)
const DAMAGE := 15
const SUIT := Color("23262f")
const SUIT_HI := Color("3a4050")
const SHIRT := Color("c9ccd0")
const TIE := Color("6a1c28")
const SKIN := Color("9a7563")
const HAIR := Color("121214")
const GLASSES := Color("07080a")
const SHOES := Color("0c0d10")
const GUN := Color("44484f")
const LASER := Color("ff2f4f")
const GLINT := Color("a8f4ff")
const MUZZLE_FLASH := Color("ffe08a")

var shot := Shot.READY
var shot_time := 0.0
var cooldown_left := FIRST_SHOT_DELAY
var shots_fired := 0
## Where the laser sight ends (world): the hero's body or a wall.
var sight_end := Vector2.ZERO
var _flash_left := 0.0


func _ready() -> void:
	max_hp = 5
	kind = "gunner"
	super()


func _physics_process(delta: float) -> void:
	var step := delta * world_scale()
	_flash_left = maxf(0.0, _flash_left - step)
	if active and not held and shot == Shot.READY:
		cooldown_left = maxf(0.0, cooldown_left - step)
	super(delta)


func muzzle() -> Vector2:
	return global_position + Vector2(MUZZLE.x * facing, MUZZLE.y)


func aiming() -> bool:
	return shot == Shot.AIM


## The sight has stopped tracking and blinks: the shot is about to go.
func locked() -> bool:
	return shot == Shot.AIM and shot_time > AIM_SECONDS - LOCK_SECONDS


func think(step: float) -> void:
	if not hero_on_my_floor():
		velocity.x = 0.0
		if shot == Shot.AIM:
			_spoil(FIRST_SHOT_DELAY)
		return
	match shot:
		Shot.AIM:
			velocity.x = 0.0
			shot_time += step
			if not locked():
				face_hero()
			_track()
			if shot_time >= AIM_SECONDS:
				_fire()
		Shot.RECOIL:
			velocity.x = 0.0
			shot_time += step
			if shot_time >= RECOIL_SECONDS:
				shot = Shot.READY
				cooldown_left = COOLDOWN
		_:
			face_hero()
			var offset := hero_offset()
			var distance := absf(offset)
			if distance < NEAR and not blocked(-signf(offset)):
				walk(-signf(offset), BACK_SPEED)
			elif distance > FAR:
				walk(signf(offset), WALK_SPEED)
			else:
				velocity.x = 0.0
			if cooldown_left <= 0.0 and distance <= RANGE:
				shot = Shot.AIM
				shot_time = 0.0
				_track()


## Laser sight along the muzzle height: up to the hero's body when the hero is in line, else to the wall.
func _track() -> void:
	var start := muzzle()
	var far_point := start + Vector2(facing * RANGE * 1.6, 0)
	var ray := PhysicsRayQueryParameters2D.create(start, far_point, 1)
	var wall := get_world_2d().direct_space_state.intersect_ray(ray)
	sight_end = Vector2(wall["position"].x, start.y) if not wall.is_empty() else far_point
	if is_instance_valid(hero):
		var box: Rect2 = hero.hurtbox()
		var front := box.position.x if facing > 0.0 else box.end.x
		if start.y >= box.position.y and start.y <= box.end.y and (front - start.x) * facing > 0.0 \
				and absf(front - start.x) < absf(sight_end.x - start.x):
			sight_end.x = front


func _fire() -> void:
	var bullet: Node2D = BULLET.new()
	bullet.setup(self, hero, muzzle(), facing, DAMAGE)
	get_parent().add_child(bullet)
	shots_fired += 1
	_flash_left = 0.08
	shot = Shot.RECOIL
	shot_time = 0.0
	fired.emit(bullet)


func _spoil(wait: float) -> void:
	shot = Shot.READY
	shot_time = 0.0
	cooldown_left = wait


func on_flinch() -> void:
	if shot != Shot.READY:
		_spoil(0.9)


func stand_down() -> void:
	_spoil(1.0)


func pose() -> String:
	if dead:
		return "dead"
	if shot == Shot.AIM and is_on_floor() and flinch_left <= 0.0:
		return "aim"
	if shot == Shot.RECOIL and is_on_floor():
		return "fire"
	return super()


func figure(current: String) -> Array:
	return _parts(current)[0]


func glow_figure(current: String) -> Array:
	return _parts(current)[1]


func _parts(current: String) -> Array:
	match current:
		"dead":
			return [lying(SUIT, SUIT, SKIN, HAIR), []]
		"tumble":
			return [tumbling(SUIT, SUIT, SKIN, HAIR), []]
	var leg_mode := current if current in ["walk_a", "walk_b"] else "stand"
	var lean := Vector2i(-1, 1) if current == "flinch" else (Vector2i(-1, 0) if current == "fire" else Vector2i.ZERO)
	var upper: Array = [[-4, -21, 8, 10, SUIT], [0, -21, 2, 4, SHIRT], [0, -19, 1, 4, TIE],
		[-2, -26, 5, 5, SKIN], [-3, -28, 6, 3, HAIR], [-3, -26, 1, 3, HAIR], [1, -25, 3, 1, GLASSES]]
	var lights: Array = [[3, -25, 1, 1, GLINT]]
	if current == "aim" or current == "fire":
		# Both hands on the pistol, arm level at the muzzle height.
		upper.append_array([[1, -20, 7, 2, SUIT], [2, -19, 7, 2, SUIT_HI], [9, -20, 2, 2, SKIN], [10, -21, 4, 2, GUN],
			[10, -19, 1, 2, GUN]])
		lights.append([13, -20, 1, 1, LASER])
		if current == "fire" and _flash_left > 0.0:
			lights.append_array([[15, -22, 3, 4, MUZZLE_FLASH], [18, -21, 2, 2, MUZZLE_FLASH]])
	else:
		upper.append_array([[-5, -20, 2, 9, SUIT_HI], [2, -20, 2, 9, SUIT_HI], [2, -11, 2, 2, SKIN], [3, -10, 2, 3, GUN]])
	return [legs(leg_mode, SUIT, SHOES) + shifted(upper, lean.x, lean.y), shifted(lights, lean.x, lean.y)]


## The laser sight while aiming: flickering while it tracks, solid and blinking fast once locked; a dot where it ends.
func draw_glow_extra(canvas: Node2D) -> void:
	if shot != Shot.AIM or dead or held:
		return
	var start := muzzle() - global_position
	var end := sight_end - global_position
	var alpha := 0.0
	if locked():
		alpha = 0.95 if int(clock / 0.05) % 2 == 0 else 0.45
	else:
		alpha = 0.55 if int(clock / 0.1) % 2 == 0 else 0.32
	var left := minf(start.x, end.x)
	canvas.draw_rect(Rect2(roundf(left), roundf(start.y), roundf(absf(end.x - start.x)), 1), Color(LASER, alpha))
	canvas.draw_rect(Rect2(roundf(end.x) - 1, roundf(start.y) - 1, 2, 2), Color(LASER, minf(1.0, alpha + 0.2)))
