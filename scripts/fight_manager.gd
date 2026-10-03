extends Node3D
## Fight scene root. Owns the fixed-order 60 Hz simulation:
##   view → input → fighter tick → pushbox → hits
## P1 vs. the CPU (AIController, or a training dummy via F1) or, in Versus mode, a second
## local player. Best of 3 rounds.
## Round flow (INTRO → FIGHT → ROUND_OVER → … → MATCH_OVER) also runs on the tick, so
## timers are frame-exact and pausing freezes everything.

signal hit_landed(attacker: Fighter, defender: Fighter, move: MoveData, result: Fighter.HitResult)
signal throw_landed(attacker: Fighter, defender: Fighter)
signal round_ended(winner: Fighter, reason: String)

enum Phase { INTRO, FIGHT, ROUND_OVER, MATCH_OVER }

const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const FIGHTER_SCENE := preload("res://scenes/fighter/fighter.tscn")
const TICKS_PER_SECOND := 60
## "ROUND N" shows from the start of the intro; "FIGHT!" at the end, when input unlocks.
const INTRO_TICKS := 110
const ROUND_OVER_TICKS := 210
## Winner switches to the victory pose this long after the round ends.
const VICTORY_POSE_DELAY := 70
## After this many rounds a tie on round wins is a draw game.
const MAX_ROUNDS := 5
## Match-win cinematic: winner name appears, then the result menu once the shot plays.
const VICTORY_TITLE_TICKS := 40
const VICTORY_RESULT_TICKS := 220
## Share of a hit's knockback transferred to the attacker when the defender is pinned.
const CORNER_PUSHBACK := 0.8
## Per-tick slerp factor for the logical view direction following the fight axis.
const VIEW_FOLLOW := 0.08

var stage: Stage
var fighters: Array[Fighter] = []
## Unit vector (flattened) from the fighters' midpoint toward the camera. Part of the
## simulation state because it decides which way "left/right" map for each player.
var view_dir := Vector3.BACK
var ai: AIController
var dummy: DummyController
## -1 = AI controls P2, otherwise a DummyController.Mode.
var cpu_mode := -1
var debug_draw := false

var phase: Phase = Phase.INTRO
var phase_ticks := 0
var round_number := 1
var round_wins: Array[int] = [0, 0]
var timer_ticks := 0
var round_winner: Fighter
var match_winner: Fighter
var fx: FightFx
var _cosmetic_rng := RandomNumberGenerator.new() # victory pose choice only; never gameplay
## Fighters knocked out this tick (both, for a double K.O.); resolved after the tick.
var _knocked_out: Array[Fighter] = []

@onready var camera: ActionCamera = $ActionCamera
@onready var hud: FightHud = $HUD


func _ready() -> void:
	GameState.ensure_selections()
	stage = (load(GameState.stage_path) as PackedScene).instantiate() as Stage
	add_child(stage)

	_cosmetic_rng.randomize()
	ai = AIController.new(Settings.ai_difficulty, GameState.match_seed)
	dummy = DummyController.new()
	var p1 := _spawn_fighter(GameState.player_character, PlayerController.new("p1_"))
	var p2_controller: FighterController = PlayerController.new("p2_") if is_versus() else ai
	# Mirror match: P2 wears the alternate look so the two fighters can be told apart.
	var mirror := GameState.p2_character == GameState.player_character
	var p2 := _spawn_fighter(GameState.p2_character, p2_controller, mirror)
	ai.attach(p2)
	p1.opponent = p2
	p2.opponent = p1
	for fighter in fighters:
		fighter.knocked_out.connect(_on_knocked_out)
		fighter.throw_teched.connect(_on_throw_teched)

	hud.setup(p1, p2, GameState.ROUNDS_TO_WIN, is_versus())
	hud.rematch_pressed.connect(start_match)
	hud.restart_pressed.connect(start_match)
	hud.character_select_pressed.connect(_go_to.bind(CHARACTER_SELECT_SCENE))
	hud.main_menu_pressed.connect(_go_to.bind(MAIN_MENU_SCENE))
	camera.setup(self)
	camera.mode = Settings.camera_mode
	fx = FightFx.new()
	fx.name = "FightFx"
	add_child(fx)
	fx.setup(self)
	Audio.music(&"fight")
	start_match()
	_update_debug_text()
	if "--smoke-test" in OS.get_cmdline_user_args():
		print("SMOKE TEST: fight ready (%s vs %s, %d moves loaded)" % [p1.data.display_name, p2.data.display_name, p1.data.moves.size()])
		round_ended.connect(func(_w: Fighter, reason: String) -> void: print("SMOKE TEST: round ended (%s)" % reason))


