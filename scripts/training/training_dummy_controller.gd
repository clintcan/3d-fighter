class_name TrainingDummyController
extends FighterController
## Training-mode dummy. Holds a stance, optionally blocks (it may peek at the attacker's
## move to pick the correct height — fine for a dummy, never for the real AI), can be
## driven by the CPU AI, or replays a recording of inputs on a loop.

enum Stance { STAND, CROUCH, JUMP, CPU, PLAYBACK }
enum Guard { NONE, ALL, AFTER_FIRST_HIT, RANDOM }

const STANCE_NAMES := ["Stand", "Crouch", "Jump", "CPU", "Playback"]
const GUARD_NAMES := ["None", "Block All", "Block After First Hit", "Random"]
const STANCE_DIRS := [5, 2, 8]
## "After first hit": keep blocking this long after the last hit taken.
const GUARD_MEMORY_TICKS := 90
const MAX_RECORDING_TICKS := 600

var stance: Stance = Stance.STAND
var guard: Guard = Guard.NONE
var ai: AIController
## Recorded packed inputs (facing-relative, so they replay correctly from either side).
var recording := PackedInt32Array()

var _playback_index := 0
var _tick := 0
var _guard_ticks := 0
var _rng := RandomNumberGenerator.new()
var _rolled_attack := -1
var _random_block := false


func _init() -> void:
	_rng.seed = 7


func read(fighter: Fighter) -> int:
	_tick += 1
	if fighter.combo_hits > 0:
		_guard_ticks = GUARD_MEMORY_TICKS
	elif _guard_ticks > 0:
		_guard_ticks -= 1

	if stance == Stance.PLAYBACK and not recording.is_empty():
		var packed := recording[_playback_index]
		_playback_index = (_playback_index + 1) % recording.size()
		return packed
	if stance == Stance.CPU and ai:
		return ai.read(fighter)

	var dir: int = STANCE_DIRS[stance] if stance < STANCE_DIRS.size() else 5
	if _should_block(fighter):
		return InputBuffer.pack(_block_dir(fighter), 0)
	return InputBuffer.pack(dir, 0)


func restart_playback() -> void:
	_playback_index = 0


func _should_block(fighter: Fighter) -> bool:
	var attacker := fighter.opponent
	if not attacker.is_threatening(fighter):
		return false
	match guard:
		Guard.ALL:
			return true
		Guard.AFTER_FIRST_HIT:
			return _guard_ticks > 0
		Guard.RANDOM:
			# Roll once per attack instance, identified by the tick it started.
			var attack_id := _tick - attacker.state_frame
			if attack_id != _rolled_attack:
				_rolled_attack = attack_id
				_random_block = _rng.randf() < 0.5
			return _random_block
	return false


## Lows must be crouch-blocked, overheads stand-blocked; mids follow the stance.
func _block_dir(fighter: Fighter) -> int:
	var move := fighter.opponent.current_move
	if move == null:
		return 4
	match move.hit_level:
		MoveData.HitLevel.LOW:
			return 1
		MoveData.HitLevel.MID:
			return 1 if stance == Stance.CROUCH else 4
	return 4


func stance_name() -> String:
	return STANCE_NAMES[stance]


func guard_name() -> String:
	return GUARD_NAMES[guard]
