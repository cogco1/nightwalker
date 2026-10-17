extends Node
## A chapter night's fight in the side-view hospital (第一夜: the organ trade at 22:00), run by hospital_chapter.gd
## when the step names one (chapter1.json steps.d1_night.fight -> nights.night1). It
## - puts the night's people in the world from the chapter data (guards, gunners, buyers, doctors and the last
##   doctor) and wakes each one once the hero is on its floor within WAKE_DISTANCE;
## - keeps the hero's hit points (hero_vitals.gd, health_hud.gd): an enemy HIT takes attack.damage. At 0 the screen
##   washes red and goes black and the floor starts over: its people back at their posts, the hero at the floor's
##   start with full health. Lessons already met stay met;
## - teaches the fight with key icons only (tutorial_plate.gd): move, the light string, a heavy finisher, a dodge,
##   a perfect dodge and its counter, each met by doing it on a real enemy;
## - keeps the stairs shut until floor 1 is clear, and points the way with a chevron at the screen edge;
## - once only the last doctor is left and the hero comes near, plays his three lines; the next hit executes him (a
##   heavy freeze, a white frame, black) and the night goes on to the held breath.

const VITALS = preload("res://scripts/core/hero_vitals.gd")
const HEALTH_HUD = preload("res://scripts/ui/health_hud.gd")
const TUTORIAL = preload("res://scripts/ui/tutorial_plate.gd")
const STYLE = preload("res://scripts/ui/hud_style.gd")
const GAME_SESSION = preload("res://scripts/core/game_session.gd")
const KINDS := {
	"guard": preload("res://scripts/enemies/guard.gd"),
	"gunner": preload("res://scripts/enemies/gunner.gd"),
	"buyer": preload("res://scripts/enemies/buyer.gd"),
	"doctor": preload("res://scripts/enemies/doctor.gd"),
}
const LESSONS := ["move", "light", "heavy", "dodge", "perfect"]
## Native px of walking that meets the first lesson.
const MOVE_DISTANCE := 40.0
const LIGHT_STRING := [&"attack1", &"attack2", &"attack3", &"thrust4", &"spin5a", &"spin5b", &"shadow_slash"]
const HEAVY_MOVES := [&"rush_cleave", &"chase_cleave", &"launch_slash", &"spin_cleave_a", &"spin_cleave_b",
	&"rift_dive", &"leap_cleave_chop", &"heavy_slash", &"air_spin_a", &"air_spin_b", &"air_spin_c"]
## A missed attack counts as dodged for the lesson when the hero's dash started at most this long before.
const DODGE_WINDOW := 0.6
## Hits closer together than this take no more health (their knockback and stun still land).
const MERCY_SECONDS := 0.35
const WAKE_DISTANCE := 150.0
const LAST_WORDS_DISTANCE := 48.0
## Guards swing less often while the first three lessons run.
const LESSON_COOLDOWN := 2.4
const FLOOR_Y := {1: 286.0, 2: 164.0}
## Where the stairs are taken on each floor (the edge chevron points there once a floor is clear).
const STAIRS_X := {1: 162.0, 2: 30.0}

var chapter: Node
var hospital: Node2D
var story: Node
var data: Dictionary
var vitals: RefCounted
var health: Node
var tutorial: Node
## Edge chevron and the mouse over the last doctor, on the HUD canvas.
var pointer: Node2D
var execute_icon: Node2D
var enemies: Array[Node2D] = []
var bullets: Array[Node2D] = []
var dead_ids: Dictionary = {}
var last_doctor: Node2D
## Index of the current lesson in LESSONS (LESSONS.size() once all are met).
var lesson := 0
var moved := 0.0
var deaths := 0
## A story moment holds the night (going down, the last words, the execution).
var busy := false
var words_heard := false
var executed := false
## Lesson ids in the order they were met, and the health enemies have taken in all (tests read them).
var met: Array[String] = []
var damage_taken := 0
var pointer_target := Vector2.INF
var _player: CharacterBody2D
var _hero_x := 0.0
var _last_damage_at := -INF
var _clock := 0.0
var _next_lesson_pending := false
var _checkpoint_floor := 0


