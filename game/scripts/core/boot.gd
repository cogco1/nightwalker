extends Node
## Main entry: the repository's factory/sand prologue and the requested combat whitebox.

const CONTROLS = preload("res://scripts/core/controls.gd")
const UI = preload("res://scripts/ui/pixel_ui.gd")
const WHITEBOX := "res://scenes/whitebox_test.tscn"
const PROLOGUE := "res://scenes/battlefield_run_test.tscn"


func _ready() -> void:
	CONTROLS.install()
	get_tree().root.content_scale_size=Vector2i(320,180)
	get_tree().root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_tree().root.title="夜行者"
	var canvas := CanvasLayer.new()
	canvas.name="EntryUI"
	add_child(canvas)
	var background := ColorRect.new()
	background.size=Vector2(320,180)
	background.color=Color("20252b")
	canvas.add_child(background)
	var title := UI.label(canvas,Vector2(100,44),Vector2(120,20),"夜行者",16)
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var prologue := Button.new()
	prologue.name="EnterPrologue"
	prologue.text="序章 · 工厂黄沙"
	prologue.position=Vector2(88,78)
	prologue.size=Vector2(144,28)
	prologue.add_theme_font_override("font",UI.font())
	prologue.add_theme_font_size_override("font_size",12)
	prologue.pressed.connect(open_prologue)
	canvas.add_child(prologue)
	var button := Button.new()
	button.name="EnterWhitebox"
	button.text="进入白盒测试"
	button.position=Vector2(88,114)
	button.size=Vector2(144,28)
	button.add_theme_font_override("font",UI.font())
	button.add_theme_font_size_override("font_size",12)
	button.pressed.connect(open_whitebox)
	canvas.add_child(button)
	prologue.grab_focus()

func open_prologue() -> void:
	CONTROLS.release_actions()
	get_tree().paused=false
	get_tree().change_scene_to_file.call_deferred(PROLOGUE)

func open_whitebox() -> void:
	CONTROLS.release_actions()
	get_tree().paused=false
	get_tree().change_scene_to_file.call_deferred(WHITEBOX)
