extends Node
## The hero's health plate for chapter nights, in the "冷光终端" style and in the exposure plate's slot at the top
## right (stealth and fights never share a screen): "生命" and a 50px bar. The bar is off-white, magenta at 30% or
## less; a hit leaves a red trail that drains after a moment and rings the plate red; overheal (the vodka's
## temporary hit points) is an amber strip over the top of the bar. The host calls build(canvas) and bind(vitals).

const STYLE = preload("res://scripts/ui/hud_style.gd")
const VIEWPORT_WIDTH := 320.0
const BAR_WIDTH := 50
const BAR_HEIGHT := 5
const LOW := 0.3
## A hit's red trail waits this long, then drains at TRAIL_SPEED of the bar per second.
const TRAIL_HOLD := 0.35
const TRAIL_SPEED := 0.9
const HIT_RING_SECONDS := 0.3

var vitals: RefCounted
var plate: Panel
var label: Label
var bar: Node2D
## Fraction of the bar the red trail still shows (>= the hp fraction).
var trail := 1.0
var _trail_wait := 0.0
var _ring_left := 0.0
var _clock := 0.0
var _plate_style: StyleBoxFlat


func build(canvas: CanvasLayer) -> void:
	_plate_style = STYLE.plate()
	plate = STYLE.panel(canvas, "HealthPlate", _plate_style)
	var label_width := STYLE.width("生命")
	plate.size = Vector2(4 + label_width + 5 + BAR_WIDTH + 5, 13)
	plate.position = Vector2(VIEWPORT_WIDTH - 4.0 - plate.size.x, 4)
	label = STYLE.small(plate, Vector2(4, 0), "生命", STYLE.MUTED)
	bar = Node2D.new()
	bar.name = "HealthBar"
	bar.position = Vector2(4 + label_width + 5, 4)
	plate.add_child(bar)
	bar.draw.connect(_draw_bar)
	plate.hide()


func bind(next: RefCounted) -> void:
	vitals = next
	trail = vitals.ratio()
	vitals.changed.connect(_on_changed)
	bar.queue_redraw()


func set_visible(shown: bool) -> void:
	plate.visible = shown


func _on_changed() -> void:
	if vitals.ratio() < trail:
		_trail_wait = TRAIL_HOLD
		_ring_left = HIT_RING_SECONDS
	else:
		trail = vitals.ratio()
	bar.queue_redraw()


func _process(delta: float) -> void:
	if vitals == null or not plate.visible:
		return
	_clock += delta
	if _trail_wait > 0.0:
		_trail_wait -= delta
	elif trail > vitals.ratio():
		trail = maxf(vitals.ratio(), trail - TRAIL_SPEED * delta)
	_ring_left = maxf(0.0, _ring_left - delta)
	var low: bool = vitals.ratio() <= LOW
	_plate_style.border_color = STYLE.RED
	_plate_style.set_border_width_all(1 if _ring_left > 0.0 else 0)
	label.modulate = STYLE.MAGENTA if low and fmod(_clock, 0.8) < 0.5 else STYLE.MUTED
	bar.queue_redraw()


## Pixels of the bar a fraction fills; any hp left shows at least one column.
static func columns(fraction: float) -> int:
	if fraction <= 0.0:
		return 0
	return clampi(int(roundf(fraction * BAR_WIDTH)), 1, BAR_WIDTH)


func _draw_bar() -> void:
	if vitals == null:
		return
	var fill := columns(vitals.ratio())
	var lost := columns(trail)
	bar.draw_rect(Rect2(0, 0, BAR_WIDTH, BAR_HEIGHT), STYLE.CYAN_DIM)
	if lost > fill:
		bar.draw_rect(Rect2(fill, 0, lost - fill, BAR_HEIGHT), STYLE.RED)
	var colour: Color = STYLE.MAGENTA if vitals.ratio() <= LOW else STYLE.TEXT
	bar.draw_rect(Rect2(0, 0, fill, BAR_HEIGHT), colour)
	if vitals.overheal > 0:
		var extra := columns(float(vitals.overheal) / float(vitals.max_hp))
		bar.draw_rect(Rect2(0, 0, extra, 2), STYLE.AMBER)
