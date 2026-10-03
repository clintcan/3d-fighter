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
## extras: cancel_into, camera_intensity, launches, knockdown, lunge
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

## Per-character tuning applied to the base set, plus stats and signature moves.
## startup: frames added to every base move (min 3). damage / knockback: multipliers.
const CHARACTERS := {
	"kenji": {
		startup = 0, damage = 1.0, knockback = 1.0, hitstop = 0,
		stats = {max_health = 1000, walk_speed = 2.0, back_walk_speed = 1.6, dash_speed = 6.0,
			jump_velocity = 6.0, weight = 1.0, throw_damage = 120, power_rating = 0.55, speed_rating = 0.55,
			victory_animations = [&"fight/victory_bow", &"fight/victory_fist_pump"]},
		signatures = {
			"advancing_straight": ["Advancing Straight", "6HP", &"ual1/Punch_Cross", 0.28, 0.85, 12, 3, 18, 90, H.HIGH, 21, 16, 9, Vector2(2.8, 0), Vector3(0.1, 1.36, -0.70), 0.2, {lunge = 4.5, camera_intensity = 0.15}],
			"snap_kick": ["Snap Kick", "6LK", &"fight/front_kick", 0.20, 0.0, 5, 2, 14, 40, H.MID, 15, 11, 5, Vector2(1.4, 0), Vector3(0.05, 1.0, -1.0), 0.18, {cancel_into = ["HP", "6HP"]}],
		},
	},
	"rhea": {
		startup = -1, damage = 0.85, knockback = 0.9, hitstop = -1,
		stats = {max_health = 900, walk_speed = 2.6, back_walk_speed = 2.0, dash_speed = 7.5,
			jump_velocity = 6.4, weight = 0.85, throw_damage = 100, power_rating = 0.35, speed_rating = 0.9,
			victory_animations = [&"fight/victory_point", &"fight/victory_fist_pump"]},
		signatures = {
			"rushing_hook": ["Rushing Hook", "6HP", &"fight/rushing_hook", 0.28, 0.0, 10, 3, 20, 70, H.MID, 20, 14, 8, Vector2(2.5, 0), Vector3(-0.15, 0.72, -0.95), 0.22, {lunge = 4.0, camera_intensity = 0.15}],
			"step_kick": ["Step Kick", "6LK", &"fight/front_kick", 0.20, 0.0, 7, 3, 12, 40, H.MID, 16, 11, 5, Vector2(1.4, 0), Vector3(0.05, 1.0, -1.0), 0.18, {lunge = 3.5, cancel_into = ["6HP", "LP"]}],
		},
	},
	"brutus": {
		startup = 2, damage = 1.3, knockback = 1.25, hitstop = 2,
		stats = {max_health = 1150, walk_speed = 1.5, back_walk_speed = 1.2, dash_speed = 4.5,
			jump_velocity = 5.6, weight = 1.3, throw_damage = 160, power_rating = 0.95, speed_rating = 0.25,
			victory_animations = [&"fight/victory_flex", &"fight/victory_fist_pump"]},
		signatures = {
			"overhead_smash": ["Overhead Smash", "6HP", &"ual2/OverhandThrow", 0.40, 0.9, 20, 4, 24, 130, H.OVERHEAD, 0, 18, 12, Vector2(2.0, 0), Vector3(0.2, 0.8, -0.95), 0.28, {knockdown = true, camera_intensity = 0.3}],
			"heavy_boot": ["Heavy Boot", "6HK", &"fight/front_kick", 0.20, 0.0, 12, 4, 22, 100, H.MID, 22, 16, 11, Vector2(4.5, 0), Vector3(0.05, 1.0, -1.0), 0.22, {camera_intensity = 0.2}],
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
			moves.append(_save(move, dir + file + ".tres"))
		for file: String in spec.signatures:
			moves.append(_save(_make(spec.signatures[file]), dir + file + ".tres"))

		var path := "res://data/characters/%s.tres" % id
		var character := load(path) as CharacterData
		character.moves.assign(moves)
		for stat: String in spec.stats:
			if stat == "victory_animations":
				character.victory_animations.assign(spec.stats[stat])
			else:
				character.set(stat, spec.stats[stat])
		var portrait := "res://assets/ui/portraits/%s.png" % id # from tools/render_portraits.gd
		if ResourceLoader.exists(portrait):
			character.portrait = load(portrait)
		var err := ResourceSaver.save(character, path)
		print("%-7s %2d moves  err=%d" % [id, moves.size(), err])
	quit()


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
	return m


func _save(move: MoveData, path: String) -> MoveData:
	var err := ResourceSaver.save(move, path)
	assert(err == OK, "failed to save %s" % path)
	return load(path)
