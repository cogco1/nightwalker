extends "res://tests/support/isolated_suite.gd"
## Chapter 1, milestone 2: the first night's fight in the side-view hospital, piece by piece. Every verified action
## is real input (the keys and clicks of tests/support/night_bot.gd); between pieces the suite stages the scene
## directly (moves the hero, takes people out of the way). Covered: the night's people, health and its plate, the
## five icon-only lessons met by doing them, the begging doctor, a guard's swing and the mercy window, overheal,
## going down and the floor starting over, the stairs shut until floor 1 is clear, the buyer's flight, the gunner's
## laser sight and bullet (hit, jumped, ducked, perfect-dodged and countered), the climb to floor 2, the last
## doctor's protection, three lines and execution into the held breath, and a sandbox hospital with none of it.
## Test-Game runs it with "-- --nw-step=d1_night", so it enters through boot.tscn like Run-Game.ps1 -Step d1_night;
## without that argument it starts the chapter and travels to the night itself.

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const NIGHT_BOT = preload("res://tests/support/night_bot.gd")
const HEALTH_HUD = preload("res://scripts/ui/health_hud.gd")
const NIGHT_FIGHT = preload("res://scripts/levels/hospital/night_fight.gd")
const BOOT_SCRIPT = preload("res://scripts/core/boot.gd")
const BOOT := "res://scenes/boot.tscn"
const HOSPITAL := "res://scenes/underground_hospital.tscn"
const BREATH := "res://scenes/breath_interlude.tscn"

var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var story: Node
var routes: Node
var hospital: Node2D
var fight: Node
var bot: RefCounted
## The guard the hit, overheal and going-down pieces use; everyone else on floor 1 is held meanwhile.
var staged_guard: Node2D
## Every enemy attack result the hero took: [result, source id].
var results: Array = []
var _finished := false


func _initialize() -> void:
	create_timer(260.0, true).timeout.connect(func() -> void:
		check(false, "Night fight suite completes before its deadline")
		finish()
	)
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)


func frames(count := 1) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func wait_until(condition: Callable, limit := 240) -> bool:
	for _index in range(limit):
		if condition.call():
			return true
		await frames(1)
	return condition.call()


func arrive(path: String, limit := 600) -> bool:
	for _index in range(limit):
		if current_scene != null and current_scene.scene_file_path == path and not routes.switching:
			await frames(4)
			return true
		await frames(1)
	check(false, "arrives at " + path)
	return false


func hero() -> CharacterBody2D:
	return hospital.player


func enemy(id: String) -> Node2D:
	for body in fight.enemies:
		if is_instance_valid(body) and body.id == id:
			return body
	return null


## Staging: the hero stands at point facing a side, still (once any swing in progress is over).
func place(point: Vector2, facing := "right") -> void:
	var player := hero()
	bot.release_all()
	await wait_until(func() -> bool: return player.state == player.State.FREE and not player.is_frozen(), 120)
	player.position = point
	player.velocity = Vector2.ZERO
	player.facing = facing
	player.show_idle()
	hospital.follow_player()
	await frames(3)


## Staging: people taken out of the way.
func clear_out(ids: Array) -> void:
	for id in ids:
		var body := enemy(id)
		if body != null and not body.dead:
			body.take_damage(99)
	await frames(2)


func living_on(floor_number: int) -> Array:
	return fight.living(false).filter(func(body: Node2D) -> bool: return body.floor_id == floor_number)


func last_result() -> int:
	return int(results[-1][0]) if not results.is_empty() else -1


## Every Label under a node (the lesson plate's words, if it had any).
func label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for child in node.find_children("*", "Label", true, false):
		texts.append((child as Label).text)
	return texts


