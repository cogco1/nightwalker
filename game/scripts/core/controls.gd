extends RefCounted

const SETTINGS_PATH := "user://keybindings.cfg"
const SLOTS := ["move_up", "move_down", "move_left", "move_right", "run", "jump", "crouch", "rising_modifier", "dash_modifier", "attack_mouse", "heavy_mouse", "switch_view", "reset_arena"]
## Slots bound to a mouse button rather than a key.
const MOUSE_SLOTS := ["attack_mouse", "heavy_mouse"]
const LABELS := {
	"move_up": "俯视上移", "move_down": "俯视下移", "move_left": "左移 / 突刺", "move_right": "右移 / 突刺",
	"run": "按住跑步", "jump": "跳跃 / 二段跳", "crouch": "下蹲 / 下劈", "rising_modifier": "上挑修饰键",
	"dash_modifier": "突刺键",
	"attack_mouse": "攻击鼠标键", "heavy_mouse": "重击鼠标键", "switch_view": "切换视角", "reset_arena": "重置位置",
}
const MOUSE_BUTTONS := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]
## E inspects, talks, uses stairs and opens keypads in every scene. It is reserved: no rebindable action may use it.
const INTERACT_KEY := KEY_E
# Free keys offered when a saved action has to move (dash off run, any action off E), in this order.
const SPARE_KEYS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_F, KEY_Q, KEY_L, KEY_K]

static var settings_path := SETTINGS_PATH
static var current: Dictionary = {}
static var load_notice := ""


static func defaults() -> Dictionary:
	return {
		"move_up": KEY_W, "move_down": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"run": KEY_CAPSLOCK, "jump": KEY_SPACE, "crouch": KEY_S, "rising_modifier": KEY_W,
		"dash_modifier": KEY_SHIFT,
		"attack_mouse": MOUSE_BUTTON_LEFT, "heavy_mouse": MOUSE_BUTTON_RIGHT, "switch_view": KEY_TAB, "reset_arena": KEY_R,
	}


static func install(load_saved: bool = true) -> void:
	if current.is_empty():
		current = defaults()
		if load_saved:
			_load_saved()
	_apply()


static func _load_saved() -> void:
	load_notice = ""
	if not FileAccess.file_exists(settings_path):
		return
	var config := ConfigFile.new()
	if config.load(settings_path) != OK or config.get_value("bindings", "version", 0) not in [1, 2, 3]:
		load_notice = "设置文件无法读取，已使用默认按键。"
		return
	var profile: Dictionary = {}
	for slot in SLOTS:
		if slot == "dash_modifier" and not config.has_section_key("bindings", slot):
			profile[slot] = KEY_SHIFT
			continue
		if slot == "heavy_mouse" and not config.has_section_key("bindings", slot):
			profile[slot] = -1
			continue
		if not config.has_section_key("bindings", slot):
			load_notice = "设置文件不完整，已使用默认按键。"
			return
		profile[slot] = config.get_value("bindings", slot)
	var notices: Array[String] = []
	if profile["dash_modifier"] == profile["run"]:
		# The dash key used to be a modifier that could share run's key; it is now a press of its own.
		profile["dash_modifier"] = _free_key(profile, "dash_modifier")
		notices.append("突刺键改成单按触发，已从跑步键移到「%s」。" % binding_text("dash_modifier", profile))
	for slot in SLOTS:
		# Older menus allowed E; it is now the reserved interaction key.
		if slot not in MOUSE_SLOTS and profile[slot] == INTERACT_KEY:
			profile[slot] = _free_key(profile, slot)
			notices.append("E 键留给交互，「%s」已移到「%s」。" % [LABELS[slot], binding_text(slot, profile)])
	if profile["heavy_mouse"] == -1:
		# Saved before the heavy attack existed: right button, or the first mouse button attack leaves free.
		for button in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2, MOUSE_BUTTON_LEFT]:
			if button != profile["attack_mouse"]:
				profile["heavy_mouse"] = button
				break
		notices.append("新增重击，鼠标键为「%s」。" % binding_text("heavy_mouse", profile))
	load_notice = " ".join(notices)
	if not validate(profile).is_empty():
		load_notice = "设置文件无效，已使用默认按键。"
		return
	current = profile


static func _free_key(profile: Dictionary, moving_slot: String) -> int:
	var used: Array = []
	for slot in SLOTS:
		if slot != moving_slot and slot not in MOUSE_SLOTS:
			used.append(profile[slot])
	for code in SPARE_KEYS:
		if code not in used:
			return code
	return KEY_SHIFT


static func _valid_key(code: int) -> bool:
	if code == KEY_ESCAPE or code == KEY_F1:
		return false
	if code >= KEY_SPACE and code <= KEY_ASCIITILDE:
		return true
	if code >= KEY_F2 and code <= KEY_F35:
		return true
	if code >= KEY_KP_MULTIPLY and code <= KEY_KP_9:
		return true
	return code in [KEY_TAB, KEY_BACKSPACE, KEY_ENTER, KEY_KP_ENTER, KEY_INSERT, KEY_DELETE,
		KEY_PAUSE, KEY_PRINT, KEY_HOME, KEY_END, KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN,
		KEY_PAGEUP, KEY_PAGEDOWN, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]


