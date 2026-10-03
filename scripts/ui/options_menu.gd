extends Control
## Options: volumes, action camera mode, CPU difficulty, fullscreen. Changes apply and
## save immediately (Settings autoload).

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var voice_slider: HSlider = %VoiceSlider
@onready var camera_option: OptionButton = %CameraOption
@onready var difficulty_option: OptionButton = %DifficultyOption
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var swap_pads_check: CheckButton = %SwapPadsCheck


func _ready() -> void:
	for mode_name in ActionCamera.MODE_NAMES:
		camera_option.add_item(mode_name)
	for level_name in AIController.DIFFICULTY_NAMES:
		difficulty_option.add_item(level_name)

	music_slider.value = Settings.music_volume
	sfx_slider.value = Settings.sfx_volume
	voice_slider.value = Settings.voice_volume
	camera_option.selected = Settings.camera_mode
	difficulty_option.selected = Settings.ai_difficulty
	fullscreen_check.button_pressed = Settings.fullscreen
	swap_pads_check.button_pressed = Settings.swap_pads

	music_slider.value_changed.connect(func(v: float) -> void: _change(&"music_volume", v))
	sfx_slider.value_changed.connect(func(v: float) -> void:
		_change(&"sfx_volume", v)
		Audio.sfx(&"hit_light")) # preview
	voice_slider.value_changed.connect(func(v: float) -> void: _change(&"voice_volume", v))
	camera_option.item_selected.connect(func(i: int) -> void: _change(&"camera_mode", i))
	difficulty_option.item_selected.connect(func(i: int) -> void: _change(&"ai_difficulty", i))
	fullscreen_check.toggled.connect(func(on: bool) -> void: _change(&"fullscreen", on))
	swap_pads_check.toggled.connect(func(on: bool) -> void: _change(&"swap_pads", on))
	%BackButton.pressed.connect(_back)
	music_slider.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()


func _change(setting: StringName, value: Variant) -> void:
	Settings.set(setting, value)
	Settings.apply()
	Settings.save_settings()


func _back() -> void:
	Audio.sfx(&"ui_back", -4.0)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
