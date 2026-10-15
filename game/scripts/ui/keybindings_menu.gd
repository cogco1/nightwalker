extends CanvasLayer

signal closed(saved: bool)

const CONTROLS = preload("res://scripts/core/controls.gd")
var panel: Control
var status: Label
var header_hint: Label
var buttons: Dictionary = {}
var draft: Dictionary = {}
var waiting_slot := ""
var active := false


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	theme.default_font = font
	theme.default_font_size = 9
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("353442") if state == "normal" else Color("555067")
		style.border_color = Color("d7bd72") if state == "focus" else Color("82717c")
		style.set_border_width_all(1)
		style.content_margin_left = 2
		style.content_margin_right = 2
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		theme.set_stylebox(state, "Button", style)
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.theme = theme
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var background := ColorRect.new()
	background.color = Color("181923")
	background.size = Vector2(320, 180)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(background)
	label("按键设置", Vector2(10, 7), Vector2(90, 15), 12).modulate = Color("d7bd72")
	header_hint = label("Esc / F1 返回", Vector2(216, 8), Vector2(94, 13))
	header_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for index in range(CONTROLS.SLOTS.size()):
		var slot: String = CONTROLS.SLOTS[index]
		var x := 10 + floori(index / 6.0) * 156
		var y := 28 + (index % 6) * 17
		label(CONTROLS.LABELS[slot], Vector2(x, y), Vector2(82, 15))
		var button := make_button("", Vector2(x + 83, y), Vector2(61, 15))
		button.pressed.connect(begin_capture.bind(slot))
		buttons[slot] = button
	status = label("", Vector2(10, 131), Vector2(300, 23), 8)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	make_button("恢复默认", Vector2(10, 157), Vector2(83, 17)).pressed.connect(restore_defaults)
	make_button("取消", Vector2(103, 157), Vector2(68, 17)).pressed.connect(cancel)
	make_button("保存并返回", Vector2(181, 157), Vector2(129, 17)).pressed.connect(save_and_close)
	panel.hide()


func label(text: String, position: Vector2, size: Vector2, font_size: int = 9) -> Label:
	var result := Label.new()
	result.text = text
	result.position = position
	result.size = size
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", font_size)
	panel.add_child(result)
	return result


func make_button(text: String, position: Vector2, size: Vector2) -> Button:
	var result := Button.new()
	result.text = text
	result.position = position
	result.size = size
	result.add_theme_font_size_override("font_size", 9)
	result.add_theme_constant_override("outline_size", 0)
	panel.add_child(result)
	# Apply the final size after inheriting this panel's compact font and styles.
	result.size = size
	return result


func open() -> void:
	draft = CONTROLS.current.duplicate()
	active = true
	waiting_slot = ""
	panel.show()
	refresh()
	show_status(CONTROLS.load_notice if not CONTROLS.load_notice.is_empty() else "点击按键后录入单键；鼠标攻击可改为左 / 中 / 右 / 侧键。")
	buttons["move_up"].grab_focus()


func refresh() -> void:
	for slot in CONTROLS.SLOTS:
		buttons[slot].text = "请按键…" if slot == waiting_slot else CONTROLS.binding_text(slot, draft)
		buttons[slot].modulate = Color("d7bd72") if slot == waiting_slot else Color.WHITE
	header_hint.text = "Esc 取消录入" if not waiting_slot.is_empty() else "Esc / F1 返回"


func show_status(text: String, error: bool = false) -> void:
	status.text = text
	status.modulate = Color("ef9b93") if error else Color("c2c2d1")


func begin_capture(slot: String) -> void:
	waiting_slot = slot
	refresh()
	show_status("正在修改「%s」：%s；Esc 取消。" % [CONTROLS.LABELS[slot], "点击新鼠标键" if slot == "attack_mouse" else "按下新键"])


func _input(event: InputEvent) -> void:
	if not active:
		return
	if not waiting_slot.is_empty():
		get_viewport().set_input_as_handled()
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
				waiting_slot = ""
				refresh()
				show_status("已取消本次录入。")
			elif waiting_slot == "attack_mouse":
				show_status("这个项目需要点击鼠标键；Esc 取消。", true)
			else:
				var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
				if (event.ctrl_pressed and code != KEY_CTRL) or (event.alt_pressed and code != KEY_ALT) or (event.shift_pressed and code != KEY_SHIFT) or (event.meta_pressed and code != KEY_META):
					show_status("仅支持单键，请松开其他修饰键后再试。", true)
				else:
					capture(code)
		elif event is InputEventMouseButton and event.pressed:
			if waiting_slot == "attack_mouse":
				capture(event.button_index)
			else:
				show_status("这个项目需要键盘单键；Esc 取消。", true)
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode in [KEY_ESCAPE, KEY_F1] or event.physical_keycode in [KEY_ESCAPE, KEY_F1]):
		get_viewport().set_input_as_handled()
		cancel()


func capture(code: int) -> void:
	var candidate := draft.duplicate()
	candidate[waiting_slot] = code
	var error := CONTROLS.validate(candidate)
	if not error.is_empty():
		show_status(error, true)
		return
	draft = candidate
	waiting_slot = ""
	refresh()
	show_status("已录入，点击「保存并返回」生效。")


func restore_defaults() -> void:
	draft = CONTROLS.defaults()
	waiting_slot = ""
	refresh()
	show_status("已恢复默认草稿，点击「保存并返回」生效。")


func save_and_close() -> void:
	if not waiting_slot.is_empty():
		show_status("请先完成录入，或按 Esc 取消录入。", true)
		return
	var error := CONTROLS.save_bindings(draft)
	if not error.is_empty():
		show_status(error, true)
		return
	finish(true)


func cancel() -> void:
	finish(false)


func finish(saved: bool) -> void:
	active = false
	waiting_slot = ""
	panel.hide()
	closed.emit(saved)