func is_versus() -> bool:
	return GameState.mode == GameState.Mode.VERSUS


func _spawn_fighter(character: CharacterData, controller: FighterController, alt_look: bool = false) -> Fighter:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	fighter.setup(character, controller, alt_look)
	fighter.bounds_half_extent = stage.bounds_half_extent
	add_child(fighter)
	fighters.append(fighter)
	return fighter


# --- Match / round flow ----------------------------------------------------------

func start_match() -> void:
	get_tree().paused = false
	round_number = 1
	round_wins = [0, 0]
	match_winner = null
	hud.set_round_wins(round_wins)
	hud.hide_result()
	hud.end_cinematic()
	_start_round()


func _start_round() -> void:
	_reset_round()
	phase = Phase.INTRO
	phase_ticks = 0
	timer_ticks = GameState.ROUND_TIME_SECONDS * TICKS_PER_SECOND
	hud.set_timer(GameState.ROUND_TIME_SECONDS)
	for fighter in fighters:
		fighter.input_locked = true
	var final := round_wins[0] == GameState.ROUNDS_TO_WIN - 1 and round_wins[1] == GameState.ROUNDS_TO_WIN - 1
	hud.announce("FINAL ROUND" if final else "ROUND %d" % round_number)
	Audio.voice("final_round" if final else "round_%d" % clampi(round_number, 1, 5))


## Skips the intro (tests, debug).
func start_fight_immediately() -> void:
	phase = Phase.FIGHT
	phase_ticks = 0
	hud.announce("")
	for fighter in fighters:
		fighter.input_locked = false


func _tick_round() -> void:
	phase_ticks += 1
	match phase:
		Phase.INTRO:
			if phase_ticks >= INTRO_TICKS:
				start_fight_immediately()
				hud.announce("FIGHT!", "", true)
				Audio.voice("fight")
				Audio.sfx(&"bell", -6.0)
		Phase.FIGHT:
			if not _knocked_out.is_empty():
				_end_round_by_ko()
			else:
				timer_ticks -= 1
				hud.set_timer(ceili(timer_ticks / float(TICKS_PER_SECOND)))
				if timer_ticks <= 0:
					_end_round_by_time()
		Phase.ROUND_OVER:
			if phase_ticks == VICTORY_POSE_DELAY and round_winner:
				round_winner.victory = true
			if phase_ticks >= ROUND_OVER_TICKS:
				_after_round()
		Phase.MATCH_OVER:
			if match_winner:
				if phase_ticks == VICTORY_TITLE_TICKS:
					if is_versus():
						hud.announce("PLAYER %d WINS" % (fighters.find(match_winner) + 1), match_winner.data.display_name.to_upper(), true)
					else:
						hud.announce("%s WINS" % match_winner.data.display_name.to_upper(), "", true)
				elif phase_ticks == VICTORY_RESULT_TICKS:
					hud.show_result()
	_knocked_out.clear()


func _end_round_by_ko() -> void:
	if _knocked_out.size() >= 2:
		_finish_round(null, "DOUBLE K.O.")
	else:
		_finish_round(_knocked_out[0].opponent, "K.O.")


## Time out: higher remaining health (as a share of max) wins.
func _end_round_by_time() -> void:
	var a := fighters[0].health / float(fighters[0].data.max_health)
	var b := fighters[1].health / float(fighters[1].data.max_health)
	_finish_round(null if is_equal_approx(a, b) else (fighters[0] if a > b else fighters[1]), "TIME")


