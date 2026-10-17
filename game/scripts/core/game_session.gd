extends Node
## Shared settings menu, impact pause (hit-stop), perfect-dodge slow motion and combat sounds for every scene with
## a player, including the combat test fixture, so tests exercise the same hit-stop the game ships.

const CONTROLS = preload("res://scripts/core/controls.gd")
const MENU = preload("res://scripts/ui/keybindings_menu.gd")
const COMBAT_FEEDBACK = preload("res://scripts/core/combat_feedback.gd")
const IMPACT_FRAME = preload("res://shaders/impact_frame.gdshader")
const PLAYER = preload("res://scripts/player/player.gd")
# Impact weight -> displayed frames held (and at least frames/60 s), shake in native px, how the frozen frame
# looks (negative frames first, then flash frames) and the camera after-shock once it resumes; after-shock x
# follows the attack direction, so the camera is kicked along the blow. light 4 / critical 6 are the source
# game's guarantees; only the look is added on top.
const STOPS := {
	# The middle hits of the aerial spin: a short tick that keeps the spin flowing.
	&"tick": {"frames": 2, "shake": 0},
	&"light": {"frames": 4, "shake": 1},
	&"critical": {"frames": 6, "shake": 1, "flash": Color(1.5, 1.5, 1.6), "flash_frames": 1,
		"aftershock": [Vector2(2, 0), Vector2(-2, 0), Vector2(1, 0), Vector2.ZERO]},
	&"heavy": {"frames": 10, "shake": 2, "negative_frames": 1, "flash": Color(1.8, 1.8, 2.0), "flash_frames": 2,
		"aftershock": [Vector2(4, 1), Vector2(-3, -1), Vector2(3, 1), Vector2(-2, 0), Vector2(1, 0), Vector2(-1, 0), Vector2.ZERO]},
}
const HEAVY_STOP_FRAMES := 10
# Perfect dodge: the world runs at SLOWMO_SCALE for SLOWMO_SECONDS of real time while the hero keeps full speed
# (enemies scale their delta by world_time_scale; Engine.time_scale stays 1). The clock stands still during hit-stops
# and the settings menu. The screen edges glow cyan, the hero cannot be hit, and the hero's counter ends it.
const SLOWMO_SCALE := 0.25
const SLOWMO_SECONDS := 1.2
const SLOWMO_TINT := Color(0.42, 0.89, 0.91)

const GROUP := &"game_session"

signal stop_clock_step
signal hit_stop_started
signal hit_stop_frame(frame: int, shake: Vector2i)
signal hit_stop_finished(frames: int)
## After the settings menu closes; scenes redraw hints that name keys.
signal keybindings_closed(saved: bool)
signal slowmo_started
signal slowmo_finished
var settings_open := false
var keybindings_menu: CanvasLayer
var combat_feedback: Node
var hit_stop_active := false
## Speed of the world relative to the hero: enemies scale their delta by it (1 = normal).
var world_time_scale := 1.0
var slowmo_active := false
## Real seconds of slow motion left.
var slowmo_left := 0.0
var slowmo_overlay: TextureRect
var _slowmo_layer: CanvasLayer
var _counter_swung := false
var hit_stop_requested_frames := 0
var hit_stop_min_seconds := 0.0
var hit_stop_elapsed_seconds := 0.0
var hit_stop_displayed_frames := 0
var hit_stop_shake := Vector2i.ZERO
var hit_stop_overlay: TextureRect
var _impact_frame: ShaderMaterial
var completed_stop_frames: Array[int] = []
var completed_stop_durations: Array[float] = []
var _player: CharacterBody2D
var _host: Node
var _overlay_layer: CanvasLayer
var _saved_pause := false
var _menu_saved_pause := false
var _saved_canvas := Transform2D.IDENTITY
var _layer_offsets: Dictionary = {}
var _token := 0
# Open story modals (dialogue boxes, keypads) by instance id -> weakref; while any is open, Esc / F1 belong to it.
var _modals: Dictionary = {}


