class_name FightIntro
extends Node
## Pre-fight intro before round 1 of an offline match: each fighter in turn, P1 first,
## gets a 3/4 front close-up (ActionCamera.start_intro), plays its intro animation
## (CharacterData.intro_animation), shouts and says a line in the lower third, under the
## letterbox. Any attack button from either player skips it.
##
## Cosmetic: FightManager holds the simulation until `finished`, nothing here touches
## gameplay state, and lines are picked with the manager's cosmetic RNG.

signal finished

const SHOT_SECONDS := 2.4
const LINE_AT := 0.25 # the name and line appear...
const SHOUT_AT := 0.45 # ...and the fighter shouts
## [intro line, win quote] when a fighter meets their own double (mirror match, Arcade boss).
const MIRROR_LINES := ["There's only room for one of us.", "Only one of us is the real thing."]
const SKIP_ACTIONS: Array[StringName] = [&"p1_lp", &"p1_hp", &"p1_lk", &"p1_hk",
	&"p2_lp", &"p2_hp", &"p2_lk", &"p2_hk", &"ui_accept"]

var manager: Node
var _time := 0.0
var _shot := -1
var _line_shown := false
var _shouted := false
var _lines: Array[String] = []
var _done := false
## While true the intro holds its first frame (FightManager: until it's on screen).
var hold := false


## The line `data` opens with against `opponent`: the rival line if there is one, else a
## random one of its intro lines.
static func intro_line(data: CharacterData, opponent: CharacterData, rng: RandomNumberGenerator) -> String:
	return _pick(data, opponent, rng, 0, data.intro_lines)


## What `data` says after beating `opponent` in a match.
static func win_quote(data: CharacterData, opponent: CharacterData, rng: RandomNumberGenerator) -> String:
	return _pick(data, opponent, rng, 1, data.win_quotes)


static func _pick(data: CharacterData, opponent: CharacterData, rng: RandomNumberGenerator, which: int, pool: PackedStringArray) -> String:
	if opponent and opponent.id == data.id:
		return MIRROR_LINES[which]
	if opponent and data.rival_lines.has(String(opponent.id)):
		return data.rival_lines[String(opponent.id)][which]
	return pool[rng.randi() % pool.size()] if not pool.is_empty() else ""


func setup(fight_manager: Node) -> void:
	manager = fight_manager
	for fighter: Fighter in manager.fighters:
		_lines.append(intro_line(fighter.data, fighter.opponent.data, manager._cosmetic_rng))
	manager.hud.start_cinematic(true)
	_next_shot()


func _process(delta: float) -> void:
	if hold:
		return
	if _skip_pressed():
		skip()
	else:
		advance(delta)


func _skip_pressed() -> bool:
	for action in SKIP_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			return true
	return false


## Moves the intro on by `delta` seconds (real time).
func advance(delta: float) -> void:
	if _done:
		return
	_time += delta
	var fighter: Fighter = manager.fighters[_shot]
	if _time >= LINE_AT and not _line_shown:
		_line_shown = true
		manager.hud.announce(fighter.data.display_name.to_upper())
		manager.hud.show_quote(_lines[_shot])
	if _time >= SHOUT_AT and not _shouted:
		_shouted = true
		# Looked up at run time: tests compile this class before the autoloads exist.
		var audio := get_tree().root.get_node_or_null("Audio")
		var player: AudioStreamPlayer = audio.shout(fighter.data.id, "special") if audio else null
		if player and fighter.model:
			fighter.model.speak(player)
	if _time >= SHOT_SECONDS:
		if _shot + 1 < manager.fighters.size():
			_next_shot()
		else:
			_finish()


## Ends the intro at once (an attack button).
func skip() -> void:
	if not _done:
		_finish()


func is_done() -> bool:
	return _done


func current_shot() -> int:
	return _shot


func _next_shot() -> void:
	if _shot >= 0:
		(manager.fighters[_shot] as Fighter).end_intro() # its clip has settled in the guard
	_shot += 1
	_time = 0.0
	_line_shown = false
	_shouted = false
	var fighter: Fighter = manager.fighters[_shot]
	if fighter.data.intro_animation != &"":
		fighter.start_intro(fighter.data.intro_animation)
	fighter.intro_on_camera = true
	manager.camera.start_intro(fighter)
	manager.hud.announce("")
	manager.hud.show_quote("")


func _finish() -> void:
	_done = true
	for fighter: Fighter in manager.fighters:
		fighter.end_intro()
	manager.hud.announce("")
	manager.hud.end_cinematic()
	manager.camera.snap()
	finished.emit()
	queue_free()
