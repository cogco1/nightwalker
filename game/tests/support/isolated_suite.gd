extends SceneTree
## Base for every regression suite and recorder: points the key-binding file at a test-only path before any
## scene calls CONTROLS.install(), so the player's own user://keybindings.cfg never changes a test result.
## Suites that test saving/loading bindings still set their own settings_path afterwards.

const ISOLATED_SETTINGS_PATH := "user://test_isolated_keybindings.cfg"


func _init() -> void:
	var controls: GDScript = load("res://scripts/core/controls.gd")
	controls.settings_path = ISOLATED_SETTINGS_PATH
	controls.current = {}
