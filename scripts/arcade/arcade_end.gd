extends Control
## Arcade results. A cleared run shows "ARCADE CLEAR" with the stats, then (on confirm
## or after a while) rolls the credits; a run given up shows "GAME OVER" and returns to
## the main menu. The score is saved as the character's best if it beats it.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const GOLD := Color(1.0, 0.82, 0.3)
const AUTO_CREDITS_SECONDS := 8.0
const CREDITS_SPEED := 90.0 # pixels per second
const CREDITS := [
	["3D FIGHTER", ""],
	["", ""],
	["Made with", "Godot Engine (MIT License)"],
	["", ""],
	["Characters & animations", "Quaternius: Universal Base Characters,\nUniversal Animation Library 1 & 2 (CC0)"],
	["Stage lighting & textures", "Poly Haven: \"Basement Boxing Ring\" HDRI by Sergej\nMajboroda; Terlenka, Fabric Leather 02,\nConcrete Floor Worn 001 (CC0)"],
	["Dojo textures", "Poly Haven: Tatami Mat, Hinoki Planks, Japanese Cedar Planks\n(Charlotte Baglioni, Rico Cilliers), Dark Wood (Dario Barresi,\nDimitrios Savva, Rico Cilliers), White Plaster 02 (Rob Tuytel) (CC0)"],
	["Music", "\"Heavy Battle 2\" and \"Space Battle\" by MintoDog, \"Determination\"\nby HydroGene, \"Midnight Drive\" by congusbongus (OpenGameArt, CC0)"],
	["Fighter voices", "\"Male Grunt/Yelling sounds\" by HaelDB, \"Female Hurt\nGrunts & Groans\" by AuraVoice (OpenGameArt, CC0)"],
	["Sound effects & announcer", "Kenney: Impact Sounds, Interface Sounds,\nVoiceover Pack: Fighter (CC0)"],
	["Rooftop skyline", "Poly Haven: \"Shanghai Bund\" HDRI by Greg Zaal (CC0)"],
	["Made for this project", "Ring, arena, dojo, rooftop and crowds, fight and special-move\nanimations, portraits, swing, energy and super sounds"],
	["", ""],
	["THANKS FOR PLAYING!", ""],
]

var _run: ArcadeRun
var _results: Control
var _credits: VBoxContainer
var _rolling := false
var _done := false
var _time := 0.0
var _record_label: Label


func _ready() -> void:
	Audio.music(&"menu")
	_run = GameState.arcade
	if _run == null: # scene run on its own (editor F6): show a sample cleared run
		GameState.ensure_selections()
		_run = ArcadeRun.create(GameState.player_character, GameState.roster, 1, 1, GameState.arcade_arenas(), GameState.DOJO_STAGE)
		_run.cleared = true
	var previous_best := ArcadeRun.best_score(_run.player)
	var record := _run.record_best()

	var background := ColorRect.new()
	background.color = Color(0.03, 0.03, 0.06)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	_results = HBoxContainer.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	(_results as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_results.add_theme_constant_override("separation", 80)
	add_child(_results)

	var portrait := TextureRect.new()
	portrait.texture = _run.player.portrait
	portrait.custom_minimum_size = Vector2(560, 560)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not _run.cleared:
		portrait.modulate = Color(0.45, 0.45, 0.5)
	_results.add_child(portrait)

	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 14)
	_results.add_child(column)
	column.add_child(_label("ARCADE CLEAR" if _run.cleared else "GAME OVER", 96, GOLD if _run.cleared else Color(1, 0.35, 0.3)))
	column.add_child(_label(_run.player.display_name.to_upper(), 40, Color(0.75, 0.8, 0.9)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 50)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	var stages_cleared := _run.stages.size() if _run.cleared else _run.stage
	for row in [
		["SCORE", "%07d" % _run.score],
		["STAGES", "%d / %d" % [stages_cleared, _run.stages.size()]],
		["TIME", _run.clear_time_text()],
		["CONTINUES", str(_run.continues)],
		["PERFECTS", str(_run.perfects)],
		["BEST", "%07d" % maxi(previous_best, _run.score)],
	]:
		grid.add_child(_label(row[0], 34, Color(0.7, 0.7, 0.75)))
		grid.add_child(_label(row[1], 34, Color.WHITE))
	if record:
		_record_label = _label("NEW RECORD!", 44, GOLD)
		column.add_child(_record_label)
	column.add_child(_label("Enter / A to continue", 24, Color(0.5, 0.5, 0.55)))

	Audio.voice("winner" if _run.cleared else "game_over")


func _process(delta: float) -> void:
	_time += delta
	if _record_label:
		_record_label.modulate.a = 0.6 + 0.4 * sin(_time * 6.0)
	if _run.cleared and not _rolling and not _done and _time >= AUTO_CREDITS_SECONDS:
		_start_credits()
	if _rolling:
		_credits.position.y -= CREDITS_SPEED * delta
		if _credits.position.y + _credits.size.y < get_viewport_rect().size.y * 0.5:
			_rolling = false # the last line (THANKS FOR PLAYING) rests mid-screen
			_done = true


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept"):
		return
	get_viewport().set_input_as_handled()
	if _run.cleared and _credits == null:
		_start_credits()
	else:
		_finish()


func _start_credits() -> void:
	_results.visible = false
	_rolling = true
	_credits = VBoxContainer.new()
	_credits.add_theme_constant_override("separation", 34)
	_credits.custom_minimum_size.x = get_viewport_rect().size.x
	for entry in CREDITS:
		if entry[0] == "" and entry[1] == "":
			var gap := Control.new()
			gap.custom_minimum_size.y = 60
			_credits.add_child(gap)
			continue
		var big: bool = entry[1] == ""
		_credits.add_child(_label(entry[0], 72 if big else 30, GOLD if big else Color(0.65, 0.7, 0.8), true))
		if not big:
			_credits.add_child(_label(entry[1], 34, Color.WHITE, true))
	add_child(_credits)
	_credits.position = Vector2(0, get_viewport_rect().size.y)


func _finish() -> void:
	GameState.arcade = null
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _label(text: String, size: int, color: Color, centered := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
