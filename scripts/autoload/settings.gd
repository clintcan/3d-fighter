extends Node
## Player options, persisted to user://settings.cfg and applied on load and change.

const PATH := "user://settings.cfg"

var music_volume := 0.7
var sfx_volume := 0.9
var voice_volume := 1.0
## Stage background sound and crowd reactions (0 turns them off).
var ambience_volume := 1.0
var camera_mode: ActionCamera.Mode = ActionCamera.Mode.FULL
var ai_difficulty: AIController.Difficulty = AIController.Difficulty.NORMAL
## Pre-fight intros (FightIntro) before round 1 of an offline match.
var fight_intros := true
## Display: a window, a borderless window covering the screen, or exclusive fullscreen
## (Windows can hand the screen to the game: slightly lower latency, slower Alt-Tab).
## Fullscreen always runs at the desktop resolution; Godot never changes display modes.
enum DisplayMode { WINDOWED, BORDERLESS, EXCLUSIVE }
const DISPLAY_NAMES := ["Windowed", "Borderless Fullscreen", "Exclusive Fullscreen"]
var display_mode: DisplayMode = DisplayMode.WINDOWED
## Window size when windowed (sizes that don't fit the screen are skipped in Options).
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
var window_size := 0
## 3D resolution: the fight is drawn at most this many lines tall and scaled up to the
## window; menus, HUD and text stay at full sharpness. 0 = the window's own resolution.
## A high-DPI screen at 3024×1898 draws about three times the pixels of 1080p.
const RESOLUTIONS: Array[int] = [720, 900, 1080, 1440, 0]
const RESOLUTION_NAMES := ["720p", "900p", "1080p", "1440p", "Native"]
var resolution := 2
## Graphics preset (measured on an integrated GPU, 1280×720: render scale, MSAA and glow
## are the big costs; volumetric fog and reflection probes cost about nothing, and FSR
## upscaling cost more than it saved, so scaling is bilinear).
## High: everything. Medium: 85% of the resolution, 2× MSAA, half the ambient particles,
## one shadowed light. Low: 75% of the resolution, FXAA instead of MSAA, no glow, fog,
## probes, ambient particles or extra shadows. Purely visual: the simulation never reads it.
enum Graphics { LOW, MEDIUM, HIGH }
const GRAPHICS_NAMES := ["Low", "Medium", "High"]
var graphics: Graphics = Graphics.HIGH
## Give gamepad 1 to Player 2 (useful with a single pad in Versus).
var swap_pads := false
## Online: the name shown to opponents, and the last address joined.
var player_name := ""
var last_join_address := ""
## Internet lobby: the server's address (ws:// or wss://), whether to always play through
## its relay (the opponent never sees your IP address), and this installation's random id
## (the server uses it for bans and "same player again" hints, never shown to others).
var server_url := ""
var relay_only := false
var client_id := ""


func _ready() -> void:
	load_settings()
	apply()
	get_tree().root.size_changed.connect(func() -> void: apply_graphics(get_tree().root)) # the scale follows the window


## The last display mode and window size applied, so apply() (called on every option
## change) only touches the window when they change and never undoes a manual resize.
var _applied_display := Vector2i(-1, -1)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	voice_volume = cfg.get_value("audio", "voice", voice_volume)
	ambience_volume = cfg.get_value("audio", "ambience", ambience_volume)
	camera_mode = cfg.get_value("game", "camera_mode", camera_mode)
	ai_difficulty = cfg.get_value("game", "ai_difficulty", ai_difficulty)
	fight_intros = cfg.get_value("game", "fight_intros", fight_intros)
	# Settings from before the display choice had only a fullscreen switch.
	var legacy_mode := DisplayMode.BORDERLESS if cfg.get_value("video", "fullscreen", false) else DisplayMode.WINDOWED
	display_mode = clampi(cfg.get_value("video", "display_mode", legacy_mode), DisplayMode.WINDOWED, DisplayMode.EXCLUSIVE) as DisplayMode
	window_size = clampi(cfg.get_value("video", "window_size", window_size), 0, WINDOW_SIZES.size() - 1)
	resolution = clampi(cfg.get_value("video", "resolution", resolution), 0, RESOLUTIONS.size() - 1)
	graphics = clampi(cfg.get_value("video", "graphics", graphics), Graphics.LOW, Graphics.HIGH) as Graphics
	swap_pads = cfg.get_value("input", "swap_pads", swap_pads)
	player_name = cfg.get_value("online", "player_name", player_name)
	last_join_address = cfg.get_value("online", "last_join_address", last_join_address)
	server_url = cfg.get_value("online", "server_url", server_url)
	relay_only = cfg.get_value("online", "relay_only", relay_only)
	client_id = cfg.get_value("online", "client_id", client_id)
	InputSetup.load_bindings(cfg)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "voice", voice_volume)
	cfg.set_value("audio", "ambience", ambience_volume)
	cfg.set_value("game", "camera_mode", camera_mode)
	cfg.set_value("game", "ai_difficulty", ai_difficulty)
	cfg.set_value("game", "fight_intros", fight_intros)
	cfg.set_value("video", "display_mode", display_mode)
	cfg.set_value("video", "window_size", window_size)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("video", "graphics", graphics)
	cfg.set_value("input", "swap_pads", swap_pads)
	cfg.set_value("online", "player_name", player_name)
	cfg.set_value("online", "last_join_address", last_join_address)
	cfg.set_value("online", "server_url", server_url)
	cfg.set_value("online", "relay_only", relay_only)
	cfg.set_value("online", "client_id", client_id)
	InputSetup.save_bindings(cfg)
	cfg.save(PATH)


