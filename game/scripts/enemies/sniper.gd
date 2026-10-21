extends "res://scripts/enemies/humanoid.gd"
## Anchored sniper: far -> lower/aim/prone shot; middle -> rise/shoulder shot;
## close -> committed rifle-butt strike. All poses and attacks use the world clock.
signal fired(bullet: Node2D)
signal melee_resolved(result: int)
const ROUND = preload("res://scripts/enemies/ballistic_round.gd")
const ORIGINAL = preload("res://assets/enemy_animations_v01/sniper_B/animations.tres")
const STAND_SHEET = preload("res://assets/sniper_combat_v02/stand_fire.png")
const MELEE_SHEET = preload("res://assets/sniper_combat_v02/melee.png")
enum Posture { STAND, LOWER, PRONE, RISE }
enum Mode { FAR, MIDDLE, CLOSE }
enum Phase { READY, AIM, SHOT, MELEE, RECOVER }
const TRANSITION := 8.0/12.0
const NEAR_ENTER := 42.0
const NEAR_EXIT := 58.0
const FAR_ENTER := 180.0
const FAR_EXIT := 146.0
const RANGE := 420.0
const LOCK_SECONDS := 0.24
const MELEE_WINDUP := 0.30
const MELEE_ACTIVE := 0.12
const MELEE_SECONDS := 0.80
const MELEE_PUSH := 26.0
const MELEE_DAMAGE := 10
@export_range(0.0,96.0,1.0) var region_radius := 40.0
var home_position := Vector2.ZERO
var posture := Posture.STAND
var mode := Mode.MIDDLE
var phase := Phase.READY
var posture_time := 0.0
var phase_time := 0.0
var cooldown_left := 0.4
var settle_left := 0.0
var aim_seconds := 0.75
var aim_point := Vector2.ZERO
var shot_direction := Vector2.LEFT
var sight_end := Vector2.ZERO
var shot_count := 0
var melee_count := 0
var sprite: AnimatedSprite2D
var laser: Line2D
var _released := false
var _melee_checked := false
var _flash_seconds := 0.0

func _ready() -> void:
	max_hp=12
	kind="sniper"
	super()
	home_position=global_position
	sprite=AnimatedSprite2D.new()
	sprite.name="SniperSprite"
	sprite.centered=false
	sprite.position=Vector2(-48,-57)
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.sprite_frames=ORIGINAL.duplicate()
	for pair in [["stand_fire",STAND_SHEET],["melee",MELEE_SHEET]]:
		var animation := "right_"+str(pair[0])
		sprite.sprite_frames.add_animation(animation)
		sprite.sprite_frames.set_animation_loop(animation,false)
		sprite.sprite_frames.set_animation_speed(animation,12.0)
		for index in range(8):
			var atlas := AtlasTexture.new()
			atlas.atlas=pair[1]
			atlas.region=Rect2((index%4)*96,(index/4)*64,96,64)
			sprite.sprite_frames.add_frame(animation,atlas)
	add_child(sprite)
	laser=Line2D.new()
	laser.name="AimLaser"
	laser.z_index=8
	# Two native pixels survive vertex snapping on both horizontal and shallow-angle sights.
	laser.width=2.0
	laser.antialiased=false
	var laser_material := CanvasItemMaterial.new()
	laser_material.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED
	laser.material=laser_material
	add_child(laser)
	_sync_pose()

func hero_on_my_floor() -> bool:
	return is_instance_valid(hero) and absf(hero.global_position.y-global_position.y)<90.0

func _physics_process(delta: float) -> void:
	if dead or held or not active or not is_instance_valid(hero):
		if phase==Phase.AIM or (phase==Phase.SHOT and not _released) or phase==Phase.MELEE:
			_cancel(0.4)
	super(delta)
	# Every horizontal motion, including a hit reaction, stays inside this spawn region.
	var bounded := clampf(global_position.x,home_position.x-region_radius,home_position.x+region_radius)
	if not is_equal_approx(bounded,global_position.x):
		global_position.x=bounded
		velocity.x=0.0
	if not held:
		_flash_seconds=maxf(0.0,_flash_seconds-delta*world_scale())
	_sync_pose()
	laser.visible=aiming()
	if laser.visible:
		laser.points=PackedVector2Array([(muzzle()-global_position).round(),(sight_end-global_position).round()])
		laser.default_color=Color(1.0,0.16,0.18,0.95 if locked() else 0.65)

