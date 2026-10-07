class_name StageAmbience
extends Node
## A stage's ambient sound: looping layers (rain, crowd, waves, wind...), occasional
## one-shots at random intervals (seagulls, a jeepney horn) and, on stages with an
## audience (a `reaction` set), a crowd that follows the fight. Plays on the Ambience
## bus, so Options → Ambience Volume controls (or silences) all of it.
##
## The crowd: an excitement level (0–1) rises with hits, combos, counters, throws,
## supers and K.O.s and fades a few seconds after the action stops. A cheering layer
## swells and settles with it, and the crowd reacts out loud: "ooh" at big hits and
## throws, gasps at counter hits, "wow" at long combos and super finishers, a roar
## and applause at a K.O. Cosmetic only: every handler is connected through
## FightManager.cosmetic(), so frames re-simulated by rollback never react twice, and
## the random picks use their own RNG, never the simulation's.

## Looping layers and their volumes (dB).
@export var loops: Array[AudioStream] = []
@export var loop_volumes := PackedFloat32Array()
## One-shots played every `sprinkle_interval` seconds (a random value in the range).
@export var sprinkles: Array[AudioStream] = []
@export var sprinkle_volume := -14.0
@export var sprinkle_interval := Vector2(6.0, 14.0)
## Applause at a K.O. (none if null). Setting it also gives the stage a reacting crowd,
## with every crowd sound balanced around `reaction_volume`.
@export var reaction: AudioStream
@export var reaction_volume := -6.0

const FADE_IN := 1.5
const CROWD_DIR := "res://assets/audio/ambience/crowd/"
## Reaction kinds (files crowd_<kind>_N.ogg): [volume offset (dB) from reaction_volume, priority].
## A reaction waits out SHOUT_COOLDOWN unless it outranks the last one.
const SHOUTS := {
	&"ooh": [-3.0, 1],
	&"gasp": [-4.0, 1],
	&"wow": [-1.0, 2],
	&"roar": [1.0, 3],
}
const SHOUT_COOLDOWN := 4.0
## The cheering layer at full excitement, relative to reaction_volume.
const SWELL_DB := -2.0
## Excitement holds this long after the last bump, then fades at this rate per second.
## Bumps shrink as it nears 1, so only sustained action (combos, a comeback) gets the
## crowd fully on its feet; trading pokes keeps it around a third.
const EXCITEMENT_HOLD := 1.0
const EXCITEMENT_DECAY := 0.18
## Combo lengths that make the crowd go "wow".
const WOW_COMBOS := [5, 8, 12]
const APPLAUSE_DELAY := 1.4

## 0 = calm, 1 = on its feet.
var excitement := 0.0
var _hold := 0.0
var _swell: AudioStreamPlayer
var _swell_level := 0.0
var _shouts := {} # kind -> Array[AudioStream]
var _shout_players: Array[AudioStreamPlayer] = []
var _last_shout_time := -100.0
var _last_shout_priority := 0
var _last_clip: AudioStream
var _applause_at := -1.0

var _loop_players: Array[AudioStreamPlayer] = []
var _sprinkle_player: AudioStreamPlayer
var _reaction_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _next_sprinkle := 0.0
var _time := 0.0


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
		_load_crowd()
		_connect_fight.call_deferred()


func _process(delta: float) -> void:
	_time += delta
	if _sprinkle_player and _time >= _next_sprinkle:
		_sprinkle_player.stream = sprinkles[_rng.randi() % sprinkles.size()]
		_sprinkle_player.volume_db = sprinkle_volume + _rng.randf_range(-3.0, 1.0)
		_sprinkle_player.pitch_scale = _rng.randf_range(0.92, 1.08)
		_sprinkle_player.play()
		_next_sprinkle = _time + _rng.randf_range(sprinkle_interval.x, sprinkle_interval.y)
	if _swell == null:
		return
	if _hold > 0.0:
		_hold -= delta
	else:
		excitement = move_toward(excitement, 0.0, EXCITEMENT_DECAY * delta)
	# The cheering rises quickly with the action and settles slowly after it.
	var target := smoothstep(0.08, 1.0, excitement)
	_swell_level = move_toward(_swell_level, target, delta * (2.5 if target > _swell_level else 0.5))
	_swell.volume_db = reaction_volume + SWELL_DB + linear_to_db(maxf(_swell_level, 0.001))
	if _applause_at >= 0.0 and _time >= _applause_at:
		_applause_at = -1.0
		_reaction_player.pitch_scale = _rng.randf_range(0.95, 1.05)
		_reaction_player.play()


