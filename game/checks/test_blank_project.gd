extends SceneTree
## Exercise the real entry scene, player controls, kill feedback and retained animation resources.
const SPACE = preload("res://scenes/blank_space.tscn")
const CONTROLS = preload("res://scripts/core/controls.gd")
const MOVESET = preload("res://scripts/player/moves_long_blade.gd")
const TOP = preload("res://assets/top_down.tres")
const SIDE = preload("res://assets/side_view.tres")
const CHARGE_FX = preload("res://scripts/player/charge_slash_fx.gd")
var world: Node2D
var checks := 0
var failures: Array[String] = []
var contacts: Array[bool] = []
var max_charge_pixels := 0
var max_charge_bounds := 0.0

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
	verify_charge_shape()
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
	check(world.player.fx.charge_slash.release_count == 0, "ordinary light attacks do not emit charged slash")
	await tick(40)
	mouse(MOUSE_BUTTON_RIGHT, true)
	await tick(3)
	check(world.player.is_attacking, "right click starts heavy attack")
	check(world.player.fx.charge_slash.release_count == 0, "ordinary heavy attacks do not emit charged slash")
	mouse(MOUSE_BUTTON_RIGHT, false)
	await tick(50)
	mouse(MOUSE_BUTTON_LEFT, true)
	await tick(40)
	check(world.player.is_charging, "left hold charges")
	mouse(MOUSE_BUTTON_LEFT, false)
	await tick(2)
	check(world.player.move_id == &"heavy_slash", "charge retains the draw action")
	await tick(5)
	check(world.player.fx.charge_slash.release_count == 1, "full charged draw emits its slash once")
	check(not world.player.fx.charge_slash.cuts.is_empty(), "blue-white slash appears during charged swing")
	await tick(45)
	check(world.player.fx.charge_slash.release_count == 1, "active swing does not spawn repeated slashes")
	check(world.player.fx.charge_slash.cuts.is_empty(), "charged afterglow disappears promptly")
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
	await verify_top_down_attacks()
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
	await tick(10)
	mouse(MOUSE_BUTTON_LEFT, true)
	await tick(40)
	check(world.player.is_charging, "side-view charging survives a view switch")
	mouse(MOUSE_BUTTON_LEFT, false)
	await tick(7)
	check(world.player.move_id == &"heavy_slash" and world.player.fx.charge_slash.release_count == 1,
		"side-view charge still releases its blue-white slash after switching back")
	await tick(45)
	for frames in [TOP, SIDE]:
		for animation in frames.get_animation_names():
			for index in range(frames.get_frame_count(animation)):
				var texture: Texture2D = frames.get_frame_texture(animation, index)
				check(texture != null and texture.get_width() > 0, "retained animation %s/%s" % [animation, index])
	CONTROLS.release_actions()
	print(JSON.stringify({"checks": checks, "failures": failures, "status": "passed" if failures.is_empty() else "failed",
		"charge_slash": {"max_visible_pixels": max_charge_pixels, "max_bounds_area": max_charge_bounds, "life_seconds": CHARGE_FX.LIFE}}))
	quit(0 if failures.is_empty() else 1)

func _assert_clean_fx() -> void:
	for effect_name in ["ContactInk", "ChargedDraw"]:
		check(not world.player.fx.has_node(NodePath(effect_name)), "removed node: " + effect_name)
	check(not world.session.has_node("ImpactBurst"), "no sword qi or screen-cut system")


