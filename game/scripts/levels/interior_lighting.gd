extends Node2D
## Shared interior look (a profile of assets/lighting/interiors.json; the safehouse is the only one). The host
## owns one helper; refresh_context() replaces only its native-grid rig and rebinds the new player's own material.

const SETTINGS_PATH := "res://assets/lighting/interiors.json"
const EMISSIVE := preload("res://shaders/emissive_add.gdshader")
const FOG := preload("res://shaders/interior_fog.gdshader")
const LIT_MASK := 1

var world_root: Node2D
var hero: CharacterBody2D
var context: Dictionary = {}
var lights: Array[PointLight2D] = []
var ambient: CanvasModulate
var glow: WorldEnvironment
var rig: Node2D
var source_power: Dictionary = {}
var _settings: Dictionary = {}
var _profile: Dictionary = {}
var _hero_material: ShaderMaterial
var _sources: Array[Dictionary] = []
var _light_textures: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_priority = 110
	_settings = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
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


## context: profile (a key of interiors.json). No camera or player physics values are changed by this helper.
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
	var background := world_root.get_node_or_null("HomeBackground") as Sprite2D
	for item in _profile.get("screens", []):
		_add_source(item, "screen", holder, fixture_holder, background)
	for item in _profile.get("lamps", []):
		_add_source(item, "lamp", holder, fixture_holder, background)
	_build_fog()
	var sprite := hero.get_node_or_null("Sprite") as AnimatedSprite2D
	_hero_material = sprite.material as ShaderMaterial if sprite != null else null
	if _hero_material != null:
		_hero_material.set_shader_parameter("emission_lift", Vector3(1.0 / ambient.color.r, 1.0 / ambient.color.g, 1.0 / ambient.color.b))
		_hero_material.set_shader_parameter("emission_gain", 1.3)
		_hero_material.set_shader_parameter("body_lift", float(_profile.get("body_lift", 1.15)))
		_hero_material.set_shader_parameter("shade_edge_color", Color(0.035, 0.055, 0.075, 0.40))
		_hero_material.set_shader_parameter("glow_strength", 0.65)
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
	var radius := float(item.get("radius", 40.0))
	var energy := float(item.get("energy", 0.24))
	var colour := Color(String(item.get("colour", "79c1d3" if kind == "screen" else "88bac7")))
	var light := PointLight2D.new()
	light.name = "Light_" + id
	light.position = at
	light.texture = _banded_texture(roundi(radius))
	light.texture_scale = 1.0
	light.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	light.color = colour
	light.energy = energy
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.range_item_cull_mask = LIT_MASK
	light.set_meta("source_id", id)
	light.set_meta("kind", kind)
	light.set_meta("radius", radius)
	holder.add_child(light)
	lights.append(light)
	var emission: CanvasItem
	var cover: ColorRect
	if background != null and rectangle.has_area():
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
	if emission != null:
		emission.name = "Emission_" + id
		var material := ShaderMaterial.new()
		material.shader = EMISSIVE
		material.set_shader_parameter("gain", 1.4 if kind == "screen" else 1.65)
		emission.material = material
		fixture_holder.add_child(emission)
	_sources.append({"id": id, "kind": kind, "light": light, "emission": emission, "cover": cover, "energy": energy})


## Discrete falloff of every interior light (centre to rim), used by the light textures.
static func band(distance: float) -> float:
	return 1.0 if distance < 0.26 else 0.55 if distance < 0.50 else 0.24 if distance < 0.73 else 0.08 if distance < 0.94 else 0.0


func _update_sources() -> void:
	for entry in _sources:
		var powered := bool(source_power.get(entry["id"], true))
		var light: PointLight2D = entry["light"]
		light.enabled = powered
		light.energy = float(entry["energy"]) if powered else 0.0
		if is_instance_valid(entry["emission"]):
			entry["emission"].visible = powered
		if is_instance_valid(entry["cover"]):
			entry["cover"].visible = not powered


func _process(_delta: float) -> void:
	_update_hero_light()


func _update_hero_light() -> void:
	if _hero_material == null or not is_instance_valid(hero):
		return
	var chest := hero.global_position + Vector2(0, -16)
	var candidates: Array = []
	for light in lights:
		if not is_instance_valid(light) or not light.enabled:
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


func _build_fog() -> void:
	var areas: Array = [Rect2(26, 94, 268, 57)]
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


func _banded_texture(radius: int) -> ImageTexture:
	if _light_textures.has(radius):
		return _light_textures[radius]
	var size := radius * 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var local := Vector2(x + 0.5 - radius, y + 0.5 - radius)
			var level := band(local.length() / float(radius))
			image.set_pixel(x, y, Color(level, level, level, 1.0))
	var texture := ImageTexture.create_from_image(image)
	_light_textures[radius] = texture
	return texture
