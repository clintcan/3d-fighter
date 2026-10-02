extends Node
## Audio playback: pooled sound effects, an announcer voice channel, and crossfading
## music, on the Music / SFX / Voice buses (created here). Every Button in the game gets
## focus/press sounds automatically. Purely cosmetic: nothing here affects gameplay.

const SFX_DIR := "res://assets/audio/sfx/"
const VOICE_DIR := "res://assets/audio/voice/"
const MUSIC_DIR := "res://assets/audio/music/"
const SFX := {
	&"hit_light": ["impactPunch_medium_000", "impactPunch_medium_001", "impactPunch_medium_002", "impactPunch_medium_003", "impactPunch_medium_004"],
	&"hit_heavy": ["impactPunch_heavy_000", "impactPunch_heavy_001", "impactPunch_heavy_002", "impactPunch_heavy_003", "impactPunch_heavy_004"],
	&"block": ["impactPlate_light_000", "impactPlate_light_001", "impactPlate_light_002", "impactPlate_light_003", "impactPlate_light_004"],
	&"fall": ["impactSoft_heavy_000", "impactSoft_heavy_001", "impactSoft_heavy_002", "impactSoft_heavy_003", "impactSoft_heavy_004"],
	&"bell": ["impactBell_heavy_000", "impactBell_heavy_001"],
	&"swing_light": ["swing_light.wav"],
	&"swing_heavy": ["swing_heavy.wav"],
	&"ui_focus": ["select_001", "select_002", "select_003"],
	&"ui_accept": ["confirmation_001"],
	&"ui_back": ["back_001"],
}
const MUSIC := {
	&"menu": "menu_space_battle",
	&"fight": "fight_heavy_battle_2",
}
const SFX_VOICES := 16
const MUSIC_FADE := 1.2

var _sfx: Dictionary = {} # name -> Array[AudioStream]
var _pool: Array[AudioStreamPlayer] = []
var _next_player := 0
var _voice: AudioStreamPlayer
var _music: Array[AudioStreamPlayer] = []
var _music_name: StringName
var _active_music := 0
var _rng := RandomNumberGenerator.new() # cosmetic only, never gameplay RNG


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	for sound: StringName in SFX:
		var streams: Array[AudioStream] = []
		for file: String in SFX[sound]:
			streams.append(load(SFX_DIR + (file if file.contains(".") else file + ".ogg")))
		_sfx[sound] = streams
	for i in SFX_VOICES:
		_pool.append(_make_player("SFX"))
	_voice = _make_player("Voice")
	for i in 2:
		_music.append(_make_player("Music"))
	get_tree().node_added.connect(_on_node_added)


func _make_player(bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


## Plays a named effect (random variant, slight pitch variation).
func sfx(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var streams: Array = _sfx.get(sound, [])
	if streams.is_empty():
		return
	var player := _pool[_next_player]
	_next_player = (_next_player + 1) % _pool.size()
	player.stream = streams[_rng.randi() % streams.size()]
	player.volume_db = volume_db
	player.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	player.play()


## Announcer line from assets/audio/voice/<line>.ogg. A new line cuts off the old one.
func voice(line: String) -> void:
	var path := VOICE_DIR + line + ".ogg"
	if not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.play()


## Crossfades to a looping track; does nothing if it's already playing.
func music(track: StringName) -> void:
	if track == _music_name:
		return
	_music_name = track
	var old := _music[_active_music]
	_active_music = 1 - _active_music
	var new := _music[_active_music]
	var stream := load(MUSIC_DIR + MUSIC[track] + ".ogg") as AudioStreamOggVorbis
	stream.loop = true
	new.stream = stream
	new.volume_db = -40.0
	new.play()
	var tween := create_tween().set_parallel()
	tween.tween_property(new, "volume_db", 0.0, MUSIC_FADE)
	if old.playing:
		tween.tween_property(old, "volume_db", -40.0, MUSIC_FADE)
		tween.chain().tween_callback(old.stop)


func set_bus_volume(bus: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(index, linear <= 0.001)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		button.focus_entered.connect(sfx.bind(&"ui_focus", -6.0))
		button.pressed.connect(sfx.bind(&"ui_accept", -4.0))