func verify_charge_shape() -> void:
	var fx := CHARGE_FX.new()
	root.add_child(fx)
	var origin := Vector2(160, 90)
	for fps in [30, 60, 144]:
		for setting in [[Vector2.RIGHT, true], [Vector2.LEFT, true]]:
			fx.release(origin, setting[0], CHARGE_FX.REACH, setting[1])
			for _frame in range(ceili(CHARGE_FX.LIFE * fps) + 2):
				fx.step(1.0 / fps)
				var pixels := fx.effect_pixels()
				if pixels.is_empty():
					continue
				var low := Vector2(10000, 10000)
				var high := Vector2(-10000, -10000)
				var blue_white := true
				for point in pixels:
					low = low.min(Vector2(point))
					high = high.max(Vector2(point))
					var colour: Color = pixels[point]
					blue_white = blue_white and colour.r <= colour.g and colour.g <= colour.b
				var area := (high.x - low.x + 1) * (high.y - low.y + 1)
				max_charge_pixels = maxi(max_charge_pixels, pixels.size())
				max_charge_bounds = maxf(max_charge_bounds, area)
				check(pixels.size() <= 720, "visible charge pixels fit 1.25 percent of native screen")
				check(area <= 2880, "charge bounds stay within five percent of native screen")
				check(blue_white, "charged slash palette stays blue-white")
			check(fx.cuts.is_empty(), "effect expires at each tested frame rate and facing")
	# A nearby wall clips the decorative extension without changing the attack's damage geometry.
	fx.release(origin, Vector2.RIGHT, 24.0, true)
	fx.step(0.065)
	var clipped := fx.effect_pixels()
	var stopped_at_wall := true
	for point in clipped:
		stopped_at_wall = stopped_at_wall and point.x <= origin.x + 24.0
	check(not clipped.is_empty() and stopped_at_wall, "charged slash respects a nearby wall")
	fx.step(CHARGE_FX.LIFE)
	for _index in range(5):
		fx.release(origin, Vector2.RIGHT, CHARGE_FX.REACH, true)
	check(fx.cuts.size() == CHARGE_FX.MAX_CUTS, "rapid requests cannot stack unlimited effects")
	fx.free()


func verify_top_down_attacks() -> void:
	var player: CharacterBody2D = world.player
	var stats := {"started": 0, "ready": 0, "attacks": 0, "charged_moves": 0}
	player.charge_started.connect(func() -> void: stats.started += 1)
	player.charge_ready.connect(func() -> void: stats.ready += 1)
	player.move_started.connect(func(move: StringName) -> void:
		stats.attacks += 1
		if move == &"heavy_slash": stats.charged_moves += 1)
	for facing in ["up", "down", "left", "right"]:
		player.position = Vector2(160, 96)
		player.facing = facing
		player.show_idle()
		var previous_attacks: int = stats.attacks
		mouse(MOUSE_BUTTON_LEFT, true)
		await tick(2)
		check(player.is_attacking and player.move_id == &"attack1", "top-down press attacks immediately: " + facing)
		var charged := false
		for _frame in range(65):
			await tick(1)
			charged = charged or player.is_charging
		check(not charged and not player.is_attacking, "top-down long hold finishes as an ordinary attack: " + facing)
		check(stats.attacks == previous_attacks + 1, "holding does not auto-repeat top-down attacks: " + facing)
		var before_move: Vector2 = player.position
		key(KEY_D, true)
		await tick(12)
		key(KEY_D, false)
		await tick(8)
		check(player.position.x > before_move.x + 4, "holding attack does not charge-lock top-down movement: " + facing)
		mouse(MOUSE_BUTTON_LEFT, false)
		await tick(5)
		check(not player.is_attacking and stats.attacks == previous_attacks + 1, "release adds no top-down attack: " + facing)
	# A held second click during a combo must not enter charge after the preceding swing ends.
	var before_combo: int = stats.attacks
	mouse(MOUSE_BUTTON_LEFT, true)
	await tick(2)
	mouse(MOUSE_BUTTON_LEFT, false)
	await tick(7)
	mouse(MOUSE_BUTTON_LEFT, true)
	var combo_charged := false
	for _frame in range(80):
		await tick(1)
		combo_charged = combo_charged or player.is_charging
	mouse(MOUSE_BUTTON_LEFT, false)
	await tick(5)
	check(stats.attacks >= before_combo + 2, "top-down light combos still work")
	check(not combo_charged and stats.started == 0 and stats.ready == 0 and stats.charged_moves == 0,
		"top-down clicks and held combos never start or release a charge")
	player._begin_charge(1.0)
	check(not player.is_charging, "charge entry rejects the top-down view")
	player.fx._on_swing_released(&"heavy_slash")
	check(player.fx.charge_slash.release_count == 0 and player.fx.charge_slash.cuts.is_empty(),
		"top-down view cannot emit the charged slash effect")
