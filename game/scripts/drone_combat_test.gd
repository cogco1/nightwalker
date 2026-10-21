extends Node2D
## Playable cannon drone: the real hero and shared health, hit-stop and dodge session.
const PLAYER = preload("res://scenes/player.tscn")
const DRONE = preload("res://scripts/enemies/cannon_drone.gd")
const SESSION = preload("res://scripts/core/game_session.gd")
const VITALS = preload("res://scripts/core/hero_vitals.gd")
const HEALTH = preload("res://scripts/ui/health_hud.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const KIT = preload("res://scripts/levels/level_kit.gd")
const UI = preload("res://scripts/ui/pixel_ui.gd")
const OUTPUT := "res://evidence/drone_combat/"
var player: CharacterBody2D
var drone: CharacterBody2D
var session: Node
var vitals: RefCounted
var camera: Camera2D
var cover: StaticBody2D
var status: Label
var hp_label: Label
var ready_for_test := false
var _reset_pending := false
var _smoke := false

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var window := get_tree().root
	window.content_scale_size=Vector2i(320,180)
	window.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch=Window.CONTENT_SCALE_STRETCH_INTEGER
	window.title="夜行者 · 机炮无人机战斗试玩"
	_smoke=OS.get_cmdline_user_args().has("--drone-smoke")
	CONTROLS.install()
	KIT.add_box(self,Rect2(-20,140,680,32),"Floor")
	KIT.add_box(self,Rect2(-20,-20,20,160),"LeftWall")
	KIT.add_box(self,Rect2(640,-20,20,160),"RightWall")
	KIT.add_box(self,Rect2(0,-20,640,20),"Ceiling")
	cover=KIT.add_box(self,Rect2(275,85,10,55),"Cover")
	cover.collision_layer=0
	vitals=VITALS.new(100)
	_spawn()
	session=SESSION.new()
	session.name="GameSession"
	add_child(session)
	camera=Camera2D.new()
	camera.position=Vector2(290,90)
	camera.position_smoothing_enabled=false
	camera.process_callback=Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)
	camera.make_current()
	var canvas := CanvasLayer.new()
	canvas.name="EnvironmentUI"
	add_child(canvas)
	UI.label(canvas,Vector2(6,5),Vector2(220,14),"烛眼 · 机炮无人机",12)
	status=UI.label(canvas,Vector2(6,22),Vector2(305,12),"",10,true,UI.small_font())
	hp_label=UI.label(canvas,Vector2(6,36),Vector2(220,12),"",10,true,UI.small_font())
	UI.label(canvas,Vector2(6,153),Vector2(308,12),"AD移动 · 空格跳跃 · 鼠标攻击 · Shift闪避",10,true,UI.small_font())
	UI.label(canvas,Vector2(6,166),Vector2(308,12),"4撤远冲撞 · B自爆 · H/J受击 · R重来",10,true,UI.small_font())
	var health := HEALTH.new()
	add_child(health)
	health.build(canvas)
	health.bind(vitals)
	health.set_visible(true)
	vitals.died.connect(_on_died)
	ready_for_test=true
	if _smoke:
		_record.call_deferred()

func _spawn() -> void:
	for bullet in get_tree().get_nodes_in_group(&"ballistic_rounds"):
		bullet.queue_free()
	if is_instance_valid(player):
		remove_child(player)
		player.queue_free()
	if is_instance_valid(drone):
		remove_child(drone)
		drone.queue_free()
	player=PLAYER.instantiate()
	player.name="Player"
	player.view_mode=1
	player.position=Vector2(180,140)
	add_child(player)
	drone=DRONE.new()
	drone.name="CannonDrone"
	drone.position=Vector2(400,106)
	add_child(drone)
	drone.bind_hero(player)
	player.attack_received.connect(_on_attack)
	if session!=null:
		session.bind_player(player)
	vitals.refill()
	_reset_pending=false

func _on_attack(result: int, attack: Dictionary) -> void:
	if result==player.AttackResult.HIT:
		vitals.damage(int(attack.get("damage",0)))

func _on_died() -> void:
	drone.held=true
	_reset_pending=true
	player.freeze(self)
	get_tree().create_timer(0.85).timeout.connect(func() -> void: _spawn.call_deferred())

