extends Node2D
## "屏息": the held-breath interlude that ends each chapter night. On black, with the breath sound, the dream's
## slogan lines surface one at a time in large type, typed out. Each round (chapter1.json breath[round]) shows
## more of the words; then the story moves to the step's next morning. A pure cutscene: no input.

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const STORY_OVERLAY = preload("res://scripts/ui/story_overlay.gd")
const TYPE_SECONDS := 0.9
const HOLD_SECONDS := 1.1
const FADE_SECONDS := 0.4

var story: Node
var overlay: CanvasLayer
var line_label: Label
## Lines fully shown so far, in order (tests and recordings read it).
var shown_lines: Array[String] = []
var finished := false


func _ready() -> void:
	DisplayServer.window_set_title("夜行者 · 屏息")
	get_tree().root.content_scale_size = Vector2i(320, 180)
	story = STORY_STATE.ensure(get_tree())
	var canvas := CanvasLayer.new()
	canvas.name = "BreathUI"
	add_child(canvas)
	var black := ColorRect.new()
	black.size = Vector2(320, 180)
	black.color = Color.BLACK
	canvas.add_child(black)
	line_label = PIXEL_UI.label(canvas, Vector2.ZERO, Vector2(160, 16), "", PIXEL_UI.FONT_SIZE, true)
	line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	line_label.scale = Vector2(2, 2)
	line_label.position = Vector2(0, 74)
	line_label.self_modulate = Color("d9dee6")
	overlay = STORY_OVERLAY.new()
	overlay.name = "StoryOverlay"
	add_child(overlay)
	_run.call_deferred()


func _run() -> void:
	var rounds: Array = story.chapter.get("breath", [])
	var index := int(story.step_data().get("breath_round", 0))
	var lines: Array = rounds[index] if index < rounds.size() else []
	overlay.play("breath")
	await get_tree().create_timer(0.8).timeout
	for line in lines:
		await _surface(String(line))
	await get_tree().create_timer(0.6).timeout
	finished = true
	get_tree().root.get_node("SceneRoutes").call("travel", String(story.step_data().get("next", "")))


func _surface(line: String) -> void:
	line_label.text = line
	line_label.modulate.a = 1.0
	line_label.visible_characters = 0
	var tween := create_tween()
	tween.tween_property(line_label, "visible_characters", line.length(), TYPE_SECONDS)
	await tween.finished
	shown_lines.append(line)
	await get_tree().create_timer(HOLD_SECONDS).timeout
	tween = create_tween()
	tween.tween_property(line_label, "modulate:a", 0.0, FADE_SECONDS)
	await tween.finished
