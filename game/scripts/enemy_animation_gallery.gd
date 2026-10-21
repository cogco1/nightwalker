extends Node2D
## Standalone art viewer: no enemy combat AI, chapter routes or gameplay scenes are changed.
## Launch with -- --enemy-gallery-smoke to record actual viewport frames and exit.

const MANIFEST_PATH := "res://assets/enemy_animations_v01/manifest.json"
const OUTPUT := "res://evidence/enemy_animation_gallery/"
const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const VIEWPORT_SIZE := Vector2i(320, 180)
const BASE_Y := 125
const ACTION_NAMES := {
	"idle": "待机", "hover": "悬浮", "laser": "激光发射", "walk": "行走", "fire": "开火",
	"attack": "近战攻击", "prone_down": "卧倒", "prone_crawl": "匍匐", "prone_fire": "卧射",
	"prone_idle": "卧姿待机", "prone_up": "起身",
}

var manifest: Dictionary = {}
var units: Array = []
var current_unit := 0
var current_action := "idle"
var action_names: Array[String] = []
var actor: Node2D
var sprite: AnimatedSprite2D
var title_label: Label
var action_label: Label
var unit_label: Label
var ready_for_test := false
var paused := false
var prone := false
var _x := 160.0
var _transition_action := ""
var _recording := false
var _moving_by_input := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var window := get_tree().root
	window.content_scale_size = VIEWPORT_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	window.title = "夜行者 · 外骨骼敌人动作预览 v01"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary or not parsed.has("units"):
		push_error("Enemy animation manifest is missing or invalid")
		return
	manifest = parsed
	units = manifest.units
	actor = Node2D.new()
	actor.name = "ArtPreview"
	actor.position = Vector2(_x, BASE_Y)
	add_child(actor)
	sprite = AnimatedSprite2D.new()
	sprite.name = "NativeEnemy"
	sprite.centered = false
	actor.add_child(sprite)
	sprite.animation_finished.connect(_on_animation_finished)
	_build_ui()
	ready_for_test = select_unit(0)
	_recording = OS.get_cmdline_user_args().has("--enemy-gallery-smoke")
	if _recording:
		_record_evidence.call_deferred()


func _build_ui() -> void:
	title_label = PIXEL_UI.label(self, Vector2(9, 6), Vector2(302, 14), "", 12)
	unit_label = PIXEL_UI.label(self, Vector2(9, 23), Vector2(302, 12), "", 10, true, PIXEL_UI.small_font())
	action_label = PIXEL_UI.label(self, Vector2(9, 39), Vector2(302, 12), "", 10, true, PIXEL_UI.small_font())
	PIXEL_UI.label(self, Vector2(9, 143), Vector2(302, 12), "← → / 1—2 换兵种　↑ ↓ 换动作", 10, true, PIXEL_UI.small_font())
	PIXEL_UI.label(self, Vector2(9, 157), Vector2(302, 12), "A D 移动　F 攻击　S 卧倒　空格暂停", 10, true, PIXEL_UI.small_font())


func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color("11181c"))
	draw_rect(Rect2(0, 56, 320, 70), Color("1b252a"))
	for x in range(0, 320, 40):
		draw_rect(Rect2(x, 57, 1, 68), Color("223036"))
		draw_rect(Rect2(x + 2, 59, 1, 1), Color("405056"))
	draw_rect(Rect2(0, 126, 320, 13), Color("484735"))
	draw_rect(Rect2(0, 125, 320, 1), Color("9e8a52"))
	for x in range(0, 320, 8):
		draw_rect(Rect2(x, 133 + x % 3, 2, 1), Color("626044"))
	draw_rect(Rect2(0, 140, 320, 1), Color("334047"))


func select_unit(index: int) -> bool:
	if units.is_empty():
		return false
	current_unit = posmod(index, units.size())
	var unit: Dictionary = units[current_unit]
	var resource_path := "res://assets/enemy_animations_v01/%s/animations.tres" % unit.unit
	var frames := load(resource_path) as SpriteFrames
	if frames == null:
		push_error("Enemy animation resource is missing: " + resource_path)
		return false
	sprite.sprite_frames = frames
	action_names.assign(["idle"])
	for action: Dictionary in unit.actions:
		action_names.append(action.name)
	if unit.unit == "sniper_B":
		action_names.append("prone_idle")
		action_names.append("prone_up")
	prone = false
	_transition_action = ""
	_moving_by_input = false
	_x = 160.0
	actor.position = Vector2(_x, BASE_Y)
	set_facing(false)
	title_label.text = "%s · %s %s" % [unit.code, unit.callsign, unit.variant]
	unit_label.text = "%d / %d　%s" % [current_unit + 1, units.size(), unit.name]
	return select_action("hover" if unit.unit == "laser_drone_B" else "idle")


func set_facing(left: bool) -> void:
	sprite.flip_h = left
	var cell: Array = manifest.cell_size
	var anchor: Array = manifest.foot_anchor
	sprite.position = Vector2(-(int(cell[0]) - int(anchor[0])) if left else -int(anchor[0]), -int(anchor[1]))


