extends Node
## Builds both players' input actions ("p1_*", "p2_*") at startup. This is the single
## source of truth for fight controls (the p1 actions in project.godot are only editor
## defaults and are replaced here).
##
## Keyboard: P1 = WASD + U I J K L, P2 = arrows + numpad (4 5 / 1 2 / 6), with a fallback
## on [ ] ; ' / for keyboards without a numpad. Gamepads: pad 1 → P1, pad 2 → P2, or the
## other way round when `swap_pads` is set (Options), so one pad can be P2's.

const ACTIONS := ["left", "right", "up", "down", "lp", "hp", "lk", "hk", "sidestep"]

const KEYBOARD := {
	"p1": {
		"left": [KEY_A], "right": [KEY_D], "up": [KEY_W], "down": [KEY_S],
		"lp": [KEY_U], "hp": [KEY_I], "lk": [KEY_J], "hk": [KEY_K], "sidestep": [KEY_L],
	},
	"p2": {
		"left": [KEY_LEFT], "right": [KEY_RIGHT], "up": [KEY_UP], "down": [KEY_DOWN],
		"lp": [KEY_KP_4, KEY_BRACKETLEFT], "hp": [KEY_KP_5, KEY_BRACKETRIGHT],
		"lk": [KEY_KP_1, KEY_SEMICOLON], "hk": [KEY_KP_2, KEY_APOSTROPHE],
		"sidestep": [KEY_KP_6, KEY_SLASH],
	},
}

## Gamepad: [buttons], [axis, direction] pairs per action.
const PAD_BUTTONS := {
	"left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT],
	"up": [JOY_BUTTON_DPAD_UP], "down": [JOY_BUTTON_DPAD_DOWN],
	"lp": [JOY_BUTTON_X], "hp": [JOY_BUTTON_Y], "lk": [JOY_BUTTON_A], "hk": [JOY_BUTTON_B],
	"sidestep": [JOY_BUTTON_RIGHT_SHOULDER],
}
const PAD_AXES := {
	"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
	"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0],
}
const DEADZONE := 0.3


func _ready() -> void:
	apply(false)


## Rebuilds every p1_/p2_ action. `swap_pads` gives gamepad 1 to P2 and gamepad 2 to P1.
func apply(swap_pads: bool) -> void:
	for player in ["p1", "p2"]:
		var pad := (0 if player == "p1" else 1)
		if swap_pads:
			pad = 1 - pad
		for action: String in ACTIONS:
			var name := "%s_%s" % [player, action]
			if InputMap.has_action(name):
				InputMap.action_erase_events(name)
			else:
				InputMap.add_action(name)
			InputMap.action_set_deadzone(name, DEADZONE)
			for key: int in KEYBOARD[player][action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(name, ev)
			for button: int in PAD_BUTTONS[action]:
				var jb := InputEventJoypadButton.new()
				jb.device = pad
				jb.button_index = button
				InputMap.action_add_event(name, jb)
			if PAD_AXES.has(action):
				var jm := InputEventJoypadMotion.new()
				jm.device = pad
				jm.axis = PAD_AXES[action][0]
				jm.axis_value = PAD_AXES[action][1]
				InputMap.action_add_event(name, jm)


## Human-readable controls for menus and the move list.
func describe(player: String) -> String:
	if player == "p1":
		return "WASD move · U/I punch · J/K kick · L sidestep"
	return "Arrows move · Num4/Num5 punch · Num1/Num2 kick · Num6 sidestep"