## The current scene's session, for story modals to register with; null outside a game scene (bare test hosts).
static func of(node: Node) -> Node:
	return node.get_tree().get_first_node_in_group(GROUP) if node.is_inside_tree() else null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	_host = get_parent()
	keybindings_menu = MENU.new()
	keybindings_menu.name = "KeybindingsMenu"
	add_child(keybindings_menu)
	keybindings_menu.closed.connect(_close_keybindings)
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 100
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay_layer)
	hit_stop_overlay = TextureRect.new()
	hit_stop_overlay.size = Vector2(320, 180)
	hit_stop_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hit_stop_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hit_stop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_stop_overlay.hide()
	_impact_frame = ShaderMaterial.new()
	_impact_frame.shader = IMPACT_FRAME
	hit_stop_overlay.material = _impact_frame
	_overlay_layer.add_child(hit_stop_overlay)
	# Below the hit-stop overlay, so a freeze inside the slow motion snapshots the glow once.
	_slowmo_layer = CanvasLayer.new()
	_slowmo_layer.layer = 99
	_slowmo_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_slowmo_layer)
	slowmo_overlay = TextureRect.new()
	slowmo_overlay.size = Vector2(320, 180)
	slowmo_overlay.texture = _edge_glow()
	slowmo_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slowmo_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slowmo_overlay.hide()
	_slowmo_layer.add_child(slowmo_overlay)
	combat_feedback = COMBAT_FEEDBACK.new()
	combat_feedback.name = "CombatFeedback"
	add_child(combat_feedback)
	bind_player(_host.get("player"))


func bind_player(player: CharacterBody2D) -> void:
	end_slowmo()
	_player = player
	if not is_instance_valid(_player):
		return
	if not _player.impact.is_connected(_on_impact):
		_player.impact.connect(_on_impact)
	if not _player.attack_received.is_connected(_on_attack_received):
		_player.attack_received.connect(_on_attack_received)
		_player.counter_started.connect(_on_counter_started)
	combat_feedback.bind_player(_player)


func _process(delta: float) -> void:
	if hit_stop_active:
		hit_stop_elapsed_seconds += delta
		stop_clock_step.emit()
	elif slowmo_active and not get_tree().paused:
		slowmo_left -= delta
		if slowmo_left <= 0.0:
			end_slowmo()


func start_slowmo(enemy: Node2D) -> void:
	slowmo_active = true
	slowmo_left = SLOWMO_SECONDS
	world_time_scale = SLOWMO_SCALE
	_counter_swung = false
	slowmo_overlay.show()
	if is_instance_valid(_player):
		_player.invulnerable = true
		_player.open_counter(enemy)
	slowmo_started.emit()


func end_slowmo() -> void:
	if not slowmo_active:
		return
	slowmo_active = false
	slowmo_left = 0.0
	world_time_scale = 1.0
	slowmo_overlay.hide()
	if is_instance_valid(_player):
		_player.invulnerable = false
		_player.close_counter()
	slowmo_finished.emit()


func _on_attack_received(result: int, attack: Dictionary) -> void:
	if result == PLAYER.AttackResult.PERFECT and not slowmo_active:
		start_slowmo(attack.get("source"))


func _on_counter_started(_enemy: Node2D) -> void:
	_counter_swung = true


# Cyan glow along the screen edges in a few flat steps, so it stays on the pixel grid.
static func _edge_glow() -> ImageTexture:
	var image := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	for y in range(180):
		for x in range(320):
			var edge := mini(mini(x, 319 - x), mini(y, 179 - y))
			var alpha: float = [0.42, 0.30, 0.20, 0.12, 0.06][edge / 3] if edge < 15 else 0.0
			image.set_pixel(x, y, Color(SLOWMO_TINT, alpha))
	return ImageTexture.create_from_image(image)


func push_modal(owner: Object) -> void:
	_modals[owner.get_instance_id()] = weakref(owner)


func pop_modal(owner: Object) -> void:
	_modals.erase(owner.get_instance_id())


func has_modal() -> bool:
	for id in _modals.keys():
		if _modals[id].get_ref() == null:
			_modals.erase(id)
	return not _modals.is_empty()


func _input(event: InputEvent) -> void:
	if settings_open:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode in [KEY_F1, KEY_ESCAPE] or event.physical_keycode in [KEY_F1, KEY_ESCAPE]):
		if not has_modal():
			open_keybindings()
			get_viewport().set_input_as_handled()
		return
	if hit_stop_active and is_instance_valid(_player):
		_player.handle_input(event)


func open_keybindings() -> void:
	if settings_open or has_modal() or not is_instance_valid(_player):
		return
	cancel_hit_stop()
	_menu_saved_pause = get_tree().paused
	settings_open = true
	_player.freeze(self, false)
	get_tree().paused = true
	keybindings_menu.open()


func _close_keybindings(saved: bool) -> void:
	CONTROLS.release_actions()
	if is_instance_valid(_player):
		_player.unfreeze(self)
	settings_open = false
	get_tree().paused = _menu_saved_pause
	keybindings_closed.emit(saved)


# One pause per attack stage: the player emits impact once per stage, and a request during a pause is ignored.
func _on_impact(weight: StringName, direction: Vector2) -> void:
	# The counter's hit ends the slow motion; its freeze follows at normal speed.
	if slowmo_active and _counter_swung:
		end_slowmo()
	if not hit_stop_active:
		_run_hit_stop(direction, weight)


