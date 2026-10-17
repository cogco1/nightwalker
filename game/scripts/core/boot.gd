extends Node
## Formal entry (Run-Demo): starts chapter 1, then opens the safehouse. With "-- --sandbox" it opens the free
## sandbox instead, the same as Run-Sandbox.cmd starting main.tscn directly: no clock, F7 / F8 / Tab free.

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const MAIN_PATH := "res://scenes/main.tscn"
const SANDBOX_ARGUMENT := "--sandbox"


func _ready() -> void:
	var story := STORY_STATE.ensure(get_tree())
	if OS.get_cmdline_user_args().has(SANDBOX_ARGUMENT):
		story.end_chapter()
	else:
		story.start_chapter()
	get_tree().change_scene_to_file.call_deferred(MAIN_PATH)
