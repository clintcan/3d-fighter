extends Control
## Arcade best scores (main menu): one row per fighter with portrait, best score, stages
## cleared, clear time, continues and perfects. The overall top score gets a gold
## frame. Back or confirm returns to the main menu.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const WALLPAPER := "res://assets/ui/wallpaper.png"
const GOLD := Color(1.0, 0.82, 0.3)
const COLUMNS := ["SCORE", "STAGES", "TIME", "CONTINUES", "PERFECTS"]

var _rows: Array[Control] = []


func _ready() -> void:
	Audio.music(&"menu")
	var background := ColorRect.new()
	background.color = Color(0.03, 0.03, 0.05)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var art := TextureRect.new()
	art.texture = load(WALLPAPER)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.modulate = Color(0.22, 0.22, 0.28)
	add_child(art)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	add_child(column)
	column.add_child(_label("ARCADE BEST SCORES", 64, GOLD, HORIZONTAL_ALIGNMENT_CENTER))

	var header := _row_box(false)
	(header.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a = 0.0
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(72, 0) # portrait column
	header.get_child(0).add_child(spacer)
	header.get_child(0).add_child(_cell("FIGHTER", 24, Color(0.6, 0.62, 0.7), 220, HORIZONTAL_ALIGNMENT_LEFT))
	for title: String in COLUMNS:
		header.get_child(0).add_child(_cell(title, 24, Color(0.6, 0.62, 0.7), 190))
	column.add_child(header)

	var top_score := 0
	for character in GameState.roster:
		top_score = maxi(top_score, ArcadeRun.best_score(character))
	for character in GameState.roster:
		var run := ArcadeRun.best_run(character)
		var score := int(run.get("score", 0))
		var row := _row_box(score > 0 and score == top_score)
		var line: HBoxContainer = row.get_child(0)
		var portrait := TextureRect.new()
		portrait.texture = character.portrait
		portrait.custom_minimum_size = Vector2(72, 72)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		line.add_child(portrait)
		line.add_child(_cell(character.display_name.to_upper(), 34, Color.WHITE, 220, HORIZONTAL_ALIGNMENT_LEFT))
		if score == 0:
			line.add_child(_cell("no clear yet", 28, Color(0.5, 0.5, 0.56), 190 * COLUMNS.size()))
		else:
			var stages := "%d / %d" % [run.stages, GameState.roster.size()] if run.has("stages") else "—"
			if run.get("cleared", false):
				stages = "ALL ✓"
			line.add_child(_cell("%07d" % score, 34, GOLD if score == top_score else Color.WHITE, 190))
			line.add_child(_cell(stages, 30, Color.WHITE, 190))
			line.add_child(_cell(ArcadeRun.time_text(run.ticks) if run.has("ticks") else "—", 30, Color.WHITE, 190))
			line.add_child(_cell(str(run.continues) if run.has("continues") else "—", 30, Color.WHITE, 190))
			line.add_child(_cell(str(run.perfects) if run.has("perfects") else "—", 30, Color.WHITE, 190))
		column.add_child(row)
		_rows.append(row)
	column.add_child(_label("Enter / A or Esc to return", 22, Color(0.55, 0.55, 0.6), HORIZONTAL_ALIGNMENT_CENTER))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.sfx(&"ui_back", -4.0)
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## A centered panel holding one HBox row; `highlight` gives it a gold frame.
func _row_box(highlight: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.75)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	style.set_border_width_all(3 if highlight else 0)
	style.border_color = GOLD
	panel.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(line)
	return panel


func _cell(text: String, size: int, color: Color, width: float, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := _label(text, size, color, align)
	label.custom_minimum_size.x = width
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _label(text: String, size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.horizontal_alignment = align
	return label