func run() -> void:
	routes = root.get_node("SceneRoutes")
	CONTROLS.install()
	story = STORY_STATE.ensure(self)
	check(BOOT_SCRIPT.requested_step(PackedStringArray(["--nw-debug", "--nw-step=d1_night"])) == "d1_night"
		and BOOT_SCRIPT.requested_step(PackedStringArray(["--nw-debug"])) == "", "the boot reads --nw-step=<id> among the user arguments")
	var via_boot := BOOT_SCRIPT.requested_step(OS.get_cmdline_user_args()) == "d1_night"
	observations["entry"] = BOOT if via_boot else "travel"
	if via_boot:
		var boot: Node = load(BOOT).instantiate()
		root.add_child(boot)
		current_scene = boot
	else:
		story.start_chapter()
		routes.travel("d1_night")
	if not await arrive(HOSPITAL):
		finish()
		return
	hospital = current_scene
	fight = hospital.chapter.fight
	if via_boot:
		check(story.chapter_active and story.step == "d1_night" and story.day == 1 and story.clock_text() == "22:00" and not story.debug_keys,
			"-Step d1_night: the boot starts the chapter at the first night, 7/27 22:00, debug keys off")
	bot = NIGHT_BOT.new(self)
	bot.bind(hospital)
	hero().attack_received.connect(func(result: int, attack: Dictionary) -> void:
		var source: Variant = attack.get("source")
		results.append([result, String(source.get("id")) if is_instance_valid(source) else ""]))
	await night_setup()
	await lesson_move()
	await begging_doctor()
	await lessons_fight()
	await guard_hit()
	await overheal()
	await going_down()
	await stairs_shut()
	await jump_under_floor_two()
	await buyer_flees()
	await gunner()
	await up_the_stairs()
	await last_doctor()
	await sandbox()
	finish()


func night_setup() -> void:
	check(fight != null and fight.get_script() == NIGHT_FIGHT, "the night's step runs its fight")
	var kinds := {}
	for body in fight.enemies:
		kinds[body.kind] = int(kinds.get(body.kind, 0)) + 1
	check(kinds.get("guard") == 3 and kinds.get("gunner") == 3 and kinds.get("buyer") == 2 and kinds.get("doctor") == 3,
		"the organ trade: 3 guards, 3 gunners, 2 buyers, 3 doctors: " + str(kinds))
	var last: Node2D = fight.last_doctor
	check(last != null and last.id == "office_doctor" and last.floor_id == 2 and last.last and not last.can_be_hurt(),
		"one last doctor upstairs, not to be hurt yet")
	check(fight.enemies.all(func(body: Node2D) -> bool: return not body.active), "everyone starts at their post, unaware")
	check(fight.health.plate.visible and fight.vitals.hp == 100 and fight.vitals.max_hp == 100, "the health plate shows a full 100")
	var chapter: Node = hospital.chapter
	check(not chapter.hud.plate.visible, "the night has no stealth meter in the health plate's place")
	var hud: Node = chapter.chapter_hud
	check(hud.place_label.text == "地下医院 1F" and hud.clock_label.text == "22:00" and hud.goal_label.text == "" and hud.status.size.y == 15.0,
		"the status plate has the place and 22:00 and no goal words")
	var items: Array = hospital.interactions._all_interactions()
	check(not items.is_empty() and items.all(func(item: Dictionary) -> bool: return item.get("kind") == "stairs"),
		"nothing to read at night: only the stairs answer E")
	check(not fight.stairs_open() and not chapter.stairs_open(), "the stairs are shut while floor 1 is not clear")
	check(fight.tutorial.plate.visible and fight.tutorial.lesson == "move" and str(fight.tutorial.icons) == str(["key:A", "key:D"]),
		"the first lesson shows the A and D key caps: " + str(fight.tutorial.icons))


## Lesson words: only key names on caps, never sentences.
func icons_only(lesson: String) -> void:
	var words := label_texts(fight.tutorial.plate)
	var keys := RegEx.create_from_string("^[A-Za-z0-9]+$")
	check(words.all(func(text: String) -> bool: return keys.search(text) != null), lesson + ": the plate has key names only: " + str(words))


