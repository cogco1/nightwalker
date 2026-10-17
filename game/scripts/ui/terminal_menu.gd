extends Panel
## The dark-web terminal on the safehouse computer, in the black-market magenta of the "冷光终端" UI: a magenta
## frame, a 10px header with the clock on the right, 12px rows with the selected one on a dark magenta bar, an
## optional 10px note right-aligned per row (shop prices) and a magenta dot for unread entries. While open it
## freezes the player and holds a GameSession modal like the reading box. The owner feeds key events to
## handle_input(); up / down (bound movement keys or arrows) move, E or Enter chooses, Esc goes back.

signal chosen(index: int)
signal cancelled

const STYLE = preload("res://scripts/ui/hud_style.gd")
const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const GAME_SESSION = preload("res://scripts/core/game_session.gd")
const ROWS := 4
const ROW_TOP := 19.0
const ROW_STEP := 16.0

var active := false
## Row labels, notes and unread dots of the open page.
var options: Array[String] = []
var notes: Array[String] = []
var badges: Array[bool] = []
var selected := 0
var title: Label
var corner: Label
var footer: Label
var _bar: ColorRect
var _rows: Array[Label] = []
var _row_notes: Array[Label] = []
var _row_marks: Array[Label] = []
var _row_dots: Array[Label] = []
var _first := 0
var _frozen_player: WeakRef
var _session: WeakRef


func setup(location: Vector2) -> void:
	position = location
	size = Vector2(204, 100)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", STYLE.plate(STYLE.INK_SOLID, STYLE.MAGENTA))
	title = STYLE.small(self, Vector2(6, 2), "", STYLE.MAGENTA)
	corner = STYLE.small(self, Vector2(6, 2), "", STYLE.MUTED)
	var rule := ColorRect.new()
	rule.color = STYLE.MAGENTA_DARK
	rule.position = Vector2(1, 14)
	rule.size = Vector2(size.x - 2, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)
	_bar = ColorRect.new()
	_bar.color = STYLE.MAGENTA_DARK
	_bar.size = Vector2(size.x - 4, 15)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	for row in range(ROWS):
		var y := ROW_TOP + row * ROW_STEP
		_row_marks.append(PIXEL_UI.label(self, Vector2(7, y), Vector2.ZERO, "", PIXEL_UI.FONT_SIZE, true))
		_rows.append(PIXEL_UI.label(self, Vector2(19, y), Vector2.ZERO, "", PIXEL_UI.FONT_SIZE, true))
		_row_dots.append(STYLE.small(self, Vector2(0, y + 1), "●", STYLE.MAGENTA))
		_row_notes.append(STYLE.small(self, Vector2(0, y + 1), "", STYLE.MUTED))
	footer = STYLE.small(self, Vector2(6, 86), "", STYLE.MUTED)
	hide()


## entries: Strings, or Dictionaries {label, note (10px, right-aligned), badge (unread dot)}.
func open(heading: String, entries: Array, player: CharacterBody2D, start := 0, clock := "") -> void:
	options.clear()
	notes.clear()
	badges.clear()
	for entry in entries:
		var row: Dictionary = entry if entry is Dictionary else {"label": String(entry)}
		options.append(String(row.get("label", "")))
		notes.append(String(row.get("note", "")))
		badges.append(bool(row.get("badge", false)))
	selected = clampi(start, 0, maxi(0, options.size() - 1))
	_first = 0
	title.text = heading
	corner.text = clock
	corner.position.x = size.x - 6 - STYLE.width(clock)
	footer.text = "%s/%s 选择 · %s 确定 · Esc 返回" % [CONTROLS.hint_text("move_up"), CONTROLS.hint_text("move_down"),
		CONTROLS.interact_text()]
	if not active:
		active = true
		if is_instance_valid(player):
			player.freeze(self)
			_frozen_player = weakref(player)
		var session := GAME_SESSION.of(self)
		if session != null:
			session.push_modal(self)
			_session = weakref(session)
	show()
	_redraw_rows()


func close() -> void:
	if not active:
		return
	active = false
	if _frozen_player != null:
		var player: Variant = _frozen_player.get_ref()
		if is_instance_valid(player):
			player.unfreeze(self)
		_frozen_player = null
	if _session != null:
		var session: Variant = _session.get_ref()
		if is_instance_valid(session):
			session.pop_modal(self)
		_session = null
	hide()


## Returns true when the event belonged to the menu.
func handle_input(event: InputEvent) -> bool:
	if not active or not event is InputEventKey or not event.pressed or event.echo:
		return false
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if event.is_action_pressed("move_up") or code == KEY_UP:
		move(-1)
	elif event.is_action_pressed("move_down") or code == KEY_DOWN:
		move(1)
	elif CONTROLS.is_interact(event) or code in [KEY_ENTER, KEY_KP_ENTER]:
		chosen.emit(selected)
	elif code == KEY_ESCAPE:
		cancelled.emit()
	return true


func move(step: int) -> void:
	if options.is_empty():
		return
	selected = wrapi(selected + step, 0, options.size())
	_redraw_rows()


func _redraw_rows() -> void:
	if selected < _first:
		_first = selected
	elif selected >= _first + ROWS:
		_first = selected - ROWS + 1
	_bar.position = Vector2(2, ROW_TOP - 1 + (selected - _first) * ROW_STEP)
	for row in range(ROWS):
		var index := _first + row
		var shown := index < options.size()
		var chosen_row := index == selected
		_rows[row].text = options[index] if shown else ""
		_rows[row].modulate = STYLE.TEXT if chosen_row else STYLE.MUTED
		_row_marks[row].text = "▸" if shown and chosen_row else ""
		_row_marks[row].modulate = STYLE.MAGENTA
		_row_dots[row].visible = shown and badges[index]
		_row_dots[row].position.x = 19 + STYLE.width(_rows[row].text, PIXEL_UI.FONT_SIZE) + 4
		_row_notes[row].text = notes[index] if shown else ""
		_row_notes[row].position.x = size.x - 6 - STYLE.width(_row_notes[row].text)


func _exit_tree() -> void:
	close()