func _change_phase(next: Phase) -> void:
	phase=next
	phase_time=0.0
	_released=false
	_melee_checked=false

func _cancel(wait: float) -> void:
	_change_phase(Phase.READY)
	cooldown_left=maxf(cooldown_left,wait)
	if laser!=null:
		laser.hide()

func on_flinch() -> void:
	_cancel(0.65)

func stand_down() -> void:
	_cancel(0.5)

func _die() -> void:
	_cancel(1.0)
	super()

func _pick_mode(distance: float) -> void:
	if distance<NEAR_ENTER:
		mode=Mode.CLOSE
	elif mode==Mode.CLOSE and distance>NEAR_EXIT:
		mode=Mode.FAR if distance>FAR_ENTER else Mode.MIDDLE
	elif mode==Mode.FAR and distance<FAR_EXIT:
		mode=Mode.MIDDLE
	elif mode==Mode.MIDDLE and distance>FAR_ENTER:
		mode=Mode.FAR

func _start_posture(next: Posture) -> void:
	_cancel(0.16)
	if (posture==Posture.LOWER and next==Posture.RISE) or (posture==Posture.RISE and next==Posture.LOWER):
		posture_time=TRANSITION-posture_time
	else:
		posture_time=0.0
	posture=next
	velocity.x=0.0

