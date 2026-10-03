extends Node
## Global game state: roster, current selections, match settings.

const CHARACTER_DIR := "res://data/characters/"
const DEFAULT_STAGE := "res://scenes/stages/ring.tscn"

const ROUNDS_TO_WIN := 2
const ROUND_TIME_SECONDS := 99

enum Mode { VS_CPU, VERSUS, TRAINING, ARCADE }

var roster: Array[CharacterData] = []
## VS_CPU: P2 is the AI. VERSUS: P2 is a second local player. TRAINING: P2 is the
## training dummy (see scripts/training/training_mode.gd). ARCADE: a ladder of CPU
## opponents (see `arcade`).
var mode: Mode = Mode.VS_CPU
var player_character: CharacterData
## P2's character (the CPU in VS_CPU mode, the second player in VERSUS).
var p2_character: CharacterData
var stage_path: String = DEFAULT_STAGE
## Seeds the CPU's decisions; the same seed and inputs replay the same match.
var match_seed := 1
## The Arcade run in progress (ARCADE mode), or null.
var arcade: ArcadeRun


func _ready() -> void:
	_load_roster()


func _load_roster() -> void:
	roster.clear()
	# list_directory handles exported (.remap) resources, unlike DirAccess.
	for file in ResourceLoader.list_directory(CHARACTER_DIR):
		if not file.ends_with(".tres"):
			continue
		var data := load(CHARACTER_DIR + file) as CharacterData
		if data:
			roster.append(data)
	roster.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.select_order < b.select_order)


## Random CPU opponent, preferring someone other than the player.
func pick_random_cpu() -> CharacterData:
	var others := roster.filter(func(c: CharacterData) -> bool: return c != player_character)
	if others.is_empty():
		return player_character
	return others.pick_random()


## Starts an Arcade run with `character` and sets up its first opponent.
func start_arcade(character: CharacterData) -> void:
	player_character = character
	arcade = ArcadeRun.create(character, roster, Settings.ai_difficulty, randi())
	apply_arcade_stage()


func apply_arcade_stage() -> void:
	p2_character = arcade.current().character


func is_arcade() -> bool:
	return mode == Mode.ARCADE and arcade != null


## Fills missing selections so a scene can be run directly from the editor (F6).
func ensure_selections() -> void:
	if player_character == null and not roster.is_empty():
		player_character = roster[0]
	if p2_character == null:
		p2_character = pick_random_cpu()
