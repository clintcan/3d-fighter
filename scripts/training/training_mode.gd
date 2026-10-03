class_name TrainingMode
extends Node
## Training mode tools, added by FightManager when GameState.mode == TRAINING:
## endless session with health refill, dummy settings (stance, guard, CPU, record &
## playback), measured frame data for P1's attacks, input history, hitbox display, and
## a training menu. Keys: Tab / pad Back = menu, Backspace / L3 = reset, F6 = record,
## F7 = playback.

const REFILL_DELAY_TICKS := 40
const HISTORY_SIZE := 16
const ARROWS := ["↙", "↓", "↘", "←", "•", "→", "↖", "↑", "↗"]
const BUTTONS := [[InputBuffer.LP, "LP"], [InputBuffer.HP, "HP"], [InputBuffer.LK, "LK"],
	[InputBuffer.HK, "HK"], [InputBuffer.SIDESTEP, "SS"]]
const ACTIONS := {
	"training_menu": [KEY_TAB, JOY_BUTTON_BACK],
	"training_reset": [KEY_BACKSPACE, JOY_BUTTON_LEFT_STICK],
	"training_record": [KEY_F6, -1],
	"training_playback": [KEY_F7, -1],
}

var manager: Node
var player: Fighter
var dummy: Fighter
var dummy_controller: TrainingDummyController

var refill_health := true
var show_frame_data := true
var show_input_history := true
var show_hitboxes := false

## Last measured attack: {name, startup, active, recovery, damage, result, advantage}
var last_frame_data := {}
## Input history, newest first: [packed input, ticks held].
var history: Array = []
var recording := false

var _player_controller: FighterController
var _record_buffer := PackedInt32Array()
var _pending := {} # attack being measured
var _refill_ticks := {}
var _in_combo := false
var _combo_start_health := 0
var _dummy_prev_health := 0
var _last_combo := ""

var _layer: CanvasLayer
var _status: Label
var _frame_label: Label
var _history_label: Label
var _menu: PanelContainer
var _menu_first: Control


func setup(fight_manager: Node) -> void:
	manager = fight_manager
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = manager.fighters[0]
	dummy = manager.fighters[1]
	dummy_controller = dummy.controller as TrainingDummyController
	dummy_controller.ai = manager.ai
	_player_controller = player.controller
	_dummy_prev_health = dummy.health
	_add_actions()
	_build_ui()
	manager.ticked.connect(_on_tick)
	manager.hit_landed.connect(_on_hit_landed)
	_refresh()


# --- Simulation hooks ------------------------------------------------------------

func _on_tick() -> void:
	_track_history()
	_track_frame_data()
	_track_combo()
	if refill_health:
		_refill(player)
		_refill(dummy)
	if recording:
		if _record_buffer.size() >= TrainingDummyController.MAX_RECORDING_TICKS:
			stop_recording()
		else:
			_update_status()


func _on_hit_landed(attacker: Fighter, defender: Fighter, move: MoveData, result: Fighter.HitResult) -> void:
	if attacker != player:
		return
	_pending = {
		name = move.name, startup = move.startup + 1, active = move.active, recovery = move.recovery,
		damage = move.damage, result = result, ticks = 0, attacker_free = -1, defender_free = -1,
		defender = defender,
	}


## Frame advantage = ticks until the defender can act minus ticks until the attacker can.
## Measured from the simulation after each tick, so cancels, pushback and hitstop all count.
func _track_frame_data() -> void:
	if _pending.is_empty():
		return
	_pending.ticks += 1
	var defender: Fighter = _pending.defender
	if defender.state == Fighter.State.KNOCKDOWN or defender.state == Fighter.State.KO:
		_finish_frame_data("KD")
		return
	if _pending.attacker_free < 0 and player.is_actionable():
		_pending.attacker_free = _pending.ticks
	if _pending.defender_free < 0 and defender.is_actionable():
		_pending.defender_free = _pending.ticks
	if _pending.attacker_free >= 0 and _pending.defender_free >= 0:
		var advantage: int = _pending.defender_free - _pending.attacker_free
		_finish_frame_data("%+d" % advantage)
	elif _pending.ticks > 240:
		_pending = {}


func _finish_frame_data(advantage: String) -> void:
	last_frame_data = _pending.duplicate()
	last_frame_data.erase("defender")
	last_frame_data.advantage = advantage
	_pending = {}
	_update_frame_label()


## Totals each combo on the dummy (hits + damage) once it ends.
func _track_combo() -> void:
	if dummy.combo_hits > 0 and not _in_combo:
		_in_combo = true
		_combo_start_health = _dummy_prev_health
	elif dummy.combo_hits > 1:
		_last_combo = "%d hits, %d dmg" % [dummy.combo_hits, _combo_start_health - dummy.health]
	elif _in_combo:
		_in_combo = false
		_update_frame_label()
	_dummy_prev_health = dummy.health