func _finish_round(winner: Fighter, reason: String) -> void:
	phase = Phase.ROUND_OVER
	phase_ticks = 0
	round_winner = winner
	for fighter in fighters:
		fighter.input_locked = true
	var sub := ""
	if winner:
		round_wins[fighters.find(winner)] += 1
		hud.set_round_wins(round_wins)
		if winner.health == winner.data.max_health:
			sub = "PERFECT"
	else:
		sub = "DRAW"
	hud.announce(reason, sub, true)
	Audio.sfx(&"bell", -3.0)
	if reason == "TIME":
		Audio.voice("time")
	elif sub == "PERFECT":
		Audio.voice("flawless_victory")
	elif sub == "DRAW":
		Audio.voice("its_a_tie")
	round_ended.emit(winner, reason)


func _after_round() -> void:
	var p1_won := round_wins[0] >= GameState.ROUNDS_TO_WIN
	var p2_won := round_wins[1] >= GameState.ROUNDS_TO_WIN
	if p1_won or p2_won or round_number >= MAX_ROUNDS:
		phase = Phase.MATCH_OVER
		phase_ticks = 0
		if round_wins[0] != round_wins[1]:
			_start_victory(fighters[0] if round_wins[0] > round_wins[1] else fighters[1])
		else:
			Audio.voice("its_a_tie")
			hud.announce("DRAW GAME", "", true)
			hud.show_result()
	else:
		round_number += 1
		_start_round()


## Match win: the winner's victory animation, the cinematic camera and letterbox. The
## title and result menu follow on the tick (see _tick_round).
func _start_victory(winner: Fighter) -> void:
	match_winner = winner
	var clips := winner.data.victory_animations
	winner.start_victory(clips[_cosmetic_rng.randi() % clips.size()] if not clips.is_empty() else &"")
	camera.start_victory(winner)
	hud.announce("")
	hud.start_cinematic()
	if is_versus():
		Audio.voice_sequence(["player_%d" % (fighters.find(winner) + 1), "winner"])
	else:
		Audio.voice("you_win" if winner == fighters[0] else "you_lose")


