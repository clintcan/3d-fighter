extends Control

const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const OPTIONS_SCENE := "res://scenes/options.tscn"

@onready var start_button: Button = %StartButton
@onready var quit_button: Button = %QuitButton
@onready var options_button: Button = %OptionsButton
@onready var versus_button: Button = %VersusButton


func _ready() -> void:
	start_button.pressed.connect(_start.bind(GameState.Mode.VS_CPU))
	versus_button.pressed.connect(_start.bind(GameState.Mode.VERSUS))
	quit_button.pressed.connect(_on_quit_pressed)
	options_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(OPTIONS_SCENE))
	start_button.grab_focus()
	Audio.music(&"menu")
	# `3DFighter.exe -- --smoke-test` jumps straight into a fight (packaging checks).
	if "--smoke-test" in OS.get_cmdline_user_args():
		if "--versus" in OS.get_cmdline_user_args():
			GameState.mode = GameState.Mode.VERSUS
		get_tree().change_scene_to_file.call_deferred("res://scenes/fight.tscn")


func _start(mode: GameState.Mode) -> void:
	GameState.mode = mode
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