func standing_clear() -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size=Vector2(12,31)
	query.shape=shape
	query.transform=Transform2D(0.0,global_position+Vector2(0,-16))
	query.collision_mask=1
	query.exclude=[get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func think(step: float) -> void:
	cooldown_left=maxf(0.0,cooldown_left-step)
	settle_left=maxf(0.0,settle_left-step)
	velocity.x=move_toward(velocity.x,0.0,220.0*step)
	if not hero_on_my_floor():
		_cancel(0.35)
		return
	var offset := hero_offset()
	var distance := absf(offset)
	_pick_mode(distance)
	var committed := phase in [Phase.SHOT,Phase.MELEE]
	var needs_turn := absf(offset)>5.0 and signf(offset)!=facing and not committed
	var want_prone := mode==Mode.FAR and distance<=RANGE and not needs_turn
	# Finish/reverse the actual transition frames; no shooting or swivelling while getting up.
	if posture==Posture.LOWER and not want_prone and standing_clear():
		_start_posture(Posture.RISE)
	elif posture==Posture.RISE and want_prone:
		_start_posture(Posture.LOWER)
	if posture==Posture.LOWER or posture==Posture.RISE:
		posture_time=minf(TRANSITION,posture_time+step)
		if posture_time>=TRANSITION:
			posture=Posture.PRONE if posture==Posture.LOWER else Posture.STAND
			settle_left=0.12
		return
	if posture==Posture.PRONE and (not want_prone or needs_turn) and not committed:
		if standing_clear():
			_start_posture(Posture.RISE)
		return
	if needs_turn:
		_cancel(0.22)
		facing=signf(offset)
		settle_left=0.14
		return
	if posture==Posture.STAND and want_prone and phase not in [Phase.MELEE,Phase.SHOT,Phase.RECOVER]:
		_start_posture(Posture.LOWER)
		return
	# A player entering melee range spoils an uncommitted shot; committed recoil completes.
	if mode==Mode.CLOSE and phase==Phase.AIM:
		_cancel(0.08)
	match phase:
		Phase.AIM:
			phase_time+=step
			if not locked():
				aim_point=hero.hurtbox().get_center()
				shot_direction=(aim_point-muzzle()).normalized()
			_update_sight()
			if not _line_of_sight():
				_cancel(0.30)
			elif phase_time>=aim_seconds:
				_change_phase(Phase.SHOT)
				if posture==Posture.STAND:
					_release()
		Phase.SHOT:
			phase_time+=step
			if not _released:
				_update_sight()
			if posture==Posture.PRONE and not _released and phase_time>=0.25:
				_release()
			var duration := 8.0/12.0 if posture==Posture.PRONE else 4.0/12.0
			if phase_time>=duration:
				_change_phase(Phase.READY if posture==Posture.PRONE else Phase.RECOVER)
				cooldown_left=1.25 if posture==Posture.PRONE else 0.85
		Phase.MELEE:
			phase_time+=step
			if phase_time>=MELEE_WINDUP and phase_time<MELEE_WINDUP+MELEE_ACTIVE:
				# A small braced step, never a homing lunge.
				_short_step(facing,30.0,step)
				_resolve_melee(true)
			if phase_time>=MELEE_WINDUP+MELEE_ACTIVE and not _melee_checked:
				_resolve_melee(false)
			if phase_time>=MELEE_SECONDS:
				_change_phase(Phase.RECOVER)
				cooldown_left=0.95
		Phase.RECOVER:
			phase_time+=step
			if phase_time>=4.0/12.0:
				_change_phase(Phase.READY)
		_:
			if settle_left>0.0 or cooldown_left>0.0 or distance>RANGE:
				return
			if mode==Mode.CLOSE and posture==Posture.STAND:
				_change_phase(Phase.MELEE)
				melee_count+=1
			elif _line_of_sight():
				_change_phase(Phase.AIM)
				aim_seconds=1.15 if posture==Posture.PRONE else 0.72
				aim_point=hero.hurtbox().get_center()
				shot_direction=(aim_point-muzzle()).normalized()
				_update_sight()

func _short_step(direction: float, speed: float, step: float) -> void:
	var next_x := global_position.x+direction*speed*step
	if absf(next_x-home_position.x)>region_radius:
		return
	if blocked(direction,3.0):
		return
	var ahead := global_position+Vector2(direction*14.0,-1)
	var floor_ray := PhysicsRayQueryParameters2D.create(ahead,ahead+Vector2(0,12),1)
	if not get_world_2d().direct_space_state.intersect_ray(floor_ray).is_empty():
		velocity.x=move_toward(velocity.x,direction*speed,260.0*step)

func muzzle() -> Vector2:
	return global_position+Vector2(facing*(30.0 if posture==Posture.PRONE else 29.0),-6.0 if posture==Posture.PRONE else -21.0)

func aiming() -> bool:
	return not dead and not held and active and flinch_left<=0.0 and (phase==Phase.AIM or (phase==Phase.SHOT and not _released))

func locked() -> bool:
	return phase==Phase.SHOT or (phase==Phase.AIM and phase_time>=aim_seconds-LOCK_SECONDS)

func _line_of_sight() -> bool:
	if not is_instance_valid(hero):
		return false
	var from := muzzle()
	var to: Vector2=hero.hurtbox().get_center()
	# Include the body-to-barrel interval: a protruding rifle cannot shoot through a thin wall.
	var chest := global_position+Vector2(0,from.y-global_position.y)
	return get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(chest,to,1)).is_empty()

func _update_sight() -> void:
	var from := muzzle()
	var end := from+shot_direction*RANGE
	var wall := get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from,end,1))
	if not wall.is_empty():
		end=wall.position
	if is_instance_valid(hero):
		var t := ROUND.box_contact(from,end,hero.hurtbox())
		if t<=1.0:
			end=from.lerp(end,t)
	sight_end=end

func _release() -> void:
	if _released or dead or held or not active or not is_instance_valid(hero):
		return
	_released=true
	var chest := global_position+Vector2(0,muzzle().y-global_position.y)
	var wall := get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(chest,muzzle(),1))
	if not wall.is_empty():
		return
	var bullet: Node2D=ROUND.new()
	bullet.setup(self,hero,muzzle(),shot_direction,ROUND.Weapon.SNIPER)
	get_parent().add_child(bullet)
	shot_count+=1
	_flash_seconds=0.075
	fired.emit(bullet)

