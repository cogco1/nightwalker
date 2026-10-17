extends Node2D
## Short, broad ink cuts with very small white cores. Uses normal, unshaded blend: no additive screen wash.
const PROFILES := {
	&"tick": {"reach": 24.0, "width": 1.8, "life": 0.045, "chips": 5},
	&"light": {"reach": 38.0, "width": 2.6, "life": 0.065, "chips": 9},
	&"critical": {"reach": 67.0, "width": 3.5, "life": 0.075, "chips": 15},
	&"heavy": {"reach": 88.0, "width": 4.4, "life": 0.085, "chips": 22},
	&"kill": {"reach": 108.0, "width": 4.8, "life": 0.09, "chips": 28},
}
const MAX_CONTACTS := 8
const MAX_CHIPS := 96
var contacts: Array[Dictionary] = []
var chips: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var serial := 0


func _ready() -> void:
	rng.randomize()
	var ink := CanvasItemMaterial.new()
	ink.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = ink


func contact(point: Vector2, weight: StringName, direction: Vector2, killed: bool, substance: StringName, crimson := false) -> void:
	var key: StringName = &"kill" if killed else weight
	var profile: Dictionary = PROFILES.get(key, PROFILES[&"light"])
	serial += 1
	var forward := direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	var cross := forward.rotated(-0.48 if serial % 2 else 0.5)
	contacts.append({"point": point.round(), "axis": cross, "reach": profile.reach, "width": profile.width,
		"life": profile.life, "max_life": profile.life, "kill": killed, "weight": key, "crimson": crimson})
	if contacts.size() > MAX_CONTACTS:
		contacts.pop_front()
	var metal := substance == &"metal"
	for i in range(int(profile.chips)):
		var angle := forward.angle() + rng.randf_range(-1.5, 0.7)
		var speed := rng.randf_range(48.0, 135.0) * (1.3 if killed else 1.0)
		var velocity := Vector2.from_angle(angle) * speed + Vector2(0, -rng.randf_range(12, 42))
		var colour: Color
		if metal:
			colour = [Color("dba475"), Color("6f8195"), Color("9f5d58"), Color("49334c")][i % 4]
		else:
			colour = [Color("a83b52"), Color("72283e"), Color("c25660"), Color("472638")][i % 4]
		chips.append({"point": point, "velocity": velocity, "life": rng.randf_range(0.13, 0.25),
			"max_life": 0.25, "metal": metal, "colour": colour, "size": 2 if i % 4 == 0 else 1})
	while chips.size() > MAX_CHIPS:
		chips.pop_front()
	queue_redraw()


func step(delta: float) -> void:
	for i in range(contacts.size()-1, -1, -1):
		contacts[i].life = float(contacts[i].life)-delta
		if float(contacts[i].life) <= 0.0:
			contacts.remove_at(i)
	for i in range(chips.size()-1, -1, -1):
		var chip := chips[i]
		chip.life = float(chip.life)-delta
		if float(chip.life) <= 0.0:
			chips.remove_at(i)
			continue
		var velocity: Vector2 = chip.velocity
		velocity.y += 290.0*delta
		chip.velocity = velocity
		chip.point = Vector2(chip.point)+velocity*delta
	queue_redraw()


func _ribbon(center: Vector2, axis: Vector2, reach: float, width: float, colour: Color) -> void:
	var normal := axis.orthogonal()
	# Integer-width segments remain valid even when the tapered end collapses to one native pixel.
	for i in range(16):
		var t := float(i)/16.0
		var next := float(i+1)/16.0
		var at := center+axis*lerpf(-reach*0.72, reach, t)+normal*sin(t*PI)*reach*0.17
		var to := center+axis*lerpf(-reach*0.72, reach, next)+normal*sin(next*PI)*reach*0.17
		var taper := maxf(1.0,roundf(pow(sin(PI*(t+next)*0.5),1.3)*width*1.28))
		draw_line(at.round()-global_position,to.round()-global_position,colour,taper,false)


func _draw() -> void:
	for chip in chips:
		var fade := minf(1.0, float(chip.life)*12.0)
		var at: Vector2 = Vector2(chip.point).round()-global_position
		var colour: Color = chip.colour
		if chip.metal:
			var tail := -Vector2(chip.velocity).normalized()*3.0
			draw_line(at, (at+tail).round(), Color(colour, fade), 1.0, false)
		else:
			draw_rect(Rect2(at, Vector2(int(chip.size)+1, int(chip.size))), Color(colour, fade))
	for cut in contacts:
		var fade := clampf(float(cut.life)/float(cut.max_life), 0.0, 1.0)
		var point: Vector2 = cut.point
		var axis: Vector2 = cut.axis
		var reach := float(cut.reach)*(0.86+0.14*fade)
		var width := float(cut.width)
		_ribbon(point+Vector2(0,1), axis, reach, width+1.4, Color(0.035,0.045,0.085,fade*0.8))
		_ribbon(point, axis, reach, width, (Color(0.42,0.06,0.13,fade*0.85) if cut.crimson else Color(0.17,0.55,0.68,fade*0.75)))
		_ribbon(point, axis, reach*0.90, width*0.38, (Color(0.75,0.24,0.31,fade*0.85) if cut.crimson else Color(0.64,0.82,0.87,fade*0.9)))
		# Only the contact's tiny central edge is white; the broad silhouette stays coloured and translucent.
		draw_line((point-axis*5.0).round()-global_position, (point+axis*8.0).round()-global_position, Color(0.93,0.98,1.0,fade), 1.0, false)
		if cut.kill or cut.weight == &"heavy":
			_ribbon(point+axis.orthogonal()*5.0, axis.rotated(-0.14), reach*0.78, 1.0, Color(0.75,0.53,0.45,fade*0.65))
		if cut.kill:
			# A broken execution halo, never a filled disk or full-screen flash.
			for sector in range(6):
				var from := sector*TAU/6.0+0.15
				for j in range(4):
					var a := from+j*0.07
					var b := a+0.07
					var radius := 30.0+(1.0-fade)*14.0
					draw_line((point+Vector2.from_angle(a)*radius).round()-global_position,
						(point+Vector2.from_angle(b)*radius).round()-global_position, Color(0.82,0.62,0.48,fade*0.8),1.0,false)