func _init(owner_chapter: Node, night: Dictionary) -> void:
	chapter = owner_chapter
	hospital = chapter.hospital
	story = chapter.story
	data = night
	name = "NightFight"


func _ready() -> void:
	process_physics_priority = 120
	var canvas: CanvasLayer = hospital.get_node("EnvironmentUI")
	vitals = VITALS.new(int(story.hero_max_hp))
	vitals.died.connect(_on_died)
	health = HEALTH_HUD.new()
	health.name = "HealthHud"
	add_child(health)
	health.build(canvas)
	health.bind(vitals)
	health.set_visible(true)
	tutorial = TUTORIAL.new()
	tutorial.name = "Tutorial"
	add_child(tutorial)
	tutorial.build(canvas)
	pointer = Node2D.new()
	pointer.name = "WayPointer"
	canvas.add_child(pointer)
	pointer.draw.connect(_draw_pointer)
	execute_icon = Node2D.new()
	execute_icon.name = "ExecuteIcon"
	canvas.add_child(execute_icon)
	execute_icon.draw.connect(_draw_execute_icon)
	on_view_activated()
	_show_lesson()
	var session := GAME_SESSION.of(hospital)
	if session != null:
		# The key caps name the current bindings.
		session.keybindings_closed.connect(func(_saved: bool) -> void: tutorial.relabel())


## The hospital (re)built its world: people back in it, the hero bound.
func on_view_activated() -> void:
	_bind_player()
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	_clear_bullets()
	if hospital.view_mode != 1:
		return
	for entry in data.get("enemies", []):
		if not dead_ids.has(String(entry["id"])):
			_spawn(entry)
	_set_checkpoint(hospital.floor_id)


func _bind_player() -> void:
	_player = hospital.player
	if not is_instance_valid(_player):
		return
	_hero_x = _player.global_position.x
	if not _player.attack_received.is_connected(_on_attack_received):
		_player.attack_received.connect(_on_attack_received)
		_player.hit_resolved.connect(_on_hit_resolved)


func _spawn(entry: Dictionary) -> Node2D:
	var body: Node2D = KINDS[String(entry["kind"])].new()
	var floor_number := int(entry.get("floor", 1))
	body.id = String(entry["id"])
	body.name = body.id
	body.position = Vector2(float(entry["x"]), FLOOR_Y[floor_number] - 1.0)
	body.facing = float(entry.get("faces", -1))
	if String(entry["kind"]) == "doctor":
		body.set("last", bool(entry.get("last", false)))
	hospital.world.add_child(body)
	body.bind_hero(_player)
	body.defeated.connect(_on_defeated)
	if body.has_signal("fired"):
		body.fired.connect(func(bullet: Node2D) -> void: bullets.append(bullet))
	if bool(entry.get("last", false)):
		last_doctor = body
	enemies.append(body)
	_pace_guards()
	return body


func living(include_last := true) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead and (include_last or enemy != last_doctor):
			result.append(enemy)
	return result


func floor_clear(floor_number: int) -> bool:
	for enemy in living(false):
		if enemy.floor_id == floor_number:
			return false
	return true


## Floor 1 must be clear before the stairs take the hero up; story moments hold them too.
func stairs_open() -> bool:
	return not busy and floor_clear(1)


func _set_checkpoint(floor_number: int) -> void:
	_checkpoint_floor = floor_number
	var start: Array = data.get("floors", {}).get(str(floor_number), {}).get("start", [])
	if start.size() == 2:
		chapter.checkpoint = Vector2(start[0], start[1])


