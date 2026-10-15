extends "res://tests/record_motion_v05.gd"

func record() -> void:
	_output_folder = "top_directions_v05"
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute("res://evidence/" + _output_folder)
	arena = MAIN.instantiate()
	root.add_child(arena)
	await combo(0,"up")
	await combo(0,"down")
	release()
	sections.append({"name":section_name,"first":section_start,"last":captured - 1})
	var file := FileAccess.open("res://evidence/%s/capture_manifest.json" % _output_folder,FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info()["string"],"source":"actual Godot viewport rendering","native_viewport":[320,180],"captured_frames":captured,"sections":sections,"states":states},"\t"))
	file.close()
	print("PASS: captured %d actual up/down combo frames" % captured)
	quit(0)