func _track_history() -> void:
	var packed := player.input.current()
	if not history.is_empty() and history[0][0] == packed:
		history[0][1] = mini(history[0][1] + 1, 99)
	else:
		history.push_front([packed, 1])
		if history.size() > HISTORY_SIZE:
			history.pop_back()
	if show_input_history:
		_history_label.text = format_history()


func _refill(fighter: Fighter) -> void:
	var key := fighter.get_instance_id()
	if fighter.health < fighter.data.max_health and fighter.combo_hits == 0 and fighter.is_actionable():
		_refill_ticks[key] = int(_refill_ticks.get(key, 0)) + 1
		if _refill_ticks[key] >= REFILL_DELAY_TICKS:
			fighter.health = fighter.data.max_health
			fighter.health_changed.emit(fighter.health, fighter.data.max_health)
			_refill_ticks[key] = 0
	else:
		_refill_ticks[key] = 0


# --- Record / playback / reset -----------------------------------------------------

## P1 takes control of the dummy and records its inputs (P1's own fighter stands still).
func start_recording() -> void:
	recording = true
	_record_buffer.clear()
	var recorder := RecordingController.new(_player_controller, _record_buffer)
	dummy.controller = recorder
	player.controller = FighterController.new()
	_update_status()


func stop_recording() -> void:
	if not recording:
		return
	recording = false
	var recorder := dummy.controller as RecordingController
	if recorder:
		_record_buffer = recorder.buffer
	dummy.controller = dummy_controller
	player.controller = _player_controller
	if not _record_buffer.is_empty():
		dummy_controller.recording = _record_buffer.duplicate()
		dummy_controller.stance = TrainingDummyController.Stance.PLAYBACK
		dummy_controller.restart_playback()
	_refresh()


func toggle_playback() -> void:
	if dummy_controller.recording.is_empty():
		return
	var playing := dummy_controller.stance == TrainingDummyController.Stance.PLAYBACK
	dummy_controller.stance = TrainingDummyController.Stance.STAND if playing else TrainingDummyController.Stance.PLAYBACK
	dummy_controller.restart_playback()
	_refresh()


func reset_positions() -> void:
	stop_recording()
	manager.start_match()
	_pending = {}
	dummy_controller.restart_playback()
	_refresh()


# --- Input & UI ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("training_menu") and (_menu.visible or not get_tree().paused):
		_toggle_menu()
	elif _menu.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			_toggle_menu()
			get_viewport().set_input_as_handled()
		return
	elif get_tree().paused:
		return
	elif event.is_action_pressed("training_reset"):
		reset_positions()
	elif event.is_action_pressed("training_record"):
		if recording:
			stop_recording()
		else:
			start_recording()
	elif event.is_action_pressed("training_playback"):
		toggle_playback()
	else:
		return
	get_viewport().set_input_as_handled()


func _toggle_menu() -> void:
	_menu.visible = not _menu.visible
	get_tree().paused = _menu.visible
	if _menu.visible:
		_menu_first.grab_focus()


func _add_actions() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var key := InputEventKey.new()
		key.physical_keycode = ACTIONS[action][0]
		InputMap.action_add_event(action, key)
		if ACTIONS[action][1] >= 0:
			var pad := InputEventJoypadButton.new()
			pad.device = -1
			pad.button_index = ACTIONS[action][1]
			InputMap.action_add_event(action, pad)


func _refresh() -> void:
	for fighter: Fighter in manager.fighters:
		fighter.debug_draw = show_hitboxes
	_frame_label.get_parent().visible = show_frame_data
	_history_label.get_parent().visible = show_input_history
	_update_status()
	_update_frame_label()


func _update_status() -> void:
	if recording:
		_status.text = "●  RECORDING DUMMY  %.1fs  -  F6 to stop" % (_record_buffer.size() / 60.0)
		_status.modulate = Color(1, 0.35, 0.3)
		return
	_status.modulate = Color.WHITE
	_status.text = "TRAINING  ·  Dummy: %s  ·  Guard: %s  ·  Tab: Menu  ·  Backspace: Reset  ·  F6: Record  ·  F7: Playback" % [
		dummy_controller.stance_name(), dummy_controller.guard_name()]


func _update_frame_label() -> void:
	if last_frame_data.is_empty():
		_frame_label.text = "FRAME DATA\nLand an attack on the dummy"
	else:
		var d := last_frame_data
		var result_name: String = Fighter.HitResult.keys()[d.result].capitalize()
		_frame_label.text = "FRAME DATA  -  %s\nStartup %d  ·  Active %d  ·  Recovery %d\nDamage %d  ·  On %s: %s" % [
			d.name.to_upper(), d.startup, d.active, d.recovery, d.damage, result_name.to_lower(), d.advantage]
	if _last_combo != "":
		_frame_label.text += "\nLast combo: " + _last_combo


