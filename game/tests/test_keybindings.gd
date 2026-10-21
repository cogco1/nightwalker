extends "res://tests/support/isolated_suite.gd"

const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const TEST_PATH := "user://keybindings_regression.cfg"
var arena: Node2D
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	create_timer(120.0, true).timeout.connect(func() -> void: quit(2))
	call_deferred("run_tests")


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)


func tick(count: int = 1) -> void:
	# Menu tests also run while the world is paused.
	for _index in range(count):
		await process_frame


func key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func mouse(button: MouseButton, pressed: bool, point: Vector2 = Vector2(160, 140)) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	mouse(MOUSE_BUTTON_LEFT, true, point)
	mouse(MOUSE_BUTTON_LEFT, false, point)
	await tick(2)


func tap(code: Key) -> void:
	key(code, true)
	await tick(1)
	key(code, false)
	await tick(1)


func release_inputs() -> void:
	for code in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_J, KEY_K, KEY_I, KEY_C, KEY_L, KEY_V, KEY_N, KEY_M, KEY_E, KEY_F, KEY_SHIFT, KEY_SPACE, KEY_R, KEY_TAB, KEY_F1, KEY_ESCAPE]:
		key(code, false)
	for button in CONTROLS.MOUSE_BUTTONS:
		mouse(button, false)
	CONTROLS.release_actions()


func fixture(mode: int = 0) -> void:
	release_inputs()
	arena.build_arena(mode)
	await tick(8)
	for target in arena.targets:
		target.position.x = 280
	arena.player.critical_roll_override = 0.99


func custom_profile() -> Dictionary:
	var result := CONTROLS.defaults()
	result["move_up"] = KEY_UP
	result["move_down"] = KEY_DOWN
	result["move_left"] = KEY_LEFT
	result["move_right"] = KEY_RIGHT
	result["run"] = KEY_SHIFT
	result["dash_modifier"] = KEY_L
	result["jump"] = KEY_I
	result["crouch"] = KEY_C
	result["rising_modifier"] = KEY_U
	result["attack_mouse"] = MOUSE_BUTTON_RIGHT
	result["heavy_mouse"] = MOUSE_BUTTON_MIDDLE
	result["switch_view"] = KEY_V
	result["reset_arena"] = KEY_N
	return result


