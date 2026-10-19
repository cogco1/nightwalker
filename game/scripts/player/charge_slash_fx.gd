extends Node2D
## Compact charged-draw afterglow: white cutting edge, blue ribbon and sparse trailing vapour.
## Native pixels, normal unshaded blend. No screen overlay, projectile, hit box or damage changes.

const LIFE := 0.24
const MAX_CUTS := 2
const MAX_PIXELS := 720
const REACH := 56.0
const WHITE := Color("f1fbff")
const ICE := Color("bdeaff")
const BLUE := Color("58baff")
const DEEP := Color("2e69c9")
const MIST := Color("629fe4")

var cuts: Array[Dictionary] = []
var release_count := 0


func _ready() -> void:
	var ink := CanvasItemMaterial.new()
	ink.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = ink


func release(origin: Vector2, direction: Vector2, reach := REACH, side_view := false) -> void:
	if direction.is_zero_approx() or reach < 4.0:
		return
	cuts.append({"origin": origin.round(), "forward": direction.normalized(),
		"across": Vector2.DOWN if side_view else Vector2(-direction.y, direction.x).normalized(),
		"reach": minf(reach, REACH), "age": 0.0})
	while cuts.size() > MAX_CUTS:
		cuts.pop_front()
	release_count += 1
	queue_redraw()


func step(delta: float) -> void:
	for index in range(cuts.size() - 1, -1, -1):
		cuts[index].age = float(cuts[index].age) + delta
		if float(cuts[index].age) >= LIFE:
			cuts.remove_at(index)
	queue_redraw()


func _point(cut: Dictionary, t: float, offset := Vector2.ZERO) -> Vector2:
	var forward: Vector2 = cut.forward
	var across: Vector2 = cut.across
	# A narrow open crescent: about 52 x 48 native pixels including its soft trailing edge.
	var local := Vector2(6.0 + sin(t * PI) * 44.0 + t * 4.0, -25.0 + t * 44.0) + offset
	return Vector2(cut.origin) + forward * local.x + across * local.y


func _put(pixels: Dictionary, point: Vector2i, colour: Color, cut: Dictionary) -> void:
	var distance := (Vector2(point) - Vector2(cut.origin)).dot(Vector2(cut.forward))
	if distance < 0.0 or distance > float(cut.reach) or colour.a < 0.025:
		return
	if not pixels.has(point) and pixels.size() >= MAX_PIXELS:
		return
	if not pixels.has(point) or colour.a >= Color(pixels[point]).a:
		pixels[point] = colour


func _line(pixels: Dictionary, start: Vector2, finish: Vector2, colour: Color, cut: Dictionary) -> void:
	var from := Vector2i(start.round())
	var to := Vector2i(finish.round())
	var distance := to - from
	var count := maxi(absi(distance.x), absi(distance.y))
	for index in range(count + 1):
		var point := Vector2i(Vector2(from).lerp(Vector2(to), float(index) / maxf(1.0, count)).round())
		_put(pixels, point, colour, cut)


## Actual drawn pixels, also used to measure screen coverage in the rendered-effect checks.
func effect_pixels() -> Dictionary:
	var pixels: Dictionary = {}
	for cut in cuts:
		var age := float(cut.age)
		var head := clampf(age / 0.055, 0.0, 1.0)
		var tail := clampf((age - 0.075) / 0.17, 0.0, 1.0)
		var fade := 1.0 - smoothstep(0.065, LIFE, age)
		var core := 1.0 - smoothstep(0.055, 0.115, age)
		# Short broken blue fibres trail the blade. Their spacing leaves the background readable.
		for strand in range(6):
			var t := 0.16 + strand * 0.12
			if t > head or t < tail:
				continue
			var drift := age * 13.0
			var start := _point(cut, t, Vector2(-4.0 - drift, 1.0 + strand % 2))
			var finish := _point(cut, minf(t + 0.065, head), Vector2(-6.0 - drift, 1.0))
			_line(pixels, start, finish, Color(MIST, fade * 0.34), cut)
		# Tapered blue body, a pale inner edge, then a one-pixel white cutting edge.
		for segment in range(52):
			var t := float(segment) / 52.0
			var next := minf(float(segment + 1) / 52.0, head)
			if t > head or next < tail or next <= t:
				continue
			var offset := Vector2(age * 4.0, 0)
			var start := _point(cut, maxf(t, tail), offset)
			var finish := _point(cut, next, offset)
			var normal := (finish - start).orthogonal().normalized()
			var width := 1 + int(round(sin(PI * t) * 1.4))
			for layer in range(-1, width + 1):
				var colour := Color(DEEP if layer == width else BLUE, fade * (0.26 if layer == width else 0.62))
				_line(pixels, start + normal * layer, finish + normal * layer, colour, cut)
			_line(pixels, start - normal, finish - normal, Color(ICE, fade * 0.84), cut)
			if core > 0.02:
				_line(pixels, start - normal * 2.0, finish - normal * 2.0, Color(WHITE, core * 0.96), cut)
	return pixels


func _draw() -> void:
	var pixels := effect_pixels()
	for point in pixels:
		draw_rect(Rect2(Vector2(point) - global_position, Vector2.ONE), pixels[point])
