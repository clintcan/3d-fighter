class_name AIController
extends FighterController
## Basic CPU opponent (CLAUDE.md §7). Produces the same packed inputs a player would and
## never touches fighter state. It perceives the opponent `reaction_frames` late, runs
## short input "plans" (walk, poke, string, dash, jump-in, throw...), and overrides them
## with reactive rules: block, punish whiffs, anti-air, juggle. Seeded RNG, so a match
## with the same inputs plays out identically.

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
var _blocking := false
var _block_dir := 4
var _moves: Dictionary = {} # input string -> MoveData, filled by attach()


func _init(level: Difficulty = Difficulty.NORMAL, seed_value: int = 1) -> void:
	set_difficulty(level)
	_rng.seed = seed_value


func set_difficulty(level: Difficulty) -> void:
	difficulty = level
	var profile: Dictionary = PROFILES[level]
	for key in profile:
		set(key, profile[key])


func difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]


func reset() -> void:
	_seen_history.clear()
	_plan.clear()
	_step_ticks_left = 0
	_rolled_attack = ""
	_rolled_punish = ""
	_blocking = false


func read(fighter: Fighter) -> int:
	_tick += 1
	_remember(fighter.opponent)
	var seen := _perceived(reaction_frames)
	var dist := _distance(fighter, seen)
	var seen_for_block := _perceived(block_reaction_frames)

	# Reactive defense overrides any plan.
	if _wants_block(fighter, seen_for_block, _distance(fighter, seen_for_block)):
		_plan.clear()
		_step_ticks_left = 0
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
		Fighter.State.JUMP:
			var approaching: bool = (seen.velocity as Vector3).dot(fighter.position - seen.position) > 0.0
			if approaching and dist < 2.0 and _rng.randf() < anti_air_chance * 0.15:
				_queue_press(HP, 2) # uppercut


## Highs whiff over a crouching target, so crouchers get a mid or a low.
func _punish(fighter: Fighter, dist: float, target_crouching: bool) -> void:
	var launcher := _move("2HP")
	if launcher and dist <= reach(launcher) and _rng.randf() < 0.6:
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
			# Close in for wake-up pressure, but don't walk into them.
			if dist > WAKEUP_SPACING:
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

	var options: Array = []
	if dist > FAR_RANGE:
		options = [
			[4.0, func() -> void: _plan.append([6, 0, _rng.randi_range(12, 28)])],
			[2.0 * aggression, func() -> void: _queue_dash()],
			[1.0 * aggression, func() -> void: _queue_jump_in()],
			[1.0 * (1.0 - aggression), func() -> void: _plan.append([5, 0, _rng.randi_range(8, 20)])],
		]
	elif dist > CLOSE_RANGE:
		options = [
			[3.0, func() -> void: _plan.append([6, 0, _rng.randi_range(6, 14)])],
			[2.0 * aggression, func() -> void: _queue_poke(dist)],
			[1.2 * aggression if _signature_in_range(dist) else 0.0, func() -> void: _queue_press(HP, 6)],
			[1.5 * aggression, func() -> void: _queue_jump_in()],
			[1.0, func() -> void: _queue_sidestep()],
			[0.6, func() -> void: _queue_backdash()],
			[1.0 * (1.0 - aggression), func() -> void: _plan.append([4, 0, _rng.randi_range(6, 14)])],
		]
	else:
		options = [
			[3.0 * aggression, func() -> void: _queue_string()],
			[1.5, func() -> void: _queue_press(LK, 2)],
			[1.0 * aggression, func() -> void: _queue_press(HK, 2)],
			[1.0, func() -> void: _queue_press(HP, 2)],
			[1.2 * aggression if dist < THROW_RANGE else 0.0, func() -> void: _queue_throw()],
			[1.5 * (1.0 - aggression), func() -> void: _plan.append([4 if _rng.randf() < 0.5 else 1, 0, _rng.randi_range(8, 18)])],
			[0.6, func() -> void: _queue_backdash()],
			[0.5, func() -> void: _queue_sidestep()],
		]
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


## Jab, then (unless the combo is "dropped") cancel into a straight.
func _queue_string() -> void:
	_queue_press(LP)
	_plan.append([5, 0, 2])
	if _rng.randf() >= combo_drop_chance:
		_queue_press(HP)


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


func _queue_dash() -> void:
	_plan.append_array([[6, 0, 2], [5, 0, 2], [6, 0, 1], [5, 0, 12]])


func _queue_backdash() -> void:
	_plan.append_array([[4, 0, 2], [5, 0, 2], [4, 0, 1], [5, 0, 14]])


func _queue_jump_in() -> void:
	_plan.append_array([[9, 0, 5], [5, 0, _rng.randi_range(9, 13)]])
	_queue_press(HK if _rng.randf() < 0.6 else HP)
	_plan.append([5, 0, 20])


func _queue_throw() -> void:
	_plan.append([5, LP | LK, 1])
	_plan.append([5, 0, 2])


func _queue_sidestep() -> void:
	_plan.append([2 if _rng.randf() < 0.5 else 5, SIDESTEP, 1])
	_plan.append([5, 0, 14])


func _next_plan_input() -> int:
	var step: Array = _plan[0]
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


## Distance (center to center) at which a move's hitbox can touch a standing opponent,
## including how far a lunge slides the attacker.
static func reach(move: MoveData) -> float:
	if move == null:
		return 0.0
	var slide := move.lunge * move.lunge / (2.0 * Fighter.GROUND_FRICTION)
	return absf(move.hitbox_offset.z) + move.hitbox_radius + Fighter.BODY_RADIUS + slide
