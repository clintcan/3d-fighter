extends Control
## The first scene: the boot splash (same image, same background, so the hand-over from
## the engine's splash is invisible) with a progress bar while the fighters' textures
## load on background threads (GameState.preload_fighters), then the main menu. Loading
## them here keeps the first visit to character select from stalling for seconds.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SPLASH := "res://assets/ui/splash.png"
const BACKGROUND := Color(0.03, 0.03, 0.05) # project.godot boot_splash/bg_color
const GOLD := Color(1.0, 0.82, 0.3)
## The bar only appears if loading takes longer than this (no flash on a fast machine).
const SHOW_BAR_AFTER := 0.25
const BAR_SIZE := Vector2(520, 6)

var _bar: ProgressBar
var _label: Label
var _shown := 0.0 # smoothed progress
var _time := 0.0
var _leaving := false


func _ready() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var splash := TextureRect.new()
	splash.texture = load(SPLASH)
	splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED # boot_splash/fullsize
	add_child(splash)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -18 # below the fighters' name plates
	box.add_theme_constant_override("separation", 5)
	box.modulate.a = 0.0
	add_child(box)
	_label = Label.new()
	_label.text = "LOADING FIGHTERS"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = BAR_SIZE
	_bar.show_percentage = false
	_bar.max_value = 1.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.6)
	track.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", track)
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)

	GameState.preload_fighters()


func _process(delta: float) -> void:
	_time += delta
	var progress := GameState.fighter_preload_progress()
	_shown = move_toward(_shown, progress, delta * 2.5) # glides instead of jumping per texture
	_bar.value = _shown
	var box := _bar.get_parent() as Control
	if _time > SHOW_BAR_AFTER and progress < 1.0:
		box.modulate.a = move_toward(box.modulate.a, 1.0, delta * 5.0)
	if progress >= 1.0 and (_shown >= 1.0 or box.modulate.a == 0.0) and not _leaving:
		_leaving = true
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
