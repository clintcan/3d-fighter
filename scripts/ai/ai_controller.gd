class_name AIController
extends FighterController
## Basic CPU opponent (CLAUDE.md §7). Produces the same packed inputs a player would and
## never touches fighter state. It perceives the opponent `reaction_frames` late, runs
## short input "plans" (walk, poke, string, dash, jump-in, throw, specials by motion
## input...), and overrides them with reactive rules: block (projectiles too), punish
## whiffs (with the super when the meter is full), anti-air, juggle. Seeded RNG, so a
## match with the same inputs plays out identically.
## Each character also has a personality (PERSONALITIES, picked in attach()) layered on
## the difficulty: a preferred fighting range it steers toward, skill bonuses, weights on
## its options, how often it keeps pressure on a blocking opponent, and how far it
## reaches to punish a whiff.
## A power-up stance (a special with focus_gain, Mira's Lakas Stance) is never picked as
## an attack: the CPU uses it on purpose, at range and while the opponent is knocked
## down, weighted by the personality's `stance`.
## A reversal stance (Lian's Still Water) is never an attack either: the CPU uses it
## against attacks it sees coming early enough, against jump-ins and as a read up close
## (the personality's `reversal`), and every CPU throws, goes low or waits against one.

enum Difficulty { EASY, NORMAL, HARD }

const DIFFICULTY_NAMES := ["Easy", "Normal", "Hard"]
const PROFILES := {
	Difficulty.EASY: {
		reaction_frames = 22, block_reaction_frames = 12, decision_interval = 16, block_chance = 0.25, punish_chance = 0.2,
		anti_air_chance = 0.2, combo_drop_chance = 0.5, aggression = 0.35,
	},
	Difficulty.NORMAL: {
		reaction_frames = 14, block_reaction_frames = 7, decision_interval = 10, block_chance = 0.55, punish_chance = 0.5,
		anti_air_chance = 0.45, combo_drop_chance = 0.25, aggression = 0.55,
	},
	Difficulty.HARD: {
		reaction_frames = 8, block_reaction_frames = 4, decision_interval = 6, block_chance = 0.8, punish_chance = 0.85,
		anti_air_chance = 0.75, combo_drop_chance = 0.05, aggression = 0.75,
	},
}

const LP := InputBuffer.LP
const HP := InputBuffer.HP
const LK := InputBuffer.LK
const HK := InputBuffer.HK
const SIDESTEP := InputBuffer.SIDESTEP
const FAR_RANGE := 2.2
const CLOSE_RANGE := 1.2
const THROW_RANGE := 0.9
const WAKEUP_SPACING := 1.4
## How far from the preferred range before the AI steers back toward it.
const SPACING_SLACK := 0.5