func lesson_move() -> void:
	icons_only("move")
	# Rebound in the settings menu: the caps follow.
	CONTROLS.current["move_left"] = KEY_J
	hospital.get_node("GameSession").keybindings_closed.emit(true)
	check(str(fight.tutorial.icons) == str(["key:J", "key:D"]) and fight.tutorial.lesson == "move", "rebinding renames the lesson's key caps: " + str(fight.tutorial.icons))
	CONTROLS.current["move_left"] = KEY_A
	hospital.get_node("GameSession").keybindings_closed.emit(true)
	var start := hero().position.x
	bot.key(KEY_D, true)
	var met := await wait_until(func() -> bool: return fight.met.has("move"), 120)
	bot.key(KEY_D, false)
	check(met and hero().position.x - start >= NIGHT_FIGHT.MOVE_DISTANCE - 1.0, "holding D 40 px meets the move lesson")
	check(fight.tutorial.ticking() and fight.tutorial.progress == fight.tutorial.needed, "a met lesson ticks before the next")
	await wait_until(func() -> bool: return fight.tutorial.lesson == "light" and not fight.tutorial.ticking(), 90)
	check(str(fight.tutorial.icons) == str(["mouse:left", "pips:3"]), "the light lesson shows the mouse's left button and 3 pips: " + str(fight.tutorial.icons))
	icons_only("light")
	check(enemy("ward_guard_1").cooldown == NIGHT_FIGHT.LESSON_COOLDOWN, "guards give room while the first lessons run")


func begging_doctor() -> void:
	var doctor := enemy("ward_doctor")
	await place(Vector2(doctor.position.x - 70, 286))
	check(await wait_until(func() -> bool: return doctor.active and not doctor.begging and doctor.velocity.x > 0.0, 60),
		"the doctor backs away from the hero")
	bot.key(KEY_D, true)
	await wait_until(func() -> bool: return doctor.begging, 120)
	bot.key(KEY_D, false)
	check(doctor.begging and doctor.pose() == "beg" and absf(doctor.position.x - hero().position.x) <= doctor.KNEEL + 1.0,
		"close up the doctor kneels with his hands up")
	check(doctor.get_node_or_null("Attacker") == null and not doctor.has_signal("fired"), "the doctor has no attack at all")
	await frames(60)
	check(results.all(func(entry: Array) -> bool: return entry[1] != doctor.id), "the begging doctor never strikes")
	await bot.walk_to(doctor.position.x - 16.0)
	for _index in range(6):
		if doctor.dead:
			break
		bot._face(1.0)
		await frames(1)
		bot.hold_only([])
		await bot.click()
		await frames(9)
	check(doctor.dead and doctor.collision_layer == 0 and doctor.pose() == "dead", "two cuts and the doctor lies dead, out of reach of further hits")
	check(fight.dead_ids.has(doctor.id), "the night counts him")


