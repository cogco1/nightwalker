extends Node
## The chapter HUD in the "冷光终端" style: a status plate at the top left (place, clock, ▸ goal), the interaction
## key cap at the bottom centre, tips as toasts just above it, and the control hints at the bottom left for a
## few seconds after the opening or after the key bindings change. Levels feed it their state; it has no logic.

const STYLE = preload("res://scripts/ui/hud_style.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const VIEWPORT_WIDTH := 320.0
const PROMPT_Y := 148.0
const TOAST_Y := 131.0
const HINTS_Y := 165.0
const HINT_SECONDS := 6.0
const TOAST_SECONDS := 4.0
const RECEIPT_SECONDS := 4.0
const FADE_SECONDS := 0.5

var status: Panel
var place_label: Label
var clock_label: Label
var goal_label: Label
var balance_panel: Panel
var balance_label: Label
var balance_change_label: Label
var prompt: Panel
var key_cap: ColorRect
var key_label: Label
var prompt_label: Label
var toast_panel: Panel
var toast_line: ColorRect
var toast_label: Label
var hints_panel: Panel
var hints_label: Label
var _toast_left := 0.0
var _hints_left := 0.0
var _receipt_left := 0.0


func build(canvas: CanvasLayer) -> void:
	status = STYLE.panel(canvas, "StatusPlate", STYLE.plate(STYLE.INK, Color.TRANSPARENT, STYLE.CYAN))
	status.position = Vector2(4, 4)
	place_label = STYLE.small(status, Vector2(6, 1), "", STYLE.TEXT)
	clock_label = STYLE.small(status, Vector2(6, 1), "", STYLE.MUTED)
	goal_label = STYLE.small(status, Vector2(6, 13), "", STYLE.AMBER)
	balance_panel = STYLE.panel(canvas, "AccountPlate", STYLE.plate())
	balance_label = STYLE.small(balance_panel, Vector2(6, 1), "", STYLE.MUTED)
	balance_change_label = STYLE.small(balance_panel, Vector2.ZERO, "", STYLE.AMBER)
	balance_change_label.hide()
	balance_panel.hide()
	prompt = STYLE.panel(canvas, "PromptChip", STYLE.plate())
	key_cap = ColorRect.new()
	key_cap.color = STYLE.TEXT
	key_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_child(key_cap)
	# The 10px face sits 4px down its line box: lift the letter 2px so it centres in the 11px cap.
	key_label = STYLE.small(key_cap, Vector2(3, -2), "", STYLE.INK_SOLID)
	prompt_label = STYLE.small(prompt, Vector2.ZERO, "", STYLE.TEXT)
	prompt.hide()
	toast_panel = STYLE.panel(canvas, "Toast", STYLE.plate())
	toast_line = ColorRect.new()
	toast_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_child(toast_line)
	toast_label = STYLE.small(toast_panel, Vector2(6, 1), "", STYLE.CYAN)
	toast_panel.hide()
	hints_panel = STYLE.panel(canvas, "ControlHints", STYLE.plate(Color(STYLE.INK, 0.6)))
	hints_panel.position = Vector2(4, HINTS_Y)
	hints_label = STYLE.small(hints_panel, Vector2(5, 1), "", STYLE.MUTED)
	hints_panel.hide()


## Place and clock on the first line, "▸ goal" in amber under them; the plate fits its text.
func set_status(place: String, clock: String, goal: String) -> void:
	place_label.text = place
	clock_label.text = clock
	clock_label.position.x = 6 + STYLE.width(place) + 6
	goal_label.text = "" if goal.is_empty() else "▸ " + goal
	var wide := maxi(STYLE.width(place) + 6 + STYLE.width(clock), STYLE.width(goal_label.text))
	status.size = Vector2(wide + 12, 27 if not goal.is_empty() else 15)
	balance_panel.position = Vector2(4, status.position.y + status.size.y + 3)


## The safehouse account. Existing chapter HUDs keep this hidden until a balance is supplied.
## A positive change is a one-off receipt; ordinary refreshes update the total without restarting it.
func set_balance(amount: int, change := 0) -> void:
	if amount < 0:
		balance_panel.hide()
		return
	balance_label.text = "账户 ￥%d" % amount
	if change > 0:
		balance_change_label.text = "+%d 已到账" % change
		balance_change_label.modulate.a = 1.0
		balance_change_label.show()
		_receipt_left = RECEIPT_SECONDS
	_layout_balance()
	balance_panel.show()


func _layout_balance() -> void:
	var wide := STYLE.width(balance_label.text) + 12
	if balance_change_label.visible:
		balance_change_label.position = Vector2(wide + 2, 1)
		wide += STYLE.width(balance_change_label.text) + 8
	balance_panel.size = Vector2(wide, 14)


## The key cap for what E would do here; an empty label hides it.
func set_prompt(label: String, key := "") -> void:
	if label.is_empty():
		prompt.hide()
		return
	var cap := key if not key.is_empty() else CONTROLS.interact_text()
	key_label.text = cap
	prompt_label.text = label
	var cap_width := STYLE.width(cap) + 5
	key_cap.position = Vector2(3, 2)
	key_cap.size = Vector2(cap_width, 11)
	prompt_label.position = Vector2(3 + cap_width + 4, 1)
	var wide := 3 + cap_width + 4 + STYLE.width(label) + 5
	prompt.size = Vector2(wide, 14)
	prompt.position = Vector2(roundf((VIEWPORT_WIDTH - wide) * 0.5), PROMPT_Y)
	prompt.show()


## A tip over the key cap for a few seconds, with a coloured rule on top.
func toast(text: String, colour := STYLE.CYAN, seconds := TOAST_SECONDS) -> void:
	toast_label.text = text
	toast_label.modulate = colour
	toast_line.color = colour
	var wide := STYLE.width(text) + 12
	toast_panel.size = Vector2(wide, 14)
	toast_panel.position = Vector2(roundf((VIEWPORT_WIDTH - wide) * 0.5), TOAST_Y)
	toast_line.size = Vector2(wide, 1)
	toast_panel.modulate.a = 1.0
	toast_panel.show()
	_toast_left = seconds


## The control hints for a while: after the opening, after the key bindings change.
func show_hints(text: String, seconds := HINT_SECONDS) -> void:
	hints_label.text = text
	hints_panel.size = Vector2(STYLE.width(text) + 10, 14)
	hints_panel.modulate.a = 1.0
	hints_panel.show()
	_hints_left = seconds


## "WASD 移动  Caps 跑  E 交互  F1 按键" from the current bindings.
static func controls_text() -> String:
	return "%s%s%s%s 移动  %s 跑  %s 交互  F1 按键" % [CONTROLS.hint_text("move_up"), CONTROLS.hint_text("move_left"),
		CONTROLS.hint_text("move_down"), CONTROLS.hint_text("move_right"), CONTROLS.hint_text("run"), CONTROLS.interact_text()]


func _process(delta: float) -> void:
	_toast_left = _fade(toast_panel, _toast_left, delta)
	_hints_left = _fade(hints_panel, _hints_left, delta)
	if balance_change_label.visible:
		_receipt_left = _fade(balance_change_label, _receipt_left, delta)
		if not balance_change_label.visible:
			_layout_balance()


func _fade(item: CanvasItem, left: float, delta: float) -> float:
	if not item.visible:
		return 0.0
	left -= delta
	item.modulate.a = clampf(left / FADE_SECONDS, 0.0, 1.0)
	if left <= 0.0:
		item.hide()
	return left