## Option weight keys: fireball, rush (travelling special), dash, jump, throw, grab
## (command grab), ground_special (214), poke, string, sidestep, wait (stand / walk
## back), retreat and approach (steering toward the preferred range). Missing keys
## count as 1.0.
## Bonuses add to the difficulty profile's chances / aggression.
const PERSONALITIES := {
	&"kenji": {
		name = "Zoner", blurb = "keeps you at range with fireballs and anti-airs", preferred_range = 2.6,
		aggression = -0.05, block = 0.05, punish = 0.0, anti_air = 0.25,
		rising_anti_air = 0.9, pressure = 0.2, far_punish = 0.0,
		weights = {fireball = 2.5, rush = 0.6, dash = 0.5, jump = 0.5, throw = 0.8,
			poke = 1.3, retreat = 1.8, approach = 0.6},
	},
	&"rhea": {
		name = "Rushdown", blurb = "dashes in and never lets up the pressure", preferred_range = 0.9,
		aggression = 0.25, block = -0.1, punish = 0.0, anti_air = -0.1,
		rising_anti_air = 0.5, pressure = 0.75, far_punish = 0.3,
		weights = {rush = 2.0, dash = 2.4, jump = 1.6, throw = 1.8, string = 1.5,
			sidestep = 0.6, wait = 0.3, retreat = 0.2, approach = 1.8},
	},
	&"valka": {
		name = "Grappler", blurb = "walks you down and grabs you if you just block", preferred_range = 0.8,
		aggression = 0.05, block = 0.1, punish = 0.05, anti_air = 0.15,
		rising_anti_air = 0.8, pressure = 0.55, far_punish = 0.0,
		weights = {grab = 2.5, approach = 2.0, dash = 0.6, jump = 0.5, throw = 1.5, poke = 0.9,
			wait = 0.6, retreat = 0.3, sidestep = 0.6},
	},
	&"jin": {
		name = "Footsies", blurb = "keeps you at kick range and punishes every step in", preferred_range = 1.9,
		aggression = 0.0, block = 0.1, punish = 0.15, anti_air = 0.2,
		rising_anti_air = 0.85, pressure = 0.3, far_punish = 0.6,
		weights = {poke = 2.4, rush = 1.4, retreat = 1.3, approach = 1.0, dash = 0.6, jump = 0.4,
			throw = 0.7, string = 0.7, sidestep = 0.8},
	},
	&"mira": {
		name = "Brawler", blurb = "powers up when you give her room, then rushes you down", preferred_range = 1.0,
		aggression = 0.15, block = 0.0, punish = 0.05, anti_air = 0.1,
		rising_anti_air = 0.7, pressure = 0.5, far_punish = 0.4,
		weights = {stance = 2.0, rush = 1.6, string = 1.6, dash = 1.4, jump = 1.0, approach = 1.5,
			poke = 1.0, wait = 0.4, retreat = 0.4},
	},
	&"lian": {
		name = "Counter", blurb = "waits for you to swing, then turns it into a throw", preferred_range = 1.3,
		aggression = -0.15, block = 0.1, punish = 0.1, anti_air = 0.15,
		rising_anti_air = 0.0, pressure = 0.35, far_punish = 0.2, reversal = 0.35,
		weights = {reversal = 1.0, glide = 1.5, poke = 1.2, string = 1.4, wait = 1.8, approach = 1.0,
			retreat = 0.6, jump = 0.4, dash = 0.6, throw = 1.0},
	},
	&"brutus": {
		name = "Punisher", blurb = "waits patiently, then punishes every mistake", preferred_range = 1.6,
		aggression = -0.2, block = 0.15, punish = 0.2, anti_air = 0.0,
		rising_anti_air = 0.0, pressure = 0.2, far_punish = 0.85,
		weights = {rush = 0.5, dash = 0.3, jump = 0.4, throw = 1.2, ground_special = 2.0,
			poke = 0.8, string = 0.8, wait = 2.4, retreat = 0.6, approach = 0.7},
	},
}
const DEFAULT_PERSONALITY := {
	name = "Balanced", blurb = "a bit of everything", preferred_range = 1.6,
	aggression = 0.0, block = 0.0, punish = 0.0, anti_air = 0.0,
	rising_anti_air = 0.6, pressure = 0.3, far_punish = 0.3, weights = {},
}
## Distance at which an incoming projectile may be jumped over instead of blocked.
const PROJECTILE_JUMP_RANGE := 2.6
## Ticks from deciding on a reversal until its stance catches (the 214 motion plus the
## stance's startup), and the latest an attack may land for the stance to still be up.
const REVERSAL_LEAD := 6
const REVERSAL_LATEST := 18
## A power-up stance is only used from at least this far away.
const STANCE_MIN_DISTANCE := 2.4

var difficulty: Difficulty = Difficulty.NORMAL
var reaction_frames := 14
## Blocking reads attack startups faster than general decisions (players block partly
## on anticipation), so it uses its own, shorter delay.
var block_reaction_frames := 7
var decision_interval := 10
var block_chance := 0.55
var punish_chance := 0.5
var anti_air_chance := 0.45
var combo_drop_chance := 0.25
var aggression := 0.55

var _rng := RandomNumberGenerator.new()
var _tick := 0
## Opponent snapshots, newest last; the AI acts on the one `reaction_frames` old.
var _seen_history: Array[Dictionary] = []
## Queued input steps: [numpad dir, buttons, ticks]. Buttons are held for the step's
## first tick only, so consecutive presses register as fresh presses.
var _plan: Array = []
var _step_ticks_left := 0
## Attack instance (move + start tick) already rolled for blocking, and the outcome.
var _rolled_attack := ""
var _rolled_punish := ""
var _rolled_reversal := ""
var _blocking := false
var _block_dir := 4
var _block_level: MoveData.HitLevel = MoveData.HitLevel.MID
## Projectile already rolled for (instance id) and whether to jump it.
var _rolled_projectile := 0
var _moves: Dictionary = {} # input string -> MoveData, filled by attach()
## The attached character's personality (DEFAULT_PERSONALITY until attach()).
var personality: Dictionary = DEFAULT_PERSONALITY
var _rolled_pressure := ""
## Recent output directions, newest last (to avoid accidental double-tap dashes).
var _recent_dirs: Array[int] = []
## True while the current plan step is part of an intended dash / backdash.
var _dashing := false
var _wary_of: CharacterData # the opponent _opponent_has_reversal was looked up for
var _opponent_has_reversal := false


