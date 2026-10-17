extends "res://tests/support/isolated_suite.gd"
## Chapter 1, milestone 1, played start to finish with real input: the boot scene starts the story, the title
## card and the opening play in 601 at 12:00, the computer takes Coburn's job, the door leaves for the hospital,
## light locks the hero on, the breaker darkens the clinic, the roster gives the door code, Coburn falls from
## behind, the exit returns home at 14:50, the shop takes an order, the bed sleeps to the 22:00 rampage, the
## night hospital (side view) ends at its exit in the held-breath interlude, and day 2 wakes at 11:00 with the
## 7/27 news and Morwen's job. Every walk is held WASD along a route found on the real colliders; nothing is
## teleported. F7 / F8 / Tab stay inert inside the chapter.

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const BOOT := "res://scenes/boot.tscn"
const MAIN := "res://scenes/main.tscn"
const HOME := "res://scenes/home_601.tscn"
const HOSPITAL := "res://scenes/underground_hospital.tscn"
const BREATH := "res://scenes/breath_interlude.tscn"
const STREET := "res://scenes/night_street_proto.tscn"
const STEPS := [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]
const MARGIN := [Vector2.ZERO, Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5)]

var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
var story: Node
var routes: Node
var _held_key := 0
var _finished := false
var _walk_frames := 0