func lessons_fight() -> void:
	var guard := enemy("ward_guard_1")
	# The light string: three hits in one string.
	var seen: Array[int] = []
	for _index in range(30):
		if fight.met.has("light"):
			break
		var gap: float = guard.position.x - hero().position.x if not guard.dead else 0.0
		if guard.dead:
			guard = fight.living(false).filter(func(body: Node2D) -> bool: return body.kind == "guard")[0]
			continue
		if absf(gap) > 26.0:
			await bot.walk_to(guard.position.x - 18.0 * signf(gap))
		bot._face(signf(guard.position.x - hero().position.x))
		await frames(1)
		bot.hold_only([])
		await bot.click()
		await frames(8)
		if not seen.has(fight.tutorial.progress):
			seen.append(fight.tutorial.progress)
	check(fight.met.has("light") and seen.max() == 3 and seen.min() < 3, "three light hits in a string meet the light lesson, the pips filling: " + str(seen))
	await wait_until(func() -> bool: return fight.tutorial.lesson == "heavy" and not fight.tutorial.ticking(), 90)
	check(str(fight.tutorial.icons) == str(["mouse:left", "then", "mouse:right", "pips:1"]), "the heavy lesson shows left, then right: " + str(fight.tutorial.icons))
	icons_only("heavy")
	var heavy_move: Array = []
	hero().move_started.connect(func(id: StringName) -> void: heavy_move.append(id))
	for _index in range(8):
		if fight.met.has("heavy"):
			break
		if guard.dead:
			guard = fight.living(false).filter(func(body: Node2D) -> bool: return body.kind == "guard")[0]
		await bot.walk_to(guard.position.x - 18.0 * signf(guard.position.x - hero().position.x))
		bot._face(signf(guard.position.x - hero().position.x))
		await frames(1)
		bot.hold_only([])
		await bot.click(MOUSE_BUTTON_LEFT)
		await frames(8)
		await bot.click(MOUSE_BUTTON_RIGHT)
		await frames(30)
	check(fight.met.has("heavy") and heavy_move.any(func(id: StringName) -> bool: return id in NIGHT_FIGHT.HEAVY_MOVES),
		"a left click then a right click finishes with a heavy move: " + str(heavy_move))
	await wait_until(func() -> bool: return fight.tutorial.lesson == "dodge" and not fight.tutorial.ticking(), 90)
	check(str(fight.tutorial.icons) == str(["warn", "then", "key:Shift", "pips:1"]), "the dodge lesson shows the warning, then Shift: " + str(fight.tutorial.icons))
	icons_only("dodge")
	check(fight.enemies.filter(func(body: Node2D) -> bool: return body.kind == "guard").all(func(body: Node2D) -> bool: return body.cooldown == body.COOLDOWN),
		"from the dodge lesson on guards swing at full pace")
	var before := results.size()
	check(await bot.play(func() -> bool: return fight.met.has("dodge"), 900), "Shift as a guard's baton comes down meets the dodge lesson")
	var dodged: Array = results.slice(before).map(func(entry: Array) -> int: return entry[0])
	check(dodged.has(hero().AttackResult.PERFECT) or dodged.has(hero().AttackResult.EVADE), "the lesson was met by a real dodge: " + str(dodged))
	await wait_until(func() -> bool: return fight.tutorial.lesson == "perfect" and not fight.tutorial.ticking(), 90)
	check(str(fight.tutorial.icons) == str(["warn", "then", "key:Shift", "then", "mouse:left", "pips:1"]),
		"the perfect lesson shows the warning, Shift, then the left button: " + str(fight.tutorial.icons))
	icons_only("perfect")
	var counters_before: int = bot.tally["counters"]
	check(await bot.play(func() -> bool: return fight.met.has("perfect"), 900), "a perfect dodge and a click meet the last lesson")
	check(bot.tally["counters"] > counters_before, "the counter came from a click in the slow motion")
	check(str(fight.met) == str(NIGHT_FIGHT.LESSONS), "the lessons were met in order: " + str(fight.met))
	check(await wait_until(func() -> bool: return not fight.tutorial.plate.visible, 90), "after the last tick the lesson plate goes")
	observations["lessons"] = {"frames": bot.frames_run, "tally": bot.tally.duplicate()}


## Staging: everyone on floor 1 but `keep` stands still.
func hold_floor_one_but(keep: Node2D) -> void:
	for body in living_on(1):
		body.held = body != keep
		if body.held and body.has_method("stand_down"):
			body.stand_down()


func guard_hit() -> void:
	var guard: Node2D = null
	for body in living_on(1):
		if body.kind == "guard":
			guard = body
			break
	if guard == null:
		var entry: Dictionary = fight.data["enemies"][0]
		fight.dead_ids.erase(String(entry["id"]))
		guard = fight._spawn(entry)
	staged_guard = guard
	hold_floor_one_but(guard)
	await frames(20)
	await place(Vector2(guard.position.x - 22.0, 286))
	guard.active = true
	var hp_before: int = fight.vitals.hp
	var before := results.size()
	var x_before := hero().position.x
	check(await wait_until(func() -> bool: return results.size() > before, 240), "a guard by a still hero swings")
	check(int(results[before][0]) == hero().AttackResult.HIT and fight.vitals.hp == hp_before - guard.DAMAGE,
		"a swing that lands takes 10 health: %d -> %d" % [hp_before, fight.vitals.hp])
	check(fight.health.trail > fight.vitals.ratio() and fight.health._ring_left > 0.0, "the plate rings red and a red trail shows what was lost")
	await frames(16)
	var pushed := absf(hero().position.x - x_before)
	check(pushed >= 12.0 and pushed <= 28.0, "the swing knocks the hero about 22 px back: %.1f" % pushed)
	var hp_mid: int = fight.vitals.hp
	fight._last_damage_at = hero().combat_time
	fight._on_attack_received(hero().AttackResult.HIT, {"damage": 10})
	check(fight.vitals.hp == hp_mid, "a second hit inside 0.35 s takes nothing more (it still stuns)")
	check(await wait_until(func() -> bool: return fight.health.trail <= fight.vitals.ratio() + 0.001, 150), "the red trail drains down to the bar")


