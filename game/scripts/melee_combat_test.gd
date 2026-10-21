extends Node2D
## Hands-on melee timing range: the same hero, snipers, health and shared session.
const PLAYER = preload("res://scenes/player.tscn")
const SNIPER = preload("res://scripts/enemies/sniper.gd")
const SESSION = preload("res://scripts/core/game_session.gd")
const VITALS = preload("res://scripts/core/hero_vitals.gd")
const HEALTH = preload("res://scripts/ui/health_hud.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const KIT = preload("res://scripts/levels/level_kit.gd")
const UI = preload("res://scripts/ui/pixel_ui.gd")
const OUTPUT := "res://evidence/melee_v06/"
var player: CharacterBody2D
var enemies: Array[CharacterBody2D] = []
var session: Node
var vitals: RefCounted
var camera: Camera2D
var status: Label
var detail: Label
var mode := 1
var events: Array[Dictionary] = []
var ready_for_test := false

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var window := get_tree().root
	window.content_scale_size=Vector2i(320,180)
	window.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch=Window.CONTENT_SCALE_STRETCH_INTEGER
	window.title="夜行者 · 近战闪避练习"
	CONTROLS.install()
	KIT.add_box(self,Rect2(-20,140,680,40),"Floor")
	KIT.add_box(self,Rect2(-20,-20,20,160),"LeftWall")
	KIT.add_box(self,Rect2(640,-20,20,160),"RightWall")
	vitals=VITALS.new(100)
	_spawn(1)
	session=SESSION.new()
	add_child(session)
	camera=Camera2D.new()
	camera.position=Vector2(220,90)
	camera.position_smoothing_enabled=false
	camera.process_callback=Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)
	camera.make_current()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	UI.label(canvas,Vector2(6,5),Vector2(220,14),"近战节奏 · 看准再闪",12)
	status=UI.label(canvas,Vector2(6,23),Vector2(308,12),"",10,true,UI.small_font())
	detail=UI.label(canvas,Vector2(6,37),Vector2(308,12),"",10,true,UI.small_font())
	UI.label(canvas,Vector2(6,153),Vector2(308,12),"短按Shift闪避 · 完美闪避后点击攻击",10,true,UI.small_font())
	UI.label(canvas,Vector2(6,166),Vector2(308,12),"1狙击手 2近距 3围攻 · R重来 · F1改键",10,true,UI.small_font())
	var health := HEALTH.new()
	add_child(health)
	health.build(canvas)
	health.bind(vitals)
	health.set_visible(true)
	ready_for_test=true
	if OS.get_cmdline_user_args().has("--melee-smoke"):
		_record.call_deferred()

func _spawn(next_mode: int) -> void:
	mode=next_mode
	if session!=null:
		session.end_slowmo()
	for bullet in get_tree().get_nodes_in_group(&"ballistic_rounds"):
		bullet.queue_free()
	for enemy in enemies:
		remove_child(enemy)
		enemy.queue_free()
	enemies.clear()
	if is_instance_valid(player):
		remove_child(player)
		player.queue_free()
	player=PLAYER.instantiate()
	player.view_mode=1
	player.position=Vector2(200,140)
	add_child(player)
	var layout := [[SNIPER,232.0]] if mode==1 else ([[SNIPER,228.0]] if mode==2 else [[SNIPER,226.0],[SNIPER,174.0],[SNIPER,236.0]])
	for row in layout:
		var enemy: CharacterBody2D=row[0].new()
		enemy.position=Vector2(row[1],140)
		enemy.active=true
		add_child(enemy)
		enemy.bind_hero(player)
		enemies.append(enemy)
	player.attack_received.connect(_on_attack)
	if session!=null:
		session.bind_player(player)
	vitals.refill()
	events.clear()

func _on_attack(result: int, attack: Dictionary) -> void:
	events.append({"time":player.combat_time,"result":result,"kind":str(attack.get("attack_kind",""))})
	if result==player.AttackResult.HIT:
		vitals.damage(int(attack.get("damage",0)))

