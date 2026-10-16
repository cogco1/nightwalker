extends "res://tests/support/isolated_suite.gd"
## Move data sanity: every move in moves_long_blade.gd points at drawn frames for both facings, keeps its hit
## window inside the animation, has blade paths, uses hit-stop weights GameSession knows, and the combo graph
## only names existing moves. Playback: every move, started in each view, facing and (where it has an air clip)
## in the air, plays at its move-table fps. The speed written in side_view.tres / top_down.tres is only the
## divisor player.gd scales by, so the test reads the sprite's actual rate and never the tres numbers.

const MOVESET = preload("res://scripts/player/moves_long_blade.gd")
const SESSION = preload("res://scripts/core/game_session.gd")
const LAB = preload("res://tests/fixtures/combat_lab.tscn")
const SIDE = preload("res://assets/side_view.tres")
const TOP = preload("res://assets/top_down.tres")
# Moves the top-down view can start (no crouch, no specials there).
const TOP_MOVES := [&"attack1", &"attack2", &"attack3", &"heavy_slash"]
# speed_scale is a 32-bit float, so fps / clip speed * clip speed can be off by about 1e-6.
const RATE_TOLERANCE := 0.001
# Moves player.gd starts by request rather than through the combo graph.
const REQUESTED := [&"crouch_stab", &"rising_slash", &"dive_slash", &"dash_stab", &"heavy_slash", &"counter_slash", &"leap_cleave"]
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
		for field in ["anim", "fps"]:
			check(data.has(field), "%s has %s" % [id, field])
		check(data.has("active") or not data.has("box"), "%s: a move with a hit box has a hit window" % id)
		check(data.get("swing", &"light") in [&"light", &"heavy", &"none"], "%s uses a known swing sound" % id)
		if data.has("as"):
			check(MOVESET.MOVES.has(data["as"]), "%s counts as a known move" % id)
		if data.get("resumes", false):
			var after_dodge := false
			for from in MOVESET.STRINGS:
				if from != &"" and MOVESET.MOVES[from].get("dodge", false) and id in MOVESET.next_moves(from, &"light"):
					after_dodge = true
			check(after_dodge, "%s resumes a string, so it follows a dodge" % id)
		if data.has("then"):
			check(MOVESET.MOVES.has(data["then"]) and data["then"] != id, "%s: its next segment is another known move" % id)
		if data.has("arc"):
			check(data["arc"].has("from") and data["arc"].has("to") and data["arc"]["from"] != data["arc"]["to"], "%s: blade arc has a sweep" % id)
		if data.has("shockwave"):
			check((data.get("dive", false) or data.get("lands", false)) and float(data["shockwave"].get("half_width", 0.0)) > 0.0, "%s: only a move that lands has a shockwave, with a width" % id)
			check(SESSION.STOPS.has(data["shockwave"].get("crit_stop", &"critical")) and SESSION.STOPS.has(data["shockwave"].get("stop", &"light")), "%s: shockwave uses known hit-stop weights" % id)
		check(float(data.get("fps", 0.0)) > 0.0, "%s plays at a positive rate" % id)
		check(data.get("crit", &"none") in CRITS, "%s uses a known critical rule" % id)
		check(SESSION.STOPS.has(data.get("stop", &"light")) and SESSION.STOPS.has(data.get("crit_stop", &"critical")), "%s uses hit-stop weights GameSession knows" % id)
		for prefix in [data["anim"]] + ([data["air_anim"]] if data.has("air_anim") else []):
			for facing in ["left", "right"]:
				verify_clip(SIDE, "%s_%s" % [prefix, facing], data, paths.get("side_view", {}), id)
		if id in TOP_MOVES:
			for facing in ["up", "down", "left", "right"]:
				verify_clip(TOP, "%s_%s" % [data["anim"], facing], data, paths.get("top_down", {}), id)
	var reachable: Dictionary = {}
	for id in REQUESTED:
		reachable[id] = true
	for id in MOVESET.MOVES:
		if MOVESET.MOVES[id].has("then"):
			reachable[MOVESET.MOVES[id]["then"]] = true
	for from in MOVESET.STRINGS:
		check(from == &"" or MOVESET.MOVES.has(from), "combo graph starts from a known move: " + String(from))
		for input in MOVESET.STRINGS[from]:
			check(input in [&"light", &"heavy"], "combo graph %s uses a known input %s" % [from, input])
			for next in MOVESET.next_moves(from, input):
				check(MOVESET.MOVES.has(next), "combo graph %s --%s--> names a known move" % [from, input])
				reachable[next] = true
				if MOVESET.MOVES.has(next) and not MOVESET.MOVES[next].get("side_only", false):
					check(next in TOP_MOVES, "%s can start in the top-down view, so it has top-down frames" % next)
	for id in MOVESET.MOVES:
		check(reachable.has(id), "%s can be started (combo graph, segment or request)" % id)
	await verify_playback_rates()
	finish()