func overheal() -> void:
	fight.vitals.grant_overheal(30)
	check(fight.vitals.overheal == 30 and HEALTH_HUD.columns(30.0 / 100.0) == 15, "overheal (milestone 3's vodka) adds an amber strip of 15 px")
	var guard := staged_guard
	await frames(80)
	await place(Vector2(guard.position.x - 22.0, 286))
	var hp_before: int = fight.vitals.hp
	var before := results.size()
	await wait_until(func() -> bool: return results.size() > before and int(results[-1][0]) == hero().AttackResult.HIT, 300)
	check(fight.vitals.overheal == 20 and fight.vitals.hp == hp_before, "a hit eats the overheal first: 30 -> %d, health kept at %d" % [fight.vitals.overheal, fight.vitals.hp])


func going_down() -> void:
	var lesson_before: int = fight.lesson
	var floor_one_entries := (fight.data["enemies"] as Array).filter(func(entry: Dictionary) -> bool: return int(entry["floor"]) == 1)
	var guard := staged_guard
	await frames(40)
	# 5 health and 3 overheal left: the next swing (10) is the last.
	fight.vitals.hp = 5
	fight.vitals.overheal = 3
	await place(Vector2(guard.position.x - 22.0, 286))
	check(await wait_until(func() -> bool: return fight.busy and fight.deaths == 1, 300), "a hit at 5 health and 3 overheal puts the hero down")
	check(hospital.chapter.overlay.shown.has("death") and hero().is_frozen(), "the screen washes red and goes black with the hero held")
	check(await wait_until(func() -> bool: return not fight.busy, 300), "the floor starts over")
	var start: Array = fight.data["floors"]["1"]["start"]
	check(hero().position.distance_to(Vector2(start[0], start[1])) < 1.0 and hospital.chapter.checkpoint == Vector2(start[0], start[1]),
		"the hero is back at the start of floor 1")
	check(fight.vitals.hp == fight.vitals.max_hp and fight.vitals.overheal == 0 and not fight.vitals.dead, "with full health and no overheal")
	var back := living_on(1)
	check(back.size() == floor_one_entries.size(), "everyone on floor 1 is back: %d of %d" % [back.size(), floor_one_entries.size()])
	var at_posts := true
	for entry: Dictionary in floor_one_entries:
		var body := enemy(String(entry["id"]))
		at_posts = at_posts and body != null and absf(body.position.x - float(entry["x"])) <= 1.0 and not body.active and body.hp == body.max_hp
	check(at_posts, "at their posts, unaware and unhurt")
	check(fight.lesson == lesson_before and fight.met.size() == NIGHT_FIGHT.LESSONS.size() and not fight.tutorial.plate.visible,
		"the lessons already met stay met")
	check(fight.bullets.is_empty() and not hero().is_frozen(), "no bullet is left flying and the hero is free")
	observations["deaths"] = fight.deaths


func stairs_shut() -> void:
	var flight: Dictionary = hospital.base_layout["stairs"]["side_flight"]
	var entry: Array = flight["lower_entry_x"]
	await bot.walk_to((float(entry[0]) + float(entry[1])) * 0.5)
	await frames(4)
	check(hero().position.x >= float(entry[0]) and hero().position.x <= float(entry[1]) and hero().is_on_floor(), "the hero stands at the foot of the stairs")
	await bot.tap(KEY_W)
	check(not hospital._using_stairs and hospital.floor_id == 1, "W at the foot of the stairs does nothing while floor 1 is not clear")
	check(hospital.chapter._prompt_title() == "", "and no key cap offers them")


