extends Node
## Surveillance HUD of the night street, in the "冷光终端" style: a plate at the top
## right with "暴露" and ten cells (cyan, magenta from 70%, red when marked), and while the light is on the hero
## a small scan tag whose magnified serial never resolves ("ID 无法识别"). The tag sits above the head, or under
## the feet when the status plate is in the way. The host calls build(canvas) once and update() every frame.

const STYLE = preload("res://scripts/ui/hud_style.gd")
const SCAN_BARS := [2, 1, 1, 3, 1, 2, 1, 1, 2, 3, 1, 1, 2, 1]
const VIEWPORT_SIZE := Vector2(320, 180)
const CELLS := 10
## Lowest screen y the tag may take above the head without covering the status plate.
const TAG_TOP := 34.0

var exposure := 0.0
var marked := false
var scanning := false
## The hero's feet in screen pixels.
var hero_screen := Vector2.ZERO
var plate: Panel
var meter: Node2D
var scan: Node2D
var scan_label: Label
var meter_label: Label
var marked_text := "已标记"
var _clock := 0.0


func build(canvas: CanvasLayer) -> void:
	plate = STYLE.panel(canvas, "ExposurePlate", STYLE.plate())
	var label_width := STYLE.width("暴露")
	plate.size = Vector2(4 + label_width + 5 + CELLS * 4 - 1 + 5, 13)
	plate.position = Vector2(VIEWPORT_SIZE.x - 4.0 - plate.size.x, 4)
	meter_label = STYLE.small(plate, Vector2(4, 0), "暴露", STYLE.MUTED)
	meter = Node2D.new()
	meter.name = "ExposureMeter"
	meter.position = Vector2(4 + label_width + 5, 5)
	plate.add_child(meter)
	meter.draw.connect(_draw_meter)
	scan = Node2D.new()
	scan.name = "ScanReadout"
	canvas.add_child(scan)
	scan.draw.connect(_draw_scan)
	scan_label = STYLE.small(canvas, Vector2.ZERO, "", STYLE.CYAN)
	scan_label.visible = false


func update(delta: float, level: float, is_marked: bool, in_light: bool, feet_on_screen: Vector2) -> void:
	_clock += delta
	exposure = level
	marked = is_marked
	scanning = in_light
	hero_screen = feet_on_screen
	meter.queue_redraw()
	scan.queue_redraw()
	scan_label.visible = scanning
	if scanning:
		var panel := scan_panel()
		scan_label.text = marked_text if marked else ("ID 无法识别" if fmod(_clock, 0.6) < 0.45 else "ID ？？？？")
		scan_label.modulate = STYLE.RED if marked else STYLE.CYAN
		scan_label.position = panel.position + Vector2(5, 7)


func set_visible(shown: bool) -> void:
	plate.visible = shown
	scan.visible = shown
	scan_label.visible = shown and scanning


func _draw_meter() -> void:
	var colour := STYLE.RED if marked else STYLE.MAGENTA if exposure >= 0.7 else STYLE.CYAN
	var lit := int(ceilf(exposure * CELLS - 0.001))
	for index in range(CELLS):
		var on := index < lit and not (marked and fmod(_clock, 0.5) > 0.3)
		meter.draw_rect(Rect2(Vector2(index * 4, 0), Vector2(3, 4)), colour if on else STYLE.CYAN_DIM)


## The tag above the head, or under the feet when that would cover the status plate.
func scan_panel() -> Rect2:
	var size := Vector2(STYLE.width("ID 无法识别") + 10, 19)
	var feet := hero_screen.round()
	var top := feet.y - 34.0 - size.y - 1.0
	if top < TAG_TOP:
		top = minf(feet.y + 4.0, VIEWPORT_SIZE.y - 18.0 - size.y)
	var left := clampf(feet.x - roundf(size.x * 0.5), 2.0, VIEWPORT_SIZE.x - 2.0 - size.x)
	return Rect2(Vector2(left, top), size)


func _draw_scan() -> void:
	if not scanning:
		return
	var panel := scan_panel()
	var colour := STYLE.RED if marked else STYLE.CYAN
	scan.draw_rect(panel, Color(0.016, 0.031, 0.055, 0.84))
	scan.draw_rect(panel, colour, false)
	# magnified serial: a scratched-out band shifts every tick, so it never reads
	var bars_width := 0
	for width in SCAN_BARS:
		bars_width += width
	var x := panel.position.x + floorf((panel.size.x - bars_width) * 0.5)
	var top := panel.position.y + 2.0
	var glitch := int(_clock * 9.0)
	var bar_index := 0
	for width in SCAN_BARS:
		var scratched := (bar_index + glitch) % 5 < 2
		if bar_index % 2 == 0:
			scan.draw_rect(Rect2(Vector2(x, top), Vector2(width, 4)), Color("6a2032") if scratched else colour)
		x += width
		bar_index += 1