func select_action(action: String) -> bool:
	if not sprite.sprite_frames.has_animation("right_" + action):
		return false
	current_action = action
	prone = action.begins_with("prone_") and action != "prone_up"
	sprite.play("right_" + action)
	sprite.set_frame_and_progress(0, 0.0)
	if paused:
		sprite.pause()
	action_label.text = "%s　%d 帧 · %d fps · 原生像素 1:1" % [
		ACTION_NAMES.get(action, action), sprite.sprite_frames.get_frame_count(sprite.animation),
		int(sprite.sprite_frames.get_animation_speed(sprite.animation))]
	return true


func trigger_attack() -> void:
	var unit: Dictionary = units[current_unit]
	if unit.unit == "sniper_B" and current_action == "prone_down":
		_transition_action = "prone_fire"
		return
	if current_action == "prone_up":
		return
	if unit.unit == "sniper_B" and not prone:
		_transition_action = "prone_fire"
		select_action("prone_down")
	elif unit.unit == "sniper_B":
		select_action("prone_fire")
	elif unit.unit == "laser_drone_B":
		select_action("laser")
	else:
		select_action("attack" if unit["class"] in ["blade_assault", "breacher"] else "fire")


func toggle_prone() -> void:
	if units[current_unit].unit == "sniper_B":
		if current_action in ["prone_down", "prone_up"]:
			return
		_transition_action = ""
		select_action("prone_up" if prone else "prone_down")


func _on_animation_finished() -> void:
	if _recording:
		return
	if current_action == "prone_down":
		var next := _transition_action if not _transition_action.is_empty() else "prone_idle"
		_transition_action = ""
		select_action(next)
	elif current_action == "prone_fire":
		select_action("prone_idle")
	elif current_action == "prone_up":
		select_action("idle")
	elif current_action in ["fire", "attack", "laser"]:
		select_action("hover" if units[current_unit].unit == "laser_drone_B" else "idle")


func _unhandled_key_input(event: InputEvent) -> void:
	if _recording or not ready_for_test or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE: get_tree().quit()
		KEY_RIGHT: select_unit(current_unit + 1)
		KEY_LEFT: select_unit(current_unit - 1)
		KEY_UP, KEY_DOWN:
			var offset := 1 if event.keycode == KEY_DOWN else -1
			_transition_action = ""
			_moving_by_input = false
			select_action(action_names[posmod(action_names.find(current_action) + offset, action_names.size())])
		KEY_F: trigger_attack()
		KEY_S: toggle_prone()
		KEY_SPACE:
			paused = not paused
			if paused: sprite.pause()
			else: sprite.play()
		_:
			if event.keycode >= KEY_1 and event.keycode <= KEY_2:
				select_unit(event.keycode - KEY_1)


func _process(delta: float) -> void:
	if not ready_for_test or _recording or paused:
		return
	var direction := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	if direction != 0.0:
		set_facing(direction < 0.0)
		var move_action := "prone_crawl" if prone else "walk"
		if units[current_unit].unit == "laser_drone_B":
			move_action = "hover"
		if current_action in ["idle", "walk", "hover", "prone_idle", "prone_crawl"]:
			if current_action != move_action:
				select_action(move_action)
			_moving_by_input = true
			_x = clampf(_x + direction * (14.0 if prone else 32.0) * delta, 48.0, 272.0)
			actor.position.x = roundf(_x)
	elif _moving_by_input:
		_moving_by_input = false
		if current_action == "walk":
			select_action("idle")
		elif current_action == "prone_crawl":
			select_action("prone_idle")


func _record_evidence() -> void:
	if not ready_for_test:
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var report := {"passed": true, "headless": DisplayServer.get_name() == "headless", "units": [], "viewport": [320, 180], "scale": 1, "screenshots": 0}
	for unit_index in range(units.size()):
		select_unit(unit_index)
		var unit_report := {"unit": units[unit_index].unit, "actions": [], "flip_h": true}
		for action: Dictionary in units[unit_index].actions:
			select_action(action.name)
			var captured: Array[String] = []
			for frame_index in range(int(action.frames)):
				sprite.pause()
				sprite.set_frame_and_progress(frame_index, 0.0)
				await get_tree().process_frame
				if not report.headless:
					await RenderingServer.frame_post_draw
					var path := OUTPUT + "%s_%s_%02d.png" % [units[unit_index].unit, action.name, frame_index]
					var error := get_viewport().get_texture().get_image().save_png(path)
					report.passed = report.passed and error == OK
					captured.append(path)
					report.screenshots += 1
			unit_report.actions.append({"name": action.name, "frames": int(action.frames), "captures": captured})
		set_facing(true)
		await get_tree().process_frame
		if not report.headless:
			await RenderingServer.frame_post_draw
			var left_path := OUTPUT + "%s_left.png" % units[unit_index].unit
			report.passed = report.passed and get_viewport().get_texture().get_image().save_png(left_path) == OK
			report.screenshots += 1
		report.units.append(unit_report)
	var file := FileAccess.open(OUTPUT + "gpu_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("ENEMY_GALLERY_EVIDENCE " + JSON.stringify({"passed": report.passed, "units": report.units.size(), "screenshots": report.screenshots, "headless": report.headless}))
	get_tree().quit(0 if report.passed else 1)