## A double jump on floor 1 right under the upstairs gunner reaches y ~206 (above the old 225 split); it must not
## count as floor 2 and wake him.
func jump_under_floor_two() -> void:
	var upstairs := enemy("reception_gunner")
	await place(Vector2(upstairs.position.x, 286), "right")
	var highest := hero().position.y
	await bot.tap(KEY_SPACE)
	for _index in range(40):
		highest = minf(highest, hero().position.y)
		if hero().velocity.y >= -5.0:
			break
		await frames(1)
	await bot.tap(KEY_SPACE)
	for _index in range(60):
		highest = minf(highest, hero().position.y)
		await frames(1)
	check(highest < 225.0 and highest > 174.0, "a double jump on floor 1 rises to y %.0f under the floor-2 slab" % highest)
	check(not upstairs.active and not upstairs.aiming() and living_on(2).all(func(body: Node2D) -> bool: return not body.active),
		"nobody upstairs wakes to a hero jumping below")
	await wait_until(func() -> bool: return hero().is_on_floor(), 60)


func buyer_flees() -> void:
	await clear_out(["ward_guard_1", "ward_guard_2", "ward_doctor", "storage_guard"])
	var buyer := enemy("storage_buyer")
	var gunner := enemy("storage_gunner")
	gunner.held = true
	await place(Vector2(buyer.position.x - 80.0, 286))
	var x0 := buyer.position.x
	await frames(45)
	check(buyer.active and buyer.position.x > x0 + 20.0 and buyer.pose().begins_with("run"), "the buyer runs from the hero")
	check(await wait_until(func() -> bool: return buyer.cowering, 300), "until the wall stops him")
	check(buyer.pose() == "cower" and buyer.position.x >= 610.0, "he cowers against the end wall: x %.0f" % buyer.position.x)
	check(results.all(func(record: Array) -> bool: return record[1] != buyer.id), "the buyer never strikes")
	for _index in range(12):
		if buyer.dead:
			break
		await bot.walk_to(buyer.position.x - 16.0)
		bot._face(1.0)
		await frames(1)
		bot.hold_only([])
		await bot.click()
		await frames(9)
	check(buyer.dead, "cornered, he falls")
	gunner.held = false


