extends Node2D

const CONTROLS = preload("res://scripts/core/controls.gd")
const PLAYER_SCENE = preload("res://scenes/player.tscn")
const TARGET_SCRIPT = preload("res://tests/fixtures/training_target.gd")
const KEYBINDINGS_MENU = preload("res://scripts/ui/keybindings_menu.gd")
signal hit_stop_started
signal hit_stop_frame(frame: int, shake: Vector2i)
signal hit_stop_finished(frames: int)
signal hit_stop_clock_step

var view_mode := 0
var world: Node2D
var player: CharacterBody2D
var targets: Array[CharacterBody2D] = []
var obstacles: Array[Rect2] = []
var hits := 0
var defeated := 0
var view_label: Label
var controls_label: Label
var status_label: Label
var message := "Tap LMB again to chain."
var critical_events := 0
var normal_contact_events := 0
var hit_stop_requested_frames := 0
var hit_stop_elapsed_seconds := 0.0
var hit_stop_min_seconds := 0.0
var completed_stop_requests: Array[int] = []
var completed_stop_durations: Array[float] = []
var hit_stop_active := false
var hit_stop_displayed_frames := 0
var hit_stop_shake := Vector2i.ZERO
var hit_stop_snapshot: Image
var hit_stop_overlay: TextureRect
var hit_stop_render_frames: Array[int] = []
var hud_layer: CanvasLayer
var _stop_token := 0
var _saved_pause := false
var _saved_canvas := Transform2D.IDENTITY
var _saved_hud_offset := Vector2.ZERO
var keybindings_menu: CanvasLayer
var settings_open := false
var _settings_saved_pause := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_mode = Node.PROCESS_MODE_ALWAYS
	CONTROLS.install()
	_create_hud()
	keybindings_menu = KEYBINDINGS_MENU.new()
	add_child(keybindings_menu)
	keybindings_menu.closed.connect(_close_keybindings)
	build_arena(0)


func build_arena(mode: int) -> void:
	_cancel_hit_stop()
	view_mode = mode
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = Node2D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.y_sort_enabled = view_mode == 0
	add_child(world)
	targets.clear()
	obstacles.clear()
	hits = 0
	defeated = 0
	critical_events = 0
	normal_contact_events = 0
	completed_stop_requests.clear()
	completed_stop_durations.clear()
	message = "Tap %s again to chain." % CONTROLS.binding_text("attack_mouse")
	if view_mode == 0:
		add_wall(Rect2(8, 38, 304, 4))
		add_wall(Rect2(8, 166, 304, 4))
		add_wall(Rect2(4, 38, 4, 132))
		add_wall(Rect2(312, 38, 4, 132))
		add_wall(Rect2(126, 97, 28, 18))
		add_wall(Rect2(215, 46, 16, 43))
	else:
		add_wall(Rect2(8, 160, 304, 10))
		add_wall(Rect2(4, 38, 4, 132))
		add_wall(Rect2(312, 38, 4, 132))
		# The platform is 38 px high: reachable by the 225 px/s jump.
		add_wall(Rect2(128, 122, 28, 6))
		# Gap of 19 px: standing (26) is blocked; crouching (14) fits.
		add_wall(Rect2(196, 124, 42, 17))
	player = PLAYER_SCENE.instantiate()
	player.view_mode = view_mode
	player.z_index = 1 if view_mode == 1 else 0
	player.position = Vector2(44, 116) if view_mode == 0 else Vector2(42, 160)
	world.add_child(player)
	player.attack_hit.connect(_on_attack_hit)
	player.combo_changed.connect(_on_combo_changed)
	player.hit_resolved.connect(_on_hit_resolved)
	player.critical_hit.connect(_on_critical_hit)
	player.normal_contact_stop.connect(_on_normal_contact_stop)
	player.special_started.connect(_on_special_started)
	player.landing_impact.connect(_on_landing_impact)
	var spawn_points: Array[Vector2] = [Vector2(90, 83), Vector2(171, 143), Vector2(273, 93)]
	if view_mode == 1:
		spawn_points = [Vector2(99, 160), Vector2(153, 122), Vector2(278, 160), Vector2(119, 160), Vector2(135, 160)]
	for index in range(spawn_points.size()):
		var point := spawn_points[index]
		var target := TARGET_SCRIPT.new()
		target.side_view = view_mode == 1
		if view_mode == 1:
			target.max_hp = 9
		target.position = point
		target.destroyed.connect(_on_target_destroyed)
		world.add_child(target)
		targets.append(target)
	_refresh_hud()
	queue_redraw()


