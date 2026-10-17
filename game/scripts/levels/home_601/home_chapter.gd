extends Node
## Chapter mode of the safehouse (only when the story runs; the sandbox home is untouched). Replaces the sandbox
## labels with the chapter HUD (status plate, key cap, control hints), plays the step's opening sequence, and
## gives the hub its jobs: the TV shows the day's
## news, the computer opens the dark-web terminal (messages advance the story, the shop records orders), the
## fridge and dumbbells mark tonight's buffs, the bed sleeps to 22:00 and the door leaves for the job.
## Text comes from assets/story/chapter1.json.

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const GAME_SESSION = preload("res://scripts/core/game_session.gd")
const STORY_OVERLAY = preload("res://scripts/ui/story_overlay.gd")
const TERMINAL_MENU = preload("res://scripts/ui/terminal_menu.gd")
const CHAPTER_HUD = preload("res://scripts/ui/chapter_hud.gd")
const ROOT_OPTIONS := ["信息（主线）", "购物", "离开"]

var home: Node2D
var story: Node
var overlay: CanvasLayer
var menu: Panel
var hud: Node
## A sequence or the sleep is running: the player is frozen and keys wait (reading pages still turn).
var busy := false
var menu_page := ""
var last_read := ""


func _ready() -> void:
	home = get_parent()
	story = STORY_STATE.ensure(get_tree())
	overlay = STORY_OVERLAY.new()
	overlay.name = "StoryOverlay"
	add_child(overlay)
	var canvas: CanvasLayer = home.get_node("HomeUI")
	home.title_label.hide()
	home._route_hint.hide()
	home.set_hint_visible(false)
	hud = CHAPTER_HUD.new()
	hud.name = "ChapterHud"
	add_child(hud)
	hud.build(canvas)
	menu = TERMINAL_MENU.new()
	menu.name = "TerminalMenu"
	canvas.add_child(menu)
	menu.setup(Vector2(58, 40))
	home.get_node("GameSession").keybindings_closed.connect(func(_saved: bool) -> void:
		hud.show_hints(CHAPTER_HUD.controls_text()))
	menu.chosen.connect(_on_menu_chosen)
	menu.cancelled.connect(_on_menu_cancelled)
	story.step_changed.connect(func(_step: String) -> void: refresh_hud())
	refresh_hud()
	var sequence := String(story.step_data().get("enter_sequence", ""))
	if not sequence.is_empty() and not story.has_flag("sequence:" + sequence):
		var first: Array = story.text("sequences", sequence)
		if not first.is_empty() and (first[0].has("title") or first[0].has("wake")):
			overlay.shade.color.a = 1.0
		run_sequence.call_deferred(sequence)


func refresh_hud() -> void:
	hud.set_status("C区 601", "%s %s" % [story.short_date(), story.clock_text()], story.objective())


## The key cap names what E would open here, while nothing else holds the room.
func _process(_delta: float) -> void:
	var item: Dictionary = home._find_item(home.nearest_interaction)
	var free: bool = not busy and not menu.active and not home.dialogue_active
	hud.set_prompt(String(item.get("name", "")) if free and not item.is_empty() else "")


## Returns true when the chapter owns the event: the terminal menu, or any key while a sequence holds the room.
func handle_input(event: InputEvent) -> bool:
	if menu.active:
		return menu.handle_input(event)
	if busy and not home.dialogue_active and event is InputEventKey:
		return true
	return false


## Chapter behaviour for a safehouse interaction; false leaves it to the ordinary reading.
func open_interaction(id: String) -> bool:
	if busy:
		return true
	match id:
		"television":
			home.prop_effects.call("play_interaction", id)
			_read(story.text("tv", str(story.day)), "电视", ["television"])
		"computer":
			home.prop_effects.call("play_interaction", id)
			open_terminal()
		"fridge":
			home.prop_effects.call("play_interaction", id)
			story.set_flag("vodka_day_%d" % story.day)
			_read(story.text("home", "fridge"), "冰箱", [], id)
		"dumbbells":
			home.prop_effects.call("play_interaction", id)
			story.set_flag("trained_day_%d" % story.day)
			_read(story.text("home", "dumbbells"), "哑铃", [], id)
		"bed":
			var target := String(story.step_data().get("bed", ""))
			if target.is_empty():
				_read(story.text("home", "bed_not_yet"), "床", [], id)
			else:
				sleep_to(target)
		"door":
			var destination := String(story.step_data().get("door", ""))
			if not destination.is_empty():
				_leave(destination)
			elif story.step == "d2_contract":
				_read(story.text("home", "door_m4"), "房门")
			else:
				_read(story.text("home", "door_nowhere"), "房门")
		_:
			return false
	return true


