extends Node
## Global game state: roster, current selections, match settings.

const CHARACTER_DIR := "res://data/characters/"
const DEFAULT_STAGE := "res://scenes/stages/ring.tscn"
const DOJO_STAGE := "res://scenes/stages/dojo.tscn"
const ROOFTOP_STAGE := "res://scenes/stages/rooftop.tscn"
const TEMPLE_STAGE := "res://scenes/stages/temple.tscn"
const BEACH_STAGE := "res://scenes/stages/beach.tscn"
## Selectable stages: scene, display name, select-screen thumbnail (rendered by
## tools/render_stage_thumbs.gd) and a one-line description.
const STAGES := [
	{path = DEFAULT_STAGE, name = "Boxing Ring", thumb = "res://assets/ui/stages/ring.png",
		blurb = "Under the arena lights, in front of a packed house."},
	{path = DOJO_STAGE, name = "Dojo", thumb = "res://assets/ui/stages/dojo.png",
		blurb = "Tatami, paper screens and a hall full of students."},
	{path = ROOFTOP_STAGE, name = "Rooftop", thumb = "res://assets/ui/stages/rooftop.png",
		blurb = "A helipad high above the city lights."},
	{path = TEMPLE_STAGE, name = "Temple", thumb = "res://assets/ui/stages/temple.png",
		blurb = "A mountain courtyard at sunset, under falling blossom."},
	{path = BEACH_STAGE, name = "Beach", thumb = "res://assets/ui/stages/beach.png",
		blurb = "Sun, sand and turquoise surf, ringed by tiki torches."},
]

const ROUNDS_TO_WIN := 2
const ROUND_TIME_SECONDS := 99

enum Mode { VS_CPU, VERSUS, TRAINING, ARCADE, ONLINE }

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
## Stage preloaded by the loading screen, kept referenced so it stays in the resource
## cache until the fight scene loads it (the loading screen itself is freed first).
var preloaded_stage: Resource

const LOADING_SCENE := "res://scenes/loading_screen.tscn"


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


## Goes to the fight through the loading screen (wallpaper + progress bar).
func go_to_fight(tree: SceneTree) -> void:
	tree.change_scene_to_file(LOADING_SCENE)


## Starts an Arcade run with `character` and sets up its first opponent.
func start_arcade(character: CharacterData) -> void:
	player_character = character
	arcade = ArcadeRun.create(character, roster, Settings.ai_difficulty, randi(), arcade_arenas(), DOJO_STAGE)
	apply_arcade_stage()


func apply_arcade_stage() -> void:
	p2_character = arcade.current().character
	stage_path = arcade.current().stage_path


func stage_paths() -> Array:
	return STAGES.map(func(s: Dictionary) -> String: return s.path)


## Stages for Arcade's regular fights: every stage except the boss's (the dojo), so a
## run visits all of them.
func arcade_arenas() -> Array:
	return stage_paths().filter(func(path: String) -> bool: return path != DOJO_STAGE)


## Display name of a stage scene (for the VS screen etc.).
func stage_name(path: String) -> String:
	for stage: Dictionary in STAGES:
		if stage.path == path:
			return stage.name
	return ""


func is_arcade() -> bool:
	return mode == Mode.ARCADE and arcade != null


func is_online() -> bool:
	return mode == Mode.ONLINE


func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))


## A hash of every character's stats and moves. Online peers must match exactly, or the
## same inputs would play out differently on each machine.
func content_hash() -> int:
	var parts := []
	for character in roster:
		parts.append(_stored_values(character))
		for move in character.moves:
			parts.append(_stored_values(move))
	return hash(var_to_bytes(parts)) & 0xFFFFFFFF


func _stored_values(resource: Resource) -> Array:
	var out := []
	for property in resource.get_property_list():
		var key: String = property.name
		if not (property.usage & PROPERTY_USAGE_STORAGE) or key.begins_with("resource_") or key == "script":
			continue
		var value: Variant = resource.get(key)
		if value is Resource:
			value = (value as Resource).resource_path
		elif value is Array:
			value = (value as Array).map(func(v: Variant) -> Variant: return v.resource_path if v is Resource else v)
		out.append([key, value])
	return out


## Fills missing selections so a scene can be run directly from the editor (F6).
func ensure_selections() -> void:
	if player_character == null and not roster.is_empty():
		player_character = roster[0]
	if p2_character == null:
		p2_character = pick_random_cpu()