func add_wall(rectangle: Rect2) -> StaticBody2D:
	obstacles.append(rectangle)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rectangle.get_center()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rectangle.size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body


func switch_view() -> void:
	build_arena(1 - view_mode)


func _unhandled_input(event: InputEvent) -> void:
	if settings_open or hit_stop_active:
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("switch_view"):
		switch_view()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_arena"):
		build_arena(view_mode)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if settings_open:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode in [KEY_F1, KEY_ESCAPE] or event.physical_keycode in [KEY_F1, KEY_ESCAPE]):
		open_keybindings()
		get_viewport().set_input_as_handled()
		return
	if hit_stop_active and is_instance_valid(player):
		# Only collect button edges during the freeze; the paused player acts after it ends.
		player.call("_input", event)


func open_keybindings() -> void:
	if settings_open:
		return
	_cancel_hit_stop()
	_settings_saved_pause = get_tree().paused
	settings_open = true
	player.input_suspended = true
	player.clear_input_buffer()
	CONTROLS.release_actions()
	get_tree().paused = true
	keybindings_menu.open()


func _close_keybindings(saved: bool) -> void:
	CONTROLS.release_actions()
	player.clear_input_buffer()
	player.input_suspended = false
	settings_open = false
	get_tree().paused = _settings_saved_pause
	if saved:
		message = "Bindings saved."
	_refresh_hud()


func _process(delta: float) -> void:
	if hit_stop_active:
		hit_stop_elapsed_seconds += delta
		hit_stop_clock_step.emit()


func _on_attack_hit(target: Node) -> void:
	hits += 1
	message = "Target down. %s resets." % CONTROLS.binding_text("reset_arena") if target.get("hp") == 0 else "Hit! 1 damage."
	_refresh_hud()


func _on_target_destroyed() -> void:
	defeated += 1
	message = "Target down. %s resets." % CONTROLS.binding_text("reset_arena")
	_refresh_hud()


func _on_combo_changed(_stage: int) -> void:
	_refresh_hud()


func _on_hit_resolved(_target: Node, damage: int, critical: bool, kind: String) -> void:
	message = "CRITICAL x3! %d damage." % damage if critical else ("%s hit!" % kind if kind != "" else "Hit! %d damage." % damage)
	_refresh_hud()


func _on_special_started(kind: String, _direction: Vector2) -> void:
	message = "RISING SLASH" if kind == "rising_slash" else ("DIVE SLASH" if kind == "dive_slash" else "PIERCING DASH")
	_refresh_hud()


func _on_landing_impact(_point: Vector2) -> void:
	message = "DIVE IMPACT"
	_refresh_hud()


func _on_critical_hit(_target: Node, _damage: int, direction: Vector2) -> void:
	critical_events += 1
	if not hit_stop_active:
		_run_hit_stop(direction)


func _on_normal_contact_stop(direction: Vector2) -> void:
	normal_contact_events += 1
	if not hit_stop_active:
		_run_hit_stop(direction, 4)


func _display_frame() -> void:
	if DisplayServer.get_name() == "headless":
		# Dummy rendering has no post-draw image; count after this frame's clock update.
		await hit_stop_clock_step
	else:
		await RenderingServer.frame_post_draw


