extends Node2D
## Placeholder for a seated assassination target in the top-down hospital (chapter 1: Coburn at his office
## desk), drawn on the native grid until the real sprite exists. position is the feet; facing is where he
## looks, so "behind" is the opposite side. A small static body keeps the hero from walking through him.

const LEVEL_KIT = preload("res://scripts/levels/level_kit.gd")
const HAIR := Color("1d1a1c")
const SKIN := Color("8b6a5e")
const COAT := Color("b9c6c9")
const COAT_SHADE := Color("7d8c92")
const OUTLINE := Color("0c1216")
const BLOOD := Color("4a0f18")

var facing := Vector2.DOWN
var dead := false


func setup(world: Node, feet: Vector2) -> void:
	position = feet
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(self)
	LEVEL_KIT.add_box(world, Rect2(feet + Vector2(-6, -14), Vector2(12, 14)), "StoryTargetBody")


## The hero is behind when the target's own facing points away from them.
func is_behind(point: Vector2) -> bool:
	return (point - position).dot(facing) < -4.0


func kill() -> void:
	dead = true
	queue_redraw()


func _draw() -> void:
	if dead:
		# Slumped forward onto the desk.
		draw_rect(Rect2(-7, -13, 14, 10), OUTLINE)
		draw_rect(Rect2(-6, -12, 12, 8), COAT_SHADE)
		draw_rect(Rect2(-6, -12, 12, 3), COAT)
		draw_rect(Rect2(-4, -5, 8, 6), OUTLINE)
		draw_rect(Rect2(-3, -4, 6, 4), HAIR)
		draw_rect(Rect2(-5, 1, 9, 2), BLOOD)
		draw_rect(Rect2(3, 3, 3, 1), BLOOD)
		return
	# Seated, facing the door: hair and face, white coat over the chair back, arms reaching to the desk.
	draw_rect(Rect2(-5, -23, 10, 9), OUTLINE)
	draw_rect(Rect2(-4, -22, 8, 7), HAIR)
	draw_rect(Rect2(-3, -18, 6, 3), SKIN)
	draw_rect(Rect2(-7, -15, 14, 13), OUTLINE)
	draw_rect(Rect2(-6, -14, 12, 11), COAT)
	draw_rect(Rect2(-6, -6, 12, 3), COAT_SHADE)
	draw_rect(Rect2(-1, -14, 2, 6), COAT_SHADE)
	draw_rect(Rect2(-8, -9, 2, 8), COAT_SHADE)
	draw_rect(Rect2(6, -9, 2, 8), COAT_SHADE)
	draw_rect(Rect2(-8, -1, 2, 1), SKIN)
	draw_rect(Rect2(6, -1, 2, 1), SKIN)
