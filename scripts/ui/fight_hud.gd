class_name FightHud
extends CanvasLayer
## Fight HUD: health bars with a delayed damage trail, round-win pips, timer, combo
## counters, callouts, center announcements, the match result menu, and the pause menu.
## Runs while the tree is paused (process_mode = Always) so menus work.

signal rematch_pressed
signal restart_pressed
signal character_select_pressed
signal main_menu_pressed

const TRAIL_DELAY := 0.45
const TRAIL_DRAIN_TIME := 0.35
const PIP_SIZE := Vector2(22, 22)
const PIP_OFF := Color(0.15, 0.15, 0.18)
const PIP_ON := Color(1.0, 0.8, 0.15)
const LEVEL_NAMES := ["High", "Mid", "Low", "Overhead"]

@onready var p1_health: ProgressBar = %P1Health
@onready var p2_health: ProgressBar = %P2Health
@onready var p1_trail: ProgressBar = %P1Trail
@onready var p2_trail: ProgressBar = %P2Trail
@onready var p1_name: Label = %P1Name
@onready var p2_name: Label = %P2Name
@onready var p1_pips: HBoxContainer = %P1Pips
@onready var p2_pips: HBoxContainer = %P2Pips
@onready var p1_combo: Label = %P1Combo
@onready var p2_combo: Label = %P2Combo
@onready var p1_note: Label = %P1Note
@onready var p2_note: Label = %P2Note
@onready var timer_label: Label = %TimerLabel
@onready var center_label: Label = %CenterLabel
@onready var sub_label: Label = %SubLabel
@onready var result_panel: Control = %ResultPanel
@onready var debug_label: Label = %DebugLabel
@onready var pause_menu: Control = %PauseMenu
@onready var move_list_panel: Control = %MoveListPanel
@onready var move_list_label: Label = %MoveListLabel

var _trail_tweens := {}
var _announce_tween: Tween


func _ready() -> void:
	%RematchButton.pressed.connect(func() -> void: rematch_pressed.emit())
	%ResultSelectButton.pressed.connect(func() -> void: character_select_pressed.emit())
	%ResultMenuButton.pressed.connect(func() -> void: main_menu_pressed.emit())
	%ResumeButton.pressed.connect(hide_pause)
	%RestartButton.pressed.connect(func() -> void:
		hide_pause()
		restart_pressed.emit())
	%MoveListButton.toggled.connect(func(on: bool) -> void: move_list_panel.visible = on)
	%PauseSelectButton.pressed.connect(func() -> void: character_select_pressed.emit())
	%PauseMenuButton.pressed.connect(func() -> void: main_menu_pressed.emit())


func setup(p1: Fighter, p2: Fighter, rounds_to_win: int) -> void:
	p1_name.text = p1.data.display_name
	p2_name.text = "%s (CPU)" % p2.data.display_name
	_bind_health(p1, p1_health, p1_trail)
	_bind_health(p2, p2_health, p2_trail)
	# A combo is shown on the attacker's side, so P2's hits taken appear under P1.
	p2.combo_changed.connect(_on_combo_changed.bind(p1_combo))
	p1.combo_changed.connect(_on_combo_changed.bind(p2_combo))
	for pips in [p1_pips, p2_pips]:
		for i in rounds_to_win:
			pips.add_child(_make_pip())
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Menlo", "monospace"])
	move_list_label.add_theme_font_override("font", mono)
	move_list_label.text = _move_list_text(p1.data)
	for label in [p1_combo, p2_combo, p1_note, p2_note, center_label, sub_label]:
		label.text = ""


# --- Announcements & timer -------------------------------------------------------

