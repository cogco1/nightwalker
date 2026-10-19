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


func _press_interact() -> void:
	scene._key(KEY_E, true)
	await scene._ticks(1)
	scene._key(KEY_E, false)


func _walk_to_x(target: float, limit := 240) -> void:
	for _tick in range(limit):
		var dx := target - player.position.x
		_steer(0 if absf(dx) <= 2.0 else int(signf(dx)))
		await scene._ticks(1)
		if absf(dx) <= 2.0 and absf(player.velocity.x) < 0.1:
			break
	_steer(0)
	await scene._ticks(8)


func _ride_elevator(label: String) -> Dictionary:
	var lift: AnimatableBody2D = scene.elevator
	var start: Vector2 = player.position
	var start_y: float = lift.position.y
	await _press_interact()
	scene._check(lift.moving, "A fresh E input starts the docked cage for " + label)
	var ticks := 0
	var grounded_ticks := 0
	var platform_ticks := 0
	var max_error := 0.0
	var minimum_camera_y: float = scene.camera.position.y
	var target_y: float = lift.target_y
	var captured := false
	while lift.moving and ticks < 1800:
		await scene._ticks(1)
		ticks += 1
		if player.is_on_floor():
			grounded_ticks += 1
		var contact := support()
		if String(contact.id) == String(lift.get_meta("surface_id")):
			platform_ticks += 1
		max_error = maxf(max_error, absf(player.position.y - lift.position.y))
		minimum_camera_y = minf(minimum_camera_y, scene.camera.position.y)
		if ticks == 12:
			await _press_interact()
			scene._check(lift.target_y == target_y, "E cannot reverse a moving cage during " + label)
		if not captured and absf(lift.position.y - start_y) > absf(target_y - start_y) * 0.5:
			await scene._capture("elevator_" + label + "_mid")
			captured = true
	await scene._ticks(12)
	scene._check(not lift.moving and is_equal_approx(lift.position.y, target_y), "The cage stops exactly at the landing for " + label)
	scene._check(ticks > 60 and grounded_ticks >= ticks - 3 and platform_ticks >= ticks - 4,
		"Normal CharacterBody2D floor contact carries the hero throughout " + label)
	scene._check(max_error <= 2.0 and absf((player.position.y - start.y) - (target_y - start_y)) <= 2.0,
		"The real moving deck carries the hero without a forced rider offset during " + label)
	scene._check(absf(player.position.x - start.x) <= 1.0 and player.scale == Vector2.ONE,
		"Riding preserves hero control position and native scale during " + label)
	await scene._capture("elevator_" + label + "_dock")
	return {"name": label, "start": [start.x, start.y], "end": [player.position.x, player.position.y],
		"platform_start_y": start_y, "platform_end_y": lift.position.y, "target_y": target_y,
		"physics_ticks": ticks, "grounded_ticks": grounded_ticks, "platform_contact_ticks": platform_ticks,
		"max_foot_error": max_error, "minimum_camera_y": minimum_camera_y}