func format_history() -> String:
	var lines := PackedStringArray(["INPUT"])
	for entry in history:
		var packed: int = entry[0]
		var dir := packed & 0xF
		var buttons := PackedStringArray()
		for b in BUTTONS:
			if ((packed >> InputBuffer.BUTTON_SHIFT) & b[0]) != 0:
				buttons.append(b[1])
		lines.append("%2d  %s %s" % [entry[1], ARROWS[clampi(dir, 1, 9) - 1], " ".join(buttons)])
	return "\n".join(lines)


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 2
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Menlo", "monospace"])

	_status = _label(24, null)
	_status.anchor_left = 0.0
	_status.anchor_right = 1.0
	_status.offset_top = 150
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer.add_child(_status)

	var frame_panel := _panel(Vector2(40, -40), Control.PRESET_BOTTOM_LEFT)
	_frame_label = _label(22, mono)
	frame_panel.add_child(_frame_label)

	var history_panel := _panel(Vector2(40, 210), Control.PRESET_TOP_LEFT)
	_history_label = _label(22, mono)
	history_panel.add_child(_history_label)

	_build_menu()


func _panel(offset: Vector2, preset: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(panel)
	panel.set_anchors_preset(preset)
	panel.offset_left = offset.x
	panel.offset_top = offset.y
	if preset == Control.PRESET_BOTTOM_LEFT:
		panel.grow_vertical = Control.GROW_DIRECTION_BEGIN # grows upward from the bottom offset
		panel.offset_bottom = offset.y
	return panel


func _label(size: int, font: Font) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	if font:
		label.add_theme_font_override("font", font)
	return label


func _build_menu() -> void:
	_menu = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.06, 0.95)
	style.border_color = Color(0.95, 0.75, 0.2)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(30)
	_menu.add_theme_stylebox_override("panel", style)
	_menu.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(center)
	center.add_child(_menu)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(620, 0)
	_menu.add_child(box)
	var title := _label(44, null)
	title.text = "TRAINING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	_menu_first = _option(grid, "Dummy", TrainingDummyController.STANCE_NAMES, dummy_controller.stance,
		func(i: int) -> void:
			dummy_controller.stance = i as TrainingDummyController.Stance
			dummy_controller.restart_playback()
			_refresh())
	_option(grid, "Guard", TrainingDummyController.GUARD_NAMES, dummy_controller.guard,
		func(i: int) -> void:
			dummy_controller.guard = i as TrainingDummyController.Guard
			_refresh())
	_toggle(grid, "Health Refill", refill_health, func(on: bool) -> void: refill_health = on)
	_toggle(grid, "Frame Data", show_frame_data, func(on: bool) -> void:
		show_frame_data = on
		_refresh())
	_toggle(grid, "Input History", show_input_history, func(on: bool) -> void:
		show_input_history = on
		_refresh())
	_toggle(grid, "Hitboxes", show_hitboxes, func(on: bool) -> void:
		show_hitboxes = on
		_refresh())

	for item in [["Record Dummy (F6)", func() -> void:
			_toggle_menu()
			start_recording()],
		["Reset Positions (Backspace)", func() -> void:
			_toggle_menu()
			reset_positions()],
		["Close", _toggle_menu]]:
		var button := Button.new()
		button.text = item[0]
		button.custom_minimum_size = Vector2(0, 50)
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(item[1])
		box.add_child(button)


func _option(grid: GridContainer, label_text: String, items: Array, selected: int, on_change: Callable) -> OptionButton:
	var label := _label(26, null)
	label.text = label_text
	grid.add_child(label)
	var option := OptionButton.new()
	option.add_theme_font_size_override("font_size", 22)
	option.custom_minimum_size = Vector2(320, 44)
	for item: String in items:
		option.add_item(item)
	option.selected = selected
	option.item_selected.connect(on_change)
	grid.add_child(option)
	return option


func _toggle(grid: GridContainer, label_text: String, value: bool, on_change: Callable) -> void:
	var label := _label(26, null)
	label.text = label_text
	grid.add_child(label)
	var check := CheckButton.new()
	check.button_pressed = value
	check.toggled.connect(on_change)
	grid.add_child(check)


## Feeds P1's controls to the dummy while recording them.
class RecordingController extends FighterController:
	var source: FighterController
	var buffer: PackedInt32Array

	func _init(player_controller: FighterController, into: PackedInt32Array) -> void:
		source = player_controller
		buffer = into

	func read(fighter: Fighter) -> int:
		var packed := source.read(fighter)
		buffer.append(packed)
		return packed
