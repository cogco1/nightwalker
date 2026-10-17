extends RefCounted
## Plays a chapter fight night (scripts/levels/hospital/night_fight.gd) with real input, the way a careful player
## would: holds A / D (and Caps to run) to walk, clicks to string attacks, dodges with Shift just before a guard's
## blow or a bullet lands (a perfect dodge) and clicks again to counter, follows each lesson's icons, climbs the
## stairs with W and A, turns the last doctor's lines with E and executes him with a click. It reads only what a
## player sees on screen: where people stand, the red blink of a swing coming, the laser sight and the bullet in
## flight. Used by test_chapter_flow.gd (the whole night) and test_night_fight.gd (pieces of it).

const HUMANOID = preload("res://scripts/enemies/humanoid.gd")
const SHIFT_LEAD := 0.12
## Press the dash when a bullet's nose is this close to the hero's body line (250 px/s: about 0.17 s).
const BULLET_DODGE := 44.0
## Stop swinging when a bullet is this close, so the dash is free when it arrives.
const BULLET_WARY := 130.0
const CLICK_FRAMES := 8
const STRIKE_RANGE := 30.0

var suite: SceneTree
var hospital: Node2D
var fight: Node
var session: Node
## What the bot did, for the report: perfect dodges, counters, kills, deaths seen.
var tally := {"perfect": 0, "evade": 0, "hit": 0, "counters": 0, "clicks": 0, "heavy_clicks": 0, "shift": 0}
var frames_run := 0
var _held: Dictionary = {}
var _since_click := 99
var _since_shift := 99
var _since_e := 99
var _heavy_next := false
var _dodged: Dictionary = {}


func _init(owner: SceneTree) -> void:
	suite = owner


func bind(scene: Node2D) -> void:
	hospital = scene
	fight = scene.chapter.fight
	session = scene.get_node("GameSession")
	var hero: CharacterBody2D = scene.player
	if not hero.attack_received.is_connected(_count):
		hero.attack_received.connect(_count)
		hero.counter_started.connect(func(_enemy: Node2D) -> void: tally["counters"] += 1)


func _count(result: int, _attack: Dictionary) -> void:
	tally[["hit", "evade", "perfect"][result]] += 1


# --- input ---------------------------------------------------------------------------------------

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	if pressed:
		_held[code] = true
	else:
		_held.erase(code)


func mouse(button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = Vector2(160, 90)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func hold_only(codes: Array) -> void:
	for code in _held.keys():
		if code not in codes:
			key(code, false)
	for code in codes:
		if not _held.has(code):
			key(code, true)


func release_all() -> void:
	hold_only([])
	mouse(MOUSE_BUTTON_LEFT, false)
	mouse(MOUSE_BUTTON_RIGHT, false)


func frames(count := 1) -> void:
	for _index in range(count):
		await suite.physics_frame
	await suite.process_frame


## One click: pressed on this frame, released on the next tick.
func click(button := MOUSE_BUTTON_LEFT) -> void:
	mouse(button, true)
	await frames(1)
	mouse(button, false)
	_since_click = 0
	tally["clicks" if button == MOUSE_BUTTON_LEFT else "heavy_clicks"] += 1


func tap(code: int) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)


# --- what the player sees ----------------------------------------------------------------------

func hero() -> CharacterBody2D:
	return hospital.player


func floor_of(y: float) -> int:
	return 2 if y < HUMANOID.FLOOR_SPLIT else 1


func same_floor(body: Node2D) -> bool:
	return floor_of(body.global_position.y) == floor_of(hero().global_position.y)


func targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for enemy in fight.living(false):
		if same_floor(enemy):
			result.append(enemy)
	result.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return absf(a.global_position.x - hero().global_position.x) < absf(b.global_position.x - hero().global_position.x))
	return result


## A guard on this floor whose baton is going up within reach of the hero.
func swing_coming() -> Node2D:
	for enemy in fight.living(false):
		if enemy.kind == "guard" and same_floor(enemy) and enemy.attacker.phase == enemy.attacker.Phase.TELEGRAPH \
				and absf(enemy.global_position.x - hero().global_position.x) <= 44.0:
			return enemy
	return null


## Nearest bullet still flying at the hero on this floor, and how far its nose is from the hero's body line.
func bullet_coming() -> Array:
	var best: Array = []
	var center: Vector2 = hero().hurtbox().get_center()
	for bullet in fight.bullets:
		if not is_instance_valid(bullet) or bullet.resolved or bullet.spent or floor_of(bullet.global_position.y) != floor_of(hero().global_position.y):
			continue
		var gap: float = (center.x - bullet.global_position.x) * bullet.heading
		if gap > 0.0 and (best.is_empty() or gap < best[1]):
			best = [bullet, gap]
	return best


# --- playing -------------------------------------------------------------------------------------

## Plays until done() is true or the frame limit runs out; returns whether done() came true.
func play(done: Callable, limit := 6000) -> bool:
	for _index in range(limit):
		if done.call():
			release_all()
			return true
		if not is_instance_valid(hospital) or not hospital.is_inside_tree() or not is_instance_valid(fight):
			release_all()
			return done.call()
		await tick()
		frames_run += 1
	release_all()
	return done.call()