func run_elevator() -> Dictionary:
	var lift: AnimatableBody2D = scene.elevator
	scene.CONTROLS.release_actions()
	player.clear_input_buffer()
	player.velocity = Vector2.ZERO
	# A separate test setup starts on the adjacent sand. Boarding, riding and
	# disembarking after this point all use ordinary input and actual collisions.
	player.position = Vector2(lift.position.x - 80.0, lift.bottom_y - 1.0)
	await scene._ticks(12)
	await _press_interact()
	scene._check(not lift.moving and lift.position.y == lift.bottom_y, "E outside the landing's range cannot call or start the elevator")
	await _walk_to_x(lift.position.x + lift.width / 2.0)
	scene._check(player.is_on_floor() and absf(player.position.x - lift.position.x - lift.width / 2.0) <= 3.0,
		"The unchanged hero walks from the sand into the open industrial cage")
	var up := await _ride_elevator("01_up")
	scene._check(float(up.minimum_camera_y) <= lift.top_y - 60.0 and scene.foreground_covers_view()
		and scene.near_covers_view() and scene.mid_covers_view() and scene.far_covers_view(),
		"The camera follows the rising rider while every panorama covers the high landing")
	await _walk_to_x(lift.position.x + lift.width + 18.0)
	var roof_contact := support()
	var roof_id := String(scene.traversal_layout.elevator.get("landing_surface_id", ""))
	scene._check(player.is_on_floor() and absf(player.position.y - lift.top_y) <= 2.0
		and not String(roof_contact.id) in ["", "ground", String(lift.get_meta("surface_id"))]
		and (roof_id.is_empty() or String(roof_contact.id) == roof_id),
		"The rider freely walks out of the cage onto the giant building's real roof")
	await scene._capture("elevator_02_roof_exit")
	var roof_position: Vector2 = player.position
	await _press_interact()
	scene._check(lift.moving and lift.target_y == lift.bottom_y, "The landing control sends the empty cage down")
	for _tick in range(1800):
		await scene._ticks(1)
		if not lift.moving:
			break
	scene._check(player.is_on_floor() and player.position.distance_to(roof_position) <= 1.0,
		"Leaving the platform releases the hero; an empty descending cage cannot drag the roof rider")
	await _walk_to_x(lift.position.x + lift.width + lift.call_range + 14.0)
	await _press_interact()
	scene._check(not lift.moving and lift.position.y == lift.bottom_y, "E beyond the upper call range leaves the empty cage at the bottom")
	await _walk_to_x(lift.position.x + lift.width + 18.0)
	await _press_interact()
	scene._check(lift.moving and lift.target_y == lift.top_y, "E at the upper landing calls the distant cage up")
	for _tick in range(1800):
		await scene._ticks(1)
		if not lift.moving:
			break
	scene._check(lift.position.y == lift.top_y and player.is_on_floor(), "The called empty cage docks beside the waiting hero")
	await _walk_to_x(lift.position.x + lift.width / 2.0)
	var down := await _ride_elevator("03_down")
	await _walk_to_x(lift.position.x - 26.0)
	var ground_contact := support()
	scene._check(player.is_on_floor() and String(ground_contact.id) == "ground"
		and absf(player.position.y - lift.bottom_y) <= 2.0,
		"The rider walks out of the docked cage onto the original sand without losing control")
	await scene._capture("elevator_04_ground_exit")
	await _walk_to_x(lift.position.x + lift.width / 2.0)
	await _press_interact()
	await scene._ticks(90)
	var moving_exit_y: float = lift.position.y
	await _walk_to_x(lift.position.x - 18.0)
	await scene._ticks(90)
	var moving_exit_contact := support()
	scene._check(moving_exit_y < lift.bottom_y - 40.0 and player.is_on_floor()
		and String(moving_exit_contact.id) == "ground" and player.position.x < lift.position.x - 6.0,
		"The hero can walk off a moving cage edge and land independently on the sand")
	scene._check(lift.moving and lift.target_y == lift.top_y,
		"The empty cage continues its commanded journey after the moving rider steps off")
	await scene._capture("elevator_05_moving_exit")
	return {"setup_relocations": 1, "intermediate_relocations": 0, "rides": [up, down],
		"roof_surface_id": roof_contact.id, "empty_cage_round_trip": true,
		"moving_edge_exit": {"cage_y_at_exit": moving_exit_y, "landed_surface_id": moving_exit_contact.id,
			"player": [player.position.x, player.position.y]},
		"bottom_stop": lift.bottom_y, "top_stop": lift.top_y, "speed": lift.speed,
		"landing_range": lift.call_range, "final_position": [player.position.x, player.position.y]}


func _ambient_frame(time: float, kind: String = "") -> Image:
	scene.ambient.update_at(time)
	for effect: Dictionary in scene.ambient.effects:
		if not kind.is_empty() and String(effect.kind) != kind:
			effect.node.visible = false
	await scene.get_tree().process_frame
	await RenderingServer.frame_post_draw
	return scene.get_viewport().get_texture().get_image()


func _changed_pixels(first: Image, second: Image, effects: Array) -> int:
	var count := 0
	var rects: Array[Rect2] = []
	for effect: Dictionary in effects:
		var raw: Array = effect.rect
		rects.append(Rect2(Vector2(float(raw[0]), float(raw[1])) - scene.camera.position + Vector2(160, 90), Vector2(float(raw[2]), float(raw[3]))))
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			for rect: Rect2 in rects:
				if rect.has_point(Vector2(x, y)) and not scene._pixel_matches(first.get_pixel(x, y), second.get_pixel(x, y)):
					count += 1
					break
	return count


