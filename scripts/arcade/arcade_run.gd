class_name ArcadeRun
extends RefCounted
## One Arcade mode run: the ladder of CPU opponents, score and stats. Held by
## GameState.arcade from character select until the ending screen.
##
## Ladder: every other roster fighter in a shuffled order with rising difficulty, then
## the final boss: the player's own "shadow" (alternate look, Hard AI, full super meter
## at the start of every round). Regular fights rotate through `arenas` (every stage
## but the boss's); the boss is fought on `boss_stage` (the dojo).
## Score: damage dealt × 10, per round won a time bonus (seconds left × 100), a life
## bonus (up to 5,000 at full health) and 10,000 for a perfect, plus 10,000 × stage
## number per stage cleared. A continue replays the stage from its starting score.

## Best scores per character: [best] <id> = score (the original format, still read),
## [details] <id> = {ticks, continues, perfects, stages, cleared} for the best run.
## A static var so tests can point it at a scratch file.
static var save_path := "user://arcade.cfg"
const POINTS_PER_DAMAGE := 10
const TIME_BONUS_PER_SECOND := 100
const LIFE_BONUS := 5000
const PERFECT_BONUS := 10000
const STAGE_CLEAR_POINTS := 10000

var player: CharacterData
## [{character: CharacterData, difficulty: AIController.Difficulty, boss: bool, stage_path: String}]
var stages: Array[Dictionary] = []
var stage := 0
var score := 0
var stage_start_score := 0
var continues := 0
var perfects := 0
## Fight ticks played (60 per second), for the clear time.
var ticks := 0
var cleared := false


static func create(player_character: CharacterData, roster: Array[CharacterData], base_difficulty: int, seed_value: int,
		arenas: Array, boss_stage: String) -> ArcadeRun:
	var run := ArcadeRun.new()
	run.player = player_character
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var others := roster.filter(func(c: CharacterData) -> bool: return c != player_character)
	# Seeded Fisher-Yates so the ladder order is reproducible.
	for i in range(others.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = others[i]
		others[i] = others[j]
		others[j] = swap
	for i in others.size():
		var difficulty := clampi(base_difficulty - 1 + i, AIController.Difficulty.EASY, AIController.Difficulty.HARD)
		run.stages.append({character = others[i], difficulty = difficulty, boss = false, stage_path = arenas[i % arenas.size()]})
	run.stages.append({character = player_character, difficulty = AIController.Difficulty.HARD, boss = true,
		stage_path = boss_stage})
	return run


func current() -> Dictionary:
	return stages[stage]


func is_final() -> bool:
	return stage == stages.size() - 1


func opponent_title(entry: Dictionary = current()) -> String:
	var character: CharacterData = entry.character
	return ("SHADOW " if entry.boss else "") + character.display_name.to_upper()


## Points for P1's damage dealt.
func add_damage(amount: int) -> void:
	score += maxi(amount, 0) * POINTS_PER_DAMAGE


## P1 won a round. Returns the bonus breakdown {time, life, perfect, total}.
func add_round_bonus(seconds_left: int, health_fraction: float) -> Dictionary:
	var perfect := health_fraction >= 1.0
	var bonus := {
		time = maxi(seconds_left, 0) * TIME_BONUS_PER_SECOND,
		life = roundi(LIFE_BONUS * clampf(health_fraction, 0.0, 1.0)),
		perfect = PERFECT_BONUS if perfect else 0,
	}
	bonus.total = bonus.time + bonus.life + bonus.perfect
	score += bonus.total
	if perfect:
		perfects += 1
	return bonus


## P1 won the match: stage clear points, then on to the next stage (or the ending).
func clear_stage() -> int:
	var points := STAGE_CLEAR_POINTS * (stage + 1)
	score += points
	if is_final():
		cleared = true
	else:
		stage += 1
	stage_start_score = score
	return points


## Replays the current stage from the score it started with (continue or restart).
func restart_stage(use_continue: bool) -> void:
	score = stage_start_score
	if use_continue:
		continues += 1


func clear_time_text() -> String:
	return time_text(ticks)


static func best_score(character: CharacterData) -> int:
	return int(best_run(character).get("score", 0))


## The character's best run: {score, ticks, continues, perfects, stages, cleared}, or {}
## if none. Records saved before details were kept have only the score.
static func best_run(character: CharacterData) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return {}
	var id := String(character.id)
	if not config.has_section_key("best", id):
		return {}
	var run: Dictionary = config.get_value("details", id, {}).duplicate()
	run.score = int(config.get_value("best", id, 0))
	return run


## Saves the run if its score beats the best for this character. Returns true on a record.
func record_best() -> bool:
	if score <= best_score(player):
		return false
	var config := ConfigFile.new()
	config.load(save_path)
	config.set_value("best", String(player.id), score)
	config.set_value("details", String(player.id), {
		ticks = ticks, continues = continues, perfects = perfects,
		stages = stages.size() if cleared else stage, cleared = cleared,
	})
	config.save(save_path)
	return true


static func time_text(fight_ticks: int) -> String:
	var seconds := fight_ticks / 60
	return "%d:%02d" % [seconds / 60, seconds % 60]
