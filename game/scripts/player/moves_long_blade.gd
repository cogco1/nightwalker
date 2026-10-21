extends RefCounted
## The long-blade move set as data: every attack and special the hero can start, and the combo graph
## between them. player.gd reads these fields instead of per-stage constants and special_kind string tests;
## new moves are added here (tests/test_moveset.gd checks every entry against the frames and blade paths).
##
## Fields (anim and fps are required):
##   stage        combo stage reported through combo_changed / combo_stage (1-5)
##   followup_seconds  extra continuation window after recovery; retains this move's combo identity
##   anim         animation prefix; "_<facing>" is appended
##   charge_link  side-view continuation with authored charged recovery poses at its beginning
##   side_anim    dedicated side-view prefix (anim remains the top-down fallback)
##   air_anim     prefix used instead when the move starts airborne
##   fps          playback rate
##   start_frame  first frame shown
##   active       Vector2i(first, last) frames that hit; last = -1 keeps hitting until the move ends; no active = no hit
##   side_first   first active frame in side view when it differs from active.x
##   box          blade box {length, width, reach, height} in front of the hero, or {rect, forward}
##   lunge        {px, from}: forward advance eased over frames from..active.y, on the ground only
##   crit         &"none" | &"roll" (CRIT_CHANCE) | &"always"; a critical hit deals CRIT_MULT damage
##   stop         impact weight of a normal hit; crit_stop of a critical hit (default &"critical")
##   hit_feedback false suppresses contact VFX, sound, camera and hit-stop; damage and motion still resolve
##   dmg_mult     damage multiplier before the critical multiplier (default 1)
##   launch       the hit launches the target
##   knockback    the hit pushes a grounded target this many native px away
##   juggle       an airborne hit holds an airborne target in the air
##   steer        horizontal input steers the hero while the move plays airborne
##   chain        a ground light swing: holding the button after it coils into the charge
##   crouched     a crouching attack (lower origin, no lunge, no chain)
##   recovery     seconds of return pose; default 2 frames on the ground / 1 in the air at fps
##   air          {hold, fall} hang time when started airborne; end_hold after finishing airborne
##   jump         vertical speed given on the start frame when the move starts on the floor
##   special      special_kind name the move reports (tests, HUD, hit_resolved kind)
##   pierce       dash: continuously travels DASH_DISTANCE through targets during its active rush
##   dive         dive slash: falls at DIVE_SPEED, holds its last air frame, lands into a short recovery
##   lands        ends on touching the floor like a dive (landing pose, recovery, shockwave) but falls normally;
##                hold_frame is the frame held if the clip runs out in the air (default 11)
##   carry        horizontal speed (px/s, along the facing) while the move is airborne
##   shockwave    landing wave {half_width, launch, crit, dmg_mult, stop, crit_stop, again, ring}: hits grounded
##                targets near the feet; again = false spares targets the move already hit; ring adds a ring and
##                dust columns to the shock lines
##   launcher     rising slash: jumps and spawns rising airflow
##   ghosts       frames that leave an afterimage
##   rehit        frames from which every target can be hit again (multi-hit swings)
##   arc          {from, to}: code-drawn blade circle swept over the move, degrees from forward, negative is up
##   end          frame at which the move counts as finished, cutting the rest of the clip
##   then         segment that follows automatically when this one finishes (multi-part moves)
##   cancel       frame from which a buffered follow-up starts at once instead of at the end (not the original three)
##   dash_cancel  frame from which a dash press cuts the move short (light swings: hit, then dodge)
##   dodge        the evade: a press within DODGE_OFFSET_SECONDS after it starts the dodge-offset follow-up
##   resumes      dodge offset: counts as the next light hit of the string the dash interrupted
##   as           counts as this move in the combo graph (its follow-ups and stage)
##   side_only    side view only; ground / air_only: only started from the combo graph on the floor / in the air
##   swing        &"light" | &"heavy" | &"none" swing sound; pitch scales it

const CRIT_CHANCE := 0.30
const CRIT_MULT := 3
const SIDE_EXTRA_REACH := 12.0
const ORIGIN_HEIGHT := 17.0
const BLADE := {"length": 34.0, "width": 20.0, "reach": 21.0, "height": ORIGIN_HEIGHT}
const BIG_BLADE := {"length": 44.0, "width": 28.0, "reach": 21.0, "height": ORIGIN_HEIGHT}
# Spinning swings reach behind the hero as well.
const SPIN_BOX := {"rect": Rect2(-30, -42, 60, 44), "forward": 6.0}
const DIVE_BOX := {"rect": Rect2(-13, -24, 26, 42), "forward": 0.0}
const LIGHT_AIR := {"hold": 0.55, "fall": 6.0}
# Each part of the aerial spin holds the hero up anew; the last one also hangs on after the spin.
const SPIN_AIR := {"hold": 0.25, "fall": 6.0}

