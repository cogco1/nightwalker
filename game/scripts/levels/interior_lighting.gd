extends Node2D
## Shared interior look. The host owns one helper; rebuilding a hospital World
## replaces only its native-grid rig and rebinds the new player's own material.

const SETTINGS_PATH := "res://assets/lighting/interiors.json"
const EMISSIVE := preload("res://shaders/emissive_add.gdshader")
const FOG := preload("res://shaders/interior_fog.gdshader")
const LIT_MASK := 1

var world_root: Node2D
var hero: CharacterBody2D
var context: Dictionary = {}
var lights: Array[PointLight2D] = []
## The first day's three floor-2 moving surveillance lights, sharing the visible/exposure source records.
var patrols: Array[Dictionary] = []
var ambient: CanvasModulate
var glow: WorldEnvironment
var rig: Node2D
var power_states: Dictionary = {}
var source_power: Dictionary = {}
var _settings: Dictionary = {}
var _profile: Dictionary = {}
var _hero_material: ShaderMaterial
var _sources: Array[Dictionary] = []
var _light_textures: Dictionary = {}
var _clock := 0.0
var _last_tick := -1
var _patrol_settings: Dictionary = {}
var _patrol_clock := 0.0
var _day_patrol := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_priority = 110
	_settings = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	_patrol_settings = {}
	ambient = CanvasModulate.new()
	ambient.name = "InteriorAmbient"
	add_child(ambient)
	glow = WorldEnvironment.new()
	glow.name = "InteriorGlow"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.background_canvas_max_layer = 1
	environment.glow_enabled = true
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	glow.environment = environment
	add_child(glow)


## context: profile(home/hospital), layout(active view), base_layout, view_mode,
## floor_id. No camera or player physics values are changed by this helper.
func refresh_context(next_world: Node2D, next_hero: CharacterBody2D, next_context: Dictionary) -> void:
	if is_instance_valid(rig):
		var previous_parent := rig.get_parent()
		if previous_parent != null:
			previous_parent.remove_child(rig)
		rig.queue_free()
	world_root = next_world
	hero = next_hero
	context = next_context.duplicate(true)
	_profile = _settings.get(String(context.get("profile", "home")), {})
	ambient.color = Color(String(_profile.get("ambient", "c4cbdc")))
	glow.environment.glow_intensity = float(_profile.get("glow_intensity", 0.45))
	lights.clear()
	_sources.clear()
	patrols.clear()
	_patrol_clock = 0.0
	_day_patrol = _uses_day_patrols()
	rig = Node2D.new()
	rig.name = "InteriorLightRig"
	rig.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_root.add_child(rig)
	var holder := Node2D.new()
	holder.name = "Lights"
	rig.add_child(holder)
	var fixture_holder := Node2D.new()
	fixture_holder.name = "FixtureEmission"
	# The safehouse redraws its animated screens at z1. Emission and off covers
	# must composite above those same screen pixels, without covering the UI.
	fixture_holder.z_index = 2
	rig.add_child(fixture_holder)
	var layout: Dictionary = context.get("layout", {})
	var background := world_root.get_node_or_null("HomeBackground") as Sprite2D
	if background == null:
		background = world_root.get_node_or_null("HospitalBackground") as Sprite2D
	if String(context.get("profile", "home")) == "home":
		for item in _profile.get("screens", []):
			_add_source(item, "screen", holder, fixture_holder, background)
		for item in _profile.get("lamps", []):
			_add_source(item, "lamp", holder, fixture_holder, background)
	else:
		for item in layout.get("fluorescents", []):
			_add_source(item, "fluorescent", holder, fixture_holder, background)
		for item in layout.get("monitors", []):
			_add_source(item, "screen", holder, fixture_holder, background)
		var key := "emergency_side_view" if int(context.get("view_mode", 0)) == 1 else "emergency_top_down_%d" % int(context.get("floor_id", 1))
		for item in _profile.get(key, []):
			_add_source(item, "emergency", holder, fixture_holder, background)
		if _day_patrol:
			for item in _patrol_settings.get("sources", []):
				_add_source(item, "patrol", holder, fixture_holder, background)
	_build_fog(layout)
	var sprite := hero.get_node_or_null("Sprite") as AnimatedSprite2D
	_hero_material = sprite.material as ShaderMaterial if sprite != null else null
	if _hero_material != null:
		_hero_material.set_shader_parameter("emission_lift", Vector3(1.0 / ambient.color.r, 1.0 / ambient.color.g, 1.0 / ambient.color.b))
		_hero_material.set_shader_parameter("emission_gain", 1.3)
		_hero_material.set_shader_parameter("body_lift", float(_profile.get("body_lift", 1.15)))
		_hero_material.set_shader_parameter("shade_edge_color", Color(0.035, 0.055, 0.075, 0.40))
		_hero_material.set_shader_parameter("glow_strength", 0.65)
	_update_sources()
	_place_patrols()
	_update_hero_light()


