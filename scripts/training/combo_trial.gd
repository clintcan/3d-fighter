class_name ComboTrial
extends RefCounted
## Checks one combo trial (CharacterData.combo_trials): the player must land every step
## in order in one combo on the dummy. Steps are move inputs ("LP", "2HP", "236P"...)
## plus "WALL" for a wall splat. A multi-hit move counts once, a super's "~" finisher is
## part of the super, and a wrong move or a dropped combo starts the trial over.
## TrainingMode feeds it the fight's events.

signal progressed(index: int)
signal completed
signal dropped

var trial: Dictionary
var steps: PackedStringArray
var progress := 0
var done := false

var _instance := 0
var _started := {} # MoveData -> the instance number of its latest start
var _matched := -1 # instance of the last move counted (multi-hits count once)


func _init(trial_data: Dictionary) -> void:
	trial = trial_data
	steps = trial_data.steps


## The player started `move`.
func move_started(move: MoveData) -> void:
	_instance += 1
	_started[move] = _instance


## The player's `move` hit the dummy (not blocked).
func hit(move: MoveData) -> void:
	if done or move.input.begins_with("~"):
		return
	var id: int = _started.get(move, -1)
	if id == _matched and id >= 0:
		return # another hit of the same move
	_matched = id
	if steps[progress] == move.input:
		_advance()
	elif progress > 0:
		progress = 0
		dropped.emit()
		if steps[0] == move.input:
			_advance()
	elif steps[0] == move.input:
		_advance()


## The dummy splatted against the wall (or bounced off the ropes).
func wall() -> void:
	if not done and progress > 0 and steps[progress] == "WALL":
		_advance()


## The dummy's combo ended (it can act again).
func combo_ended() -> void:
	if not done and progress > 0:
		progress = 0
		_matched = -1
		dropped.emit()


func reset() -> void:
	progress = 0
	done = false
	_matched = -1


func _advance() -> void:
	progress += 1
	progressed.emit(progress)
	if progress >= steps.size():
		done = true
		completed.emit()