func _initialize() -> void:
	create_timer(280.0, true).timeout.connect(func() -> void:
		check(false, "Chapter flow completes before the deadline")
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


func key(code: int, pressed: bool, character := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = character
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(code: int, character := 0) -> void:
	key(code, true, character)
	await frames(2)
	key(code, false, character)
	await frames(3)


func hold(code: int) -> void:
	if code == _held_key:
		return
	if _held_key != 0:
		key(_held_key, false)
	_held_key = code
	if code != 0:
		key(code, true)


func player() -> CharacterBody2D:
	return current_scene.get("player") if current_scene != null else null


func arrive(path: String, label: String, limit := 600) -> bool:
	for _index in range(limit):
		if current_scene != null and current_scene.scene_file_path == path and not routes.switching:
			await frames(4)
			return true
		await frames(1)
	check(false, label + " arrives at " + path)
	return false


# --- real-input walking on the actual colliders -------------------------------------------------

func clear_at(point: Vector2) -> bool:
	var body := player()
	var shape := body.get_node("BodyShape") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	var space := body.get_world_2d().direct_space_state
	for offset in MARGIN:
		query.transform = Transform2D(0, point + offset + shape.position)
		if not space.intersect_shape(query, 1).is_empty():
			return false
	return true


## Breadth-first route on a 2px lattice from the hero to the first clear point the goal accepts; returns corners.
func route(goal: Callable) -> Array[Vector2]:
	var start := player().position.round()
	var parents := {start: start}
	var queue: Array[Vector2] = [start]
	var cursor := 0
	var found := Vector2.INF
	while cursor < queue.size() and cursor < 90000:
		var point := queue[cursor]
		cursor += 1
		if goal.call(point):
			found = point
			break
		for step in STEPS:
			var candidate: Vector2 = point + step
			if parents.has(candidate) or not clear_at(candidate):
				continue
			parents[candidate] = point
			queue.append(candidate)
	if found == Vector2.INF:
		observations["failed_route"] = {"from": [start.x, start.y], "explored": cursor}
		return []
	var path: Array[Vector2] = [found]
	while path[-1] != start:
		path.append(parents[path[-1]])
	path.reverse()
	var corners: Array[Vector2] = []
	for index in range(1, path.size() - 1):
		if path[index] - path[index - 1] != path[index + 1] - path[index]:
			corners.append(path[index])
	corners.append(found)
	return corners


func move_to(point: Vector2) -> bool:
	for _attempt in range(55):
		var delta: Vector2 = point - player().position
		if delta.length() <= 0.6:
			return true
		var horizontal := absf(delta.x) >= absf(delta.y)
		var distance := absf(delta.x) if horizontal else absf(delta.y)
		var code := (KEY_D if delta.x > 0 else KEY_A) if horizontal else (KEY_S if delta.y > 0 else KEY_W)
		hold(code)
		if distance > 3.0:
			var still := 0
			var previous: Vector2 = player().position
			for _tick in range(600):
				await frames()
				_walk_frames += 1
				still = still + 1 if player().position.distance_to(previous) < 0.01 else 0
				previous = player().position
				if still >= 12:
					hold(0)
					await frames(6)
					return false
				var remaining: float = absf(point.x - player().position.x) if horizontal else absf(point.y - player().position.y)
				if remaining <= 2.0:
					break
		else:
			await frames(1 if distance < 1.4 else 2)
		hold(0)
		await frames(6)
		_walk_frames += 6
	return false


func walk(goal: Callable, label: String) -> bool:
	var corners := route(goal)
	if corners.is_empty():
		check(false, "a real route exists to " + label)
		return false
	for corner in corners:
		if not await move_to(corner):
			check(false, "held keys reach " + label + " (stuck near " + str(player().position) + ")")
			return false
	check(true, "held keys reach " + label)
	return true


## Home: the interaction the safehouse itself would pick at a point, with a pixel and a half to spare against
## its radius and the next candidate, so stopping a fraction short still picks it.
func home_pick(point: Vector2) -> String:
	var best := INF
	var second := INF
	var chosen := ""
	var spare := false
	for item in current_scene.layout["interactions"]:
		var distance := point.distance_to(Vector2(item["anchor"][0], item["anchor"][1]))
		if distance > float(item["radius"]):
			continue
		if distance < best:
			second = best
			best = distance
			chosen = String(item["id"])
			spare = distance <= float(item["radius"]) - 1.5
		elif distance < second:
			second = distance
	return chosen if spare and second - best >= 1.5 else ""


func walk_home(id: String) -> bool:
	if not await walk(func(point: Vector2) -> bool: return home_pick(point) == id, "home " + id):
		return false
	await frames(2)
	if current_scene.nearest_interaction != id:
		observations["pick_" + id] = [player().position.x, player().position.y, current_scene.nearest_interaction, home_pick(player().position)]
	check(current_scene.nearest_interaction == id, "the safehouse offers " + id + " where the hero stands")
	return current_scene.nearest_interaction == id


func walk_hospital(id: String, anchor: Vector2, radius := 20.0, extra := Callable()) -> bool:
	var hospital := current_scene
	var item: Dictionary = hospital.interactions._find_interaction(id)
	var room := String(item.get("room_id", ""))
	var goal := func(point: Vector2) -> bool:
		if point.distance_to(anchor) > radius:
			return false
		if not room.is_empty() and String(item.get("kind", "")) != "stairs" and hospital.room_for_position(point, 0) != room:
			return false
		return extra.is_null() or extra.call(point)
	return await walk(goal, "hospital " + id)


# --- reading -----------------------------------------------------------------------------------

## Turns every page of the open reading with E; returns the pages it showed.
func read_all(box: Panel) -> Array:
	var pages: Array = box.pages.duplicate()
	var state := {"closed": false}
	var mark := func() -> void: state["closed"] = true
	box.closed.connect(mark, CONNECT_ONE_SHOT)
	for _index in range(200):
		if state["closed"] or not box.active:
			break
		key(KEY_E, true)
		await frames(2)
		key(KEY_E, false)
		if state["closed"]:
			break
		await frames(3)
	if box.closed.is_connected(mark):
		box.closed.disconnect(mark)
	await frames(1)
	check(state["closed"], "E turns every page of: " + (String(pages[0]) if not pages.is_empty() else "?"))
	return pages


## Lets a chapter sequence run, turning its pages; returns every page shown.
func play_sequence(chapter: Node, box: Panel) -> Array:
	var shown: Array = []
	for _index in range(3000):
		if not chapter.busy:
			break
		if box.active:
			shown.append_array(await read_all(box))
		else:
			await frames(1)
	check(not chapter.busy, "the sequence hands control back")
	return shown


func stay(code: int, label: String) -> void:
	var before := current_scene.get_instance_id()
	await tap(code)
	await frames(4)
	check(current_scene.get_instance_id() == before and not routes.switching, label)


# --- the chapter ---------------------------------------------------------------------------------

func day_one_home() -> void:
	var boot: Node = load(BOOT).instantiate()
	root.add_child(boot)
	current_scene = boot
	if not await arrive(MAIN, "Boot"):
		return
	var home := current_scene
	story = STORY_STATE.ensure(self)
	check(story.chapter_active and story.step == "d1_wake" and story.day == 1, "the boot scene starts chapter 1 at its first step")
	check(home.chapter != null and home.player.is_frozen(), "the safehouse runs the opening with the hero held")
	var hud: Node = home.chapter.hud
	check(hud.place_label.text == "C区 601" and hud.clock_label.text == "07/27 12:00", "the status plate shows 601, the story date and 12:00")
	check(not home.title_label.visible and not home._route_hint.visible and not home._hint.visible, "the sandbox labels give way to the chapter HUD")
	await frames(2)
	check(home.chapter.overlay.shown.has("title:第一章"), "the title card shows 第一章")
	var opening := await play_sequence(home.chapter, home.dialogue)
	check(not opening.is_empty() and String(opening[0]).begins_with("2040年7月19日晚在佩特拉新城C区"), "the opening starts with the TV news line")
	check(opening.has("咚咚 咚咚") and home.chapter.overlay.played.has("knock"), "the knock code sounds and is captioned")
	check(opening.has("又有生命要逝去了……"), "the opening ends on the knock's meaning")
	check(not home.player.is_frozen() and hud.goal_label.text == "▸ 电脑", "after the opening the hero is free and sent to the computer")
	check(hud.hints_panel.visible and hud.hints_label.text.contains("移动"), "the control hints show for a while after the opening")
	await stay(KEY_F8, "F8 is a developer key inside the chapter")
	await stay(KEY_F7, "F7 is a developer key inside the chapter")
	check(not home._route_hint.visible, "the safehouse no longer advertises F8 inside the chapter")

	if not await walk_home("computer"):
		return
	check(hud.prompt.visible and hud.prompt_label.text == "电脑" and hud.key_label.text == "E", "the key cap names the computer")
	await tap(KEY_E)
	var menu: Panel = home.chapter.menu
	check(menu.active and menu.options[0] == "信息（主线）" and menu.badges[0] and menu.options.size() == 3, "the computer opens the dark-web terminal with an unread message")
	check(not hud.prompt.visible and menu.corner.text == "07/27 12:00", "the terminal hides the key cap and shows the clock")
	await tap(KEY_E)
	check(home.dialogue.active and story.step == "d1_contract", "reading Joren's message takes the job")
	var bold_index: int = home.dialogue.pages.find("甚至连他们为什么要死都不知道……")
	check(bold_index >= 0 and home.dialogue.page_bold[bold_index] and not home.dialogue.page_bold[0], "the script's bold line is typed in bold")
	check(home.dialogue.page_speakers[0] == "qiaolun", "the job comes from Joren")
	var message := await read_all(home.dialogue)
	check(String(message[0]).begins_with("科伯恩 男 27岁"), "Joren names Coburn")
	check(hud.goal_label.text == "▸ 出门 · 费列罗诊所", "the objective points at the door")

	if not await walk_home("door"):
		return
	await tap(KEY_E)


func hospital_day() -> void:
	if not await arrive(HOSPITAL, "The door"):
		return
	var hospital := current_scene
	var chapter: Node = hospital.chapter
	check(story.step == "d1_hospital" and hospital.view_mode == 0 and hospital.floor_id == 1, "the job opens the hospital top-down on floor 1")
	var hud: Node = chapter.chapter_hud
	check(hud.place_label.text == "地下医院 1F" and hud.clock_label.text == "12:30", "the status plate shows the floor and the arrival time")
	check(not hospital._title.visible and not hospital._hint.visible, "the sandbox title and control line give way to the HUD")
	check(hud.toast_panel.visible and hud.toast_label.text == "灯光下会暴露，暗处才安全", "a toast explains the light")
	await stay(KEY_F7, "F7 is inert in the chapter hospital")
	await tap(KEY_TAB)
	check(hospital.view_mode == 0, "Tab does not switch the projection inside the chapter")
	var checkpoint: Vector2 = chapter.checkpoint

	# Into the lit corridor: the meter fills and the lock sends the hero back.
	await walk(func(point: Vector2) -> bool: return point == Vector2(76, 70), "the lit floor-1 corridor")
	var waited := 0
	while chapter.locks == 0 and waited < 240:
		await frames(1)
		waited += 1
	check(chapter.locks == 1 and chapter.overlay.shown.has("lock:微光粒子监控已锁定"), "standing in the corridor light locks on")
	while chapter.busy:
		await frames(1)
	await frames(3)
	check(hospital.player.position.distance_to(checkpoint) < 1.0, "the lock returns the hero to the entry room")

	# Breaker: no key inside the chapter; the clinic goes dark.
	if not await walk_hospital("breaker", Vector2(116, 157), 18.0):
		return
	check(hud.prompt.visible and hud.prompt_label.text == "配电箱" and not hospital.interactions._hint.visible, "the key cap names the breaker")
	await tap(KEY_E)
	check(hospital.interactions.dialogue_active and not hospital.interactions.power_states["clinical"], "the breaker opens without a key and cuts the clinic's power")
	await read_all(hospital.interactions.dialogue)
	if not await walk_hospital("stairs_up", Vector2(74, 174), 18.0):
		return
	await tap(KEY_E)
	await frames(6)
	check(hospital.floor_id == 2 and chapter.checkpoint.distance_to(Vector2(71, 124)) < 1.0, "the stairs reach floor 2 and set its checkpoint")
	check(hud.place_label.text == "地下医院 2F", "the status plate follows the floor")
	check(chapter.target != null and not chapter.target.dead, "Coburn sits in the office")

	if not await walk_hospital("reception_pc", Vector2(117, 137), 12.0):
		return
	await tap(KEY_E)
	var roster := await read_all(hospital.interactions.dialogue)
	check(roster.any(func(page: String) -> bool: return page.contains("1010")), "the duty roster carries the door code")

	# Office door: the corridor is dark now.
	if not await walk_hospital("office_door", Vector2(502, 152), 6.0):
		return
	check(not chapter.in_light, "the corridor by the office is dark after the breaker")
	check(hud.prompt_label.text == "办公室密码门" and not hospital.security.get("_hint").visible, "the key cap names the locked office door")
	await tap(KEY_E)
	check(hospital.security.keypad_active, "E at the office door opens the keypad")
	for digit in "1010":
		await tap(KEY_0 + int(digit), digit.unicode_at(0))
	await tap(KEY_ENTER)
	await frames(24)
	check(hospital.security.is_door_unlocked("office_door") and not hospital.security.keypad_active, "1010 opens the office door")

	# From the front Coburn would see the hero; from behind, in the dark, the job is done.
	var feet: Vector2 = chapter.target.position
	if not await walk(func(point: Vector2) -> bool: return point.distance_to(feet) <= 20.0 and point.y <= feet.y - 14.0, "behind Coburn"):
		return
	await frames(2)
	check(hospital.interactions.nearest_id == "coburn" and hud.prompt_label.text == "科伯恩", "behind Coburn the key cap names him")
	await tap(KEY_E)
	check(chapter.target.dead and story.has_flag("coburn_dead") and story.step == "d1_target_down", "E from behind, in the dark, kills Coburn")
	check(chapter.overlay.shown.has("strike") and not hospital.interactions.dialogue_active, "the kill flashes without any subtitle")
	check(chapter.locks == 1, "the dark route never locked on again")
	if not await walk_hospital("exit_panel", Vector2(590, 175), 16.0):
		return
	await tap(KEY_E)


func day_one_evening() -> void:
	if not await arrive(HOME, "The exit"):
		return
	var home := current_scene
	var hud: Node = home.chapter.hud
	check(story.step == "d1_return" and hud.clock_label.text == "07/27 14:50", "the exit returns home at 14:50")
	check(hud.goal_label.text == "▸ 电脑 · 暗网购物", "home sends the hero to shop")
	if not await walk_home("computer"):
		return
	await tap(KEY_E)
	var menu: Panel = home.chapter.menu
	check(menu.active and not menu.badges[0], "no new message after the job")
	await tap(KEY_S)
	check(menu.selected == 1, "S moves to 购物")
	await tap(KEY_E)
	check(menu.active and menu.options.size() == 4 and menu.options[0] == "暗器 · 钢钉" and menu.notes[0] == "武器装备 ￥40", "the shop lists equipment, food, drink and supplies with prices")
	await tap(KEY_E)
	check(story.has_item("throwing_spike") and story.step == "d1_shopped" and not menu.active, "ordering an item completes the shop lesson")
	await read_all(home.dialogue)
	check(hud.goal_label.text == "▸ 床 · 睡觉", "after shopping the bed waits")
	if not await walk_home("bed"):
		return
	await tap(KEY_E)
	check(home.chapter.busy and home.player.is_frozen(), "sleep holds the hero")
	for _index in range(400):
		if home.chapter.overlay.shown.has("rampage:22:00") or not is_instance_valid(home):
			break
		await frames(1)
	check(not is_instance_valid(home) or home.chapter.overlay.shown.has("rampage:22:00"), "22:00 brings the rampage")


func night_one() -> void:
	if not await arrive(HOSPITAL, "The rampage"):
		return
	var hospital := current_scene
	var chapter: Node = hospital.chapter
	check(story.step == "d1_night" and story.is_night() and hospital.view_mode == 1 and hospital.floor_id == 1, "the night is side view in the hospital")
	check(chapter.chapter_hud.clock_label.text == "22:00" and chapter.chapter_hud.goal_label.text == "▸ 出口", "the night status plate shows 22:00 and the exit")
	check(not chapter.hud.plate.visible and not chapter.stealth(), "the night has no stealth meter")
	await tap(KEY_TAB)
	check(hospital.view_mode == 1, "Tab does not switch the night projection")
	var flight: Dictionary = hospital.base_layout["stairs"]["side_flight"]
	var entry: Array = flight["lower_entry_x"]
	await side_walk(KEY_D, (float(entry[0]) + float(entry[1])) * 0.5)
	await tap(KEY_W)
	await side_walk(KEY_A, float(flight["upper_exit_x"]) - 2.0)
	await frames(10)
	check(hospital.floor_id == 2 and absf(hospital.player.position.y - 164.0) < 1.0, "the night stairs climb to floor 2")
	await side_walk(KEY_D, 585.0)
	await frames(4)
	check(hospital.interactions.nearest_id == "exit_panel", "the night exit is in reach")
	await tap(KEY_E)


func side_walk(code: int, destination: float) -> void:
	var right := code == KEY_D
	key(code, true)
	for _index in range(900):
		await frames(1)
		var x: float = player().position.x
		if (right and x >= destination) or (not right and x <= destination):
			break
	key(code, false)
	await frames(6)


func breath() -> void:
	if not await arrive(BREATH, "The night exit"):
		return
	var interlude := current_scene
	check(story.step == "d1_breath", "the night ends in the held breath")
	for _index in range(900):
		if interlude.finished:
			break
		await frames(1)
	var expected: Array = story.chapter["breath"][0]
	check(str(interlude.shown_lines) == str(expected), "the dream's lines surface in order, still garbled: " + str(interlude.shown_lines))
	check(interlude.overlay.played.has("breath"), "the held breath is heard")


func day_two() -> void:
	if not await arrive(HOME, "The interlude"):
		return
	var home := current_scene
	check(story.step == "d2_wake" and home.chapter.hud.clock_label.text == "07/28 11:00", "day 2 wakes at 11:00")
	var wake := await play_sequence(home.chapter, home.dialogue)
	check(home.chapter.overlay.played.has("breath") and str(wake) == str(["这次听的更清楚了", "但还是不知道是什么……"]), "waking up: breath, then the two lines")
	if not await walk_home("television"):
		return
	await tap(KEY_E)
	var news := await read_all(home.dialogue)
	check(String(news[0]).begins_with("2040年7月27日晚在佩特拉新城C区地下医院"), "the TV now reports the hospital")
	if not await walk_home("computer"):
		return
	await tap(KEY_E)
	check(home.chapter.menu.badges[0], "Joren has written again")
	await tap(KEY_E)
	check(home.dialogue.page_speakers.has("sk_reply") and story.step == "d2_contract", "the reply is the hero's own and the next job is taken")
	await read_all(home.dialogue)
	check(home.chapter.hud.goal_label.text.begins_with("▸ 莫温"), "the objective names Morwen")
	if not await walk_home("fridge"):
		return
	await tap(KEY_E)
	await read_all(home.dialogue)
	check(story.has_flag("vodka_day_2"), "the fridge's vodka is marked for tonight")
	if not await walk_home("dumbbells"):
		return
	await tap(KEY_E)
	await read_all(home.dialogue)
	check(story.has_flag("trained_day_2"), "the dumbbells are marked for tonight")
	if not await walk_home("bed"):
		return
	await tap(KEY_E)
	var bed := await read_all(home.dialogue)
	check(str(bed) == str(story.chapter["home"]["bed_not_yet"]) and current_scene == home, "the bed waits until Morwen's job (M4)")
	if not await walk_home("door"):
		return
	await tap(KEY_E)
	var door := await read_all(home.dialogue)
	check(str(door) == str(story.chapter["home"]["door_m4"]) and current_scene == home, "the door says the Jinyu building is still to come")
	await stay(KEY_F8, "F8 stays inert on day 2")
	story.debug_keys = true
	await tap(KEY_F8)
	check(await arrive(STREET, "Debug F8"), "with --nw-debug F8 still opens the street")
	story.debug_keys = false


func run() -> void:
	routes = root.get_node("SceneRoutes")
	await day_one_home()
	await hospital_day()
	await day_one_evening()
	await night_one()
	await breath()
	await day_two()
	observations["walk_seconds"] = snappedf(_walk_frames / 60.0, 0.1)
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	hold(0)
	var report := {"suite": "chapter_flow", "checks": checks, "failures": failures, "observations": observations,
		"status": "passed" if failures.is_empty() else "failed"}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
