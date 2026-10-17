extends CanvasLayer
## Full-screen story moments on the 320x180 canvas: the chapter title card, fades to and from black, the 22:00
## rampage and the surveillance lock, plus the story sounds. Every moment is a coroutine the caller awaits;
## freezing the player and holding a GameSession modal stays with the caller (home_chapter, hospital_chapter).

const PIXEL_UI = preload("res://scripts/ui/pixel_ui.gd")
const STYLE = preload("res://scripts/ui/hud_style.gd")
const SOUNDS := {
	"knock": preload("res://assets/audio/story/knock.wav"),
	"heartbeat": preload("res://assets/audio/story/heartbeat.wav"),
	"breath": preload("res://assets/audio/story/breath.wav"),
	"lock": preload("res://assets/audio/story/lock.wav"),
}
const RAMPAGE := Color(1.0, 0.16, 0.38)
const LOCKED := Color(1.0, 0.24, 0.43)

var busy := false
## Sound ids in play order and the story moments shown, for tests and recordings.
var played: Array[String] = []
var shown: Array[String] = []
var shade: ColorRect
var tint: ColorRect
var big_text: Label
var small_text: Label
## The lock notice on an ink plate with a red rule.
var notice: Panel
var notice_label: Label
var _voice: AudioStreamPlayer


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	shade = _rect(Color(0.0, 0.0, 0.0, 0.0))
	tint = _rect(Color(RAMPAGE, 0.0))
	big_text = PIXEL_UI.label(self, Vector2.ZERO, Vector2.ZERO, "", PIXEL_UI.FONT_SIZE, true)
	big_text.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	big_text.oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_DISABLED
	big_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_text.modulate.a = 0.0
	small_text = PIXEL_UI.label(self, Vector2(0, 112), Vector2(320, 16), "", PIXEL_UI.FONT_SIZE, true)
	small_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	small_text.modulate.a = 0.0
	notice = STYLE.panel(self, "LockNotice", STYLE.plate(STYLE.INK, STYLE.RED))
	notice_label = PIXEL_UI.label(notice, Vector2(8, 2), Vector2.ZERO, "", PIXEL_UI.FONT_SIZE, true)
	notice_label.modulate = STYLE.RED
	notice.hide()
	_voice = AudioStreamPlayer.new()
	add_child(_voice)


func _rect(colour: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = Vector2(320, 180)
	rect.color = colour
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


func play(sound: String) -> void:
	played.append(sound)
	if DisplayServer.get_name() == "headless" or not SOUNDS.has(sound):
		return
	_voice.stream = SOUNDS[sound]
	_voice.play()


## Big pixel text centred on screen, magnified on the native grid (the title card fills about a quarter).
func _set_big(text: String, magnify: int, colour := Color("dfe8ec")) -> void:
	big_text.text = text
	big_text.size = Vector2(text.length() * PIXEL_UI.FONT_SIZE + 4, 16)
	big_text.scale = Vector2.ONE * magnify
	big_text.position = (Vector2(320, 180) - big_text.size * magnify).round() * 0.5
	big_text.self_modulate = colour


func _fade(node: CanvasItem, alpha: float, seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "modulate:a" if node != shade and node != tint else "color:a", alpha, seconds)
	await tween.finished


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


## "第一章": black screen, the title fades in at four times the pixel size, holds, fades out with the black.
func title_card(text: String, hold := 1.6) -> void:
	busy = true
	shown.append("title:" + text)
	shade.color.a = 1.0
	_set_big(text, 4)
	await _fade(big_text, 1.0, 0.5)
	await _wait(hold)
	await _fade(big_text, 0.0, 0.5)
	await _fade(shade, 0.0, 0.5)
	busy = false


func fade_to_black(seconds := 0.5) -> void:
	await _fade(shade, 1.0, seconds)


func fade_from_black(seconds := 0.5) -> void:
	await _fade(shade, 0.0, seconds)


## 22:00: the screen drops to black, the clock flickers red to the heartbeat, then stays black for travel.
func rampage(clock: String) -> void:
	busy = true
	shown.append("rampage:" + clock)
	play("heartbeat")
	await _fade(shade, 1.0, 0.25)
	_set_big(clock, 3, RAMPAGE)
	small_text.text = "暴走"
	small_text.self_modulate = RAMPAGE
	for flash in range(4):
		big_text.modulate.a = 1.0
		small_text.modulate.a = 1.0 if flash >= 1 else 0.0
		tint.color = Color(RAMPAGE, 0.32 - flash * 0.06)
		big_text.position.x += 2.0 if flash % 2 == 0 else -2.0
		await _wait(0.12)
		tint.color.a = 0.0
		big_text.modulate.a = 0.55
		await _wait(0.26)
	big_text.modulate.a = 0.0
	small_text.modulate.a = 0.0
	busy = false


## Full exposure: a red flash with the lock notice; the caller moves the player back while it shows.
func lock_flash(text: String) -> void:
	busy = true
	shown.append("lock:" + text)
	play("lock")
	notice_label.text = text
	notice.size = Vector2(STYLE.width(text, PIXEL_UI.FONT_SIZE) + 16, 17)
	notice.position = ((Vector2(320, 180) - notice.size) * 0.5).round()
	notice.show()
	tint.color = Color(LOCKED, 0.42)
	await _fade(tint, 0.0, 0.6)
	await _wait(0.4)
	notice.hide()
	busy = false


## A kill: one dark-red frame that fades in a third of a second (no waiting).
func strike_flash() -> void:
	shown.append("strike")
	tint.color = Color(0.45, 0.02, 0.06, 0.5)
	_fade(tint, 0.0, 0.3)


## The hero goes down at night: a red wash, then black. The caller restarts the floor behind the black and fades in.
func death() -> void:
	busy = true
	shown.append("death")
	play("heartbeat")
	tint.color = Color(LOCKED, 0.5)
	_fade(tint, 0.0, 0.7)
	await _wait(0.35)
	await _fade(shade, 1.0, 0.45)
	tint.color.a = 0.0
	busy = false


## The execution, standing in for the animation to come: after the hit's freeze, a white frame, then black that
## stays for the travel on.
func execution() -> void:
	busy = true
	shown.append("execution")
	tint.color = Color(1.0, 1.0, 1.0, 1.0)
	await _wait(0.1)
	tint.color = Color(1.0, 1.0, 1.0, 0.0)
	shade.color.a = 1.0
	await _wait(1.2)
	busy = false
