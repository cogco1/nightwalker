extends Panel
## Shared reading box for story interactions: the approved 80% panel with the 12px pixel font and the 48x64
## protagonist portrait, paged and typed out per scene (page_characters, type_speed). While open it freezes
## the player and registers with GameSession as a story modal, so Esc closes it instead of opening settings.
## Owners add it to a CanvasLayer, call setup(), open() / advance() / close(), and connect finished to their
## own close so scene state (hints, current interaction) is cleaned up when the last page is read.

signal finished
## Every close, by the last page or by Esc; story sequences wait on it.
signal closed

const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const GAME_SESSION = preload("res://scripts/core/game_session.gd")

var page_characters := 32
var type_speed := 36.0
var active := false
var pages: Array[String] = []
var page_speakers: Array[String] = []
var page_bold: Array[bool] = []
var page_index := 0
var context_title := ""
var portrait: TextureRect
var title: Label
var body: Label
var footer: Label
var _typing_clock := 0.0
var _frozen_player: WeakRef
var _session: WeakRef


## Call once after adding the box to a CanvasLayer. colors: background, border, title, footer.
func setup(location: Vector2, colors: Dictionary, characters_per_page: int, characters_per_second: float) -> void:
	page_characters = characters_per_page
	type_speed = characters_per_second
	position = location
	size = Vector2(284, 72)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = colors["background"]
	style.border_color = colors["border"]
	style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)
	PIXEL_UI.shrink_dialogue(self)
	portrait = PIXEL_UI.add_portrait(self)
	title = PIXEL_UI.label(self, Vector2(60, 2), Vector2(218, 16), "", PIXEL_UI.FONT_SIZE, true)
	title.modulate = colors["title"]
	body = PIXEL_UI.label(self, Vector2(60, 20), Vector2(218, 32), "", PIXEL_UI.FONT_SIZE, true)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.clip_text = true
	footer = PIXEL_UI.label(self, Vector2(60, 54), Vector2(218, 16), "", PIXEL_UI.FONT_SIZE, true)
	footer.modulate = colors["footer"]
	hide()


## lines are split into pages of page_characters; speakers[i] names line i's speaker, default_speaker the rest.
## A line wrapped in ** (the script's "加粗") is typed in bold.
func open(lines: Array, context: String, player: CharacterBody2D, speakers: Array = [], default_speaker := "protagonist") -> void:
	pages.clear()
	page_speakers.clear()
	page_bold.clear()
	for line_index in range(lines.size()):
		var speaker := String(speakers[line_index]) if line_index < speakers.size() else default_speaker
		var remaining := String(lines[line_index])
		var bold := remaining.length() > 4 and remaining.begins_with("**") and remaining.ends_with("**")
		if bold:
			remaining = remaining.substr(2, remaining.length() - 4)
		while remaining.length() > page_characters:
			pages.append(remaining.substr(0, page_characters))
			page_speakers.append(speaker)
			page_bold.append(bold)
			remaining = remaining.substr(page_characters)
		if not remaining.is_empty():
			pages.append(remaining)
			page_speakers.append(speaker)
			page_bold.append(bold)
	if pages.is_empty():
		pages.append("……")
		page_speakers.append(default_speaker)
		page_bold.append(false)
	page_index = 0
	context_title = context
	active = true
	if is_instance_valid(player):
		player.freeze(self)
		_frozen_player = weakref(player)
	var session := GAME_SESSION.of(self)
	if session != null:
		session.push_modal(self)
		_session = weakref(session)
	show()
	_show_page()


## E or a click: finish typing the page, else turn to the next one; after the last page the box closes.
func advance() -> void:
	if not active:
		return
	if body.visible_characters >= 0 and body.visible_characters < body.text.length():
		_typing_clock = body.text.length() / type_speed + 1.0
		body.visible_characters = -1
		return
	page_index += 1
	if page_index >= pages.size():
		close()
		finished.emit()
	else:
		_show_page()


func close() -> void:
	var was_active := active
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
	if was_active:
		closed.emit()


func _process(delta: float) -> void:
	if active:
		_typing_clock += delta
		body.visible_characters = mini(int(_typing_clock * type_speed), body.text.length())


func _exit_tree() -> void:
	if active:
		close()


func _show_page() -> void:
	PIXEL_UI.set_speaker(portrait, title, body, footer, page_speakers[page_index], context_title)
	body.text = pages[page_index]
	# Bold: a 1px outline in the text's own colour thickens every stroke on the pixel grid.
	body.add_theme_constant_override("outline_size", 1 if page_bold[page_index] else 0)
	body.add_theme_color_override("font_outline_color", body.get_theme_color("font_color"))
	body.visible_characters = 0
	_typing_clock = 0.0
	footer.text = "%s继续  Esc关闭  %d/%d" % [CONTROLS.interact_text(), page_index + 1, pages.size()]
