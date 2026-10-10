class_name TrialDemoController
extends FighterController
## "Show me": plays a combo trial on the player's fighter. It walks in close enough for
## the shortest move in the combo, stands still a moment (so the walk's forward inputs
## can't turn a later 236 into a 623), then inputs each move as soon as it can come
## out: a cancel once the previous move has connected (inputs during hitstop are
## buffered), or a link the first tick the fighter can act, walking in first if needed.
## Motion inputs are fed one direction a tick. sim_test plays every trial's demo
## against every dummy, so this also proves each trial can be done.

const BUTTONS := {"LP": InputBuffer.LP, "HP": InputBuffer.HP, "LK": InputBuffer.LK, "HK": InputBuffer.HK,
	"P": InputBuffer.LP, "K": InputBuffer.LK}

var steps: PackedStringArray
var index := 0 # the next step to perform
var target: Fighter
var _queue: Array[int] = []
var _still := 0 # ticks since the last walking input
var _wait := 0 # neutral ticks before trying again (a missed motion mustn't run into the next)


func _init(trial_steps: PackedStringArray, dummy: Fighter) -> void:
	steps = trial_steps
	target = dummy


## Every step has been performed.
func finished() -> bool:
	return index >= steps.size()


## The player's fighter started `move` (connect to Fighter.attack_started).
func move_started(move: MoveData) -> void:
	if not finished() and steps[index] == move.input:
		index += 1
		_queue.clear()
		_wait = 0


func read(fighter: Fighter) -> int:
	if finished():
		return InputBuffer.pack(InputBuffer.NEUTRAL, 0)
	if steps[index] == "WALL":
		if target.state == Fighter.State.WALL_SPLAT or target.wall_used:
			index += 1
		return InputBuffer.pack(InputBuffer.NEUTRAL, 0)
	if not _queue.is_empty():
		return _queue.pop_front()
	if _wait > 0:
		_wait -= 1
		return InputBuffer.pack(InputBuffer.NEUTRAL, 0)
	var move := fighter._move_for_input(steps[index])
	if move == null:
		index = steps.size() # not this fighter's move: give up
		return InputBuffer.pack(InputBuffer.NEUTRAL, 0)
	if fighter.is_actionable():
		var gap := Vector2(target.position.x - fighter.position.x, target.position.z - fighter.position.z).length()
		var wanted := _opening_range(fighter) if index == 0 else strike_range(move) - 0.05
		if gap > wanted:
			_still = 0
			return InputBuffer.pack(6, 0) # walk in
		if index == 0 and _still < Fighter.MOTION_WINDOW + 2:
			_still += 1
			return InputBuffer.pack(InputBuffer.NEUTRAL, 0)
		_queue = sequence(steps[index])
	elif fighter.state == Fighter.State.ATTACK and fighter.move_has_hit and can_cancel(fighter, move):
		# Time the press for the end of hitstop: a press older than the buffer window
		# is gone by the time the fighter can cancel.
		var inputs := sequence(steps[index])
		if fighter.hitstop > inputs.size() - 2:
			return InputBuffer.pack(InputBuffer.NEUTRAL, 0)
		_queue = inputs
	else:
		return InputBuffer.pack(InputBuffer.NEUTRAL, 0)
	if _queue.size() > 2:
		_wait = Fighter.MOTION_WINDOW # if this motion doesn't come out, let it clear first
	return _queue.pop_front()


## The engine's cancel rules (Fighter._try_attack / _try_special): a normal into one of
## its cancel_into moves, a normal into a special, or a special into the super, within
## the special cancel window.
static func can_cancel(fighter: Fighter, move: MoveData) -> bool:
	var current := fighter.current_move
	if current == null:
		return false
	if not move.is_special():
		return move.input in current.cancel_into
	var since_active := fighter.state_frame - current.startup - current.active
	if current.super_move or since_active > Fighter.SPECIAL_CANCEL_WINDOW or fighter.position.y > 0.0:
		return false
	return not current.is_special() or move.super_move


## How far `move` reaches without counting its lunge (projectiles: their whole flight).
static func strike_range(move: MoveData) -> float:
	if move.projectile_speed > 0.0 or move.command_grab:
		return AIController.reach(move)
	return absf(move.hitbox_offset.z) + move.hitbox_radius + Fighter.BODY_RADIUS


## Where to start the combo: inside the shortest reach of its moves, so the pushback of
## the first hits doesn't carry the dummy out of range of the later ones.
func _opening_range(fighter: Fighter) -> float:
	var shortest := INF
	for step in steps:
		var move := fighter._move_for_input(step)
		if move and move.projectile_speed <= 0.0:
			shortest = minf(shortest, strike_range(move))
	return maxf(shortest - 0.25, Fighter.PUSHBOX_RADIUS * 2.0 + 0.05) if shortest < INF else 1.0


## Packed inputs for a move input: its directions one tick each, the button on the last,
## then a tick with the button let go (the buffer only counts fresh presses).
static func sequence(input: String) -> Array[int]:
	var digits := ""
	var i := 0
	while i < input.length() and input[i].is_valid_int():
		digits += input[i]
		i += 1
	var button: int = BUTTONS.get(input.substr(i), 0)
	if digits == "":
		digits = "5"
	var out: Array[int] = []
	for d in digits.length():
		out.append(InputBuffer.pack(int(digits[d]), button if d == digits.length() - 1 else 0))
	out.append(InputBuffer.pack(int(digits[-1]), 0))
	return out
