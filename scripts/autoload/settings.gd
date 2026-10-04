extends Node
## Player options, persisted to user://settings.cfg and applied on load and change.

const PATH := "user://settings.cfg"

var music_volume := 0.7
var sfx_volume := 0.9
var voice_volume := 1.0
var camera_mode: ActionCamera.Mode = ActionCamera.Mode.FULL
var ai_difficulty: AIController.Difficulty = AIController.Difficulty.NORMAL
var fullscreen := false
## Give gamepad 1 to Player 2 (useful with a single pad in Versus).
var swap_pads := false
## Online: the name shown to opponents, and the last address joined.
var player_name := ""
var last_join_address := ""


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	voice_volume = cfg.get_value("audio", "voice", voice_volume)
	camera_mode = cfg.get_value("game", "camera_mode", camera_mode)
	ai_difficulty = cfg.get_value("game", "ai_difficulty", ai_difficulty)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	swap_pads = cfg.get_value("input", "swap_pads", swap_pads)
	player_name = cfg.get_value("online", "player_name", player_name)
	last_join_address = cfg.get_value("online", "last_join_address", last_join_address)
	InputSetup.load_bindings(cfg)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "voice", voice_volume)
	cfg.set_value("game", "camera_mode", camera_mode)
	cfg.set_value("game", "ai_difficulty", ai_difficulty)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("input", "swap_pads", swap_pads)
	cfg.set_value("online", "player_name", player_name)
	cfg.set_value("online", "last_join_address", last_join_address)
	InputSetup.save_bindings(cfg)
	cfg.save(PATH)


## The online name: the saved one, else the computer's user name.
func online_name() -> String:
	if player_name.strip_edges() != "":
		return player_name.strip_edges().left(24)
	var user := OS.get_environment("USERNAME") if OS.has_environment("USERNAME") else OS.get_environment("USER")
	return user.left(24) if user != "" else "Player"


func apply() -> void:
	Audio.set_bus_volume("Music", music_volume)
	Audio.set_bus_volume("SFX", sfx_volume)
	Audio.set_bus_volume("Voice", voice_volume)
	InputSetup.apply(swap_pads)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
