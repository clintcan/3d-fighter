extends Control
## Character select: portrait roster, a 3D preview of the focused fighter performing a
## routine that matches their CPU personality (FighterShowcase), stats and moves.
## Vs CPU: pick with any device; the CPU opponent is random.
## Versus: P1 then P2 pick in turn, each with their own controls (up/down to move,
## Light Punch to confirm, Heavy Punch to go back), then the VS screen.
## Training: pick your fighter, then the training dummy, then straight into the fight.
## Arcade: pick your fighter; the ladder of opponents is generated (GameState.arcade).
## Online: each player picks on their own machine; once both have, the host picks the
## stage and the guest waits (Net autoload). Back un-picks, then leaves.
## Vs CPU, Versus and Training continue to the stage select.

const VS_SCENE := "res://scenes/vs_screen.tscn"
const STAGE_SELECT_SCENE := "res://scenes/stage_select.tscn"
const FIGHT_SCENE := "res://scenes/fight.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const ONLINE_MENU_SCENE := "res://scenes/online_menu.tscn"
const HEALTH_SCALE := 1200.0 # max_health shown as a full bar

@onready var roster_box: GridContainer = %Roster
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
var _showcase: FighterShowcase
var _effects: Node3D # showcase effects, outside the turning turntable
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
	roster_box.columns = _columns()
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
	if GameState.is_online():
		_add_security_badge()
		Net.lobby_changed.connect(_refresh_online)
		_refresh_online()


func _exit_tree() -> void:
	if Net.lobby_changed.is_connected(_refresh_online):
		Net.lobby_changed.disconnect(_refresh_online)


func _process(delta: float) -> void:
	if _showcase:
		_showcase.process(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _versus:
		_versus_input(event)
	elif GameState.is_online() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.sfx(&"ui_back", -4.0)
		if Net.local_pick >= 0:
			Net.pick(-1) # change your mind
		else:
			Net.leave()
			get_tree().change_scene_to_file(Net.SERVER_LOBBY_SCENE if Net.is_server_open() else ONLINE_MENU_SCENE)
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
		_move_cursor(-roster_box.columns, count)
	elif event.is_action_pressed(prefix + "down"):
		_move_cursor(roster_box.columns, count)
	elif roster_box.columns > 1 and event.is_action_pressed(prefix + "left"):
		_move_cursor(-1, count)
	elif roster_box.columns > 1 and event.is_action_pressed(prefix + "right"):
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


## Portraits per row: one column up to five fighters, then two.
func _columns() -> int:
	return 1 if GameState.roster.size() <= 5 else 2


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
	get_tree().change_scene_to_file(STAGE_SELECT_SCENE)


## Title, hint, cursor highlight and P1's locked pick for the player currently choosing.
func _refresh_versus() -> void:
	var player := _picking + 1
	($Margin/VBox/Title as Label).text = "PLAYER %d  -  SELECT YOUR FIGHTER" % player
	($Margin/VBox/Hint as Label).text = "PLAYER %d:  %s  ·  Light Punch to select  ·  Heavy Punch to go back" % [
		player, ("WASD or stick" if player == 1 else "Arrows or stick") if roster_box.columns > 1
			else ("W / S or stick" if player == 1 else "Up / Down arrows or stick")]
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
	_effects = Node3D.new()
	viewport.add_child(_effects)

	var camera := Camera3D.new()
	camera.fov = 32.0
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0, 1.25, -4.8), Vector3(0, 0.95, 0))
	camera.current = true


func _make_portrait_button(character: CharacterData) -> Button:
	var button := Button.new()
	# Portraits shrink so the whole roster fits the column (240 px for three fighters);
	# past five fighters they go two to a row.
	var count := maxi(GameState.roster.size(), 1)
	var rows := ceili(float(count) / _columns())
	var side := clampf((760.0 - 18.0 * (rows - 1)) / rows, 140.0, 240.0)
	button.custom_minimum_size = Vector2(side, side)
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
	var model := _models[character] as FighterModel
	model.visible = true
	_showcase = FighterShowcase.new(model, character, _turntable, _effects)

	name_label.text = character.display_name.to_upper()
	archetype_label.text = character.archetype
	var style: Dictionary = AIController.PERSONALITIES.get(character.id, AIController.DEFAULT_PERSONALITY)
	description_label.text = "%s
As CPU: %s, %s." % [character.description, style.name, style.blurb]
	power_bar.value = character.power_rating
	speed_bar.value = character.speed_rating
	health_bar.value = character.max_health / HEALTH_SCALE
	var lines := PackedStringArray()
	for move in character.moves:
		if move.is_special():
			lines.append("%s   %s%s" % [FightHud.notation(move.input), move.name, "  (super)" if move.super_move else ""])
	for move in character.moves:
		if move.input.length() == 3 and (move.input.begins_with("6") or move.input.begins_with("4")):
			lines.append("%s   %s" % [move.input, move.name])
	signature_label.text = "\n".join(lines)


## Online: the connection's security code, top right. Both players should see the same
## number; if they don't, someone is intercepting the connection.
func _add_security_badge() -> void:
	var badge := Label.new()
	badge.text = "SECURITY CODE  %s\nShould match your opponent's screen" % Net.security_code()
	badge.add_theme_font_size_override("font_size", 20)
	badge.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	badge.add_theme_constant_override("outline_size", 6)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.offset_top = 18
	badge.offset_right = -24
	add_child(badge)


## Online: titles for where the lobby stands; the host moves on once both have picked.
func _refresh_online() -> void:
	var hint := $Margin/VBox/Hint as Label
	var opponent := Net.opponent_name()
	var their_status := "choosing..." if Net.remote_pick < 0 else "ready"
	hint.text = "Online vs %s  ·  Opponent: %s  ·  Enter / A to select  ·  Esc to %s" % [
		opponent, their_status, "change your pick" if Net.local_pick >= 0 else "leave"]
	if Net.local_pick < 0:
		title_label.text = "SELECT YOUR FIGHTER"
	elif not Net.both_picked():
		title_label.text = "WAITING FOR %s..." % opponent.to_upper()
	elif Net.is_host():
		get_tree().change_scene_to_file(STAGE_SELECT_SCENE)
	else:
		title_label.text = "%s IS CHOOSING THE STAGE..." % opponent.to_upper()


func _select(character: CharacterData) -> void:
	if GameState.is_online():
		Audio.sfx(&"ui_accept", -4.0)
		Net.pick(GameState.roster.find(character))
		return
	if GameState.mode == GameState.Mode.TRAINING:
		if not _picking_dummy:
			GameState.player_character = character
			_picking_dummy = true
			title_label.text = "SELECT TRAINING DUMMY"
			return
		GameState.p2_character = character
		get_tree().change_scene_to_file(STAGE_SELECT_SCENE)
		return
	if GameState.mode == GameState.Mode.ARCADE:
		GameState.start_arcade(character)
		get_tree().change_scene_to_file(VS_SCENE)
		return
	GameState.player_character = character
	GameState.p2_character = GameState.pick_random_cpu()
	get_tree().change_scene_to_file(STAGE_SELECT_SCENE)
