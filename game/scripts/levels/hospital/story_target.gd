extends Node2D
## Coburn's seated office sprite. All poses share a native canvas and sole
## baseline. SK specifies his age and job; appearance is a visual adaptation.

const LEVEL_KIT = preload("res://scripts/levels/level_kit.gd")
const IDLE_TEXTURES := [
	preload("res://assets/npcs/coburn/idle_00.png"),
	preload("res://assets/npcs/coburn/idle_01.png"),
]
const COLLAPSE_TEXTURE = preload("res://assets/npcs/coburn/collapse_00.png")
const DEAD_TEXTURE = preload("res://assets/npcs/coburn/dead_00.png")
const FOOT_ANCHOR := Vector2(24, 40)

var facing := Vector2.DOWN
var dead := false
var sprite: AnimatedSprite2D
var body: StaticBody2D


func setup(world: Node, feet: Vector2) -> void:
	position = feet
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(self)
	# Same world-space bounds as the placeholder. Ownership lets execution sight
	# checks exclude the target's own collider without changing room geometry.
	body = LEVEL_KIT.add_box(self, Rect2(-6, -14, 12, 14), "StoryTargetBody")
	sprite = AnimatedSprite2D.new()
	sprite.name = "CoburnSprite"
	sprite.centered = false
	sprite.offset = -FOOT_ANCHOR
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 1.5)
	for texture in IDLE_TEXTURES:
		frames.add_frame("idle", texture)
	frames.add_animation("dead")
	frames.set_animation_loop("dead", false)
	frames.set_animation_speed("dead", 8.0)
	frames.add_frame("dead", COLLAPSE_TEXTURE)
	frames.add_frame("dead", DEAD_TEXTURE)
	sprite.sprite_frames = frames
	add_child(sprite)
	sprite.play("dead" if dead else "idle")
	if dead:
		sprite.pause()
		sprite.set_frame_and_progress(1, 0.0)


## The hero is behind when the target's own facing points away from them.
func is_behind(point: Vector2) -> bool:
	return (point - position).dot(facing) < -4.0


func kill(immediate := false) -> void:
	if dead and not immediate:
		return
	dead = true
	if is_instance_valid(sprite):
		sprite.play("dead")
		if immediate:
			sprite.pause()
			sprite.set_frame_and_progress(1, 0.0)
