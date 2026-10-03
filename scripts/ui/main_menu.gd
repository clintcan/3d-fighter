extends Control

const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const OPTIONS_SCENE := "res://scenes/options.tscn"
const BEST_SCORES_SCENE := "res://scenes/best_scores.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"

@onready var start_button: Button = %StartButton
@onready var arcade_button: Button = %ArcadeButton
@onready var quit_button: Button = %QuitButton
@onready var options_button: Button = %OptionsButton
@onready var versus_button: Button = %VersusButton
@onready var training_button: Button = %TrainingButton
@onready var best_scores_button: Button = %BestScoresButton
@onready var credits_button: Button = %CreditsButton


const WALLPAPER := "res://assets/ui/wallpaper.png"


func _ready() -> void:
	_add_wallpaper()
	var title := $Center/VBox/Title as Label # gold with a dark outline, like the splash
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.32))
	title.add_theme_constant_override("outline_size", 22)
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.02, 0.0))
	start_button.pressed.connect(_start.bind(GameState.Mode.VS_CPU))
	arcade_button.pressed.connect(_start.bind(GameState.Mode.ARCADE))
	versus_button.pressed.connect(_start.bind(GameState.Mode.VERSUS))
	training_button.pressed.connect(_start.bind(GameState.Mode.TRAINING))
	quit_button.pressed.connect(_on_quit_pressed)
	options_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(OPTIONS_SCENE))
	best_scores_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(BEST_SCORES_SCENE))
	credits_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(CREDITS_SCENE))
	start_button.grab_focus()
	Audio.music(&"menu")
	# `3DFighter.exe -- --smoke-test` jumps straight into a fight (packaging checks).
	if "--smoke-test" in OS.get_cmdline_user_args():
		if "--versus" in OS.get_cmdline_user_args():
			GameState.mode = GameState.Mode.VERSUS
		elif "--training" in OS.get_cmdline_user_args():
			GameState.mode = GameState.Mode.TRAINING
		elif "--arcade" in OS.get_cmdline_user_args():
			GameState.mode = GameState.Mode.ARCADE
			GameState.ensure_selections()
			GameState.start_arcade(GameState.player_character)
		get_tree().change_scene_to_file.call_deferred("res://scenes/fight.tscn")


## Key art behind the menu, darkened toward the center so the buttons stay readable.
func _add_wallpaper() -> void:
	var art := TextureRect.new()
	art.texture = load(WALLPAPER)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	move_child(art, 1) # just above the background color
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.02, 0.04, 0.82))
	gradient.set_color(1, Color(0.02, 0.02, 0.04, 0.35))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.1, 0.5)
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	move_child(shade, 2)


func _start(mode: GameState.Mode) -> void:
	GameState.mode = mode
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
