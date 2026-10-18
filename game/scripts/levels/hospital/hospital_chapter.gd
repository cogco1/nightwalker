extends Node
## Chapter mode of the underground hospital (only while the story runs). The step picks the projection: the
## day job is top-down stealth, the night is side view. By day the micro-light surveillance is the interior
## lights themselves: the hero's feet are read against interior_lighting.light_level() every physics frame,
## standing in light fills the exposure meter, a full meter locks on and sends the hero back to where they
## entered this floor. Coburn waits at his office desk and can only be taken from behind, in the dark.
## The exit panel leaves for home by day. A night that names a fight (night_fight.gd) has no exit: it ends in the
## execution, straight into the held-breath interlude.

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const STORY_OVERLAY = preload("res://scripts/ui/story_overlay.gd")
const EXPOSURE_HUD = preload("res://scripts/ui/exposure_hud.gd")
const STORY_TARGET = preload("res://scripts/levels/hospital/story_target.gd")
const CHAPTER_HUD = preload("res://scripts/ui/chapter_hud.gd")
const NIGHT_FIGHT = preload("res://scripts/levels/hospital/night_fight.gd")
const CONTROLS = preload("res://scripts/core/controls.gd")
const GAME_SESSION = preload("res://scripts/core/game_session.gd")
const DAY_STAFF = preload("res://scripts/levels/hospital/hospital_day_staff.gd")
## Light level at the feet that counts as lit: inside about 0.73 of a ceiling lamp's radius, half a screen's.
const LIT_THRESHOLD := 0.06
## Exposure per second in light / out of it; 1.0 locks on.
const EXPOSURE_RISE := 0.8
const EXPOSURE_FALL := 0.3
const KILL_RADIUS := 24.0

var hospital: Node2D
var story: Node
var overlay: CanvasLayer
## Exposure plate and scan tag (shared with the night street) and the chapter HUD.
var hud: Node
var chapter_hud: Node
var target: Node2D
var day_staff: Node2D
## The night's fight when the step names one (chapter1.json nights.*).
var fight: Node
var exposure := 0.0
var in_light := false
var in_sight := false
var light_level := 0.0
var locks := 0
var checkpoint := Vector2.ZERO
var busy := false


func _init(host: Node2D) -> void:
	hospital = host
	name = "HospitalChapter"


## Projection, floor and room the step opens on.
func start_context() -> Dictionary:
	story = STORY_STATE.ensure(hospital.get_tree())
	var settings: Dictionary = story.chapter.get("hospital", {})
	if String(story.step_data().get("view", "top_down")) == "side_view":
		return {"view": 1, "floor": int(settings.get("night_floor", 1)), "room": ""}
	var start := {"view": 0, "floor": 1, "room": String(settings.get("arrival_room", "entry"))}
	var point: Array = settings.get("arrival_position", [])
	if point.size() == 2:
		start["position"] = Vector2(point[0], point[1])
	return start


func _ready() -> void:
	process_physics_priority = 110
	overlay = STORY_OVERLAY.new()
	overlay.name = "StoryOverlay"
	add_child(overlay)
	var canvas: CanvasLayer = hospital.get_node("EnvironmentUI")
	chapter_hud = CHAPTER_HUD.new()
	chapter_hud.name = "ChapterHud"
	add_child(chapter_hud)
	chapter_hud.build(canvas)
	hud = EXPOSURE_HUD.new()
	hud.name = "ExposureHud"
	add_child(hud)
	hud.build(canvas)
	hud.marked_text = "已锁定"
	story.step_changed.connect(func(_step: String) -> void: refresh())
	story.balance_changed.connect(func(_amount: int) -> void: chapter_hud.set_balance(story.balance))
	var fight_id := String(story.step_data().get("fight", ""))
	if not fight_id.is_empty() and hospital.view_mode == 1:
		var night: Dictionary = story.chapter.get("nights", {}).get(fight_id, {}).duplicate(true)
		night["id"] = fight_id
		fight = NIGHT_FIGHT.new(self, night)
		add_child(fight)
	hospital.refresh_ui()
	overlay.shade.color.a = 1.0
	_arrive.call_deferred()


## A single introduction on the actual hospital arrival; stairs and exposure resets never replay it.
func _arrive() -> void:
	var opening: Dictionary = story.chapter.get("hospital", {}).get("opening", {})
	var show_opening: bool = stealth() and story.step == "d1_hospital" and not opening.is_empty() \
		and not story.has_flag("sequence:hospital_opening")
	var session := GAME_SESSION.of(self)
	if show_opening:
		story.set_flag("sequence:hospital_opening")
		busy = true
		hospital.player.freeze(self)
		if session != null:
			session.push_modal(self)
	await overlay.fade_from_black(0.8 if story.is_night() else 0.5)
	if show_opening:
		var dialogue: Panel = hospital.interactions.dialogue
		dialogue.open(opening.get("lines", []), "地下医院", hospital.player, opening.get("speakers", []))
		await dialogue.closed
		hospital.player.unfreeze(self)
		if session != null:
			session.pop_modal(self)
		busy = false
		chapter_hud.toast(String(opening.get("tip", "")), CHAPTER_HUD.STYLE.CYAN, 8.0)
	elif stealth():
		chapter_hud.toast(String(story.chapter.get("hospital", {}).get("tip", "")))


