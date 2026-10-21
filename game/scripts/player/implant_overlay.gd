extends Node2D
## Barcode scar on the sword-hand forearm. SK.txt: the protagonist has no readable ID serial, so the
## tattoo is scratched out - broken bars that now and then flash red. Child of the player's Sprite; the
## per-frame forearm anchors come from tools/art/gen_implant_anchors.py, the frames themselves are untouched.
## Scenes that scan the hero set `scanned` (0..1) to make the scar glitch harder.

const ANCHORS_PATH := "res://assets/fx/implant_anchors.json"
const EMISSIVE = preload("res://shaders/emissive_add.gdshader")
const BARS := [1, 0, 1, 1]
const SCAR := Color("6a2032")
const SCAR_DARK := Color("2a0c16")
const FLARE := Color(1.0, 0.24, 0.43)

static var _anchors: Dictionary = {}

var scanned := 0.0
var hurt_shift := Vector2.ZERO
var _sprite: AnimatedSprite2D
var _flare_layer: Node2D
var _anchor: Variant = null
var _drawn_offset := Vector2.ZERO
var _drawn_hurt_shift := Vector2.ZERO
var _clock := 0.0


func _ready() -> void:
	_sprite = get_parent() as AnimatedSprite2D
	if _anchors.is_empty() and FileAccess.file_exists(ANCHORS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ANCHORS_PATH))
		if parsed is Dictionary:
			_anchors = parsed
	var glow := ShaderMaterial.new()
	glow.shader = EMISSIVE
	glow.set_shader_parameter("gain", 1.8)
	_flare_layer = Node2D.new()
	_flare_layer.name = "Flare"
	_flare_layer.material = glow
	add_child(_flare_layer)
	_flare_layer.draw.connect(_draw_flare)


func _process(delta: float) -> void:
	_clock += delta
	var anchor: Variant = null
	if _sprite != null and _sprite.sprite_frames != null and _visible_look():
		var texture := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
		if texture != null:
			anchor = _anchors.get(texture.resource_path)
	if anchor != _anchor or (_sprite != null and _sprite.offset != _drawn_offset) or hurt_shift != _drawn_hurt_shift:
		_anchor = anchor
		_drawn_offset = _sprite.offset if _sprite != null else Vector2.ZERO
		_drawn_hurt_shift = hurt_shift
		queue_redraw()
	_flare_layer.queue_redraw()


func _visible_look() -> bool:
	var shader_material := _sprite.material as ShaderMaterial
	return shader_material == null or float(shader_material.get_shader_parameter("look")) > 0.5


func _origin() -> Vector2:
	var point := Vector2(_anchor[0], _anchor[1])
	var weight := smoothstep(3.0, 26.0, -_sprite.offset.y - point.y)
	return _sprite.offset + point + (hurt_shift * weight).round() - Vector2(2, 1)


func _flaring() -> bool:
	# Idle: a short red flash every couple of seconds. Under a scanner: fails to read and stutters.
	var period := 0.35 if scanned > 0.5 else 2.3
	return fmod(_clock + 0.6, period) < (0.12 if scanned > 0.5 else 0.08)


func _draw() -> void:
	if _anchor == null:
		return
	var origin := _origin()
	for index in range(BARS.size()):
		draw_rect(Rect2(origin + Vector2(index, 0), Vector2(1, 2)), SCAR if BARS[index] == 1 else SCAR_DARK)


func _draw_flare() -> void:
	if _anchor == null or not _flaring():
		return
	var origin := _origin()
	for index in range(BARS.size()):
		if BARS[index] == 1:
			_flare_layer.draw_rect(Rect2(origin + Vector2(index, 0), Vector2(1, 2)), Color(FLARE, 0.85))
