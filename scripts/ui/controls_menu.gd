extends Control
## Controls (Options → Controls): remap each player's keyboard keys and gamepad buttons.
## Select a binding, then press the new key or button (Esc / Start cancels). A key or
## button already used by another action swaps with it. The drawn controller shows
## where every gamepad action sits, lights up as buttons are pressed, and highlights the
## selected action. Changes save immediately.

const OPTIONS_SCENE := "res://scenes/options.tscn"
const GOLD := Color(1.0, 0.82, 0.3)
## Ignore input for a moment after starting a capture, so the press that started it
## (Enter / A) isn't taken as the new binding.
const CAPTURE_GRACE_MS := 200

var _player := "p1"
var _tabs: Array[Button] = []
var _list: GridContainer
var _controller: ControllerView
var _status: Label
var _capture := {} # {action, kind, button, started}


func _ready() -> void:
	Audio.music(&"menu")
	var background := ColorRect.new()
	background.color = Color(0.04, 0.045, 0.07)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	column.add_child(_label("CONTROLS", 60, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 16)
	column.add_child(tabs)
	for player in ["p1", "p2"]:
		var tab := _button("PLAYER %s" % player.substr(1), 28, Vector2(260, 52))
		tab.toggle_mode = true
		tab.add_theme_color_override("font_pressed_color", GOLD)
		tab.add_theme_color_override("font_hover_pressed_color", GOLD)
		tab.pressed.connect(_select_player.bind(player))
		tabs.add_child(tab)
		_tabs.append(tab)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(body)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(panel)
	_list = GridContainer.new()
	_list.columns = 3
	_list.add_theme_constant_override("h_separation", 14)
	_list.add_theme_constant_override("v_separation", 8)
	panel.add_child(_list)
	_controller = ControllerView.new()
	_controller.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(_controller)

	_status = _label("", 26, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	column.add_child(buttons)
	var reset := _button("Reset to Defaults", 26, Vector2(300, 56))
	reset.pressed.connect(func() -> void:
		InputSetup.reset_player(_player)
		Settings.save_settings()
		_status.text = "Player %s controls reset" % _player.substr(1)
		_refresh())
	buttons.add_child(reset)
	var back := _button("Back", 26, Vector2(220, 56))
	back.pressed.connect(_back)
	buttons.add_child(back)
	_select_player("p1")


func _select_player(player: String) -> void:
	_player = player
	for i in _tabs.size():
		_tabs[i].button_pressed = (i == (0 if player == "p1" else 1))
	_controller.player = player
	_refresh()


## Rebuilds the binding rows for the current player.
func _refresh() -> void:
	var focused_action := ""
	var focused_kind := ""
	var focus := get_viewport().gui_get_focus_owner()
	if focus and focus.has_meta(&"action"):
		focused_action = focus.get_meta(&"action")
		focused_kind = focus.get_meta(&"kind")
	for child in _list.get_children():
		child.queue_free()
	_list.add_child(_label("ACTION", 22, Color(0.6, 0.62, 0.7)))
	_list.add_child(_label("KEYBOARD", 22, Color(0.6, 0.62, 0.7), HORIZONTAL_ALIGNMENT_CENTER))
	_list.add_child(_label("GAMEPAD", 22, Color(0.6, 0.62, 0.7), HORIZONTAL_ALIGNMENT_CENTER))
	var first: Button
	for action: String in InputSetup.ACTIONS:
		var binding: Dictionary = InputSetup.bindings[_player][action]
		var name := _label(InputSetup.ACTION_NAMES[action], 26, Color.WHITE)
		name.custom_minimum_size.x = 230
		_list.add_child(name)
		var key := _binding_button(action, "key", InputSetup.key_name(binding.key))
		_list.add_child(key)
		if first == null:
			first = key
		if binding.has("pad"):
			_list.add_child(_binding_button(action, "pad", InputSetup.pad_name(binding.pad)))
		else:
			_list.add_child(_label("D-pad / stick", 22, Color(0.5, 0.52, 0.58), HORIZONTAL_ALIGNMENT_CENTER))
		if action == focused_action:
			var target: Button = key if focused_kind == "key" else _list.get_child(_list.get_child_count() - 1) as Button
			if target:
				target.call_deferred(&"grab_focus")
	if focused_action == "" and first:
		first.call_deferred(&"grab_focus")
	_controller.highlight = -1
	_controller.queue_redraw()


func _binding_button(action: String, kind: String, text: String) -> Button:
	var button := _button(text, 26, Vector2(180, 48))
	button.set_meta(&"action", action)
	button.set_meta(&"kind", kind)
	button.pressed.connect(_start_capture.bind(action, kind, button))
	button.focus_entered.connect(func() -> void:
		var binding: Dictionary = InputSetup.bindings[_player][action]
		_controller.highlight = binding.get("pad", -1)
		_controller.queue_redraw())
	return button


func _start_capture(action: String, kind: String, button: Button) -> void:
	_capture = {action = action, kind = kind, button = button, started = Time.get_ticks_msec()}
	button.text = "..."
	_status.text = "Press a %s for %s   (Esc / Start to cancel)" % [
		"key" if kind == "key" else "gamepad button", InputSetup.ACTION_NAMES[action]]


func _input(event: InputEvent) -> void:
	if _capture.is_empty() or Time.get_ticks_msec() - int(_capture.started) < CAPTURE_GRACE_MS:
		return
	if not event.is_pressed() or event.is_echo():
		return
	var kind: String = _capture.kind
	var code := -1
	var cancel := false
	if event is InputEventKey:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_ESCAPE:
			cancel = true
		elif kind == "key":
			code = key
	elif event is InputEventJoypadButton:
		var pad_button := (event as InputEventJoypadButton).button_index
		if pad_button in [JOY_BUTTON_START, JOY_BUTTON_BACK]:
			cancel = true
		elif kind == "pad" and pad_button in InputSetup.BINDABLE_PAD:
			code = pad_button
	elif event is InputEventJoypadMotion and kind == "pad":
		var motion := event as InputEventJoypadMotion
		if motion.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and motion.axis_value > 0.6:
			code = 100 + motion.axis
	else:
		return
	get_viewport().set_input_as_handled()
	if cancel:
		_capture = {}
		_status.text = ""
		_refresh()
		return
	if code < 0:
		return # wrong device for this column: keep waiting
	finish_capture(code)


## Applies a captured key / button to the binding being edited (public for tests).
func finish_capture(code: int) -> void:
	var action: String = _capture.action
	var kind: String = _capture.kind
	_capture = {}
	InputSetup.set_binding(_player, action, kind, code)
	Settings.save_settings()
	Audio.sfx(&"ui_accept", -4.0)
	_status.text = "%s → %s" % [InputSetup.ACTION_NAMES[action],
		InputSetup.key_name(code) if kind == "key" else InputSetup.pad_name(code)]
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _capture.is_empty() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()


func _back() -> void:
	Audio.sfx(&"ui_back", -4.0)
	get_tree().change_scene_to_file(OPTIONS_SCENE)


func _button(text: String, font_size: int, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _label(text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