func stage(enemy: CharacterBody2D) -> String:
	if enemy.dead:
		return "已击败"
	if enemy.kind=="sniper":
		if enemy.phase==enemy.Phase.MELEE:
			return "前摇预警" if enemy.phase_time<enemy.MELEE_WINDUP else ("挥击" if enemy.phase_time<enemy.MELEE_WINDUP+enemy.MELEE_ACTIVE else "收招空隙")
		return "等待下一击"
	return "等待下一击"

func _physics_process(_delta: float) -> void:
	if not ready_for_test:
		return
	camera.position=Vector2(roundf(clampf(player.position.x+24.0,160.0,480.0)),90)
	camera.force_update_scroll()
	status.text=stage(enemies[0])+" · 前摇0.55秒 / 收招0.55秒"
	detail.text="受击后可提前输入闪避"
	if player.state==player.State.HURT:
		detail.text="受击硬直 · 现在短按Shift，恢复时闪避"
	elif player.melee_protection_left>0.0:
		detail.text="近战保护 %.2f秒 · 可以移动或闪避"%player.melee_protection_left
	if player.counter_ready:
		detail.text="完美闪避成功 · 点击攻击反击"
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or session.settings_open:
		return
	match event.keycode:
		KEY_1,KEY_2,KEY_3: _spawn(int(event.keycode-KEY_0))
		KEY_R: _spawn(mode)
		KEY_ESCAPE: get_tree().quit()

func _draw() -> void:
	draw_rect(Rect2(0,0,640,180),Color("111b24"))
	for x in range(0,640,32):
		draw_rect(Rect2(x,54,1,86),Color("283a44"))
	draw_rect(Rect2(0,140,640,40),Color("354247"))
	draw_rect(Rect2(0,140,640,1),Color("9aaead"))
	for x in range(0,640,16):
		draw_rect(Rect2(x,148,8,1),Color("53666a"))

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _record() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var records: Array=[]
	for scene in [["windup_recovery",1,3.2],["buffered_escape",2,2.4],["perfect_counter",1,2.6],["crowd",3,3.4]]:
		_spawn(scene[1])
		var tapped := false
		var release_next := false
		var countered := false
		for index in range(int(float(scene[2])*60.0)):
			if release_next:
				_key(KEY_SHIFT,false)
				release_next=false
			if scene[0]=="buffered_escape" and not tapped and player.state==player.State.HURT:
				_key(KEY_SHIFT,true)
				release_next=true
				tapped=true
			if scene[0]=="perfect_counter" and not tapped and enemies[0].phase==enemies[0].Phase.MELEE and enemies[0].phase_time>=enemies[0].MELEE_WINDUP-0.14:
				_key(KEY_SHIFT,true)
				release_next=true
				tapped=true
			if scene[0]=="perfect_counter" and player.counter_ready and player.perfect_pose_left<=0.0 and not countered:
				var event := InputEventMouseButton.new()
				event.button_index=MOUSE_BUTTON_RIGHT
				event.pressed=true
				Input.parse_input_event(event)
				Input.flush_buffered_events()
				countered=true
			elif countered:
				var event := InputEventMouseButton.new()
				event.button_index=MOUSE_BUTTON_RIGHT
				event.pressed=false
				Input.parse_input_event(event)
				Input.flush_buffered_events()
			await get_tree().physics_frame
			if index%2!=0:
				continue
			await RenderingServer.frame_post_draw
			var path := OUTPUT+"%s_%03d.png"%[scene[0],index/2]
			get_viewport().get_texture().get_image().save_png(path)
			records.append({"file":path,"stage":scene[0],"enemy_stage":stage(enemies[0]),"time":player.combat_time,
				"state":player.state,"animation":String(player.sprite.animation),"hp":vitals.hp,"dodge":player.is_dodging,
				"melee_protection":player.melee_protection_left,"counter":player.counter_ready,"move":String(player.move_id),
				"player":[player.position.x,player.position.y],"camera":[camera.position.x,camera.position.y],"camera_offset":[camera.offset.x,camera.offset.y],"events":events.duplicate(true)})
	var file := FileAccess.open(OUTPUT+"recording.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":records},"\t"))
	get_tree().quit()
