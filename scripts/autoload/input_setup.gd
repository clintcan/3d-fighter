extends Node
## Builds both players' input actions ("p1_*", "p2_*"). This is the single source of
## truth for fight controls (the p1 actions in project.godot are only editor defaults
## and are replaced here).
##
## Each player has a remappable binding per action: a keyboard key and a gamepad button
## (Options → Controls; saved by Settings). Defaults: P1 = WASD + U I J K L, P2 = arrows
## + numpad 4 5 / 1 2 / 6 (with a fallback on [ ] ; ' / for keyboards without a numpad,
## kept while P2's binding is the default). Gamepad: D-pad + left stick always move;
## buttons X Y A B RB by default, and the triggers can be bound too. Pad 1 → P1, pad 2 →
## P2, or the other way round when `swap_pads` is set.

const ACTIONS := ["left", "right", "up", "down", "lp", "hp", "lk", "hk", "sidestep"]
## Actions whose gamepad button can be remapped (movement is always D-pad + left stick).
const PAD_ACTIONS := ["lp", "hp", "lk", "hk", "sidestep"]
const ACTION_NAMES := {
	"left": "Left", "right": "Right", "up": "Up / Jump", "down": "Down / Crouch",
	"lp": "Light Punch", "hp": "Heavy Punch", "lk": "Light Kick", "hk": "Heavy Kick", "sidestep": "Sidestep",
}
## Pseudo button codes for the analog triggers (bound as "pressed past half way").
const PAD_TRIGGER_LEFT := 100 + JOY_AXIS_TRIGGER_LEFT
const PAD_TRIGGER_RIGHT := 100 + JOY_AXIS_TRIGGER_RIGHT
## Buttons that can be bound (Start and Back stay reserved for pause / training menu).
const BINDABLE_PAD := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
	JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, PAD_TRIGGER_LEFT, PAD_TRIGGER_RIGHT,
	JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]
## Keys that can't be bound (Esc pauses and cancels menus).
const RESERVED_KEYS := [KEY_ESCAPE]
const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	PAD_TRIGGER_LEFT: "LT", PAD_TRIGGER_RIGHT: "RT",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
}

const DEFAULT_KEYS := {
	"p1": {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S,
		"lp": KEY_U, "hp": KEY_I, "lk": KEY_J, "hk": KEY_K, "sidestep": KEY_L},
	"p2": {"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN,
		"lp": KEY_KP_4, "hp": KEY_KP_5, "lk": KEY_KP_1, "hk": KEY_KP_2, "sidestep": KEY_KP_6},
}
## P2's second keys for keyboards without a numpad (only while the binding is default).
const P2_FALLBACK_KEYS := {"lp": KEY_BRACKETLEFT, "hp": KEY_BRACKETRIGHT, "lk": KEY_SEMICOLON,
	"hk": KEY_APOSTROPHE, "sidestep": KEY_SLASH}
const DEFAULT_PAD := {"lp": JOY_BUTTON_X, "hp": JOY_BUTTON_Y, "lk": JOY_BUTTON_A, "hk": JOY_BUTTON_B,
	"sidestep": JOY_BUTTON_RIGHT_SHOULDER}
const PAD_DIRECTIONS := {
	"left": [JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0], "right": [JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0],
	"up": [JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0],
}
const DEADZONE := 0.3

## "p1"/"p2" -> action -> {key: keycode, pad: button code (PAD_ACTIONS only)}.
var bindings := {}
var _swap_pads := false


func _ready() -> void:
	bindings = default_bindings()
	apply(false)


func default_bindings() -> Dictionary:
	var out := {}
	for player: String in ["p1", "p2"]:
		out[player] = {}
		for action: String in ACTIONS:
			var binding := {key = DEFAULT_KEYS[player][action]}
			if action in PAD_ACTIONS:
				binding.pad = DEFAULT_PAD[action]
			out[player][action] = binding
	return out