func _init(level: Difficulty = Difficulty.NORMAL, seed_value: int = 1) -> void:
	set_difficulty(level)
	_rng.seed = seed_value


func set_difficulty(level: Difficulty) -> void:
	difficulty = level
	_apply_profile()


## Difficulty profile plus the personality's bonuses.
func _apply_profile() -> void:
	var profile: Dictionary = PROFILES[difficulty]
	for key in profile:
		set(key, profile[key])
	aggression = clampf(aggression + personality.aggression, 0.05, 0.95)
	block_chance = clampf(block_chance + personality.block, 0.0, 0.95)
	punish_chance = clampf(punish_chance + personality.punish, 0.0, 0.95)
	anti_air_chance = clampf(anti_air_chance + personality.anti_air, 0.0, 0.95)


func personality_name() -> String:
	return personality.name


## Personality weight for an option kind.
func _w(kind: String) -> float:
	return (personality.weights as Dictionary).get(kind, 1.0)


func difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]


func reset() -> void:
	_seen_history.clear()
	_plan.clear()
	_step_ticks_left = 0
	_rolled_attack = ""
	_rolled_punish = ""
	_rolled_reversal = ""
	_blocking = false
	_rolled_projectile = 0
	_rolled_pressure = ""
	_recent_dirs.clear()
	_dashing = false


func read(fighter: Fighter) -> int:
	var packed := _choose_input(fighter)
	return _without_accidental_dash(packed)


func _choose_input(fighter: Fighter) -> int:
	_tick += 1
	_dashing = false
	_remember(fighter.opponent)
	var seen := _perceived(reaction_frames)
	var dist := _distance(fighter, seen)
	var seen_for_block := _perceived(block_reaction_frames)

	# Reactive defense overrides any plan.
	if _try_reversal(fighter, seen, dist):
		return _next_plan_input()
	if _wants_block_projectile(fighter):
		_plan.clear()
		_step_ticks_left = 0
		return InputBuffer.pack(4, 0)
	if _wants_block(fighter, seen_for_block, _distance(fighter, seen_for_block)):
		_plan.clear()
		_step_ticks_left = 0
		var level: MoveData.HitLevel = seen_for_block.move.hit_level if seen_for_block.move else MoveData.HitLevel.MID
		_block_level = level
		return InputBuffer.pack(_block_dir, 0)

	if not _plan.is_empty():
		return _next_plan_input()

	if fighter.is_actionable() and _tick % decision_interval == 0:
		_decide(fighter, seen, dist)
	elif fighter.is_actionable():
		_react(fighter, seen, dist) # punishes/anti-airs/juggles don't wait for the interval
	if not _plan.is_empty():
		return _next_plan_input()
	return InputBuffer.pack(InputBuffer.NEUTRAL, 0)


# --- Perception ------------------------------------------------------------------

func _remember(opponent: Fighter) -> void:
	_seen_history.append({
		state = opponent.state,
		state_frame = opponent.state_frame,
		move = opponent.current_move,
		position = opponent.position,
		velocity = opponent.velocity,
		crouching = opponent.crouching,
		start_tick = _tick - opponent.state_frame,
	})
	if _seen_history.size() > maxi(reaction_frames, block_reaction_frames) + 1:
		_seen_history.pop_front()


## Opponent snapshot from `frames_ago` ticks back (or the oldest available).
func _perceived(frames_ago: int) -> Dictionary:
	return _seen_history[maxi(0, _seen_history.size() - 1 - frames_ago)]


func _distance(fighter: Fighter, seen: Dictionary) -> float:
	var delta: Vector3 = seen.position - fighter.position
	return Vector2(delta.x, delta.z).length()


