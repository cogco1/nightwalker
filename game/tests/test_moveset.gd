extends "res://tests/support/isolated_suite.gd"
## Move data sanity: every move in moves_long_blade.gd points at drawn frames for both facings, keeps its hit
## window inside the animation, has blade paths, uses hit-stop weights GameSession knows, and the combo graph
## only names existing moves.

const MOVESET = preload("res://scripts/player/moves_long_blade.gd")
const SESSION = preload("res://scripts/core/game_session.gd")
const SIDE = preload("res://assets/side_view.tres")
const TOP = preload("res://assets/top_down.tres")
# Moves the top-down view can start (no crouch, no specials there).
const TOP_MOVES := [&"attack1", &"attack2", &"attack3", &"heavy_slash"]
const CRITS := [&"none", &"roll", &"always"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)


func run() -> void:
	var paths: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/blade_paths.json"))
	for id in MOVESET.MOVES:
		var data: Dictionary = MOVESET.MOVES[id]
		for field in ["anim", "fps", "active"]:
			check(data.has(field), "%s has %s" % [id, field])
		check(float(data.get("fps", 0.0)) > 0.0, "%s plays at a positive rate" % id)
		check(data.get("crit", &"none") in CRITS, "%s uses a known critical rule" % id)
		check(SESSION.STOPS.has(data.get("stop", &"light")) and SESSION.STOPS.has(data.get("crit_stop", &"critical")), "%s uses hit-stop weights GameSession knows" % id)
		for prefix in [data["anim"]] + ([data["air_anim"]] if data.has("air_anim") else []):
			for facing in ["left", "right"]:
				verify_clip(SIDE, "%s_%s" % [prefix, facing], data, paths.get("side_view", {}), id)
		if id in TOP_MOVES:
			for facing in ["up", "down", "left", "right"]:
				verify_clip(TOP, "%s_%s" % [data["anim"], facing], data, paths.get("top_down", {}), id)
	for from in MOVESET.STRINGS:
		check(from == &"" or MOVESET.MOVES.has(from), "combo graph starts from a known move: " + String(from))
		for input in MOVESET.STRINGS[from]:
			check(MOVESET.MOVES.has(MOVESET.STRINGS[from][input]), "combo graph %s --%s--> names a known move" % [from, input])
	finish()


func verify_clip(frames: SpriteFrames, clip: String, data: Dictionary, blade_paths: Dictionary, id: StringName) -> void:
	check(frames.has_animation(clip), "%s: animation %s exists" % [id, clip])
	if not frames.has_animation(clip):
		return
	var count := frames.get_frame_count(clip)
	var active: Vector2i = data["active"]
	check(active.x >= 0 and active.x < count, "%s: first active frame lies inside %s" % [id, clip])
	check(active.y == -1 or (active.y >= active.x and active.y < count), "%s: last active frame lies inside %s" % [id, clip])
	check(int(data.get("side_first", active.x)) < count, "%s: side-view first active frame lies inside %s" % [id, clip])
	check(int(data.get("start_frame", 0)) < count, "%s: start frame lies inside %s" % [id, clip])
	if data.has("lunge"):
		check(int(data["lunge"]["from"]) <= active.y, "%s: lunge starts no later than the last active frame" % id)
	for frame in data.get("ghosts", []):
		check(int(frame) < count, "%s: afterimage frame lies inside %s" % [id, clip])
	check(blade_paths.has(clip) and blade_paths[clip].size() == count, "%s: blade path has one tip per frame of %s" % [id, clip])


func finish() -> void:
	var report := {"suite": "moveset", "status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures,
		"moves": MOVESET.MOVES.size()}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