const MOVES := {
	&"attack1": {"stage": 1, "anim": "attack1", "air_anim": "air_attack1", "fps": 36.0, "active": Vector2i(6, 9),
		# The long blade is still behind the shoulder in side-view frame 6; frame 7 crosses forward.
		"side_first": 7, "box": BLADE, "lunge": {"px": 8.0, "from": 6}, "crit": &"none", "stop": &"light",
		"juggle": true, "steer": true, "chain": true, "air": LIGHT_AIR, "dash_cancel": 7},
	&"attack2": {"stage": 2, "anim": "attack2", "charge_link": "charge_link_light", "air_anim": "air_attack2", "fps": 40.0, "active": Vector2i(6, 9),
		"box": BLADE, "lunge": {"px": 8.0, "from": 6}, "crit": &"none", "stop": &"light",
		"juggle": true, "steer": true, "chain": true, "air": LIGHT_AIR, "dash_cancel": 6},
	&"attack3": {"stage": 3, "anim": "attack3", "air_anim": "air_attack3", "fps": 42.0, "active": Vector2i(6, 9),
		"box": BLADE, "lunge": {"px": 10.0, "from": 6}, "crit": &"roll", "stop": &"light",
		"juggle": true, "steer": true, "chain": true, "air": LIGHT_AIR, "dash_cancel": 6},
	&"crouch_stab": {"stage": 1, "anim": "crouch_stab", "fps": 40.0, "active": Vector2i(6, 9),
		"box": {"length": 27.0, "width": 16.0, "reach": 17.0, "height": 9.0}, "crit": &"none", "stop": &"light",
		"juggle": true, "crouched": true},
	&"rising_slash": {"stage": 1, "anim": "rising_slash", "fps": 40.0, "active": Vector2i(3, 9),
		"box": {"rect": Rect2(-18, -36, 36, 48), "forward": 19.0}, "crit": &"none", "stop": &"light",
		"launch": true, "special": "rising_slash", "launcher": true, "jump": -280.0},
	&"dive_slash": {"stage": 1, "anim": "dive_slash", "fps": 40.0, "active": Vector2i(0, -1),
		"box": DIVE_BOX, "crit": &"none", "stop": &"light", "special": "dive_slash", "dive": true},
	&"dash_stab": {"stage": 1, "anim": "dash_stab", "air_anim": "air_dash_stab", "fps": 40.0, "active": Vector2i(6, 13),
		"crit": &"none", "stop": &"tick", "juggle": true, "special": "dash_stab", "pierce": true, "hit_feedback": true,
		"air": {"hold": 0.55, "fall": 6.0, "end_hold": 0.30}, "dodge": true, "cancel": 14},
	# Fully charged draw: twice the old reach and damage, paid for by the stationary coil and recovery.
	&"heavy_slash": {"stage": 1, "as": &"attack1", "cancel": 11, "followup_seconds": 0.25, "anim": "attack3", "side_anim": "charged_draw", "fps": 40.0, "start_frame": 6, "active": Vector2i(8, 10),
		"box": {"length": 108.0, "width": 56.0, "reach": 48.0, "height": ORIGIN_HEIGHT},
		"lunge": {"px": 36.0, "from": 7}, "crit": &"always", "dmg_mult": 2, "crit_stop": &"heavy", "launch": true, "charged_launch": true, "knockback": 20.0, "recovery": 0.22,
		"special": "heavy_slash", "charged": true, "ghosts": [8], "swing": &"heavy", "pitch": 0.78},

	# Light string 4-5 (side view, on the ground): a quick thrust, then a two-part spin with a full blade circle.
	&"thrust4": {"stage": 4, "anim": "stab", "fps": 48.0, "active": Vector2i(6, 9),
		"box": {"length": 40.0, "width": 12.0, "reach": 24.0, "height": ORIGIN_HEIGHT}, "lunge": {"px": 10.0, "from": 5},
		"crit": &"none", "stop": &"light", "cancel": 11, "dash_cancel": 6, "side_only": true, "ground": true, "pitch": 1.15},
	&"spin5a": {"stage": 5, "anim": "attack2", "fps": 60.0, "start_frame": 2, "active": Vector2i(4, 10), "end": 11,
		"box": SPIN_BOX, "crit": &"none", "stop": &"light", "ghosts": [6], "arc": {"from": 30.0, "to": -180.0},
		"then": &"spin5b", "dash_cancel": 4, "side_only": true, "ground": true, "pitch": 1.2},
	&"spin5b": {"stage": 5, "anim": "attack1", "fps": 60.0, "start_frame": 2, "active": Vector2i(6, 11), "side_first": 7,
		"box": SPIN_BOX, "crit": &"none", "stop": &"critical", "recovery": 0.14, "ghosts": [8],
		"arc": {"from": -180.0, "to": -330.0}, "dash_cancel": 7, "side_only": true, "ground": true, "pitch": 1.1},

	# Heavy finishers: right button after light 0-4 (0 = on its own), and H H.
	&"rush_cleave": {"stage": 2, "anim": "heavy_cleave", "charge_link": "charge_link_heavy", "fps": 32.0, "active": Vector2i(8, 10),
		# A readable coil before a fast release. No dodge cancel or armour: committing can be punished.
		"box": {"length": 50.0, "width": 32.0, "reach": 24.0, "height": ORIGIN_HEIGHT},
		"lunge": {"px": 24.0, "from": 8}, "crit": &"none", "stop": &"heavy", "dmg_mult": 3,
		"knockback": 14.0, "ghosts": [8], "cancel": 13, "recovery": 0.16, "side_only": true, "ground": true,
		"swing": &"heavy", "pitch": 0.93},
	&"launch_slash": {"stage": 3, "anim": "rising_slash", "fps": 40.0, "active": Vector2i(3, 9),
		"box": {"rect": Rect2(-18, -36, 36, 48), "forward": 19.0}, "crit": &"none", "stop": &"light",
		"launch": true, "launcher": true, "jump": -280.0, "side_only": true, "ground": true, "pitch": 0.95},
	&"spin_cleave_a": {"stage": 4, "anim": "attack3", "fps": 48.0, "start_frame": 2, "active": Vector2i(5, 9), "rehit": [8],
		"end": 10, "box": SPIN_BOX, "crit": &"none", "stop": &"light", "ghosts": [6], "arc": {"from": 0.0, "to": -240.0},
		"then": &"spin_cleave_b", "side_only": true, "ground": true, "swing": &"heavy", "pitch": 1.05},
	&"spin_cleave_b": {"stage": 4, "anim": "attack2", "fps": 44.0, "start_frame": 3, "active": Vector2i(5, 10),
		"box": BIG_BLADE, "crit": &"always", "crit_stop": &"critical", "recovery": 0.16, "ghosts": [8],
		"arc": {"from": -240.0, "to": -400.0}, "side_only": true, "ground": true, "swing": &"heavy"},
	# Rift slash: a small hop on the dive wind-up, then the dive with a landing shockwave.
	&"rift_hop": {"stage": 5, "anim": "dive_slash", "fps": 36.0, "end": 6, "jump": -170.0, "then": &"rift_dive",
		"side_only": true, "ground": true, "pitch": 1.2},
	&"rift_dive": {"stage": 5, "anim": "dive_slash", "fps": 40.0, "start_frame": 6, "active": Vector2i(6, -1),
		"box": DIVE_BOX, "crit": &"none", "stop": &"light", "dive": true, "recovery": 0.16,
		"shockwave": {"half_width": 36.0, "launch": true, "crit": true, "crit_stop": &"critical"},
		"side_only": true, "swing": &"heavy", "pitch": 0.9},

	# Aerial spin: air_attack1 -> air_attack2 -> air_attack1 at 60 fps, a hit each, one blade circle across the three.
	# The middle hits stop 2 frames (tick), the last one is a sure critical with the 6-frame stop.
	&"air_spin_a": {"stage": 4, "anim": "air_attack1", "fps": 60.0, "active": Vector2i(6, 10), "end": 11,
		"box": SPIN_BOX, "crit": &"none", "stop": &"tick", "juggle": true, "air": SPIN_AIR, "ghosts": [7],
		"arc": {"from": 40.0, "to": -90.0}, "then": &"air_spin_b", "side_only": true, "air_only": true, "pitch": 1.25},
	&"air_spin_b": {"stage": 4, "anim": "air_attack2", "fps": 60.0, "start_frame": 2, "active": Vector2i(4, 10), "end": 11,
		"box": SPIN_BOX, "crit": &"none", "stop": &"tick", "juggle": true, "air": SPIN_AIR, "ghosts": [6],
		"arc": {"from": -90.0, "to": -210.0}, "then": &"air_spin_c", "side_only": true, "pitch": 1.3},
	&"air_spin_c": {"stage": 4, "anim": "air_attack1", "fps": 60.0, "start_frame": 2, "active": Vector2i(6, 11),
		"box": SPIN_BOX, "crit": &"always", "crit_stop": &"critical", "juggle": true,
		"air": {"hold": 0.25, "fall": 6.0, "end_hold": 0.30}, "ghosts": [8], "arc": {"from": -210.0, "to": -320.0},
		"side_only": true, "swing": &"heavy", "pitch": 1.1},

	# W + right click on the floor (player.request_leap_cleave): a forward leap of about 52 px and 15 px high with the
	# blade raised overhead, an overhead chop on the way down, and a shockwave along the floor on landing. Unlike
	# rift_hop (straight up at the end of the light string) and dive_slash (air S, straight down) it travels forward.
	&"leap_cleave": {"stage": 1, "anim": "air_attack2", "fps": 36.0, "start_frame": 2, "end": 10, "jump": -136.0,
		"carry": 118.0, "then": &"leap_cleave_chop", "ghosts": [6], "special": "leap_cleave", "side_only": true,
		"swing": &"heavy", "pitch": 0.85},
	&"leap_cleave_chop": {"stage": 1, "anim": "air_attack2", "fps": 30.0, "start_frame": 9, "active": Vector2i(10, -1),
		"box": {"rect": Rect2(-16, -34, 32, 38), "forward": 14.0}, "crit": &"none", "stop": &"heavy", "dmg_mult": 2,
		"launch": true, "carry": 118.0, "lands": true, "hold_frame": 15, "recovery": 0.16, "ghosts": [11],
		"shockwave": {"half_width": 24.0, "launch": true, "dmg_mult": 2, "stop": &"heavy", "again": false, "ring": true},
		"special": "leap_cleave", "side_only": true, "swing": &"none"},

	# Perfect-dodge counter (player._start_counter): a sure critical with the heavy freeze, 3x damage.
	&"counter_slash": {"stage": 3, "anim": "attack3", "air_anim": "air_attack3", "fps": 48.0, "start_frame": 3,
		"active": Vector2i(5, 9), "box": BIG_BLADE, "crit": &"always", "crit_stop": &"heavy", "ghosts": [4, 6],
		"recovery": 0.16, "air": LIGHT_AIR, "special": "counter", "side_only": true, "swing": &"heavy", "pitch": 0.9},

	# Dodge offset: right after the dash. The shadow slash is a quicker, longer-reaching attack1 that takes the place
	# of the next light hit (the string goes on from there); the chase cleave is a rush cleave with a longer lunge.
	&"shadow_slash": {"stage": 1, "anim": "attack1", "air_anim": "air_attack1", "fps": 52.0, "active": Vector2i(6, 9),
		"side_first": 7, "box": {"length": 42.0, "width": 20.0, "reach": 25.0, "height": ORIGIN_HEIGHT},
		"lunge": {"px": 8.0, "from": 4}, "crit": &"none", "stop": &"light", "juggle": true, "steer": true, "chain": true,
		"air": LIGHT_AIR, "ghosts": [5, 7], "resumes": true, "dash_cancel": 7, "side_only": true, "pitch": 1.15},
	&"chase_cleave": {"stage": 2, "anim": "attack3", "fps": 40.0, "start_frame": 2, "active": Vector2i(5, 9),
		"box": BIG_BLADE, "lunge": {"px": 24.0, "from": 3}, "crit": &"none", "stop": &"critical", "dmg_mult": 2,
		"knockback": 10.0, "ghosts": [4, 6], "cancel": 11, "recovery": 0.12, "as": &"rush_cleave", "side_only": true,
		"ground": true, "swing": &"heavy", "pitch": 1.2},
}

## Combo graph: current move (&"" = idle) -> input -> next move, or several candidates in order; the hero takes
## the first one its situation allows (side_only / ground).
const STRINGS := {
	&"": {&"light": &"attack1", &"heavy": [&"rush_cleave", &"air_spin_a"]},
	&"attack1": {&"light": &"attack2", &"heavy": [&"rush_cleave", &"air_spin_a"]},
	&"attack2": {&"light": &"attack3", &"heavy": [&"launch_slash", &"air_spin_a"]},
	&"attack3": {&"light": [&"thrust4", &"air_spin_a"], &"heavy": [&"spin_cleave_a", &"air_spin_a"]},
	&"thrust4": {&"light": &"spin5a", &"heavy": &"rift_hop"},
	&"rush_cleave": {&"heavy": &"launch_slash"},
	&"dash_stab": {&"light": &"shadow_slash", &"heavy": [&"chase_cleave", &"air_spin_a"]},
}


## Candidate follow-ups of a move for one input, in order of preference.
static func next_moves(current: StringName, input: StringName) -> Array:
	var next: Variant = STRINGS.get(current, {}).get(input, [])
	return next if next is Array else [next]
