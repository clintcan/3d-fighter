extends Node
## Global game state: roster, current selections, match settings.

const CHARACTER_DIR := "res://data/characters/"
const DEFAULT_STAGE := "res://scenes/stages/ring.tscn"

const ROUNDS_TO_WIN := 2
const ROUND_TIME_SECONDS := 99

var roster: Array[CharacterData] = []
var player_character: CharacterData
var cpu_character: CharacterData
var stage_path: String = DEFAULT_STAGE
var ai_difficulty: AIController.Difficulty = AIController.Difficulty.NORMAL
## Seeds the CPU's decisions; the same seed and inputs replay the same match.
var match_seed := 1


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


## Fills missing selections so a scene can be run directly from the editor (F6).
func ensure_selections() -> void:
	if player_character == null and not roster.is_empty():
		player_character = roster[0]
	if cpu_character == null:
		cpu_character = pick_random_cpu()
