extends Node
## Formal entry (Run-Demo): starts chapter 1, then opens the safehouse. With "-- --sandbox" it opens the free
## sandbox instead, the same as Run-Sandbox.cmd starting main.tscn directly: no clock, F7 / F8 / Tab free. With
## "-- --nw-step=<id>" (Run-Game.ps1 -Step <id>) the chapter starts at that step instead, to try one part (a step
## that names its scene, e.g. d1_night for the first night's fight).

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const MAIN_PATH := "res://scenes/main.tscn"
const SANDBOX_ARGUMENT := "--sandbox"
const STEP_ARGUMENT := "--nw-step="


func _ready() -> void:
	_open_initial_scene.call_deferred()


func _open_initial_scene() -> void:
	CONTROLS.install()
	var story := STORY_STATE.ensure(get_tree())
	if OS.get_cmdline_user_args().has(SANDBOX_ARGUMENT):
		story.end_chapter()
	else:
		story.start_chapter()
		var step := requested_step(OS.get_cmdline_user_args())
		if not step.is_empty() and story.chapter.get("steps", {}).get(step, {}).has("scene"):
			get_tree().root.get_node("SceneRoutes").travel.call_deferred(step)
			return
	get_tree().change_scene_to_file.call_deferred(MAIN_PATH)


## The step named by "--nw-step=<id>" among the user arguments, or "".
static func requested_step(arguments: PackedStringArray) -> String:
	for argument in arguments:
		if argument.begins_with(STEP_ARGUMENT):
			return argument.substr(STEP_ARGUMENT.length())
	return ""
