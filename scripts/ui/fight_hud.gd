class_name FightHud
extends CanvasLayer
## Fight HUD: health bars with a delayed damage trail, round-win pips, timer, combo
## counters, callouts, center announcements, super meters and the super flash, the match
## result menu, and the pause menu.
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
const METER_SIZE := Vector2(360, 18)
const METER_COLOR := Color(0.25, 0.6, 1.0)
const METER_FULL_COLOR := Color(1.0, 0.8, 0.2)
const SUPER_DIM := 0.45
## Numpad digits as arrows, for move notation.
const ARROWS := {"1": "↙", "2": "↓", "3": "↘", "4": "←", "6": "→", "7": "↖", "8": "↑", "9": "↗"}

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
var _letterbox: Array[ColorRect] = []
var _cinematic_tween: Tween
var _meter_root: Control
var _meters: Array[ProgressBar] = []
var _meter_labels: Array[Label] = []
var _super_dim: ColorRect
var _super_label: Label
var _super_tween: Tween


func _ready() -> void:
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.size_flags_horizontal = Control.SIZE_FILL
		add_child(bar)
		move_child(bar, 0)
		_letterbox.append(bar)
	_set_letterbox(0.0)
	_build_super_flash()
	_build_meters()
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


## `p2_tag` labels P2: "CPU", "P2" (versus, which also tags P1) or "Dummy".
func setup(p1: Fighter, p2: Fighter, rounds_to_win: int, p2_tag: String = "CPU") -> void:
	p1_name.text = "%s (P1)" % p1.data.display_name if p2_tag == "P2" else p1.data.display_name
	p2_name.text = "%s (%s)" % [p2.data.display_name, p2_tag]
	_bind_health(p1, p1_health, p1_trail)
	_bind_health(p2, p2_health, p2_trail)
	_bind_meter(p1, 0)
	_bind_meter(p2, 1)
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


func set_timer_text(text: String) -> void:
	timer_label.text = text
	timer_label.modulate = Color.WHITE


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


# --- Super meter & super flash -----------------------------------------------------

## Dims the screen and calls out the super's name on the attacker's side.
func super_flash(player_index: int, move_name: String) -> void:
	_super_label.text = move_name.to_upper()
	_super_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if player_index == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	if _super_tween:
		_super_tween.kill()
	_super_label.pivot_offset = Vector2(0.0 if player_index == 0 else _super_label.size.x, _super_label.size.y / 2.0)
	_super_label.scale = Vector2(1.5, 1.5)
	_super_tween = create_tween().set_parallel()
	_super_tween.tween_property(_super_dim, "color:a", SUPER_DIM, 0.08)
	_super_tween.tween_property(_super_label, "modulate:a", 1.0, 0.08)
	_super_tween.tween_property(_super_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_super_tween.tween_property(_super_dim, "color:a", 0.0, 0.25).set_delay(0.6)
	_super_tween.tween_property(_super_label, "modulate:a", 0.0, 0.4).set_delay(1.1)


func _build_super_flash() -> void:
	_super_dim = ColorRect.new()
	_super_dim.color = Color(0.02, 0.0, 0.06, 0.0)
	_super_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_super_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_super_dim)
	move_child(_super_dim, 0)
	_super_label = Label.new()
	_super_label.add_theme_font_size_override("font_size", 64)
	_super_label.add_theme_color_override("font_color", METER_FULL_COLOR)
	_super_label.add_theme_constant_override("outline_size", 14)
	_super_label.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.0))
	_super_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_super_label.anchor_left = 0.0
	_super_label.anchor_right = 1.0
	_super_label.anchor_top = 0.26
	_super_label.anchor_bottom = 0.26
	_super_label.offset_left = 80
	_super_label.offset_right = -80
	_super_label.modulate.a = 0.0
	add_child(_super_label)


## Meters sit in the bottom corners; P2's fills from the right.
func _build_meters() -> void:
	_meter_root = Control.new()
	_meter_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_meter_root)
	for side in 2:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		_meter_root.add_child(box)
		var right := side == 1
		box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT if right else Control.PRESET_BOTTOM_LEFT)
		box.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
		box.grow_vertical = Control.GROW_DIRECTION_BEGIN
		box.offset_left = -40.0 - METER_SIZE.x if right else 40.0
		box.offset_right = -40.0 if right else 40.0 + METER_SIZE.x
		box.offset_top = -34.0 - METER_SIZE.y - 30.0
		box.offset_bottom = -34.0
		var label := Label.new()
		label.text = "SUPER"
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(label)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = METER_SIZE
		bar.show_percentage = false
		bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN if right else ProgressBar.FILL_BEGIN_TO_END
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.06, 0.06, 0.09, 0.85)
		background.set_border_width_all(2)
		background.border_color = Color.BLACK
		var fill := StyleBoxFlat.new()
		fill.bg_color = METER_COLOR
		bar.add_theme_stylebox_override("background", background)
		bar.add_theme_stylebox_override("fill", fill)
		box.add_child(bar)
		_meters.append(bar)
		_meter_labels.append(label)


