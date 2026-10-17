extends CharacterBody2D
## Side-view human of the chapter nights, drawn in code on the native grid until the real sprites exist (like
## story_target.gd). Origin is the feet; about 28 px tall. The hero hits it like any target (take_damage,
## damage_point, receive_hit_reaction, knock_up, knock_back): a hit flinches it, a launcher throws it up, airborne
## hits juggle it, the last hit leaves a body on the floor. It does not block the hero (a collision exception).
## Its own time runs on the world clock (GameSession.world_time_scale), so the perfect-dodge slow motion slows it.
##
## The kinds (guard.gd, gunner.gd, buyer.gd, doctor.gd) say what an active one does in think() and how it looks
## in figure(); night_fight.gd wakes them (active), holds them during story moments (held) and binds the hero.

signal defeated(enemy: Node2D)

const GRAVITY := 620.0
const FRICTION := 280.0
const FLINCH_SECONDS := 0.28
const AIR_HOLD_SECONDS := 0.55
const OUTLINE := Color("0b0f14")
const FLASH := Color("f0e8d8")
const BLOOD := Color("5a0f1c")
const SLASH := Color("8ebce8")
const SLASH_CORE := Color("f2f8ff")
## Feet above this height are on floor 2 of the side-view hospital (floor 1 at 286, floor 2 at 164): floor 1's
## ceiling, the floor-2 slab, ends at 174, so a hero jumping on floor 1 keeps the feet below about 200.
const FLOOR_SPLIT := 190.0

@export var max_hp := 4
var hp := 4
## Chapter id (chapter1.json nights.*.enemies[].id) and kind name.
var id := ""
var kind := ""
var floor_id := 1
## Woken by the night: it fights, flees or begs; asleep it keeps to its post.
var active := false
## Story moments (death, dialogue, execution) hold everyone still.
var held := false
var dead := false
var hero: CharacterBody2D
## 1 faces right, -1 left.
var facing := -1.0
var flinch_left := 0.0
var flash_left := 0.0
var slash_flash_left := 0.0
var air_hold_left := 0.0
var last_hit_direction := Vector2.RIGHT
var hits_taken := 0
## Seconds on the world clock, for walk cycles and shivers.
var clock := 0.0
var body_shape: CollisionShape2D
## Unshaded child for what glows in the dark (visors, laser sights, muzzle flashes): night lighting does not dim it.
var glow: Node2D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	hp = max_hp
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_snap_length = 4.0
	body_shape = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 26)
	body_shape.position = Vector2(0, -13)
	body_shape.shape = shape
	add_child(body_shape)
	glow = Node2D.new()
	glow.name = "Glow"
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = unshaded
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(glow)
	glow.draw.connect(_draw_glow_layer)
	floor_id = 2 if position.y < FLOOR_SPLIT else 1


## The hero it reacts to; the hero walks through it rather than being blocked.
func bind_hero(next: CharacterBody2D) -> void:
	hero = next
	add_collision_exception_with(hero)


func world_scale() -> float:
	var session := get_tree().get_first_node_in_group(&"game_session") if is_inside_tree() else null
	return float(session.world_time_scale) if session != null else 1.0


func hero_on_my_floor() -> bool:
	return is_instance_valid(hero) and (2 if hero.global_position.y < FLOOR_SPLIT else 1) == floor_id


## Horizontal offset to the hero (positive: the hero is to the right).
func hero_offset() -> float:
	return hero.global_position.x - global_position.x if is_instance_valid(hero) else 0.0


func face_hero() -> void:
	var offset := hero_offset()
	if absf(offset) > 1.0:
		facing = signf(offset)


func can_act() -> bool:
	return active and not held and not dead and flinch_left <= 0.0 and is_on_floor() and is_instance_valid(hero)


# --- the hero's attacks ------------------------------------------------------------------------

func damage_point() -> Vector2:
	return global_position + Vector2(0, -17)


## Whether hits land at all (the last doctor is untouchable until his words are said).
func can_be_hurt() -> bool:
	return true