## Chapter-only challenge; the sandbox, safehouse, first floor and every side view keep their old lights.
func _uses_day_patrols() -> bool:
	if String(context.get("profile", "")) != "hospital" or int(context.get("view_mode", 0)) != 0 \
			or int(context.get("floor_id", 1)) != 2:
		return false
	var chapter: Node = get_parent().get("chapter")
	if not is_instance_valid(chapter):
		return false
	var story: Node = chapter.get("story")
	return is_instance_valid(story) and story.chapter_active and story.step in ["d1_hospital", "d1_target_down"]


func set_power_states(states: Dictionary) -> void:
	if power_states == states:
		return
	power_states = states.duplicate(true)
	_update_sources()
	_update_hero_light()


func set_source_power(source_id: String, powered: bool) -> void:
	source_power[source_id] = powered
	_update_sources()
	_update_hero_light()


func _add_source(item: Dictionary, kind: String, holder: Node2D, fixture_holder: Node2D, background: Sprite2D) -> void:
	var id := String(item.get("id", kind))
	var values: Array = item.get("rect", [])
	var rectangle := Rect2()
	var at := Vector2.ZERO
	if values.size() == 4:
		rectangle = Rect2(values[0], values[1], values[2], values[3])
		at = rectangle.get_center().round()
	else:
		var coordinates: Array = item.get("position", [0, 0])
		at = Vector2(coordinates[0], coordinates[1]).round()
	var side := int(context.get("view_mode", 0)) == 1
	var radius := float(item.get("radius", 108.0 if side and kind == "fluorescent" else 76.0 if kind == "fluorescent" else 40.0))
	var energy := float(item.get("energy", 0.34 if kind == "fluorescent" else 0.24))
	if _day_patrol and kind == "fluorescent":
		energy = float(_patrol_settings.get("fluorescent_energy", 0.19))
	var colour := Color(String(item.get("colour", "79c1d3" if kind == "screen" else "88bac7")))
	if kind == "emergency":
		radius = 42.0
		energy = 0.14
		colour = Color("c98782")
	var light := PointLight2D.new()
	light.name = "Light_" + id
	light.position = at
	var source_floor := int(context.get("floor_id", 1))
	var vertical_span := Vector2(-10000, 10000)
	var reach := Rect2(-10000, -10000, 20000, 20000)
	if side:
		source_floor = 2 if at.y < 170.0 else 1
		vertical_span = Vector2(64, 164) if source_floor == 2 else Vector2(176, 287)
		reach = Rect2(-10000, vertical_span.x, 20000, vertical_span.y - vertical_span.x)
	else:
		reach = _zone_rect(item, at, reach)
	light.texture = _banded_texture(roundi(radius), Rect2(reach.position - at, reach.size))
	light.texture_scale = 1.0
	light.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	light.color = colour
	light.energy = energy
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.range_item_cull_mask = LIT_MASK
	light.set_meta("source_id", id)
	light.set_meta("kind", kind)
	light.set_meta("radius", radius)
	light.set_meta("floor_id", source_floor)
	light.set_meta("vertical_span", vertical_span)
	light.set_meta("reach", reach)
	# Surveillance has its own supply; a room's breaker never removes these moving pools.
	var section := "" if kind in ["emergency", "patrol"] else _power_section(rectangle, at)
	light.set_meta("power_section", section)
	holder.add_child(light)
	lights.append(light)
	var emission: CanvasItem
	var cover: ColorRect
	if kind == "emergency":
		var core := ColorRect.new()
		core.position = at - Vector2.ONE
		core.size = Vector2(2, 1)
		core.color = Color(colour, 0.65)
		core.mouse_filter = Control.MOUSE_FILTER_IGNORE
		emission = core
	elif background != null and rectangle.has_area():
		var crop := AtlasTexture.new()
		crop.atlas = background.texture
		crop.region = rectangle
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.position = rectangle.position
		sprite.texture = crop
		emission = sprite
		cover = ColorRect.new()
		cover.name = "Off_" + id
		cover.position = rectangle.position
		cover.size = rectangle.size
		cover.color = Color(0.025, 0.045, 0.065, 0.94)
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fixture_holder.add_child(cover)
	# The floor-2 corridor paints each lamp's pool into the floor art; off, a generated cover takes it away
	# (tools/art/gen_lamp_off_covers.py) so the picture agrees with the stealth light test.
	var pool: Sprite2D
	var off_cover: Dictionary = item.get("off_cover", {})
	if not off_cover.is_empty() and ResourceLoader.exists(String(off_cover["texture"])):
		var covers := rig.get_node_or_null("LampOffCovers") as Node2D
		if covers == null:
			covers = Node2D.new()
			covers.name = "LampOffCovers"
			covers.z_index = -9
			rig.add_child(covers)
		pool = Sprite2D.new()
		pool.name = "PoolOff_" + id
		pool.centered = false
		pool.texture = load(String(off_cover["texture"]))
		pool.position = Vector2(off_cover["position"][0], off_cover["position"][1])
		covers.add_child(pool)
	if emission != null:
		emission.name = "Emission_" + id
		var material := ShaderMaterial.new()
		material.shader = EMISSIVE
		material.set_shader_parameter("gain", 1.4 if kind == "screen" else 1.65)
		material.set_shader_parameter("flicker", 0.09 if kind == "fluorescent" else 0.0)
		emission.material = material
		fixture_holder.add_child(emission)
	var source := {"id": id, "kind": kind, "light": light, "emission": emission, "cover": cover,
		"section": section, "energy": energy, "radius": radius, "reach": reach, "pool": pool}
	_sources.append(source)
	if kind == "patrol":
		var start: Array = item["from"]
		var end: Array = item["to"]
		source["from"] = Vector2(start[0], start[1])
		source["to"] = Vector2(end[0], end[1])
		source["period"] = float(item["period"])
		source["phase"] = float(item.get("phase", 0.0))
		patrols.append(source)