func _read(lines: Variant, context: String, speakers: Array = [], id := "") -> void:
	var list: Array = lines if lines is Array else []
	home.dialogue.position.y = home.dialogue_top(id)
	home.dialogue.open(list, context, home.player, speakers)


## Plays a named sequence from the chapter file: title card, wake-up, sounds and readings, in order.
func run_sequence(sequence_name: String) -> void:
	var entries: Array = story.text("sequences", sequence_name)
	story.set_flag("sequence:" + sequence_name)
	_hold(true)
	for entry: Dictionary in entries:
		if entry.has("title"):
			await overlay.title_card(String(entry["title"]))
		if bool(entry.get("wake", false)):
			overlay.shade.color.a = 1.0
			overlay.play("breath")
			await overlay.fade_from_black(1.2)
		if entry.has("sound"):
			overlay.play(String(entry["sound"]))
		if entry.has("lines"):
			_read(entry["lines"], String(entry.get("context", "601")), entry.get("speakers", []))
			await home.dialogue.closed
			await get_tree().process_frame
	_hold(false)
	if sequence_name == "intro":
		hud.show_hints(CHAPTER_HUD.controls_text())


func open_terminal() -> void:
	menu_page = "root"
	var entries: Array = []
	for label in ROOT_OPTIONS:
		entries.append({"label": label, "badge": label == ROOT_OPTIONS[0] and _unread_message() != ""})
	menu.open("暗网终端", entries, home.player, 0, _terminal_clock())


func open_shop() -> void:
	menu_page = "shop"
	var entries: Array = []
	for item: Dictionary in story.chapter.get("shop", []):
		entries.append({"label": String(item["name"]), "note": "%s ￥%d" % [item["kind"], int(item["price"])]})
	menu.open("暗网终端 · 购物", entries, home.player, 0, _terminal_clock())


func _terminal_clock() -> String:
	return "%s %s" % [story.short_date(), story.clock_text()]


func _unread_message() -> String:
	var next := String(story.step_data().get("computer", ""))
	return story.step if not next.is_empty() and story.text("messages", story.step) != null else ""


func _on_menu_chosen(index: int) -> void:
	if menu_page == "shop":
		var item: Dictionary = story.chapter.get("shop", [])[index]
		story.grant_item(String(item["id"]))
		var lines: Array = []
		for line in story.text("home", "shop_bought"):
			lines.append(String(line).replace("%s", String(item["name"])))
		_close_menu()
		var next := String(story.step_data().get("shop_next", ""))
		if not next.is_empty():
			story.set_step(next)
		_read(lines, "暗网购物", ["terminal", "terminal"])
		return
	match index:
		0:
			var key := _unread_message()
			_close_menu()
			if not key.is_empty():
				var message: Dictionary = story.text("messages", key)
				last_read = key
				story.set_step(String(story.step_data().get("computer", "")))
				_read(message["lines"], "暗网终端", message.get("speakers", []))
			elif not last_read.is_empty():
				var message: Dictionary = story.text("messages", last_read)
				_read(message["lines"], "暗网终端", message.get("speakers", []))
			else:
				_read(story.text("home", "no_messages"), "暗网终端", ["terminal"])
		1:
			open_shop()
		_:
			_close_menu()


func _on_menu_cancelled() -> void:
	if menu_page == "shop":
		open_terminal()
	else:
		_close_menu()


func _close_menu() -> void:
	menu.close()
	menu_page = ""
	home.current_interaction = ""


## Bed: the room goes dark, the clock jumps to 22:00 and the rampage takes over.
func sleep_to(target: String) -> void:
	_hold(true)
	await overlay.fade_to_black(0.8)
	await overlay.rampage(String(story.step_data(target).get("time", "22:00")))
	get_tree().root.get_node("SceneRoutes").call("travel", target)


func _leave(destination: String) -> void:
	_hold(true)
	await overlay.fade_to_black(0.4)
	get_tree().root.get_node("SceneRoutes").call("travel", destination)


func _hold(on: bool) -> void:
	busy = on
	var session := GAME_SESSION.of(self)
	if on:
		home.player.freeze(self)
		if session != null:
			session.push_modal(self)
	else:
		home.player.unfreeze(self)
		if session != null:
			session.pop_modal(self)
		refresh_hud()