func _physics_process(_delta: float) -> void:
	if not ready_for_test:
		return
	var middle := (player.position.x+drone.position.x)*0.5
	if absf(player.position.x-drone.position.x)>250.0:
		middle=player.position.x+signf(drone.position.x-player.position.x)*75.0
	camera.position=Vector2(roundf(clampf(middle,160,480)),90)
	camera.force_update_scroll()
	var phases := ["区域追击","减速瞄准","三发点射","后坐恢复","自爆警报","已自爆","冲撞预警","加速冲撞"]
	status.text="%s · 距离 %d" % [phases[drone.phase],roundi(player.position.distance_to(drone.position))]
	if drone.self_destructing:
		status.text="自爆警报 %.1f秒 · 离开红圈或补刀"%maxf(0.0,drone.FUSE_SECONDS-drone.phase_time)
	elif drone.rushing():
		status.text="撤远触发冲撞 · 预警后加速自爆"
	elif drone.returning_home:
		status.text="已脱离追击区域 · 无人机返回"
	if player.hit_invulnerability_left>0.0:
		status.text="%s受击 · 保护 %.2f秒"%["背面" if player.hurt_from_back else "正面",player.hit_invulnerability_left]
	if player.counter_ready:
		status.text="完美闪避 · 点击攻击发动反击"
	hp_label.text="敌人生命 %d/%d%s" % [drone.hp,drone.max_hp," · R重新挑战" if drone.dead else ""]
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or session.settings_open:
		return
	match event.keycode:
		KEY_ESCAPE: get_tree().quit()
		KEY_R:
			if not _reset_pending:
				_spawn.call_deferred()
		KEY_1,KEY_2,KEY_3:
			place_player(220.0 if event.keycode==KEY_1 else (75.0 if event.keycode==KEY_2 else -140.0))
		KEY_C:
			cover.collision_layer=1 if cover.collision_layer==0 else 0
		KEY_B:
			if not drone.dead and not drone.self_destructing:
				drone.take_damage(maxi(0,drone.hp-3))
		KEY_H,KEY_J:
			practice_hit(event.keycode==KEY_J)
		KEY_4:
			practice_retreat()

func practice_retreat() -> void:
	_spawn()
	place_player(120.0)
	await get_tree().create_timer(0.2,false).timeout
	if is_instance_valid(player) and is_instance_valid(drone) and not drone.dead:
		place_player(330.0)

func practice_hit(from_back: bool) -> void:
	drone.active=false
	for bullet in get_tree().get_nodes_in_group(&"ballistic_rounds"):
		bullet.queue_free()
	var direction: Vector2=player._facing_vector()*(1.0 if from_back else -1.0)
	player.receive_attack({"source":null,"direction":direction,"contact":true,"window_age":0.0,
		"damage":10,"knockback":18.0,"weapon":"practice"})

func place_player(distance: float) -> void:
	player.position=Vector2(drone.position.x-distance,140)
	player.velocity=Vector2.ZERO
	player.clear_input_buffer()
	for bullet in get_tree().get_nodes_in_group(&"ballistic_rounds"):
		bullet.queue_free()

func _draw() -> void:
	draw_rect(Rect2(0,0,640,180),Color("101b24"))
	for x in range(0,640,32):
		draw_rect(Rect2(x,52,1,88),Color("263840"))
		draw_rect(Rect2(x+7,63,18,2),Color("30444c"))
	draw_rect(Rect2(0,140,640,40),Color("333d40"))
	draw_rect(Rect2(0,140,640,1),Color("9baaa4"))
	for x in range(0,640,16):
		draw_rect(Rect2(x,146,8,1),Color("4c5e5e"))
	if is_instance_valid(drone) and drone.territory!=null:
		for side in [-1,1]:
			var edge: float=drone.home_position.x+float(side)*drone.territory_radius
			draw_line(Vector2(edge,58),Vector2(edge,140),Color(0.35,0.65,0.75,0.65),1.0,false)
	if is_instance_valid(cover) and cover.collision_layer!=0:
		draw_rect(Rect2(275,85,10,55),Color("75878a"))
		draw_rect(Rect2(278,89,2,47),Color("a1a99d"))