func stealth() -> bool:
	return bool(story.step_data().get("stealth", false)) and hospital.view_mode == 0


func refresh() -> void:
	chapter_hud.set_status("地下医院 %dF" % hospital.floor_id, story.clock_text(), story.objective())
	chapter_hud.set_balance(story.balance)
	hud.set_visible(stealth())
	if not stealth():
		exposure = 0.0
		in_light = false
		in_sight = false


## The hospital rebuilt its world (arrival, stairs): this is the floor's checkpoint; Coburn is on floor 2.
func on_view_activated() -> void:
	checkpoint = hospital.player.position
	exposure = 0.0
	in_sight = false
	day_staff = DAY_STAFF.refresh(hospital, story)
	target = null
	var settings: Dictionary = story.chapter.get("hospital", {}).get("coburn", {})
	if hospital.view_mode == 0 and hospital.floor_id == int(settings.get("floor", 2)) and not story.chapter.is_empty():
		var feet: Array = settings.get("position", [492, 82])
		target = STORY_TARGET.new()
		target.name = "Coburn"
		target.setup(hospital.world, Vector2(feet[0], feet[1]))
		if story.has_flag("coburn_dead"):
			target.kill(true)
	if is_instance_valid(fight):
		fight.on_view_activated()
	if is_inside_tree():
		refresh()


func _physics_process(delta: float) -> void:
	var player: CharacterBody2D = hospital.player
	if not is_instance_valid(player) or not stealth():
		return
	light_level = hospital.lighting.light_level(player.global_position)
	in_light = light_level >= LIT_THRESHOLD
	in_sight = is_instance_valid(day_staff) and day_staff.visible_by(player)
	if _input_blocked():
		return
	exposure = clampf(exposure + (EXPOSURE_RISE if in_light or in_sight else -EXPOSURE_FALL) * delta, 0.0, 1.0)
	if exposure >= 1.0:
		lock_on(String(story.chapter.get("hospital", {}).get("doctor_locked", "医生发现了你")) if in_sight else "")


func _process(delta: float) -> void:
	var execution := _execution_prompt()
	chapter_hud.set_prompt(execution if not execution.is_empty() else _prompt_title(),
		CONTROLS.execute_text() if not execution.is_empty() else "")
	if not stealth() or not is_instance_valid(hospital.player):
		return
	hud.meter_label.text = "目击" if in_sight else "暴露"
	var top_left: Vector2 = hospital.camera.get_screen_center_position() - Vector2(160, 90)
	hud.update(delta, exposure, busy, (in_light or in_sight) and not busy, hospital.player.global_position - top_left)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and CONTROLS.is_execute(event):
		request_execution()
		get_viewport().set_input_as_handled()


## Full exposure: the lock flashes and the hero is put back where this floor was entered.
func lock_on(reason := "") -> void:
	busy = true
	locks += 1
	var player: CharacterBody2D = hospital.player
	player.freeze(self)
	await overlay.lock_flash(reason if not reason.is_empty() else String(story.chapter.get("hospital", {}).get("locked", "")))
	if is_instance_valid(player):
		player.position = checkpoint
		player.velocity = Vector2.ZERO
		player.show_idle()
		player.unfreeze(self)
		hospital.follow_player()
	exposure = 0.0
	in_sight = false
	busy = false


## What E would do here, for the key cap: a locked door first, then the nearest interaction.
func _prompt_title() -> String:
	var interactions: Node = hospital.interactions
	var security: Node = hospital.security
	if _input_blocked():
		return ""
	var door: String = security.nearest_door_title() if is_instance_valid(security) else ""
	if not door.is_empty():
		return door
	var item: Dictionary = interactions._find_interaction(interactions.nearest_id)
	if String(item.get("kind", "")) == "story":
		return "" # Coburn has his own F prompt, never an E execution.
	if String(item.get("kind", "")) == "stairs" and not stairs_open():
		return ""
	return String(item.get("title", ""))


## Whether the stairs take the hero now (always, except on a fight night before floor 1 is clear).
func stairs_open() -> bool:
	return not is_instance_valid(fight) or fight.stairs_open()


## The hospital's interactions inside the chapter: Coburn joins them while he lives; a fight night has nothing to read
## ("全程无字幕") and keeps only the stairs.
func interactions(items: Array) -> Array:
	if is_instance_valid(fight):
		return items.filter(func(item: Variant) -> bool: return item is Dictionary and String(item.get("kind", "")) == "stairs")
	return items + story_targets()


## Extra interaction points for hospital_interactions: Coburn while he is alive.
func story_targets() -> Array:
	if not is_instance_valid(target) or target.dead or hospital.view_mode != 0:
		return []
	var settings: Dictionary = story.chapter.get("hospital", {}).get("coburn", {})
	return [{"id": "coburn", "title": String(settings.get("title", "科伯恩")), "kind": "story",
		"floor_id": int(settings.get("floor", 2)), "radius": KILL_RADIUS,
		"anchors": {"top_down": [target.position.x, target.position.y]}}]


