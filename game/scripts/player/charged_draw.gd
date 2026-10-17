extends Node2D
## A broad black-crimson blade extension. Normal, unshaded blend; short life and no full-screen flash.
const LIFE := 0.14
const MAX_CUTS := 2
var cuts: Array[Dictionary] = []

func _ready() -> void:
	var ink:=CanvasItemMaterial.new()
	ink.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material=ink

func release(feet:Vector2, direction:Vector2, reach:float) -> void:
	if reach<4.0:return
	cuts.append({"feet":feet,"direction":direction.normalized(),"reach":reach,"life":LIFE})
	while cuts.size()>MAX_CUTS:cuts.pop_front()
	queue_redraw()

func step(delta:float) -> void:
	for i in range(cuts.size()-1,-1,-1):
		cuts[i].life=float(cuts[i].life)-delta
		if float(cuts[i].life)<=0.0:cuts.remove_at(i)
	queue_redraw()

func _point(cut:Dictionary,t:float,shift:=0.0) -> Vector2:
	var forward:Vector2=cut.direction
	var across:=Vector2(-forward.y,forward.x)
	# A long, open crescent follows the low-to-high draw. Its dark body leaves the scene visible around it.
	var x:=5.0+(float(cut.reach)-5.0)*sin(t*PI*0.6)
	var y:=-43.0+t*54.0+shift
	return to_local(Vector2(cut.feet)+forward*x+across*y).round()

func _draw() -> void:
	for cut in cuts:
		var age:=1.0-float(cut.life)/LIFE
		var fade:=1.0-smoothstep(0.35,1.0,age)
		for i in range(28):
			var t0:=float(i)/28.0
			var t1:=float(i+1)/28.0
			var thickness:=1.0+sin((t0+t1)*0.5*PI)*8.0
			draw_line(_point(cut,t0),_point(cut,t1),Color(0.055,0.025,0.06,0.9*fade),thickness,false)
			# Sparse crimson fibres define the cut without additive light or a solid luminous slab.
			if i%5!=3:
				draw_line(_point(cut,t0,-thickness*0.35),_point(cut,t1,-thickness*0.35),Color(0.57,0.11,0.21,0.9*fade),1.0,false)
			if i%4==1:
				draw_line(_point(cut,t0,thickness*0.2),_point(cut,t1,thickness*0.2),Color(0.78,0.24,0.32,0.6*fade),1.0,false)
		for i in range(7):
			var t:=0.18+float(i)*0.1
			var point:=_point(cut,t,7.0+age*(6.0+i))
			var drift:=Vector2(cut.direction)*(-3.0-age*8.0)
			draw_line(point,(point+drift).round(),Color(0.22,0.045,0.12,0.65*fade),1.0,false)
