extends RefCounted
## The long-blade move set as data: every attack and special the hero can start, and the combo graph
## between them. player.gd reads these fields instead of per-stage constants and special_kind string tests;
## new moves are added here (tests/test_moveset.gd checks every entry against the frames and blade paths).
##
## Fields (anim, fps and active are required):
##   stage        combo stage reported through combo_changed / combo_stage (1-3)
##   anim         animation prefix; "_<facing>" is appended
##   air_anim     prefix used instead when the move starts airborne
##   fps          playback rate
##   start_frame  first frame shown
##   active       Vector2i(first, last) frames that hit; last = -1 keeps hitting until the move ends
##   side_first   first active frame in side view when it differs from active.x
##   box          blade box {length, width, reach, height} in front of the hero, or {rect, forward}
##   lunge        {px, from}: forward advance eased over frames from..active.y, on the ground only
##   crit         &"none" | &"roll" (CRIT_CHANCE) | &"always"; a critical hit deals CRIT_MULT damage
##   stop         impact weight of a normal hit; crit_stop of a critical hit (default &"critical")
##   launch       the hit launches the target
##   juggle       an airborne hit holds an airborne target in the air
##   steer        horizontal input steers the hero while the move plays airborne
##   chain        a ground light swing: holding the button after it coils into the charge
##   crouched     a crouching attack (lower origin, no lunge, no chain)
##   recovery     seconds of return pose; default 2 frames on the ground / 1 in the air at fps
##   air          {hold, fall} hang time when started airborne; end_hold after finishing airborne
##   special      special_kind name the move reports (tests, HUD, hit_resolved kind)
##   pierce       dash: travels DASH_DISTANCE through targets on its first active frame
##   dive         dive slash: falls at DIVE_SPEED, holds its last air frame, lands into a short recovery
##   launcher     rising slash: jumps and spawns rising airflow
##   ghosts       frames that leave an afterimage

const CRIT_CHANCE := 0.30
const CRIT_MULT := 3
const SIDE_EXTRA_REACH := 12.0
const ORIGIN_HEIGHT := 17.0
const BLADE := {"length": 34.0, "width": 20.0, "reach": 21.0, "height": ORIGIN_HEIGHT}
const LIGHT_AIR := {"hold": 0.55, "fall": 6.0}

const MOVES := {
	&"attack1": {"stage": 1, "anim": "attack1", "air_anim": "air_attack1", "fps": 36.0, "active": Vector2i(6, 9),
		# The long blade is still behind the shoulder in side-view frame 6; frame 7 crosses forward.
		"side_first": 7, "box": BLADE, "lunge": {"px": 5.5, "from": 6}, "crit": &"none", "stop": &"light",
		"juggle": true, "steer": true, "chain": true, "air": LIGHT_AIR},
	&"attack2": {"stage": 2, "anim": "attack2", "air_anim": "air_attack2", "fps": 40.0, "active": Vector2i(6, 9),
		"box": BLADE, "lunge": {"px": 5.5, "from": 6}, "crit": &"none", "stop": &"light",
		"juggle": true, "steer": true, "chain": true, "air": LIGHT_AIR},
	&"attack3": {"stage": 3, "anim": "attack3", "air_anim": "air_attack3", "fps": 42.0, "active": Vector2i(6, 9),
		"box": BLADE, "lunge": {"px": 6.8, "from": 6}, "crit": &"roll", "stop": &"light",
		"juggle": true, "steer": true, "chain": true, "air": LIGHT_AIR},
	&"crouch_stab": {"stage": 1, "anim": "crouch_stab", "fps": 40.0, "active": Vector2i(6, 9),
		"box": {"length": 27.0, "width": 16.0, "reach": 17.0, "height": 9.0}, "crit": &"none", "stop": &"light",
		"juggle": true, "crouched": true},
	&"rising_slash": {"stage": 1, "anim": "rising_slash", "fps": 40.0, "active": Vector2i(3, 9),
		"box": {"rect": Rect2(-18, -36, 36, 48), "forward": 19.0}, "crit": &"none", "stop": &"light",
		"launch": true, "special": "rising_slash", "launcher": true},
	&"dive_slash": {"stage": 1, "anim": "dive_slash", "fps": 40.0, "active": Vector2i(0, -1),
		"box": {"rect": Rect2(-13, -24, 26, 42), "forward": 0.0}, "crit": &"none", "stop": &"light",
		"special": "dive_slash", "dive": true},
	&"dash_stab": {"stage": 1, "anim": "dash_stab", "air_anim": "air_dash_stab", "fps": 40.0, "active": Vector2i(6, 9),
		"crit": &"none", "stop": &"light", "juggle": true, "special": "dash_stab", "pierce": true,
		"air": {"hold": 0.55, "fall": 6.0, "end_hold": 0.30}},
	# The charged slash: released from the charge pose, it plays attack3 from frame 4.
	&"heavy_slash": {"stage": 3, "anim": "attack3", "fps": 46.0, "start_frame": 4, "active": Vector2i(6, 9),
		"box": {"length": 44.0, "width": 28.0, "reach": 21.0, "height": ORIGIN_HEIGHT},
		"lunge": {"px": 32.0, "from": 4}, "crit": &"always", "crit_stop": &"heavy", "recovery": 0.18,
		"special": "heavy_slash", "ghosts": [5, 7]},
}

## Combo graph: current move (&"" = idle) -> input -> next move.
const STRINGS := {
	&"": {&"light": &"attack1"},
	&"attack1": {&"light": &"attack2"},
	&"attack2": {&"light": &"attack3"},
}


static func next_move(current: StringName, input: StringName) -> StringName:
	return STRINGS.get(current, {}).get(input, &"")