func melee_box() -> Rect2:
	return Rect2(global_position+Vector2(1.0 if facing>0.0 else -37.0,-29),Vector2(36,29))

func _resolve_melee(contact_window: bool) -> void:
	if _melee_checked or not is_instance_valid(hero):
		return
	var contact := melee_box().intersects(hero.hurtbox())
	var close := global_position.distance_to(hero.global_position)<65.0
	var clear := _line_of_sight()
	if contact_window and (not contact or not clear):
		return
	_melee_checked=true
	if not close or not clear:
		return
	var result := int(hero.receive_attack({"source":self,"direction":Vector2(facing,0),"contact":contact and contact_window,
		"window_age":maxf(0.0,phase_time-MELEE_WINDUP),"knockback":MELEE_PUSH,"damage":MELEE_DAMAGE,"weapon":"rifle_butt"}))
	melee_resolved.emit(result)

func damage_point() -> Vector2:
	return global_position+Vector2(0,-6.0 if posture==Posture.PRONE else -18.0)

func _set_pose(animation: String, index: int) -> void:
	sprite.animation="right_"+animation
	sprite.pause()
	sprite.frame=clampi(index,0,sprite.sprite_frames.get_frame_count(sprite.animation)-1)

func _sync_pose() -> void:
	if sprite==null:
		return
	sprite.flip_h=facing<0.0
	var height := 32.0
	if dead:
		height=10.0
		_set_pose("prone_idle",0)
	elif posture==Posture.LOWER or posture==Posture.RISE:
		var index := mini(7,int(posture_time*12.0))
		var visual_index := index if posture==Posture.LOWER else 7-index
		height=float([32,31,25,18,12,10,10,10][visual_index])
		_set_pose("prone_down" if posture==Posture.LOWER else "prone_up",index)
	elif phase==Phase.MELEE:
		_set_pose("melee",mini(7,int(phase_time*10.0)))
	elif phase==Phase.RECOVER:
		_set_pose("stand_fire",maxi(0,3-int(phase_time*12.0)))
	elif phase==Phase.SHOT:
		_set_pose("prone_fire" if posture==Posture.PRONE else "stand_fire",
			int(phase_time*12.0) if posture==Posture.PRONE else 4+int(phase_time*12.0))
	elif posture==Posture.PRONE:
		height=10.0
		_set_pose("prone_idle",0)
	elif phase==Phase.AIM:
		_set_pose("stand_fire",mini(3,int(phase_time*12.0)))
	elif absf(velocity.x)>3.0 and flinch_left<=0.0:
		_set_pose("walk",int(clock*12.0)%8)
	else:
		_set_pose("idle",0)
	if posture==Posture.PRONE:
		height=10.0
	var shape := body_shape.shape as RectangleShape2D
	shape.size=Vector2(26.0 if height<14.0 else 12.0,height)
	body_shape.position=Vector2(0,-height*0.5)
	sprite.modulate=Color("6a6461") if dead else (Color("ffe4d1") if flash_left>0.0 else Color.WHITE)
	if phase==Phase.MELEE and phase_time<MELEE_WINDUP:
		sprite.modulate=Color(1.0,0.55,0.45) if int(clock*14.0)%2==0 else Color.WHITE

func draw_glow_extra(canvas: Node2D) -> void:
	if aiming():
		var end := (sight_end-global_position).round()
		canvas.draw_rect(Rect2(end-Vector2.ONE,Vector2(2,2)),Color("ff9d73"))
	if _flash_seconds>0.0:
		var at := (muzzle()-global_position).round()
		canvas.draw_rect(Rect2(at-Vector2(2,2),Vector2(5,4)),Color("fff4bc"))
		canvas.draw_line(at,at+Vector2(facing*8,0),Color("ffb24c"),2.0,false)
