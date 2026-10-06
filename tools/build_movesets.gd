extends SceneTree
## Builds every character's move list (res://data/moves/<id>/*.tres) from one shared base
## set, per-character tuning, and per-character signature moves, then assigns the lists
## and character stats to res://data/characters/<id>.tres.
##
## Run: godot_console --headless --path . -s res://tools/build_movesets.gd
##
## This script is the source of truth for move data: edit values here and re-run.
## Hitbox offsets/impact times were calibrated against the animation clips (CLAUDE.md §5.5).

const H := MoveData.HitLevel

## file: [name, input, animation, impact, end, startup, active, recovery, damage, level,
##        hitstun, blockstun, hitstop, knockback, hitbox_offset, radius, extras]
## extras: cancel_into, camera_intensity, launches, knockdown, lunge, and for specials:
##         chip_damage, hits, hit_interval, travel, rise, landing_recovery, invuln_frames,
##         low_profile, super_move, followup, projectile_speed, projectile_lifetime,
##         projectile_color, dive, focus_gain, focus_hits, focus_damage, focus_rise,
##         focus_consume, focus_followup (see MoveData)
const BASE := {
	"jab": ["Jab", "LP", &"ual1/Punch_Jab", 0.20, 0.62, 4, 2, 8, 30, H.HIGH, 14, 10, 5, Vector2(1.2, 0), Vector3(0, 1.40, -0.78), 0.15, {cancel_into = ["LP", "HP", "2LP"]}],
	"straight": ["Straight", "HP", &"ual1/Punch_Cross", 0.28, 0.85, 9, 3, 18, 80, H.HIGH, 20, 14, 8, Vector2(2.5, 0), Vector3(0.1, 1.36, -0.70), 0.18, {camera_intensity = 0.1}],
	"mid_kick": ["Mid Kick", "LK", &"fight/front_kick", 0.20, 0.0, 7, 3, 14, 50, H.MID, 17, 12, 6, Vector2(1.8, 0), Vector3(0.05, 1.0, -1.0), 0.18, {cancel_into = ["HP"]}],
	"roundhouse": ["Roundhouse", "HK", &"fight/high_kick", 0.26, 0.0, 13, 4, 22, 110, H.HIGH, 22, 16, 10, Vector2(3.5, 0), Vector3(-0.08, 1.50, -0.85), 0.22, {camera_intensity = 0.2}],
	"crouch_jab": ["Crouching Jab", "2LP", &"fight/crouch_jab", 0.12, 0.0, 5, 2, 9, 25, H.MID, 13, 9, 5, Vector2(1.0, 0), Vector3(-0.1, 0.84, -0.55), 0.15, {cancel_into = ["2LP", "2LK"]}],
	"low_kick": ["Low Kick", "2LK", &"fight/sweep", 0.18, 0.0, 6, 3, 13, 35, H.LOW, 15, 11, 6, Vector2(1.2, 0), Vector3(0.08, 0.18, -0.78), 0.18, {}],
	"uppercut": ["Uppercut", "2HP", &"fight/uppercut", 0.22, 0.0, 8, 4, 24, 90, H.MID, 0, 16, 10, Vector2(0.8, 6.5), Vector3(0.0, 1.30, -0.40), 0.25, {launches = true, camera_intensity = 0.35}],
	"sweep": ["Sweep", "2HK", &"fight/spin_sweep", 0.20, 0.0, 9, 4, 26, 80, H.LOW, 0, 14, 8, Vector2(1.0, 0), Vector3(0.0, 0.15, -0.78), 0.22, {knockdown = true, camera_intensity = 0.2}],
	"jump_jab": ["Jump Jab", "j.LP", &"fight/jump_punch", 0.10, 0.4, 4, 8, 6, 40, H.OVERHEAD, 14, 10, 5, Vector2(1.0, 0), Vector3(-0.22, 1.0, -0.63), 0.18, {}],
	"jump_hammer": ["Jump Hammer", "j.HP", &"fight/jump_punch", 0.10, 0.4, 7, 5, 10, 75, H.OVERHEAD, 20, 14, 8, Vector2(1.8, 0), Vector3(-0.22, 1.0, -0.63), 0.2, {camera_intensity = 0.1}],
	"jump_kick": ["Jump Kick", "j.LK", &"fight/jump_kick", 0.12, 0.45, 5, 8, 6, 45, H.OVERHEAD, 15, 10, 6, Vector2(1.2, 0), Vector3(0.11, 0.45, -0.88), 0.2, {}],
	"flying_kick": ["Flying Kick", "j.HK", &"fight/jump_kick", 0.12, 0.45, 8, 6, 10, 85, H.OVERHEAD, 21, 15, 9, Vector2(2.2, 0), Vector3(0.11, 0.45, -0.88), 0.22, {camera_intensity = 0.15}],
}

