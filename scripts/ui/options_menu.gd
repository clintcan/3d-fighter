extends Control
## Options: volumes (music, effects, announcer, stage ambience), action camera mode, CPU difficulty, display, resolution, graphics. Changes apply and
## save immediately (Settings autoload).

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var voice_slider: HSlider = %VoiceSlider
@onready var ambience_slider: HSlider = %AmbienceSlider
@onready var camera_option: OptionButton = %CameraOption
@onready var difficulty_option: OptionButton = %DifficultyOption
@onready var display_option: OptionButton = %DisplayOption
@onready var window_size_option: OptionButton = %WindowSizeOption
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var graphics_option: OptionButton = %GraphicsOption
@onready var swap_pads_check: CheckButton = %SwapPadsCheck


func _ready() -> void:
	for mode_name in ActionCamera.MODE_NAMES:
		camera_option.add_item(mode_name)
	for level_name in AIController.DIFFICULTY_NAMES:
		difficulty_option.add_item(level_name)
	for display_name in Settings.DISPLAY_NAMES:
		display_option.add_item(display_name)
	for size: Vector2i in Settings.WINDOW_SIZES:
		window_size_option.add_item("%d × %d" % [size.x, size.y])
	for i in Settings.WINDOW_SIZES.size(): # sizes bigger than the screen can't be picked
		window_size_option.set_item_disabled(i, Settings.fitting_window_size(i) != Settings.WINDOW_SIZES[i])
	for resolution_name in Settings.RESOLUTION_NAMES:
		resolution_option.add_item(resolution_name)
	for quality_name in Settings.GRAPHICS_NAMES:
		graphics_option.add_item(quality_name)

	music_slider.value = Settings.music_volume
	sfx_slider.value = Settings.sfx_volume
	voice_slider.value = Settings.voice_volume
	ambience_slider.value = Settings.ambience_volume
	camera_option.selected = Settings.camera_mode
	difficulty_option.selected = Settings.ai_difficulty
	display_option.selected = Settings.display_mode
	window_size_option.selected = Settings.window_size
	window_size_option.disabled = Settings.display_mode != Settings.DisplayMode.WINDOWED
	resolution_option.selected = Settings.resolution
	graphics_option.selected = Settings.graphics
	swap_pads_check.button_pressed = Settings.swap_pads

	music_slider.value_changed.connect(func(v: float) -> void: _change(&"music_volume", v))
	sfx_slider.value_changed.connect(func(v: float) -> void:
		_change(&"sfx_volume", v)
		Audio.sfx(&"hit_light")) # preview
	voice_slider.value_changed.connect(func(v: float) -> void: _change(&"voice_volume", v))
	ambience_slider.value_changed.connect(func(v: float) -> void: _change(&"ambience_volume", v))
	camera_option.item_selected.connect(func(i: int) -> void: _change(&"camera_mode", i))
	difficulty_option.item_selected.connect(func(i: int) -> void: _change(&"ai_difficulty", i))
	display_option.item_selected.connect(func(i: int) -> void:
		_change(&"display_mode", i)
		window_size_option.disabled = i != Settings.DisplayMode.WINDOWED)
	window_size_option.item_selected.connect(func(i: int) -> void: _change(&"window_size", i))
	resolution_option.item_selected.connect(func(i: int) -> void: _change(&"resolution", i))
	graphics_option.item_selected.connect(func(i: int) -> void: _change(&"graphics", i))
	swap_pads_check.toggled.connect(func(on: bool) -> void: _change(&"swap_pads", on))
	%BackButton.pressed.connect(_back)
	%ControlsButton.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/controls.tscn"))
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
