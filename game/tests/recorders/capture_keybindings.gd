extends "res://tests/support/isolated_suite.gd"

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
var arena: Node2D
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("capture")


func screenshot(filename: String) -> void:
	for _index in range(3):
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.get_size() != Vector2i(320, 180):
		failures.append("Unexpected native viewport size: " + str(image.get_size()))
	image.save_png("res://evidence/" + filename + ".png")
	image.resize(1280, 720, Image.INTERPOLATE_NEAREST)
	image.save_png("res://evidence/" + filename + "_4x.png")


func check_layout() -> void:
	for child in arena.keybindings_menu.panel.get_children():
		if child is Button and not Rect2(0, 0, 320, 180).encloses(child.get_global_rect()):
			failures.append("Menu button is outside viewport: " + child.text)
	for slot in CONTROLS.SLOTS:
		var button: Button = arena.keybindings_menu.buttons[slot]
		if not Rect2(0, 0, 320, 180).encloses(button.get_global_rect()):
			failures.append("Binding button is outside viewport: " + slot)
		if button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x > button.size.x - 4:
			failures.append("Binding text overflows: " + slot)
	if arena.controls_label.get_theme_font("font").get_multiline_string_size(arena.controls_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, arena.controls_label.get_theme_font_size("font_size")).x > 304:
		failures.append("HUD controls overflow viewport")


func capture() -> void:
	CONTROLS.install(false)
	arena = MAIN.instantiate()
	root.add_child(arena)
	await screenshot("gameplay_topdown")
	arena.open_keybindings()
	check_layout()
	await screenshot("keybindings_default")
	arena.keybindings_menu.begin_capture("move_left")
	arena.keybindings_menu.capture(KEY_D)
	await screenshot("keybindings_conflict")
	arena.keybindings_menu.capture(KEY_K)
	arena.keybindings_menu.begin_capture("attack_mouse")
	arena.keybindings_menu.capture(MOUSE_BUTTON_RIGHT)
	check_layout()
	await screenshot("keybindings_custom_draft")
	arena.keybindings_menu.cancel()
	arena.build_arena(1)
	await screenshot("gameplay_sideview")
	check_layout()
	var profile := CONTROLS.defaults()
	profile["move_up"] = KEY_UP
	profile["move_down"] = KEY_DOWN
	profile["move_left"] = KEY_LEFT
	profile["move_right"] = KEY_RIGHT
	profile["run"] = KEY_SHIFT
	profile["jump"] = KEY_I
	profile["crouch"] = KEY_C
	profile["rising_modifier"] = KEY_U
	profile["attack_mouse"] = MOUSE_BUTTON_RIGHT
	profile["switch_view"] = KEY_V
	profile["reset_arena"] = KEY_N
	CONTROLS.current = profile
	CONTROLS.install()
	arena._refresh_hud()
	await screenshot("gameplay_rebound")
	check_layout()
	arena.open_keybindings()
	check_layout()
	await screenshot("keybindings_rebound")
	var file := FileAccess.open("res://evidence/keybindings_visual_report.json", FileAccess.WRITE)
	var report := {"status": "passed" if failures.is_empty() else "failed", "failures": failures, "native_resolution": "320x180", "preview_resolution": "1280x720", "captures": 7}
	file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
