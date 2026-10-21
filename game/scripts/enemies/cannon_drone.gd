extends CharacterBody2D
## Existing drone-B art with damped local hover and committed three-round cannon bursts.
## The body, hit shape and muzzle move together; world slow motion affects motion and combat equally.
signal fired(bullet: Node2D)
signal defeated(enemy: Node2D)
signal detonated(result: int)
const ROUND = preload("res://scripts/enemies/ballistic_round.gd")
const FRAMES = preload("res://assets/enemy_animations_v01/laser_drone_B/animations.tres")
const TERRITORY = preload("res://scripts/enemies/enemy_territory.gd")
enum Phase { PATROL, AIM, BURST, RECOVER, FUSE, EXPLODED, RUSH_WARNING, RUSH }
const AIM_SECONDS := 0.85
const LOCK_SECONDS := 0.20
const BURST_SIZE := 3
const SHOT_INTERVAL := 0.22
const RECOVER_SECONDS := 0.45
const COOLDOWN := 1.55
const RANGE := 390.0
const OMEGA := 4.2
const FUSE_SECONDS := 1.20
const CRITICAL_HEALTH_RATIO := 0.25
const EXPLOSION_SECONDS := 0.78
const BLAST_RADIUS := 64.0
const BLAST_DAMAGE := 35
const BLAST_PUSH := 34.0
const FOLLOW_GAP := 105.0
const RETREAT_DISTANCE := 230.0
const RETREAT_SECONDS := 0.65
const RUSH_WARNING_SECONDS := 0.50
const RUSH_SECONDS := 1.60
const RUSH_MAX_SPEED := 220.0
const RUSH_ACCELERATION := 300.0
@export var max_hp := 12
@export_range(16.0,120.0,1.0) var region_radius := 64.0
@export_range(96.0,600.0,1.0) var territory_radius := 280.0
var hp := 12
var dead := false
var active := true
var held := false
var kind := "cannon_drone"
var hero: CharacterBody2D
var home_position := Vector2.ZERO
var facing := -1.0
var phase := Phase.PATROL
var phase_time := 0.0
var clock := 0.0
var cooldown_left := 0.55
var shot_count := 0
var burst_count := 0
var burst_shots := 0
var shot_direction := Vector2.LEFT
var locked_direction := Vector2.LEFT
var sprite: AnimatedSprite2D
var body_shape: CollisionShape2D
var fx: Node2D
var stun_left := 0.0
var self_destructing := false
var exploded := false
var explosion_left := 0.0
var _hold_position := Vector2.ZERO
var _hover_velocity := Vector2.ZERO
var _impulse := Vector2.ZERO
var _flash_left := 0.0
var _muzzle_flash := 0.0
var _death_sparks := 0.0
var territory: RefCounted
var pursuing := false
var returning_home := false
var _chase_station := Vector2.ZERO
var _seen_close := false
var _retreat_time := 0.0
var rush_speed := 0.0
var rush_direction := Vector2.LEFT

func rushing() -> bool:
	return phase in [Phase.RUSH_WARNING,Phase.RUSH]

func _ready() -> void:
	collision_layer=2
	collision_mask=1
	motion_mode=CharacterBody2D.MOTION_MODE_FLOATING
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	set_meta("hit_material",&"metal")
	z_index=2
	hp=max_hp
	home_position=global_position
	territory=TERRITORY.new(home_position,territory_radius,14.0)
	_chase_station=home_position
	_hold_position=home_position
	var shape := RectangleShape2D.new()
	shape.size=Vector2(24,12)
	body_shape=CollisionShape2D.new()
	body_shape.shape=shape
	add_child(body_shape)
	sprite=AnimatedSprite2D.new()
	sprite.name="DroneSprite"
	sprite.sprite_frames=FRAMES
	sprite.centered=false
	sprite.position=Vector2(-48,-39)
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	fx=Node2D.new()
	fx.name="CannonEffects"
	fx.z_index=8
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED
	fx.material=unshaded
	add_child(fx)
	fx.draw.connect(_draw_fx)
	_update_visual()

