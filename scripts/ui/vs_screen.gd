extends Control
## "P1 VS P2" splash between character select and the fight. Portraits slide in from
## the sides, "VS" punches in, then the fight loads. Confirm skips it. In Arcade mode it
## also shows the stage number and the ladder, and the boss's portrait is darkened.

const FIGHT_SCENE := "res://scenes/fight.tscn"
const HOLD_SECONDS := 2.2
const LADDER_ICON := Vector2(110, 110)
const SHADOW_TINT := Color(0.55, 0.35, 0.75)

@onready var left_portrait: TextureRect = %LeftPortrait
@onready var right_portrait: TextureRect = %RightPortrait
@onready var left_name: Label = %LeftName
@onready var right_name: Label = %RightName
@onready var vs_label: Label = %VsLabel
@onready var left_side: Control = %LeftSide
@onready var right_side: Control = %RightSide

var _leaving := false


func _ready() -> void:
	GameState.ensure_selections()
	left_portrait.texture = GameState.player_character.portrait
	right_portrait.texture = GameState.p2_character.portrait
	var versus := GameState.mode == GameState.Mode.VERSUS
	left_name.text = ("P1  " if versus else "") + GameState.player_character.display_name.to_upper()
	right_name.text = "%s (%s)" % [GameState.p2_character.display_name.to_upper(), "P2" if versus else "CPU"]
	if GameState.is_arcade():
		_show_arcade_ladder()
	else:
		_show_stage_name()
	# Wait a frame so containers have laid out, then animate from off-screen.
	await get_tree().process_frame
	var width := get_viewport_rect().size.x
	var left_home := left_side.position
	var right_home := right_side.position
	left_side.position.x -= width * 0.6
	right_side.position.x += width * 0.6
	vs_label.pivot_offset = vs_label.size / 2.0
	vs_label.scale = Vector2(3, 3)
	vs_label.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(left_side, "position", left_home, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(right_side, "position", right_home, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(vs_label, "scale", Vector2.ONE, 0.3).set_delay(0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(vs_label, "modulate:a", 1.0, 0.15).set_delay(0.35)
	get_tree().create_timer(HOLD_SECONDS).timeout.connect(_go)


func _show_stage_name() -> void:
	var label := Label.new()
	label.text = GameState.stage_name(GameState.stage_path).to_upper()
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_bottom = -50
	add_child(label)


## Stage title above "VS" and a row of opponent portraits along the bottom: beaten
## ones dimmed, the current one framed in gold, the boss as a silhouette until reached.
func _show_arcade_ladder() -> void:
	var run := GameState.arcade
	right_name.text = run.opponent_title()
	if run.current().boss:
		right_portrait.modulate = SHADOW_TINT
		right_name.text += "\nFINAL BOSS"
		Audio.voice("prepare_yourself")
	var title := Label.new()
	title.text = "FINAL STAGE" if run.is_final() else "STAGE %d / %d" % [run.stage + 1, run.stages.size()]
	title.text += "  ·  " + GameState.stage_name(GameState.stage_path).to_upper()
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 40
	add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_bottom = -36
	add_child(row)
	for i in run.stages.size():
		var entry: Dictionary = run.stages[i]
		var frame := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
		style.set_border_width_all(4 if i == run.stage else 2)
		style.border_color = Color(1.0, 0.82, 0.3) if i == run.stage else Color(0.3, 0.3, 0.36)
		frame.add_theme_stylebox_override("panel", style)
		var icon := TextureRect.new()
		icon.texture = (entry.character as CharacterData).portrait
		icon.custom_minimum_size = LADDER_ICON
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if entry.boss:
			icon.modulate = SHADOW_TINT if i <= run.stage else Color(0.05, 0.05, 0.08)
		elif i < run.stage:
			icon.modulate = Color(0.35, 0.35, 0.35) # beaten
		frame.add_child(icon)
		row.add_child(frame)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_go()


func _go() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(FIGHT_SCENE)
