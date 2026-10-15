extends RefCounted
## Shared native 12px text and 48x64 portrait for the 320x180 dialogue canvas.

const PIXEL_FONT = preload("res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.otf")
const HERO_PORTRAIT = preload("res://assets/ui/hero_portrait.png")
const FONT_SIZE := 12
const DIALOGUE_SCALE := 0.8
static var _font: FontFile


static func font() -> FontFile:
	if _font == null:
		_font = PIXEL_FONT.duplicate() as FontFile
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.generate_mipmaps = false
		_font.multichannel_signed_distance_field = false
		_font.allow_system_fallback = false
		_font.force_autohinter = false
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font.oversampling = 0.0
		_font.fixed_size = FONT_SIZE
	return _font


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
	for label in [title, body, footer]:
		label.position.x = left
		label.size.x = 278.0 - left
	var speaker_name := "独白"
	match speaker:
		"television": speaker_name = "电视播报"
		"qiaolun": speaker_name = "乔伦 · 留言"
		"terminal": speaker_name = "终端"
	title.text = speaker_name + " · " + context