func bind_hero(next: CharacterBody2D) -> void:
	hero=next
	add_collision_exception_with(next)

func world_scale() -> float:
	var session := get_tree().get_first_node_in_group(&"game_session")
	return float(session.world_time_scale) if session!=null else 1.0

func _physics_process(delta: float) -> void:
	var scale := world_scale()
	var step := delta*scale
	if held or step<=0.0:
		return
	clock+=step
	_flash_left=maxf(0.0,_flash_left-step)
	_muzzle_flash=maxf(0.0,_muzzle_flash-step)
	_death_sparks=maxf(0.0,_death_sparks-step)
	_check_critical_health()
	if active and not dead and not self_destructing and not rushing():
		_update_pursuit(step)
	if exploded:
		explosion_left=maxf(0.0,explosion_left-step)
	elif dead:
		_step_wreck(step,scale)
	elif self_destructing:
		phase_time+=step
		_step_hover(step,scale)
		if phase_time>=FUSE_SECONDS:
			_explode()
	elif rushing():
		_step_rush(step,scale)
	else:
		stun_left=maxf(0.0,stun_left-step)
		cooldown_left=maxf(0.0,cooldown_left-step)
		if active and stun_left<=0.0 and is_instance_valid(hero):
			_think(step)
		elif phase!=Phase.PATROL:
			_cancel(0.5)
		_step_hover(step,scale)
	_update_visual()
	fx.queue_redraw()

func _set_phase(next: Phase) -> void:
	phase=next
	phase_time=0.0

func _cancel(wait: float) -> void:
	if self_destructing or exploded or rushing():
		return
	_set_phase(Phase.PATROL)
	cooldown_left=maxf(cooldown_left,wait)
	burst_shots=0

func stand_down() -> void:
	_cancel(0.65)

func muzzle() -> Vector2:
	return global_position+Vector2(facing*15.0,1.0)

func aiming() -> bool:
	return active and not dead and not held and stun_left<=0.0 and phase==Phase.AIM

func locked() -> bool:
	return phase==Phase.BURST or (phase==Phase.AIM and phase_time>=AIM_SECONDS-LOCK_SECONDS)

func target_visible() -> bool:
	if not is_instance_valid(hero) or not territory.target_inside or global_position.distance_to(hero.hurtbox().get_center())>RANGE:
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position,hero.hurtbox().get_center(),1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _think(step: float) -> void:
	if not target_visible():
		if phase in [Phase.AIM,Phase.BURST]:
			_cancel(0.45)
		if phase==Phase.RECOVER:
			phase_time+=step
			if phase_time>=RECOVER_SECONDS:
				_set_phase(Phase.PATROL)
		return
	var offset: float=hero.global_position.x-global_position.x
	if phase!=Phase.BURST and absf(offset)>18.0 and signf(offset)!=facing:
		# No instant homing reversal during a committed burst.
		facing=signf(offset)
		_cancel(0.3)
		return
	match phase:
		Phase.AIM:
			phase_time+=step
			if not locked():
				var desired: Vector2=(hero.hurtbox().get_center()-muzzle()).normalized()
				var angle := rotate_toward(shot_direction.angle(),desired.angle(),3.0*step)
				shot_direction=Vector2.from_angle(angle)
			if phase_time>=AIM_SECONDS:
				locked_direction=shot_direction
				burst_shots=0
				burst_count+=1
				_set_phase(Phase.BURST)
				_fire()
		Phase.BURST:
			phase_time+=step
			if burst_shots<BURST_SIZE and phase_time>=float(burst_shots)*SHOT_INTERVAL:
				_fire()
			if burst_shots>=BURST_SIZE and phase_time>=float(BURST_SIZE-1)*SHOT_INTERVAL+0.12:
				_set_phase(Phase.RECOVER)
				cooldown_left=COOLDOWN
		Phase.RECOVER:
			phase_time+=step
			if phase_time>=RECOVER_SECONDS:
				_set_phase(Phase.PATROL)
		_:
			if cooldown_left<=0.0:
				_hold_position=global_position
				shot_direction=(hero.hurtbox().get_center()-muzzle()).normalized()
				_set_phase(Phase.AIM)

