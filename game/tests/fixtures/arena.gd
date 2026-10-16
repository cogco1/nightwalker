extends Node2D

const CONTROLS = preload("res://scripts/core/controls.gd")
const PLAYER_SCENE = preload("res://scenes/player.tscn")
const TARGET_SCRIPT = preload("res://tests/fixtures/training_target.gd")
const DRONE_SCRIPT = preload("res://tests/fixtures/attack_drone.gd")
const GAME_SESSION = preload("res://scripts/core/game_session.gd")
const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const LEVEL_KIT = preload("res://scripts/levels/level_kit.gd")
# The fixture runs the shipped GameSession (hit-stop, settings menu, combat sounds); the names below forward
# to it so the suites keep their wording while testing the real code.
signal hit_stop_started
signal hit_stop_frame(frame: int, shake: Vector2i)
signal hit_stop_finished(frames: int)

var view_mode := 0
var world: Node2D
var player: CharacterBody2D
var targets: Array[CharacterBody2D] = []
## Drones that attack the hero; only suites that ask for them get them (add_attacker).
var attackers: Array[CharacterBody2D] = []
var obstacles: Array[Rect2] = []
var hits := 0
var defeated := 0
var view_label: Label
var controls_label: Label
var status_label: Label
var message := "Tap LMB again to chain."
var critical_events := 0
var normal_contact_events := 0
var hud_layer: CanvasLayer
var session: Node
var hit_stop_active: bool:
	get: return session != null and session.hit_stop_active
var hit_stop_requested_frames: int:
	get: return session.hit_stop_requested_frames
var hit_stop_elapsed_seconds: float:
	get: return session.hit_stop_elapsed_seconds
var hit_stop_min_seconds: float:
	get: return session.hit_stop_min_seconds
var hit_stop_displayed_frames: int:
	get: return session.hit_stop_displayed_frames
var hit_stop_shake: Vector2i:
	get: return session.hit_stop_shake
var hit_stop_overlay: TextureRect:
	get: return session.hit_stop_overlay
var completed_stop_requests: Array[int]:
	get: return session.completed_stop_frames
var completed_stop_durations: Array[float]:
	get: return session.completed_stop_durations
var keybindings_menu: CanvasLayer:
	get: return session.keybindings_menu
var settings_open: bool:
	get: return session != null and session.settings_open


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_mode = Node.PROCESS_MODE_ALWAYS
	CONTROLS.install()
	_create_hud()
	session = GAME_SESSION.new()
	session.name = "GameSession"
	add_child(session)
	session.hit_stop_started.connect(hit_stop_started.emit)
	session.hit_stop_frame.connect(hit_stop_frame.emit)
	session.hit_stop_finished.connect(hit_stop_finished.emit)
	session.keybindings_closed.connect(func(_saved: bool) -> void: _refresh_hud())
	build_arena(0)


func build_arena(mode: int) -> void:
	session.cancel_hit_stop()
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
	attackers.clear()
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
	player.attack_received.connect(_on_attack_received)
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
	session.bind_player(player)
	_refresh_hud()
	queue_redraw()


## Side view: a hovering drone at `at` (its body centre) that telegraphs and lunges at the hero.
func add_attacker(at: Vector2) -> CharacterBody2D:
	var drone := DRONE_SCRIPT.new()
	drone.position = at
	world.add_child(drone)
	drone.attacker.bind_target(player)
	attackers.append(drone)
	return drone


func add_wall(rectangle: Rect2) -> StaticBody2D:
	obstacles.append(rectangle)
	return LEVEL_KIT.add_box(world, rectangle)


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


func open_keybindings() -> void:
	session.open_keybindings()


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


func _on_attack_received(result: int, _attack: Dictionary) -> void:
	message = ["HIT TAKEN", "EVADED", "PERFECT DODGE"][result]
	_refresh_hud()


func _on_special_started(kind: String, _direction: Vector2) -> void:
	message = "RISING SLASH" if kind == "rising_slash" else ("DIVE SLASH" if kind == "dive_slash" else "PIERCING DASH")
	_refresh_hud()


func _on_landing_impact(_point: Vector2) -> void:
	message = "DIVE IMPACT"
	_refresh_hud()


func _on_critical_hit(_target: Node, _damage: int, _direction: Vector2) -> void:
	critical_events += 1


func _on_normal_contact_stop(_direction: Vector2) -> void:
	normal_contact_events += 1


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


# The lab HUD keeps its small system-font text; the scenes use the 12px pixel font.
func _label(parent: Node, location: Vector2, size: int) -> Label:
	var system_font := SystemFont.new()
	system_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	system_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	return PIXEL_UI.label(parent, location, Vector2.ZERO, "", size, false, system_font)


func _refresh_hud() -> void:
	view_label.text = "俯视 · 白天" if view_mode == 0 else "侧视 · 夜晚"
	var attack := CONTROLS.binding_text("attack_mouse")
	var left := CONTROLS.binding_text("move_left")
	var right := CONTROLS.binding_text("move_right")
	controls_label.text = "%s/%s/%s/%s Move %s Run F1 Keys\n%s Combo %s View %s Reset" % [CONTROLS.binding_text("move_up"), left, CONTROLS.binding_text("move_down"), right, CONTROLS.binding_text("run"), attack, CONTROLS.binding_text("switch_view"), CONTROLS.binding_text("reset_arena")]
	if view_mode == 1:
		controls_label.text = "%s/%s Move %s Duck/Dive %s x2 Jump %s Run\n%s+%s Rise %s Dash %s Combo %s Heavy" % [left, right, CONTROLS.binding_text("crouch"), CONTROLS.binding_text("jump"), CONTROLS.binding_text("run"), CONTROLS.binding_text("rising_modifier"), attack, CONTROLS.binding_text("dash_modifier"), attack, CONTROLS.binding_text("heavy_mouse")]
	var width := controls_label.get_theme_font("font").get_multiline_string_size(controls_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var hud_size := 8 if width <= 304 else (7 if width <= 347 else 6)
	controls_label.add_theme_font_size_override("font_size", hud_size)
	var combo: int = player.combo_stage if is_instance_valid(player) else 0
	status_label.text = "COMBO %d/5 HIT %d KO %d/%d | %s" % [combo, hits, defeated, targets.size(), message]


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
