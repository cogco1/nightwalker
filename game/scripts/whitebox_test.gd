extends Node2D
const PLAYER = preload("res://scenes/player.tscn")
const SNIPER = preload("res://scripts/enemies/sniper.gd")
const DRONE = preload("res://scripts/enemies/cannon_drone.gd")
const SESSION = preload("res://scripts/core/game_session.gd")
const VITALS = preload("res://scripts/core/hero_vitals.gd")
const HEALTH = preload("res://scripts/ui/health_hud.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const KIT = preload("res://scripts/levels/level_kit.gd")
const UI = preload("res://scripts/ui/pixel_ui.gd")
const WIDTH := 1440.0
var player: CharacterBody2D
var sniper: CharacterBody2D
var drone: CharacterBody2D
var session: Node
var camera: Camera2D
var vitals: RefCounted
var ready_for_test := false
var _respawning := false

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	get_tree().root.title="夜行者 · 白盒测试"
	CONTROLS.install()
	KIT.add_box(self,Rect2(-20,140,WIDTH+40,40),"Floor")
	KIT.add_box(self,Rect2(-20,-120,20,260),"LeftWall")
	KIT.add_box(self,Rect2(WIDTH,-120,20,260),"RightWall")
	KIT.add_box(self,Rect2(710,96,12,44),"Cover")
	KIT.add_box(self,Rect2(220,104,48,7),"JumpPlatform")
	vitals=VITALS.new(100)
	_spawn()
	session=SESSION.new()
	session.name="GameSession"
	add_child(session)
	camera=Camera2D.new()
	camera.name="Camera"
	camera.position=Vector2(160,90)
	camera.process_callback=Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)
	camera.make_current()
	var canvas := CanvasLayer.new()
	canvas.name="WhiteboxUI"
	add_child(canvas)
	UI.label(canvas,Vector2(6,5),Vector2(240,14),"白盒测试 · 狙击手 / 无人机",12)
	UI.label(canvas,Vector2(6,153),Vector2(310,12),"AD移动 · 空格跳跃 · 鼠标攻击 · Shift闪避",10,true,UI.small_font())
	UI.label(canvas,Vector2(6,166),Vector2(310,12),"1狙击手 2无人机 · R重置 · F1设置",10,true,UI.small_font())
	var back := Button.new()
	back.name="BackToEntry"
	back.text="返回入口"
	back.position=Vector2(254,22)
	back.size=Vector2(60,20)
	back.add_theme_font_override("font",UI.small_font())
	back.add_theme_font_size_override("font_size",10)
	back.pressed.connect(return_to_entry)
	canvas.add_child(back)
	var health := HEALTH.new()
	add_child(health)
	health.build(canvas)
	health.bind(vitals)
	health.set_visible(true)
	vitals.died.connect(_on_died)
	ready_for_test=true

func _spawn() -> void:
	if session!=null:
		session.cancel_hit_stop()
		session.end_slowmo()
	for bullet in get_tree().get_nodes_in_group(&"ballistic_rounds"):
		bullet.queue_free()
	for body in [player,sniper,drone]:
		if is_instance_valid(body):
			remove_child(body)
			body.queue_free()
	player=PLAYER.instantiate()
	player.name="Player"
	player.view_mode=1
	player.position=Vector2(80,140)
	add_child(player)
	sniper=SNIPER.new()
	sniper.name="Sniper"
	sniper.position=Vector2(480,140)
	sniper.active=true
	add_child(sniper)
	sniper.bind_hero(player)
	drone=DRONE.new()
	drone.name="CannonDrone"
	drone.position=Vector2(1120,105)
	add_child(drone)
	drone.bind_hero(player)
	player.attack_received.connect(_on_attack)
	if session!=null:session.bind_player(player)
	vitals.refill()
	_respawning=false

func _on_attack(result: int, attack: Dictionary) -> void:
	if result==player.AttackResult.HIT:vitals.damage(int(attack.get("damage",0)))

func _on_died() -> void:
	if _respawning:return
	_respawning=true
	sniper.held=true
	drone.held=true
	player.freeze(self)
	get_tree().create_timer(0.7).timeout.connect(func() -> void: _spawn.call_deferred())

func _physics_process(_delta: float) -> void:
	if ready_for_test:
		camera.position=Vector2(roundf(clampf(player.position.x+30,160,WIDTH-160)),90)
		camera.force_update_scroll()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or session.settings_open:return
	match event.keycode:
		KEY_R: _spawn.call_deferred()
		KEY_1: _place_player(Vector2(448,140))
		KEY_2: _place_player(Vector2(960,140))

func _place_player(at: Vector2) -> void:
	if session.hit_stop_active or _respawning:return
	player.clear_input_buffer()
	player.position=at
	player.velocity=Vector2.ZERO

func return_to_entry() -> void:
	session.cancel_hit_stop()
	session.end_slowmo()
	player.clear_input_buffer()
	get_tree().paused=false
	get_tree().change_scene_to_file.call_deferred("res://scenes/boot.tscn")

func _draw() -> void:
	draw_rect(Rect2(0,-120,WIDTH,300),Color("20252b"))
	for x in range(0,int(WIDTH),16):draw_line(Vector2(x,0),Vector2(x,140),Color("30363d"))
	for y in range(12,140,16):draw_line(Vector2(0,y),Vector2(WIDTH,y),Color("30363d"))
	draw_rect(Rect2(0,140,WIDTH,40),Color("7d858b"))
	draw_line(Vector2(0,140),Vector2(WIDTH,140),Color("d0d4d8"))
	draw_rect(Rect2(710,96,12,44),Color("a5abb0"))
	draw_rect(Rect2(220,104,48,7),Color("a5abb0"))