func hover_goal() -> Vector2:
	if self_destructing or phase==Phase.RUSH_WARNING:
		return _hold_position+Vector2(0,sin(clock*3.0)*0.6)
	if phase in [Phase.AIM,Phase.BURST]:
		# Hold the acquired station and gently breathe rather than sliding sideways while shooting.
		return _hold_position+Vector2(sin(clock*1.1)*1.0,sin(clock*1.8)*1.8)
	if active and (pursuing or returning_home):
		return territory.bounded_goal(_chase_station+Vector2(sin(clock*0.9)*3.0,sin(clock*1.8)*2.0))
	var goal := home_position+Vector2(sin(clock*0.66)*28.0,sin(clock*1.8)*3.0+sin(clock*0.83)*1.1)
	if is_instance_valid(hero) and absf(hero.position.x-global_position.x)<85.0:
		goal.x=home_position.x+signf(global_position.x-hero.position.x)*34.0
	goal.x=clampf(goal.x,home_position.x-region_radius+8.0,home_position.x+region_radius-8.0)
	return goal

func _step_hover(step: float, scale: float) -> void:
	var goal := hover_goal()
	# Analytic critically damped spring: no rate-dependent Euler oscillation or teleported bob offsets.
	var displacement := global_position-goal
	var decay := exp(-OMEGA*step)
	var intermediate := (_hover_velocity+OMEGA*displacement)*step
	var next := goal+(displacement+intermediate)*decay
	var next_velocity := (_hover_velocity-OMEGA*intermediate)*decay
	var motion: Vector2 = territory.bounded_motion(global_position,next-global_position+_impulse*step)
	velocity=motion/step
	_impulse*=exp(-6.0*step)
	velocity*=scale
	move_and_slide()
	global_position=territory.bounded_goal(global_position)
	velocity/=scale
	_hover_velocity=next_velocity
	for index in range(get_slide_collision_count()):
		var normal := get_slide_collision(index).get_normal()
		_hover_velocity=_hover_velocity.slide(normal)
		_impulse=_impulse.slide(normal)

func _update_pursuit(step: float) -> void:
	if not is_instance_valid(hero):
		pursuing=false
		returning_home=true
		_chase_station=_chase_station.move_toward(territory.return_goal(),48.0*step)
		return
	var inside: bool=territory.update_target(hero.global_position)
	var distance := global_position.distance_to(hero.hurtbox().get_center())
	if inside and distance<170.0:
		_seen_close=true
	if _seen_close and (distance>RETREAT_DISTANCE or not inside):
		_retreat_time+=step
	else:
		_retreat_time=0.0
	if _retreat_time>=RETREAT_SECONDS:
		_hold_position=global_position
		_muzzle_flash=0.0
		_set_phase(Phase.RUSH_WARNING)
		return
	pursuing=inside
	returning_home=not inside
	if inside and phase in [Phase.AIM,Phase.BURST]:
		_chase_station=global_position
		return
	var goal: Vector2=territory.return_goal()
	if inside:
		var side := signf(global_position.x-hero.global_position.x)
		if side==0.0:
			side=-facing
		goal=Vector2(hero.global_position.x+side*FOLLOW_GAP,clampf(hero.global_position.y-32.0,home_position.y-30.0,home_position.y+12.0))
		if distance<150.0:
			goal=_chase_station
	goal=territory.bounded_goal(goal)
	_chase_station=_chase_station.move_toward(goal,48.0*step)