## Per-character tuning applied to the base set, plus stats, signature moves, and
## specials (motion inputs, not scaled by the tuning). Specials' hitboxes were measured
## from their clips at the impact time (fighter-local, -Z toward the opponent).
## startup: frames added to every base move (min 3). damage / knockback: multipliers.
const CHARACTERS := {
	"kenji": {
		startup = 0, damage = 1.05, knockback = 1.0, hitstop = 0,
		stats = {max_health = 1000, walk_speed = 2.0, back_walk_speed = 1.6, dash_speed = 6.0,
			jump_velocity = 6.0, weight = 1.0, throw_damage = 120, power_rating = 0.55, speed_rating = 0.55,
			victory_animations = [&"fight/victory_bow", &"fight/victory_fist_pump"],
			alt_body_albedo = "res://assets/characters/base/T_Superhero_Male_Dark.png", alt_hair_color = Color(0.55, 0.38, 0.18)},
		signatures = {
			"advancing_straight": ["Advancing Straight", "6HP", &"ual1/Punch_Cross", 0.28, 0.85, 12, 3, 18, 90, H.HIGH, 21, 16, 9, Vector2(2.8, 0), Vector3(0.1, 1.36, -0.70), 0.2, {lunge = 4.5, camera_intensity = 0.15}],
			"snap_kick": ["Snap Kick", "6LK", &"fight/front_kick", 0.20, 0.0, 5, 2, 14, 40, H.MID, 15, 11, 5, Vector2(1.4, 0), Vector3(0.05, 1.0, -1.0), 0.18, {cancel_into = ["HP", "6HP"]}],
		},
		specials = {
			# Fireball: slow enough to walk behind, fast enough to zone with.
			"ki_blast": ["Ki Blast", "236P", &"fight/palm_blast", 0.20, 0.65, 10, 1, 27, 70, H.MID, 18, 14, 7, Vector2(1.8, 0), Vector3(0, 1.2, -0.6), 0.3,
				{projectile_speed = 6.5, projectile_lifetime = 100, chip_damage = 8, camera_intensity = 0.1}],
			# Invincible anti-air / reversal; very punishable when it misses.
			"rising_dragon": ["Rising Dragon", "623P", &"fight/rising_uppercut", 0.09, 0.7, 4, 12, 14, 110, H.MID, 0, 18, 10, Vector2(1.0, 7.0), Vector3(-0.15, 1.55, -0.35), 0.38,
				{launches = true, rise = 7.0, travel = 1.2, invuln_frames = 7, landing_recovery = 16, chip_damage = 12, camera_intensity = 0.35}],
			"dragon_barrage": ["Dragon Barrage", "236236P", &"fight/punch_flurry", 0.10, 0.70, 6, 30, 24, 28, H.MID, 22, 16, 4, Vector2(0.6, 0), Vector3(0, 1.22, -0.6), 0.32,
				{super_move = true, hits = 6, hit_interval = 5, travel = 1.8, invuln_frames = 12, chip_damage = 6, followup = "~dragon_finish", camera_intensity = 0.15}],
			"dragon_finish": ["Dragon Barrage", "~dragon_finish", &"fight/rising_uppercut", 0.09, 0.7, 3, 10, 20, 140, H.MID, 0, 20, 16, Vector2(1.2, 8.0), Vector3(-0.15, 1.55, -0.35), 0.42,
				{launches = true, rise = 7.5, travel = 1.0, invuln_frames = 13, landing_recovery = 12, chip_damage = 15, camera_intensity = 0.6}],
		},
	},
	"rhea": {
		startup = -1, damage = 0.95, knockback = 0.9, hitstop = -1,
		stats = {max_health = 960, walk_speed = 2.6, back_walk_speed = 2.0, dash_speed = 7.5,
			jump_velocity = 6.4, weight = 0.85, throw_damage = 100, power_rating = 0.35, speed_rating = 0.9,
			victory_animations = [&"fight/victory_point", &"fight/victory_fist_pump"],
			alt_body_albedo = "res://assets/characters/base/T_Superhero_Female_Light_BaseColor.png", alt_hair_color = Color(0.07, 0.07, 0.1)},
		signatures = {
			"rushing_hook": ["Rushing Hook", "6HP", &"fight/rushing_hook", 0.28, 0.0, 10, 3, 20, 70, H.MID, 20, 14, 8, Vector2(2.5, 0), Vector3(-0.15, 0.72, -0.95), 0.22, {lunge = 4.0, camera_intensity = 0.15}],
			"step_kick": ["Step Kick", "6LK", &"fight/front_kick", 0.20, 0.0, 7, 3, 12, 40, H.MID, 16, 11, 5, Vector2(1.4, 0), Vector3(0.05, 1.0, -1.0), 0.18, {lunge = 3.5, cancel_into = ["6HP", "LP"]}],
		},
		specials = {
			# Feet-first slide along the canvas: low, slides under highs, knocks down.
			"gale_slide": ["Gale Slide", "236K", &"fight/slide_kick", 0.15, 1.25, 8, 16, 14, 70, H.LOW, 0, 14, 8, Vector2(1.5, 0), Vector3(-0.07, 0.15, -0.85), 0.28,
				{knockdown = true, travel = 5.5, low_profile = true, chip_damage = 8, camera_intensity = 0.2}],
			"crescent_rise": ["Crescent Rise", "623K", &"fight/rising_kick", 0.09, 0.7, 4, 10, 14, 85, H.MID, 0, 16, 9, Vector2(1.0, 7.0), Vector3(-0.04, 1.75, -0.5), 0.36,
				{launches = true, rise = 7.5, travel = 1.0, invuln_frames = 6, landing_recovery = 14, chip_damage = 10, camera_intensity = 0.3}],
			"tempest_kicks": ["Tempest Kicks", "236236K", &"fight/kick_flurry", 0.10, 0.77, 5, 32, 24, 24, H.MID, 22, 16, 4, Vector2(0.6, 0), Vector3(-0.04, 1.2, -0.95), 0.32,
				{super_move = true, hits = 7, hit_interval = 4, travel = 2.0, invuln_frames = 11, chip_damage = 5, followup = "~tempest_finish", camera_intensity = 0.15}],
			"tempest_finish": ["Tempest Kicks", "~tempest_finish", &"fight/rising_kick", 0.09, 0.7, 3, 10, 18, 120, H.MID, 0, 20, 14, Vector2(1.2, 8.0), Vector3(-0.04, 1.75, -0.5), 0.4,
				{launches = true, rise = 7.5, travel = 1.0, invuln_frames = 13, landing_recovery = 10, chip_damage = 12, camera_intensity = 0.6}],
		},
	},
	"brutus": {
		startup = 2, damage = 1.25, knockback = 1.25, hitstop = 2,
		stats = {max_health = 1100, walk_speed = 1.5, back_walk_speed = 1.2, dash_speed = 4.5,
			jump_velocity = 5.6, weight = 1.3, throw_damage = 160, power_rating = 0.95, speed_rating = 0.25,
			victory_animations = [&"fight/victory_flex", &"fight/victory_fist_pump"],
			alt_body_albedo = "res://assets/characters/base/T_Superhero_Male_Light.png", alt_hair_color = Color(0.42, 0.42, 0.44)},
		signatures = {
			"overhead_smash": ["Overhead Smash", "6HP", &"ual2/OverhandThrow", 0.40, 0.9, 20, 4, 24, 130, H.OVERHEAD, 0, 18, 12, Vector2(2.0, 0), Vector3(0.2, 0.8, -0.95), 0.28, {knockdown = true, camera_intensity = 0.3}],
			"heavy_boot": ["Heavy Boot", "6HK", &"fight/front_kick", 0.20, 0.0, 12, 4, 22, 100, H.MID, 22, 16, 11, Vector2(4.5, 0), Vector3(0.05, 1.0, -1.0), 0.22, {camera_intensity = 0.2}],
		},
		specials = {
			# Charges across the ring until it connects; huge pushback.
			"bull_charge": ["Bull Charge", "236P", &"fight/shoulder_charge", 0.15, 0.83, 14, 16, 20, 120, H.MID, 24, 18, 12, Vector2(5.0, 0), Vector3(0, 1.0, -0.6), 0.38,
				{travel = 8.0, chip_damage = 14, camera_intensity = 0.3}],
			# Double-fist slam: a shockwave along the floor that must be blocked low.
			"earthquake": ["Earthquake", "214P", &"fight/ground_pound", 0.33, 0.85, 18, 6, 24, 110, H.LOW, 0, 16, 12, Vector2(1.5, 0), Vector3(0, 0.2, -0.9), 0.55,
				{knockdown = true, chip_damage = 12, camera_intensity = 0.3, impact_fx = &"shockwave"}],
			"titan_rush": ["Titan Rush", "236236P", &"fight/shoulder_charge", 0.15, 0.83, 6, 24, 26, 40, H.MID, 24, 16, 6, Vector2(0.6, 0), Vector3(0, 1.0, -0.6), 0.4,
				{super_move = true, hits = 4, hit_interval = 6, travel = 5.0, invuln_frames = 10, chip_damage = 8, followup = "~titan_finish", camera_intensity = 0.2}],
			"titan_finish": ["Titan Rush", "~titan_finish", &"ual2/OverhandThrow", 0.40, 0.9, 8, 5, 26, 220, H.MID, 0, 20, 16, Vector2(2.5, 0), Vector3(0.2, 0.8, -0.95), 0.42,
				{knockdown = true, chip_damage = 18, camera_intensity = 0.6}],
		},
	},
	"valka": {
		startup = 1, damage = 1.1, knockback = 1.1, hitstop = 1,
		# New characters are created from these (existing ones keep their scene setup).
		create = {display_name = "Valka", archetype = "Grappler", select_order = 3,
			description = "Towering wrestler. Walks you down, spins through fireballs, and grabs anyone who just blocks.",
			model_scene = "res://assets/characters/base/Superhero_Female_FullBody.gltf",
			hair_scenes = ["res://assets/characters/hair/Hair_Long.gltf", "res://assets/characters/hair/Eyebrows_Female.gltf"],
			body_albedo = "res://assets/characters/base/T_Superhero_Female_Light_BaseColor.png",
			model_scale = 1.06, hair_color = Color(0.93, 0.86, 0.68), placeholder_color = Color(0.85, 0.75, 0.3)},
		stats = {max_health = 1050, walk_speed = 1.8, back_walk_speed = 1.4, dash_speed = 5.0,
			jump_velocity = 5.8, weight = 1.15, throw_damage = 150, power_rating = 0.8, speed_rating = 0.4,
			victory_animations = [&"fight/victory_flex", &"fight/victory_fist_pump"],
			alt_body_albedo = "res://assets/characters/base/T_Superhero_Female_Dark_BaseColor.png", alt_hair_color = Color(0.62, 0.12, 0.06)},
		signatures = {
			"shoulder_tackle": ["Shoulder Tackle", "6HP", &"fight/shoulder_charge", 0.15, 0.83, 12, 4, 20, 85, H.MID, 20, 15, 9, Vector2(3.5, 0), Vector3(0, 1.0, -0.6), 0.3, {lunge = 4.0, camera_intensity = 0.15}],
			"knee_lift": ["Knee Lift", "6LK", &"fight/knee_lift", 0.16, 0.62, 8, 3, 18, 70, H.MID, 0, 14, 9, Vector2(0.8, 6.0), Vector3(0, 1.0, -0.45), 0.28, {launches = true, camera_intensity = 0.25}],
		},
		specials = {
			# Command grab: unblockable and untechable, but a whiff is very punishable.
			"valkyrie_slam": ["Valkyrie Slam", "63214P", &"fight/throw", 0.08, 0.85, 8, 3, 36, 150, H.MID, 0, 0, 12, Vector2.ZERO, Vector3(0, 1.0, -0.6), 0.3,
				{command_grab = true, grab_range = 0.95, camera_intensity = 0.4}],
			# Spins through fireballs; three hits, the last one pops the opponent up.
			"spinning_lariat": ["Spinning Lariat", "623P", &"fight/lariat", 0.12, 0.93, 7, 32, 16, 45, H.MID, 18, 14, 6, Vector2(2.0, 4.0), Vector3(0, 1.35, -0.35), 0.6,
				{hits = 3, hit_interval = 8, travel = 1.2, projectile_immune = true, launches = true, chip_damage = 6, camera_intensity = 0.2}],
			"thunder_valkyrie": ["Thunder Valkyrie", "236236P", &"fight/throw", 0.08, 0.85, 7, 4, 34, 240, H.MID, 0, 0, 16, Vector2.ZERO, Vector3(0, 1.0, -0.6), 0.3,
				{super_move = true, command_grab = true, grab_range = 1.15, invuln_frames = 8, camera_intensity = 0.6, impact_fx = &"shockwave"}],
		},
	},
	"jin": {
		startup = 0, damage = 0.95, knockback = 1.05, hitstop = 0,
		reach = 1.12, # long legs: base moves reach 12% further
		create = {display_name = "Jin", archetype = "Kicker", select_order = 4,
			description = "Tae Kwon Do kicker. Controls the space at kick range and punishes anyone who steps in.",
			model_scene = "res://assets/characters/base/Superhero_Male_FullBody.gltf",
			hair_scenes = ["res://assets/characters/hair/Hair_Buzzed.gltf", "res://assets/characters/hair/Eyebrows_Regular.gltf"],
			body_albedo = "res://assets/characters/jin/T_Jin_Body.png", # deeper skin, teal shorts (from the CC0 texture)
			model_scale = 1.02, hair_color = Color(0.05, 0.04, 0.04), placeholder_color = Color(0.2, 0.7, 0.55)},
		stats = {max_health = 980, walk_speed = 2.2, back_walk_speed = 1.8, dash_speed = 6.5,
			jump_velocity = 6.2, weight = 0.95, throw_damage = 110, power_rating = 0.6, speed_rating = 0.65,
			victory_animations = [&"fight/victory_point", &"fight/victory_fist_pump"],
			alt_body_albedo = "res://assets/characters/base/T_Superhero_Male_Light.png", alt_hair_color = Color(0.5, 0.33, 0.15)},
		signatures = {
			# Overhead from kick range: must be blocked standing.
			"axe_kick": ["Axe Kick", "6HK", &"fight/axe_kick", 0.30, 0.75, 16, 4, 18, 100, H.OVERHEAD, 24, 16, 10, Vector2(2.0, 0), Vector3(0.04, 1.1, -1.0), 0.26, {camera_intensity = 0.25}],
			"push_kick": ["Push Kick", "6LK", &"fight/front_kick", 0.20, 0.0, 9, 3, 16, 55, H.MID, 16, 13, 7, Vector2(3.2, 0), Vector3(0.05, 1.0, -1.12), 0.2, {lunge = 2.5, camera_intensity = 0.1}],
		},
		specials = {
			# Turns and drives the heel back: long-reaching, big pushback, slightly unsafe.
			"spinning_back_kick": ["Spinning Back Kick", "236K", &"fight/spin_back_kick", 0.22, 0.66, 12, 3, 20, 90, H.MID, 22, 16, 11, Vector2(4.0, 0), Vector3(-0.05, 1.06, -0.92), 0.27,
				{lunge = 4.5, chip_damage = 10, camera_intensity = 0.25}], # steps in as it turns
			# Rising spin kick anti-air: invincible start, two hits, launches.
			"tornado_kick": ["Tornado Kick", "623K", &"fight/tornado_kick", 0.13, 0.71, 4, 14, 14, 50, H.MID, 0, 16, 8, Vector2(1.0, 6.5), Vector3(0, 1.4, -0.55), 0.42,
				{hits = 2, hit_interval = 7, launches = true, rise = 6.5, travel = 1.0, invuln_frames = 6, landing_recovery = 14, chip_damage = 6, camera_intensity = 0.3}],
			"hurricane_kicks": ["Hurricane Kicks", "236236K", &"fight/hurricane_kicks", 0.10, 0.775, 5, 30, 22, 24, H.MID, 22, 16, 4, Vector2(0.6, 0), Vector3(0.0, 1.3, -0.98), 0.32,
				{super_move = true, hits = 7, hit_interval = 4, travel = 1.8, invuln_frames = 11, chip_damage = 5, followup = "~hurricane_finish", camera_intensity = 0.15}],
			"hurricane_finish": ["Hurricane Kicks", "~hurricane_finish", &"fight/axe_kick", 0.30, 0.75, 6, 4, 22, 130, H.MID, 0, 20, 14, Vector2(1.5, 0), Vector3(0.04, 1.1, -1.0), 0.32,
				{knockdown = true, chip_damage = 12, camera_intensity = 0.6}],
		},
	},
	"mira": {
		startup = 0, damage = 1.05, knockback = 1.0, hitstop = 0,
		create = {display_name = "Mira", archetype = "Brawler", select_order = 5,
			description = "Manila street brawler. Strings punches into flip kicks, and powers up with Lakas Stance until her rushes hit like a typhoon.",
			model_scene = "res://assets/characters/base/Superhero_Female_FullBody.gltf",
			hair_scenes = ["res://assets/characters/hair/Hair_Bob.tscn", "res://assets/characters/hair/Eyebrows_Female.gltf"], # from tools/build_hair.gd
			body_albedo = "res://assets/characters/mira/T_Mira_Body.png", # the female base tinted warm medium-brown
			model_scale = 1.0, hair_color = Color(0.13, 0.08, 0.05), placeholder_color = Color(0.86, 0.62, 0.12)},
		stats = {max_health = 1000, walk_speed = 2.3, back_walk_speed = 1.8, dash_speed = 7.0,
			jump_velocity = 6.3, weight = 0.92, throw_damage = 115, power_rating = 0.55, speed_rating = 0.75,
			victory_animations = [&"fight/victory_fist_pump", &"fight/victory_point"],
			alt_body_albedo = "res://assets/characters/mira/T_Mira_Body.png", alt_hair_color = Color(0.32, 0.1, 0.05)},
		signatures = {
			# Backfist that chains into itself, the straight or the flip kick.
			"tapik": ["Tapik", "6LP", &"fight/backfist", 0.12, 0.32, 6, 2, 10, 40, H.HIGH, 15, 11, 5, Vector2(1.3, 0), Vector3(-0.08, 1.36, -0.6), 0.17,
				{cancel_into = ["6LP", "HP", "6HK"]}],
			# Somersault kick: launches, but very punishable on block.
			"sipa_flip": ["Sipa Flip", "6HK", &"fight/flip_kick", 0.12, 0.66, 9, 4, 24, 85, H.MID, 0, 16, 10, Vector2(0.6, 6.8), Vector3(0.02, 1.45, -0.5), 0.32,
				{launches = true, camera_intensity = 0.3}],
			# Dive kick: changes the jump arc; extra landing lag when it misses.
			"lawin_drop": ["Lawin Drop", "j.2K", &"fight/dive_kick", 0.08, 0.6, 5, 30, 4, 60, H.OVERHEAD, 17, 12, 7, Vector2(1.5, 0), Vector3(0.1, 0.25, -0.6), 0.24,
				{dive = Vector2(4.5, 7.0), landing_recovery = 10, camera_intensity = 0.1}],
		},
		specials = {
			# Travelling punch flurry: Focus adds a hit and 15% damage per level.
			"bagyo_rush": ["Bagyo Rush", "236P", &"fight/punch_flurry", 0.10, 0.70, 10, 18, 22, 36, H.MID, 20, 15, 5, Vector2(3.0, 0), Vector3(0, 1.22, -0.6), 0.32,
				{hits = 3, hit_interval = 6, travel = 4.2, chip_damage = 5, focus_hits = 1, focus_damage = 0.15, camera_intensity = 0.15}],
			# Invincible rising flip kick: Focus adds height and 15% damage per level.
			"lawin_rise": ["Lawin Rise", "623K", &"fight/flip_kick", 0.12, 0.66, 4, 10, 16, 90, H.MID, 0, 16, 9, Vector2(1.0, 7.0), Vector3(0.02, 1.5, -0.45), 0.38,
				{launches = true, rise = 6.5, travel = 1.0, invuln_frames = 6, landing_recovery = 14, chip_damage = 10, focus_damage = 0.15, focus_rise = 0.6, camera_intensity = 0.3}],
			# Power-up stance: no hitbox, one Focus level on its first active frame.
			"lakas_stance": ["Lakas Stance", "214P", &"fight/focus_stance", 0.25, 0.6, 14, 1, 10, 0, H.MID, 0, 0, 0, Vector2.ZERO, Vector3(0, 1.0, 0), 0.0,
				{focus_gain = 1, impact_fx = &"focus"}],
			"huling_hagupit": ["Huling Hagupit", "236236P", &"fight/punch_flurry", 0.10, 0.70, 6, 34, 22, 26, H.MID, 22, 16, 4, Vector2(0.6, 0), Vector3(0, 1.22, -0.6), 0.32,
				{super_move = true, hits = 8, hit_interval = 4, travel = 2.0, invuln_frames = 12, chip_damage = 5,
					followup = "~hagupit_finish", focus_followup = "~hagupit_max", focus_consume = true, camera_intensity = 0.15}],
			"hagupit_finish": ["Huling Hagupit", "~hagupit_finish", &"fight/palm_blast", 0.20, 0.65, 4, 4, 24, 130, H.MID, 0, 20, 14, Vector2(4.0, 2.5), Vector3(0, 1.1, -0.55), 0.4,
				{knockdown = true, chip_damage = 12, camera_intensity = 0.6}],
			# The finisher at full Focus: a shockwave strike.
			"hagupit_max": ["Huling Hagupit", "~hagupit_max", &"fight/palm_blast", 0.20, 0.65, 4, 4, 24, 170, H.MID, 0, 20, 16, Vector2(5.0, 3.0), Vector3(0, 1.1, -0.55), 0.45,
				{knockdown = true, chip_damage = 16, camera_intensity = 0.8, impact_fx = &"shockwave"}],
		},
	},
}