static func validate(profile: Dictionary) -> String:
	if profile.size() != SLOTS.size():
		return "按键设置不完整。"
	for slot in SLOTS:
		if not profile.has(slot) or typeof(profile[slot]) != TYPE_INT:
			return "按键设置无效。"
		var code: int = profile[slot]
		if slot in MOUSE_SLOTS:
			if code not in MOUSE_BUTTONS:
				return "请选择鼠标左键、右键、中键或侧键。"
		elif code == KEY_ESCAPE or code == KEY_F1:
			return "Esc 和 F1 保留用于打开 / 关闭改键界面。"
		elif code == INTERACT_KEY:
			return "E 保留用于交互（调查、对话、楼梯、密码门）。"
		elif not _valid_key(code):
			return "这个按键暂不支持，请换一个键。"
	if profile["attack_mouse"] == profile["heavy_mouse"]:
		return "与「%s」/「%s」冲突，请换一个键。" % [LABELS["attack_mouse"], LABELS["heavy_mouse"]]
	for left in range(SLOTS.size()):
		for right in range(left + 1, SLOTS.size()):
			var a: String = SLOTS[left]
			var b: String = SLOTS[right]
			if a in MOUSE_SLOTS or b in MOUSE_SLOTS or profile[a] != profile[b]:
				continue
			# Cross-view pairs may share a key; the dash key is a press of its own and cannot share with run.
			if [a, b] in [["move_up", "rising_modifier"], ["move_down", "crouch"]]:
				continue
			return "与「%s」/「%s」冲突，请换一个键。" % [LABELS[a], LABELS[b]]
	return ""


static func save_bindings(profile: Dictionary) -> String:
	var error := validate(profile)
	if not error.is_empty():
		return error
	var config := ConfigFile.new()
	config.set_value("bindings", "version", 3)
	for slot in SLOTS:
		config.set_value("bindings", slot, profile[slot])
	var temp_path := settings_path + ".tmp"
	if config.save(temp_path) != OK:
		return "保存失败，请检查设置目录是否可写。"
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(settings_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return "保存失败，原来的按键设置仍然保留。"
	current = profile.duplicate()
	load_notice = ""
	_apply()
	return ""


static func release_actions() -> void:
	for slot in SLOTS:
		Input.action_release(action_for(slot))


static func action_for(slot: String) -> StringName:
	return &"attack" if slot.begins_with("attack_") else StringName(slot)


static func _apply() -> void:
	for slot in SLOTS:
		var action := action_for(slot)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		Input.action_release(action)
		InputMap.action_erase_events(action)
	for slot in SLOTS:
		var event: InputEvent
		if slot in MOUSE_SLOTS:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = current[slot]
			event = mouse
		else:
			var key := InputEventKey.new()
			key.physical_keycode = current[slot]
			event = key
		InputMap.action_add_event(action_for(slot), event)


static func binding_pressed(slot: String) -> bool:
	if slot in MOUSE_SLOTS:
		return Input.is_mouse_button_pressed(current[slot])
	return Input.is_physical_key_pressed(current[slot])


static func is_interact(event: InputEvent) -> bool:
	return event is InputEventKey and (event.physical_keycode == INTERACT_KEY or event.keycode == INTERACT_KEY)


static func interact_text() -> String:
	return OS.get_keycode_string(INTERACT_KEY)


## Key name for the on-screen scene hints: binding_text, except that Space and the mouse buttons read in Chinese
## there (空格, 左键, 右键 ...).
static func hint_text(slot: String) -> String:
	if slot in MOUSE_SLOTS:
		match int(current[slot]):
			MOUSE_BUTTON_LEFT: return "左键"
			MOUSE_BUTTON_RIGHT: return "右键"
			MOUSE_BUTTON_MIDDLE: return "中键"
			MOUSE_BUTTON_XBUTTON1: return "侧键1"
			MOUSE_BUTTON_XBUTTON2: return "侧键2"
	elif int(current[slot]) == KEY_SPACE:
		return "空格"
	return binding_text(slot)


static func binding_text(slot: String, profile: Dictionary = {}) -> String:
	var bindings := current if profile.is_empty() else profile
	if slot in MOUSE_SLOTS:
		match int(bindings[slot]):
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_XBUTTON1: return "Mouse4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse5"
	var code: int = bindings[slot]
	match code:
		KEY_CAPSLOCK: return "Caps"
		KEY_SPACE: return "Space"
		KEY_CTRL: return "Ctrl"
		KEY_PAGEUP: return "PgUp"
		KEY_PAGEDOWN: return "PgDn"
		KEY_BACKSPACE: return "Bksp"
	return OS.get_keycode_string(code)