func run_ambient() -> Dictionary:
	var ambient: Node = scene.ambient
	var saved_time: float = ambient.elapsed
	var saved_position: Vector2 = player.position
	var saved_camera: Vector2 = scene.camera.position
	var saved_animation: bool = player.sprite.is_playing()
	var count_before: int = scene.get_tree().get_node_count()
	var report := {"pool_size": ambient.effects.size(), "update_hz": ambient.update_hz, "draw_scale": 1,
		"steam_frame_size": [ambient.steam_frame_size.x, ambient.steam_frame_size.y],
		"kind_counts": {"lights": 0, "steam": 0, "stars": 0, "dust": 0, "vehicle_smoke": 0, "vehicle_fire": 0},
		"animation_frames": [], "sky_animation_frames": [], "vehicle_animation_frames": [],
		"vehicle_seed": ambient.vehicle_seed, "vehicle_assignments": ambient.vehicle_assignments.duplicate(true), "gpu_probes": [], "intermediate_node_allocations": 0}
	for effect: Dictionary in ambient.effects:
		report.kind_counts[effect.kind] += 1
		var node: Node2D = effect.node
		scene._check(node.scale == Vector2.ONE and node.position == node.position.round(), "Native ambient coordinates: " + String(effect.id))
		if effect.kind != "dust":
			scene._check(node.get_parent() == ambient._layer(effect.layer) and node.z_index == 0,
				"Ambient inherits the exact panorama depth: " + String(effect.id))
	var variants: Dictionary = {}
	for choice: Dictionary in ambient.vehicle_assignments:
		variants[choice.variant_id] = true
	scene._check(ambient.vehicle_assignments.size() == 7 and variants.size() >= 3,
		"The live vehicle pool really uses at least three randomized visual variants across seven wrecks")
	var assignment_snapshot := JSON.stringify(ambient.vehicle_assignments)
	var initial: Array = []
	for effect: Dictionary in ambient.effects:
		initial.append([effect.node.position, effect.node.modulate])
	ambient.update_at(saved_time + 0.8)
	var state_changes := 0
	for index in range(ambient.effects.size()):
		var node: Node2D = ambient.effects[index].node
		if initial[index] != [node.position, node.modulate]:
			state_changes += 1
	scene._check(state_changes > 0 and scene.get_tree().get_node_count() == count_before,
		"Real ambient time changes the fixed pool without per-frame node creation")
	scene._check(JSON.stringify(ambient.vehicle_assignments) == assignment_snapshot, "Vehicle startup choices never reroll as the animation runs")
	report["state_changes"] = state_changes
	if DisplayServer.get_name() != "headless":
		# Freeze only this evidence interval: the earlier/later terrain, roof and lift tests use real physics.
		scene.set_physics_process(false)
		player.set_physics_process(false)
		player.sprite.pause()
		if scene.elevator != null:
			scene.elevator.set_physics_process(false)
		ambient.set_process(false)
		player.position = Vector2(400, scene.ground_y_at(400))
		player.velocity = Vector2.ZERO
		scene.camera.position = Vector2(400, 104)
		scene.camera.force_update_scroll()
		scene.far_background.position.x = roundf((400.0 - 160.0) * (1.0 - scene.FAR_SCROLL_RATIO))
		scene.mid_background.position.x = roundf((400.0 - 160.0) * (1.0 - scene.MID_SCROLL_RATIO))
		for index in range(12):
			var time := 1.0 + float(index) / 8.0
			var frame := await _ambient_frame(time)
			var path: String = scene.OUTPUT + "ambient_animation_%02d.png" % index
			scene._check(frame.save_png(path) == OK, "Write continuous native ambient frame %02d" % index)
			report.animation_frames.append({"png": ProjectSettings.globalize_path(path), "time": time,
				"camera": [400, 104], "effects": ambient.visible_effects()})
		scene.camera.position = Vector2(1008, -106)
		scene.camera.force_update_scroll()
		scene.far_background.position.x = roundf((1008.0 - 160.0) * (1.0 - scene.FAR_SCROLL_RATIO))
		scene.mid_background.position.x = roundf((1008.0 - 160.0) * (1.0 - scene.MID_SCROLL_RATIO))
		for index in range(12):
			var time := 1.0 + float(index) / 8.0
			var frame := await _ambient_frame(time)
			var path: String = scene.OUTPUT + "ambient_sky_animation_%02d.png" % index
			scene._check(frame.save_png(path) == OK, "Write continuous native sky ambient frame %02d" % index)
			report.sky_animation_frames.append({"png": ProjectSettings.globalize_path(path), "time": time,
				"camera": [1008, -106], "effects": ambient.visible_effects()})
		player.position = Vector2(612, 147)
		scene.camera.position = Vector2(616, 104)
		scene.camera.force_update_scroll()
		scene.far_background.position.x = roundf((616.0 - 160.0) * (1.0 - scene.FAR_SCROLL_RATIO))
		scene.mid_background.position.x = roundf((616.0 - 160.0) * (1.0 - scene.MID_SCROLL_RATIO))
		for index in range(12):
			var time := 1.0 + float(index) / 8.0
			var frame := await _ambient_frame(time)
			var path: String = scene.OUTPUT + "ambient_vehicle_animation_%02d.png" % index
			scene._check(frame.save_png(path) == OK, "Write continuous native vehicle smoke/fire frame %02d" % index)
			report.vehicle_animation_frames.append({"png": ProjectSettings.globalize_path(path), "time": time,
				"camera": [616, 104], "effects": ambient.visible_effects()})
		for kind in ["lights", "steam", "stars", "dust", "vehicle_smoke", "vehicle_fire"]:
			var probe := {"kind": kind, "changed_pixels": 0, "camera": [], "first_png": "", "second_png": ""}
			var tried := 0
			for effect: Dictionary in ambient.effects:
				if effect.kind != kind:
					continue
				var camera_x := 400.0
				var camera_y := 104.0
				if kind != "dust":
					var anchor: Vector2 = effect.anchor
					var ratio: float = scene.FAR_SCROLL_RATIO if effect.layer == "far" else (scene.MID_SCROLL_RATIO if effect.layer == "mid" else 1.0)
					camera_x = clampf((anchor.x - 160.0) / ratio + 160.0, 160.0, 5984.0)
					camera_y = clampf(anchor.y - 48.0 if effect.layer == "world" else anchor.y - 256.0 - (15.0 if kind == "steam" else 0.0), -166.0, 166.0)
				scene.camera.position = Vector2(camera_x, camera_y).round()
				scene.camera.force_update_scroll()
				scene.far_background.position.x = roundf((scene.camera.position.x - 160.0) * (1.0 - scene.FAR_SCROLL_RATIO))
				scene.mid_background.position.x = roundf((scene.camera.position.x - 160.0) * (1.0 - scene.MID_SCROLL_RATIO))
				var period := float(effect.data.get("period", 3.0))
				var phase := float(effect.data.get("phase", 0.0))
				var first_time := (2.20 - phase) * period if kind != "dust" else 1.0
				var second_time := (2.72 - phase) * period if kind != "dust" else 2.6
				var first := await _ambient_frame(first_time, kind)
				var first_effects: Array = ambient.visible_effects()
				var second := await _ambient_frame(second_time, kind)
				var changed := _changed_pixels(first, second, first_effects + ambient.visible_effects())
				tried += 1
				if changed > int(probe.changed_pixels):
					var prefix: String = scene.OUTPUT + "ambient_probe_" + kind
					first.save_png(prefix + "_a.png")
					second.save_png(prefix + "_b.png")
					probe = {"kind": kind, "changed_pixels": changed, "camera": [scene.camera.position.x, scene.camera.position.y],
						"first_png": ProjectSettings.globalize_path(prefix + "_a.png"), "second_png": ProjectSettings.globalize_path(prefix + "_b.png"),
						"first_time": first_time, "second_time": second_time, "first_effects": first_effects, "second_effects": ambient.visible_effects()}
				if changed >= (2 if kind == "stars" else 4):
					break
				if tried >= 12:
					break
			scene._check(int(probe.changed_pixels) > 0, "GPU renders real, unoccluded two-frame motion for " + kind)
			report.gpu_probes.append(probe)
		player.position = saved_position
		player.velocity = Vector2.ZERO
		player.set_physics_process(true)
		if saved_animation:
			player.sprite.play()
		scene.set_physics_process(true)
		if scene.elevator != null:
			scene.elevator.set_physics_process(true)
		ambient.set_process(true)
	scene.camera.position = saved_camera
	scene._follow_player()
	ambient.update_at(saved_time)
	report["intermediate_node_allocations"] = scene.get_tree().get_node_count() - count_before
	scene._check(int(report.intermediate_node_allocations) == 0, "Ambient playback keeps its fixed node pool")
	return report