func _attack_id(seen: Dictionary) -> String:
	var move: MoveData = seen.move
	return "%s@%d" % [move.resource_path if move else "", seen.start_tick]


func _attack_phase(seen: Dictionary) -> String:
	if seen.state != Fighter.State.ATTACK or seen.move == null:
		return ""
	var move: MoveData = seen.move
	if seen.state_frame <= move.startup + move.active:
		return "threat"
	return "recovery"


# --- Reactive rules --------------------------------------------------------------

func _wants_block(fighter: Fighter, seen: Dictionary, dist: float) -> bool:
	if fighter.state == Fighter.State.BLOCKSTUN:
		return _blocking # keep holding block through blockstun
	if not fighter.is_actionable():
		return false
	if _attack_phase(seen) != "threat":
		_blocking = false
		return false
	var move: MoveData = seen.move
	if dist > reach(move) + 0.4:
		return false
	var attack_id := _attack_id(seen)
	if attack_id != _rolled_attack:
		_rolled_attack = attack_id
		_blocking = _rng.randf() < block_chance
		match move.hit_level:
			MoveData.HitLevel.LOW:
				_block_dir = 1
			MoveData.HitLevel.HIGH, MoveData.HitLevel.OVERHEAD:
				_block_dir = 4
			_:
				_block_dir = 4 if _rng.randf() < 0.5 else 1
	return _blocking


## Incoming fireball: rolled once per projectile, either jumped over (from range) or
## blocked when it gets close.
func _wants_block_projectile(fighter: Fighter) -> bool:
	var p := fighter.opponent.projectile
	if p == null or not fighter.is_actionable() and fighter.state != Fighter.State.BLOCKSTUN:
		return false
	var to_me := fighter.position - p.position
	to_me.y = 0.0
	if to_me.dot(p.direction) < 0.0:
		return false # already past
	var id := p.get_instance_id()
	if id != _rolled_projectile:
		_rolled_projectile = id
		var immune := _special_any(func(m: MoveData) -> bool: return m.projectile_immune and not m.super_move)
		if immune and to_me.length() < reach(immune) + 2.0 and fighter.is_actionable() and _rng.randf() < 0.5:
			_blocking = false
			_plan.clear()
			_queue_special(immune) # spin straight through it
			return false
		_blocking = _rng.randf() < minf(block_chance + 0.2, 0.95)
		if not _blocking and to_me.length() > PROJECTILE_JUMP_RANGE * 0.7 and _rng.randf() < anti_air_chance:
			_plan.clear()
			_plan.append_array([[9, 0, 5], [5, 0, 30]]) # jump over it
	return _blocking and p.is_threatening(fighter)


## Walking or blocking back and forth with a neutral tick in between reads as a
## double tap (dash / backdash). Unless the plan means to dash, hold neutral that tick
## instead of walking, and crouch-block instead of a standing block (highs whiff over a
## crouch anyway; overheads still get the standing block).
func _without_accidental_dash(packed: int) -> int:
	var dir := packed & 0xF
	if (dir == 6 or dir == 4) and not _dashing and _would_double_tap(dir):
		var blocking := dir == 4 and _blocking
		if blocking and _block_level != MoveData.HitLevel.OVERHEAD:
			dir = 1
		elif not blocking:
			dir = InputBuffer.NEUTRAL
		packed = (packed & ~0xF) | dir
	_recent_dirs.append(dir)
	if _recent_dirs.size() > Fighter.DOUBLE_TAP_WINDOW + 1:
		_recent_dirs.pop_front()
	return packed


func _would_double_tap(dir: int) -> bool:
	if _recent_dirs.is_empty() or _recent_dirs[-1] != InputBuffer.NEUTRAL:
		return false
	for i in range(_recent_dirs.size() - 2, -1, -1):
		if _recent_dirs[i] == dir:
			return true
		if _recent_dirs[i] != InputBuffer.NEUTRAL:
			return false
	return false