func gunner() -> void:
	var gunner := enemy("storage_gunner")
	gunner.held = true
	gunner.stand_down()
	await place(Vector2(470, 286), "right")
	gunner.active = true
	gunner.held = false
	var session: Node = hospital.get_node("GameSession")
	# The laser sight, then the shot.
	check(await wait_until(func() -> bool: return gunner.aiming(), 300), "the gunner raises his pistol")
	var aim_frames := 0
	var locked_frames := 0
	var sight_on_hero := true
	var facing_locked: float = 0.0
	var turned_while_locked := false
	var shots: int = gunner.shots_fired
	while gunner.aiming() and aim_frames < 120:
		aim_frames += 1
		var box: Rect2 = hero().hurtbox()
		sight_on_hero = sight_on_hero and absf(gunner.sight_end.x - box.end.x) <= 1.0
		if gunner.locked():
			if locked_frames == 0:
				facing_locked = gunner.facing
			turned_while_locked = turned_while_locked or gunner.facing != facing_locked
			locked_frames += 1
		await frames(1)
	check(absi(aim_frames - 48) <= 2 and gunner.shots_fired == shots + 1, "the laser sight warns for 0.8 s before the shot: %d frames" % aim_frames)
	check(absi(locked_frames - 15) <= 2 and not turned_while_locked, "the last 0.25 s it holds still and blinks: %d frames" % locked_frames)
	check(sight_on_hero, "the sight ends on the hero's body")
	check(not fight.bullets.is_empty() and absf(fight.bullets[-1].global_position.y - (gunner.position.y + gunner.MUZZLE.y)) < 0.01,
		"the bullet flies level from the muzzle")
	# Standing still: hit.
	var hp_before: int = fight.vitals.hp
	var before := results.size()
	check(await wait_until(func() -> bool: return results.size() > before, 90), "the bullet reaches the hero")
	check(last_result() == hero().AttackResult.HIT and fight.vitals.hp == hp_before - gunner.DAMAGE, "a bullet takes 15 health")
	# Jumped.
	await dodge_bullet(gunner, "jump")
	# Ducked.
	await dodge_bullet(gunner, "duck")
	# Perfect dodge and the counter blink to the gunner.
	await wait_until(func() -> bool: return fight.bullets.is_empty() or fight.bullets.all(func(b: Node2D) -> bool: return not is_instance_valid(b) or b.resolved), 120)
	await place(Vector2(gunner.position.x - 110.0, 286), "right")
	hp_before = fight.vitals.hp
	before = results.size()
	var shots_before: int = gunner.shots_fired
	await wait_until(func() -> bool: return gunner.shots_fired > shots_before, 400)
	var coming: Array = []
	await wait_until(func() -> bool:
		coming = bot.bullet_coming()
		return not coming.is_empty() and coming[1] <= bot.BULLET_DODGE, 120)
	await bot._dash_toward(1.0)
	check(await wait_until(func() -> bool: return results.size() > before, 60), "the bullet meets the dashing hero")
	check(last_result() == hero().AttackResult.PERFECT and session.slowmo_active and fight.vitals.hp == hp_before,
		"Shift just before the bullet is a perfect dodge into the slow motion")
	var gunner_hp: int = gunner.hp
	var countered: Array = []
	hero().counter_started.connect(func(target: Node2D) -> void: countered.append(target), CONNECT_ONE_SHOT)
	await bot.click()
	check(countered.size() == 1 and countered[0] == gunner, "a click counters the gunner who fired")
	await wait_until(func() -> bool: return gunner.hp < gunner_hp or gunner.dead, 40)
	check(absf(hero().position.x - gunner.position.x) <= 24.0 and (gunner.dead or gunner.hp <= gunner_hp - 3), "the counter blinks to him and cuts for 3")
	check(await wait_until(func() -> bool: return not session.slowmo_active, 90), "the counter's hit ends the slow motion")
	for _index in range(10):
		if gunner.dead:
			break
		bot._face(signf(gunner.position.x - hero().position.x))
		await frames(1)
		bot.hold_only([])
		await bot.click()
		await frames(9)
	check(gunner.dead and living_on(1).is_empty(), "floor 1 is clear")


## The next bullet, avoided without the dash: jumped over or ducked under; contact false is an EVADE.
func dodge_bullet(gunner: Node2D, how: String) -> void:
	await place(Vector2(gunner.position.x - 110.0, 286), "right")
	var hp_before: int = fight.vitals.hp
	var before := results.size()
	var shots_before: int = gunner.shots_fired
	if how == "duck":
		bot.key(KEY_S, true)
	await wait_until(func() -> bool: return gunner.shots_fired > shots_before, 400)
	if how == "jump":
		var coming: Array = []
		await wait_until(func() -> bool:
			coming = bot.bullet_coming()
			return not coming.is_empty() and coming[1] <= 60.0, 120)
		await bot.tap(KEY_SPACE)
	check(await wait_until(func() -> bool: return results.size() > before, 120), how + ": the bullet passes the hero")
	if how == "duck":
		bot.key(KEY_S, false)
	check(last_result() == hero().AttackResult.EVADE and fight.vitals.hp == hp_before, how + ": an evade, no health lost")
	await wait_until(func() -> bool: return hero().is_on_floor(), 60)


func up_the_stairs() -> void:
	check(fight.stairs_open() and hospital.chapter.stairs_open(), "a clear floor 1 opens the stairs")
	await bot.climb()
	var start: Array = fight.data["floors"]["2"]["start"]
	check(hospital.floor_id == 2 and absf(hero().position.y - 164.0) < 1.0, "W and A climb to floor 2")
	check(hospital.chapter.checkpoint == Vector2(start[0], start[1]), "floor 2 starts over at the top of the stairs")
	check(hospital.chapter.chapter_hud.place_label.text == "地下医院 2F", "the status plate follows the floor")


