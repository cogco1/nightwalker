extends Node
## Chapter mode of the underground hospital (only while the story runs). The step picks the projection: the
## day job is top-down stealth, the night is side view. By day the micro-light surveillance is the interior
## lights themselves: the hero's feet are read against interior_lighting.light_level() every physics frame,
## standing in light fills the exposure meter, a full meter locks on and sends the hero back to where they
## entered this floor. Coburn waits at his office desk and can only be taken from behind, in the dark.
## The exit panel leaves for home by day and for the held-breath interlude at night.

const STORY_STATE = preload("res://scripts/core/story_state.gd")
const STORY_OVERLAY = preload("res://scripts/ui/story_overlay.gd")
const EXPOSURE_HUD = preload("res://scripts/ui/exposure_hud.gd")
const STORY_TARGET = preload("res://scripts/levels/hospital/story_target.gd")
const CHAPTER_HUD = preload("res://scripts/ui/chapter_hud.gd")
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
var exposure := 0.0
var in_light := false
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
	return {"view": 0, "floor": 1, "room": String(settings.get("arrival_room", "entry"))}


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
	if stealth():
		chapter_hud.toast(String(story.chapter.get("hospital", {}).get("tip", "")))
	hospital.refresh_ui()
	overlay.shade.color.a = 1.0
	overlay.fade_from_black(0.8 if story.is_night() else 0.5)


func stealth() -> bool:
	return bool(story.step_data().get("stealth", false)) and hospital.view_mode == 0


func refresh() -> void:
	chapter_hud.set_status("地下医院 %dF" % hospital.floor_id, story.clock_text(), story.objective())
	hud.set_visible(stealth())
	if not stealth():
		exposure = 0.0
		in_light = false


## The hospital rebuilt its world (arrival, stairs): this is the floor's checkpoint; Coburn sits on floor 2.
func on_view_activated() -> void:
	checkpoint = hospital.player.position
	exposure = 0.0
	target = null
	var settings: Dictionary = story.chapter.get("hospital", {}).get("coburn", {})
	if hospital.view_mode == 0 and hospital.floor_id == int(settings.get("floor", 2)) and not story.chapter.is_empty():
		var feet: Array = settings.get("position", [492, 82])
		target = STORY_TARGET.new()
		target.name = "Coburn"
		target.setup(hospital.world, Vector2(feet[0], feet[1]))
		if story.has_flag("coburn_dead"):
			target.kill()
	if is_inside_tree():
		refresh()


func _physics_process(delta: float) -> void:
	var player: CharacterBody2D = hospital.player
	if not is_instance_valid(player) or not stealth():
		return
	light_level = hospital.lighting.light_level(player.global_position)
	in_light = light_level >= LIT_THRESHOLD
	if busy or player.is_frozen():
		return
	exposure = clampf(exposure + (EXPOSURE_RISE if in_light else -EXPOSURE_FALL) * delta, 0.0, 1.0)
	if exposure >= 1.0:
		lock_on()


func _process(delta: float) -> void:
	chapter_hud.set_prompt(_prompt_title())
	if not stealth() or not is_instance_valid(hospital.player):
		return
	var top_left: Vector2 = hospital.camera.get_screen_center_position() - Vector2(160, 90)
	hud.update(delta, exposure, busy, in_light and not busy, hospital.player.global_position - top_left)


## Full exposure: the lock flashes and the hero is put back where this floor was entered.
func lock_on() -> void:
	busy = true
	locks += 1
	var player: CharacterBody2D = hospital.player
	player.freeze(self)
	await overlay.lock_flash(String(story.chapter.get("hospital", {}).get("locked", "")))
	if is_instance_valid(player):
		player.position = checkpoint
		player.velocity = Vector2.ZERO
		player.show_idle()
		player.unfreeze(self)
		hospital.follow_player()
	exposure = 0.0
	busy = false


## What E would do here, for the key cap: a locked door first, then the nearest interaction.
func _prompt_title() -> String:
	var interactions: Node = hospital.interactions
	var security: Node = hospital.security
	if busy or hospital.stairs_busy or not is_instance_valid(interactions) or interactions.dialogue_active:
		return ""
	if is_instance_valid(security) and security.keypad_active:
		return ""
	var door: String = security.nearest_door_title() if is_instance_valid(security) else ""
	if not door.is_empty():
		return door
	var item: Dictionary = interactions._find_interaction(interactions.nearest_id)
	return String(item.get("title", ""))


## Extra interaction points for hospital_interactions: Coburn while he is alive.
func story_targets() -> Array:
	if not is_instance_valid(target) or target.dead or hospital.view_mode != 0:
		return []
	var settings: Dictionary = story.chapter.get("hospital", {}).get("coburn", {})
	return [{"id": "coburn", "title": String(settings.get("title", "科伯恩")), "kind": "story",
		"floor_id": int(settings.get("floor", 2)), "radius": KILL_RADIUS,
		"anchors": {"top_down": [target.position.x, target.position.y]}}]


## E on Coburn: only from behind and out of the light.
func story_interact(_id: String) -> Array:
	var settings: Dictionary = story.chapter.get("hospital", {})
	var player: CharacterBody2D = hospital.player
	if in_light:
		return settings.get("kill_too_bright", [])
	if not target.is_behind(player.global_position):
		return settings.get("kill_from_front", [])
	target.kill()
	overlay.strike_flash()
	story.set_flag("coburn_dead")
	story.set_step("d1_target_down")
	return []


## Reading text the chapter replaces for an interaction (the duty roster carries the door code).
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