## Opportunities that don't wait for the decision interval.
func _react(fighter: Fighter, seen: Dictionary, dist: float) -> void:
	match seen.state:
		Fighter.State.ATTACK:
			# Roll once per whiffed/blocked attack, as soon as its recovery is seen.
			var attack_id := _attack_id(seen)
			if _attack_phase(seen) == "recovery" and attack_id != _rolled_punish:
				_rolled_punish = attack_id
				if _rng.randf() < punish_chance:
					_punish(fighter, dist, seen.crouching)
		Fighter.State.AIR_HIT:
			if dist < 1.5 and seen.position.y < 1.4:
				_queue_press(HK if _rng.randf() < 0.5 else HP)
		Fighter.State.BLOCKSTUN:
			# Pressure: keep attacking a blocking opponent (frame traps, a low, or a throw
			# as they come out of blockstun). Rolled once per blockstun.
			var block_id := "b%d" % seen.start_tick
			if dist < CLOSE_RANGE + 0.3 and block_id != _rolled_pressure:
				_rolled_pressure = block_id
				if _rng.randf() < personality.pressure:
					_queue_pressure(dist)
		Fighter.State.JUMP:
			var approaching: bool = (seen.velocity as Vector3).dot(fighter.position - seen.position) > 0.0
			var reversal := _reversal_move()
			if reversal and approaching and dist < 1.8 and (seen.velocity as Vector3).y < 0.0 					and _rng.randf() < anti_air_chance * 0.3 * personality.get("reversal", 0.0):
				_queue_special(reversal) # catch the jump-in
			elif approaching and dist < 2.0 and _rng.randf() < anti_air_chance * 0.15:
				var rising := _special_with(func(m: MoveData) -> bool: return (m.rise > 0.0 or m.projectile_immune) and not m.super_move)
				if rising and _rng.randf() < personality.rising_anti_air:
					_queue_special(rising) # invincible rising anti-air
				else:
					_queue_press(HP, 2) # uppercut


## Highs whiff over a crouching target, so crouchers get a mid or a low. A full meter
## goes into the super when it reaches.
func _punish(fighter: Fighter, dist: float, target_crouching: bool) -> void:
	var super_move := _special_with(func(m: MoveData) -> bool: return m.super_move)
	var launcher := _move("2HP")
	var rush := _special_with(func(m: MoveData) -> bool: return (m.travel > 0.0 or m.lunge > 0.0) and m.rise == 0.0 and not m.super_move)
	if super_move and fighter.meter >= Fighter.MAX_METER and dist <= reach(super_move) and _rng.randf() < 0.8:
		_queue_special(super_move)
	elif rush and dist > reach(_move("HK")) and dist <= reach(rush) and _rng.randf() < personality.far_punish:
		_queue_special(rush) # whiff punish from long range
	elif launcher and dist <= reach(launcher) and _rng.randf() < 0.6:
		_queue_press(HP, 2)
	elif target_crouching:
		if dist <= reach(_move("LK")):
			_queue_press(LK)
		elif dist <= reach(_move("2LK")):
			_queue_press(LK, 2)
	elif dist <= reach(_move("LP")):
		_queue_string()
	elif dist <= reach(_move("HK")):
		_queue_press(HK)


# --- Decisions -------------------------------------------------------------------

