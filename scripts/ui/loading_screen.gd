extends Control
## Loading screen shown while a fight loads: the key-art wallpaper, the matchup and
## stage, a progress bar and a gameplay tip. The fight scene and its stage load on a
## background thread (ResourceLoader.load_threaded_request); FightManager's own load()
## of the stage then comes straight from the cache. Use GameState.go_to_fight().

const FIGHT_SCENE := "res://scenes/fight.tscn"
const WALLPAPER := "res://assets/ui/wallpaper.png"
const GOLD := Color(1.0, 0.82, 0.3)
## Shown at least this long so the screen doesn't just flash.
const MIN_SECONDS := 0.6
const TIPS := [
	"Hold back to block. Hold down-back to block lows; overheads must be blocked standing.",
	"Normals that connect can be cancelled into a special move.",
	"Fill the SUPER meter, then input the motion twice + punch or kick for your super.",
	"Light Punch + Light Kick up close throws. Press it again as you're grabbed to break free.",
	"Sidestep (L / RB) to dodge fireballs and step around attacks.",
	"Rising Dragon and Crescent Rise are invincible as they start: perfect against jump-ins.",
	"Tap forward twice to dash in, back twice to backdash out.",
	"Hitting an opponent during their attack's startup is a COUNTER hit: more damage, more stun.",
	"Training mode shows live frame data. Plus frames mean it's your turn.",
	"Brutus's Earthquake hits low: crouch-block it, or jump it.",
]

var _paths: Array[String] = []
var _bar: ProgressBar
var _percent: Label
var _shown := 0.0
var _elapsed := 0.0
var _done := false


func _ready() -> void:
	_paths = [FIGHT_SCENE, GameState.stage_path]
	for path in _paths:
		ResourceLoader.load_threaded_request(path)
	_build()


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	var total := 0.0
	var all_loaded := true
	for path in _paths:
		var progress := []
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				total += 1.0
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				total += float(progress[0]) if not progress.is_empty() else 0.0
				all_loaded = false
			_:
				push_error("Loading failed: %s" % path)
				all_loaded = false
	var target := total / _paths.size()
	_shown = move_toward(_shown, target, delta * 2.5) # smooth, never jumps backwards
	_bar.value = _shown
	_percent.text = "%d%%" % roundi(_shown * 100.0)
	if all_loaded and _shown >= 0.999 and _elapsed >= MIN_SECONDS:
		_done = true
		GameState.preloaded_stage = ResourceLoader.load_threaded_get(GameState.stage_path)
		var fight := ResourceLoader.load_threaded_get(FIGHT_SCENE) as PackedScene
		get_tree().change_scene_to_packed(fight)


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.03, 0.03, 0.05)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var art := TextureRect.new()
	art.texture = load(WALLPAPER)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(art)
	# Darken the lower part so the text reads.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.0))
	gradient.set_color(1, Color(0, 0, 0, 0.85))
	var shade_tex := GradientTexture2D.new()
	shade_tex.gradient = gradient
	shade_tex.fill_from = Vector2(0.5, 0.35)
	shade_tex.fill_to = Vector2(0.5, 1.0)
	shade.texture = shade_tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_left = 120
	column.offset_right = -120
	column.offset_bottom = -70
	add_child(column)
	GameState.ensure_selections()
	var matchup := "%s  VS  %s" % [GameState.player_character.display_name.to_upper(), GameState.p2_character.display_name.to_upper()]
	var stage_name: String = GameState.stage_name(GameState.stage_path)
	column.add_child(_label(matchup, 54, GOLD))
	if stage_name != "":
		column.add_child(_label(stage_name.to_upper(), 30, Color(0.85, 0.87, 0.95)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	column.add_child(row)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 22)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.6)
	back.set_border_width_all(2)
	back.border_color = Color(1, 1, 1, 0.35)
	back.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", fill)
	row.add_child(_bar)
	_percent = _label("0%", 30, Color.WHITE)
	_percent.custom_minimum_size = Vector2(90, 0)
	row.add_child(_percent)
	var tip := _label("TIP: " + TIPS.pick_random(), 26, Color(0.85, 0.87, 0.95))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(tip)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	return label
