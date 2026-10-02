extends Control

const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"

@onready var start_button: Button = %StartButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	start_button.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
