extends Control
## Character select: portrait roster, a turntable 3D preview of the focused fighter,
## stats and signature moves. Selecting picks a random CPU opponent and goes to the VS
## screen.

const VS_SCENE := "res://scenes/vs_screen.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const TURNTABLE_SPEED := 0.5 # rad/s
const HEALTH_SCALE := 1200.0 # max_health shown as a full bar

@onready var roster_box: VBoxContainer = %Roster
@onready var viewport: SubViewport = %Viewport
@onready var name_label: Label = %NameLabel
@onready var archetype_label: Label = %ArchetypeLabel
@onready var description_label: Label = %DescriptionLabel
@onready var power_bar: ProgressBar = %PowerBar
@onready var speed_bar: ProgressBar = %SpeedBar
@onready var health_bar: ProgressBar = %HealthBar
@onready var signature_label: Label = %SignatureLabel

var _turntable: Node3D
var _models := {} # CharacterData -> FighterModel
var _focused: CharacterData


func _ready() -> void:
	Audio.music(&"menu")
	Audio.voice("choose_your_character")
	_build_preview_stage()
	for character in GameState.roster:
		roster_box.add_child(_make_portrait_button(character))
		var model := FighterModel.new()
		_turntable.add_child(model)
		model.build(character)
		model.visible = false
		_models[character] = model
	if roster_box.get_child_count() > 0:
		var start := GameState.roster.find(GameState.player_character)
		(roster_box.get_child(maxi(start, 0)) as Button).grab_focus()


func _process(delta: float) -> void:
	_turntable.rotate_y(TURNTABLE_SPEED * delta)
	if _focused:
		(_models[_focused] as FighterModel).show_clip(&"fight/guard", -1.0, 1.0, delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Audio.sfx(&"ui_back", -4.0)
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _build_preview_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var key := SpotLight3D.new()
	key.light_energy = 18.0
	key.spot_range = 10.0
	key.spot_angle = 30.0
	key.shadow_enabled = true
	viewport.add_child(key)
	key.look_at_from_position(Vector3(1.2, 4.5, -2.5), Vector3(0, 0.9, 0))
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.8
	rim.light_color = Color(0.5, 0.65, 1.0)
	viewport.add_child(rim)
	rim.look_at_from_position(Vector3(-1.0, 2.0, 2.0), Vector3(0, 1.0, 0))

	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 1.1
	floor_mesh.bottom_radius = 1.1
	floor_mesh.height = 0.06
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.1, 0.1, 0.13)
	floor_mat.metallic = 0.5
	floor_mat.roughness = 0.3
	floor_mesh.material = floor_mat
	var floor_disc := MeshInstance3D.new()
	floor_disc.mesh = floor_mesh
	floor_disc.position.y = -0.03
	viewport.add_child(floor_disc)

	_turntable = Node3D.new()
	viewport.add_child(_turntable)

	var camera := Camera3D.new()
	camera.fov = 32.0
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0, 1.25, -4.8), Vector3(0, 0.95, 0))
	camera.current = true


func _make_portrait_button(character: CharacterData) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(240, 240)
	button.icon = character.portrait
	button.expand_icon = true
	button.text = character.display_name
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.add_theme_font_size_override("font_size", 26)

	var normal := StyleBoxFlat.new()
	normal.bg_color = character.placeholder_color.darkened(0.7)
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(3)
	normal.border_color = character.placeholder_color.darkened(0.3)
	var focused := normal.duplicate() as StyleBoxFlat
	focused.bg_color = character.placeholder_color.darkened(0.4)
	focused.set_border_width_all(5)
	focused.border_color = Color(1, 0.85, 0.3)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", focused)
	button.add_theme_stylebox_override("pressed", focused)
	button.add_theme_stylebox_override("focus", focused)

	button.focus_entered.connect(_show_details.bind(character))
	button.mouse_entered.connect(button.grab_focus)
	button.pressed.connect(_select.bind(character))
	return button


func _show_details(character: CharacterData) -> void:
	if _focused:
		(_models[_focused] as FighterModel).visible = false
	_focused = character
	(_models[character] as FighterModel).visible = true
	_turntable.rotation.y = 0.0

	name_label.text = character.display_name.to_upper()
	archetype_label.text = character.archetype
	description_label.text = character.description
	power_bar.value = character.power_rating
	speed_bar.value = character.speed_rating
	health_bar.value = character.max_health / HEALTH_SCALE
	var lines := PackedStringArray()
	for move in character.moves:
		if move.input.begins_with("6") or move.input.begins_with("4"):
			lines.append("%s   %s" % [move.input, move.name])
	signature_label.text = "\n".join(lines)


func _select(character: CharacterData) -> void:
	GameState.player_character = character
	GameState.cpu_character = GameState.pick_random_cpu()
	get_tree().change_scene_to_file(VS_SCENE)
