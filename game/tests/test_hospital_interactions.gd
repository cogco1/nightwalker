extends SceneTree

const INTERACTIONS = preload("res://scripts/levels/hospital/hospital_interactions.gd")

class MockPlayer extends CharacterBody2D:
	var ticks := 0

	func _process(_delta: float) -> void:
		ticks += 1


class MockHospital extends Node2D:
	var player: CharacterBody2D
	var base_layout: Dictionary = {}
	var view_mode := 0
	var floor_id := 1
	var stairs_busy := false
	var ambient_ticks := 0

	func _process(_delta: float) -> void:
		ambient_ticks += 1

	func _room_for_position(point: Vector2, mode: int) -> String:
		return "west" if point.x < (80.0 if mode == 0 else 180.0) else "east"


var checks := 0
var failures: Array[String] = []
var host: MockHospital
var interactions: Node2D


func _initialize() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Hospital interaction suite timed out")
		quit(2)
	)
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func key(code: Key, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.echo = echo
	interactions.call("_unhandled_input", event)


func run() -> void:
	host = MockHospital.new()
	host.player = MockPlayer.new()
	host.player.position = Vector2(20, 20)
	host.add_child(host.player)
	host.base_layout = {
		"interactions": [
			{"id": "bad_anchor", "anchors": {"top_down": ["wrong", 20]}, "radius": 22},
			{"id": "bad_radius", "anchors": {"top_down": [20, 20]}, "radius": "wrong"},
			{"id": "other_room", "room_id": "east", "anchors": {"top_down": [20, 20]}, "radius": 22},
			{
				"id": "casefile", "room_id": "west", "title": "病例档案", "kind": "inspect",
				"anchors": {"top_down": [20, 20], "side_view": [120, 20]}, "radius": 22,
				"lines": ["这是用于检查长段落分页与阅读状态的场景文本。".repeat(4)]
			},
			{
				"id": "breaker", "room_id": "west", "title": "配电箱", "kind": "toggle_power",
				"anchors": {"top_down": [60, 20], "side_view": [160, 20]}, "radius": 12,
				"power_section": "surgery", "lines": ["配电箱上的开关。"],
				"power_on_lines": ["测试提供的接通描述。"], "power_off_lines": ["测试提供的断电描述。"]
			}
		],
		"power_sections": {
			"surgery": {
				"top_down": {"darken_rects": [[1, 1, 10, 10]], "screen_rects": [[2, 2, 3, 2]]},
				"side_view": {"darken_rects": [[101, 1, 10, 10]], "screen_rects": [[102, 2, 3, 2]]}
			}
		}
	}
	interactions = INTERACTIONS.new()
	interactions.name = "HospitalInteractions"
	interactions.call("configure", host, host.base_layout)
	host.add_child(interactions)
	root.add_child(host)
	current_scene = host
	await frames(3)
	check(interactions.process_mode == Node.PROCESS_MODE_ALWAYS, "Interactions and ambience can continue while the player is reading")
	check(interactions.power_states.get("surgery", false), "Power starts on for declared sections")
	check(interactions.nearest_id == "casefile", "Nearest item excludes malformed anchors/radii and items across room boundaries")
	key(KEY_E)
	check(interactions.dialogue_active and interactions.current_interaction == "casefile", "E opens the nearby narrative item")
	check(host.player.process_mode == Node.PROCESS_MODE_DISABLED and host.player.velocity == Vector2.ZERO, "Reading freezes only the player and clears movement")
	check(interactions.interaction_counts.get("casefile", 0) == 1 and interactions.last_interaction == "casefile", "Inspection records object use")
	var frozen_ticks: int = host.player.ticks
	var ambient_ticks := host.ambient_ticks
	await frames(5)
	check(host.player.ticks == frozen_ticks and host.ambient_ticks > ambient_ticks, "Ambient processing remains active while player processing stops")
	var pages: Array = interactions.get("_pages")
	var short_pages := not pages.is_empty()
	for page in pages:
		short_pages = short_pages and String(page).length() <= 32
	check(short_pages and pages.size() > 1, "Long narrative text is paged into readable blocks")
	key(KEY_E, true)
	check(interactions.get("_page_index") == 0 and interactions.interaction_counts["casefile"] == 1, "Keyboard repeat neither advances nor reopens inspection")
	key(KEY_E)
	var body: Label = interactions.get("_body")
	check(body.visible_characters == -1, "First E reveals the current typed page")
	key(KEY_E)
	check(interactions.get("_page_index") == 1, "Next E advances the narrative page")
	key(KEY_ESCAPE)
	check(not interactions.dialogue_active and host.player.process_mode == Node.PROCESS_MODE_INHERIT, "Esc closes inspection and restores movement processing")
	host.player.position = Vector2(500, 200)
	check(String(interactions.call("interact_nearest")).is_empty(), "Remote interaction is rejected")
	host.player.position = Vector2(60, 20)
	key(KEY_E)
	check(interactions.current_interaction == "breaker" and not interactions.power_states["surgery"], "Breaker interaction switches its lighting section off")
	check(interactions.get("_pages")[0] == "测试提供的断电描述。", "Power-off narrative uses scene-provided text")
	check(interactions.get("_feedback_remaining") > 0.0, "Interacting produces brief pixel feedback")
	interactions.close_dialogue()
	var old_player := host.player
	host.remove_child(old_player)
	old_player.queue_free()
	host.view_mode = 1
	host.player = MockPlayer.new()
	host.player.position = Vector2(160, 20)
	host.add_child(host.player)
	interactions.on_view_change()
	await frames(3)
	check(not interactions.power_states["surgery"] and interactions.interaction_counts["breaker"] == 1, "Power and interaction state persist across replacement of the player/view")
	check(interactions.nearest_id == "breaker", "Side view uses the corresponding anchor in the same room")
	check(interactions.get("_feedback_remaining") == 0.0, "Changing view clears feedback at the previous projection")
	key(KEY_E)
	check(interactions.power_states["surgery"] and interactions.interaction_counts["breaker"] == 2, "Breaker can restore power in the other projection")
	check(interactions.get("_pages")[0] == "测试提供的接通描述。", "Restored-power narrative uses scene-provided text")
	interactions.on_view_change()
	check(not interactions.dialogue_active and host.player.process_mode == Node.PROCESS_MODE_INHERIT, "Changing view closes dialogue and releases the currently frozen player")
	host.player.position = Vector2(120, 20)
	key(KEY_E)
	check(interactions.current_interaction == "casefile" and interactions.interaction_counts["casefile"] == 2, "Same narrative object can be inspected from both views")
	interactions.close_dialogue()
	await frames(1)
	var report := {"version": "v11", "suite": "hospital_interactions", "checks": checks, "passed": checks - failures.size(), "failures": failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	var file := FileAccess.open("res://evidence/hospital_interaction_results_v11.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Hospital interaction checks: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
