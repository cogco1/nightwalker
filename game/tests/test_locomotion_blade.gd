extends "res://tests/support/isolated_suite.gd"
## Inspect the textures actually loaded by AnimatedSprite2D, not just the importer's coordinates.
## A complete walk/run loop must never turn its blade to the other side of the player.

const SIDE = preload("res://assets/side_view.tres")
const STEEL := [Color("8e999f"), Color("bbc2c3"), Color("e5e8e0")]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)


func run() -> void:
	var paths: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/blade_paths.json"))
	for action in ["walk", "run"]:
		for facing in ["left", "right"]:
			var clip := StringName(action + "_" + facing)
			check(SIDE.has_animation(clip) and SIDE.get_frame_count(clip) == 16 and SIDE.get_animation_loop(clip), String(clip) + " keeps the complete looping leg cycle")
			var expected_sign := (1 if facing == "right" else -1) * (1 if action == "walk" else -1)
			for index in range(SIDE.get_frame_count(clip)):
				var image := SIDE.get_frame_texture(clip, index).get_image()
				var tip: Array = paths["side_view"][clip][index]
				var point := Vector2i(int(tip[0]) + 56, int(tip[1]) + 84)
				var label := "%s/%02d" % [clip, index]
				check(image.get_size() == Vector2i(112, 96), label + " preserves the native canvas and foot anchor")
				check(int(tip[0]) * expected_sign > 0, label + " keeps its blade on the intended carry side")
				check(image.get_pixelv(point) in STEEL and point.y < 84, label + " coordinate lies on real steel above the soles")
				var mirrored := SIDE.get_frame_texture(StringName(action + "_" + ("right" if facing == "left" else "left")), index).get_image()
				var mirror_matches := true
				for y in range(96):
					for x in range(1, 112):
						var a := image.get_pixel(x, y)
						var b := mirrored.get_pixel(112 - x, y)
						# The importer's alpha-border repair can fill invisible RGB differently on each side.
						if a.a != b.a or (a.a > 0.0 and a != b):
							mirror_matches = false
				check(mirror_matches, label + " mirrors about the same foot anchor")
	var result := {"checks": checks, "failed": failures.size(), "failures": failures, "status": "passed" if failures.is_empty() else "failed"}
	DirAccess.make_dir_recursive_absolute("res://evidence")
	var file := FileAccess.open("res://evidence/locomotion_blade_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