func tick() -> void:
	_since_click += 1
	_since_shift += 1
	_since_e += 1
	var player := hero()
	var box: Panel = hospital.interactions.dialogue
	if box.active:
		hold_only([])
		if _since_e >= 6:
			_since_e = 0
			await tap(KEY_E)
		else:
			await frames(1)
		return
	if fight.busy or player.is_frozen():
		hold_only([])
		await frames(1)
		return
	# The perfect dodge's slow motion: a click is the counter.
	if session.slowmo_active and is_instance_valid(player.get("_counter_target")):
		hold_only([])
		await click()
		return
	var swing := swing_coming()
	if swing != null:
		await _meet_swing(swing)
		return
	var incoming := bullet_coming()
	if not incoming.is_empty() and incoming[1] <= BULLET_DODGE:
		await _dash_toward(-float(incoming[0].heading))
		return
	var wary: bool = not incoming.is_empty() and incoming[1] <= BULLET_WARY
	var lesson: String = fight._lesson_id()
	var list := targets()
	if lesson in ["dodge", "perfect"]:
		# Learning to dodge: stand by a guard, out of the way of nothing, and wait for the blink.
		var guards := list.filter(func(enemy: Node2D) -> bool: return enemy.kind == "guard")
		if not guards.is_empty():
			await _wait_by(guards[0])
			return
	if list.is_empty():
		await _go_on()
		return
	var target: Node2D = list[0]
	await _strike(target, lesson, wary)


func _dash_toward(direction: float) -> void:
	if _since_shift < 12:
		await frames(1)
		return
	hold_only([KEY_D if direction > 0.0 else KEY_A])
	await frames(1)
	key(KEY_SHIFT, true)
	tally["shift"] += 1
	_since_shift = 0
	await frames(2)
	key(KEY_SHIFT, false)
	hold_only([])


## A guard's baton is going up: keep still, then dash through him SHIFT_LEAD before it falls (a perfect dodge).
func _meet_swing(guard: Node2D) -> void:
	var attacker: Node = guard.attacker
	var swing_id := "%d:%d" % [guard.get_instance_id(), roundi((guard.clock - attacker.phase_time) * 10.0)]
	hold_only([])
	if _dodged.has(swing_id) or attacker.phase_time < attacker.telegraph_seconds - SHIFT_LEAD:
		await frames(1)
		return
	_dodged[swing_id] = true
	await _dash_toward(signf(guard.global_position.x - hero().global_position.x))


## Stand facing a guard at striking distance without swinging.
func _wait_by(guard: Node2D) -> void:
	var gap: float = guard.global_position.x - hero().global_position.x
	if absf(gap) > 26.0:
		hold_only([KEY_D if gap > 0.0 else KEY_A] + ([KEY_CAPSLOCK] if absf(gap) > 90.0 else []))
	elif absf(gap) < 12.0:
		hold_only([KEY_A if gap > 0.0 else KEY_D])
	else:
		hold_only([])
		_face(signf(gap))
	await frames(1)


## Tap a direction for a frame when the hero faces the wrong way.
func _face(direction: float) -> void:
	var player := hero()
	var facing := 1.0 if player.facing == "right" else -1.0
	if facing != direction and not player.is_attacking and not player.is_charging:
		hold_only([KEY_D if direction > 0.0 else KEY_A])


func _strike(target: Node2D, lesson: String, wary: bool) -> void:
	var player := hero()
	var gap: float = target.global_position.x - player.global_position.x
	if absf(gap) > STRIKE_RANGE:
		var codes: Array = [KEY_D if gap > 0.0 else KEY_A]
		if absf(gap) > 70.0:
			codes.append(KEY_CAPSLOCK)
		hold_only(codes)
		await frames(1)
		return
	hold_only([])
	var facing := 1.0 if player.facing == "right" else -1.0
	if facing != signf(gap) and absf(gap) > 2.0:
		_face(signf(gap))
		await frames(1)
		return
	if wary or _since_click < CLICK_FRAMES:
		await frames(1)
		return
	if lesson == "heavy" and _heavy_next:
		_heavy_next = false
		await click(MOUSE_BUTTON_RIGHT)
		return
	await click(MOUSE_BUTTON_LEFT)
	_heavy_next = lesson == "heavy"


## Nobody left on this floor: up the stairs while others remain, else to the last doctor.
func _go_on() -> void:
	var player := hero()
	if floor_of(player.global_position.y) == 1:
		await climb()
		return
	var doctor: Node2D = fight.last_doctor
	if not is_instance_valid(doctor) or doctor.dead:
		hold_only([])
		await frames(1)
		return
	if not doctor.executable:
		var gap: float = doctor.global_position.x - player.global_position.x
		hold_only([KEY_D if gap > 0.0 else KEY_A] + ([KEY_CAPSLOCK] if absf(gap) > 90.0 else []))
		await frames(1)
		return
	await _strike(doctor, "", false)


## The stairs from floor 1: walk to their foot, W, then hold A up the flight to floor 2.
func climb() -> void:
	var flight: Dictionary = hospital.base_layout["stairs"]["side_flight"]
	var entry: Array = flight["lower_entry_x"]
	var foot := (float(entry[0]) + float(entry[1])) * 0.5
	await walk_to(foot)
	hold_only([])
	await frames(4)
	await tap(KEY_W)
	hold_only([KEY_A])
	for _index in range(600):
		await frames(1)
		if hero().global_position.x <= float(flight["upper_exit_x"]) - 2.0 and hero().is_on_floor():
			break
	hold_only([])
	await frames(8)


## Held A or D until the hero's feet pass x.
func walk_to(x: float, limit := 900) -> void:
	for _index in range(limit):
		var gap: float = x - hero().global_position.x
		if absf(gap) <= 2.0:
			break
		hold_only([KEY_D if gap > 0.0 else KEY_A] + ([KEY_CAPSLOCK] if absf(gap) > 60.0 else []))
		await frames(1)
	hold_only([])
