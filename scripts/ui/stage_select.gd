extends Control
## Stage select (after character select in Vs CPU, Versus and Training): a card per
## stage from GameState.STAGES plus Random. Left/right to choose, confirm to fight,
## back to return to character select. Any player's controls work.

const VS_SCENE := "res://scenes/vs_screen.tscn"
const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const MAX_CARD_WIDTH := 560.0
const CARD_GAP := 36
const GOLD := Color(1.0, 0.82, 0.3)

var _cards: Array[Button] = []
var _card_size := Vector2(MAX_CARD_WIDTH, MAX_CARD_WIDTH * 9.0 / 16.0)
var _name_label: Label
var _blurb_label: Label
var _leaving := false


func _ready() -> void:
	Audio.music(&"menu")
	var background := ColorRect.new()
	background.color = Color(0.04, 0.045, 0.07)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 34)
	add_child(column)
	column.add_child(_label("SELECT STAGE", 72, Color.WHITE))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", CARD_GAP)
	column.add_child(row)
	var entries: Array = GameState.STAGES.duplicate()
	entries.append({path = "", name = "Random", thumb = "", blurb = "Let fate decide."})
	# Cards shrink to fit however many stages there are (16:9 thumbnails).
	var available := get_viewport_rect().size.x - 120.0 - CARD_GAP * (entries.size() - 1)
	var width := minf(MAX_CARD_WIDTH, available / entries.size() - 16.0)
	_card_size = Vector2(width, width * 9.0 / 16.0)
	for entry: Dictionary in entries:
		row.add_child(_make_card(entry))

	_name_label = _label("", 56, GOLD)
	column.add_child(_name_label)
	_blurb_label = _label("", 28, Color(0.75, 0.78, 0.85))
	column.add_child(_blurb_label)
	column.add_child(_label("Left / Right to choose  ·  Enter / A to fight  ·  Esc to go back", 22, Color(0.5, 0.5, 0.55)))

	for i in _cards.size():
		_cards[i].focus_neighbor_left = _cards[(i - 1 + _cards.size()) % _cards.size()].get_path()
		_cards[i].focus_neighbor_right = _cards[(i + 1) % _cards.size()].get_path()
	var current := GameState.STAGES.map(func(s: Dictionary) -> String: return s.path).find(GameState.stage_path)
	_cards[maxi(current, 0)].grab_focus()
	if GameState.is_online():
		Net.lobby_changed.connect(_on_lobby_changed)


func _exit_tree() -> void:
	if Net.lobby_changed.is_connected(_on_lobby_changed):
		Net.lobby_changed.disconnect(_on_lobby_changed)


## Online (host): the guest changed their mind; back to character select.
func _on_lobby_changed() -> void:
	if not Net.both_picked() and not _leaving:
		_leaving = true
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _make_card(entry: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = _card_size + Vector2(16, 16)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.08, 0.12)
	normal.set_border_width_all(3)
	normal.border_color = Color(0.25, 0.25, 0.3)
	normal.set_corner_radius_all(8)
	var focused := normal.duplicate() as StyleBoxFlat
	focused.set_border_width_all(6)
	focused.border_color = GOLD
	for state in ["normal", "disabled"]:
		card.add_theme_stylebox_override(state, normal)
	for state in ["hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(state, focused)

	if entry.thumb != "" and ResourceLoader.exists(entry.thumb):
		var image := TextureRect.new()
		image.texture = load(entry.thumb)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.set_anchors_preset(Control.PRESET_FULL_RECT)
		image.offset_left = 8
		image.offset_top = 8
		image.offset_right = -8
		image.offset_bottom = -8
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(image)
	else:
		var mark := _label("?", int(_card_size.y * 0.6), Color(0.6, 0.6, 0.7))
		mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.add_child(mark)

	card.focus_entered.connect(func() -> void:
		_name_label.text = String(entry.name).to_upper()
		_blurb_label.text = entry.blurb)
	card.mouse_entered.connect(card.grab_focus)
	card.pressed.connect(_choose.bind(entry.path))
	_cards.append(card)
	return card


## Empty path = random stage.
func choose(path: String) -> void:
	_choose(path)


func _choose(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	if path == "":
		path = (GameState.STAGES.pick_random() as Dictionary).path
	GameState.stage_path = path
	if GameState.is_online():
		Net.start_match(path) # tells the guest and moves both to the VS screen
		return
	if GameState.mode == GameState.Mode.TRAINING:
		GameState.go_to_fight(get_tree())
	else:
		get_tree().change_scene_to_file(VS_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _leaving:
		Audio.sfx(&"ui_back", -4.0)
		_leaving = true
		if GameState.is_online():
			Net.pick(-1) # the host picks again
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