func _display_frame() -> void:
	if DisplayServer.get_name() == "headless":
		await stop_clock_step
	else:
		await RenderingServer.frame_post_draw


func _run_hit_stop(direction: Vector2, weight: StringName) -> void:
	var stop: Dictionary = STOPS.get(weight, STOPS[&"light"])
	_token += 1
	var token := _token
	hit_stop_active = true
	hit_stop_requested_frames = int(stop["frames"])
	hit_stop_min_seconds = hit_stop_requested_frames / 60.0
	hit_stop_elapsed_seconds = 0.0
	hit_stop_displayed_frames = 0
	var unit := Vector2i(int(signf(direction.x)), 0) if direction.x != 0.0 else Vector2i(0, int(signf(direction.y)))
	hit_stop_shake = unit * int(stop["shake"])
	_saved_pause = get_tree().paused
	_saved_canvas = get_viewport().canvas_transform
	var shifted := _saved_canvas
	shifted.origin += Vector2(hit_stop_shake)
	get_viewport().canvas_transform = shifted
	_layer_offsets.clear()
	for layer in _host.find_children("*", "CanvasLayer", true, false):
		if layer != _overlay_layer and layer != _slowmo_layer:
			_layer_offsets[layer] = layer.offset
			layer.offset += Vector2(hit_stop_shake)
	get_tree().paused = true
	hit_stop_started.emit()
	# The first displayed freeze frame already holds the impact and the shared shift.
	await _display_frame()
	if token != _token:
		return
	hit_stop_displayed_frames = 1
	hit_stop_frame.emit(1, hit_stop_shake)
	if DisplayServer.get_name() != "headless":
		var snapshot := get_viewport().get_texture().get_image()
		if snapshot != null and not snapshot.is_empty():
			hit_stop_overlay.texture = ImageTexture.create_from_image(snapshot)
			_frozen_look(stop, 1)
			hit_stop_overlay.show()
	# Retain the frame AND visible-time guarantees on every refresh rate.
	while hit_stop_displayed_frames < hit_stop_requested_frames or hit_stop_elapsed_seconds + 0.000001 < hit_stop_min_seconds:
		await _display_frame()
		if token != _token:
			return
		hit_stop_displayed_frames += 1
		hit_stop_frame.emit(hit_stop_displayed_frames, hit_stop_shake)
		_frozen_look(stop, hit_stop_displayed_frames)
	completed_stop_frames.append(hit_stop_displayed_frames)
	completed_stop_durations.append(hit_stop_elapsed_seconds)
	_finish_hit_stop()
	hit_stop_finished.emit(hit_stop_displayed_frames)
	if stop.has("aftershock"):
		_aftershock(stop["aftershock"], token, -1.0 if direction.x < 0.0 else 1.0)


# Frozen-frame look for displayed frame `frame` (1-based): negative first, then flash, then the plain snapshot.
func _frozen_look(stop: Dictionary, frame: int) -> void:
	var negative_frames := int(stop.get("negative_frames", 0))
	var flash_until := negative_frames + int(stop.get("flash_frames", 0))
	_impact_frame.set_shader_parameter("negative", 1.0 if frame <= negative_frames else 0.0)
	hit_stop_overlay.modulate = stop.get("flash", Color.WHITE) if frame > negative_frames and frame <= flash_until else Color.WHITE


func _aftershock(offsets: Array, token: int, side: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var rest := camera.offset
	for offset in offsets:
		if token != _token or not is_instance_valid(camera):
			break
		camera.offset = rest + Vector2(offset.x * side, offset.y)
		await get_tree().process_frame
	if is_instance_valid(camera):
		camera.offset = rest


func _finish_hit_stop() -> void:
	hit_stop_overlay.hide()
	get_viewport().canvas_transform = _saved_canvas
	for layer in _layer_offsets:
		if is_instance_valid(layer):
			layer.offset = _layer_offsets[layer]
	_layer_offsets.clear()
	get_tree().paused = _saved_pause
	hit_stop_active = false


## A freeze the story asks for (the execution), run like an impact's unless one is already running.
func hit_stop(weight: StringName, direction := Vector2.RIGHT) -> void:
	if not hit_stop_active:
		_run_hit_stop(direction, weight)


func cancel_hit_stop() -> void:
	_token += 1
	if hit_stop_active:
		_finish_hit_stop()


func _exit_tree() -> void:
	cancel_hit_stop()
	end_slowmo()
	if settings_open:
		_close_keybindings(false)
