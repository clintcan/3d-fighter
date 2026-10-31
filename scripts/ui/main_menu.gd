extends Control

const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const OPTIONS_SCENE := "res://scenes/options.tscn"
const BEST_SCORES_SCENE := "res://scenes/best_scores.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"
const ONLINE_SCENE := "res://scenes/online_menu.tscn"
const REPLAYS_SCENE := "res://scenes/replays.tscn"

@onready var start_button: Button = %StartButton
@onready var arcade_button: Button = %ArcadeButton
@onready var quit_button: Button = %QuitButton
@onready var options_button: Button = %OptionsButton
@onready var versus_button: Button = %VersusButton
@onready var training_button: Button = %TrainingButton
@onready var best_scores_button: Button = %BestScoresButton
@onready var credits_button: Button = %CreditsButton


const LOGO := "res://assets/ui/logo.png" # the brush title, from tools/build_logo.py
const LOGO_SIZE := Vector2(900, 167)


## Swaps the text title for the brush logo, like the title screen's (the label stays as a
## fallback if the image is missing).
func _use_logo(title: Label) -> void:
	if not ResourceLoader.exists(LOGO):
		return
	var logo := TextureRect.new()
	logo.name = "Logo"
	logo.texture = load(LOGO)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = LOGO_SIZE
	title.add_sibling(logo)
	title.get_parent().move_child(logo, title.get_index())
	title.hide()


func _ready() -> void:
	_add_wallpaper()
	_use_logo($Center/VBox/Title as Label)
	start_button.pressed.connect(_start.bind(GameState.Mode.VS_CPU))
	arcade_button.pressed.connect(_start.bind(GameState.Mode.ARCADE))
	versus_button.pressed.connect(_start.bind(GameState.Mode.VERSUS))
	training_button.pressed.connect(_start.bind(GameState.Mode.TRAINING))
	# Demo: two CPU fighters on a random stage until a button is pressed.
	var demo_button := training_button.duplicate(0) as Button
	demo_button.name = "DemoButton"
	demo_button.unique_name_in_owner = false
	demo_button.text = "Demo"
	training_button.add_sibling(demo_button)
	demo_button.pressed.connect(func() -> void: GameState.start_demo(get_tree()))
	# Online sits under Versus; built from it so it shares the menu's look.
	var online_button := versus_button.duplicate(0) as Button # 0: without Versus's signal connections
	online_button.name = "OnlineButton"
	online_button.unique_name_in_owner = false
	online_button.text = "Online"
	versus_button.add_sibling(online_button)
	online_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(ONLINE_SCENE))
	if Net.peer:
		Net.leave() # back at the main menu: any online session is over
	if Net.lobby:
		Net.disconnect_server()
	quit_button.pressed.connect(_on_quit_pressed)
	options_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(OPTIONS_SCENE))
	best_scores_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(BEST_SCORES_SCENE))
	# Replays sit under Best Scores; built from it so they share the menu's look.
	var replays_button := best_scores_button.duplicate(0) as Button
	replays_button.name = "ReplaysButton"
	replays_button.unique_name_in_owner = false
	replays_button.text = "Replays"
	best_scores_button.add_sibling(replays_button)
	replays_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(REPLAYS_SCENE))
	credits_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(CREDITS_SCENE))
	start_button.grab_focus()
	Audio.music(&"menu")
	# `3DFighter.exe -- --smoke-test` jumps straight into a fight (packaging checks).
	if "--smoke-test" in OS.get_cmdline_user_args():
		if _online_smoke_test():
			return
		if "--determinism" in OS.get_cmdline_user_args():
			(func() -> void:
				DeterminismCheck.run(get_tree())
				get_tree().quit()).call_deferred()
			return
		if "--versus" in OS.get_cmdline_user_args():
			GameState.mode = GameState.Mode.VERSUS
		elif "--training" in OS.get_cmdline_user_args():
			GameState.mode = GameState.Mode.TRAINING
		elif "--demo" in OS.get_cmdline_user_args():
			GameState.start_demo.call_deferred(get_tree())
			return
		elif "--arcade" in OS.get_cmdline_user_args():
			GameState.mode = GameState.Mode.ARCADE
			GameState.ensure_selections()
			GameState.start_arcade(GameState.player_character)
		get_tree().change_scene_to_file.call_deferred("res://scenes/fight.tscn")


## `-- --smoke-test --online-host` / `--online-join=IP[:port]`: two processes connect, pick,
## fight with random inputs and print a checksum each (they must match).
## `--server=ws://HOST:PORT/v1/ws` with `--server-host` / `--server-join` / `--server-watch`:
## the same through the internet lobby server, plus a spectator replaying the match.
func _online_smoke_test() -> bool:
	var server_url := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			server_url = arg.get_slice("=", 1) if arg.get_slice_count("=") == 2 else arg.substr(9)
	for arg in OS.get_cmdline_user_args():
		if server_url != "" and arg in ["--server-host", "--server-join", "--server-watch"]:
			var role := arg.trim_prefix("--server-")
			var err := Net.start_server_smoke(server_url, role)
			print("SMOKE TEST: lobby server %s as %s (%s)" % [server_url, role, error_string(err)])
			if err != OK:
				get_tree().quit(1)
			return true
		if arg == "--online-host" or arg.begins_with("--online-join="):
			Net.smoke = true
			var err := Net.host() if arg == "--online-host" else Net.join(arg.get_slice("=", 1))
			print("SMOKE TEST: online %s (%s)" % ["hosting" if arg == "--online-host" else "joining", error_string(err)])
			if err != OK:
				get_tree().quit(1)
			return true
	return false


## Behind the menu: fighters in close-up running their routines (MenuShowcase), with a
## dark band down the middle so the buttons stay readable. Smoke tests leave straight
## away, so they skip it.
func _add_wallpaper() -> void:
	var back: Control
	if "--smoke-test" in OS.get_cmdline_user_args():
		back = Control.new()
	else:
		back = MenuShowcase.new()
		back.name = "Showcase"
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	move_child(back, 1) # just above the background color
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.7, 1.0])
	var clear := Color(0.02, 0.02, 0.04, 0.0)
	var dark := Color(0.02, 0.02, 0.04, 0.8)
	gradient.colors = PackedColorArray([clear, clear, dark, clear, clear])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 256
	tex.height = 1
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	move_child(shade, 2)


func _start(mode: GameState.Mode) -> void:
	GameState.mode = mode
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
