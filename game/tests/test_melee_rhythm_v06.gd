extends "res://tests/support/isolated_suite.gd"
## Actual close-range sniper attacks, crowd rehit spacing, buffered escapes and real perfect counters.
const ARENA = preload("res://scenes/melee_combat_test.tscn")
const RHYTHM = preload("res://scripts/enemies/melee_rhythm.gd")
var arena: Node2D
var rate := 60
var checks := 0
var failures: Array[String] = []
var observed: Dictionary = {}

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--melee-30"):
		rate=30
	elif OS.get_cmdline_user_args().has("--melee-144"):
		rate=144
	Engine.physics_ticks_per_second=rate
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func seconds(duration: float) -> void:
	await frames(ceili(duration*rate))

func until(condition: Callable, duration := 4.0) -> bool:
	for index in range(ceili(duration*rate)):
		if condition.call():
			return true
		await frames(1)
	return condition.call()

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index=button
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func fresh(mode := 1) -> void:
	arena.session.cancel_hit_stop()
	arena._spawn(mode)
	await frames(4)

func run() -> void:
	arena=ARENA.instantiate()
	root.add_child(arena)
	current_scene=arena
	await frames(5)
	check(arena.ready_for_test,"The melee range loads the real player, health and enemies")
	for mode in [1,2]:
		await fresh(mode)
		var enemy: CharacterBody2D=arena.enemies[0]
		check(await until(func() -> bool: return arena.stage(enemy)=="前摇预警"),"Entering close range starts a readable windup: "+enemy.kind)
		var tell_started: float=arena.player.combat_time
		await seconds(0.42)
		check(arena.vitals.hp==100 and arena.stage(enemy)=="前摇预警","The nearby enemy cannot immediately damage the player during its tell")
		check(await until(func() -> bool: return arena.vitals.hp<100,0.5),"The committed melee still lands when the player stands in it")
		var first_hit: float=arena.player.combat_time
		check(first_hit-tell_started>=0.50,"At least half a second of visible preparation precedes actual contact")
		check(await until(func() -> bool: return arena.stage(enemy)=="收招空隙",0.4),"The swing enters a separate harmless recovery pose")
		var recover_started: float=arena.player.combat_time
		var before_hp: int=arena.vitals.hp
		await seconds(0.42)
		check(arena.stage(enemy)=="收招空隙" and arena.vitals.hp==before_hp,"The enemy stays punishable and cannot re-hit during recovery")
		check(arena.player.state==arena.player.State.FREE,"The player's control returns before the enemy finishes recovery")
		observed[enemy.kind]={"first_contact_delay":first_hit-tell_started,"recovery_checked":arena.player.combat_time-recover_started}
	await fresh(2)
	check(await until(func() -> bool: return arena.player.state==arena.player.State.HURT),"Stage a genuine melee hit for the buffered escape")
	var hit_time: float=arena.player.combat_time
	check(not RHYTHM.can_begin(arena.player),"An unrecovered victim cannot be covered by a fresh melee windup")
	key(KEY_SHIFT,true)
	await frames(1)
	key(KEY_SHIFT,false)
	await frames(1)
	check(arena.player.state==arena.player.State.HURT,"A buffered dodge does not erase the remaining hit reaction")
	check(await until(func() -> bool: return arena.player.is_dodging,0.4),"A Shift tap early in the stun survives until control returns")
	check(absf(arena.player.combat_time-hit_time-0.3)<2.1/float(rate),"The buffered dodge starts as soon as the 0.3-second stun ends")
	check(arena.player.melee_protection_left>0.5,"The victim has a usable protection interval after recovering")
	var protected_result: int=arena.player.receive_attack({"source":arena.enemies[0],"direction":Vector2.LEFT,"damage":10,"attack_kind":"melee","window_age":0.0})
	check(protected_result==arena.player.AttackResult.PERFECT and arena.player.counter_ready,
		"A fresh deliberate dodge can still earn PERFECT while anti-stunlock protection remains")
	await fresh(1)
	var sniper: CharacterBody2D=arena.enemies[0]
	await until(func() -> bool: return sniper.phase==sniper.Phase.MELEE and sniper.phase_time>=sniper.MELEE_WINDUP-0.14)
	key(KEY_SHIFT,true)
	await frames(1)
	key(KEY_SHIFT,false)
	check(await until(func() -> bool: return arena.player.counter_ready,0.5),"Real Shift timing near the enlarged windup's end earns a perfect melee dodge")
	check(arena.vitals.hp==100 and String(arena.player.sprite.animation).begins_with("perfect_dodge_"),"Perfect evasion shows its dedicated animation without damage")
	mouse(MOUSE_BUTTON_RIGHT,true)
	await frames(1)
	mouse(MOUSE_BUTTON_RIGHT,false)
	check(await until(func() -> bool: return sniper.hp<12,1.0),"The real counter punishes the recovering melee enemy")
	check(sniper.hp==9,"A perfect melee dodge still grants the actual triple-damage counter")
	await fresh(1)
	sniper=arena.enemies[0]
	await until(func() -> bool: return sniper.phase==sniper.Phase.MELEE and sniper.phase_time>=sniper.MELEE_WINDUP-0.25-2.0/float(rate))
	key(KEY_SHIFT,true)
	await frames(1)
	key(KEY_SHIFT,false)
	await seconds(0.65)
	observed["ordinary_dodge"]={"hp":arena.vitals.hp,"slowmo":arena.session.slowmo_active,"events":arena.events.duplicate(true)}
	check(arena.vitals.hp==100 and not arena.session.slowmo_active,"An early ordinary dodge evades the committed direction without falsely granting PERFECT")
	await fresh(2)
	var defender: CharacterBody2D=arena.enemies[0]
	await until(func() -> bool: return arena.stage(defender)=="收招空隙")
	arena.player.position=defender.position-Vector2(24,0)
	arena.player.velocity=Vector2.ZERO
	arena.player.facing="right"
	await until(func() -> bool: return arena.player.state==arena.player.State.FREE,0.4)
	var defender_hp: int=defender.hp
	mouse(MOUSE_BUTTON_LEFT,true)
	await frames(1)
	mouse(MOUSE_BUTTON_LEFT,false)
	check(await until(func() -> bool: return defender.hp<defender_hp,0.7),"The recovery window is long enough for a real player attack to punish")
	await fresh(3)
	var longest_hurt := 0.0
	var hurt_run := 0.0
	var longest_control := 0.0
	var control_run := 0.0
	for index in range(rate*6):
		await frames(1)
		if arena.player.state==arena.player.State.HURT:
			hurt_run+=1.0/float(rate)
			control_run=0.0
		else:
			control_run+=1.0/float(rate)
			hurt_run=0.0
		longest_hurt=maxf(longest_hurt,hurt_run)
		longest_control=maxf(longest_control,control_run)
	var hits: Array=arena.events.filter(func(event: Dictionary) -> bool: return event.result==arena.player.AttackResult.HIT)
	check(hits.size()>=2,"Several real surrounding enemies remain able to threaten a stationary player")
	var min_interval := INF
	for index in range(1,hits.size()):
		min_interval=minf(min_interval,float(hits[index].time)-float(hits[index-1].time))
	check(min_interval>=0.90-1.1/float(rate),"Alternating real enemies cannot bypass the shared melee rehit interval")
	check(longest_hurt<=0.3+1.1/float(rate) and longest_control>=0.55,"Crowd hits cannot chain the stun; the player repeatedly regains a usable action window")
	observed["crowd"]={"hits":hits.size(),"min_hit_interval":min_interval,"longest_stun":longest_hurt,"longest_control":longest_control}
	await fresh(3)
	var attack := {"source":arena.enemies[0],"direction":Vector2.LEFT,"damage":10,"knockback":0.0,"attack_kind":"melee"}
	check(arena.player.receive_attack(attack)==arena.player.AttackResult.HIT,"Start a simultaneous-source protection check")
	var deadline: float=arena.player._melee_protected_until
	for enemy in arena.enemies:
		attack.source=enemy
		check(arena.player.receive_attack(attack)==arena.player.AttackResult.EVADE,"Another nearby source cannot add a same-frame melee hit")
	check(arena.player._melee_protected_until==deadline and arena.vitals.hp==90,"Rejected melee hits do not refresh protection, stun, or damage")
	for enemy in arena.enemies:
		enemy.active=false
	await seconds(0.72)
	check(arena.player.hit_invulnerability_left==0.0 and arena.player.receive_attack(attack)==arena.player.AttackResult.EVADE,
		"A late melee from another source is still rejected after ordinary hit invulnerability expires")
	check(arena.player._melee_protected_until==deadline and arena.player.state==arena.player.State.FREE and arena.vitals.hp==90,
		"Late crowd pressure cannot refresh the protection or restart the stun")
	await seconds(0.22)
	check(arena.player.receive_attack(attack)==arena.player.AttackResult.HIT and arena.vitals.hp==80,
		"Melee becomes dangerous again after the finite 0.9-second recovery opportunity")
	await fresh(2)
	defender=arena.enemies[0]
	var wall: StaticBody2D=arena.KIT.add_box(arena,Rect2(214,75,4,65),"MeleeWall")
	await seconds(1.5)
	check(arena.vitals.hp==100 and defender.position.x>=224.0-0.1,"A real sniper lunge and baton cannot hit through solid cover")
	wall.queue_free()
	await frames(2)
	await fresh(1)
	sniper=arena.enemies[0]
	await until(func() -> bool: return sniper.phase==sniper.Phase.MELEE)
	var before: float=sniper.phase_time
	arena.session.world_time_scale=0.25
	await seconds(0.4)
	check(sniper.phase_time-before>0.07 and sniper.phase_time-before<0.14,"The melee tell follows the same quarter-speed world clock as enemies")
	arena.session.world_time_scale=1.0
	before=sniper.phase_time
	arena.session.open_keybindings()
	await seconds(0.2)
	check(sniper.phase_time==before,"Settings pause the melee tell instead of allowing an unseen hit")
	arena.session._close_keybindings(false)
	var report := {"suite":"melee_rhythm_v06","passed":failures.is_empty(),"checks":checks,"physics_rate":rate,"failures":failures,"observed":observed}
	DirAccess.make_dir_recursive_absolute("res://evidence/melee_v06/")
	var file := FileAccess.open("res://evidence/melee_v06/test_%d.json"%rate,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