# --- every frame -------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player) or hospital.view_mode != 1:
		return
	if hospital.floor_id != _checkpoint_floor and not hospital.stairs_busy and _player.is_on_floor():
		_set_checkpoint(hospital.floor_id)
	if LESSONS.size() > lesson and LESSONS[lesson] == "move" and not busy:
		moved += absf(_player.global_position.x - _hero_x)
		if moved >= MOVE_DISTANCE:
			_meet("move")
	_hero_x = _player.global_position.x
	if busy:
		return
	for enemy in living():
		if not enemy.active and enemy.hero_on_my_floor() and absf(enemy.hero_offset()) <= WAKE_DISTANCE:
			enemy.active = true
	if not words_heard and is_instance_valid(last_doctor) and not last_doctor.dead and living(false).is_empty() \
			and last_doctor.hero_on_my_floor() and absf(last_doctor.hero_offset()) <= LAST_WORDS_DISTANCE:
		_last_words()


func _process(delta: float) -> void:
	_clock += delta
	if _next_lesson_pending and not tutorial.ticking():
		_next_lesson_pending = false
		_show_lesson()
	for index in range(bullets.size() - 1, -1, -1):
		if not is_instance_valid(bullets[index]):
			bullets.remove_at(index)
	pointer_target = _way()
	pointer.queue_redraw()
	execute_icon.queue_redraw()


## Where the hero should head: the nearest person left on this floor, else the stairs, else the last doctor.
func _way() -> Vector2:
	if busy or not is_instance_valid(_player):
		return Vector2.INF
	var floor_number: int = hospital.floor_id
	var best := Vector2.INF
	var others := living(false)
	for enemy in (others if not others.is_empty() else living()):
		if enemy.floor_id != floor_number:
			continue
		var at: Vector2 = enemy.global_position
		if best == Vector2.INF or absf(at.x - _player.global_position.x) < absf(best.x - _player.global_position.x):
			best = at
	if best != Vector2.INF:
		return best
	if not others.is_empty() or (is_instance_valid(last_doctor) and not last_doctor.dead):
		var stairs_floor := floor_number
		return Vector2(STAIRS_X[stairs_floor], FLOOR_Y[stairs_floor])
	return Vector2.INF


# --- the hero's hits and the enemies' -----------------------------------------------------------

func _on_attack_received(result: int, attack: Dictionary) -> void:
	if busy:
		return
	if result == _player.AttackResult.HIT:
		var now: float = _player.combat_time
		if now - _last_damage_at >= MERCY_SECONDS:
			_last_damage_at = now
			damage_taken += vitals.damage(int(attack.get("damage", 0)))
		return
	if _lesson_id() == "dodge" and _player.seconds_since_dash() <= DODGE_WINDOW:
		_meet("dodge")


func _on_hit_resolved(target: Node, _damage: int, _critical: bool, kind: String) -> void:
	if not enemies.has(target):
		return
	match _lesson_id():
		"light":
			if _player.move_id in LIGHT_STRING:
				tutorial.set_progress(_player.combo_stage)
				if _player.combo_stage >= 3:
					_meet("light")
		"heavy":
			if _player.move_id in HEAVY_MOVES:
				_meet("heavy")
		"perfect":
			if kind == "counter":
				_meet("perfect")


func _on_defeated(enemy: Node2D) -> void:
	dead_ids[enemy.id] = true
	if enemy == last_doctor and words_heard:
		_execute.call_deferred()


# --- lessons -----------------------------------------------------------------------------------

func _lesson_id() -> String:
	return LESSONS[lesson] if lesson < LESSONS.size() and not _next_lesson_pending else ""


func _meet(id: String) -> void:
	if _lesson_id() != id:
		return
	met.append(id)
	lesson += 1
	tutorial.complete(lesson >= LESSONS.size())
	_next_lesson_pending = lesson < LESSONS.size()
	_pace_guards()


func _show_lesson() -> void:
	if lesson >= LESSONS.size():
		return
	tutorial.show_lesson(LESSONS[lesson], lesson, LESSONS.size())
	moved = 0.0


## Guards give room while the hero learns to move and strike; from the dodge on they swing at full pace.
func _pace_guards() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.kind == "guard":
			enemy.cooldown = LESSON_COOLDOWN if lesson < LESSONS.find("dodge") else KINDS["guard"].COOLDOWN