## Raises the crowd's excitement (capped at 1) and holds it a moment.
func excite(amount: float, hold := EXCITEMENT_HOLD) -> void:
	excitement = minf(excitement + amount * (1.0 - 0.75 * excitement), 1.0)
	_hold = maxf(_hold, hold)


## The crowd reacts out loud: a random take of `kind` that isn't the last clip played.
## Returns false if it had to stay quiet (cooldown, or no crowd on this stage).
func shout(kind: StringName) -> bool:
	var takes: Array = _shouts.get(kind, [])
	if takes.is_empty():
		return false
	var priority: int = SHOUTS[kind][1]
	if _time - _last_shout_time < SHOUT_COOLDOWN and priority <= _last_shout_priority:
		return false
	var clip: AudioStream = takes[_rng.randi() % takes.size()]
	if clip == _last_clip and takes.size() > 1:
		clip = takes[(takes.find(clip) + 1 + _rng.randi() % (takes.size() - 1)) % takes.size()]
	var player := _shout_players[0]
	for p in _shout_players: # a free player, else the one that started first
		if not p.playing:
			player = p
			break
	_shout_players.erase(player)
	_shout_players.append(player)
	player.stream = clip
	player.volume_db = reaction_volume + SHOUTS[kind][0] + _rng.randf_range(-1.5, 1.0)
	player.pitch_scale = _rng.randf_range(0.96, 1.04)
	player.play()
	_last_shout_time = _time
	_last_shout_priority = priority
	_last_clip = clip
	return true


## The old single reaction: the applause, now part of the K.O. response.
func cheer(_strength := 1.0) -> void:
	_on_knockout(null)


func _on_knockout(_fighter: Fighter) -> void:
	excitement = 1.0
	_hold = 4.0
	shout(&"roar")
	_applause_at = _time + APPLAUSE_DELAY


func _on_hit(_attacker: Fighter, defender: Fighter, move: MoveData, result: int) -> void:
	if result == Fighter.HitResult.BLOCKED:
		excite(0.02, 0.5)
		return
	var combo := defender.combo_hits
	var counter := result == Fighter.HitResult.COUNTER
	var big := move.launches or move.knockdown or move.damage >= 100
	excite(0.03 + move.damage / 1500.0 + 0.04 * maxi(combo - 1, 0) + (0.08 if counter else 0.0) + (0.1 if big else 0.0))
	if move.input.begins_with("~"): # a super's finisher
		excite(0.4, 3.0)
		shout(&"wow")
	elif combo in WOW_COMBOS:
		shout(&"wow")
	elif counter:
		shout(&"gasp")
	elif big:
		shout(&"ooh")


func _on_throw(_attacker: Fighter, _defender: Fighter) -> void:
	excite(0.25)
	shout(&"ooh")


func _on_super(_fighter: Fighter, _move: MoveData) -> void:
	excite(0.3, 2.0)
	shout(&"ooh") # the build-up; the finisher gets the "wow"


func _connect_fight() -> void:
	var manager := _fight_manager()
	if manager == null:
		return
	for fighter: Fighter in manager.fighters:
		fighter.knocked_out.connect(manager.cosmetic(_on_knockout))
	manager.hit_landed.connect(manager.cosmetic(_on_hit))
	manager.throw_landed.connect(manager.cosmetic(_on_throw))
	manager.super_flash.connect(manager.cosmetic(_on_super))


## The crowd's reactions (crowd_<kind>_N.ogg) and its looping cheering layer.
func _load_crowd() -> void:
	for kind: StringName in SHOUTS:
		_shouts[kind] = []
	for file in ResourceLoader.list_directory(CROWD_DIR):
		var parts := file.get_basename().split("_")
		if parts.size() == 3 and parts[0] == "crowd" and _shouts.has(StringName(parts[1])):
			(_shouts[StringName(parts[1])] as Array).append(load(CROWD_DIR + file))
	for i in 3:
		_shout_players.append(_player(null))
	_swell = _player(_looping(load(CROWD_DIR + "crowd_cheering_loop.ogg")))
	_swell.volume_db = -80.0
	_swell.play(_rng.randf() * 20.0)


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
	player.bus = &"Ambience"
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