func _go_to(scene: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(scene)


func _reset_round() -> void:
	ai.reset()
	fighters[0].reset_to(stage.p1_spawn.global_position)
	fighters[1].reset_to(stage.p2_spawn.global_position)
	view_dir = Vector3.BACK
	_update_view()
	# Facing depends on the opponent's position, so face once both are placed.
	for fighter in fighters:
		fighter.face_opponent()
	hud.announce("")
	if camera.manager:
		camera.snap()


# --- Simulation ------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	_update_view()
	for fighter in fighters:
		fighter.read_input()
	for fighter in fighters:
		fighter.tick()
	_resolve_pushboxes()
	_resolve_throws()
	_resolve_hits()
	_tick_round()


## Keeps the camera side-on to the fight axis, turning toward whichever perpendicular is
## closer so the view never flips.
func _update_view() -> void:
	var axis := fighters[1].position - fighters[0].position
	axis.y = 0.0
	if axis.length_squared() > 0.0001:
		var desired := Vector3.UP.cross(axis).normalized()
		if desired.dot(view_dir) < 0.0:
			desired = -desired
		view_dir = view_dir.slerp(desired, VIEW_FOLLOW).normalized()
	var view_right := (-view_dir).cross(Vector3.UP)
	for fighter in fighters:
		fighter.view_right = view_right
		fighter.view_depth = -view_dir


func _resolve_pushboxes() -> void:
	var a := fighters[0]
	var b := fighters[1]
	var min_distance := Fighter.PUSHBOX_RADIUS * 2.0
	var delta := _flat(b.position - a.position)
	var distance := delta.length()
	if distance >= min_distance:
		return
	var push_dir := delta / distance if distance > 0.0001 else a.forward
	var overlap := min_distance - distance
	a.position -= push_dir * overlap * 0.5
	b.position += push_dir * overlap * 0.5
	a.clamp_to_bounds()
	b.clamp_to_bounds()
	# If one fighter is pinned at the edge, the other takes the remaining push.
	var remaining := min_distance - _flat(b.position - a.position).length()
	if remaining > 0.001:
		b.position += push_dir * remaining
		b.clamp_to_bounds()
		remaining = min_distance - _flat(b.position - a.position).length()
		if remaining > 0.001:
			a.position -= push_dir * remaining
			a.clamp_to_bounds()


## Grabs connect on the throw's startup tick if the opponent is close and throwable.
## Simultaneous throws break each other.
func _resolve_throws() -> void:
	var a := fighters[0]
	var b := fighters[1]
	if a.is_throw_grab_frame() and b.is_throw_grab_frame():
		a.tech_apart()
		b.tech_apart()
		hud.note(0, "TECH")
		hud.note(1, "TECH")
		return
	for attacker in fighters:
		if not attacker.is_throw_grab_frame():
			continue
		var defender := attacker.opponent
		if defender.is_throwable() and _flat(defender.position - attacker.position).length() <= Fighter.THROW_RANGE:
			attacker.on_throw_grabbed()
			defender.on_grabbed_by(attacker)
			throw_landed.emit(attacker, defender)


## Collects all connecting hitboxes first, then applies them, so simultaneous hits trade.
func _resolve_hits() -> void:
	# Capture each attacker's move now: in a trade, applying the first hit clears the
	# other fighter's current_move before its own hit is applied.
	var connecting: Array[Array] = []
	for attacker in fighters:
		var hitbox := attacker.get_active_hitbox()
		if not hitbox.is_empty() and attacker.opponent.overlaps_hurtbox(hitbox.center, hitbox.radius):
			connecting.append([attacker, attacker.current_move])
	for hit in connecting:
		var attacker: Fighter = hit[0]
		var move: MoveData = hit[1]
		var defender := attacker.opponent
		var result := defender.receive_hit(attacker, move)
		attacker.on_hit_confirmed()
		if defender.is_pinned_against_bounds(attacker.forward) and attacker.position.y <= 0.0:
			attacker.velocity -= attacker.forward * move.knockback.x * CORNER_PUSHBACK
		if result == Fighter.HitResult.COUNTER:
			hud.note(fighters.find(attacker), "COUNTER")
		hit_landed.emit(attacker, defender, move, result)


func _on_knocked_out(loser: Fighter) -> void:
	if phase == Phase.FIGHT:
		_knocked_out.append(loser)


func _on_throw_teched(defender: Fighter) -> void:
	hud.note(fighters.find(defender), "TECH")


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Debug / scene input ------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and phase != Phase.MATCH_OVER:
		get_tree().paused = true
		hud.show_pause()
		get_viewport().set_input_as_handled()
	elif OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F1 when not is_versus():
				_cycle_cpu_mode()
			KEY_F4 when not is_versus():
				ai.set_difficulty(((ai.difficulty + 1) % AIController.Difficulty.size()) as AIController.Difficulty)
				Settings.ai_difficulty = ai.difficulty
				Settings.save_settings()
			KEY_F3:
				camera.cycle_mode()
				Settings.camera_mode = camera.mode
				Settings.save_settings()
			KEY_F2:
				debug_draw = not debug_draw
				for fighter in fighters:
					fighter.debug_draw = debug_draw
			KEY_F5:
				start_match()
			_:
				return
		_update_debug_text()


## F1 cycles P2 between the AI and each training-dummy mode.
func _cycle_cpu_mode() -> void:
	cpu_mode += 1
	if cpu_mode >= DummyController.Mode.size():
		cpu_mode = -1
	if cpu_mode < 0:
		ai.reset()
		fighters[1].controller = ai
	else:
		dummy.mode = cpu_mode as DummyController.Mode
		fighters[1].controller = dummy


func _update_debug_text() -> void:
	if not OS.is_debug_build():
		hud.set_debug_text("") # release builds: no debug overlay or debug keys
		return
	if is_versus():
		hud.set_debug_text("VERSUS  ·  F2 Hurtboxes: %s  ·  F3 Action Cam: %s  ·  F5 Restart  ·  Esc Pause" % [
			"On" if debug_draw else "Off", camera.mode_name()])
		return
	var cpu := "AI" if cpu_mode < 0 else "Dummy " + dummy.mode_name()
	hud.set_debug_text("F1 CPU: %s  ·  F4 AI: %s  ·  F2 Hurtboxes: %s  ·  F3 Action Cam: %s  ·  F5 Restart  ·  Esc Pause" % [
		cpu, ai.difficulty_name(), "On" if debug_draw else "Off", camera.mode_name()])