func _record() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var capture: Array = []
	drone.active=false
	for stage in [["hover",2.4],["burst",3.8],["cover",1.8],["right",3.2],["self_destruct",2.4],
		["front_right",1.1],["back_right",1.1],["front_left",1.1],["back_left",1.1],
		["perfect_counter",2.5],["retreat_rush",3.2]]:
		if stage[0]=="burst":
			drone.active=true
		elif stage[0]=="cover":
			cover.collision_layer=1
		elif stage[0]=="right":
			cover.collision_layer=0
			place_player(-140.0)
			vitals.refill()
		elif stage[0]=="self_destruct":
			_spawn()
			place_player(40.0)
			drone.take_damage(9)
		elif String(stage[0]).begins_with("front_") or String(stage[0]).begins_with("back_"):
			_spawn()
			drone.active=false
			place_player(80.0)
			player.facing="left" if String(stage[0]).ends_with("left") else "right"
			practice_hit(String(stage[0]).begins_with("back_"))
		elif stage[0]=="perfect_counter":
			_spawn()
			drone.active=false
			place_player(70.0)
			player.facing="right"
			player.request_dodge(Vector2.RIGHT)
			# A real cannon round reaches the real hurtbox during a correctly timed dodge.
			var round: Node2D=drone.ROUND.new()
			round.setup(drone,player,player.hurtbox().get_center()+Vector2(18,0),Vector2.LEFT,drone.ROUND.Weapon.DRONE_CANNON)
			add_child(round)
		elif stage[0]=="retreat_rush":
			_spawn()
			place_player(120.0)
		for index in range(int(float(stage[1])*30.0)):
			if stage[0]=="retreat_rush" and index==6:
				place_player(330.0)
			if stage[0]=="perfect_counter" and index==12:
				var event := InputEventMouseButton.new()
				event.button_index=MOUSE_BUTTON_RIGHT
				event.pressed=true
				Input.parse_input_event(event)
				Input.flush_buffered_events()
			if stage[0]=="perfect_counter" and index==13:
				var event := InputEventMouseButton.new()
				event.button_index=MOUSE_BUTTON_RIGHT
				event.pressed=false
				Input.parse_input_event(event)
				Input.flush_buffered_events()
			await get_tree().physics_frame
			await get_tree().physics_frame
			await RenderingServer.frame_post_draw
			var path := OUTPUT+"%s_%03d.png"%[stage[0],index]
			get_viewport().get_texture().get_image().save_png(path)
			var rounds: Array=[]
			for bullet in get_tree().get_nodes_in_group(&"ballistic_rounds"):
				if not bullet.spent:
					rounds.append([bullet.position.x,bullet.position.y])
			capture.append({"file":path,"stage":stage[0],"phase":drone.phase,"shots":drone.shot_count,
				"camera":[camera.position.x,camera.position.y],"camera_offset":[camera.offset.x,camera.offset.y],"body":[drone.position.x,drone.position.y],
				"muzzle":[drone.muzzle().x,drone.muzzle().y],"rounds":rounds,
				"flash":drone._muzzle_flash>0.0,"explosion":drone.explosion_left>0.0,
				"hp":vitals.hp,"player_x":player.position.x,"player":[player.position.x,player.position.y],
				"facing":player.facing,"hurt_back":player.hurt_from_back,"hurt_pose":[player.hurt_pose_shift.x,player.hurt_pose_shift.y],
				"protection":player.hit_invulnerability_left,"player_state":player.state,"animation":String(player.sprite.animation),
				"counter_ready":player.counter_ready,"move":String(player.move_id),"drone_hp":drone.hp,"slowmo":session.slowmo_active,
				"ghosts":player.fx.afterimages.size(),"hurt_shakes":session.hurt_shake_count,
				"home":[drone.home_position.x,drone.home_position.y],"territory_radius":drone.territory_radius,
				"rush_speed":drone.rush_speed,"pursuing":drone.pursuing,"returning":drone.returning_home})
	var file := FileAccess.open(OUTPUT+"recording.json",FileAccess.WRITE)
	var maximum_shots := 0
	for frame: Dictionary in capture:
		maximum_shots=maxi(maximum_shots,int(frame.shots))
	file.store_string(JSON.stringify({"frames":capture,"shots":maximum_shots},"\t"))
	get_tree().quit()
