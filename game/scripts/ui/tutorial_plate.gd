extends Node
## The night's fight lessons as key icons only (the script: "全程无字幕"), in the "冷光终端" style: an ink plate
## above the key-cap slot with a cyan rule, five step squares on the left (done cyan, current amber, to come dim)
## and the current lesson's icons: key caps named from the current bindings, a mouse with the button to press lit,
## a red "!" for an enemy's warning, chevrons for "then", and pips that fill as the lesson is met. A finished
## lesson flashes a tick before the next one. The night (night_fight.gd) decides when lessons are met; this draws.
## Also draws the two icons the night puts in the world: the mouse over the kneeling last doctor and the edge
## chevron that points the way.

const STYLE = preload("res://scripts/ui/hud_style.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const VIEWPORT_SIZE := Vector2(320, 180)
const PLATE_Y := 129.0
const PLATE_HEIGHT := 17.0
const GAP := 4.0
const TICK_SECONDS := 0.6
## Icons of each lesson: key:<slot> is a key cap, mouse:<slot> the mouse with that slot's button lit, warn the red
## "!", then a chevron, pips:<n> the progress pips.
const LESSONS := {
	"move": ["key:move_left", "key:move_right"],
	"light": ["mouse:attack_mouse", "pips:3"],
	"heavy": ["mouse:attack_mouse", "then", "mouse:heavy_mouse", "pips:1"],
	"dodge": ["warn", "then", "key:dash_modifier", "pips:1"],
	"perfect": ["warn:ring", "then", "key:dash_modifier", "then", "mouse:attack_mouse", "pips:1"],
}

var plate: Panel
var rule: ColorRect
var steps: Node2D
var row: Control
var tick: Node2D
var lesson := ""
var lesson_index := -1
var lesson_count := 5
var progress := 0
var needed := 1
## What the current row shows, in order (tests read it): key:<name>, mouse:<left|right|...>, warn, then, pips:<n>.
var icons: Array[String] = []
var _clock := 0.0
var _tick_left := 0.0
var _hide_after_tick := false
var _drawers: Array[Node2D] = []


func build(canvas: CanvasLayer) -> void:
	plate = STYLE.panel(canvas, "TutorialPlate", STYLE.plate())
	plate.position.y = PLATE_Y
	rule = ColorRect.new()
	rule.color = STYLE.CYAN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(rule)
	steps = Node2D.new()
	steps.name = "Steps"
	steps.position = Vector2(5, 7)
	plate.add_child(steps)
	steps.draw.connect(_draw_steps)
	row = Control.new()
	row.name = "Icons"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	tick = Node2D.new()
	tick.name = "Tick"
	plate.add_child(tick)
	tick.draw.connect(_draw_tick)
	plate.hide()


## Shows lesson `id` as step index of count, with its pips empty.
func show_lesson(id: String, index: int, count: int) -> void:
	lesson = id
	lesson_index = index
	lesson_count = count
	progress = 0
	_tick_left = 0.0
	_hide_after_tick = false
	for child in row.get_children():
		child.queue_free()
	_drawers.clear()
	icons.clear()
	var x := 0.0
	for spec: String in LESSONS.get(id, []):
		var width := _add_icon(spec, x)
		x += width + GAP
	x -= GAP
	row.position = Vector2(5 + count * 4 + 4, 3)
	var wide := row.position.x + x + 4 + 7 + 5
	tick.position = Vector2(wide - 12, 4)
	plate.size = Vector2(wide, PLATE_HEIGHT)
	plate.position.x = roundf((VIEWPORT_SIZE.x - wide) * 0.5)
	rule.size = Vector2(wide, 1)
	rule.color = STYLE.CYAN
	plate.modulate.a = 1.0
	plate.show()
	steps.queue_redraw()


## The key bindings changed: the same lesson, its caps renamed, its pips and tick kept.
func relabel() -> void:
	if lesson.is_empty():
		return
	var kept := [progress, _tick_left, _hide_after_tick, rule.color]
	show_lesson(lesson, lesson_index, lesson_count)
	progress = kept[0]
	_tick_left = kept[1]
	_hide_after_tick = kept[2]
	rule.color = kept[3]
	_redraw()


func set_progress(count: int) -> void:
	progress = clampi(count, 0, needed)
	_redraw()


## The lesson is met: a tick for a moment (then the next lesson, or the plate goes when it was the last).
func complete(last_one: bool) -> void:
	progress = needed
	_tick_left = TICK_SECONDS
	_hide_after_tick = last_one
	rule.color = STYLE.TEXT
	_redraw()


func ticking() -> bool:
	return _tick_left > 0.0


func hide_plate() -> void:
	plate.hide()
	lesson = ""


func _process(delta: float) -> void:
	if not plate.visible:
		return
	_clock += delta
	if _tick_left > 0.0:
		_tick_left -= delta
		if _tick_left <= 0.0 and _hide_after_tick:
			hide_plate()
	_redraw()


func _redraw() -> void:
	steps.queue_redraw()
	tick.queue_redraw()
	for drawer in _drawers:
		drawer.queue_redraw()


## Adds one icon at x on the row; returns its width.
func _add_icon(spec: String, x: float) -> float:
	var parts := spec.split(":")
	match parts[0]:
		"key":
			var text := CONTROLS.binding_text(parts[1])
			icons.append("key:" + text)
			return key_cap(row, Vector2(x, 0), text)
		"mouse":
			icons.append("mouse:" + _button_name(parts[1]))
			_drawer(x, func(canvas: Node2D) -> void: draw_mouse(canvas, Vector2.ZERO, button_of(parts[1]), _blink()))
			return 7.0
		"warn":
			var ring := parts.size() > 1
			icons.append("warn")
			_drawer(x, func(canvas: Node2D) -> void: _draw_warn(canvas, ring))
			return 9.0
		"then":
			icons.append("then")
			_drawer(x, func(canvas: Node2D) -> void: draw_chevron(canvas, Vector2(0, 3), 1.0, STYLE.MUTED))
			return 3.0
		"pips":
			needed = int(parts[1])
			icons.append(spec)
			_drawer(x, _draw_pips)
			return needed * 5.0 - 1.0
	return 0.0


func _drawer(x: float, painter: Callable) -> void:
	var drawer := Node2D.new()
	drawer.position = Vector2(x, 0)
	row.add_child(drawer)
	drawer.draw.connect(painter.bind(drawer))
	_drawers.append(drawer)


func _blink() -> bool:
	return fmod(_clock, 0.5) < 0.3


## The mouse button bound to a slot.
static func button_of(slot: String) -> int:
	return int(CONTROLS.current.get(slot, MOUSE_BUTTON_LEFT))


static func _button_name(slot: String) -> String:
	match button_of(slot):
		MOUSE_BUTTON_LEFT: return "left"
		MOUSE_BUTTON_RIGHT: return "right"
		MOUSE_BUTTON_MIDDLE: return "middle"
	return "side"


# --- painters ------------------------------------------------------------------------------------

## A key cap like the HUD's interaction cap: off-white with ink letters, 11px high; returns its width.
static func key_cap(parent: Control, at: Vector2, text: String) -> float:
	var cap := ColorRect.new()
	cap.color = STYLE.TEXT
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.position = at
	cap.size = Vector2(STYLE.width(text) + 5, 11)
	parent.add_child(cap)
	STYLE.small(cap, Vector2(3, -2), text, STYLE.INK_SOLID)
	return cap.size.x


## A 7x11 mouse: outline, the lit button's half in cyan (dim when not blinking), the wheel between.
static func draw_mouse(canvas: Node2D, at: Vector2, button: int, lit: bool) -> void:
	var body := STYLE.TEXT
	canvas.draw_rect(Rect2(at + Vector2(1, 0), Vector2(5, 1)), body)
	canvas.draw_rect(Rect2(at + Vector2(0, 1), Vector2(1, 9)), body)
	canvas.draw_rect(Rect2(at + Vector2(6, 1), Vector2(1, 9)), body)
	canvas.draw_rect(Rect2(at + Vector2(1, 10), Vector2(5, 1)), body)
	canvas.draw_rect(Rect2(at + Vector2(1, 4), Vector2(5, 1)), body)
	canvas.draw_rect(Rect2(at + Vector2(3, 1), Vector2(1, 3)), body)
	var fill := STYLE.CYAN if lit else STYLE.CYAN_DIM
	match button:
		MOUSE_BUTTON_LEFT:
			canvas.draw_rect(Rect2(at + Vector2(1, 1), Vector2(2, 3)), fill)
		MOUSE_BUTTON_RIGHT:
			canvas.draw_rect(Rect2(at + Vector2(4, 1), Vector2(2, 3)), fill)
		_:
			canvas.draw_rect(Rect2(at + Vector2(3, 1), Vector2(1, 3)), fill)


## A small chevron pointing along `direction` (1 right, -1 left), 3 wide and 5 high.
static func draw_chevron(canvas: Node2D, at: Vector2, direction: float, colour: Color) -> void:
	for row_index in range(5):
		var depth := 2 - absi(row_index - 2)
		var x := depth if direction > 0.0 else 2 - depth
		canvas.draw_rect(Rect2(at + Vector2(x, row_index), Vector2.ONE), colour)


## A filled arrow head for the screen-edge pointer, 4 wide and 7 high.
static func draw_pointer(canvas: Node2D, at: Vector2, direction: float, colour: Color) -> void:
	for column in range(4):
		var x := column if direction > 0.0 else 3 - column
		canvas.draw_rect(Rect2(at + Vector2(x, column), Vector2(1, 7 - column * 2)), colour)


func _draw_warn(canvas: Node2D, ring: bool) -> void:
	var red := STYLE.RED if _blink() or ring else Color(STYLE.RED, 0.55)
	canvas.draw_rect(Rect2(3, 1, 3, 9), Color(STYLE.RED, 0.25))
	canvas.draw_rect(Rect2(4, 2, 1, 5), red)
	canvas.draw_rect(Rect2(4, 8, 1, 1), red)
	if ring:
		# A frame closing in on the "!" over 0.6 s: dodge as it closes, just before the blow.
		var shrink := int(fmod(_clock, 0.6) / 0.6 * 4.0)
		var frame := Rect2(shrink, shrink - 1, 9 - shrink * 2, 13 - shrink * 2)
		var colour := STYLE.TEXT if shrink >= 3 else STYLE.RED
		canvas.draw_rect(frame, colour, false)


func _draw_pips(canvas: Node2D) -> void:
	for index in range(needed):
		var box := Rect2(index * 5, 3, 4, 4)
		if index < progress:
			canvas.draw_rect(box, STYLE.CYAN)
		else:
			canvas.draw_rect(box, STYLE.CYAN_DIM, false)


func _draw_steps() -> void:
	for index in range(lesson_count):
		var colour := STYLE.CYAN_DIM
		if index < lesson_index or (index == lesson_index and _tick_left > 0.0):
			colour = STYLE.CYAN
		elif index == lesson_index:
			colour = STYLE.AMBER if _blink() else Color(STYLE.AMBER, 0.5)
		steps.draw_rect(Rect2(index * 4, 0, 3, 3), colour)


## The tick at the plate's right end while a met lesson shows.
func _draw_tick() -> void:
	if _tick_left <= 0.0:
		return
	for point in [Vector2(0, 3), Vector2(1, 4), Vector2(2, 5), Vector2(3, 4), Vector2(4, 3), Vector2(5, 2), Vector2(6, 1)]:
		tick.draw_rect(Rect2(point, Vector2(1, 2)), STYLE.CYAN)