## Top-down walls stop light: a source lights only its room or corridor (layout light_zones). A lamp on a wall
## names its zone; screens and emergency lights sit inside theirs. No zones (the safehouse): unbounded.
func _zone_rect(item: Dictionary, at: Vector2, unbounded: Rect2) -> Rect2:
	var zones: Array = context.get("layout", {}).get("light_zones", [])
	var wanted := String(item.get("zone", ""))
	for zone: Dictionary in zones:
		var values: Array = zone["rect"]
		var area := Rect2(values[0], values[1], values[2], values[3])
		if String(zone["id"]) == wanted or (wanted.is_empty() and area.has_point(at)):
			return area
	return unbounded


## How strongly the powered sources light a world point, with the same bands and reach the light textures
## are drawn with: a fluorescent core reads 0.34, a dim emergency light's core 0.14, darkness 0.
func light_level(point: Vector2) -> float:
	var level := 0.0
	for entry in _sources:
		var light: PointLight2D = entry["light"]
		if not light.enabled or not Rect2(entry["reach"]).has_point(point):
			continue
		level += float(entry["energy"]) * band(point.distance_to(light.global_position) / float(entry["radius"]))
	return level


## Discrete falloff of every interior light (centre to rim), shared by the textures and light_level().
static func band(distance: float) -> float:
	return 1.0 if distance < 0.26 else 0.55 if distance < 0.50 else 0.24 if distance < 0.73 else 0.08 if distance < 0.94 else 0.0


