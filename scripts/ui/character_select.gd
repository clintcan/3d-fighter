extends Control
## Builds one portrait button per roster entry. Selecting a character picks a
## random CPU opponent and starts the fight.
## TODO: 3D turntable preview of the focused character once models are imported.

const FIGHT_SCENE := "res://scenes/fight.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var portrait_row: HBoxContainer = %PortraitRow
@onready var name_label: Label = %NameLabel
@onready var archetype_label: Label = %ArchetypeLabel
@onready var description_label: Label = %DescriptionLabel


func _ready() -> void:
	for character in GameState.roster:
		portrait_row.add_child(_make_portrait_button(character))
	if portrait_row.get_child_count() > 0:
		(portrait_row.get_child(0) as Button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _make_portrait_button(character: CharacterData) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(240, 300)
	button.text = character.display_name
	button.icon = character.portrait
	button.expand_icon = true
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.add_theme_font_size_override("font_size", 32)

	# Placeholder color blocks until real portraits exist.
	var normal := StyleBoxFlat.new()
	normal.bg_color = character.placeholder_color.darkened(0.55)
	normal.set_corner_radius_all(10)
	var focused := normal.duplicate() as StyleBoxFlat
	focused.bg_color = character.placeholder_color.darkened(0.15)
	focused.set_border_width_all(4)
	focused.border_color = Color.WHITE
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", focused)
	button.add_theme_stylebox_override("pressed", focused)
	button.add_theme_stylebox_override("focus", focused)

	button.focus_entered.connect(_show_details.bind(character))
	button.mouse_entered.connect(button.grab_focus)
	button.pressed.connect(_select.bind(character))
	return button


func _show_details(character: CharacterData) -> void:
	name_label.text = character.display_name
	archetype_label.text = "%s  ·  HP %d  ·  Speed %.1f" % [character.archetype, character.max_health, character.walk_speed]
	description_label.text = character.description


func _select(character: CharacterData) -> void:
	GameState.player_character = character
	GameState.cpu_character = GameState.pick_random_cpu()
	get_tree().change_scene_to_file(FIGHT_SCENE)
