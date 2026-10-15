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
const STAGE_PITCH := [1.0, 1.07, 0.93]

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
	player.attack_started.connect(_on_attack_started)
	player.hit_resolved.connect(_on_hit_resolved)
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


func _on_attack_started() -> void:
	if _player.special_kind == "heavy_slash":
		play("swing_heavy")
	else:
		play("swing_light", STAGE_PITCH[clampi(_player.combo_stage - 1, 0, 2)])


func _on_hit_resolved(_target: Node, _damage: int, critical: bool, kind: String) -> void:
	if kind == "heavy_slash":
		play("hit_heavy")
	elif critical:
		play("hit_critical")
	else:
		play("hit_light", randf_range(0.95, 1.05))
