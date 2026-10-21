extends Node2D
## Playable sniper range using the real hero, health, hit-stop, dodge and counter.
const PLAYER = preload("res://scenes/player.tscn")
const SNIPER = preload("res://scripts/enemies/sniper.gd")
const SESSION = preload("res://scripts/core/game_session.gd")
const VITALS = preload("res://scripts/core/hero_vitals.gd")
const HEALTH = preload("res://scripts/ui/health_hud.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const KIT = preload("res://scripts/levels/level_kit.gd")
const UI = preload("res://scripts/ui/pixel_ui.gd")
const OUTPUT := "res://evidence/sniper_combat/"
var player: CharacterBody2D
var sniper: CharacterBody2D
var session: Node
var vitals: RefCounted
var camera: Camera2D
var status: Label
var hp_label: Label
var ready_for_test := false
var cover: StaticBody2D
var _reset_pending := false
var _smoke := false

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var window := get_tree().root
	window.content_scale_size=Vector2i(320,180)
	window.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch=Window.CONTENT_SCALE_STRETCH_INTEGER
	window.title="夜行者 · 狙击手战斗试玩"
	_smoke=OS.get_cmdline_user_args().has("--sniper-smoke")
	CONTROLS.install()
	KIT.add_box(self,Rect2(-20,140,680,32),"Floor")
	KIT.add_box(self,Rect2(-20,-100,20,240),"LeftWall")
	KIT.add_box(self,Rect2(640,-100,20,240),"RightWall")
	cover=KIT.add_box(self,Rect2(270,91,10,49),"Cover")
	cover.collision_layer=0
	vitals=VITALS.new(100)
	_spawn()
	session=SESSION.new()
	session.name="GameSession"
	add_child(session)
	camera=Camera2D.new()
	camera.position=Vector2(280,90)
	camera.position_smoothing_enabled=false
	camera.process_callback=Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)
	camera.make_current()
	var canvas := CanvasLayer.new()
	canvas.name="EnvironmentUI"
	add_child(canvas)
	UI.label(canvas,Vector2(6,5),Vector2(190,14),"长哨 · 狙击手",12)
	status=UI.label(canvas,Vector2(6,22),Vector2(304,12),"",10,true,UI.small_font())
	hp_label=UI.label(canvas,Vector2(6,36),Vector2(220,12),"",10,true,UI.small_font())
	UI.label(canvas,Vector2(6,153),Vector2(308,12),"AD 移动 · 空格跳跃 · 鼠标攻击 · Shift闪避",10,true,UI.small_font())
	UI.label(canvas,Vector2(6,166),Vector2(308,12),"1远 2中 3近 · C掩体 · R重来 · F1改键",10,true,UI.small_font())
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
	if is_instance_valid(sniper):
		remove_child(sniper)
		sniper.queue_free()
	player=PLAYER.instantiate()
	player.name="Player"
	player.view_mode=1
	player.position=Vector2(160,140)
	add_child(player)
	sniper=SNIPER.new()
	sniper.name="Sniper"
	sniper.position=Vector2(400,140)
	sniper.active=true
	add_child(sniper)
	sniper.bind_hero(player)
	player.attack_received.connect(_on_attack)
	if session!=null:
		session.bind_player(player)
	vitals.refill()
	_reset_pending=false

func _on_attack(result: int, attack: Dictionary) -> void:
	if result==player.AttackResult.HIT:
		vitals.damage(int(attack.get("damage",0)))

func _on_died() -> void:
	sniper.held=true
	_reset_pending=true
	player.freeze(self)
	get_tree().create_timer(0.85).timeout.connect(func() -> void: _spawn.call_deferred())

func _physics_process(_delta: float) -> void:
	if not ready_for_test:
		return
	var middle := (player.position.x+sniper.position.x)*0.5
	var distance := absf(player.position.x-sniper.position.x)
	if distance>250.0:
		middle=player.position.x+signf(sniper.position.x-player.position.x)*75.0
	camera.position=Vector2(roundf(clampf(middle,160,480)),90)
	camera.force_update_scroll()
	var modes := ["远距卧射","站姿射击","近身反击"]
	status.text="%s · 距离 %d" % [modes[sniper.mode],roundi(distance)]
	hp_label.text="敌人生命 %d/%d%s" % [sniper.hp,sniper.max_hp," · R重新挑战" if sniper.dead else ""]
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
			place_player(240.0 if event.keycode==KEY_1 else (100.0 if event.keycode==KEY_2 else 30.0))
		KEY_C:
			cover.collision_layer=1 if cover.collision_layer==0 else 0

func place_player(distance: float) -> void:
	player.position=sniper.position-Vector2(distance,0)
	player.velocity=Vector2.ZERO
	player.clear_input_buffer()
	for bullet in get_tree().get_nodes_in_group(&"ballistic_rounds"):
		bullet.queue_free()

func _draw() -> void:
	draw_rect(Rect2(0,0,640,180),Color("111a23"))
	for x in range(0,640,32):
		draw_rect(Rect2(x,50,1,89),Color("20313b"))
		draw_rect(Rect2(x+8,72,15,2),Color("293c45"))
	draw_rect(Rect2(0,140,640,40),Color("333c3e"))
	draw_rect(Rect2(0,140,640,1),Color("92a3a0"))
	for x in range(0,640,16):
		draw_rect(Rect2(x,145,8,1),Color("485453"))
	if is_instance_valid(sniper):
		var left: float=sniper.home_position.x-sniper.region_radius
		var right: float=sniper.home_position.x+sniper.region_radius
		draw_line(Vector2(left,139),Vector2(right,139),Color("a6814f"),1.0,false)
		for x in [left,right]:
			draw_rect(Rect2(x,135,1,5),Color("dbb372"))
	if is_instance_valid(cover) and cover.collision_layer!=0:
		draw_rect(Rect2(270,91,10,49),Color("68777c"))
		draw_rect(Rect2(272,94,2,41),Color("8c9a9b"))

func _record() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var frames: Array = []
	# Staged distances, real physics/AI/player. Viewport snapshots record visible lasers and impact motion.
	player.invulnerable=false
	for stage in [["far",240.0,2.8],["middle",100.0,2.7],["close",30.0,2.4]]:
		place_player(stage[1])
		for index in range(int(float(stage[2])*30.0)):
			await get_tree().physics_frame
			await get_tree().physics_frame
			await RenderingServer.frame_post_draw
			var path := OUTPUT+"%s_%03d.png" % [stage[0],index]
			get_viewport().get_texture().get_image().save_png(path)
			var rounds: Array = []
			for bullet in get_tree().get_nodes_in_group(&"ballistic_rounds"):
				if not bullet.spent:
					rounds.append([bullet.position.x,bullet.position.y])
			frames.append({"file":path,"stage":stage[0],"posture":sniper.posture,"phase":sniper.phase,"shots":sniper.shot_count,
				"aiming":sniper.aiming(),"muzzle":[sniper.muzzle().x,sniper.muzzle().y],
				"sight":[sniper.sight_end.x,sniper.sight_end.y],"laser_visible":sniper.laser.is_visible_in_tree(),
				"camera":[camera.position.x,camera.position.y],"rounds":rounds,"flash":sniper._flash_seconds>0.0})
	var file := FileAccess.open(OUTPUT+"recording.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":frames,"shots":sniper.shot_count,"melees":sniper.melee_count},"\t"))
	get_tree().quit()