## Ordinary E interactions never execute a story target. Kept for the shared interaction dispatcher.
func story_interact(_id: String) -> Array:
	return []


## Modals and impact pauses must never queue an execution for when normal play resumes.
func _input_blocked() -> bool:
	var player: CharacterBody2D = hospital.player
	if busy or hospital.stairs_busy or not is_instance_valid(player) or player.is_frozen() or get_tree().paused:
		return true
	if is_instance_valid(overlay) and (overlay.busy or overlay.shade.color.a > 0.01):
		return true
	if not is_instance_valid(hospital.interactions) or hospital.interactions.dialogue_active:
		return true
	if is_instance_valid(hospital.security) and hospital.security.keypad_active:
		return true
	if is_instance_valid(fight) and fight.busy:
		return true
	var session := GAME_SESSION.of(self)
	return session != null and (session.settings_open or session.hit_stop_active or session.has_modal())


func _near_execution_target() -> bool:
	var settings: Dictionary = story.chapter.get("hospital", {}).get("coburn", {})
	return story.chapter_active and story.step == "d1_hospital" and stealth() \
		and hospital.floor_id == int(settings.get("floor", 2)) \
		and is_instance_valid(target) and not target.dead and target.get_parent() == hospital.world \
		and not story.has_flag("coburn_dead") \
		and hospital.player.global_position.distance_to(target.global_position) <= KILL_RADIUS


## Read the light at the key press, not the previous physics frame (a breaker may have just changed it).
func _execution_block_reason() -> String:
	var player: CharacterBody2D = hospital.player
	if hospital.lighting.light_level(player.global_position) >= LIT_THRESHOLD:
		return "先避开光线"
	if is_instance_valid(day_staff) and day_staff.visible_by(player):
		return "先避开医生视线"
	if not target.is_behind(player.global_position):
		return "需绕到背后"
	var ray := PhysicsRayQueryParameters2D.create(player.global_position, target.global_position, 1)
	# The target's own body is the destination, not cover. Other solid furniture / closed doors still block F.
	var excluded: Array[RID] = [player.get_rid()]
	var body := target.get_node_or_null("StoryTargetBody") as CollisionObject2D
	if body != null:
		excluded.append(body.get_rid())
	ray.exclude = excluded
	if not hospital.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
		return "路径被挡住"
	if player.is_attacking or player.is_charging or player.is_dodging or player.state == player.State.HURT:
		return "先收起动作"
	return ""


func _execution_prompt() -> String:
	if _input_blocked() or not _near_execution_target():
		return ""
	var reason := _execution_block_reason()
	return "处决 · 科伯恩" if reason.is_empty() else reason


## Dedicated F request: the same gates drive both the prompt and the action; holding F never repeats it.
func request_execution() -> bool:
	if _input_blocked() or not _near_execution_target() or not _execution_block_reason().is_empty():
		return false
	_execute()
	return true


## Reuse the existing native attack drawings and kill feedback, without advancing the ordinary combo state.
func _execute() -> void:
	busy = true
	var player: CharacterBody2D = hospital.player
	var session := GAME_SESSION.of(self)
	if session != null:
		session.push_modal(self)
	player.freeze(self)
	player._update_facing(target.global_position - player.global_position)
	var animation := "attack1_" + String(player.facing)
	player._set_manual_frame(animation, 2)
	chapter_hud.set_prompt("")
	if session != null:
		session.combat_feedback.play("swing_light")
	await get_tree().create_timer(0.07, false).timeout
	player._set_manual_frame(animation, 6)
	target.kill()
	overlay.strike_flash()
	var direction: Vector2 = player._facing_vector()
	player.fx.impact(target.global_position + Vector2(0, -12), &"light", direction, player.global_position, true)
	story.set_flag("coburn_dead")
	story.set_step("d1_target_down")
	player.impact.emit(&"kill", direction)
	if session != null and session.hit_stop_active:
		await session.hit_stop_finished
	player._set_manual_frame(animation, 11)
	await get_tree().create_timer(0.13, false).timeout
	player.show_idle()
	player.unfreeze(self)
	if session != null:
		session.pop_modal(self)
	busy = false


## Reading text the chapter replaces for an interaction (the treatment drawer carries the door code).
func line_override(id: String) -> Variant:
	return story.chapter.get("hospital", {}).get("line_overrides", {}).get(id)


## The exit panel: by day it waits for the job, at night it ends the night. Always handled in the chapter.
func exit_requested() -> Array:
	var next := String(story.step_data().get("exit", ""))
	if next.is_empty():
		return story.chapter.get("hospital", {}).get("exit_not_yet", [])
	_leave(next)
	return []


func _leave(next: String) -> void:
	busy = true
	hospital.player.freeze(self)
	await overlay.fade_to_black(0.5)
	hospital.get_tree().root.get_node("SceneRoutes").call("travel", next)