func _decide(fighter: Fighter, seen: Dictionary, dist: float) -> void:
	match seen.state:
		Fighter.State.KNOCKDOWN, Fighter.State.GETUP:
			# Power up while they're down (from a safe distance), or close in for wake-up
			# pressure without walking into them.
			var down_stance := _stance(fighter)
			if down_stance and seen.state == Fighter.State.KNOCKDOWN and dist > CLOSE_RANGE \
					and _rng.randf() < 0.35 * _w("stance"):
				_queue_special(down_stance)
			elif dist > WAKEUP_SPACING:
				_plan.append([6, 0, 6])
			return
		Fighter.State.ATTACK:
			if _attack_phase(seen) == "recovery":
				_react(fighter, seen, dist)
				if not _plan.is_empty():
					return
		Fighter.State.AIR_HIT:
			_react(fighter, seen, dist)
			return
	if _attack_phase(seen) == "threat" and (seen.move as MoveData).reversal:
		# Never strike into a reversal stance: throw it, go low, or wait it out.
		if dist < THROW_RANGE:
			_queue_throw()
		elif dist <= reach(_move("2LK")):
			_queue_press(LK, 2)
		else:
			_plan.append([5, 0, 10])
		return

	var options: Array = []
	var projectile_move := _special_with(func(m: MoveData) -> bool: return m.projectile_speed > 0.0)
	var rush := _special_with(func(m: MoveData) -> bool: return (m.travel > 0.0 or m.lunge > 0.0) and m.rise == 0.0 and not m.super_move)
	var ground_special := _special_with(func(m: MoveData) -> bool: return m.motion() == "214")
	var grab := _special_with(func(m: MoveData) -> bool: return m.command_grab and not m.super_move)
	var can_fireball := projectile_move != null and fighter.projectile == null
	var stance := _stance(fighter)
	var reversal := _reversal_move()
	var glide := _special_any(func(m: MoveData) -> bool: return m.projectile_immune and m.travel > 0.0 and not _is_attack(m))
	if dist > FAR_RANGE:
		options = [
			[2.5 * _w("fireball") if can_fireball else 0.0, func() -> void: _queue_special(projectile_move)],
			[1.0 * _w("stance") if stance else 0.0, func() -> void: _queue_special(stance)],
			[1.0 * aggression * _w("rush") if rush and dist <= reach(rush) else 0.0, func() -> void: _queue_special(rush)],
			[4.0 * _w("approach"), func() -> void: _plan.append([6, 0, _rng.randi_range(12, 28)])],
			[1.0 * _w("glide") if glide else 0.0, func() -> void: _queue_special(glide)],
			[2.0 * aggression * _w("dash"), func() -> void: _queue_dash()],
			[1.0 * aggression * _w("jump"), func() -> void: _queue_jump_in()],
			[1.0 * (1.0 - aggression) * _w("wait"), func() -> void: _plan.append([5, 0, _rng.randi_range(8, 20)])],
		]
	elif dist > CLOSE_RANGE:
		options = [
			[3.0 * _w("approach"), func() -> void: _plan.append([6, 0, _rng.randi_range(6, 14)])],
			[2.0 * aggression * _w("poke"), func() -> void: _queue_poke(dist)],
			[1.2 * aggression if _signature_in_range(dist) else 0.0, func() -> void: _queue_press(HP, 6)],
			[1.0 * aggression * _w("rush") if rush and dist <= reach(rush) else 0.0, func() -> void: _queue_special(rush)],
			[0.8 * _w("fireball") if can_fireball else 0.0, func() -> void: _queue_special(projectile_move)],
			[1.5 * aggression * _w("jump"), func() -> void: _queue_jump_in()],
			[1.0 * _w("sidestep"), func() -> void: _queue_sidestep()],
			[0.6 * _w("retreat"), func() -> void: _queue_backdash()],
			[1.0 * (1.0 - aggression) * _w("wait"), func() -> void: _plan.append([4, 0, _rng.randi_range(6, 14)])],
		]
	else:
		# Against a fighter with a reversal stance: more lows and throws, fewer big swings.
		var wary := 1.0 if _opponent_reverses(fighter) else 0.0
		options = [
			[3.0 * aggression * _w("string") * (1.0 - 0.4 * wary), func() -> void: _queue_string()],
			[1.5 * (1.0 + wary), func() -> void: _queue_press(LK, 2)],
			[1.0 * aggression * (1.0 + 0.5 * wary), func() -> void: _queue_press(HK, 2)],
			[1.0 * (1.0 - 0.5 * wary), func() -> void: _queue_press(HP, 2)],
			[0.8 * aggression * _w("ground_special") * (1.0 + wary) if ground_special and dist <= reach(ground_special) else 0.0, func() -> void: _queue_special(ground_special)],
			[1.2 * aggression * _w("throw") * (1.0 + wary) if dist < THROW_RANGE else 0.0, func() -> void: _queue_throw()],
			[1.0 * aggression * _w("grab") if grab and dist < grab.grab_range - 0.05 else 0.0, func() -> void: _queue_special(grab)],
			[1.5 * (1.0 - aggression) * _w("wait"), func() -> void: _plan.append([4 if _rng.randf() < 0.5 else 1, 0, _rng.randi_range(8, 18)])],
			[0.6 * _w("retreat"), func() -> void: _queue_backdash()],
			[0.5 * _w("sidestep"), func() -> void: _queue_sidestep()],
			[1.0 * _w("reversal") * personality.get("reversal", 0.0) if reversal else 0.0, func() -> void: _queue_special(reversal)],
		]
	# Steer toward the personality's preferred range (unless backed into the ropes).
	var preferred: float = personality.preferred_range
	if dist < preferred - SPACING_SLACK and not fighter.is_pinned_against_bounds(-fighter.forward):
		options.append([2.5 * _w("retreat"), func() -> void: _plan.append([4, 0, _rng.randi_range(10, 20)])])
		options.append([0.8 * _w("retreat"), func() -> void: _queue_backdash()])
	elif dist > preferred + SPACING_SLACK:
		options.append([2.0 * _w("approach"), func() -> void: _plan.append([6, 0, _rng.randi_range(8, 16)])])
	_pick(options).call()


