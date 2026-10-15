extends SceneTree

const ROOT := "res://art_metadata/air_actions_v09/"
var palette: Array[Color] = []

func _initialize() -> void:
	var registration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art_metadata/master_registration.json"))
	for value in registration["palette"]:
		palette.append(Color(String(value)))
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "generation_manifest.json"))
	var paths: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "blade_paths_base.json"))
	var resources := ""
	var animations: Array[String] = []
	var report: Dictionary = {}
	for job in metadata["jobs"]:
		var name: String = job["name"]
		var source := Image.load_from_file(ProjectSettings.globalize_path(ROOT + name + "_source.png"))
		var cell_size := source.get_width() / 4.0
		if source.get_width() != source.get_height():
			push_error("Atlas must have a square 4x4 layout")
			quit(1)
			return
		var source_ratio := source.get_width() / 1280.0
		var scale: float = float(job["uniform_sampling_scale"]) / source_ratio
		var preview := Image.create(320, 320, false, Image.FORMAT_RGBA8)
		var steel_tips: Array = []
		var frames: Array[Image] = []
		for frame in range(16):
			var image := Image.create(80, 80, false, Image.FORMAT_RGBA8)
			var origin := Vector2((frame % 4) * cell_size, floori(frame / 4.0) * cell_size)
			var anchor := Vector2(float(job["target_sample_pivot"][0]), float(job["target_sample_pivot"][1]))
			for y in range(80):
				for x in range(80):
					var point := Vector2(160, 272) * source_ratio + (Vector2(x, y) - anchor) / scale
					if point.x < 0 or point.y < 0 or point.x >= cell_size or point.y >= cell_size:
						continue
					var color := source.get_pixelv(Vector2i((origin + point).round()))
					if color.a < 0.6:
						continue
					var selected := 0
					var distance := INF
					for index in range(palette.size()):
						var candidate := palette[index]
						var delta := Vector3(color.r - candidate.r, color.g - candidate.g, color.b - candidate.b).length_squared()
						if delta < distance:
							distance = delta
							selected = index
					image.set_pixel(x, y, palette[selected])
			frames.append(image)
			preview.blit_rect(image, Rect2i(0, 0, 80, 80), Vector2i((frame % 4) * 80, floori(frame / 4.0) * 80))
			var tip := Vector2i(40, 51)
			var farthest := -1.0
			for y in range(80):
				for x in range(80):
					var color := image.get_pixel(x, y)
					if color.a > 0 and color in [palette[14], palette[15], palette[16]]:
						var distance := Vector2(x - 45, y - 51).length_squared()
						if distance > farthest:
							farthest = distance
							tip = Vector2i(x, y)
			steel_tips.append([tip.x - 40, tip.y - 68])
		for direction in ["right", "left"]:
			var animation: String = name + "_" + direction
			var frame_refs: Array[String] = []
			var directory: String = "res://frames/side_view_" + direction + "_" + name
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
			var mirrored_tips: Array = []
			for frame in range(16):
				var image := frames[frame].duplicate()
				var tip: Array = steel_tips[frame]
				if direction == "left":
					image.flip_x()
					# The canonical virtual pivot stays exactly at x=40, so compensate the 79-x flip.
					var aligned := Image.create(80, 80, false, Image.FORMAT_RGBA8)
					aligned.blit_rect(image, Rect2i(0, 0, 79, 80), Vector2i(1, 0))
					image = aligned
				mirrored_tips.append([-tip[0], tip[1]] if direction == "left" else tip)
				var path: String = directory + "/%02d.png" % frame
				image.save_png(path)
				var id := "v09_%s_%d" % [animation, frame]
				resources += "[ext_resource type=\"Texture2D\" path=\"%s\" id=\"%s\"]\n" % [path, id]
				frame_refs.append("{\"duration\":1.0,\"texture\":ExtResource(\"%s\")}" % id)
			paths["side_view"][animation] = mirrored_tips
			animations.append("{\"frames\":[%s],\"loop\":%s,\"name\":&\"%s\",\"speed\":%s}" % [", ".join(frame_refs), "true" if name == "air_idle" else "false", animation, "10.0" if name == "air_idle" else "40.0"])
		preview.resize(1280, 1280, Image.INTERPOLATE_NEAREST)
		preview.save_png(ProjectSettings.globalize_path(ROOT + name + "_native_preview.png"))
		report[name] = {"frames_per_direction": 16, "native_canvas": [80, 80], "source_size": [source.get_width(), source.get_height()], "uniform_scale": scale, "palette_colors": palette.size(), "opaque_alpha_only": true}
	var file := FileAccess.open("res://assets/blade_paths.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(paths, "\t"))
	var text := FileAccess.get_file_as_string(ROOT + "side_view_base.tres")
	assert(not text.contains("v09_"), "Do not append resources twice")
	text = text.replace("load_steps=385", "load_steps=545")
	text = text.replace("[resource]", resources + "\n[resource]")
	var end := text.rfind("]")
	text = text.substr(0, end) + ",\n" + ",\n".join(animations) + "\n]\n"
	file = FileAccess.open("res://assets/side_view.tres", FileAccess.WRITE)
	file.store_string(text)
	file = FileAccess.open(ROOT + "import_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit()

