extends RefCounted
## "冷光终端" UI tokens (approved 2026-10-17): every HUD word sits on a half-transparent ink plate in the 10px
## pixel face; colours carry roles. Off-white text, blue-grey secondary, cyan for surveillance and the system
## (exposure, scan, tips), amber for the current goal, magenta for the black market and danger.

const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const INK := Color(0.035, 0.051, 0.075, 0.77)
const INK_SOLID := Color(0.047, 0.035, 0.071, 0.94)
const TEXT := Color("ccd8de")
const MUTED := Color("7a919d")
const CYAN := Color("4ff0ff")
const CYAN_DIM := Color("204652")
const AMBER := Color("f0a852")
const MAGENTA := Color("ff3d9a")
const MAGENTA_DARK := Color("420e2a")
const RED := Color("ff4f7e")


## A plate: ink fill, optionally a 1px border or a 2px accent bar on the left.
static func plate(fill := INK, border := Color.TRANSPARENT, accent := Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	if border.a > 0.0:
		style.border_color = border
		style.set_border_width_all(1)
	elif accent.a > 0.0:
		style.border_color = accent
		style.border_width_left = 2
	return style


static func panel(parent: Node, name: String, style: StyleBoxFlat) -> Panel:
	var result := Panel.new()
	result.name = name
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_stylebox_override("panel", style)
	parent.add_child(result)
	return result


## 10px HUD text.
static func small(parent: Node, location: Vector2, text: String, colour: Color) -> Label:
	var result := PIXEL_UI.label(parent, location, Vector2.ZERO, text, PIXEL_UI.SMALL_FONT_SIZE, true, PIXEL_UI.small_font())
	result.modulate = colour
	return result


static func width(text: String, size := PIXEL_UI.SMALL_FONT_SIZE) -> int:
	var face: Font = PIXEL_UI.small_font() if size == PIXEL_UI.SMALL_FONT_SIZE else PIXEL_UI.font()
	return int(ceilf(face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x))