func _pick(options: Array) -> Callable:
	var total := 0.0
	for option in options:
		total += option[0]
	var roll := _rng.randf() * total
	for option in options:
		roll -= option[0]
		if roll <= 0.0:
			return option[1]
	return options[-1][1]


# --- Plans -----------------------------------------------------------------------

func _queue_press(button: int, dir: int = 5) -> void:
	_plan.append([dir, button, 1])
	_plan.append([dir, 0, 2])


## Jab, then (unless the combo is "dropped") cancel into a straight, or sometimes into
## a special.
func _queue_string() -> void:
	_queue_press(LP)
	_plan.append([5, 0, 2])
	if _rng.randf() < combo_drop_chance:
		return
	var finisher := _special_with(func(m: MoveData) -> bool: return not m.super_move and m.projectile_speed == 0.0 and m.rise == 0.0)
	if finisher and _rng.randf() < 0.3:
		_queue_special(finisher, false)
	else:
		_queue_press(HP)


## Inputs a motion special: one tick per direction, the button with the last one.
func _queue_special(move: MoveData, recover := true) -> void:
	var motion := move.motion()
	var suffix := move.input.substr(motion.length())
	var button: int = HP if suffix == "P" else HK if suffix == "K" else InputBuffer.BUTTON_NAMES.find_key(suffix)
	for i in motion.length():
		_plan.append([int(motion[i]), button if i == motion.length() - 1 else 0, 1])
	if recover:
		_plan.append([5, 0, 3])


## First attacking special (motion input) of this character matching `test`, or null.
## Stances (power-up, reversal) and moves without a hitbox aren't attacks.
func _special_with(test: Callable) -> MoveData:
	for move: MoveData in _moves.values():
		if move.is_special() and _is_attack(move) and test.call(move):
			return move
	return null


## First special of any kind matching `test`, or null.
func _special_any(test: Callable) -> MoveData:
	for move: MoveData in _moves.values():
		if move.is_special() and test.call(move):
			return move
	return null


static func _is_attack(move: MoveData) -> bool:
	return move.focus_gain == 0 and not move.reversal 			and (move.hitbox_radius > 0.0 or move.projectile_speed > 0.0 or move.command_grab)


## True if the opponent has a reversal stance (looked up once per opponent).
func _opponent_reverses(fighter: Fighter) -> bool:
	var data := fighter.opponent.data
	if data != _wary_of:
		_wary_of = data
		_opponent_has_reversal = data.moves.any(func(m: MoveData) -> bool: return m.reversal)
	return _opponent_has_reversal


## This character's reversal stance (not a super), or null.
func _reversal_move() -> MoveData:
	return _special_any(func(m: MoveData) -> bool: return m.reversal and not m.super_move)


## Against an attack seen early enough (and not a low), sometimes answer with the
## reversal stance instead of blocking. Seen with the general reaction delay, not the
## quicker blocking one: entering a motion on reaction is slower than holding back, so
## only slow attacks can be reversed on sight (the rest takes a read). Rolled once per
## attack. True if it was queued.
func _try_reversal(fighter: Fighter, seen: Dictionary, dist: float) -> bool:
	var reversal := _reversal_move()
	if reversal == null or not fighter.is_actionable() or _attack_phase(seen) != "threat":
		return false
	var move: MoveData = seen.move
	if move.hit_level == MoveData.HitLevel.LOW or move.reversal or dist > reach(move) + 0.4:
		return false
	var attack_id := _attack_id(seen)
	if attack_id == _rolled_reversal:
		return false
	_rolled_reversal = attack_id
	var lands_in: int = move.startup + 1 - (seen.state_frame + reaction_frames)
	if lands_in < REVERSAL_LEAD or lands_in > REVERSAL_LATEST or _rng.randf() >= personality.get("reversal", 0.0):
		return false
	_plan.clear()
	_step_ticks_left = 0
	_queue_special(reversal)
	return true


