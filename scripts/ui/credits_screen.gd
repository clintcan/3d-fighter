extends Control
## Credits (main menu): the scrolling credits roll over the darkened key art. Back or
## confirm returns to the main menu; when the roll finishes it waits for a press.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const WALLPAPER := "res://assets/ui/wallpaper.png"

var _roll: CreditsRoll
var _hint: Label


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
	art.modulate = Color(0.16, 0.16, 0.2) # darkened so the text reads
	add_child(art)
	_roll = CreditsRoll.new()
	add_child(_roll)
	_roll.start()
	_hint = Label.new()
	_hint.text = "Enter / A or Esc to return"
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
	_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT) # clear of the scrolling text
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.offset_right = -40
	_hint.offset_top = 30
	add_child(_hint)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.sfx(&"ui_back", -4.0)
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