func _run_hit_stop(direction: Vector2, frames: int = 6) -> void:
	_stop_token += 1
	var token := _stop_token
	hit_stop_active = true
	hit_stop_requested_frames = clampi(frames, 4, 6)
	hit_stop_elapsed_seconds = 0.0
	hit_stop_min_seconds = hit_stop_requested_frames / 60.0
	hit_stop_displayed_frames = 0
	hit_stop_render_frames.clear()
	hit_stop_shake = Vector2i(int(signf(direction.x)), 0) if direction.x != 0.0 else Vector2i(0, int(signf(direction.y)))
	_saved_pause = get_tree().paused
	_saved_canvas = get_viewport().canvas_transform
	_saved_hud_offset = hud_layer.offset
	var shifted := _saved_canvas
	shifted.origin += Vector2(hit_stop_shake)
	get_viewport().canvas_transform = shifted
	hud_layer.offset = _saved_hud_offset + Vector2(hit_stop_shake)
	get_tree().paused = true
	hit_stop_started.emit()
	# The first actual displayed freeze frame contains the impact and one shared shift.
	await _display_frame()
	if token != _stop_token:
		return
	hit_stop_displayed_frames = 1
	hit_stop_render_frames.append(Engine.get_process_frames())
	hit_stop_frame.emit(1, hit_stop_shake)
	if DisplayServer.get_name() != "headless":
		hit_stop_snapshot = get_viewport().get_texture().get_image()
		if hit_stop_snapshot != null and not hit_stop_snapshot.is_empty():
			hit_stop_overlay.texture = ImageTexture.create_from_image(hit_stop_snapshot)
			hit_stop_overlay.visible = true
	# Keep the entire impact image still for the minimum frame count AND real duration.
	# Higher refresh rates need additional displayed frames to preserve the visible pause.
	while hit_stop_displayed_frames < hit_stop_requested_frames or hit_stop_elapsed_seconds + 0.000001 < hit_stop_min_seconds:
		await _display_frame()
		if token != _stop_token:
			return
		hit_stop_displayed_frames += 1
		hit_stop_render_frames.append(Engine.get_process_frames())
		hit_stop_frame.emit(hit_stop_displayed_frames, hit_stop_shake)
	_finish_hit_stop()


func _finish_hit_stop() -> void:
	hit_stop_overlay.visible = false
	get_viewport().canvas_transform = _saved_canvas
	hud_layer.offset = _saved_hud_offset
	get_tree().paused = _saved_pause
	hit_stop_active = false
	completed_stop_requests.append(hit_stop_displayed_frames)
	completed_stop_durations.append(hit_stop_elapsed_seconds)
	hit_stop_finished.emit(hit_stop_displayed_frames)


func _cancel_hit_stop() -> void:
	_stop_token += 1
	if hit_stop_active:
		_finish_hit_stop()
	hit_stop_displayed_frames = 0
	hit_stop_shake = Vector2i.ZERO


func _create_hud() -> void:
	var canvas := CanvasLayer.new()
	hud_layer = canvas
	canvas.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(canvas)
	var title := _label(canvas, Vector2(8, 3), 8)
	title.text = "NIGHTWALKER / AIR COMBAT  v10"
	var keys_button := Button.new()
	keys_button.text = "改键"
	keys_button.focus_mode = Control.FOCUS_NONE
	keys_button.position = Vector2(202, 2)
	keys_button.size = Vector2(26, 12)
	keys_button.add_theme_font_size_override("font_size", 8)
	keys_button.add_theme_font_override("font", title.get_theme_font("font"))
	for state in ["normal", "hover", "pressed"]:
		var button_style := StyleBoxFlat.new()
		button_style.bg_color = Color("353442") if state == "normal" else Color("555067")
		button_style.content_margin_left = 2
		button_style.content_margin_right = 2
		button_style.content_margin_top = 0
		button_style.content_margin_bottom = 0
		keys_button.add_theme_stylebox_override(state, button_style)
	keys_button.pressed.connect(open_keybindings)
	canvas.add_child(keys_button)
	keys_button.size = Vector2(26, 12)
	view_label = _label(canvas, Vector2(232, 4), 10)
	view_label.modulate = Color("d7bd72")
	controls_label = _label(canvas, Vector2(8, 15), 8)
	status_label = _label(canvas, Vector2(8, 170), 8)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New"])
	mono.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	controls_label.add_theme_font_override("font", mono)
	status_label.add_theme_font_override("font", mono)
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 100
	overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay_layer)
	hit_stop_overlay = TextureRect.new()
	hit_stop_overlay.size = Vector2(320, 180)
	hit_stop_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hit_stop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_stop_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hit_stop_overlay.visible = false
	overlay_layer.add_child(hit_stop_overlay)