func _power_section(rectangle: Rect2, at: Vector2) -> String:
	var base: Dictionary = context.get("base_layout", {})
	var view_key := "top_down" if int(context.get("view_mode", 0)) == 0 else "side_view"
	for section_id in base.get("power_sections", {}):
		var view: Dictionary = base["power_sections"][section_id].get(view_key, {})
		if view_key == "top_down" and int(view.get("floor_id", context.get("floor_id", 1))) != int(context.get("floor_id", 1)):
			continue
		for key in ["screen_rects", "darken_rects"]:
			for area in view.get(key, []):
				var region := Rect2(area[0], area[1], area[2], area[3])
				if region.has_point(at) or (rectangle.has_area() and region.intersects(rectangle)):
					return String(section_id)
	return ""


func _update_sources() -> void:
	for entry in _sources:
		var powered := bool(source_power.get(entry["id"], true))
		if not String(entry["section"]).is_empty():
			powered = powered and bool(power_states.get(entry["section"], true))
		var light: PointLight2D = entry["light"]
		light.enabled = powered
		light.energy = float(entry["energy"]) if powered else 0.0
		if is_instance_valid(entry["emission"]):
			entry["emission"].visible = powered
		if is_instance_valid(entry["cover"]):
			entry["cover"].visible = not powered
		if is_instance_valid(entry["pool"]):
			entry["pool"].visible = not powered


func _process(delta: float) -> void:
	_clock += delta
	if not patrols.is_empty() and not _patrol_motion_blocked():
		_patrol_clock += delta
		_place_patrols()
	# Mirror the prop animation's discrete cadence, never modulating body scale.
	var tick := int(_clock * 12.0)
	if tick != _last_tick:
		_last_tick = tick
		for entry in _sources:
			var light: PointLight2D = entry["light"]
			if light.enabled and entry["kind"] == "fluorescent":
				light.energy = float(entry["energy"]) * (0.91 if (tick + int(light.position.x)) % 71 in [0, 1] else 1.0)
	_update_hero_light()


## Pause the route as well as the hero while reading, entering a code, changing floors or playing a scene.
func _patrol_motion_blocked() -> bool:
	if get_tree().paused or not is_instance_valid(hero) or hero.is_frozen():
		return true
	var host := get_parent()
	var chapter: Node = host.get("chapter")
	if not is_instance_valid(chapter) or chapter.busy or bool(host.get("stairs_busy")):
		return true
	var overlay: Node = chapter.get("overlay")
	if is_instance_valid(overlay) and (overlay.busy or overlay.shade.color.a > 0.01):
		return true
	var session := host.get_node_or_null("GameSession")
	return session != null and (session.settings_open or session.hit_stop_active or session.has_modal())


## Cached disks on horizontal rails, with no painted centre marker. The horizontal span stays inside its
## room; the fixed-height texture clipping and gameplay reach share the same wall boundaries.
func _place_patrols() -> void:
	for source in patrols:
		var phase := _patrol_clock / float(source["period"]) + float(source["phase"])
		var progress := 0.5 - 0.5 * cos(TAU * phase)
		var at := Vector2(source["from"]).lerp(Vector2(source["to"]), progress).round()
		var light: PointLight2D = source["light"]
		light.position = at


