extends Node
## Session story state under /root/NightwalkerStoryState: inventory and flags (doors, power, breaker key) and,
## once start_chapter() runs, the chapter progress: day, clock and the current step of assets/story/chapter1.json.
## Without start_chapter() the game is the free sandbox it always was (scene tests, editor F6, Run-Sandbox):
## no clock, and F7 / F8 / Tab stay free. Nothing is saved; quitting clears it.

signal step_changed(step: String)

const NODE_NAME := "NightwalkerStoryState"
const CHAPTER_PATH := "res://assets/story/chapter1.json"
## Command-line user argument (after --) that keeps F7 / F8 / Tab working inside the chapter.
const DEBUG_ARGUMENT := "--nw-debug"

var items: Dictionary = {}
var flags: Dictionary = {}
var chapter_active := false
var debug_keys := false
var chapter: Dictionary = {}
var step := ""
var day := 1
var minutes := 0


## The shared node, created on first use; null outside a running tree.
static func ensure(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var existing := tree.root.get_node_or_null(NODE_NAME)
	if existing != null:
		return existing
	var state: Node = load("res://scripts/core/story_state.gd").new()
	state.name = NODE_NAME
	tree.root.add_child(state)
	return state


func grant_item(id: String) -> void:
	if not id.is_empty():
		items[id] = true


func has_item(id: String) -> bool:
	return bool(items.get(id, false))


func set_flag(id: String, value: bool = true) -> void:
	if not id.is_empty():
		flags[id] = value


func has_flag(id: String) -> bool:
	return bool(flags.get(id, false))


## Starts a fresh chapter run: clears this session's items and flags and enters the chapter's first step.
func start_chapter(path := CHAPTER_PATH) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	chapter = parsed if parsed is Dictionary else {}
	items.clear()
	flags.clear()
	chapter_active = true
	debug_keys = OS.get_cmdline_user_args().has(DEBUG_ARGUMENT)
	day = 1
	minutes = 0
	step = ""
	set_step(String(chapter.get("start_step", "")))


## Back to the sandbox (tests use this between runs).
func end_chapter() -> void:
	chapter_active = false
	debug_keys = false
	chapter = {}
	step = ""


## F7 / F8 / Tab are developer keys inside the chapter; the sandbox always has them.
func allows_debug_routes() -> bool:
	return not chapter_active or debug_keys


func set_step(id: String) -> void:
	var data: Dictionary = chapter.get("steps", {}).get(id, {})
	step = id
	if data.has("day"):
		day = int(data["day"])
	if data.has("time"):
		minutes = parse_time(String(data["time"]))
	step_changed.emit(id)


func step_data(id := "") -> Dictionary:
	return chapter.get("steps", {}).get(step if id.is_empty() else id, {})


func objective() -> String:
	return String(step_data().get("objective", ""))


func is_night() -> bool:
	return String(step_data().get("phase", "day")) == "night"


func clock_text() -> String:
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## "07/27" from the day's ISO date in the chapter file, for the HUD status plate.
func short_date() -> String:
	var parts := String(chapter.get("days", {}).get(str(day), {}).get("date", "")).split("-")
	return "%s/%s" % [parts[1], parts[2]] if parts.size() == 3 else ""


## Chapter text block by key (sequences, messages, tv, shop, breath).
func text(section: String, key: String) -> Variant:
	return chapter.get(section, {}).get(key)


static func parse_time(value: String) -> int:
	var parts := value.split(":")
	return int(parts[0]) * 60 + int(parts[1]) if parts.size() == 2 else 0
