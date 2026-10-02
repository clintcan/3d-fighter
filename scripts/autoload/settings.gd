extends Node
## Player options, persisted to user://settings.cfg and applied on load and change.

const PATH := "user://settings.cfg"

var music_volume := 0.7
var sfx_volume := 0.9
var voice_volume := 1.0
var camera_mode: ActionCamera.Mode = ActionCamera.Mode.FULL
var ai_difficulty: AIController.Difficulty = AIController.Difficulty.NORMAL
var fullscreen := false


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


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "voice", voice_volume)
	cfg.set_value("game", "camera_mode", camera_mode)
	cfg.set_value("game", "ai_difficulty", ai_difficulty)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(PATH)


func apply() -> void:
	Audio.set_bus_volume("Music", music_volume)
	Audio.set_bus_volume("SFX", sfx_volume)
	Audio.set_bus_volume("Voice", voice_volume)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