func _update_hero_light() -> void:
	if _hero_material == null or not is_instance_valid(hero):
		return
	var chest := hero.global_position + Vector2(0, -16)
	var candidates: Array = []
	for light in lights:
		if not is_instance_valid(light) or not light.enabled:
			continue
		if int(context.get("view_mode", 0)) == 1:
			var hero_floor := 2 if hero.global_position.y <= 164.0 else 1
			if int(light.get_meta("floor_id")) != hero_floor:
				continue
		elif not Rect2(light.get_meta("reach")).has_point(hero.global_position):
			continue
		var offset := light.global_position - chest
		var influence := light.energy * clampf(1.0 - offset.length() / float(light.get_meta("radius")), 0.0, 1.0)
		if influence > 0.003:
			candidates.append([influence, offset.normalized(), light.color])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var rims := [[Vector2.UP, Color("8cbdce"), 0.025], [Vector2.RIGHT, Color("708da5"), 0.0]]
	for index in range(mini(2, candidates.size())):
		rims[index] = [candidates[index][1], candidates[index][2], clampf(float(candidates[index][0]) * 1.15, 0.0, 0.55)]
	_hero_material.set_shader_parameter("rim_a_dir", rims[0][0])
	_hero_material.set_shader_parameter("rim_a_color", Color(rims[0][1], rims[0][2]))
	_hero_material.set_shader_parameter("rim_b_dir", rims[1][0])
	_hero_material.set_shader_parameter("rim_b_color", Color(rims[1][1], rims[1][2]))
	var strongest: Array = candidates[0] if not candidates.is_empty() else [0.0, Vector2.UP, Color("93adbe")]
	_hero_material.set_shader_parameter("reflect_strength", clampf(0.07 + float(strongest[0]) * 1.6, 0.07, 0.72))
	_hero_material.set_shader_parameter("reflect_color", Color(strongest[2]).lightened(0.18))
	var implant := hero.get_node_or_null("Sprite/ImplantOverlay")
	if implant != null:
		implant.set("scanned", 0.0)


func _build_fog(_layout: Dictionary) -> void:
	var areas: Array = []
	if String(context.get("profile", "home")) == "home":
		areas = [Rect2(26, 94, 268, 57)]
	elif int(context.get("view_mode", 0)) == 0:
		areas = [Rect2(21, 145, 598, 45)]
	else:
		areas = [Rect2(23, 141, 594, 22), Rect2(23, 263, 594, 22)]
	var holder := Node2D.new()
	holder.name = "InteriorFog"
	holder.z_index = 4
	rig.add_child(holder)
	for area: Rect2 in areas:
		var fog := ColorRect.new()
		fog.position = area.position
		fog.size = area.size
		fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = FOG
		material.set_shader_parameter("native_size", area.size)
		material.set_shader_parameter("native_origin", area.position)
		material.set_shader_parameter("band_top", area.position.y)
		material.set_shader_parameter("band_bottom", area.end.y)
		material.set_shader_parameter("density", float(_profile.get("fog_density", 0.05)))
		fog.material = material
		holder.add_child(fog)


## relative_reach: the light's reach relative to its centre; texels outside it stay black.
func _banded_texture(radius: int, relative_reach: Rect2) -> ImageTexture:
	var key := "%d:%s" % [radius, relative_reach]
	if _light_textures.has(key):
		return _light_textures[key]
	var size := radius * 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var local := Vector2(x + 0.5 - radius, y + 0.5 - radius)
			if not relative_reach.has_point(local):
				image.set_pixel(x, y, Color(0, 0, 0, 1))
				continue
			var level := band(local.length() / float(radius))
			image.set_pixel(x, y, Color(level, level, level, 1.0))
	var texture := ImageTexture.create_from_image(image)
	_light_textures[key] = texture
	return texture
