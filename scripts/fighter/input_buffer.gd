class_name InputBuffer
extends RefCounted
## Per-fighter history of packed inputs, one entry per 60 Hz tick.
## Packed format: bits 0-3 = numpad direction relative to facing (6 = toward opponent,
## 4 = away, 8 = up, 2 = down), bits 4+ = held buttons.

const LP := 1
const HP := 2
const LK := 4
const HK := 8
const SIDESTEP := 16

const BUTTON_NAMES := { LP: "LP", HP: "HP", LK: "LK", HK: "HK" }
const BUTTON_SHIFT := 4
const NEUTRAL := 5
const SIZE := 60

var _frames := PackedInt32Array()
var _frame := -1 # index of the newest entry (total pushes - 1)
var _consumed_until := {} # button -> last frame whose presses are used up


func _init() -> void:
	_frames.resize(SIZE)
	_frames.fill(NEUTRAL)


static func pack(dir: int, buttons: int) -> int:
	return dir | (buttons << BUTTON_SHIFT)


func push(packed: int) -> void:
	_frame += 1
	_frames[_frame % SIZE] = packed


## The newest packed input.
func current() -> int:
	return _at(0)


func dir(ago: int = 0) -> int:
	return _at(ago) & 0xF


func held(button: int, ago: int = 0) -> bool:
	return ((_at(ago) >> BUTTON_SHIFT) & button) != 0


func pressed(button: int, ago: int = 0) -> bool:
	return held(button, ago) and not held(button, ago + 1)


## True if the button was freshly pressed within the last `window` ticks and that
## press hasn't been consumed by a previous action.
func pressed_within(button: int, window: int) -> bool:
	var consumed: int = _consumed_until.get(button, -1)
	for ago in window:
		if _frame - ago <= consumed:
			return false
		if pressed(button, ago):
			return true
	return false


func consume(button: int) -> void:
	_consumed_until[button] = _frame


## True if `target_dir` was just pressed for the second time within `window` ticks.
func double_tapped(target_dir: int, window: int) -> bool:
	if dir(0) != target_dir or dir(1) == target_dir:
		return false
	for ago in range(2, window):
		if dir(ago) == target_dir:
			return true
	return false


func _at(ago: int) -> int:
	if ago > _frame or ago >= SIZE:
		return pack(NEUTRAL, 0)
	return _frames[(_frame - ago) % SIZE]
