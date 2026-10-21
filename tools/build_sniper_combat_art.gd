extends SceneTree
## Deterministic Godot import of imagegen sheets: split equal cells, register feet,
## nearest-neighbour native sizing and quantize to the existing enemy palette.
const SOURCE := "res://art_metadata/sniper_combat_20261021/"
const DEST := "res://assets/sniper_combat_v02/"

func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/enemy_animations_v01/manifest.json"))
	var palette: Array[Color] = []
	for rgb: Array in manifest.palette:
		palette.append(Color8(rgb[0], rgb[1], rgb[2]))
	DirAccess.make_dir_recursive_absolute(DEST)
	var report: Dictionary = {"generator": "built-in imagegen", "native_cell": [96,64], "anchor": [48,57], "actions": {}}
	for action in ["stand_fire", "melee"]:
		var raw := Image.load_from_file(SOURCE + action + "_source.png")
		if raw == null:
			quit(1)
			return
		# Ignore faint generator edge alpha when measuring actual visible character height.
		for y in range(raw.get_height()):
			for x in range(raw.get_width()):
				if raw.get_pixel(x,y).a<0.5:
					raw.set_pixel(x,y,Color.TRANSPARENT)
		var cell := Vector2i(raw.get_width()/4, raw.get_height()/2)
		var first := raw.get_region(Rect2i(Vector2i.ZERO, cell))
		var box := first.get_used_rect()
		var factor := 32.0 / float(box.size.y)
		var sheet := Image.create(384,128,false,Image.FORMAT_RGBA8)
		var sizes: Array = []
		for index in range(8):
			var frame := raw.get_region(Rect2i(Vector2i(index%4,index/4)*cell,cell))
			var used := frame.get_used_rect()
			# Find the two feet at the bottom of the sprite, independent of its rifle.
			var foot_left := cell.x
			var foot_right := 0
			for y in range(maxi(0, used.end.y-6),used.end.y):
				for x in range(cell.x):
					if frame.get_pixel(x,y).a >= 0.5:
						foot_left=mini(foot_left,x)
						foot_right=maxi(foot_right,x)
			var pivot := Vector2(float(foot_left+foot_right)*0.5,float(used.end.y))
			var small := Vector2i(roundi(cell.x*factor),roundi(cell.y*factor))
			frame.resize(small.x,small.y,Image.INTERPOLATE_NEAREST)
			var native := Image.create(96,64,false,Image.FORMAT_RGBA8)
			var offset := Vector2i(48,57)-Vector2i(roundi(pivot.x*factor),roundi(pivot.y*factor))
			for y in range(frame.get_height()):
				for x in range(frame.get_width()):
					var at := Vector2i(x,y)+offset
					if at.x<0 or at.x>=96 or at.y<0 or at.y>=64:
						continue
					var col := frame.get_pixel(x,y)
					if col.a<0.5:
						continue
					var best := palette[0]
					var distance := INF
					for candidate in palette:
						var error := Vector3(col.r-candidate.r,col.g-candidate.g,col.b-candidate.b).length_squared()
						if error<distance:
							distance=error
							best=candidate
					native.set_pixelv(at,best)
			sheet.blit_rect(native,Rect2i(0,0,96,64),Vector2i(index%4,index/4)*Vector2i(96,64))
			sizes.append([native.get_used_rect().size.x,native.get_used_rect().size.y])
		sheet.save_png(DEST+action+".png")
		report.actions[action]={"source_size":[raw.get_width(),raw.get_height()],"scale":factor,"visible_sizes":sizes}
	var file := FileAccess.open(SOURCE+"import_record.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit()
