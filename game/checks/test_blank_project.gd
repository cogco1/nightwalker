extends SceneTree
## Exercise the real entry scene, player controls, kill feedback and retained animation resources.
const SPACE = preload("res://scenes/blank_space.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const MOVESET = preload("res://scripts/player/moves_long_blade.gd")
const TOP = preload("res://assets/top_down.tres")
const SIDE = preload("res://assets/side_view.tres")
var world: Node2D
var checks := 0
var failures: Array[String] = []
var contacts: Array[bool] = []

# A temporary data probe: no enemy behavior, artwork, collision or normal-game spawning.
class ContactProbe extends Node2D:
	var hp := 1
	func take_damage(amount: int) -> bool:
		hp -= amount
		return true

func _initialize() -> void:
	create_timer(30.0, true).timeout.connect(func() -> void: quit(2))
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func tick(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code, true)
	await tick(2)
	key(code, false)
	await tick(2)

func _run() -> void:
	CONTROLS.install(false)
	world = SPACE.instantiate()
	root.add_child(world)
	current_scene = world
	await tick(12)
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/blank_space.tscn", "default entry is empty")
	check(not root.has_node("SceneRoutes"), "no legacy scene router")
	for path in ["scenes/boot.tscn", "scenes/main.tscn", "scenes/home_601.tscn", "scenes/underground_hospital.tscn", "scenes/night_street_proto.tscn", "scenes/breath_interlude.tscn", "scripts/player/charged_draw.gd", "scripts/player/impact_v2.gd", "scripts/core/impact_burst.gd", "shaders/screen_cut.gdshader"]:
		check(not FileAccess.file_exists("res://" + path), "removed resource: " + path)
	for folder in ["scripts/enemies", "scripts/levels", "assets/home_601", "assets/underground_hospital", "assets/night_street", "assets/npcs", "assets/story"]:
		check(not DirAccess.dir_exists_absolute("res://" + folder), "removed folder: " + folder)
	check(get_nodes_in_group("enemies").is_empty(), "no enemies spawned")
	check(world.player.view_mode == 1 and world.player.is_on_floor(), "side view starts on a plain floor")
	var start: Vector2 = world.player.position
	key(KEY_D, true)
	await tick(12)
	key(KEY_D, false)
	await tick(10)
	check(world.player.position.x > start.x + 4, "movement works")
	await tap(KEY_SPACE)
	check(world.player.position.y < start.y - 4, "jump works")
	await tick(65)
	check(world.player.is_on_floor(), "player lands")
	mouse(MOUSE_BUTTON_LEFT, true)
	await tick(2)
	mouse(MOUSE_BUTTON_LEFT, false)
	await tick(3)
	check(world.player.is_attacking, "short left click starts light attack")
	await tick(40)
	mouse(MOUSE_BUTTON_RIGHT, true)
	await tick(3)
	check(world.player.is_attacking, "right click starts heavy attack")
	mouse(MOUSE_BUTTON_RIGHT, false)
	await tick(50)
	mouse(MOUSE_BUTTON_LEFT, true)
	await tick(40)
	check(world.player.is_charging, "left hold charges")
	mouse(MOUSE_BUTTON_LEFT, false)
	await tick(2)
	check(world.player.move_id == &"heavy_slash", "charge retains the draw action")
	await tick(45)
	_assert_clean_fx()
	var probe := ContactProbe.new()
	world.add_child(probe)
	world.player.struck.connect(func(_point: Vector2, _weight: StringName, _direction: Vector2, killed: bool) -> void: contacts.append(killed))
	world.player.fx.effects.clear()
	world.player._resolve_hit(probe, world.player.position + Vector2(12, -16), MOVESET.MOVES[&"attack1"])
	check(contacts.has(true), "real kill-feedback path exercised")
	check(world.player.fx.effects.size() == 5, "kill creates small neutral sparks only")
	for effect in world.player.fx.effects:
		check(effect.color in [world.player.fx.WHITE, world.player.fx.BLUE], "no black/red contact particles")
	check(world.session.hit_stop_active, "ordinary hit-stop retained")
	await tick(25)
	check(not paused and not world.session.hit_stop_active, "hit-stop completes without removed system")
	_assert_clean_fx()
	probe.free()
	await tap(KEY_TAB)
	check(world.player.view_mode == 0, "Tab opens empty top-down view")
	start = world.player.position
	key(KEY_W, true)
	await tick(12)
	key(KEY_W, false)
	await tick(8)
	check(world.player.position.y < start.y - 4, "top-down movement works")
	await tap(KEY_R)
	check(world.player.position.distance_to(Vector2(160, 96)) < 1, "reset works")
	await tap(KEY_F7)
	await tap(KEY_F8)
	await tap(KEY_F10)
	check(current_scene == world and world.player.view_mode == 0, "old level and effect shortcuts stay removed")
	_assert_clean_fx()
	await tap(KEY_ESCAPE)
	check(world.session.settings_open and paused, "settings opens")
	await tap(KEY_ESCAPE)
	check(not world.session.settings_open and not paused, "settings closes")
	await tap(KEY_TAB)
	check(world.player.view_mode == 1, "Tab returns to empty side view")
	for frames in [TOP, SIDE]:
		for animation in frames.get_animation_names():
			for index in range(frames.get_frame_count(animation)):
				var texture: Texture2D = frames.get_frame_texture(animation, index)
				check(texture != null and texture.get_width() > 0, "retained animation %s/%s" % [animation, index])
	CONTROLS.release_actions()
	print(JSON.stringify({"checks": checks, "failures": failures, "status": "passed" if failures.is_empty() else "failed"}))
	quit(0 if failures.is_empty() else 1)

func _assert_clean_fx() -> void:
	for effect_name in ["ContactInk", "ChargedDraw"]:
		check(not world.player.fx.has_node(NodePath(effect_name)), "removed node: " + effect_name)
	check(not world.session.has_node("ImpactBurst"), "no sword qi or screen-cut system")