func take_damage(amount: int) -> bool:
	if dead or amount <= 0 or not can_be_hurt():
		return false
	hp = maxi(0, hp - amount)
	hits_taken += 1
	flash_left = 0.10
	if hp == 0:
		_die()
	queue_redraw()
	return true


func receive_hit_reaction(direction: Vector2, strong: bool = false, air_combo: bool = false) -> void:
	last_hit_direction = direction
	slash_flash_left = 0.08
	if absf(direction.x) > 0.0:
		facing = -signf(direction.x)
	flinch_left = FLINCH_SECONDS
	on_flinch()
	if strong:
		knock_up(direction)
	elif air_combo and not is_on_floor():
		air_hold_left = AIR_HOLD_SECONDS
		velocity = Vector2(0, 6.0)
	else:
		knock_small(direction)
	queue_redraw()


func knock_up(direction: Vector2) -> void:
	air_hold_left = 0.0
	velocity = Vector2(signf(direction.x) * 55.0, -300.0)


## Charged cuts expose the same physical launch and jump-chase interface as the other combat targets.
func receive_charged_launch(direction: Vector2) -> void:
	receive_hit_reaction(direction, true, false)
	velocity.x = signf(direction.x) * 105.0


## Pushes a grounded body about `distance` px away (ground friction brakes it).
func knock_back(direction: Vector2, distance: float) -> void:
	if is_on_floor():
		velocity.x = signf(direction.x) * sqrt(2.0 * FRICTION * distance)


func knock_small(direction: Vector2) -> void:
	velocity = Vector2(signf(direction.x) * 25.0, 360.0 if direction == Vector2.DOWN else -50.0)


## A hit lands on it: kinds call off what they were winding up.
func on_flinch() -> void:
	pass


func _die() -> void:
	dead = true
	active = false
	# Off the attack layer, still on the floor.
	collision_layer = 0
	defeated.emit(self)


# --- motion --------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var scale := world_scale()
	var step := delta * scale
	clock += step
	flinch_left = maxf(0.0, flinch_left - step)
	air_hold_left = maxf(0.0, air_hold_left - step)
	flash_left = maxf(0.0, flash_left - delta)
	slash_flash_left = maxf(0.0, slash_flash_left - delta)
	if moved_by_attack():
		queue_redraw()
		glow.queue_redraw()
		return
	if not is_on_floor() or velocity.y < 0.0:
		velocity.y = 6.0 if air_hold_left > 0.0 else velocity.y + GRAVITY * step
	else:
		velocity.y = 0.0
	if can_act():
		think(step)
	elif is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * step)
	# move_and_slide integrates over the physics delta: scale the speed for the world clock, keep what the
	# collisions left of it.
	if scale > 0.0:
		velocity *= scale
		move_and_slide()
		velocity /= scale
	queue_redraw()
	glow.queue_redraw()


## Whether an attack moves the body this frame instead of physics (the guard's lunge).
func moved_by_attack() -> bool:
	return false


## An active body's decision for this frame: set velocity.x (and anything of its own).
func think(_step: float) -> void:
	velocity.x = 0.0


## Steps toward or away from the hero at speed; stops at a wall.
func walk(direction: float, speed: float) -> void:
	velocity.x = direction * speed
	if direction != 0.0 and test_move(global_transform, Vector2(direction * 2.0, 0)):
		velocity.x = 0.0


func blocked(direction: float, distance := 6.0) -> bool:
	return test_move(global_transform, Vector2(direction * distance, 0))


# --- drawing -----------------------------------------------------------------------------------

## The pose to draw now; kinds add theirs.
func pose() -> String:
	if dead:
		return "dead"
	if not is_on_floor() and (flinch_left > 0.0 or velocity.y < -40.0 or air_hold_left > 0.0):
		return "tumble"
	if flinch_left > 0.0:
		return "flinch"
	if absf(velocity.x) > 4.0:
		return "walk_a" if int(clock / 0.16) % 2 == 0 else "walk_b"
	return "stand"


## Rectangles [x, y, w, h, colour] of a pose facing right, feet at (0, 0).
func figure(_pose: String) -> Array:
	return []


## What glows, facing right: [x, y, w, h, colour] rectangles.
func glow_figure(_pose: String) -> Array:
	return []


