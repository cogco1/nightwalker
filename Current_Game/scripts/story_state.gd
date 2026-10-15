extends Node
## Session-only story inventory and flags. This node lives outside scene roots.

var items: Dictionary = {}
var flags: Dictionary = {}


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