func _bind_meter(fighter: Fighter, side: int) -> void:
	var bar := _meters[side]
	bar.max_value = Fighter.MAX_METER
	var update := func(current: int, maximum: int) -> void:
		bar.max_value = maximum
		bar.value = current
		var full := current >= maximum
		(bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = METER_FULL_COLOR if full else METER_COLOR
		_meter_labels[side].text = "SUPER  ★ READY" if full else "SUPER"
		_meter_labels[side].modulate = METER_FULL_COLOR if full else Color.WHITE
	update.call(fighter.meter, Fighter.MAX_METER)
	fighter.meter_changed.connect(update)


func _process(_delta: float) -> void:
	# Full meters pulse.
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.008)
	for bar in _meters:
		bar.self_modulate = Color(pulse + 0.25, pulse + 0.25, pulse + 0.25) if bar.value >= bar.max_value else Color.WHITE


# --- Victory cinematic ------------------------------------------------------------

## Letterbox bars in, fight HUD out, announcements to the lower third.
func start_cinematic() -> void:
	_animate_cinematic(1.0)
	(center_label.get_parent() as Control).size_flags_vertical = Control.SIZE_SHRINK_END
	# Keep the lower-third title and menu above the bottom letterbox bar.
	$Margin.add_theme_constant_override("margin_bottom", int(get_viewport().get_visible_rect().size.y * 0.13))
	center_label.add_theme_font_size_override("font_size", 96)
	# Result menu sits in the bottom-right corner so it doesn't cover the winner.
	result_panel.reparent($Margin, false)
	result_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	result_panel.size_flags_vertical = Control.SIZE_SHRINK_END


func end_cinematic() -> void:
	if _cinematic_tween:
		_cinematic_tween.kill()
	_set_letterbox(0.0)
	%Top.modulate.a = 1.0
	debug_label.modulate.a = 1.0
	_meter_root.modulate.a = 1.0
	(center_label.get_parent() as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	$Margin.add_theme_constant_override("margin_bottom", 30)
	center_label.add_theme_font_size_override("font_size", 140)
	if result_panel.get_parent() != center_label.get_parent():
		result_panel.reparent(center_label.get_parent(), false)
		result_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		result_panel.size_flags_vertical = Control.SIZE_FILL


func _animate_cinematic(amount: float) -> void:
	if _cinematic_tween:
		_cinematic_tween.kill()
	_cinematic_tween = create_tween().set_parallel()
	_cinematic_tween.tween_method(_set_letterbox, 0.0, amount, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_cinematic_tween.tween_property(%Top, "modulate:a", 0.0, 0.35)
	_cinematic_tween.tween_property(debug_label, "modulate:a", 0.0, 0.35)
	_cinematic_tween.tween_property(_meter_root, "modulate:a", 0.0, 0.35)


## 0..1: bars cover 11% of the screen height each at 1.
func _set_letterbox(amount: float) -> void:
	var height := get_viewport().get_visible_rect().size.y * 0.11 * amount
	_letterbox[0].offset_top = 0.0
	_letterbox[0].offset_bottom = height
	_letterbox[1].offset_top = -height
	_letterbox[1].offset_bottom = 0.0
	for bar in _letterbox:
		bar.visible = amount > 0.0


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
		if not move.is_special() and not move.input.begins_with("~"):
			lines.append("%-9s %-20s %s" % [move.input, move.name, LEVEL_NAMES[move.hit_level]])
	lines.append("%-9s %-20s %s" % ["LP+LK", "Throw", "Unblockable"])
	lines.append("")
	lines.append("SPECIALS  (P = either punch, K = either kick)")
	for move in character.moves:
		if move.is_special() and not move.super_move:
			lines.append("%-9s %-20s %s" % [notation(move.input), move.name, LEVEL_NAMES[move.hit_level]])
	for move in character.moves:
		if move.super_move:
			lines.append("")
			lines.append("SUPER  (full meter)")
			lines.append("%-9s %-20s %s" % [notation(move.input), move.name, LEVEL_NAMES[move.hit_level]])
	lines.append("")
	lines.append("Dash: tap forward twice  ·  Backdash: tap back twice")
	lines.append("Sidestep: L / RB (hold down for toward camera)")
	lines.append("Block: hold back (stand) or down-back (crouch)")
	return "\n".join(lines)


## "236P" -> "↓↘→ P" (numpad motion as arrows, facing right).
static func notation(input: String) -> String:
	var arrows := ""
	var i := 0
	while i < input.length() and input[i].is_valid_int():
		arrows += ARROWS.get(input[i], input[i])
		i += 1
	return arrows + " " + input.substr(i) if arrows != "" else input
