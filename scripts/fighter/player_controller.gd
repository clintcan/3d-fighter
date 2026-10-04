class_name PlayerController
extends FighterController
## Reads the Input Map (actions named "<prefix>left", "<prefix>lp", ...). Left/right are
## screen-relative and converted to back/forward based on which side the fighter is on.

var prefix: String


func _init(action_prefix: String) -> void:
	prefix = action_prefix


func read(fighter: Fighter) -> int:
	return to_facing(read_raw(), fighter)


## Screen-relative input (numpad 6 = screen right). Netplay sends this form and converts
## it inside the simulation tick, because facing can change when frames are re-simulated.
func read_raw() -> int:
	var x := _axis("left", "right")
	var y := _axis("down", "up")
	var buttons := 0
	if Input.is_action_pressed(prefix + "lp"):
		buttons |= InputBuffer.LP
	if Input.is_action_pressed(prefix + "hp"):
		buttons |= InputBuffer.HP
	if Input.is_action_pressed(prefix + "lk"):
		buttons |= InputBuffer.LK
	if Input.is_action_pressed(prefix + "hk"):
		buttons |= InputBuffer.HK
	if Input.is_action_pressed(prefix + "sidestep"):
		buttons |= InputBuffer.SIDESTEP
	return InputBuffer.pack(to_numpad(x, y), buttons)


## Converts a screen-relative packed input to the facing-relative form the fighter uses.
static func to_facing(raw: int, fighter: Fighter) -> int:
	if fighter.faces_screen_right():
		return raw
	var dir := raw & 0xF
	var mirrored := dir + 2 - 2 * ((dir - 1) % 3) # swap the left and right columns: 1<->3, 4<->6, 7<->9
	return (raw & ~0xF) | mirrored


## The inverse of to_facing (the same mirror).
static func to_screen(facing: int, fighter: Fighter) -> int:
	return to_facing(facing, fighter)


func _axis(negative: String, positive: String) -> int:
	return int(Input.is_action_pressed(prefix + positive)) - int(Input.is_action_pressed(prefix + negative))