## The online name: the saved one, else the computer's user name.
func online_name() -> String:
	if player_name.strip_edges() != "":
		return player_name.strip_edges().left(24)
	var user := OS.get_environment("USERNAME") if OS.has_environment("USERNAME") else OS.get_environment("USER")
	return user.left(24) if user != "" else "Player"


## This installation's lobby id (a random UUID, made and saved on first use).
func get_client_id() -> String:
	if client_id == "":
		client_id = new_uuid()
		save_settings()
	return client_id


## A random (version 4) UUID.
static func new_uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


func apply() -> void:
	Audio.set_bus_volume("Music", music_volume)
	Audio.set_bus_volume("SFX", sfx_volume)
	Audio.set_bus_volume("Voice", voice_volume)
	Audio.set_bus_volume("Ambience", ambience_volume)
	InputSetup.apply(swap_pads)
	apply_display()
	apply_graphics(get_tree().root)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless" or _applied_display == Vector2i(display_mode, window_size):
		return
	_applied_display = Vector2i(display_mode, window_size)
	var mode: DisplayServer.WindowMode = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN][display_mode]
	DisplayServer.window_set_mode(mode)
	if display_mode == DisplayMode.WINDOWED:
		var size := fitting_window_size(window_size)
		var screen := DisplayServer.window_get_current_screen()
		var area := DisplayServer.screen_get_usable_rect(screen)
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(area.position + (area.size - size) / 2)


## The chosen window size, or the largest one that fits the screen's usable area.
func fitting_window_size(index: int) -> Vector2i:
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	for i in range(index, -1, -1):
		if WINDOW_SIZES[i].x <= area.x and WINDOW_SIZES[i].y <= area.y:
			return WINDOW_SIZES[i]
	return WINDOW_SIZES[0]


## The 3D render scale for a viewport this tall: the resolution cap times the preset's.
func render_scale(height: int) -> float:
	var cap := 1.0
	if RESOLUTIONS[resolution] > 0 and height > RESOLUTIONS[resolution]:
		cap = float(RESOLUTIONS[resolution]) / height
	return maxf(cap * [0.75, 0.85, 1.0][graphics], 0.25)


## The preset's viewport side: anti-aliasing and render scale (resolution × preset).
func apply_graphics(viewport: Viewport) -> void:
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][graphics]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if graphics == Graphics.LOW else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var pixels: Vector2i = (viewport as Window).size if viewport is Window else (viewport as SubViewport).size # real pixels, not the stretched design size
	viewport.scaling_3d_scale = render_scale(pixels.y)


## The preset's stage side, called by every Stage when it enters the tree. The
## environment is copied first: it's shared with the cached scene, and a later stage
## loaded at a higher setting must get the original back.
func apply_graphics_to_stage(stage: Node) -> void:
	if graphics == Graphics.HIGH:
		return
	var low := graphics == Graphics.LOW
	for node in stage.find_children("*", "WorldEnvironment", true, false):
		var world := node as WorldEnvironment
		if world.environment and low:
			world.environment = world.environment.duplicate()
			world.environment.volumetric_fog_enabled = false
			world.environment.glow_enabled = false
	var first_shadow := true # the key light (each builder adds it first) keeps its shadow
	for node in stage.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light.shadow_enabled:
			if first_shadow:
				first_shadow = false
			else:
				light.shadow_enabled = false
	for node in stage.find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		if low:
			particles.emitting = false
			particles.visible = false
		else:
			particles.amount_ratio = 0.5
	if low:
		for node in stage.find_children("*", "ReflectionProbe", true, false):
			(node as ReflectionProbe).visible = false
