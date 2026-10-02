class_name PlayerController
extends FighterController
## Reads the Input Map (actions named "<prefix>left", "<prefix>lp", ...). Left/right are
## screen-relative and converted to back/forward based on which side the fighter is on.

var prefix: String


func _init(action_prefix: String) -> void:
	prefix = action_prefix


func read(fighter: Fighter) -> int:
	var x := _axis("left", "right")
	var y := _axis("down", "up")
	if not fighter.faces_screen_right():
		x = -x
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


func _axis(negative: String, positive: String) -> int:
	return int(Input.is_action_pressed(prefix + positive)) - int(Input.is_action_pressed(prefix + negative))
