extends RefCounted
## Shared native 12px text and 48x64 portrait for the 320x180 dialogue canvas.

const PIXEL_FONT = preload("res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.otf")
const SMALL_PIXEL_FONT = preload("res://assets/fonts/fusion-pixel-10px-proportional-zh_hans.otf")
const HERO_PORTRAIT = preload("res://assets/ui/hero_portrait.png")
const FONT_SIZE := 12
## HUD text (status, objective, prompts, hints) in the chapter UI.
const SMALL_FONT_SIZE := 10
const DIALOGUE_SCALE := 0.8
static var _font: FontFile
static var _small_font: FontFile


static func font() -> FontFile:
	if _font == null:
		_font = _pixel_copy(PIXEL_FONT, FONT_SIZE)
	return _font


## The 10px face of the same pixel family, for the HUD.
static func small_font() -> FontFile:
	if _small_font == null:
		_small_font = _pixel_copy(SMALL_PIXEL_FONT, SMALL_FONT_SIZE)
	return _small_font


static func _pixel_copy(source: FontFile, size: int) -> FontFile:
	var copy := source.duplicate() as FontFile
	copy.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	copy.generate_mipmaps = false
	copy.multichannel_signed_distance_field = false
	copy.allow_system_fallback = false
	copy.force_autohinter = false
	copy.hinting = TextServer.HINTING_NONE
	copy.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	copy.oversampling = 0.0
	copy.fixed_size = size
	return copy


## Label on the native grid with the 12px pixel font (or custom_font) that ignores the mouse. dimensions ZERO
## keeps the label's own size; tight sets zero line spacing, used by the dialogue boxes and the safehouse HUD.
static func label(parent: Node, location: Vector2, dimensions := Vector2.ZERO, text := "",
		font_size := FONT_SIZE, tight := false, custom_font: Font = null) -> Label:
	var result := Label.new()
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_override("font", custom_font if custom_font != null else font())
	result.add_theme_font_size_override("font_size", font_size)
	if tight:
		result.add_theme_constant_override("line_spacing", 0)
	result.text = text
	parent.add_child(result)
	result.position = location
	if dimensions != Vector2.ZERO:
		result.size = dimensions
	return result


static func shrink_dialogue(panel: Panel) -> void:
	# Preserve source glyphs, portrait and local layout; resize the complete panel.
	# Composite at window resolution so a12px source stroke survives the80% scale.
	# World sprites and cameras still use their existing integer320x180 coordinates.
	panel.get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_DISABLED
	panel.scale = Vector2.ONE * DIALOGUE_SCALE
	panel.position.x = roundf((320.0 - panel.size.x * DIALOGUE_SCALE) * 0.5)


static func add_portrait(panel: Panel) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.name = "ProtagonistPortrait"
	portrait.position = Vector2(6, 4)
	portrait.size = Vector2(48, 64)
	portrait.texture = HERO_PORTRAIT
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(portrait)
	return portrait


static func set_speaker(portrait: TextureRect, title: Label, body: Label, footer: Label,
		speaker: String, context: String) -> void:
	var is_protagonist := speaker == "protagonist"
	portrait.visible = is_protagonist
	var left := 60.0 if is_protagonist else 6.0
	for field in [title, body, footer]:
		field.position.x = left
		field.size.x = 278.0 - left
	var speaker_name := "独白"
	match speaker:
		"television": speaker_name = "电视播报"
		"qiaolun": speaker_name = "乔伦 · 留言"
		"terminal": speaker_name = "终端"
		"sk_reply": speaker_name = "我 · 回复"
		"sound": speaker_name = "声音"
		"doctor": speaker_name = "医生"
	title.text = speaker_name + " · " + context
