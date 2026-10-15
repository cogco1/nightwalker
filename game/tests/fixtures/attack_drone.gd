extends CharacterBody2D
## Hovering practice drone that fights back (the training target never does): a small body with one eye, hit
## points, and an EnemyAttacker child that blinks red and lunges at the hero. The hero hits it like any target.
## Origin is the body centre.

const ATTACKER = preload("res://scripts/enemies/enemy_attacker.gd")

signal destroyed

@export var max_hp := 9

var hp := 9
var flash_left := 0.0
var attacker: Node
var body_shape: CollisionShape2D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	hp = max_hp
	body_shape = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 8)
	body_shape.shape = shape
	add_child(body_shape)
	attacker = ATTACKER.new()
	attacker.name = "Attacker"
	add_child(attacker)
	queue_redraw()


func damage_point() -> Vector2:
	return global_position


func take_damage(amount: int) -> bool:
	if hp <= 0 or amount <= 0:
		return false
	hp = maxi(0, hp - amount)
	flash_left = 0.10
	if hp == 0:
		attacker.reset()
		attacker.set_physics_process(false)
		body_shape.set_deferred("disabled", true)
		destroyed.emit()
	queue_redraw()
	return true


func receive_hit_reaction(_direction: Vector2, _strong: bool = false, _air_combo: bool = false) -> void:
	flash_left = 0.10


func _process(delta: float) -> void:
	flash_left = maxf(0.0, flash_left - delta)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(global_position.round() - global_position)
	if hp <= 0:
		draw_rect(Rect2(-5, -2, 10, 3), Color("44464c"))
		return
	var shell := Color("f0e8d8") if flash_left > 0.0 else Color("51454b")
	draw_rect(Rect2(-6, -4, 12, 8), shell)
	draw_rect(Rect2(-8, -5, 16, 1), Color("82717c"))
	var warning: bool = attacker.phase == attacker.Phase.TELEGRAPH or attacker.phase == attacker.Phase.LUNGE
	draw_rect(Rect2(-2, -1, 4, 3), Color("ef4a4a") if warning else Color("6fe3e8"))