## Lines and flashes drawn in world space by the kinds (laser sight); facing already applied.
func draw_glow_extra(_canvas: Node2D) -> void:
	pass


func _draw() -> void:
	draw_set_transform(global_position.round() - global_position)
	var current := pose()
	var rects := figure(current)
	var shiver := shiver_offset(current)
	for item in rects:
		if item[4] != BLOOD:
			draw_rect(_mirrored(item, shiver, 1), OUTLINE)
	for item in rects:
		var colour: Color = item[4]
		draw_rect(_mirrored(item, shiver, 0), FLASH if flash_left > 0.0 and colour != BLOOD else colour)
	if slash_flash_left > 0.0:
		for step in range(13):
			var x := -6 + step if last_hit_direction.x >= 0.0 else 6 - step
			draw_rect(Rect2(x + 1, -23 + step, 1, 1), SLASH)
			draw_rect(Rect2(x, -23 + step, 1, 1), SLASH_CORE if slash_flash_left > 0.035 else SLASH)


func _draw_glow_layer() -> void:
	glow.draw_set_transform(global_position.round() - global_position)
	var current := pose()
	var shiver := shiver_offset(current)
	if flash_left <= 0.0:
		for item in glow_figure(current):
			glow.draw_rect(_mirrored(item, shiver, 0), item[4])
	draw_glow_extra(glow)


## A pixel of shaking for frightened poses.
func shiver_offset(_pose: String) -> int:
	return 0


func _mirrored(item: Array, shift: int, grow: int) -> Rect2:
	var x := float(item[0])
	var width := float(item[2])
	if facing < 0.0:
		x = -x - width
	return Rect2(x + shift - grow, float(item[1]) - grow, width + grow * 2, float(item[3]) + grow * 2)


## A body lying on the floor, head toward where it faced, and a dark pool (shared by every kind).
func lying(top: Color, bottom: Color, head: Color, hair: Color) -> Array:
	return [[-13, -4, 9, 3, bottom], [-5, -5, 10, 5, top], [5, -5, 4, 4, head], [7, -6, 3, 2, hair],
		[-11, -1, 6, 1, BLOOD], [-4, 0, 12, 1, BLOOD]]


## Legs for a pose, facing right: stand, walk_a / walk_b (stride / passing), lunge, kneel, crouch.
static func legs(mode: String, pants: Color, shoes: Color) -> Array:
	match mode:
		"walk_a", "lunge":
			var reach := 3 if mode == "lunge" else 2
			return [[-5, -11, 3, 9, pants], [reach, -11, 3, 9, pants], [-6, -2, 4, 2, shoes], [reach, -2, 4, 2, shoes]]
		"walk_b":
			return [[-2, -11, 3, 9, pants], [0, -11, 3, 9, pants], [-2, -2, 4, 2, shoes], [0, -2, 4, 2, shoes]]
		"kneel":
			# Knees on the floor, shins folded back under the body.
			return [[-4, -7, 3, 4, pants], [0, -7, 4, 4, pants], [-7, -3, 7, 3, pants], [-9, -2, 3, 2, shoes]]
		"crouch":
			return [[-5, -6, 4, 4, pants], [1, -6, 4, 4, pants], [-6, -2, 5, 2, shoes], [1, -2, 5, 2, shoes]]
	return [[-3, -11, 3, 9, pants], [1, -11, 3, 9, pants], [-4, -2, 4, 2, shoes], [1, -2, 4, 2, shoes]]


## Rectangles moved by (dx, dy): an upper body leaning or sinking with the legs.
static func shifted(items: Array, dx: int, dy: int) -> Array:
	var result: Array = []
	for item in items:
		result.append([item[0] + dx, item[1] + dy, item[2], item[3], item[4]])
	return result


## A body in the air after a launch: stretched out, head trailing back.
static func tumbling(top: Color, bottom: Color, head: Color, hair: Color) -> Array:
	return [[-6, -18, 9, 6, top], [3, -17, 8, 4, bottom], [10, -16, 3, 3, bottom], [-11, -20, 5, 5, head],
		[-12, -21, 4, 2, hair], [-4, -13, 2, 4, top]]
