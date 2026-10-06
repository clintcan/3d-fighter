class_name StageAmbience
extends Node
## A stage's ambient sound: looping layers (rain, crowd, waves, wind...), occasional
## one-shots at random intervals (seagulls, a jeepney horn), and a crowd reaction to
## knockouts and super finishers. Plays on the SFX bus, so the Effects volume controls it.
## Cosmetic only: the reaction is connected through FightManager.cosmetic(), so frames
## re-simulated by rollback netcode never cheer twice.

## Looping layers and their volumes (dB).
@export var loops: Array[AudioStream] = []
@export var loop_volumes := PackedFloat32Array()
## One-shots played every `sprinkle_interval` seconds (a random value in the range).
@export var sprinkles: Array[AudioStream] = []
@export var sprinkle_volume := -14.0
@export var sprinkle_interval := Vector2(6.0, 14.0)
## Crowd reaction (none if null): on a K.O. and on a super's finisher.
@export var reaction: AudioStream
@export var reaction_volume := -6.0

const FADE_IN := 1.5
const REACTION_COOLDOWN := 3.0

var _loop_players: Array[AudioStreamPlayer] = []
var _sprinkle_player: AudioStreamPlayer
var _reaction_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _next_sprinkle := 0.0
var _time := 0.0
var _last_reaction := -100.0


func _ready() -> void:
	_rng.randomize()
	for i in loops.size():
		var player := _player(_looping(loops[i]))
		player.volume_db = -60.0
		player.play(_rng.randf() * maxf(loops[i].get_length() - 1.0, 0.0)) # don't start every match on the same beat
		var target := loop_volumes[i] if i < loop_volumes.size() else -12.0
		create_tween().tween_property(player, "volume_db", target, FADE_IN)
		_loop_players.append(player)
	if not sprinkles.is_empty():
		_sprinkle_player = _player(null)
		_next_sprinkle = _rng.randf_range(sprinkle_interval.x, sprinkle_interval.y)
	if reaction:
		_reaction_player = _player(reaction)
		_reaction_player.volume_db = reaction_volume
		_connect_fight.call_deferred()


func _process(delta: float) -> void:
	_time += delta
	if _sprinkle_player and _time >= _next_sprinkle:
		_sprinkle_player.stream = sprinkles[_rng.randi() % sprinkles.size()]
		_sprinkle_player.volume_db = sprinkle_volume + _rng.randf_range(-3.0, 1.0)
		_sprinkle_player.pitch_scale = _rng.randf_range(0.92, 1.08)
		_sprinkle_player.play()
		_next_sprinkle = _time + _rng.randf_range(sprinkle_interval.x, sprinkle_interval.y)


## The crowd roars (a little varied each time, never more than once in a few seconds).
func cheer(strength := 1.0) -> void:
	if _reaction_player == null or _time - _last_reaction < REACTION_COOLDOWN:
		return
	_last_reaction = _time
	_reaction_player.volume_db = reaction_volume + linear_to_db(clampf(strength, 0.1, 1.5))
	_reaction_player.pitch_scale = _rng.randf_range(0.95, 1.05)
	_reaction_player.play()


func _connect_fight() -> void:
	var manager := _fight_manager()
	if manager == null:
		return
	for fighter: Fighter in manager.fighters:
		fighter.knocked_out.connect(manager.cosmetic(func(_f: Fighter) -> void: cheer(1.2)))
	manager.hit_landed.connect(manager.cosmetic(_on_hit))


func _on_hit(_attacker: Fighter, _defender: Fighter, move: MoveData, result: int) -> void:
	if result != Fighter.HitResult.BLOCKED and move.input.begins_with("~"): # a super's finisher
		cheer(1.0)


func _fight_manager() -> Node:
	var node := get_parent()
	while node:
		if node.has_method("cosmetic") and "fighters" in node:
			return node
		node = node.get_parent()
	return null


func _player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	add_child(player)
	return player


## A looping copy of an imported stream (Ogg Vorbis or WAV).
func _looping(stream: AudioStream) -> AudioStream:
	var copy := stream.duplicate()
	if copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
	elif copy is AudioStreamWAV:
		var wav := copy as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	elif copy is AudioStreamMP3:
		(copy as AudioStreamMP3).loop = true
	return copy