## Rebinds one action. If another action of the same player already uses that key or
## button, the two swap, so nothing is ever left unbound.
func set_binding(player: String, action: String, kind: String, code: int) -> void:
	var mine: Dictionary = bindings[player][action]
	var old: int = mine[kind]
	for other: String in ACTIONS:
		var theirs: Dictionary = bindings[player][other]
		if other != action and theirs.has(kind) and theirs[kind] == code:
			theirs[kind] = old
	mine[kind] = code
	apply(_swap_pads)


func reset_player(player: String) -> void:
	bindings[player] = default_bindings()[player]
	apply(_swap_pads)


func key_name(code: int) -> String:
	var name := OS.get_keycode_string(code)
	return name.replace("Kp ", "Num ") if name != "" else "?"


func pad_name(code: int) -> String:
	return PAD_NAMES.get(code, "?")


## The gamepad index used by a player ("p1" -> 0, unless swapped).
func pad_device(player: String) -> int:
	var pad := 0 if player == "p1" else 1
	return 1 - pad if _swap_pads else pad


func save_bindings(cfg: ConfigFile) -> void:
	for player: String in bindings:
		for action: String in ACTIONS:
			var binding: Dictionary = bindings[player][action]
			cfg.set_value("controls", "%s_%s_key" % [player, action], binding.key)
			if binding.has("pad"):
				cfg.set_value("controls", "%s_%s_pad" % [player, action], binding.pad)


func load_bindings(cfg: ConfigFile) -> void:
	bindings = default_bindings()
	for player: String in bindings:
		for action: String in ACTIONS:
			var binding: Dictionary = bindings[player][action]
			binding.key = int(cfg.get_value("controls", "%s_%s_key" % [player, action], binding.key))
			if binding.has("pad"):
				binding.pad = int(cfg.get_value("controls", "%s_%s_pad" % [player, action], binding.pad))


## Rebuilds every p1_/p2_ action from the bindings. `swap_pads` gives gamepad 1 to P2
## and gamepad 2 to P1.
func apply(swap_pads: bool) -> void:
	_swap_pads = swap_pads
	if bindings.is_empty():
		bindings = default_bindings()
	for player: String in ["p1", "p2"]:
		var pad := pad_device(player)
		for action: String in ACTIONS:
			var name := "%s_%s" % [player, action]
			if InputMap.has_action(name):
				InputMap.action_erase_events(name)
			else:
				InputMap.add_action(name)
			InputMap.action_set_deadzone(name, DEADZONE)
			var binding: Dictionary = bindings[player][action]
			_add_key(name, binding.key)
			if player == "p2" and P2_FALLBACK_KEYS.has(action) and binding.key == DEFAULT_KEYS.p2[action]:
				_add_key(name, P2_FALLBACK_KEYS[action])
			if PAD_DIRECTIONS.has(action):
				_add_pad_button(name, pad, PAD_DIRECTIONS[action][0])
				var stick := InputEventJoypadMotion.new()
				stick.device = pad
				stick.axis = PAD_DIRECTIONS[action][1]
				stick.axis_value = PAD_DIRECTIONS[action][2]
				InputMap.action_add_event(name, stick)
			else:
				_add_pad_button(name, pad, binding.pad)


func _add_key(action: String, code: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	InputMap.action_add_event(action, ev)


func _add_pad_button(action: String, device: int, code: int) -> void:
	if code >= 100: # a trigger, as an analog axis
		var trigger := InputEventJoypadMotion.new()
		trigger.device = device
		trigger.axis = code - 100
		trigger.axis_value = 1.0
		InputMap.action_add_event(action, trigger)
	else:
		var button := InputEventJoypadButton.new()
		button.device = device
		button.button_index = code
		InputMap.action_add_event(action, button)


## Human-readable controls for menus and the move list.
func describe(player: String) -> String:
	var b: Dictionary = bindings[player]
	return "%s%s%s%s move · %s/%s punch · %s/%s kick · %s sidestep" % [
		key_name(b.up.key), key_name(b.left.key), key_name(b.down.key), key_name(b.right.key),
		key_name(b.lp.key), key_name(b.hp.key), key_name(b.lk.key), key_name(b.hk.key), key_name(b.sidestep.key)]
