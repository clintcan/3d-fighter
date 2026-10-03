extends Control
## Character select: portrait roster, a turntable 3D preview of the focused fighter,
## stats and signature moves.
## Vs CPU: pick with any device; the CPU opponent is random.
## Versus: P1 then P2 pick in turn, each with their own controls (up/down to move,
## Light Punch to confirm, Heavy Punch to go back), then the VS screen.
## Training: pick your fighter, then the training dummy, then straight into the fight.

const VS_SCENE := "res://scenes/vs_screen.tscn"
const FIGHT_SCENE := "res://scenes/fight.tscn"
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
@onready var title_label: Label = $Margin/VBox/Title

const PLAYER_COLORS := [Color(0.35, 0.6, 1.0), Color(1.0, 0.4, 0.35)]

var _turntable: Node3D
var _models := {} # CharacterData -> FighterModel
var _focused: CharacterData
# Versus mode state
var _versus := false
var _picking := 0 # 0 = P1 choosing, 1 = P2 choosing
var _cursor := 0
var _p1_pick := -1
var _styles: Array = [] # per button: [normal, focused]
# Training: true once the player's fighter is chosen and the dummy is being picked
var _picking_dummy := false


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
	_versus = GameState.mode == GameState.Mode.VERSUS
	if roster_box.get_child_count() == 0:
		return
	var start := maxi(GameState.roster.find(GameState.player_character), 0)
	if _versus:
		for button in roster_box.get_children():
			(button as Button).focus_mode = Control.FOCUS_NONE # no shared UI navigation
		_cursor = start
		_refresh_versus()
	else:
		(roster_box.get_child(start) as Button).grab_focus()


func _process(delta: float) -> void:
	_turntable.rotate_y(TURNTABLE_SPEED * delta)
	if _focused:
		(_models[_focused] as FighterModel).show_clip(&"fight/guard", -1.0, 1.0, delta)


func _unhandled_input(event: InputEvent) -> void:
	if _versus:
		_versus_input(event)
	elif event.is_action_pressed("ui_cancel"):
		if _picking_dummy:
			Audio.sfx(&"ui_back", -4.0)
			_picking_dummy = false
			title_label.text = "SELECT YOUR FIGHTER"
			get_viewport().set_input_as_handled()
		else:
			_back_to_menu()


func _back_to_menu() -> void:
	Audio.sfx(&"ui_back", -4.0)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _versus_input(event: InputEvent) -> void:
	var prefix := "p%d_" % (_picking + 1)
	var count := roster_box.get_child_count()
	if event.is_action_pressed(prefix + "up"):
		_move_cursor(-1, count)
	elif event.is_action_pressed(prefix + "down"):
		_move_cursor(1, count)
	elif event.is_action_pressed(prefix + "lp"):
		_confirm_versus(_cursor)
	elif event.is_action_pressed(prefix + "hp"):
		if _picking == 1:
			_picking = 0 # P2 backs out: P1 chooses again
			_cursor = _p1_pick
			_p1_pick = -1
			Audio.sfx(&"ui_back", -4.0)
			_refresh_versus()
		else:
			_back_to_menu()
	elif event.is_action_pressed("ui_cancel"):
		if _picking_dummy:
			Audio.sfx(&"ui_back", -4.0)
			_picking_dummy = false
			title_label.text = "SELECT YOUR FIGHTER"
			get_viewport().set_input_as_handled()
		else:
			_back_to_menu()


func _move_cursor(step: int, count: int) -> void:
	_cursor = wrapi(_cursor + step, 0, count)
	Audio.sfx(&"ui_focus", -6.0)
	_refresh_versus()


func _confirm_versus(index: int) -> void:
	Audio.sfx(&"ui_accept", -4.0)
	if _picking == 0:
		_p1_pick = index
		_picking = 1
		_cursor = index # P2 starts on the same fighter; mirror matches are allowed
		_refresh_versus()
		return
	GameState.player_character = GameState.roster[_p1_pick]
	GameState.p2_character = GameState.roster[index]
	get_tree().change_scene_to_file(VS_SCENE)


## Title, hint, cursor highlight and P1's locked pick for the player currently choosing.
func _refresh_versus() -> void:
	var player := _picking + 1
	($Margin/VBox/Title as Label).text = "PLAYER %d  -  SELECT YOUR FIGHTER" % player
	($Margin/VBox/Hint as Label).text = "PLAYER %d:  %s  ·  Light Punch to select  ·  Heavy Punch to go back" % [
		player, "W / S or stick" if player == 1 else "Up / Down arrows or stick"]
	for i in roster_box.get_child_count():
		var button := roster_box.get_child(i) as Button
		var character: CharacterData = GameState.roster[i]
		var style: StyleBoxFlat = (_styles[i][1] if i == _cursor else _styles[i][0]).duplicate()
		if i == _cursor:
			style.border_color = PLAYER_COLORS[_picking]
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.text = character.display_name + ("   P1" if i == _p1_pick else "")
	_show_details(GameState.roster[_cursor])


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
	_styles.append([normal, focused])

	button.focus_entered.connect(_show_details.bind(character))
	button.mouse_entered.connect(func() -> void:
		if not _versus:
			button.grab_focus())
	button.pressed.connect(func() -> void:
		if _versus:
			_confirm_versus(GameState.roster.find(character))
		else:
			_select(character))
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
	if GameState.mode == GameState.Mode.TRAINING:
		if not _picking_dummy:
			GameState.player_character = character
			_picking_dummy = true
			title_label.text = "SELECT TRAINING DUMMY"
			return
		GameState.p2_character = character
		get_tree().change_scene_to_file(FIGHT_SCENE)
		return
	GameState.player_character = character
	GameState.p2_character = GameState.pick_random_cpu()
	get_tree().change_scene_to_file(VS_SCENE)