func _initialize() -> void:
	for id: String in CHARACTERS:
		var spec: Dictionary = CHARACTERS[id]
		var dir := "res://data/moves/%s/" % id
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var moves: Array[MoveData] = []
		for file: String in BASE:
			var move := _make(BASE[file])
			move.startup = maxi(3, move.startup + spec.startup)
			move.damage = roundi(move.damage * spec.damage)
			move.knockback *= spec.knockback
			move.hitstop = maxi(3, move.hitstop + spec.hitstop)
			var reach: float = spec.get("reach", 1.0)
			move.hitbox_offset.z *= reach # longer limbs push the hitbox further out
			moves.append(_save(move, dir + file + ".tres"))
		for file: String in spec.signatures:
			moves.append(_save(_make(spec.signatures[file]), dir + file + ".tres"))
		for file: String in spec.specials:
			moves.append(_save(_make(spec.specials[file]), dir + file + ".tres"))

		var path := "res://data/characters/%s.tres" % id
		var character: CharacterData
		if ResourceLoader.exists(path):
			character = load(path) as CharacterData
		else:
			character = _create_character(id, spec.create)
		character.moves.assign(moves)
		for stat: String in spec.stats:
			if stat == "victory_animations":
				character.victory_animations.assign(spec.stats[stat])
			elif stat == "alt_body_albedo":
				character.alt_body_albedo = load(spec.stats[stat])
			else:
				character.set(stat, spec.stats[stat])
		var portrait := "res://assets/ui/portraits/%s.png" % id # from tools/render_portraits.gd
		if ResourceLoader.exists(portrait):
			character.portrait = load(portrait)
		var err := ResourceSaver.save(character, path)
		print("%-7s %2d moves  err=%d" % [id, moves.size(), err])
	quit()


