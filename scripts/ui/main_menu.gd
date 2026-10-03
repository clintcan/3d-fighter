extends Control

const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const OPTIONS_SCENE := "res://scenes/options.tscn"

@onready var start_button: Button = %StartButton
@onready var arcade_button: Button = %ArcadeButton
@onready var quit_button: Button = %QuitButton
@onready var options_button: Button = %OptionsButton
@onready var versus_button: Button = %VersusButton
@onready var training_button: Button = %TrainingButton


func _ready() -> void:
	start_button.pressed.connect(_start.bind(GameState.Mode.VS_CPU))
	arcade_button.pressed.connect(_start.bind(GameState.Mode.ARCADE))
	versus_button.pressed.connect(_start.bind(GameState.Mode.VERSUS))
	training_button.pressed.connect(_start.bind(GameState.Mode.TRAINING))
	quit_button.pressed.connect(_on_quit_pressed)
	options_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(OPTIONS_SCENE))
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


func _start(mode: GameState.Mode) -> void:
	GameState.mode = mode
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
