extends "res://tests/support/isolated_suite.gd"
## Real GPU captures of the furnished safehouse, independently powered lamps,
## readable furniture dialogues and the narrow bedroom circulation route.

const CONTROLS = preload("res://scripts/core/controls.gd")
const HOME := "res://scenes/home_601.tscn"
const OUT := "res://evidence/home_furniture/"
const SIZE := Vector2i(1280, 720)
var home: Node2D
var player: CharacterBody2D
var shots: Array[Dictionary] = []


func _initialize() -> void:
	CONTROLS.current = CONTROLS.defaults()
	CONTROLS.install(false)
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("Furnished safehouse GPU recorder exceeded its deadline")
		quit(2)
	)
	call_deferred("run")


func frames(count := 4) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func place(point: Vector2, facing := "down") -> void:
	player.position = point
	player.velocity = Vector2.ZERO
	player.facing = facing
	player.show_idle()
	await frames(8)


func shot(label: String) -> void:
	if root.mode != Window.MODE_WINDOWED or root.size != SIZE:
		root.mode = Window.MODE_WINDOWED
		root.size = SIZE
		await frames(2)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.get_size() == SIZE)
	var filename := "%02d_%s.png" % [shots.size() + 1, label]
	assert(image.save_png(OUT + filename) == OK)
	var sources: Array[Dictionary] = []
	for source in home.world.find_children("*", "PointLight2D", true, false):
		sources.append({"id": source.get_meta("source_id"), "kind": source.get_meta("kind"),
			"powered": source.enabled, "position": [source.position.x, source.position.y], "colour": source.color})
	var material := (player.get_node("Sprite") as AnimatedSprite2D).material as ShaderMaterial
	shots.append({"file": filename, "scene": home.scene_file_path,
		"player": [player.position.x, player.position.y], "scale": player.scale,
		"background": home.world.get_node("HomeBackground").texture.resource_path,
		"rim_colour": material.get_shader_parameter("rim_a_color"),
		"reflect_strength": material.get_shader_parameter("reflect_strength"), "sources": sources})


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	assert(change_scene_to_file(HOME) == OK)
	await frames(15)
	home = current_scene as Node2D
	player = home.get("player") as CharacterBody2D
	player.freeze(self)
	await place(Vector2(110, 104))
	await shot("safehouse_furnished_cold_and_amber")
	await frames(24)
	await shot("safehouse_live_screens_next_frame")
	await place(Vector2(107, 94), "up")
	await shot("workbench_lamp_hero_rim")
	home.set_device_power("computer", false)
	home.set_device_power("television", false)
	await frames(8)
	await shot("screens_off_warm_lamps_remain")
	home.set_device_power("computer", true)
	home.set_device_power("television", true)
	await place(Vector2(221, 87), "right")
	await shot("bedroom_lamp_and_folding_chair")
	await place(Vector2(221, 70), "down")
	await shot("bedroom_north_narrow_passage")
	await place(Vector2(50, 151), "up")
	await shot("kitchen_lower_passage_stool")
	for item in [{"id": "bookshelf", "point": Vector2(87, 88)},
		{"id": "repair_desk", "point": Vector2(107, 94)},
		{"id": "storage_box", "point": Vector2(227, 128)}]:
		await place(item["point"], "up")
		home.call("_open_interaction", item["id"])
		await frames(45)
		await shot("interaction_" + String(item["id"]))
		home.close_dialogue()
	await place(Vector2(110, 104))
	await shot("overview_after_interactions")
	var file := FileAccess.open(OUT + "capture_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": "passed", "renderer": RenderingServer.get_video_adapter_name(),
		"source": "real playable safehouse rendered by Godot", "shots": shots}, "\t"))
	file.close()
	print(JSON.stringify({"status": "passed", "captures": shots.size(), "output": OUT}))
	quit(0)