func last_doctor() -> void:
	var doctor: Node2D = fight.last_doctor
	var others := living_on(2)
	for body in others:
		body.held = true
	await place(Vector2(doctor.position.x - 18.0, 164), "right")
	var hits := 0
	hero().hit_resolved.connect(func(target: Node, _damage: int, _critical: bool, _kind: String) -> void:
		if target == doctor:
			hits += 1)
	await bot.click()
	await frames(12)
	await bot.click()
	await frames(12)
	check(doctor.hp == doctor.max_hp and not doctor.dead and hits == 0, "while others live the last doctor cannot be hurt")
	check(not fight.words_heard and not hospital.interactions.dialogue.active, "and does not speak")
	await place(Vector2(doctor.position.x - 90.0, 164), "right")
	await clear_out(others.map(func(body: Node2D) -> String: return body.id))
	var box: Panel = hospital.interactions.dialogue
	bot.key(KEY_D, true)
	await wait_until(func() -> bool: return box.active, 150)
	bot.key(KEY_D, false)
	var words: Dictionary = fight.data["last_words"]
	check(box.active and fight.busy and hero().is_frozen(), "alone with the hero the last doctor speaks; the hero is held")
	check(str(box.pages) == str(words["lines"]) and box.page_speakers.all(func(speaker: String) -> bool: return speaker == "doctor"),
		"his three lines, all his: " + str(box.pages))
	check(box.title.text == "医生 · 地下医院" and doctor.pose() == "beg", "captioned 医生 · 地下医院, on his knees")
	var turned := 0
	while box.active and turned < 12:
		await bot.tap(KEY_E)
		turned += 1
	check(not box.active and fight.words_heard and doctor.executable and doctor.can_be_hurt(), "E turns the lines; then he can be executed")
	check(not fight.busy and not hero().is_frozen(), "the hero is free to strike")
	var session: Node = hospital.get_node("GameSession")
	var freezes: Array = []
	session.hit_stop_finished.connect(func(count: int) -> void: freezes.append(count))
	var chapter: Node = hospital.chapter
	await bot.walk_to(doctor.position.x - 16.0)
	bot._face(1.0)
	await frames(1)
	bot.hold_only([])
	await bot.click()
	check(await wait_until(func() -> bool: return doctor.dead, 30), "one cut executes him")
	check(await wait_until(func() -> bool: return freezes.has(10), 60), "a heavy freeze holds the blow: " + str(freezes))
	check(await wait_until(func() -> bool: return chapter.overlay.shown.has("execution"), 60), "then a white frame and black")
	check(story.has_flag("night_done:night1") or await wait_until(func() -> bool: return story.has_flag("night_done:night1"), 120), "the night is done")
	check(await arrive(BREATH), "the night goes on to the held breath")
	check(story.step == "d1_breath", "the story steps to the breath")


func sandbox() -> void:
	story.end_chapter()
	change_scene_to_file(HOSPITAL)
	await frames(8)
	hospital = current_scene
	check(hospital != null and hospital.chapter == null, "the sandbox hospital runs no chapter")
	hospital.switch_view()
	await frames(4)
	check(hospital.view_mode == 1 and hospital.world.get_children().all(func(node: Node) -> bool: return not node.has_method("figure")),
		"its side view has nobody in it")
	check(hospital.find_children("HealthPlate", "", true, false).is_empty(), "and no health plate")
	check(hospital.interactions._all_interactions().any(func(item: Dictionary) -> bool: return item.get("id") == "exit_panel"),
		"and its exit panel still answers E")


func finish() -> void:
	if _finished:
		return
	_finished = true
	if bot != null:
		bot.release_all()
	observations["results"] = results.size()
	var report := {"suite": "night_fight", "checks": checks, "failures": failures, "observations": observations,
		"status": "passed" if failures.is_empty() else "failed"}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