## Big center text with an optional second line. `pop` scales it in.
func announce(text: String, sub: String = "", pop: bool = false) -> void:
	center_label.text = text
	sub_label.text = sub
	if _announce_tween:
		_announce_tween.kill()
	center_label.scale = Vector2.ONE
	center_label.modulate.a = 1.0
	if pop and text != "":
		center_label.pivot_offset = center_label.size / 2.0
		center_label.scale = Vector2(1.6, 1.6)
		_announce_tween = create_tween()
		_announce_tween.tween_property(center_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if text == "FIGHT!":
			_announce_tween.tween_interval(0.5)
			_announce_tween.tween_property(center_label, "modulate:a", 0.0, 0.25)


func set_timer(seconds: int) -> void:
	timer_label.text = "%02d" % maxi(seconds, 0)
	timer_label.modulate = Color(1, 0.3, 0.25) if seconds <= 10 else Color.WHITE


func set_round_wins(wins: Array[int]) -> void:
	for side in 2:
		var pips: HBoxContainer = p1_pips if side == 0 else p2_pips
		for i in pips.get_child_count():
			# P2's pips fill from the right edge inward.
			var index := i if side == 0 else pips.get_child_count() - 1 - i
			var lit := index < wins[side]
			((pips.get_child(i) as Panel).get_theme_stylebox("panel") as StyleBoxFlat).bg_color = PIP_ON if lit else PIP_OFF


## Short callout ("COUNTER", "TECH") under a player's side that fades out.
func note(player_index: int, text: String) -> void:
	var label := p1_note if player_index == 0 else p2_note
	label.text = text
	label.modulate.a = 1.0
	var tween := label.create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)


func set_debug_text(text: String) -> void:
	debug_label.text = text


# --- Menus -----------------------------------------------------------------------

func show_result() -> void:
	result_panel.visible = true
	%RematchButton.grab_focus()


func hide_result() -> void:
	result_panel.visible = false


func show_pause() -> void:
	pause_menu.visible = true
	%MoveListButton.button_pressed = false
	%ResumeButton.grab_focus()


func hide_pause() -> void:
	pause_menu.visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if pause_menu.visible and event.is_action_pressed("pause"):
		hide_pause()
		get_viewport().set_input_as_handled()


# --- Internals -------------------------------------------------------------------

func _bind_health(fighter: Fighter, bar: ProgressBar, trail: ProgressBar) -> void:
	for b in [bar, trail]:
		b.max_value = fighter.data.max_health
		b.value = fighter.health
	fighter.health_changed.connect(func(current: int, maximum: int) -> void:
		bar.max_value = maximum
		trail.max_value = maximum
		bar.value = current
		if _trail_tweens.has(trail):
			(_trail_tweens[trail] as Tween).kill()
		if current >= trail.value:
			trail.value = current # healed / new round: no trail
			return
		# The red trail lingers, then drains down to the new health.
		var tween := create_tween()
		tween.tween_interval(TRAIL_DELAY)
		tween.tween_property(trail, "value", float(current), TRAIL_DRAIN_TIME)
		_trail_tweens[trail] = tween)


func _on_combo_changed(hits: int, label: Label) -> void:
	label.text = "%d HITS" % hits if hits >= 2 else ""


func _make_pip() -> Panel:
	var pip := Panel.new()
	pip.custom_minimum_size = PIP_SIZE
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PIP_OFF
	style.set_corner_radius_all(int(PIP_SIZE.x / 2))
	style.set_border_width_all(2)
	style.border_color = Color.BLACK
	pip.add_theme_stylebox_override("panel", style)
	return pip


func _move_list_text(character: CharacterData) -> String:
	var lines := PackedStringArray(["%s - MOVE LIST" % character.display_name.to_upper(), ""])
	for move in character.moves:
		lines.append("%-6s %-16s %s" % [move.input, move.name, LEVEL_NAMES[move.hit_level]])
	lines.append("%-6s %-16s %s" % ["LP+LK", "Throw", "Unblockable"])
	lines.append("")
	lines.append("Dash: tap forward twice  ·  Backdash: tap back twice")
	lines.append("Sidestep: L / RB (hold down for toward camera)")
	lines.append("Block: hold back (stand) or down-back (crouch)")
	return "\n".join(lines)
