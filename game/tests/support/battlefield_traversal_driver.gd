extends RefCounted
## Smoke-only input driver. The playable scene does not load this file outside smoke mode.

var scene: Node2D
var player: CharacterBody2D
var vehicles: Array[Dictionary] = []
var ground_jump_events: Array[Dictionary] = []
var max_ground_error := 0.0
var max_vehicle_error := 0.0
var unexpected_airborne_ticks := 0
var ground_support_ticks := 0
var vehicle_contacts: Dictionary = {}
var _vehicle_types: Dictionary = {}
var _vehicle_index := 0
var _jump_release_pending := false
var _vehicle_episode_end := -INF
var _active_ground_event := -1


func _init(host: Node2D) -> void:
	scene = host
	player = scene.player
	for fixture: Dictionary in scene.traversal_layout.get("fixtures", []):
		if String(fixture.get("kind", "")) == "vehicle":
			vehicles.append(fixture)
			_vehicle_types[String(fixture.body_id)] = String(fixture.asset)
	vehicles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.rect[0]) < float(b.rect[0]))


func support() -> Dictionary:
	var best: Dictionary = {"id": "", "error": INF, "y": player.position.y}
	if not player.is_on_floor():
		return best
	# The rectangular foot touches the high corner of a slope. Query both corners
	# and its centre instead of comparing the centre with a steep ramp's centreline.
	for offset in [-6.0, 0.0, 6.0]:
		var query := PhysicsRayQueryParameters2D.create(
			player.position + Vector2(offset, -2.0), player.position + Vector2(offset, 18.0), 1)
		query.exclude = [player.get_rid()]
		query.hit_from_inside = true
		var hit := scene.get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var error := absf(player.position.y - float(hit.position.y))
		if error < float(best.error):
			var body: Object = hit.collider
			best = {"id": "ground" if body == scene.terrain else String(body.get_meta("surface_id", "")),
				"error": error, "y": float(hit.position.y), "normal": [hit.normal.x, hit.normal.y]}
	return best


func before_ground_tick() -> void:
	if _jump_release_pending:
		scene._key(int(scene.CONTROLS.current["jump"]), false)
		_jump_release_pending = false
	while _vehicle_index < vehicles.size() and player.position.x > float(vehicles[_vehicle_index].rect[0]) + float(vehicles[_vehicle_index].rect[2]) + 12.0:
		_vehicle_index += 1
	if _vehicle_index >= vehicles.size():
		return
	var vehicle := vehicles[_vehicle_index]
	var id := String(vehicle.id)
	var already_jumped := false
	for event in ground_jump_events:
		if String(event.vehicle_id) == id:
			already_jumped = true
	if not already_jumped and player.is_on_floor() and player.position.x >= float(vehicle.rect[0]) - 32.0:
		scene._key(int(scene.CONTROLS.current["jump"]), true)
		_jump_release_pending = true
		_vehicle_episode_end = float(vehicle.rect[0]) + float(vehicle.rect[2]) + 80.0
		ground_jump_events.append({"vehicle_id": id, "takeoff": [player.position.x, player.position.y],
			"airborne_ticks": 0, "max_rise": 0.0})
		_active_ground_event = ground_jump_events.size() - 1


func after_ground_tick() -> void:
	if _active_ground_event >= 0:
		var event: Dictionary = ground_jump_events[_active_ground_event]
		if not event.has("initial_upward_velocity"):
			event["initial_upward_velocity"] = player.velocity.y
			event["actual_takeoff"] = not player.is_on_floor() and player.velocity.y < player.jump_velocity * 0.8
		if not player.is_on_floor():
			event["airborne_ticks"] += 1
		event["max_rise"] = maxf(float(event.max_rise), float(event.takeoff[1]) - player.position.y)
		if player.is_on_floor() and player.position.x > _vehicle_episode_end:
			_active_ground_event = -1
	if player.is_on_floor():
		var contact := support()
		if String(contact.id) == "ground":
			ground_support_ticks += 1
			max_ground_error = maxf(max_ground_error, absf(player.position.y - scene.ground_y_at(player.position.x)))
		elif String(contact.id).ends_with("_body"):
			max_vehicle_error = maxf(max_vehicle_error, float(contact.error))
			var vehicle_type := String(_vehicle_types.get(String(contact.id), ""))
			if not vehicle_contacts.has(vehicle_type):
				vehicle_contacts[vehicle_type] = {"contact_ticks": 0, "max_support_error": 0.0}
			vehicle_contacts[vehicle_type]["contact_ticks"] += 1
			vehicle_contacts[vehicle_type]["max_support_error"] = maxf(float(vehicle_contacts[vehicle_type].max_support_error), float(contact.error))
	elif player.position.x > _vehicle_episode_end:
		unexpected_airborne_ticks += 1


