extends RefCounted
## Optional preserved v1 thrust-contact assets. Damage is owned by the caller; this function only draws.
## Default moveset: dash_stab.hit_feedback=false. Future code may explicitly call emit_visual and play HIT_SOUND.
const HIT_SOUND = preload("res://assets/audio/sfx/hit_light.wav")
const SHADER = preload("res://shaders/impact_frame.gdshader")

static func emit_visual(player: CharacterBody2D, point: Vector2) -> void:
	player.fx.sparks(point)
	player.fx.legacy_impact(point, &"light", player.attack_direction, player.global_position)