func _step_rush(step: float, scale: float) -> void:
	phase_time+=step
	if phase==Phase.RUSH_WARNING:
		_step_hover(step,scale)
		if phase_time>=RUSH_WARNING_SECONDS:
			rush_direction=(hero.hurtbox().get_center()-global_position).normalized() if is_instance_valid(hero) else Vector2(facing,0)
			facing=signf(rush_direction.x) if absf(rush_direction.x)>0.01 else facing
			rush_speed=36.0
			_set_phase(Phase.RUSH)
		return
	rush_speed=minf(RUSH_MAX_SPEED,rush_speed+RUSH_ACCELERATION*step)
	var requested := rush_direction*rush_speed*step
	var motion: Vector2=territory.bounded_motion(global_position,requested)
	var boundary: bool=not territory.inside_body(global_position+requested)
	var contact := false
	if is_instance_valid(hero):
		var fraction: float=ROUND.box_contact(global_position,global_position+motion,hero.hurtbox().grow(8.0))
		if fraction<=1.0:
			motion*=fraction
			contact=true
	velocity=motion/step*scale
	move_and_slide()
	velocity/=scale
	global_position=territory.bounded_goal(global_position)
	if contact or boundary or get_slide_collision_count()>0 or phase_time>=RUSH_SECONDS:
		_explode()

func _step_wreck(step: float, scale: float) -> void:
	velocity.y+=300.0*step
	velocity.x=move_toward(velocity.x,0.0,140.0*step)
	velocity*=scale
	move_and_slide()
	velocity/=scale

func _fire() -> void:
	if dead or held or self_destructing or rushing() or not active or not is_instance_valid(hero):
		return
	var obstruction := PhysicsRayQueryParameters2D.create(global_position,muzzle(),1)
	if not get_world_2d().direct_space_state.intersect_ray(obstruction).is_empty():
		_cancel(0.5)
		return
	var round: Node2D=ROUND.new()
	round.setup(self,hero,muzzle(),locked_direction,ROUND.Weapon.DRONE_CANNON)
	get_parent().add_child(round)
	burst_shots+=1
	shot_count+=1
	_muzzle_flash=0.075
	# Small physical recoil is absorbed by the same hover controller, never by a sprite teleport.
	_impulse-=locked_direction*7.0
	fired.emit(round)

func damage_point() -> Vector2:
	return global_position

func take_damage(amount: int) -> bool:
	if dead or amount<=0:
		return false
	hp=maxi(0,hp-amount)
	_flash_left=0.1
	if hp==0:
		self_destructing=false
		_set_phase(Phase.PATROL)
		dead=true
		active=false
		collision_layer=0
		velocity=_hover_velocity+_impulse
		_death_sparks=0.35
		defeated.emit(self)
	else:
		_check_critical_health()
		if not self_destructing:
			_cancel(0.65)
	if sprite!=null:
		_update_visual()
		fx.queue_redraw()
	return true

func _check_critical_health() -> void:
	# Damage, a scripted health change or a loaded low-health encounter all use the same threshold.
	if dead or self_destructing or hp<=0 or hp>maxi(1,ceili(float(max_hp)*CRITICAL_HEALTH_RATIO)):
		return
	self_destructing=true
	_hold_position=global_position
	_muzzle_flash=0.0
	_set_phase(Phase.FUSE)

func _explode() -> void:
	if dead or exploded:
		return
	exploded=true
	self_destructing=false
	dead=true
	active=false
	hp=0
	collision_layer=0
	collision_mask=0
	velocity=Vector2.ZERO
	explosion_left=EXPLOSION_SECONDS
	_set_phase(Phase.EXPLODED)
	var result := -1
	if is_instance_valid(hero):
		var box: Rect2=hero.hurtbox()
		var nearest := Vector2(clampf(global_position.x,box.position.x,box.end.x),clampf(global_position.y,box.position.y,box.end.y))
		var query := PhysicsRayQueryParameters2D.create(global_position,nearest,1)
		var clear := get_world_2d().direct_space_state.intersect_ray(query).is_empty()
		if global_position.distance_to(nearest)<=BLAST_RADIUS and clear:
			var direction: Vector2=(box.get_center()-global_position).normalized()
			if absf(direction.x)<0.01:
				direction.x=facing
			# The destroyed body cannot be a counter target; regular dodge/perfect-dodge protection still applies.
			result=int(hero.receive_attack({"source":null,"direction":direction,"contact":true,
				"window_age":0.0,"knockback":BLAST_PUSH,"damage":BLAST_DAMAGE,"weapon":"drone_explosion"}))
	defeated.emit(self)
	detonated.emit(result)