## The fighter's power-up stance while it can still gain focus and it's safe to take the
## time (no fireball in the air, the opponent not close), or null.
func _stance(fighter: Fighter) -> MoveData:
	if fighter.focus >= Fighter.MAX_FOCUS or fighter.opponent.projectile != null:
		return null
	if fighter.position.distance_to(fighter.opponent.position) < STANCE_MIN_DISTANCE:
		return null
	for move: MoveData in _moves.values():
		if move.focus_gain > 0:
			return move
	return null


## The longest-reaching standing poke that can hit at this distance.
func _queue_poke(dist: float) -> void:
	for input in ["HK", "LK", "HP", "LP"]:
		var move := _move(input)
		if move and dist <= reach(move):
			_queue_press(InputBuffer.BUTTON_NAMES.find_key(input))
			return
	_plan.append([6, 0, 8])


## The forward+HP signature move, if this character has one that reaches.
func _signature_in_range(dist: float) -> bool:
	var move := _move("6HP")
	return move != null and dist <= reach(move)


## Dash steps carry a 4th element (true) so the accidental-dash filter lets them through.
func _queue_dash() -> void:
	_plan.append_array([[6, 0, 2, true], [5, 0, 2, true], [6, 0, 1, true], [5, 0, 12]])


func _queue_backdash() -> void:
	_plan.append_array([[4, 0, 2, true], [5, 0, 2, true], [4, 0, 1, true], [5, 0, 14]])


func _queue_jump_in() -> void:
	_plan.append_array([[9, 0, 5], [5, 0, _rng.randi_range(9, 13)]])
	_queue_press(HK if _rng.randf() < 0.6 else HP)
	_plan.append([5, 0, 20])


## Pressure on a blocking opponent: a quick jab (frame trap), a low, a throw, or a
## command grab as they come out of blockstun.
func _queue_pressure(dist: float) -> void:
	var roll := _rng.randf()
	var grab := _special_with(func(m: MoveData) -> bool: return m.command_grab and not m.super_move)
	if grab and dist < grab.grab_range and roll < 0.25 * _w("grab"):
		_plan.append([5, 0, 3]) # let blockstun end: grabs can't catch a blocking opponent
		_queue_special(grab)
	elif dist < THROW_RANGE and roll < 0.35 * _w("throw"):
		_queue_throw()
	elif roll < 0.65:
		_queue_press(LP)
	else:
		_queue_press(LK, 2)


func _queue_throw() -> void:
	_plan.append([5, LP | LK, 1])
	_plan.append([5, 0, 2])


func _queue_sidestep() -> void:
	_plan.append([2 if _rng.randf() < 0.5 else 5, SIDESTEP, 1])
	_plan.append([5, 0, 14])


func _next_plan_input() -> int:
	var step: Array = _plan[0]
	_dashing = step.size() > 3 and step[3]
	var first_tick := _step_ticks_left == 0
	if first_tick:
		_step_ticks_left = step[2]
	_step_ticks_left -= 1
	var buttons: int = step[1] if first_tick else 0
	if _step_ticks_left <= 0:
		_plan.pop_front()
		_step_ticks_left = 0
	return InputBuffer.pack(step[0], buttons)


# --- Move data -------------------------------------------------------------------

func _move(input: String) -> MoveData:
	return _moves.get(input)


## Called once the fighter is known, to index its moves.
func attach(fighter: Fighter) -> void:
	_moves.clear()
	for move in fighter.data.moves:
		_moves[move.input] = move
	personality = PERSONALITIES.get(fighter.data.id, DEFAULT_PERSONALITY)
	_apply_profile()


## Distance (center to center) at which a move's hitbox can touch a standing opponent,
## including how far a lunge slides the attacker.
static func reach(move: MoveData) -> float:
	if move == null:
		return 0.0
	if move.command_grab:
		return move.grab_range
	if move.projectile_speed > 0.0:
		return move.projectile_speed * move.projectile_lifetime * Fighter.DT
	var slide := move.lunge * move.lunge / (2.0 * Fighter.GROUND_FRICTION)
	slide += move.travel * move.active * Fighter.DT
	return absf(move.hitbox_offset.z) + move.hitbox_radius + Fighter.BODY_RADIUS + slide