## Starts each move on a fresh hero in the combat lab and compares the sprite's playing rate with the move's fps.
## player.gd has no public way to start an arbitrary move, so this calls its _start_move directly.
func verify_playback_rates() -> void:
	var lab: Node2D = LAB.instantiate()
	root.add_child(lab)
	await physics_frame
	for mode in [0, 1]:
		for id in MOVESET.MOVES:
			var data: Dictionary = MOVESET.MOVES[id]
			if mode == 0 and id not in TOP_MOVES:
				continue
			for facing in (["up", "down", "left", "right"] if mode == 0 else ["left", "right"]):
				for airborne in ([false, true] if mode == 1 and data.has("air_anim") else [false]):
					lab.build_arena(mode)
					await physics_frame
					await physics_frame
					var player: CharacterBody2D = lab.player
					if airborne:
						player.position.y -= 60.0
						await physics_frame
					player.facing = facing
					player.call("_start_move", id)
					var sprite: AnimatedSprite2D = player.sprite
					var clip := "%s_%s" % [data["air_anim"] if airborne else data["anim"], facing]
					var rate := sprite.sprite_frames.get_animation_speed(sprite.animation) * sprite.speed_scale
					check(String(sprite.animation) == clip and absf(rate - float(data["fps"])) < RATE_TOLERANCE,
						"%s plays %s at its %s fps (view %d, playing %s at %.4f)" % [id, clip, data["fps"], mode, sprite.animation, rate])
	lab.queue_free()
	await process_frame


func verify_clip(frames: SpriteFrames, clip: String, data: Dictionary, blade_paths: Dictionary, id: StringName) -> void:
	check(frames.has_animation(clip), "%s: animation %s exists" % [id, clip])
	if not frames.has_animation(clip):
		return
	var count := frames.get_frame_count(clip)
	var start := int(data.get("start_frame", 0))
	var last := int(data.get("end", count - 1))
	check(start < count, "%s: start frame lies inside %s" % [id, clip])
	check(last > start and last < count, "%s: the cut-off frame lies after the start inside %s" % [id, clip])
	if data.has("active"):
		var active: Vector2i = data["active"]
		check(active.x >= start and active.x < count, "%s: first active frame lies inside the played part of %s" % [id, clip])
		check(active.y == -1 or (active.y >= active.x and active.y < count), "%s: last active frame lies inside %s" % [id, clip])
		check(int(data.get("side_first", active.x)) < count, "%s: side-view first active frame lies inside %s" % [id, clip])
		if data.has("lunge"):
			check(int(data["lunge"]["from"]) <= active.y, "%s: lunge starts no later than the last active frame" % id)
		for frame in data.get("rehit", []):
			check(int(frame) > active.x and (active.y == -1 or int(frame) <= active.y), "%s: rehit frame lies inside the hit window" % id)
	if data.has("hold_frame"):
		check(int(data["hold_frame"]) >= start and int(data["hold_frame"]) < count, "%s: held air frame lies inside the played part of %s" % [id, clip])
	if data.has("dash_cancel"):
		check(int(data["dash_cancel"]) >= start and int(data["dash_cancel"]) < count, "%s: dash-cancel frame lies inside the played part of %s" % [id, clip])
	if data.has("cancel"):
		check(int(data["cancel"]) > int(data.get("active", Vector2i(start, start)).y) and int(data["cancel"]) < count, "%s: cancel window opens after the hit frames inside %s" % [id, clip])
	for frame in data.get("ghosts", []):
		check(int(frame) < count, "%s: afterimage frame lies inside %s" % [id, clip])
	check(blade_paths.has(clip) and blade_paths[clip].size() == count, "%s: blade path has one tip per frame of %s" % [id, clip])


func finish() -> void:
	var report := {"suite": "moveset", "status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures,
		"moves": MOVESET.MOVES.size()}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
