extends Node
## Attack sounds for the hero. GameSession owns one per scene and binds the player; it keeps running while
## the hit-stop pauses the tree, so an impact sound is never cut by the freeze it causes.

const SOUNDS := {
	"swing_light": preload("res://assets/audio/sfx/swing_light.wav"),
	"swing_heavy": preload("res://assets/audio/sfx/swing_heavy.wav"),
	"hit_light": preload("res://assets/audio/sfx/hit_light.wav"),
	"hit_critical": preload("res://assets/audio/sfx/hit_critical.wav"),
	"hit_heavy": preload("res://assets/audio/sfx/hit_heavy.wav"),
	"charge": preload("res://assets/audio/sfx/charge.wav"),
	"charge_ready": preload("res://assets/audio/sfx/charge_ready.wav"),
}
const VOLUME_DB := {"swing_light": -9.0, "swing_heavy": -5.0, "hit_light": -6.0, "hit_critical": -3.0,
	"hit_heavy": 0.0, "charge": -12.0, "charge_ready": -8.0}
const SWING_PITCH := {&"attack1": 1.0, &"attack2": 1.07, &"attack3": 0.93, &"air_attack2": 1.07, &"air_attack3": 0.93}
const HIT_SOUND := {&"light": "hit_light", &"critical": "hit_critical", &"heavy": "hit_heavy"}

## Every sound started, oldest first, so tests and capture logs can check the timeline.
var played: Array[String] = []
var _voices: Dictionary = {}
var _player: CharacterBody2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sound in SOUNDS:
		var voice := AudioStreamPlayer.new()
		voice.name = sound
		voice.stream = SOUNDS[sound]
		voice.volume_db = VOLUME_DB[sound]
		add_child(voice)
		_voices[sound] = voice


func bind_player(player: CharacterBody2D) -> void:
	if _player == player or not is_instance_valid(player):
		return
	_player = player
	# Only the player's announcements decide the sound; nothing reads its internal state.
	player.move_started.connect(_on_move_started)
	player.impact.connect(func(weight: StringName, _direction: Vector2) -> void: play(HIT_SOUND.get(weight, "hit_light"), randf_range(0.95, 1.05) if weight == &"light" else 1.0))
	player.charge_started.connect(play.bind("charge", 1.0))
	player.charge_ready.connect(play.bind("charge_ready", 1.0))
	player.charge_ended.connect(func(_released: bool) -> void: _voices["charge"].stop())


func play(sound: String, pitch := 1.0) -> void:
	played.append(sound)
	# Headless runs use the dummy audio driver, which never mixes: playbacks would stay registered and
	# show up as leaks at exit, and nothing is audible anyway.
	if DisplayServer.get_name() == "headless":
		return
	var voice: AudioStreamPlayer = _voices[sound]
	voice.pitch_scale = pitch
	voice.play()


func _on_move_started(move: StringName) -> void:
	if move == &"heavy_slash":
		play("swing_heavy")
	else:
		play("swing_light", SWING_PITCH.get(move, 1.0))