func receive_hit_reaction(direction: Vector2, strong := false, air_combo := false) -> void:
	if dead:
		return
	_cancel(0.75)
	stun_left=0.65 if strong else 0.30
	_impulse=Vector2(signf(direction.x)*55.0,-90.0 if strong else -18.0)
	if air_combo:
		_impulse.y=-32.0

func receive_charged_launch(direction: Vector2) -> void:
	receive_hit_reaction(direction,true,false)
	_impulse=Vector2(signf(direction.x)*105.0,-170.0)

func knock_up(direction: Vector2) -> void:
	receive_hit_reaction(direction,true,false)

func knock_back(direction: Vector2, distance: float) -> void:
	if not dead:
		_impulse.x=signf(direction.x)*minf(120.0,sqrt(280.0*2.0*distance))

func chase_velocity() -> Vector2:
	return velocity

func _update_visual() -> void:
	sprite.animation="right_hover"
	sprite.pause()
	sprite.frame=0 if dead else int(clock*10.0)%8
	sprite.flip_h=facing<0.0
	sprite.visible=not exploded
	sprite.modulate=Color("686266") if dead else (Color("ffe5c4") if _flash_left>0.0 else Color.WHITE)
	if self_destructing:
		var interval := lerpf(0.18,0.055,clampf(phase_time/FUSE_SECONDS,0.0,1.0))
		if int(clock/interval)%2==0:
			sprite.modulate=Color(1.5,0.24,0.15)
	elif rushing() and int(clock*14.0)%2==0:
		sprite.modulate=Color(1.5,0.35,0.12)

func _draw_fx() -> void:
	fx.draw_set_transform(global_position.round()-global_position)
	if explosion_left>0.0:
		_draw_explosion(EXPLOSION_SECONDS-explosion_left)
	if self_destructing:
		fx.draw_circle(Vector2.ZERO,BLAST_RADIUS,Color(1.0,0.07,0.025,0.065))
		fx.draw_arc(Vector2.ZERO,BLAST_RADIUS,0,TAU,48,Color(1.0,0.16,0.07,0.60),2.0,false)
		if int(clock*12.0)%2==0:
			fx.draw_rect(Rect2(-16,-11,32,2),Color("ff5b36"))
		# Escaping sparks and an overheating vent foreshadow the mechanical blast.
		for index in range(3):
			var age := fmod(phase_time*2.8+float(index)*0.33,1.0)
			var at := Vector2(float(index-1)*7.0,-8.0-age*16.0).round()
			fx.draw_rect(Rect2(at,Vector2(2,2)),Color(1.0,0.53,0.12,1.0-age))
	if rushing():
		fx.draw_arc(Vector2.ZERO,BLAST_RADIUS,0,TAU,40,Color(1.0,0.18,0.03,0.65),2.0,false)
		if phase==Phase.RUSH_WARNING:
			fx.draw_rect(Rect2(-15,-12,30,3),Color("ff6535"))
		else:
			fx.draw_line((-rush_direction*10.0).round(),(-rush_direction*(18.0+rush_speed*0.06)).round(),Color("ffcd63"),3.0,false)
			fx.draw_rect(Rect2(-2,-2,4,4),Color("fff6cb"))
	if not dead:
		# Native-pixel exhaust and a pulsing amber acquisition light.
		var length := 3.0+roundf(sin(clock*9.0))
		fx.draw_rect(Rect2(-2,7,4,length),Color(0.32,0.82,1.0,0.8))
		fx.draw_rect(Rect2(-1,7,2,2),Color("e7faff"))
		if aiming():
			var alpha := 0.95 if locked() else 0.4+0.25*sin(clock*14.0)
			fx.draw_rect(Rect2(facing*6.0-1.0,-4,3,2),Color(1.0,0.5,0.15,alpha))
	if _muzzle_flash>0.0:
		var at := Vector2(facing*15.0,1.0)
		fx.draw_rect(Rect2(at-Vector2(2,2),Vector2(5,5)),Color("fff7cf"))
		fx.draw_line(at,at+locked_direction*8.0,Color("ffb655"),2.0,false)
	if _death_sparks>0.0:
		for index in range(6):
			var angle := float(index)*TAU/6.0
			var end := Vector2.from_angle(angle)*(0.35-_death_sparks)*45.0
			fx.draw_rect(Rect2(end.round(),Vector2(2,2)),Color("ffbd63"))

