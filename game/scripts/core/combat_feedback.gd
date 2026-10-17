extends Node
## Attack sounds for the hero. GameSession owns one per scene and binds the player; it keeps running while
## the hit-stop pauses the tree, so an impact sound is never cut by the freeze it causes.

const MOVESET = preload("res://scripts/player/moves_long_blade.gd")
const SOUNDS := {
	"swing_light": preload("res://assets/audio/sfx/impact_v2/swing_light.wav"),
	"swing_heavy": preload("res://assets/audio/sfx/impact_v2/swing_heavy.wav"),
	"hit_light": preload("res://assets/audio/sfx/impact_v2/hit_light.wav"),
	"hit_critical": preload("res://assets/audio/sfx/impact_v2/hit_critical.wav"),
	"hit_heavy": preload("res://assets/audio/sfx/impact_v2/hit_heavy.wav"),
	"hit_kill": preload("res://assets/audio/sfx/impact_v2/hit_kill.wav"),
	"charge": preload("res://assets/audio/sfx/charge.wav"),
	"charge_ready": preload("res://assets/audio/sfx/charge_ready.wav"),
}
const VOLUME_DB := {"swing_light": -11.0, "swing_heavy": -8.0, "hit_light": -9.0, "hit_critical": -7.0,
	"hit_heavy": -6.0, "hit_kill": -6.0, "charge": -12.0, "charge_ready": -8.0}
const SWING_AT_RELEASE := [&"attack1", &"attack2", &"attack3", &"heavy_slash", &"crouch_stab", &"rush_cleave"]
const SWING_PITCH := {&"attack1": 1.0, &"attack2": 1.07, &"attack3": 0.93, &"air_attack2": 1.07, &"air_attack3": 0.93}
const HIT_SOUND := {&"light": "hit_light", &"critical": "hit_critical", &"heavy": "hit_heavy", &"kill": "hit_kill", &"tick": "hit_light"}

## Every sound started, oldest first, so tests and capture logs can check the timeline.
var played: Array[String] = []
var _voices: Dictionary = {}
var _player: CharacterBody2D
var _pending_impact: StringName = &""
var _sound_rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sound_rng.randomize()
	for sound in SOUNDS:
		var voice := AudioStreamPlayer.new()
		voice.name = sound
		voice.stream = SOUNDS[sound]
		voice.max_polyphony = 3
		voice.volume_db = VOLUME_DB[sound]
		add_child(voice)
		_voices[sound] = voice


func bind_player(player: CharacterBody2D) -> void:
	if _player == player or not is_instance_valid(player):
		return
	_player = player
	# Only the player's announcements decide the sound; nothing reads its internal state.
	player.move_started.connect(func(id: StringName) -> void:
		if id not in SWING_AT_RELEASE: _on_move_started(id)
	)
	player.swing_released.connect(func(id: StringName) -> void:
		if id in SWING_AT_RELEASE: _on_move_started(id)
	)
	player.impact.connect(_queue_contact_sound)
	player.charge_started.connect(play.bind("charge", 1.0))
	player.charge_ready.connect(play.bind("charge_ready", 1.0))
	player.charge_ended.connect(func(_released: bool) -> void: _voices["charge"].stop())
	# Taking a hit: a low heavy impact; a perfect dodge: a high chime.
	player.attack_received.connect(func(result: int, _attack: Dictionary) -> void:
		if result == 0:
			play("hit_heavy", 0.7)
		elif result == 2:
			play("charge_ready", 1.4)
	)


## Coalesce a multi-target contact into one strongest cue; a same-tick kill replaces the ordinary hit.
func _queue_contact_sound(weight: StringName, _direction: Vector2) -> void:
	var rank := {&"tick":0,&"light":1,&"critical":2,&"heavy":3,&"kill":4}
	if _pending_impact == &"":
		_pending_impact = weight
		call_deferred("_flush_contact_sound")
	elif int(rank.get(weight,1)) > int(rank.get(_pending_impact,1)):
		_pending_impact = weight


func _flush_contact_sound() -> void:
	if _pending_impact == &"": return
	var weight := _pending_impact
	_pending_impact = &""
	play(HIT_SOUND.get(weight,"hit_light"), _sound_rng.randf_range(0.96,1.04))


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
	var row: Dictionary = MOVESET.MOVES.get(move, {})
	if row.get("swing", &"light") == &"none":
		return
	if row.get("swing", &"light") == &"heavy":
		play("swing_heavy", float(row.get("pitch", 1.0)))
	else:
		play("swing_light", SWING_PITCH.get(move, float(row.get("pitch", 1.0))))