func finish_ground_run() -> Dictionary:
	scene._key(int(scene.CONTROLS.current["jump"]), false)
	var actual_takeoffs := 0
	for event in ground_jump_events:
		if bool(event.get("actual_takeoff", false)) and int(event.airborne_ticks) > 0 and float(event.max_rise) > 20.0:
			actual_takeoffs += 1
	scene._check(ground_jump_events.size() == vehicles.size() and _vehicle_index == vehicles.size(),
		"The full-map run really jumps before and clears every damaged vehicle")
	scene._check(actual_takeoffs == vehicles.size(), "Every vehicle jump produces a real airborne upward takeoff")
	scene._check(ground_support_ticks > 60 and max_ground_error <= 6.0,
		"Original ground contacts stay within six native pixels between vehicle jumps")
	scene._check(max_vehicle_error <= 2.0, "Vehicle contacts follow the delivered painted silhouette")
	scene._check(unexpected_airborne_ticks <= 3, "The original ground route has no unexpected airborne seams")
	for vehicle_type in ["wreck_sedan.png", "wreck_van.png", "wreck_truck.png"]:
		scene._check(vehicle_contacts.has(vehicle_type) and int(vehicle_contacts[vehicle_type].contact_ticks) > 0,
			"Real jumping and landing contact are verified for " + vehicle_type)
	return {"vehicle_jump_events": ground_jump_events, "vehicles_cleared": _vehicle_index, "actual_takeoffs": actual_takeoffs,
		"max_ground_error": max_ground_error, "max_vehicle_support_error": max_vehicle_error,
		"unexpected_airborne_ticks": unexpected_airborne_ticks, "ground_support_ticks": ground_support_ticks,
		"vehicle_types": vehicle_contacts}


func _steer(direction: int) -> void:
	scene._key(int(scene.CONTROLS.current["move_left"]), direction < 0)
	scene._key(int(scene.CONTROLS.current["move_right"]), direction > 0)


func _drive_waypoint(point: Dictionary) -> Dictionary:
	var target := Vector2(float(point.position[0]), float(point.position[1]))
	var mode := String(point.get("mode", "jump"))
	var start := player.position
	var double_jump := start.y - target.y > 42.5
	var jump_presses := 0
	var airborne_ticks := 0
	var stair_ticks := 0
	var stair_ids: Dictionary = {}
	var settled := 0
	var elapsed := 0
	var timeout := int(absf(target.x - start.x)) + 240
	while elapsed < timeout:
		var dx := target.x - player.position.x
		_steer(0 if absf(dx) <= 2.5 else int(signf(dx)))
		if mode == "jump" and (elapsed == 0 or (double_jump and elapsed == 22)):
			scene._key(int(scene.CONTROLS.current["jump"]), true)
			jump_presses += 1
		elif elapsed == 1 or elapsed == 23:
			scene._key(int(scene.CONTROLS.current["jump"]), false)
		await scene._ticks(1)
		elapsed += 1
		if not player.is_on_floor():
			airborne_ticks += 1
		var contact := support()
		if String(contact.id).contains("_stairs_"):
			stair_ticks += 1
			stair_ids[String(contact.id)] = true
		var at_target := player.is_on_floor() and String(contact.id) == String(point.surface_id) \
			and absf(player.position.x - target.x) <= 3.0 and absf(player.position.y - target.y) <= 2.0
		settled = settled + 1 if at_target else 0
		if settled >= 6:
			break
	_steer(0)
	scene._key(int(scene.CONTROLS.current["jump"]), false)
	await scene._ticks(6)
	var final_support := support()
	var passed := player.is_on_floor() and String(final_support.id) == String(point.surface_id) \
		and absf(player.position.x - target.x) <= 3.0 and absf(player.position.y - target.y) <= 2.0
	scene._check(passed, "Continuous course reaches " + String(point.id) + " on its actual collider")
	var stair_climb := mode == "walk" and target.y < start.y - 20.0
	if mode == "walk":
		scene._check(jump_presses == 0, "Walking course leg uses no synthetic jump at " + String(point.id))
	if stair_climb:
		scene._check(stair_ticks > 0 and airborne_ticks <= 3, "The original hero walks the actual stair slope to " + String(point.id))
	return {"id": point.id, "mode": mode, "target": [target.x, target.y], "start": [start.x, start.y],
		"position": [player.position.x, player.position.y], "surface_id": final_support.id,
		"support_error": final_support.error, "target_y_error": absf(player.position.y - target.y),
		"jump_presses": jump_presses, "airborne_ticks": airborne_ticks, "stair_contact_ticks": stair_ticks,
		"stair_surface_ids": stair_ids.keys(), "physics_ticks": elapsed, "passed": passed}


func run_course() -> Dictionary:
	scene.CONTROLS.release_actions()
	player.clear_input_buffer()
	player.velocity = Vector2.ZERO
	var start: Array = scene.traversal_layout.route_start
	# The only course setup relocation. Every subsequent waypoint is reached with
	# the same real input events and move_and_slide as normal play.
	player.position = Vector2(float(start[0]), float(start[1]) - 1.0)
	scene._follow_player()
	await scene._ticks(12)
	scene._check(player.is_on_floor(), "The course starts on the original ground")
	await scene._capture("course_00_start")
	var legs: Array[Dictionary] = []
	for index in range(scene.route_waypoints.size()):
		var point: Dictionary = scene.route_waypoints[index]
		var leg := await _drive_waypoint(point)
		legs.append(leg)
		await scene._capture("course_%02d_%s" % [index + 1, String(point.id)])
		if not bool(leg.passed):
			break
	scene._check(legs.size() == scene.route_waypoints.size() and not legs.is_empty() and bool(legs[-1].passed),
		"Every vehicle, second-floor and rooftop waypoint is reached without intermediate relocation")
	scene._check(scene.camera.limit_top == -256 and scene.foreground_covers_view() and scene.near_covers_view()
		and scene.mid_covers_view() and scene.far_covers_view(), "The course camera stays covered by every native art layer")
	return {"setup_relocations": 1, "intermediate_relocations": 0, "waypoints": legs,
		"completed": not legs.is_empty() and legs.size() == scene.route_waypoints.size() and bool(legs[-1].passed)}