# --- going down -------------------------------------------------------------------------------

func _on_died() -> void:
	if busy:
		return
	busy = true
	deaths += 1
	var floor_number: int = hospital.floor_id
	_player.freeze(self)
	var session := GAME_SESSION.of(hospital)
	if session != null:
		session.cancel_hit_stop()
		session.end_slowmo()
	_hold(true)
	await chapter.overlay.death()
	restart_floor(floor_number)
	vitals.refill()
	_player.unfreeze(self)
	hospital.reset_view()
	_player.show_idle()
	_hold(false)
	await chapter.overlay.fade_from_black(0.5)
	busy = false


## The floor starts over: everyone on it back at their posts and asleep, flying bullets gone.
func restart_floor(floor_number: int) -> void:
	_clear_bullets()
	for enemy in enemies.duplicate():
		if enemy.floor_id == floor_number:
			enemies.erase(enemy)
			enemy.queue_free()
	for entry in data.get("enemies", []):
		if int(entry.get("floor", 1)) == floor_number:
			dead_ids.erase(String(entry["id"]))
			_spawn(entry)
	_set_checkpoint(floor_number)


func _hold(on: bool) -> void:
	for enemy in living():
		enemy.held = on
		if on and enemy.has_method("stand_down"):
			enemy.stand_down()


func _clear_bullets() -> void:
	for bullet in bullets:
		if is_instance_valid(bullet):
			bullet.queue_free()
	bullets.clear()


# --- the last doctor ---------------------------------------------------------------------------

func _last_words() -> void:
	busy = true
	_hold(true)
	_clear_bullets()
	last_doctor.active = true
	last_doctor.begging = true
	last_doctor.face_hero()
	var words: Dictionary = data.get("last_words", {})
	var box: Panel = hospital.interactions.dialogue
	box.open(words.get("lines", []), String(words.get("context", "")), _player, words.get("speakers", []), "doctor")
	await box.closed
	words_heard = true
	last_doctor.executable = true
	_hold(false)
	busy = false


func _execute() -> void:
	if executed:
		return
	executed = true
	busy = true
	_hold(true)
	var session := GAME_SESSION.of(hospital)
	if session != null:
		# The killing blow's own freeze gives way to the heavy one.
		session.cancel_hit_stop()
		session.hit_stop(&"heavy", Vector2(signf(last_doctor.global_position.x - _player.global_position.x), 0))
		if session.hit_stop_active:
			await session.hit_stop_finished
	_player.freeze(self)
	await chapter.overlay.execution()
	story.set_flag("night_done:" + String(data.get("id", "")))
	hospital.get_tree().root.get_node("SceneRoutes").call("travel", String(data.get("next", "")))


# --- HUD icons ---------------------------------------------------------------------------------

func _screen(point: Vector2) -> Vector2:
	return point - (hospital.camera.get_screen_center_position() - Vector2(160, 90))


func _draw_pointer() -> void:
	if pointer_target == Vector2.INF or not is_instance_valid(_player):
		return
	var at := _screen(pointer_target)
	if at.x >= 0.0 and at.x <= 320.0:
		return
	if fmod(_clock, 0.8) > 0.55:
		return
	var direction := 1.0 if at.x > 320.0 else -1.0
	var y := clampf(_screen(_player.global_position).y - 18.0, 20.0, 150.0)
	TUTORIAL.draw_pointer(pointer, Vector2(312.0 if direction > 0.0 else 4.0, y), direction, STYLE.CYAN)


func _draw_execute_icon() -> void:
	if not is_instance_valid(last_doctor) or not last_doctor.executable or last_doctor.dead or busy:
		return
	var at := _screen(last_doctor.global_position).round() + Vector2(-3, -38)
	TUTORIAL.draw_mouse(execute_icon, at, TUTORIAL.button_of("attack_mouse"), fmod(_clock, 0.5) < 0.3)
