extends "res://tests/support/isolated_suite.gd"
## Real shared damage path: directional recoil, multi-source protection, input recovery and independent dodge.
const ARENA = preload("res://scenes/drone_combat_test.tscn")
const ROUND = preload("res://scripts/enemies/ballistic_round.gd")
var arena: Node2D
var rate := 60
var checks := 0
var failures: Array[String] = []
var observed: Dictionary = {}

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--hurt-30"):
		rate=30
	elif OS.get_cmdline_user_args().has("--hurt-144"):
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

func fresh(face := "right") -> void:
	arena.session.end_slowmo()
	arena._spawn()
	arena.drone.active=false
	arena.place_player(100.0)
	arena.player.facing=face
	await frames(4)

func hit(direction: Vector2, push := 18.0, weapon := "test") -> int:
	return arena.player.receive_attack({"source":null,"direction":direction,"damage":10,"knockback":push,
		"contact":true,"window_age":0.0,"weapon":weapon})

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	arena=ARENA.instantiate()
	root.add_child(arena)
	current_scene=arena
	await frames(5)
	for face in ["right","left"]:
		for rear in [false,true]:
			await fresh(face)
			var direction: Vector2=arena.player._facing_vector()*(1.0 if rear else -1.0)
			var at: Vector2=arena.player.position
			check(hit(direction)==arena.player.AttackResult.HIT,"A fresh directional attack actually hits: %s rear=%s"%[face,rear])
			check(arena.vitals.hp==90 and arena.player.hurt_from_back==rear,"Front/back is relative to the hero's facing, with one real damage event")
			await seconds(0.07)
			check(arena.player.hurt_pose_shift.x*direction.x>9.0,"The enlarged torso reaction exceeds nine native pixels in the incoming direction")
			check(arena.player.hurt_pose_shift.y>0.0 if rear else arena.player.hurt_pose_shift.y<0.0,"Rear folds downward; front lifts and leans back")
			check(arena.player.facing==face and arena.player.body_shape.shape.size==Vector2(12,26),"The animation preserves facing and the real collision shape")
			await seconds(0.30)
			check(arena.player.state==arena.player.State.FREE and arena.player.hurt_pose_shift==Vector2.ZERO,"The directional pose settles completely after the stun")
			check((arena.player.position.x-at.x)*direction.x>12.0,"Physical heavy knockback accompanies both directional animations")
	await fresh()
	check(hit(Vector2.LEFT)==arena.player.AttackResult.HIT,"Stage the first hit for protection")
	var until: float=arena.player._hit_invulnerable_until
	var velocity: Vector2=arena.player.velocity
	for weapon in ["melee","sniper","drone_cannon","drone_explosion"]:
		check(hit(Vector2.RIGHT,34.0,weapon)==arena.player.AttackResult.EVADE,"Protection rejects a second damage source: "+weapon)
	check(arena.vitals.hp==90 and arena.player.velocity==velocity,"Simultaneous sources cannot add damage or reverse the first knockback")
	check(arena.player._hit_invulnerable_until==until,"Rejected hits never refresh protection or stun")
	await seconds(0.34)
	check(arena.player.state==arena.player.State.FREE and arena.player.hit_invulnerability_left>0.2,"Control returns while protection is still active")
	var x: float=arena.player.position.x
	key(KEY_D,true)
	await seconds(0.12)
	key(KEY_D,false)
	check(arena.player.position.x>x+3.0,"Real movement input works during the remaining protection")
	check(hit(Vector2.LEFT)==arena.player.AttackResult.EVADE and arena.vitals.hp==90,"Recovered movement does not remove the remaining protection")
	await seconds(0.22)
	check(arena.player.hit_invulnerability_left==0.0,"Protection expires after 0.65 seconds of combat time")
	check(hit(Vector2.LEFT)==arena.player.AttackResult.HIT and arena.vitals.hp==80,"Damage becomes possible again when protection expires")
	await fresh()
	var bullet: Node2D=ROUND.new()
	bullet.setup(null,arena.player,arena.player.hurtbox().get_center()-Vector2(20,0),Vector2.RIGHT,ROUND.Weapon.DRONE_CANNON)
	arena.add_child(bullet)
	await seconds(0.12)
	check(arena.vitals.hp==80 and arena.player.hit_invulnerability_left>0.4,"An actual swept cannon projectile grants protection on impact")
	var repeated: Node2D=ROUND.new()
	repeated.setup(null,arena.player,arena.player.hurtbox().get_center()-Vector2(20,0),Vector2.RIGHT,ROUND.Weapon.RIFLE)
	arena.add_child(repeated)
	await seconds(0.16)
	check(arena.vitals.hp==80 and repeated.result==arena.player.AttackResult.EVADE,"A following real projectile is harmless during protection")
	await fresh()
	hit(Vector2.LEFT,0.0,"rifle")
	x=arena.player.position.x
	await seconds(0.35)
	check(absf(arena.player.position.x-x)<0.01,"A zero-push rifle hit animates without inventing physical knockback")
	await fresh()
	hit(Vector2.LEFT)
	await frames(2)
	var before: float=arena.player.hit_invulnerability_left
	var pose: Vector2=arena.player.hurt_pose_shift
	arena.player.freeze(self)
	await seconds(0.30)
	check(arena.player.hit_invulnerability_left==before and arena.player.hurt_pose_shift==pose,"A modal freeze pauses protection and the reaction pose together")
	arena.player.unfreeze(self)
	await seconds(0.08)
	check(arena.player.hit_invulnerability_left<before,"Protection resumes when the modal releases the hero")
	await fresh()
	hit(Vector2.LEFT)
	await seconds(0.35)
	arena.session.start_slowmo(null)
	arena.session.end_slowmo()
	check(not arena.player.invulnerable and hit(Vector2.LEFT)==arena.player.AttackResult.EVADE,"Ending perfect-dodge protection cannot erase hit protection")
	await seconds(0.35)
	check(hit(Vector2.LEFT)==arena.player.AttackResult.HIT,"Independent hit protection still expires normally after slow motion")
	await fresh()
	key(KEY_SHIFT,true)
	await frames(2)
	key(KEY_SHIFT,false)
	await frames(2)
	check(hit(Vector2.LEFT)!=arena.player.AttackResult.HIT and arena.vitals.hp==100,"Real Shift dodge still protects an uninjured player")
	check(arena.player.hit_invulnerability_left==0.0,"Evades do not create or refresh hit protection")
	await fresh()
	arena.place_player(40.0)
	arena.drone.take_damage(9)
	await seconds(0.95)
	check(hit(Vector2.LEFT,0.0)==arena.player.AttackResult.HIT,"A separate hit lands just before a live drone detonation")
	await seconds(0.30)
	check(arena.drone.exploded and arena.vitals.hp==90,"Hit protection blocks the actual drone explosion inside its danger radius")
	await seconds(0.40)
	check(arena.player.sprite.modulate==Color.WHITE and arena.player.hurt_pose_shift==Vector2.ZERO,
		"Normal colour and the neutral pose return after the protection finishes")
	observed={"protection_seconds":arena.player.HIT_INVULNERABILITY_SECONDS,"stun_seconds":arena.player.HURT_SECONDS,"rates":rate}
	var report := {"suite":"player_hurt","passed":failures.is_empty(),"checks":checks,"failures":failures,"physics_rate":rate,"observed":observed}
	DirAccess.make_dir_recursive_absolute("res://evidence/player_hurt/")
	var file := FileAccess.open("res://evidence/player_hurt/test_%d.json"%rate,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
