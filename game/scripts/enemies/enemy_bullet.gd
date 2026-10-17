extends Node2D
## A gunner's bullet (gunner.gd): flies level at chest height on the world clock and resolves against the hero
## once, like an EnemyAttacker hit window. Touching the hurtbox is a contact; passing the hero's body line without
## touching it (jumped over, ducked under, dashed through) reports contact = false. The window opens as it reaches
## the hero, so a dash started at most the hero's PERFECT_LEAD_SECONDS before is a perfect dodge, and the counter
## blinks the hero to the gunner (attack.source). A wall or the end of its range stops it; a hit stops it in the body.

const SPEED := 250.0
const RANGE := 420.0
## A pass this close above or below the hurtbox still counts as dodged (it reports contact = false).
const NEAR_MISS := 24.0
const CORE := Color("fff4d6")
const TRAIL := Color("ff9d4a")
const SPARK := Color("ffd37a")

var source: Node2D
var hero: CharacterBody2D
var heading := 1.0
var damage := 15
var knockback := 14.0
var resolved := false
## The hero's AttackResult, or -1 before it resolves.
var result := -1
var travelled := 0.0
var spent := false
var _spark_left := 0.0
## Which side of the bullet the hero's body line was on last frame (1: still ahead).
var _hero_side := 0.0


func setup(from_body: Node2D, target: CharacterBody2D, start: Vector2, direction: float, hit_points: int) -> void:
	source = from_body
	hero = target
	position = start
	heading = signf(direction) if direction != 0.0 else 1.0
	damage = hit_points


func _ready() -> void:
	name = "Bullet"
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded
	_hero_side = _side()


func world_scale() -> float:
	var session := get_tree().get_first_node_in_group(&"game_session")
	return float(session.world_time_scale) if session != null else 1.0


func _side() -> float:
	return signf((hero.hurtbox().get_center().x - global_position.x) * heading) if is_instance_valid(hero) else 0.0


func _physics_process(delta: float) -> void:
	if spent:
		_spark_left -= delta
		queue_redraw()
		if _spark_left <= 0.0:
			queue_free()
		return
	var advance := heading * SPEED * delta * world_scale()
	var previous := global_position
	var next := previous + Vector2(advance, 0)
	var ray := PhysicsRayQueryParameters2D.create(previous, next + Vector2(heading, 0), 1)
	var wall := get_world_2d().direct_space_state.intersect_ray(ray)
	if not wall.is_empty():
		next = Vector2(wall["position"].x - heading, previous.y)
	if not resolved and is_instance_valid(hero):
		_check(previous, next)
	if spent:
		return
	global_position = next
	travelled += absf(advance)
	if not wall.is_empty() or travelled >= RANGE:
		_stop()
	queue_redraw()


func _check(previous: Vector2, next: Vector2) -> void:
	var box: Rect2 = hero.hurtbox()
	var y := previous.y
	var low := minf(previous.x, next.x) - 1.0
	var high := maxf(previous.x, next.x) + 1.0
	if y >= box.position.y and y <= box.end.y and high >= box.position.x and low <= box.end.x:
		_resolve(true)
		return
	# The body line changed sides since last frame (the bullet passed it, or the hero dashed through the bullet).
	var side := signf((box.get_center().x - next.x) * heading)
	if _hero_side > 0.0 and side <= 0.0 and absf(y - box.get_center().y) <= box.size.y * 0.5 + NEAR_MISS:
		_resolve(false)
	_hero_side = side


func _resolve(contact: bool) -> void:
	resolved = true
	result = int(hero.call("receive_attack", {"source": source, "direction": Vector2(heading, 0), "contact": contact,
		"window_age": 0.0, "knockback": knockback, "damage": damage}))
	if contact and result == int(hero.AttackResult.HIT):
		_stop()


func _stop() -> void:
	spent = true
	_spark_left = 0.1
	queue_redraw()


func _draw() -> void:
	draw_set_transform(global_position.round() - global_position)
	if spent:
		for offset in [Vector2(-heading, -1), Vector2(-heading * 2, 1), Vector2(0, 0)]:
			draw_rect(Rect2(offset, Vector2.ONE), SPARK)
		return
	draw_rect(Rect2(Vector2(-heading * 6 if heading > 0 else 3, 0), Vector2(4, 1)), Color(TRAIL, 0.55))
	draw_rect(Rect2(Vector2(-1 if heading > 0 else 0, 0), Vector2(3, 1)), CORE)