func _pixel_puff(at: Vector2, radius: float, color: Color) -> void:
	var r := maxf(1.0,roundf(radius))
	var center := at.round()
	# Stepped silhouettes preserve native pixels instead of a smooth circular fireball.
	fx.draw_rect(Rect2(center-Vector2(r,r*0.55).round(),Vector2(r*2.0,roundf(r*1.1))),color)
	fx.draw_rect(Rect2(center-Vector2(r*0.55,r).round(),Vector2(roundf(r*1.1),r*2.0)),color)

func _draw_explosion(age: float) -> void:
	# Smoke blooms behind separate fire lobes; the flash, flame, fragments and smoke have distinct lives.
	var smoke_alpha := smoothstep(0.03,0.16,age)*(1.0-smoothstep(0.38,EXPLOSION_SECONDS,age))*0.8
	for index in range(7):
		var ray := Vector2.from_angle(float(index)*TAU/7.0+0.2)
		var at := ray*(8.0+age*22.0)+Vector2(0,-age*20.0)
		_pixel_puff(at,7.0+age*12.0,Color(0.20+index*0.008,0.22,0.25,smoke_alpha))
	if age<0.30:
		var fade := 1.0-smoothstep(0.12,0.30,age)
		for index in range(9):
			var ray := Vector2.from_angle(float(index)*TAU/9.0+0.13)
			var reach := age*(70.0+float(index%3)*22.0)
			var at := ray*reach+Vector2(0,-age*14.0)
			var size := (10.0+float(index%3)*2.0)*(1.0-age*1.8)
			_pixel_puff(at,size,Color(0.94,0.23,0.035,fade))
			_pixel_puff(at-ray*3.0,size*0.62,Color(1.0,0.68,0.12,fade))
			if age<0.13:
				_pixel_puff(at-ray*4.0,size*0.30,Color("fff3c4"))
	if age<0.075:
		_pixel_puff(Vector2.ZERO,17.0-age*90.0,Color("fff9e4"))
		fx.draw_rect(Rect2(-29,-1,58,2),Color("fff0b2"))
	# A brief, thin shock front reaches the actual blast radius and immediately dissipates.
	if age<0.19:
		fx.draw_arc(Vector2.ZERO,minf(BLAST_RADIUS,10.0+age*310.0),0,TAU,40,Color(1.0,0.77,0.36,(1.0-age/0.19)*0.7),2.0,false)
	for index in range(14):
		var lifetime := 0.34+float(index%4)*0.075
		if age>=lifetime:
			continue
		var ray := Vector2.from_angle(float(index)*TAU/14.0+0.23)
		var speed := 85.0+float(index%3)*23.0
		var at := ray*speed*age+Vector2(0,65.0*age*age)
		var color := Color("ffd479") if index%3!=0 else Color("a3bec9")
		color.a=1.0-smoothstep(lifetime*0.6,lifetime,age)
		fx.draw_line(at.round(),(at-ray*(4.0 if index%3!=0 else 2.0)).round(),color,2.0,false)