func _label(parent: Node, location: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = location
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	var system_font := SystemFont.new()
	system_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	system_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	label.add_theme_font_override("font", system_font)
	parent.add_child(label)
	return label


func _refresh_hud() -> void:
	view_label.text = "俯视 · 白天" if view_mode == 0 else "侧视 · 夜晚"
	var attack := CONTROLS.binding_text("attack_mouse")
	var left := CONTROLS.binding_text("move_left")
	var right := CONTROLS.binding_text("move_right")
	controls_label.text = "%s/%s/%s/%s Move %s Run F1 Keys\n%s Combo %s View %s Reset" % [CONTROLS.binding_text("move_up"), left, CONTROLS.binding_text("move_down"), right, CONTROLS.binding_text("run"), attack, CONTROLS.binding_text("switch_view"), CONTROLS.binding_text("reset_arena")]
	if view_mode == 1:
		controls_label.text = "%s/%s Move %s Duck/Dive %s x2 Jump %s Run\n%s+%s Rise %s Dash %s Air combo" % [left, right, CONTROLS.binding_text("crouch"), CONTROLS.binding_text("jump"), CONTROLS.binding_text("run"), CONTROLS.binding_text("rising_modifier"), attack, CONTROLS.binding_text("dash_modifier"), attack]
	var width := controls_label.get_theme_font("font").get_multiline_string_size(controls_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var hud_size := 8 if width <= 304 else (7 if width <= 347 else 6)
	controls_label.add_theme_font_size_override("font_size", hud_size)
	var combo: int = player.combo_stage if is_instance_valid(player) else 0
	status_label.text = "COMBO %d/3 HIT %d KO %d/%d | %s" % [combo, hits, defeated, targets.size(), message]


func _draw() -> void:
	if view_mode == 0:
		draw_rect(Rect2(8, 42, 304, 124), Color("30303e"))
		for x in range(8, 313, 16):
			draw_rect(Rect2(x, 42, 1, 124), Color("383747"))
		for y in range(42, 167, 16):
			draw_rect(Rect2(8, y, 304, 1), Color("383747"))
		for rectangle in obstacles:
			draw_rect(rectangle, Color("594756"))
			draw_rect(Rect2(rectangle.position, Vector2(rectangle.size.x, 1)), Color("a07f87"))
		draw_rect(Rect2(236, 49, 49, 2), Color("ba655d"))
		draw_rect(Rect2(239, 53, 18, 1), Color("775c77"))
	else:
		draw_rect(Rect2(8, 38, 304, 122), Color("282634"))
		for x in range(14, 309, 12):
			draw_rect(Rect2(x, 44, 2, 113), Color("383040"))
		draw_rect(Rect2(20, 51, 26, 22), Color("796178"))
		draw_rect(Rect2(22, 53, 22, 18), Color("342c3c"))
		draw_rect(Rect2(28, 57, 7, 10), Color("b496a4"))
		for rectangle in obstacles:
			draw_rect(rectangle, Color("544653"))
			draw_rect(Rect2(rectangle.position, Vector2(rectangle.size.x, 1)), Color("bb9b88"))
		draw_rect(Rect2(196, 126, 42, 2), Color("85677b"))
		draw_rect(Rect2(196, 137, 42, 2), Color("392f3c"))
		draw_rect(Rect2(257, 149, 15, 5), Color("8b525d"))
		draw_rect(Rect2(263, 145, 5, 7), Color("ab645d"))
