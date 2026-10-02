class_name FightHud
extends CanvasLayer
## Health bars, names, combo counters, and center announcements.
## Milestone 2: minimal. Damage trail, round pips and timer come in milestone 8.

@onready var p1_health: ProgressBar = %P1Health
@onready var p2_health: ProgressBar = %P2Health
@onready var p1_name: Label = %P1Name
@onready var p2_name: Label = %P2Name
@onready var p1_combo: Label = %P1Combo
@onready var p2_combo: Label = %P2Combo
@onready var p1_note: Label = %P1Note
@onready var p2_note: Label = %P2Note
@onready var center_label: Label = %CenterLabel
@onready var debug_label: Label = %DebugLabel


func setup(p1: Fighter, p2: Fighter) -> void:
	p1_name.text = p1.data.display_name
	p2_name.text = "%s (CPU)" % p2.data.display_name
	_bind_health(p1, p1_health)
	_bind_health(p2, p2_health)
	# A combo is shown on the attacker's side, so P2's hits taken appear under P1.
	p2.combo_changed.connect(_on_combo_changed.bind(p1_combo))
	p1.combo_changed.connect(_on_combo_changed.bind(p2_combo))
	p1_combo.text = ""
	p2_combo.text = ""
	p1_note.text = ""
	p2_note.text = ""
	center_label.text = ""


func announce(text: String) -> void:
	center_label.text = text


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


func _bind_health(fighter: Fighter, bar: ProgressBar) -> void:
	bar.max_value = fighter.data.max_health
	bar.value = fighter.health
	fighter.health_changed.connect(func(current: int, maximum: int) -> void:
		bar.max_value = maximum
		bar.value = current)


func _on_combo_changed(hits: int, label: Label) -> void:
	label.text = "%d HITS" % hits if hits >= 2 else ""
