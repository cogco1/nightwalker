extends Node2D
## Shared visible projectiles. Only sniper/cannon rounds push; rifle/shotgun rounds never do.
## Swept collision resolves against the first wall or hero, including at low frame rates.
enum Weapon { SNIPER, DRONE_CANNON, RIFLE, SHOTGUN }
const PROFILES := {
	Weapon.SNIPER: {"speed":280.0, "range":460.0, "damage":18, "push":18.0, "trail":26.0},
	Weapon.DRONE_CANNON: {"speed":230.0, "range":460.0, "damage":20, "push":22.0, "trail":30.0},
	Weapon.RIFLE: {"speed":310.0, "range":400.0, "damage":10, "push":0.0, "trail":16.0},
	Weapon.SHOTGUN: {"speed":250.0, "range":150.0, "damage":6, "push":0.0, "trail":12.0},
}
var source: Node2D
var hero: CharacterBody2D
var heading := Vector2.RIGHT
var weapon := Weapon.SNIPER
var damage := 18
var knockback := 18.0
var speed := 280.0
var max_range := 460.0
var trail_length := 26.0
var travelled := 0.0
var resolved := false
var result := -1
var spent := false
var spark_left := 0.0
var _previous_side := 0.0
var _spawn := Vector2.ZERO

func setup(owner_body: Node2D, target: CharacterBody2D, start: Vector2, direction: Vector2, type := Weapon.SNIPER) -> void:
	source=owner_body
	hero=target
	position=start
	_spawn=start
	heading=direction.normalized() if direction.length_squared()>0.0 else Vector2.RIGHT
	weapon=type
	var profile: Dictionary=PROFILES[type]
	speed=profile.speed
	max_range=profile.range
	damage=profile.damage
	knockback=profile.push
	trail_length=profile.trail

func _ready() -> void:
	add_to_group(&"ballistic_rounds")
	z_index=5
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material=unshaded
	_previous_side=(hero.hurtbox().get_center()-global_position).dot(heading) if is_instance_valid(hero) else 0.0

func world_scale() -> float:
	var session := get_tree().get_first_node_in_group(&"game_session")
	return float(session.world_time_scale) if session!=null else 1.0

## Returns nearest contact fraction [0,1], or INF. Also used to clip the aiming laser.
static func box_contact(from: Vector2, to: Vector2, box: Rect2) -> float:
	if box.has_point(from):
		return 0.0
	var best := INF
	var corners := [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]
	var length := from.distance_to(to)
	if length<0.0001:
		return best
	for index in range(4):
		var point: Variant=Geometry2D.segment_intersects_segment(from,to,corners[index],corners[(index+1)%4])
		if point!=null:
			best=minf(best,from.distance_to(point)/length)
	return best

func _physics_process(delta: float) -> void:
	var step := delta*world_scale()
	if is_instance_valid(source) and bool(source.get("held")):
		return
	if spent:
		spark_left-=step
		if spark_left<=0.0:
			queue_free()
		queue_redraw()
		return
	var advance := minf(speed*step,max_range-travelled)
	if advance<=0.0:
		return
	var previous := global_position
	var next := previous+heading*advance
	var wall := get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(previous,next,1))
	var wall_t := previous.distance_to(wall.position)/advance if not wall.is_empty() else INF
	var hit_t := INF
	if not resolved and is_instance_valid(hero):
		hit_t=box_contact(previous,next,hero.hurtbox().grow(1.0))
	if hit_t<wall_t:
		global_position=previous.lerp(next,hit_t)
		_resolve(true)
		if spent:
			travelled+=advance*hit_t
			queue_redraw()
			return
	if wall_t<=1.0:
		global_position=wall.position
		travelled+=advance*wall_t
		_stop()
	else:
		global_position=next
		travelled+=advance
		if not resolved and is_instance_valid(hero):
			var center: Vector2=hero.hurtbox().get_center()
			var side := (center-next).dot(heading)
			var line_distance := absf((center-next).cross(heading))
			if _previous_side>0.0 and side<=0.0 and line_distance<32.0:
				_resolve(false)
			_previous_side=side
		if travelled>=max_range:
			_stop()
	queue_redraw()

func _resolve(contact: bool) -> void:
	resolved=true
	var owner_body: Node2D=source if is_instance_valid(source) else null
	result=int(hero.receive_attack({"source":owner_body,"direction":heading,"contact":contact,
		"window_age":0.0,"knockback":knockback,"damage":damage,"weapon":weapon}))
	if contact and result==0: # Player.AttackResult.HIT
		_stop()

func _stop() -> void:
	spent=true
	spark_left=0.12

func _draw() -> void:
	draw_set_transform(global_position.round()-global_position)
	var tail := minf(trail_length,travelled)
	if spent:
		var perpendicular := Vector2(-heading.y,heading.x)
		for side in [-1,1]:
			draw_line(Vector2.ZERO,(-heading*4.0+perpendicular*side*3.0).round(),Color("ffd679"),1.0,false)
		draw_rect(Rect2(-1,-1,3,3),Color("fff8d4"))
		return
	# Dim wide halo, saturated orange tracer, bright short core; visible over dark and light backgrounds.
	draw_line((-heading*tail).round(),Vector2.ZERO,Color(1.0,0.29,0.04,0.25),5.0,false)
	draw_line((-heading*tail).round(),Vector2.ZERO,Color("ed7626"),2.0,false)
	draw_line((-heading*minf(tail,9.0)).round(),(heading*2.0).round(),Color("fff7ce"),2.0,false)
	draw_rect(Rect2(Vector2(-1,-1),Vector2(3,3)),Color("ffe89a"))
	if weapon==Weapon.DRONE_CANNON:
		draw_line((-heading*minf(tail,6.0)).round(),Vector2.ZERO,Color("ffffff"),2.0,false)
