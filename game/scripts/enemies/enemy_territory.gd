extends RefCounted
## Shared enemy pursuit policy. Anchor is fixed at spawn; returning and hard motion limits never contain attacks.
## Future enemy AIs use this component for pursuit. Drone self-destruction stays in cannon_drone.gd.
var anchor := Vector2.ZERO
var radius := 240.0
var body_margin := 12.0
var target_inside := false

func _init(origin := Vector2.ZERO, extent := 240.0, margin := 12.0) -> void:
	anchor=origin
	radius=maxf(margin+1.0,extent)
	body_margin=maxf(0.0,margin)

func update_target(point: Vector2) -> bool:
	target_inside=anchor.distance_to(point)<=radius
	return target_inside

func bounded_goal(point: Vector2) -> Vector2:
	return anchor+(point-anchor).limit_length(radius-body_margin)

func bounded_motion(from: Vector2, motion: Vector2) -> Vector2:
	return bounded_goal(from+motion)-from

func inside_body(point: Vector2) -> bool:
	return anchor.distance_to(point)<=radius-body_margin+0.01

func return_goal() -> Vector2:
	return anchor