## A brand-new character resource from its `create` visuals.
func _create_character(id: String, visuals: Dictionary) -> CharacterData:
	var character := CharacterData.new()
	character.id = StringName(id)
	for key: String in visuals:
		var value = visuals[key]
		match key:
			"model_scene", "body_albedo":
				character.set(key, load(value))
			"hair_scenes":
				var scenes: Array[PackedScene] = []
				for path: String in value:
					scenes.append(load(path))
				character.hair_scenes = scenes
			_:
				character.set(key, value)
	return character


func _make(row: Array) -> MoveData:
	var m := MoveData.new()
	m.name = row[0]
	m.input = row[1]
	m.animation = row[2]
	m.animation_impact = row[3]
	m.animation_end = row[4]
	m.startup = row[5]
	m.active = row[6]
	m.recovery = row[7]
	m.damage = row[8]
	m.hit_level = row[9]
	m.hitstun = row[10]
	m.blockstun = row[11]
	m.hitstop = row[12]
	m.knockback = row[13]
	m.hitbox_offset = row[14]
	m.hitbox_radius = row[15]
	var extras: Dictionary = row[16]
	m.cancel_into.assign(extras.get("cancel_into", []))
	m.camera_intensity = extras.get("camera_intensity", 0.0)
	m.launches = extras.get("launches", false)
	m.knockdown = extras.get("knockdown", false)
	m.lunge = extras.get("lunge", 0.0)
	for key in ["chip_damage", "hits", "hit_interval", "travel", "rise", "landing_recovery", "invuln_frames",
			"low_profile", "super_move", "followup", "projectile_speed", "projectile_lifetime", "projectile_color", "impact_fx",
			"command_grab", "grab_range", "projectile_immune", "dive", "focus_gain", "focus_hits", "focus_damage",
			"focus_rise", "focus_consume", "focus_followup"]:
		if extras.has(key):
			m.set(key, extras[key])
	return m


func _save(move: MoveData, path: String) -> MoveData:
	var err := ResourceSaver.save(move, path)
	assert(err == OK, "failed to save %s" % path)
	return load(path)
