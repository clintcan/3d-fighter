class_name DummyController
extends FighterController
## Training dummy used until the real AI (milestone 7). Holds a fixed direction.

enum Mode { STAND, CROUCH, STAND_BLOCK, CROUCH_BLOCK, JUMP }

const MODE_NAMES := ["Stand", "Crouch", "Stand Block", "Crouch Block", "Jump"]
const MODE_DIRS := [5, 2, 4, 1, 8]

var mode := Mode.STAND


func read(_fighter: Fighter) -> int:
	return InputBuffer.pack(MODE_DIRS[mode], 0)


func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode


func mode_name() -> String:
	return MODE_NAMES[mode]