func run_tests() -> void:
	CONTROLS.settings_path = TEST_PATH
	var reloaded := "--reload-profile" in OS.get_cmdline_user_args()
	if not reloaded:
		CONTROLS.install(false)
	arena = MAIN.instantiate()
	root.add_child(arena)
	await tick(8)
	if reloaded:
		check(CONTROLS.current == custom_profile(), "fresh engine process restores the saved custom profile")
		await gameplay_checks()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
		finish("keybindings_reload_report.json")
		return
	check(CONTROLS.current == CONTROLS.defaults(), "all default keys and mouse bindings are preserved")
	check(CONTROLS.validate(CONTROLS.defaults()).is_empty(), "default cross-view W/S sharing is allowed")
	await click(Vector2(214, 8))
	check(arena.settings_open and paused, "HUD button opens the settings and pauses the world")
	check(not arena.player._mouse_attack_pending and not arena.player.is_attacking, "clicking the HUD button does not attack")
	var menu: CanvasLayer = arena.keybindings_menu
	if not arena.settings_open:
		arena.open_keybindings()
	var start: Vector2 = arena.player.position
	var frame: int = arena.player.sprite.frame
	key(KEY_D, true)
	key(KEY_J, true)
	mouse(MOUSE_BUTTON_LEFT, true)
	await tick(8)
	check(arena.player.position == start and arena.player.sprite.frame == frame, "world and animation stay frozen while editing")
	check(not arena.player._mouse_attack_pending, "settings input never fills the attack buffer")
	release_inputs()
	await click(menu.buttons["move_left"].position + Vector2(20, 7))
	check(menu.waiting_slot == "move_left", "clicking a binding starts capture")
	await tap(KEY_D)
	check(menu.waiting_slot == "move_left" and menu.status.text.contains("冲突"), "conflicts are explained and the prior draft is retained")
	check(menu.draft["move_left"] == KEY_A, "conflicting assignment leaves the old key intact")
	await tap(KEY_F1)
	check(menu.waiting_slot == "move_left" and menu.status.text.contains("保留"), "F1 remains a reliable settings shortcut")
	await tap(KEY_E)
	check(menu.waiting_slot == "move_left" and menu.status.text.contains("E 保留") and menu.draft["move_left"] == KEY_A, "E stays reserved for interaction and cannot be captured")
	await tap(KEY_F)
	check(menu.waiting_slot.is_empty() and menu.draft["move_left"] == KEY_F, "F is an ordinary key since the top-down execution was removed")
	menu.begin_capture("move_left")
	await tap(KEY_K)
	check(menu.waiting_slot.is_empty() and menu.draft["move_left"] == KEY_K, "new physical keyboard key is captured")
	menu.begin_capture("jump")
	key(KEY_L, true, true)
	key(KEY_L, false)
	check(menu.waiting_slot == "jump", "keyboard auto-repeat cannot capture a new binding")
	await tap(KEY_ESCAPE)
	check(CONTROLS.current["move_left"] == KEY_A, "draft does not change live controls before save")
	menu.begin_capture("attack_mouse")
	mouse(MOUSE_BUTTON_WHEEL_UP, true)
	check(menu.waiting_slot == "attack_mouse", "wheel events cannot replace a held attack button")
	mouse(MOUSE_BUTTON_RIGHT, true)
	mouse(MOUSE_BUTTON_RIGHT, false)
	check(menu.draft["attack_mouse"] == MOUSE_BUTTON_RIGHT and menu.waiting_slot.is_empty(), "mouse attack button can be rebound")
	check(menu.draft["heavy_mouse"] == MOUSE_BUTTON_LEFT, "taking the heavy button swaps heavy onto the old attack button")
	menu.begin_capture("jump")
	await tap(KEY_ESCAPE)
	check(arena.settings_open and menu.waiting_slot.is_empty(), "Esc cancels capture while keeping the settings open")
	await tap(KEY_ESCAPE)
	check(not arena.settings_open and not paused and CONTROLS.current == CONTROLS.defaults(), "Esc discards draft edits and resumes gameplay")
	await tick(4)
	check(not arena.player.is_attacking and arena.player.position == start, "closing settings produces no stray attacks or movement")
	await tap(KEY_F1)
	check(arena.settings_open, "F1 opens settings from gameplay")
	menu.draft = custom_profile()
	menu.refresh()
	menu.save_and_close()
	check(not arena.settings_open and CONTROLS.current == custom_profile(), "save applies all custom bindings and closes settings")
	check(FileAccess.file_exists(TEST_PATH), "save writes the profile to persistent user storage")
	check(InputMap.action_get_events("attack").size() == 1, "only the mouse attack event remains")
	CONTROLS.install()
	check(InputMap.action_get_events("attack").size() == 1 and CONTROLS.current == custom_profile(), "reinstall is idempotent and retains custom controls")
	check(arena.controls_label.text.contains("RMB") and arena.controls_label.text.contains("V View"), "HUD shows the actual custom attack and view keys")
	await gameplay_checks()
	# The original hit-stop path forwards custom inputs while player processing is paused.
	await fixture(1)
	arena.player.position = Vector2(70, 160)
	arena.targets[0].position = Vector2(96, 160)
	arena.targets[0].max_hp = 12
	arena.targets[0].hp = 12
	await tick(3)
	mouse(MOUSE_BUTTON_RIGHT, true)
	mouse(MOUSE_BUTTON_RIGHT, false)
	for _index in range(50):
		if arena.hit_stop_active:
			break
		await tick(1)
	check(arena.hit_stop_active, "custom mouse attack enters the existing hit-stop path")
	mouse(MOUSE_BUTTON_RIGHT, true)
	mouse(MOUSE_BUTTON_RIGHT, false)
	check(arena.player._mouse_attack_pending, "custom mouse attack is buffered during hit stop")
	await tick(90)
	check(arena.targets[0].hp == 10, "custom buffered input causes exactly one follow-up strike")
	await fixture(1)
	arena.player.position = Vector2(70, 160)
	arena.targets[0].position = Vector2(96, 160)
	await tick(3)
	mouse(MOUSE_BUTTON_RIGHT, true)
	mouse(MOUSE_BUTTON_RIGHT, false)
	for _index in range(50):
		if arena.hit_stop_active:
			break
		await tick(1)
	await tap(KEY_F1)
	check(arena.settings_open and paused and not arena.hit_stop_active, "settings can interrupt hit stop without leaving its overlay active")
	menu.cancel()
	await tick(20)
	check(not paused and not arena.hit_stop_overlay.visible, "closing settings after hit stop restores normal world processing")
	await tap(KEY_F1)
	menu.restore_defaults()
	check(menu.draft == CONTROLS.defaults() and CONTROLS.current == custom_profile(), "restore defaults remains a draft until saved")
	menu.cancel()
	check(CONTROLS.current == custom_profile(), "canceling default restore retains the player's custom profile")
	await tap(KEY_F1)
	menu.restore_defaults()
	menu.save_and_close()
	check(CONTROLS.current == CONTROLS.defaults(), "saving restored defaults restores every original key")
	# Verify invalid data recovery without touching the real player profile.
	var config := ConfigFile.new()
	config.set_value("bindings", "version", 1)
	config.set_value("bindings", "move_left", KEY_A)
	config.save(TEST_PATH)
	CONTROLS.current.clear()
	CONTROLS.install()
	check(CONTROLS.current == CONTROLS.defaults() and not CONTROLS.load_notice.is_empty(), "incomplete saved data falls back to defaults with a visible notice")
	var invalid := custom_profile()
	invalid["jump"] = "I"
	check(not CONTROLS.validate(invalid).is_empty(), "saved values must have the expected integer type")
	invalid = custom_profile()
	invalid["move_left"] = KEY_RIGHT
	check(not CONTROLS.save_bindings(invalid).is_empty() and CONTROLS.current == CONTROLS.defaults(), "invalid profile cannot replace live controls")
	CONTROLS.settings_path = "user://missing_keybindings_regression_folder/settings.cfg"
	check(not CONTROLS.save_bindings(custom_profile()).is_empty() and CONTROLS.current == CONTROLS.defaults(), "save failure preserves live controls and reports a useful error")
	CONTROLS.settings_path = TEST_PATH
	check(CONTROLS.save_bindings(custom_profile()).is_empty(), "valid profile can overwrite an existing settings file atomically")
	var old_config := ConfigFile.new()
	old_config.set_value("bindings", "version", 1)
	for slot in CONTROLS.SLOTS:
		if slot != "dash_modifier":
			old_config.set_value("bindings", slot, custom_profile()[slot])
	old_config.set_value("bindings", "attack_keyboard", KEY_J)
	old_config.save(TEST_PATH)
	CONTROLS.current.clear()
	CONTROLS.install()
	var migrated := custom_profile()
	migrated["dash_modifier"] = KEY_SHIFT
	check(CONTROLS.current == migrated, "old saved profiles retain every surviving binding and receive the shared modifier")
	check(CONTROLS.validate(CONTROLS.current).is_empty(), "the migrated shared modifier is valid")
	var shared := ConfigFile.new()
	shared.set_value("bindings", "version", 3)
	for slot in CONTROLS.SLOTS:
		shared.set_value("bindings", slot, custom_profile()[slot])
	shared.set_value("bindings", "dash_modifier", KEY_SHIFT)
	shared.save(TEST_PATH)
	CONTROLS.current.clear()
	CONTROLS.install()
	check(CONTROLS.current == migrated, "a saved profile that shared run and dodge keeps the shared modifier")
	var clash := custom_profile()
	clash["dash_modifier"] = clash["run"]
	check(CONTROLS.validate(clash).is_empty(), "run and dodge intentionally share a tap/hold modifier")
	clash = custom_profile()
	clash["heavy_mouse"] = clash["attack_mouse"]
	check(not CONTROLS.validate(clash).is_empty(), "attack and heavy cannot share a mouse button")
	clash = custom_profile()
	clash["heavy_mouse"] = KEY_H
	check(not CONTROLS.validate(clash).is_empty(), "the heavy slot only takes mouse buttons")
	# A profile saved before the heavy attack existed gets the right button when attack is not on it.
	var before_heavy := ConfigFile.new()
	before_heavy.set_value("bindings", "version", 3)
	for slot in CONTROLS.SLOTS:
		if slot != "heavy_mouse":
			before_heavy.set_value("bindings", slot, CONTROLS.defaults()[slot])
	before_heavy.save(TEST_PATH)
	CONTROLS.current.clear()
	CONTROLS.install()
	check(CONTROLS.current == CONTROLS.defaults() and CONTROLS.load_notice.contains("RMB"), "a profile saved before the heavy attack gets RMB for heavy and says so")
	check(InputMap.action_get_events("heavy_mouse").size() == 1, "the heavy action is bound to one mouse button")
	# F is no longer reserved: a saved F binding loads unchanged.
	var saved_f_config := ConfigFile.new()
	saved_f_config.set_value("bindings", "version", 4)
	var saved_f := custom_profile()
	saved_f["jump"] = KEY_F
	for slot in CONTROLS.SLOTS:
		saved_f_config.set_value("bindings", slot, saved_f[slot])
	saved_f_config.save(TEST_PATH)
	CONTROLS.current.clear()
	CONTROLS.install()
	check(CONTROLS.current == saved_f and CONTROLS.load_notice.is_empty(), "a saved F binding loads unchanged and without a migration notice")
	check(CONTROLS.validate(saved_f).is_empty(), "a new profile may bind a player action to F")
	# The reload stage expects the custom profile on disk.
	check(CONTROLS.save_bindings(custom_profile()).is_empty(), "the custom profile is saved again for the reload stage")
	check(InputMap.action_get_events("attack").size() == 1 and not CONTROLS.current.has("attack_keyboard"), "old saved J attack is discarded during migration")
	finish("keybindings_report.json")


func gameplay_checks() -> void:
	await fixture()
	var start: Vector2 = arena.player.position
	key(KEY_D, true)
	await tick(8)
	key(KEY_D, false)
	check(arena.player.position == start, "old movement key no longer moves after rebind")
	key(KEY_RIGHT, true)
	await tick(8)
	check(arena.player.position.x > start.x + 1.0, "new movement key moves the player")
	key(KEY_SHIFT, true)
	await tick(8)
	check(arena.player.is_running, "new run key still requires holding")
	key(KEY_SHIFT, false)
	await tick(2)
	check(not arena.player.is_running, "releasing run key returns to walking")
	key(KEY_RIGHT, false)
	await fixture()
	await tap(KEY_J)
	check(not arena.player.is_attacking, "old attack key is disabled")
	await tap(KEY_K)
	check(not arena.player.is_attacking, "there is no keyboard attack replacement")
	mouse(MOUSE_BUTTON_LEFT, true)
	mouse(MOUSE_BUTTON_LEFT, false)
	await tick(2)
	check(not arena.player.is_attacking, "old mouse attack is disabled")
	mouse(MOUSE_BUTTON_RIGHT, true)
	await tick(2)
	check(not arena.player.is_charging and not arena.player.is_attacking and not String(arena.player.sprite.animation).begins_with("attack3"), "rebound short press preserves locomotion without charge anticipation")
	mouse(MOUSE_BUTTON_RIGHT, false)
	await tick(2)
	check(arena.player.is_attacking, "short release of rebound primary starts one strike")
	await tick(65)
	check(not arena.player.is_attacking and not arena.player.is_charging, "released rebound primary never auto-chains")
	await tap(KEY_TAB)
	check(arena.view_mode == 0, "old view key is disabled")
	await tap(KEY_V)
	check(arena.view_mode == 1, "new view key switches views")
	await tick(6)
	await tap(KEY_I)
	check(arena.player.velocity.y < 0, "new jump key preserves side-view jumping")
	await fixture(1)
	key(KEY_C, true)
	await tick(5)
	check(arena.player.is_crouching, "new crouch key preserves side-view crouching")
	key(KEY_C, false)
	await fixture(1)
	key(KEY_U, true)
	mouse(MOUSE_BUTTON_RIGHT, true)
	await tick(2)
	check(arena.player.special_kind == "rising_slash", "rebound modifier plus rebound mouse triggers rising slash")
	key(KEY_U, false)
	mouse(MOUSE_BUTTON_RIGHT, false)
	await fixture(1)
	key(KEY_RIGHT, true)
	await tap(KEY_SHIFT)
	check(not arena.player.is_attacking, "Shift is the rebound run key and no longer dashes")
	key(KEY_L, true)
	mouse(MOUSE_BUTTON_RIGHT, true)
	await tick(2)
	mouse(MOUSE_BUTTON_RIGHT, false)
	key(KEY_L, false)
	check(arena.player.special_kind == "dash_stab" and arena.player.attack_direction.x > 0.0, "the rebound dash key with a held direction triggers the piercing dash")
	key(KEY_RIGHT, false)
	await fixture(1)
	await tap(KEY_I)
	key(KEY_RIGHT, true)
	key(KEY_L, true)
	mouse(MOUSE_BUTTON_RIGHT, true)
	await tick(2)
	mouse(MOUSE_BUTTON_RIGHT, false)
	key(KEY_L, false)
	check(arena.player.special_kind == "dash_stab" and not arena.player.is_on_floor(), "the rebound dash key also triggers the airborne dash")
	key(KEY_RIGHT, false)
	await fixture(1)
	arena.player.position.x = 80
	await tap(KEY_R)
	check(arena.player.position.x > 70, "old reset key is disabled")
	await tap(KEY_N)
	check(arena.player.position.x < 45 and arena.hits == 0, "new reset key resets the arena")


func finish(filename: String) -> void:
	var result := {"checks": checks, "failures": failures, "status": "passed" if failures.is_empty() else "failed", "engine": Engine.get_version_info()["string"]}
	var file := FileAccess.open("res://evidence/" + filename, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
