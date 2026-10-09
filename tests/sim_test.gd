# Headless combat regression test. Run:
#   godot_console --headless --path . -s res://tests/sim_test.gd
# Drives the real fight scene tick-by-tick with a scripted P1. Exit code 1 on failure.
extends SceneTree

class Scripted extends FighterController:
	var dir := 5
	var buttons := 0
	func read(_f: Fighter) -> int:
		var p := InputBuffer.pack(dir, buttons)
		buttons = 0
		return p

var m
var p1: Fighter
var p2: Fighter
var ctl := Scripted.new()
var ctl2 := Scripted.new()
var fails := 0
var errors := ScriptErrorCounter.new()

## A script error aborts the rest of a test section without failing a check, so count
## them as failures too.
class ScriptErrorCounter extends Logger:
	var count := 0
	var first := ""
	## Engine errors (not the headless renderer's material noise), for the network fuzz test.
	var engine_count := 0
	var last_engine := ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1
			if first == "":
				first = "%s (%s:%d %s)" % [rationale, file, line, function]
		elif error_type == ERROR_TYPE_ERROR and not (code + rationale).contains("material"):
			engine_count += 1
			last_engine = "%s %s (%s:%d)" % [code, rationale, file, line]

func check(label: String, ok: bool, extra := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + label + ("  [" + extra + "]" if extra != "" else ""))
	if not ok: fails += 1

func step(n := 1) -> void:
	for i in n: m._physics_process(1.0 / 60.0)

func hold(d: int, n: int) -> void:
	ctl.dir = d; step(n)

func press(button: int, d := 5) -> void:
	ctl.dir = d; ctl.buttons = button; step(1)

func dist() -> float:
	return Vector2(p2.position.x - p1.position.x, p2.position.z - p1.position.z).length()

func reset(mode: int) -> void:
	m.start_match(); m.start_fight_immediately()
	p2.controller = m.dummy; m.dummy.mode = mode; ctl.dir = 5; step(2)

func approach(target: float) -> void:
	ctl.dir = 6
	var guard := 0
	while dist() > target and guard < 300: step(); guard += 1
	ctl.dir = 5; step(1)

func state_name(f: Fighter) -> String: return Fighter.State.keys()[f.state]

## A move's damage from the character's data, so balance changes don't break the tests.
func dmg(f: Fighter, input: String) -> int: return f._move_for_input(input).damage

## Inputs a motion (numpad digits, one tick each) with `button` on the last direction.
func motion(digits: String, button: int) -> void:
	for i in digits.length():
		ctl.dir = int(digits[i])
		if i == digits.length() - 1:
			ctl.buttons = button
		step(1)
	ctl.dir = 5

func wait_until(cond: Callable, limit: int) -> void:
	var g := 0
	while not cond.call() and g < limit: step(); g += 1

func camera_tests() -> void:
	var D := DummyController.Mode
	var cam: ActionCamera = m.camera

	reset(D.STAND)
	check("camera neutral after reset", cam.intensity == 0.0 and cam.focus == null)
	approach(1.0)
	press(InputBuffer.LP); step(6)
	var after_jab := cam.intensity
	check("hit raises intensity and focuses the victim", after_jab > 0.1 and cam.focus == p2, "%.2f" % after_jab)
	step(20); approach(0.85)
	press(InputBuffer.HP, 2); step(12)
	check("launcher raises intensity further", cam.intensity > after_jab + 0.3, "%.2f" % cam.intensity)
	step(120)

	reset(D.STAND_BLOCK); approach(1.0)
	press(InputBuffer.LP); step(6)
	check("blocked hit doesn't set focus", cam.focus == null and cam.intensity < 0.1, "%.2f" % cam.intensity)

	# Both fighters must stay in frame at full action strength, even far apart.
	reset(D.STAND)
	cam.aspect_override = 16.0 / 9.0 # headless viewport is square
	p1.position = Vector3(-3.5, 0, 0.5); p2.position = Vector3(3.5, 0, -0.5)
	p1.reset_physics_interpolation(); p2.reset_physics_interpolation()
	await physics_frame; await physics_frame # interpolated positions update on real physics frames
	cam.focus = p2
	var fitted := cam._fit_strength(1.0)
	check("frame fit keeps both fighters visible", cam._both_fighters_visible(cam._compute_targets(fitted)), "strength %.2f" % fitted)
	p1.position = Vector3(-0.4, 0, 0); p2.position = Vector3(0.4, 0, 0)
	p1.reset_physics_interpolation(); p2.reset_physics_interpolation()
	await physics_frame; await physics_frame # interpolated positions update on real physics frames
	check("close range allows full action strength", cam._fit_strength(1.0) > 0.9, "%.2f" % cam._fit_strength(1.0))

	cam.mode = ActionCamera.Mode.OFF
	cam._add_trauma(1.0)
	check("Off mode suppresses shake", cam._trauma == 0.0)
	cam.mode = ActionCamera.Mode.FULL
	reset(D.STAND)

func milestone4_tests() -> void:
	var D := DummyController.Mode
	var dummy: FighterController = p2.controller

	# Counter hit: jab P2 during its roundhouse startup
	reset(D.STAND); approach(1.0)
	p2.controller = ctl2
	ctl2.buttons = InputBuffer.HK; step(3)
	var hp := p2.health
	press(InputBuffer.LP); step(6)
	check("counter hit: +25% damage", p2.health == hp - roundi(dmg(p1, "LP") * Fighter.COUNTER_DAMAGE_SCALE), "hp %d -> %d" % [hp, p2.health])
	p2.controller = dummy; ctl2.dir = 5; step(40)

	# Combo scaling: second hit of jab -> straight does 90%
	reset(D.STAND); approach(1.0)
	hp = p2.health
	press(InputBuffer.LP); step(5)
	press(InputBuffer.HP); step(20)
	check("combo scaling (jab + straight at 90%)", p2.health == hp - dmg(p1, "LP") - roundi(dmg(p1, "HP") * 0.9), "hp %d -> %d" % [hp, p2.health])

	# Sweep knocks down
	reset(D.STAND); approach(1.0)
	press(InputBuffer.HK, 2)
	wait_until(func(): return p2.state == Fighter.State.KNOCKDOWN, 60)
	check("2HK sweep knocks down", p2.state == Fighter.State.KNOCKDOWN, state_name(p2))

	# Jump-in overhead beats crouch block, loses to stand block
	for mode in [D.CROUCH_BLOCK, D.STAND_BLOCK]:
		reset(mode); step(10)
		p1.position.x = p2.position.x - 2.2
		hp = p2.health
		hold(9, 6)
		wait_until(func(): return p1.position.y > 0.4 and p2.position.x - p1.position.x < 1.4, 60)
		press(InputBuffer.HK, 9)
		wait_until(func(): return p1.is_actionable() or p2.state in [Fighter.State.HITSTUN, Fighter.State.BLOCKSTUN], 60)
		if mode == D.CROUCH_BLOCK:
			check("jump-in HK beats crouch block (overhead)", p2.health < hp, "hp %d -> %d %s" % [hp, p2.health, state_name(p2)])
		else:
			check("jump-in HK is stand-blockable", p2.health == hp and p2.state == Fighter.State.BLOCKSTUN, "hp %d %s" % [p2.health, state_name(p2)])
		hold(5, 40)

	# Only one air attack per jump
	reset(D.STAND)
	hold(8, 8); press(InputBuffer.LK, 8); step(20) # j.LK lasts 19 ticks; still airborne after
	var still_airborne := p1.position.y > 0.0
	press(InputBuffer.LK, 8); step(1)
	check("one air attack per jump", still_airborne and p1.state != Fighter.State.ATTACK, "%s y=%.2f" % [state_name(p1), p1.position.y])
	hold(5, 60)

	# Throw beats block
	reset(D.STAND_BLOCK); approach(0.85)
	hp = p2.health
	ctl.buttons = InputBuffer.LP | InputBuffer.LK; step(1)
	step(Fighter.THROW_STARTUP + 2)
	check("throw grabs a blocking opponent", p2.state == Fighter.State.THROWN, state_name(p2))
	step(Fighter.THROW_HOLD_FRAMES + 12)
	check("throw damages and knocks down", p2.health == hp - p1.data.throw_damage and p2.state in [Fighter.State.AIR_HIT, Fighter.State.KNOCKDOWN], "hp %d %s" % [p2.health, state_name(p2)])
	step(120)

	# Throw tech
	reset(D.STAND); approach(0.85)
	p2.controller = ctl2
	hp = p2.health
	ctl.buttons = InputBuffer.LP | InputBuffer.LK; step(Fighter.THROW_STARTUP + 2)
	ctl2.buttons = InputBuffer.LP | InputBuffer.LK; step(2)
	check("throw tech breaks the grab", p1.state == Fighter.State.TECH and p2.state == Fighter.State.TECH and p2.health == hp, "%s / %s" % [state_name(p1), state_name(p2)])
	p2.controller = dummy; step(40)

	# Throw whiff at range
	reset(D.STAND)
	ctl.buttons = InputBuffer.LP | InputBuffer.LK; step(Fighter.THROW_STARTUP + 2)
	check("throw whiffs at range", p1.state == Fighter.State.THROW and p2.is_actionable(), state_name(p1))
	step(Fighter.THROW_WHIFF_RECOVERY)
	check("throw whiff recovers", p1.is_actionable(), state_name(p1))

	# Juggle limit
	reset(D.STAND)
	p2._set_state(Fighter.State.AIR_HIT); p2.position.y = 1.0
	p2.juggle_hits = Fighter.MAX_JUGGLE_HITS
	check("juggle limit makes airborne fighter unhittable", not p2.overlaps_hurtbox(p2.position + Vector3.UP, 0.5))
	p2.juggle_hits = 0
	check("below juggle limit is hittable", p2.overlaps_hurtbox(p2.position + Vector3.UP, 0.5))
	step(80)

	# Corner pushback: attacker is pushed back when the defender is pinned
	reset(D.STAND_BLOCK)
	p2.position = Vector3(p2.bounds_half_extent, 0, 0); p1.position = Vector3(p2.bounds_half_extent - 1.0, 0, 0)
	step(2)
	var x0 := p1.position.x
	press(InputBuffer.HP); step(30)
	check("corner pushback moves attacker back", p1.position.x < x0 - 0.1, "dx %.2f" % (p1.position.x - x0))

func _initialize() -> void:
	OS.add_logger(errors)
	await process_frame
	# Several screens and tests save settings: keep the player's file byte for byte.
	var settings_file: String = root.get_node("Settings").PATH
	var had_settings := FileAccess.file_exists(settings_file)
	var settings_bytes := FileAccess.get_file_as_bytes(settings_file) if had_settings else PackedByteArray()
	# Fixed matchup: per-character frame data makes timings depend on who's fighting.
	var gs = root.get_node("GameState")
	gs.player_character = gs.roster[0] # Kenji
	gs.p2_character = gs.roster[2] # Brutus
	root.get_node("Settings").graphics = 2 # High: stage checks expect every effect, whatever the player's setting
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame
	await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	var D := DummyController.Mode
	print("P1=%s P2=%s, start dist %.2f" % [p1.data.display_name, p2.data.display_name, dist()])

	# Walk + pushbox
	reset(D.STAND)
	var x0 := p1.position.x
	hold(6, 30)
	check("walk forward moves toward opponent", p1.position.x - x0 > 0.9, "%.2f m in 0.5s" % (p1.position.x - x0))
	hold(6, 120)
	check("pushbox stops overlap", dist() >= 0.69, "dist %.3f" % dist())
	hold(4, 30)
	check("walk back", dist() > 1.0, "dist %.2f" % dist())

	# Jab hits standing dummy
	reset(D.STAND); approach(1.1)
	var hp := p2.health
	press(InputBuffer.LP); step(6)
	check("jab hits", p2.health == hp - dmg(p1, "LP"), "hp %d -> %d, p2 %s" % [hp, p2.health, state_name(p2)])

	# Chain jab -> straight via cancel
	reset(D.STAND); approach(1.0)
	press(InputBuffer.LP); step(5)
	press(InputBuffer.HP); step(20)
	check("jab -> straight cancel combo", p2.combo_hits == 2 or p2.health == p2.data.max_health - dmg(p1, "LP") - dmg(p1, "HP"), "combo %d, hp %d" % [p2.combo_hits, p2.health])

	# Standing block stops a high
	reset(D.STAND_BLOCK); approach(1.1)
	hp = p2.health
	press(InputBuffer.LP); step(6)
	check("stand block blocks jab", p2.health == hp and p2.state == Fighter.State.BLOCKSTUN, "hp %d, %s" % [p2.health, state_name(p2)])
	step(30)

	# Standing block loses to low
	reset(D.STAND_BLOCK); approach(1.1)
	hp = p2.health
	press(InputBuffer.LK, 2); step(10)
	check("low kick (low) beats stand block", p2.health == hp - dmg(p1, "2LK"), "hp %d -> %d" % [hp, p2.health])

	# Crouching dodges highs
	reset(D.CROUCH); approach(1.1)
	hp = p2.health
	press(InputBuffer.LP); step(8)
	check("jab (high) whiffs on crouching", p2.health == hp, "hp %d" % p2.health)

	# Crouch block stops low
	reset(D.CROUCH_BLOCK); step(20); approach(1.1)
	hp = p2.health
	press(InputBuffer.LK, 2); step(10)
	check("crouch block blocks sweep", p2.health == hp and p2.state == Fighter.State.BLOCKSTUN, "hp %d, %s" % [p2.health, state_name(p2)])

	# Launcher -> air hit -> knockdown -> getup
	reset(D.STAND); approach(1.0)
	press(InputBuffer.HP, 2); step(22)
	check("uppercut launches", p2.state == Fighter.State.AIR_HIT and p2.position.y > 0.1, "%s y=%.2f" % [state_name(p2), p2.position.y])
	var g := 0
	while p2.state == Fighter.State.AIR_HIT and g < 200: step(); g += 1
	check("lands into knockdown", p2.state == Fighter.State.KNOCKDOWN, state_name(p2))
	step(Fighter.KNOCKDOWN_FRAMES + Fighter.GETUP_FRAMES + 2)
	check("gets up to neutral", p2.is_actionable(), state_name(p2))

	# KO and reset
	reset(D.STAND); approach(1.1)
	p2.health = 10
	press(InputBuffer.LP); step(6)
	check("KO on lethal hit", p2.state == Fighter.State.KO and m.phase == m.Phase.ROUND_OVER, state_name(p2))
	step(m.ROUND_OVER_TICKS + 1)
	check("round resets after KO", p2.health == p2.data.max_health and p2.is_actionable() and absf(p2.position.x - 2.0) < 0.01, "hp %d, %s" % [p2.health, state_name(p2)])

	# Sidestep (away from camera = -Z) rotates the fight axis and the view follows
	reset(D.STAND)
	press(InputBuffer.SIDESTEP); step(Fighter.SIDESTEP_FRAMES + 1)
	check("sidestep moves into the screen", p1.position.z < -0.5, "z=%.2f" % p1.position.z)
	step(60)
	var axis := (p2.position - p1.position); axis.y = 0
	check("view stays perpendicular to fight axis", absf(m.view_dir.dot(axis.normalized())) < 0.05, "dot %.3f" % m.view_dir.dot(axis.normalized()))
	press(InputBuffer.SIDESTEP, 2); step(Fighter.SIDESTEP_FRAMES + 1)
	check("sidestep down comes back toward camera", p1.position.z > -0.5, "z=%.2f" % p1.position.z)

	# Dash
	reset(D.STAND)
	x0 = p1.position.x
	hold(6, 3); hold(5, 3); hold(6, 1); hold(5, Fighter.DASH_FRAMES)
	check("double-tap forward dashes", p1.position.x - x0 > 0.9, "%.2f m" % (p1.position.x - x0))

	# Jump
	reset(D.STAND)
	hold(9, 10)
	check("forward jump is airborne", p1.position.y > 0.3 and p1.state == Fighter.State.JUMP, "y=%.2f %s" % [p1.position.y, state_name(p1)])
	hold(5, 60)
	check("lands back to neutral", p1.position.y == 0.0 and p1.is_actionable(), state_name(p1))

	# Screen-relative controls flip when sides switch
	reset(D.STAND)
	p1.position = Vector3(2, 0, 0); p2.position = Vector3(-2, 0, 0)
	m.view_dir = Vector3.BACK; step(1)
	check("P1 on right side faces screen-left", not p1.faces_screen_right())

	milestone4_tests()
	await camera_tests()
	ai_tests()
	round_tests()
	character_tests()
	fx_tests()
	await face_tests()
	specials_tests()
	await character_specials_tests()
	await versus_tests()
	await training_tests()
	await arcade_tests()
	await stage_tests()
	await polish_tests()
	graphics_tests()
	await personality_tests()
	await showcase_tests()
	await loading_tests()
	await valka_tests()
	await temple_tests()
	await jin_tests()
	await mira_tests()
	await lian_tests()
	await beach_tests()
	await market_tests()
	await train_tests()
	await scores_credits_tests()
	await controls_tests()
	await outfit_tests()
	await rollback_tests()
	await net_tests()
	await server_tests()

	if had_settings:
		var f := FileAccess.open(settings_file, FileAccess.WRITE)
		f.store_buffer(settings_bytes)
		f.close()
	elif FileAccess.file_exists(settings_file):
		DirAccess.remove_absolute(settings_file)
	check("the player's settings file is left as it was", not had_settings or FileAccess.get_file_as_bytes(settings_file) == settings_bytes)
	check("no script errors during the run", errors.count == 0, "%d, first: %s" % [errors.count, errors.first])
	print("\n%d failure(s)" % fails)
	quit(1 if fails else 0)

func ai_tests() -> void:
	var D := DummyController.Mode

	# Blocks a telegraphed roundhouse (fast reactions, guaranteed block, no offense).
	var ai := AIController.new(AIController.Difficulty.HARD, 7)
	ai.attach(p2)
	reset(D.STAND); p2.controller = ai; ai.reset()
	ai.reaction_frames = 2; ai.block_reaction_frames = 2; ai.block_chance = 1.0; ai.punish_chance = 0.0
	ai.anti_air_chance = 0.0; ai.decision_interval = 100000
	approach(1.1)
	var hp := p2.health
	press(InputBuffer.HK)
	wait_until(func(): return p2.state == Fighter.State.BLOCKSTUN or p2.health < hp, 30)
	check("AI blocks a telegraphed high", p2.state == Fighter.State.BLOCKSTUN and p2.health == hp, "%s hp %d" % [state_name(p2), p2.health])
	step(60)

	# Punishes a whiffed uppercut from jab range.
	reset(D.STAND); p2.controller = ai; ai.reset()
	ai.reaction_frames = 4; ai.punish_chance = 1.0; ai.block_chance = 0.0; ai.combo_drop_chance = 0.0
	approach(1.15)
	var p1_hp := p1.health
	press(InputBuffer.HP, 2)
	wait_until(func(): return p1.health < p1_hp, 50)
	check("AI punishes a whiffed uppercut", p1.health < p1_hp, "p1 hp %d -> %d" % [p1_hp, p1.health])
	step(90)

	# AI vs AI: 30 seconds of real fighting, everyone in bounds.
	var result := _ai_match(3, 5, 1800)
	check("AI vs AI lands hits", result.hits >= 10, "%d hits, %d blocks, %d KOs" % [result.hits, result.blocks, result.kos])
	check("AI vs AI blocks some", result.blocks >= 1, "%d blocks" % result.blocks)
	check("fighters stay in bounds", result.in_bounds)

	# Determinism: same seeds, same inputs -> identical match.
	var a := _ai_match(11, 12, 600)
	var b := _ai_match(11, 12, 600)
	check("AI match is deterministic", a.state == b.state, "%s vs %s" % [a.state, b.state])

	p1.controller = ctl
	reset(D.STAND)


## Runs an AI-vs-AI match from a fresh round and summarizes it.
func _ai_match(seed1: int, seed2: int, ticks: int) -> Dictionary:
	var ai1 := AIController.new(AIController.Difficulty.NORMAL, seed1)
	var ai2 := AIController.new(AIController.Difficulty.NORMAL, seed2)
	ai1.attach(p1); ai2.attach(p2)
	m.start_match(); m.start_fight_immediately()
	p1.controller = ai1; p2.controller = ai2
	var stats := {hits = 0, blocks = 0, kos = 0, in_bounds = true}
	var on_hit := func(_a, _d, _m, r):
		if r == Fighter.HitResult.BLOCKED: stats.blocks += 1
		else: stats.hits += 1
	var on_ko := func(_f): stats.kos += 1
	m.hit_landed.connect(on_hit)
	p1.knocked_out.connect(on_ko); p2.knocked_out.connect(on_ko)
	for i in ticks:
		step()
		for f in [p1, p2]:
			if absf(f.position.x) > f.bounds_half_extent + 0.01 or absf(f.position.z) > f.bounds_half_extent + 0.01:
				stats.in_bounds = false
	m.hit_landed.disconnect(on_hit)
	p1.knocked_out.disconnect(on_ko); p2.knocked_out.disconnect(on_ko)
	stats.state = "%d/%d %s %s" % [p1.health, p2.health, p1.position.snappedf(0.001), p2.position.snappedf(0.001)]
	return stats

func round_tests() -> void:
	p1.controller = ctl
	p2.controller = m.dummy
	m.dummy.mode = DummyController.Mode.STAND
	m.start_match()
	check("round intro locks input", m.phase == m.Phase.INTRO and p1.input_locked and m.round_number == 1)
	step(m.INTRO_TICKS)
	check("FIGHT! unlocks input", m.phase == m.Phase.FIGHT and not p1.input_locked)
	var t0: int = m.timer_ticks
	step(60)
	check("round timer counts down", t0 - m.timer_ticks == 60, "%d" % (t0 - m.timer_ticks))

	# KO wins the round, then round 2 starts with full health.
	approach(1.1)
	p2.health = 10
	press(InputBuffer.LP); step(6)
	check("KO awards the round", m.phase == m.Phase.ROUND_OVER and m.round_wins == [1, 0], "%s %s" % [m.Phase.keys()[m.phase], m.round_wins])
	step(m.ROUND_OVER_TICKS)
	check("next round starts", m.phase == m.Phase.INTRO and m.round_number == 2 and p2.health == p2.data.max_health)

	# Time out: more health (as a share of max) wins; second win ends the match.
	step(m.INTRO_TICKS)
	p2.health = p2.data.max_health / 2
	m.timer_ticks = 2
	step(3)
	check("time out goes to the healthier fighter", m.round_wins == [2, 0], "%s" % [m.round_wins])
	step(m.ROUND_OVER_TICKS)
	check("two round wins end the match", m.phase == m.Phase.MATCH_OVER and p1.victory)

	# Double K.O. is a draw round.
	m.start_match(); m.start_fight_immediately()
	p1.health = 0; p2.health = 0
	p1._knock_out(Vector3.LEFT); p2._knock_out(Vector3.RIGHT)
	step(1)
	check("double K.O. is a draw", m.phase == m.Phase.ROUND_OVER and m.round_wins == [0, 0] and m.round_winner == null)
	m.start_match()

func character_tests() -> void:
	var D := DummyController.Mode
	var roster: Array = root.get_node("GameState").roster
	var kenji: CharacterData = roster[0]
	var rhea: CharacterData = roster[1]
	var brutus: CharacterData = roster[2]
	var startup := func(c: CharacterData, input: String) -> int:
		for mv in c.moves:
			if mv.input == input: return mv.startup
		return -1
	check("Rhea is faster than Brutus (jab startup)", startup.call(rhea, "LP") < startup.call(kenji, "LP") and startup.call(kenji, "LP") < startup.call(brutus, "LP"),
		"%d / %d / %d" % [startup.call(rhea, "LP"), startup.call(kenji, "LP"), startup.call(brutus, "LP")])
	check("each character has signature moves", startup.call(kenji, "6HP") > 0 and startup.call(rhea, "6HP") > 0 and startup.call(brutus, "6HP") > 0)
	check("throw damage differs by character", brutus.throw_damage > kenji.throw_damage and kenji.throw_damage > rhea.throw_damage)

	# Forward + HP picks the signature move and lunges; plain HP is still the straight.
	reset(D.STAND)
	var x0 := p1.position.x
	press(InputBuffer.HP, 6); step(1)
	check("6HP selects Advancing Straight", p1.current_move != null and p1.current_move.name == "Advancing Straight", p1.current_move.name if p1.current_move else "none")
	step(12)
	check("lunge carries the attacker forward", p1.position.x - x0 > 0.6, "%.2f m" % (p1.position.x - x0))
	step(40)
	press(InputBuffer.HP); step(1)
	check("plain HP is still the Straight", p1.current_move != null and p1.current_move.name == "Straight")
	step(40)

	# Brutus's Overhead Smash beats a crouch block and knocks down.
	reset(D.STAND)
	var p1_dummy := DummyController.new()
	p1_dummy.mode = DummyController.Mode.CROUCH_BLOCK
	p1.controller = p1_dummy
	p2.controller = ctl2
	p2.position.x = p1.position.x + 1.1
	p1.reset_physics_interpolation(); p2.reset_physics_interpolation()
	step(10)
	var hp := p1.health
	ctl2.dir = 6; ctl2.buttons = InputBuffer.HP; step(1); ctl2.dir = 5
	wait_until(func(): return p1.state in [Fighter.State.AIR_HIT, Fighter.State.KNOCKDOWN, Fighter.State.BLOCKSTUN], 40)
	check("Overhead Smash beats crouch block", p1.health < hp and p1.state != Fighter.State.BLOCKSTUN, "hp %d -> %d %s" % [hp, p1.health, state_name(p1)])
	wait_until(func(): return p1.state == Fighter.State.KNOCKDOWN, 60)
	check("Overhead Smash knocks down", p1.state == Fighter.State.KNOCKDOWN, state_name(p1))
	p1.controller = ctl
	reset(D.STAND)

func fx_tests() -> void:
	reset(DummyController.Mode.STAND)
	approach(1.0)
	var before: int = m.fx.spawned
	press(InputBuffer.LP); step(6)
	check("hits spawn effects", m.fx.spawned > before, "%d -> %d" % [before, m.fx.spawned])
	check("audio buses exist", AudioServer.get_bus_index("Music") > 0 and AudioServer.get_bus_index("SFX") > 0 and AudioServer.get_bus_index("Voice") > 0
		and AudioServer.get_bus_index("Ambience") > 0)
	var limiters := range(AudioServer.get_bus_effect_count(0)).filter(func(i: int) -> bool: return AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter)
	check("the master bus has one limiter (ceiling -1 dB) so the mix never clips", limiters.size() == 1
		and is_equal_approx((AudioServer.get_bus_effect(0, limiters[0]) as AudioEffectHardLimiter).ceiling_db, -1.0))

## Joypad device assigned to an action (first joypad event), or -99 if none.
func _pad_device(action: String) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			return ev.device
	return -99

func versus_tests() -> void:
	var gs = root.get_node("GameState")
	var setup = root.get_node("InputSetup")
	setup.apply(false)
	check("gamepad 1 -> P1, gamepad 2 -> P2", _pad_device("p1_lp") == 0 and _pad_device("p2_lp") == 1)
	setup.apply(true)
	check("swap setting gives gamepad 1 to P2", _pad_device("p1_lp") == 1 and _pad_device("p2_lp") == 0)
	setup.apply(false)
	check("P2 keyboard has numpad + fallback keys", InputMap.action_get_events("p2_lp").filter(func(e): return e is InputEventKey).size() == 2)

	# Versus fight: P2 is a second player controller, independent of P1.
	gs.mode = gs.Mode.VERSUS
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[1]
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	var vm = current_scene
	vm.set_physics_process(false)
	vm.start_fight_immediately()
	var a: Fighter = vm.fighters[0]
	var b: Fighter = vm.fighters[1]
	check("Versus: P2 is player-controlled", b.controller is PlayerController and (b.controller as PlayerController).prefix == "p2_")
	var ax := a.position.x
	var bx := b.position.x
	Input.action_press("p2_left") # P2 starts on the right: left = toward P1
	for i in 30: vm._physics_process(1.0 / 60.0)
	Input.action_release("p2_left")
	check("P2's keys move only P2", b.position.x < bx - 0.5 and absf(a.position.x - ax) < 0.01, "P2 dx %.2f, P1 dx %.2f" % [b.position.x - bx, a.position.x - ax])
	Input.action_press("p1_lp")
	vm._physics_process(1.0 / 60.0)
	Input.action_release("p1_lp")
	vm._physics_process(1.0 / 60.0)
	check("P1's attack button attacks with P1 only", a.state == Fighter.State.ATTACK and b.state != Fighter.State.ATTACK, "%s / %s" % [state_name(a), state_name(b)])

	# Mirror match: P2 gets the alternate look.
	gs.p2_character = gs.roster[0]
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	check("mirror match gives P2 the alternate look", current_scene.fighters[1].alt and not current_scene.fighters[0].alt)
	gs.mode = gs.Mode.VS_CPU

func training_tests() -> void:
	var gs = root.get_node("GameState")
	gs.mode = gs.Mode.TRAINING
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2] # Kenji vs Brutus
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl; ctl.dir = 5
	var tm: TrainingMode = m.get_node("TrainingMode")
	tm._player_controller = ctl
	var dc := p2.controller as TrainingDummyController
	check("Training: dummy controller, fight starts without intro", dc != null and m.phase == m.Phase.FIGHT and not p1.input_locked)

	# Endless: the dummy can't be knocked out, and health refills after the combo.
	step(2); approach(1.1)
	p2.health = 5
	press(InputBuffer.LP); step(8)
	check("Training: dummy survives a lethal hit", p2.health == 1 and p2.state != Fighter.State.KO and m.phase == m.Phase.FIGHT, "hp %d, %s" % [p2.health, state_name(p2)])
	check("Training: input history logs the jab", tm.history.any(func(e): return ((e[0] >> InputBuffer.BUTTON_SHIFT) & InputBuffer.LP) != 0))
	wait_until(func() -> bool: return not tm.last_frame_data.is_empty(), 60)
	check("Training: jab frame data measured (+5 on hit)", tm.last_frame_data.get("advantage") == "+5" and tm.last_frame_data.get("startup") == 5,
		str(tm.last_frame_data))
	step(TrainingMode.REFILL_DELAY_TICKS + 30)
	check("Training: health refills", p2.health == p2.data.max_health, "hp %d" % p2.health)

	# Guard "Block All" picks the right height.
	dc.guard = TrainingDummyController.Guard.ALL
	var hp := p2.health
	press(InputBuffer.LK, 2); step(10)
	check("Training: Block All crouch-blocks a low", p2.health == hp and p2.state == Fighter.State.BLOCKSTUN and p2.crouching, "hp %d, %s" % [p2.health, state_name(p2)])
	step(40)
	press(InputBuffer.LP); step(8)
	check("Training: Block All stand-blocks a high", p2.health == hp and p2.state == Fighter.State.BLOCKSTUN and not p2.crouching, "hp %d, %s" % [p2.health, state_name(p2)])
	dc.guard = TrainingDummyController.Guard.NONE
	step(40)

	# Record: P1's inputs drive the dummy (P1 stands still), then loop on playback.
	tm.reset_positions(); step(2)
	var p1x := p1.position.x
	var p2x := p2.position.x
	tm.start_recording()
	hold(4, 30) # back, relative to the dummy's facing: away from P1
	tm.stop_recording()
	check("Training: recording moves the dummy, not P1", p2.position.x > p2x + 0.3 and absf(p1.position.x - p1x) < 0.01,
		"dummy dx %.2f, P1 dx %.2f" % [p2.position.x - p2x, p1.position.x - p1x])
	check("Training: recording saved and playing back", dc.recording.size() == 30 and dc.stance == TrainingDummyController.Stance.PLAYBACK and p1.controller == ctl,
		"%d ticks, %s" % [dc.recording.size(), dc.stance_name()])
	tm.reset_positions(); step(2)
	p2x = p2.position.x
	hold(5, 28)
	check("Training: playback replays the recording", p2.position.x > p2x + 0.3, "dx %.2f" % (p2.position.x - p2x))
	gs.mode = gs.Mode.VS_CPU


func specials_tests() -> void:
	var D := DummyController.Mode
	var buf := InputBuffer.new()
	for d in [5, 2, 3, 6]: buf.push(InputBuffer.pack(d, 0))
	check("motion: 236 detected", buf.motion([2, 3, 6], 14, 8) and not buf.motion([6, 2, 3], 14, 8))

	# Projectile: fires on its first active frame, flies, hits for its damage.
	reset(D.STAND)
	motion("236", InputBuffer.HP)
	check("236P starts Ki Blast", p1.current_move != null and p1.current_move.name == "Ki Blast")
	wait_until(func() -> bool: return p1.projectile != null, 20)
	check("Ki Blast fires a projectile", p1.projectile != null)
	var hp := p2.health
	wait_until(func() -> bool: return p1.projectile == null, 90)
	check("projectile hits for its damage", p2.health == hp - dmg(p1, "236P") and p2.state == Fighter.State.HITSTUN, "hp %d -> %d" % [hp, p2.health])

	# One projectile at a time: from long range the first is still flying when P1 recovers.
	reset(D.STAND)
	p1.position.x = -3.5; p2.position.x = 3.5
	motion("236", InputBuffer.HP)
	wait_until(func() -> bool: return p1.is_actionable(), 80)
	motion("236", InputBuffer.HP)
	check("no second projectile while one is in flight", p1.projectile != null and (p1.current_move == null or p1.current_move.name != "Ki Blast"),
		p1.current_move.name if p1.current_move else state_name(p1))
	step(60)

	# Chip damage through a block, and meter for both sides.
	reset(D.STAND_BLOCK)
	motion("236", InputBuffer.HP)
	wait_until(func() -> bool: return p1.projectile == null and p1.state != Fighter.State.ATTACK, 120)
	check("blocked projectile deals chip damage", p2.health == p2.data.max_health - 8, "hp %d" % p2.health)
	check("meter: special start + blocked hit, defender gains too", p1.meter == Fighter.METER_PER_SPECIAL + roundi(dmg(p1, "236P") * Fighter.METER_PER_DAMAGE_BLOCKED)
		and p2.meter == roundi(p1._move_for_input("236P").chip_damage * Fighter.METER_PER_DAMAGE_TAKEN), "p1 %d p2 %d" % [p1.meter, p2.meter])

	# Cancel a jab into a special during its hitstop.
	reset(D.STAND); approach(1.0)
	press(InputBuffer.LP)
	wait_until(func() -> bool: return p2.state == Fighter.State.HITSTUN, 10)
	motion("236", InputBuffer.HP)
	step(12)
	check("jab cancels into Ki Blast", p1.projectile != null or (p1.current_move != null and p1.current_move.name == "Ki Blast"),
		p1.current_move.name if p1.current_move else state_name(p1))
	step(60)

	# Rising Dragon: invincible startup, rises, launches, extra landing lag.
	reset(D.STAND); approach(1.0)
	step(16) # 6-5-6 within the double-tap window would be a dash
	motion("623", InputBuffer.HP)
	check("623P starts Rising Dragon, invincible on startup", p1.current_move != null and p1.current_move.name == "Rising Dragon" and p1.is_invulnerable()
		and not p1.overlaps_hurtbox(p1.position + Vector3.UP, 0.3))
	wait_until(func() -> bool: return p2.state == Fighter.State.AIR_HIT, 20)
	check("Rising Dragon launches and rises", p2.state == Fighter.State.AIR_HIT and p1.position.y > 0.05, "%s y=%.2f" % [state_name(p2), p1.position.y])
	wait_until(func() -> bool: return p1.state == Fighter.State.LANDING, 120)
	check("Rising Dragon has landing recovery", p1._landing_frames == Fighter.LANDING_FRAMES + p1._move_for_input("623P").landing_recovery, str(p1._landing_frames))
	step(120)

	# Super: needs a full meter; freezes the fight, multi-hits, chains into the finisher.
	reset(D.STAND); approach(1.0)
	motion("236236", InputBuffer.HP)
	check("no super without meter", m.freeze_ticks == 0 and (p1.current_move == null or not p1.current_move.super_move))
	step(80)
	reset(D.STAND); approach(1.0)
	p1.add_meter(Fighter.MAX_METER)
	motion("236236", InputBuffer.HP)
	check("super starts: freeze, meter spent", m.freeze_ticks > 0 and p1.frozen and p1.meter == 0 and p1.current_move.super_move, "freeze %d meter %d" % [m.freeze_ticks, p1.meter])
	var x1 := p1.position.x
	step(m.SUPER_FREEZE_TICKS - 2)
	check("nothing moves during the super freeze", p1.position.x == x1 and p1.state_frame == 0)
	hp = p2.health
	var max_combo := 0
	for i in 120:
		step(1)
		max_combo = maxi(max_combo, p2.combo_hits)
	check("super lands all hits and the finisher", max_combo >= 7 and hp - p2.health >= 150, "combo %d, dmg %d" % [max_combo, hp - p2.health])

	# The AI zones with its projectile from range.
	reset(D.STAND)
	p1.position.x = -3.0; p2.position.x = 3.0
	var cpu := AIController.new(AIController.Difficulty.HARD, 5)
	cpu.attach(p1)
	p1.controller = cpu
	var fired := [0]
	var count := func(move: MoveData) -> void:
		if move.projectile_speed > 0.0: fired[0] += 1
	p1.attack_started.connect(count)
	for i in 600:
		step(1)
	p1.attack_started.disconnect(count)
	p1.controller = ctl
	check("AI throws fireballs from range", fired[0] > 0, "%d fired" % fired[0])


func character_specials_tests() -> void:
	var gs = root.get_node("GameState")
	var D := DummyController.Mode
	for pick in [1, 2]: # Rhea, Brutus vs Kenji
		gs.player_character = gs.roster[pick]; gs.p2_character = gs.roster[0]
		change_scene_to_file("res://scenes/fight.tscn")
		await process_frame; await process_frame
		m = current_scene
		m.set_physics_process(false)
		p1 = m.fighters[0]; p2 = m.fighters[1]
		p1.controller = ctl
		if pick == 1:
			reset(D.STAND_BLOCK); p1.position.x = -1.0; p2.position.x = 1.0
			motion("236", InputBuffer.HK)
			check("Rhea: Gale Slide is low profile", p1.current_move.name == "Gale Slide" and p1.crouching)
			wait_until(func() -> bool: return p2.state == Fighter.State.AIR_HIT or p2.state == Fighter.State.KNOCKDOWN, 40)
			check("Rhea: slide beats a standing block and knocks down", p2.state in [Fighter.State.AIR_HIT, Fighter.State.KNOCKDOWN], state_name(p2))
			reset(D.CROUCH_BLOCK); step(20); p1.position.x = -1.0; p2.position.x = 1.0
			motion("236", InputBuffer.LK)
			wait_until(func() -> bool: return p2.state == Fighter.State.BLOCKSTUN, 40)
			check("Rhea: slide is crouch-blockable (with chip)", p2.state == Fighter.State.BLOCKSTUN and p2.health == p2.data.max_health - 8, "%s hp %d" % [state_name(p2), p2.health])
		else:
			reset(D.STAND); p1.position.x = -1.5; p2.position.x = 1.5
			var x0 := p1.position.x
			motion("236", InputBuffer.HP)
			wait_until(func() -> bool: return p2.state == Fighter.State.HITSTUN, 40)
			check("Brutus: Bull Charge travels in and hits", p2.state == Fighter.State.HITSTUN and p1.position.x - x0 > 0.8, "moved %.2f, %s" % [p1.position.x - x0, state_name(p2)])
			reset(D.STAND_BLOCK); approach(1.2)
			motion("214", InputBuffer.HP)
			wait_until(func() -> bool: return p2.state == Fighter.State.AIR_HIT, 40)
			check("Brutus: Earthquake hits low through a standing block", p2.state == Fighter.State.AIR_HIT, state_name(p2))
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2]


func arcade_tests() -> void:
	var gs = root.get_node("GameState")
	var kenji: CharacterData = gs.roster[0]
	var run := ArcadeRun.create(kenji, gs.roster, AIController.Difficulty.NORMAL, 3, gs.arcade_arenas(), gs.DOJO_STAGE)
	var opponents := run.stages.map(func(e: Dictionary) -> CharacterData: return e.character)
	check("Arcade: ladder = every other fighter, then the shadow boss", run.stages.size() == gs.roster.size()
		and not opponents.slice(0, -1).has(kenji) and run.stages[-1].boss and opponents[-1] == kenji, str(opponents.map(func(c): return c.display_name)))
	check("Arcade: difficulty rises, boss on Hard", run.stages[0].difficulty == AIController.Difficulty.EASY
		and run.stages[1].difficulty == AIController.Difficulty.NORMAL and run.stages[-1].difficulty == AIController.Difficulty.HARD)
	var bonus := run.add_round_bonus(50, 1.0)
	check("Arcade: round bonus (time + life + perfect)", bonus.total == 5000 + 5000 + 10000 and run.perfects == 1, str(bonus))
	run.clear_stage()
	check("Arcade: stage clear points and next stage", run.score == 20000 + 10000 and run.stage == 1 and run.stage_start_score == run.score, str(run.score))
	run.add_damage(50)
	run.restart_stage(true)
	check("Arcade: a continue replays the stage from its starting score", run.score == 30000 and run.continues == 1)

	# A real stage: score from damage, round bonuses, then "Next Stage".
	gs.mode = gs.Mode.ARCADE
	gs.start_arcade(kenji)
	var first: Dictionary = gs.arcade.current()
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	check("Arcade: CPU difficulty comes from the ladder", m.ai.difficulty == first.difficulty and p2.data == first.character)
	for round_index in 2:
		m.start_fight_immediately()
		p2.controller = m.dummy; m.dummy.mode = DummyController.Mode.STAND
		approach(1.1)
		var before: int = gs.arcade.score
		p2.health = 10
		press(InputBuffer.LP); step(8)
		check("Arcade: round %d won, damage + bonus scored" % (round_index + 1), m.phase in [m.Phase.ROUND_OVER, m.Phase.MATCH_OVER] and gs.arcade.score > before + 100,
			"score %d -> %d" % [before, gs.arcade.score])
		step(m.ROUND_OVER_TICKS + 1)
	check("Arcade: match won -> stage 2, Next Stage", m.phase == m.Phase.MATCH_OVER and gs.arcade.stage == 1
		and m.hud.get_node("%RematchButton").text == "Next Stage" and not m.hud.get_node("%ResultSelectButton").visible)
	m._on_rematch_pressed()
	check("Arcade: next stage sets the next opponent", gs.p2_character == gs.arcade.current().character)
	await process_frame; await process_frame

	# Losing offers a continue, which restarts the stage.
	gs.arcade.stage = gs.arcade.stages.size() - 1
	gs.apply_arcade_stage()
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	check("Arcade: the boss is the shadow (alt look) with a full meter", m.fighters[1].alt and m.fighters[1].meter == Fighter.MAX_METER and m.ai.difficulty == AIController.Difficulty.HARD)
	m.phase = m.Phase.MATCH_OVER
	m._arcade_match_over(false)
	var continues: int = gs.arcade.continues
	check("Arcade: a loss offers Continue / Give Up", m.hud.get_node("%RematchButton").text == "Continue" and m.hud.get_node("%ResultMenuButton").text == "Give Up")
	m._on_rematch_pressed()
	check("Arcade: Continue restarts the stage and counts", gs.arcade.continues == continues + 1 and m.phase == m.Phase.INTRO)
	gs.arcade = null
	gs.mode = gs.Mode.VS_CPU


## Every file path under `dir` (recursive).
func _files_under(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_files_under(dir.path_join(sub)))
	return out


func stage_tests() -> void:
	var gs = root.get_node("GameState")
	check("Stages: every listed stage and thumbnail exists", gs.STAGES.all(func(st: Dictionary) -> bool:
		return ResourceLoader.exists(st.path) and ResourceLoader.exists(st.thumb)))
	# Polish: baked contact shadows (an AO overlay, or the rooftop's wet-deck shader) and
	# each stage's ambient effects.
	var polish := {gs.DEFAULT_STAGE: [["CanvasShadows", "ArenaShadows"], ["Dust", "CameraFlashes", "Sound"]],
		gs.DOJO_STAGE: [["FloorShadows"], ["Dust", "CandleFlicker", "IncenseSmoke", "Sound"]],
		gs.TEMPLE_STAGE: [["GravelShadows"], ["LanternFlicker", "Sound"]],
		gs.BEACH_STAGE: [["SandShadows"], ["SeaSpray", "TorchFire0", "TorchEmbers0", "Sound"]],
		gs.MARKET_STAGE: [["StreetShadows"], ["GrillSmoke0", "GrillSparks0", "GrillFlicker", "Ambience", "Sound"]]}
	var missing := []
	for path: String in polish:
		var scene := (load(path) as PackedScene).instantiate()
		for overlay_name: String in polish[path][0]:
			var overlay := scene.get_node_or_null(overlay_name) as MeshInstance3D
			var texture: Texture2D = (overlay.mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture if overlay else null
			# Somewhere shadowed (darker than 0.8) and somewhere open (brighter than 0.95).
			var image := texture.get_image() if texture else null
			var darkest := 1.0
			var brightest := 0.0
			if image:
				for y in range(0, image.get_height(), 4):
					for x in range(0, image.get_width(), 4):
						darkest = minf(darkest, image.get_pixel(x, y).r)
						brightest = maxf(brightest, image.get_pixel(x, y).r)
			if darkest > 0.8 or brightest < 0.95:
				missing.append("%s/%s" % [path.get_file(), overlay_name])
		for effect: String in polish[path][1]:
			if scene.get_node_or_null(effect) == null:
				missing.append("%s/%s" % [path.get_file(), effect])
		scene.free()
	check("Stages: baked contact shadows and ambient effects", missing.is_empty(), "%s" % [missing])
	var ring_crowd := (load(gs.DEFAULT_STAGE) as PackedScene).instantiate()
	check("Stages: the ring crowd is animated", (ring_crowd.get_node("Crowd") as Crowd).jump > 0.0)
	# Download size: 3D textures must not be imported lossless (a 1K photo texture is 2-3 MB
	# lossless, about 0.4 MB as lossy WebP). Godot only switches them automatically in the
	# editor, so textures imported headless stay lossless unless their .import says otherwise.
	var lossless := []
	for dir in ["res://assets/stages/", "res://assets/characters/"]:
		for path in _files_under(dir):
			if path.ends_with(".import"):
				var text := FileAccess.get_file_as_string(path)
				if 'importer="texture"' in text and "compress/mode=0" in text:
					lossless.append(path.get_file())
	check("Download size: no 3D texture is imported lossless", lossless.is_empty(), "%s" % [lossless])
	ring_crowd.free()

	# Stage select: a choice sets the stage; Random picks one of the list.
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2]
	change_scene_to_file("res://scenes/stage_select.tscn")
	await process_frame; await process_frame
	current_scene.choose(gs.DOJO_STAGE)
	check("Stage select: choosing the dojo sets it", gs.stage_path == gs.DOJO_STAGE)
	await process_frame; await process_frame
	check("Stage select: continues to the VS screen", current_scene.scene_file_path == "res://scenes/vs_screen.tscn")
	change_scene_to_file("res://scenes/stage_select.tscn")
	await process_frame; await process_frame
	current_scene.choose("")
	check("Stage select: Random picks a listed stage", gs.STAGES.any(func(st: Dictionary) -> bool: return st.path == gs.stage_path))
	await process_frame; await process_frame

	# A full fight in the dojo.
	gs.stage_path = gs.DOJO_STAGE
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	check("Dojo: loads with the standard bounds and spawns", m.stage.name == "Dojo" and m.stage.bounds_half_extent == 3.6
		and absf(p1.position.x + 2.0) < 0.01 and absf(p2.position.x - 2.0) < 0.01)
	reset(DummyController.Mode.STAND); approach(1.1)
	var hp := p2.health
	press(InputBuffer.LP); step(6)
	check("Dojo: combat works the same", p2.health == hp - dmg(p1, "LP"), "hp %d -> %d" % [hp, p2.health])
	m.stage.update_camera_occlusion(Vector3(0, 2, 7.0))
	var front: Array = get_nodes_in_group(&"ring_side_1")
	check("Dojo: students between the camera and the fight hide", not front.is_empty() and front.all(func(n: Node3D) -> bool: return not n.visible))

	# Arcade stages: alternate arenas, boss in the dojo.
	# Stages: drawn at random once per run, no arena twice (with more arenas than fights,
	# some sit out), boss always in the dojo.
	var arenas: Array = gs.arcade_arenas()
	var orders := {}
	var each_once := true
	for seed_value in 12:
		var run := ArcadeRun.create(gs.roster[0], gs.roster, 1, seed_value, arenas, gs.DOJO_STAGE)
		var regular: Array = run.stages.slice(0, -1).map(func(e: Dictionary) -> String: return e.stage_path)
		var distinct := {}
		for path: String in regular:
			distinct[path] = true
		var all_arenas := regular.all(func(p: String) -> bool: return p in arenas)
		if distinct.size() != mini(regular.size(), arenas.size()) or not all_arenas or run.stages[-1].stage_path != gs.DOJO_STAGE:
			each_once = false
		orders[str(regular)] = true
	check("Arcade: no arena twice in a run (random order), then the boss in the dojo", each_once)
	check("Arcade: the stage order differs between runs", orders.size() >= 6, "%d different orders in 12 runs" % orders.size())
	var two: Array = arenas.slice(0, 2) # more fights than stages: reshuffles, never the same stage twice in a row
	var repeats := false
	for seed_value in 12:
		var run := ArcadeRun.create(gs.roster[0], gs.roster, 1, seed_value, two, gs.DOJO_STAGE)
		for i in range(1, run.stages.size() - 1):
			if run.stages[i].stage_path == run.stages[i - 1].stage_path:
				repeats = true
	check("Arcade: with fewer stages than fights, no stage twice in a row", not repeats)
	var run := ArcadeRun.create(gs.roster[0], gs.roster, 1, 9, arenas, gs.DOJO_STAGE)
	var stage_before: String = run.current().stage_path
	run.restart_stage(true)
	check("Arcade: a continue replays the same stage", run.current().stage_path == stage_before)
	# The rooftop: loads, fights, and its sky shader compiles.
	gs.stage_path = gs.ROOFTOP_STAGE
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	reset(DummyController.Mode.STAND); approach(1.1)
	hp = p2.health
	press(InputBuffer.LP); step(6)
	check("Rooftop: loads and combat works", m.stage.name == "Rooftop" and p2.health == hp - dmg(p1, "LP"), "hp %d -> %d" % [hp, p2.health])
	# After the rain: wet deck with baked contact shadows, reflections, drizzle, neon.
	var deck_material: ShaderMaterial = null
	for mi: MeshInstance3D in m.stage.find_children("*", "MeshInstance3D", true, false):
		var material := mi.mesh.surface_get_material(0) if mi.mesh else null
		if material is ShaderMaterial and (material as ShaderMaterial).get_shader_parameter("textured"):
			deck_material = material
	var ao: Texture2D = deck_material.get_shader_parameter("ao_tex") if deck_material else null
	var ao_image := ao.get_image() if ao else null
	check("Rooftop: wet deck with baked contact shadows", ao_image != null and ao_image.get_size() == Vector2i(256, 256)
		and ao_image.get_pixel(128, 128).r > 0.9 and ao_image.get_pixel(int((8.5 + 13.0) / 26.0 * 256), int((-7.6 + 13.0) / 26.0 * 256)).r < 0.75,
		"AO %s" % [ao_image.get_size() if ao_image else "missing"])
	var ambience := m.stage.get_node_or_null("Ambience") as NeonAmbience
	check("Rooftop: reflections, drizzle and neon ambience", m.stage.get_node_or_null("Lights/WetReflections") is ReflectionProbe
		and m.stage.get_node_or_null("Rain") is GPUParticles3D and ambience != null and ambience._labels.size() == 1 and ambience._blinks.size() == 1
		and m.stage.get_node_or_null("Sound") is StageAmbience)
	gs.stage_path = gs.DEFAULT_STAGE


func polish_tests() -> void:
	var gs = root.get_node("GameState")
	var audio = root.get_node("Audio")
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2]
	# Each stage brings its own music.
	for entry in [[gs.DOJO_STAGE, &"dojo"], [gs.ROOFTOP_STAGE, &"rooftop"], [gs.TEMPLE_STAGE, &"temple"], [gs.BEACH_STAGE, &"beach"], [gs.MARKET_STAGE, &"market"], [gs.TRAIN_STAGE, &"train"], [gs.DEFAULT_STAGE, &"fight"]]:
		gs.stage_path = entry[0]
		change_scene_to_file("res://scenes/fight.tscn")
		await process_frame; await process_frame
		check("Music: %s plays its own track" % entry[1], current_scene.stage.music == entry[1] and audio._music_name == entry[1])
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl

	# Every fighter has special, super and K.O. shouts.
	var missing := []
	for c in gs.roster:
		for kind in ["special", "super", "ko"]:
			audio.shout(c.id, kind, -80.0)
			if (audio._shouts["%s_%s" % [c.id, kind]] as Array).is_empty():
				missing.append("%s_%s" % [c.id, kind])
	check("Shouts: every fighter has special / super / K.O. takes", missing.is_empty(), str(missing))

	# Walk forward, release, then 623: the 6 starts a dash that turns into the special.
	reset(DummyController.Mode.STAND); approach(1.0)
	motion("623", InputBuffer.HP)
	check("Dragon punch comes out straight from a walk (dash cancel)", p1.current_move != null and p1.current_move.name == "Rising Dragon",
		p1.current_move.name if p1.current_move else state_name(p1))
	step(120)

	# Impact effects fire on the special's first active frame.
	var fx = m.fx # untyped: naming FightFx here would compile it before the Audio autoload exists
	reset(DummyController.Mode.STAND)
	p1.position.x = -2.5; p2.position.x = 2.5
	var before: int = fx.spawned
	motion("236", InputBuffer.HP)
	step(14)
	check("FX: projectile launch flash", fx.spawned > before)
	before = fx.spawned
	wait_until(func() -> bool: return p1.projectile == null, 120)
	check("FX: projectile impact burst + ring", fx.spawned >= before + 2, "%d effects" % (fx.spawned - before))
	gs.stage_path = gs.DEFAULT_STAGE


## The reacting crowd (StageAmbience on a stage with an audience): what it reacts to,
## the excitement level and the cheering layer that follows it, cooldowns and priority.
func _crowd_tests(sound: StageAmbience) -> void:
	var counts := {}
	for kind: StringName in sound.SHOUTS:
		counts[kind] = (sound._shouts[kind] as Array).size()
	check("Crowd: reaction takes load (ooh, gasp, wow, roar) and the cheering layer plays",
		counts == {&"ooh": 8, &"gasp": 4, &"wow": 2, &"roar": 5} and sound._swell != null and sound._swell.playing, str(counts))
	var calm := func() -> void: # the crowd settles completely, cooldowns over
		sound.excitement = 0.0; sound._hold = 0.0; sound._swell_level = 0.0; sound._last_shout_time = -100.0
	var kind_of := func() -> String: return str(sound._last_clip.resource_path).get_file().split("_")[1]
	var jab: MoveData = p1._move_for_input("LP")
	var launcher: MoveData = p1._move_for_input("2HP")
	calm.call()
	sound._on_hit(p1, p2, jab, Fighter.HitResult.BLOCKED)
	check("Crowd: a blocked jab barely stirs it and stays quiet", sound.excitement < 0.05 and sound._last_shout_time < 0.0)
	calm.call()
	p2.combo_hits = 1
	sound._on_hit(p1, p2, launcher, Fighter.HitResult.HIT)
	check("Crowd: a launcher gets an \"ooh\"", kind_of.call() == "ooh" and sound.excitement > 0.15, "%s %.2f" % [kind_of.call(), sound.excitement])
	calm.call()
	sound._on_hit(p1, p2, jab, Fighter.HitResult.COUNTER)
	check("Crowd: a counter hit gets a gasp", kind_of.call() == "gasp")
	var before: float = sound._last_shout_time
	sound._on_hit(p1, p2, launcher, Fighter.HitResult.HIT)
	check("Crowd: another reaction waits out the cooldown", sound._last_shout_time == before)
	p2.combo_hits = 5
	sound._on_hit(p1, p2, jab, Fighter.HitResult.HIT)
	check("Crowd: a 5-hit combo gets a \"wow\" (it outranks the cooldown)", kind_of.call() == "wow")
	calm.call()
	p2.combo_hits = 2
	var finisher := MoveData.new()
	finisher.input = "~test_finish"; finisher.damage = 60
	sound._on_hit(p1, p2, finisher, Fighter.HitResult.HIT)
	check("Crowd: a super's finisher gets a \"wow\"", kind_of.call() == "wow" and sound.excitement > 0.4)
	p2.combo_hits = 0
	# Excitement builds through a combo, the cheering layer swells with it, then both settle.
	calm.call()
	for hit in range(1, 7):
		p2.combo_hits = hit
		sound._on_hit(p1, p2, jab, Fighter.HitResult.HIT)
		for i in 20: sound._process(1.0 / 60.0)
	var peak: float = sound.excitement
	var loud: float = sound._swell.volume_db
	for i in 600: sound._process(1.0 / 60.0)
	check("Crowd: a combo builds excitement and the cheering swells", peak > 0.6 and loud > sound.reaction_volume - 12.0, "%.2f, %.1f dB" % [peak, loud])
	check("Crowd: it settles after the action stops", sound.excitement < 0.1 and sound._swell.volume_db < loud - 15.0, "%.2f, %.1f dB" % [sound.excitement, sound._swell.volume_db])
	p2.combo_hits = 0
	calm.call()


## The train roof: a narrow stage (sideways limit), a world that streams past, and a train
## passing the other way.
func train_tests() -> void:
	var gs = root.get_node("GameState")
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2]
	gs.stage_path = gs.TRAIN_STAGE
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	reset(DummyController.Mode.STAND); approach(1.1)
	var hp := p2.health
	press(InputBuffer.LP); step(6)
	check("Train: loads and combat works", m.stage.name == "Train" and p2.health == hp - dmg(p1, "LP"), "hp %d -> %d" % [hp, p2.health])
	check("Train: in the stage list as the Express, with its own music", gs.stage_name(gs.TRAIN_STAGE) == "Express" and m.stage.music == &"train")
	check("Train: the roof is narrow (sideways limit 1.1 m), the length is standard", is_equal_approx(m.stage.depth_limit(), 1.1)
		and m.stage.bounds_half_extent == 3.6 and is_equal_approx(p1.bounds_depth, 1.1) and is_equal_approx(p2.bounds_depth, 1.1))
	var widest := 0.0
	for i in 6: # sidestep into the screen, then toward the camera, again and again
		press(InputBuffer.SIDESTEP, 5 if i < 3 else 2); step(30)
		widest = maxf(widest, maxf(absf(p1.position.z), absf(p2.position.z)))
	check("Train: sidesteps never leave the roof", widest <= 1.1001, "widest %.3f m" % widest)
	var square = load("res://scripts/stages/stage.gd").new() # not the class name: stage.gd uses an autoload, which -s scripts compile before
	check("Train: square stages keep one limit for both directions", square.depth_limit() == square.bounds_half_extent)
	square.free()
	var shot := Projectile.new()
	shot.ticks_left = 10
	shot.position = Vector3(0, 1, 1.5)
	var inside: bool = shot.tick(3.6, 1.1)
	shot.position = Vector3(0, 1, 1.7)
	var off_side: bool = shot.tick(3.6, 1.1)
	var square_stage: bool = shot.tick(3.6)
	shot.free()
	check("Train: projectiles expire past the roof's sides (only on narrow stages)", inside and not off_side and square_stage)

	var motion := m.stage.get_node_or_null("Motion") as TrainMotion
	check("Train: the moving-world driver is there", motion != null)
	if motion == null:
		return
	var trees := 0
	var poles := 0
	for child in motion.get_children():
		if child is MultiMeshInstance3D:
			if String(child.name).begins_with("Trees"): trees += (child as MultiMeshInstance3D).multimesh.instance_count
			elif child.name == "Poles": poles = (child as MultiMeshInstance3D).multimesh.instance_count
	check("Train: trees and telegraph poles are laid out at runtime", trees == motion.tree_count and poles == int(TrainMotion.SCENERY_PERIOD / motion.pole_spacing),
		"%d trees, %d poles" % [trees, poles])
	var before := motion.travelled
	for i in 30: motion._process(1.0 / 60.0)
	var moved := fposmod(motion.travelled - before, TrainMotion.WRAP)
	var synced := motion.materials.size() >= 4 and motion.materials.all(func(mat: ShaderMaterial) -> bool: return is_equal_approx(mat.get_shader_parameter("scroll"), motion.travelled))
	check("Train: the world streams past at the train's speed, every scenery material in step", is_equal_approx(moved, motion.speed * 0.5) and synced,
		"%.2f m in 0.5 s, %d materials" % [moved, motion.materials.size()])
	var seamless := true
	for period in [TrainMotion.SCENERY_PERIOD, 2400.0, 240.0, 60.0, 12.0, 2.4, 0.6]: # loops and tilings in the shaders
		if absf(TrainMotion.WRAP / period - roundf(TrainMotion.WRAP / period)) > 0.0001:
			seamless = false
	check("Train: every loop and tiling divides the scroll wrap (no jump when it wraps)", seamless)
	motion._next_pass = motion._time
	motion._process(1.0 / 60.0)
	var appeared := motion.passing_train.visible and motion.passing_sound.playing
	var frames := 0
	while motion.passing_train.visible and frames < 1200:
		motion._process(1.0 / 60.0)
		frames += 1
	check("Train: a train passes the other way (with its sound), then is gone", appeared and not motion.passing_train.visible and frames > 60,
		"%.1f s on the move" % (frames / 60.0))
	var sound := m.stage.get_node_or_null("Sound") as StageAmbience
	check("Train: rumble, clatter and wind on the Ambience bus, no crowd", sound != null and sound._loop_players.size() == 3
		and sound._loop_players.all(func(pl: AudioStreamPlayer) -> bool: return pl.bus == &"Ambience") and sound.reaction == null)
	gs.stage_path = gs.DEFAULT_STAGE


## The graphics preset: what each level turns off on a stage and the viewport, that a
## stage loaded afterwards at High gets its effects back (the environment is shared with
## the cached scene), and that the setting is saved.
func graphics_tests() -> void:
	var gs = root.get_node("GameState")
	var settings = root.get_node("Settings")
	var settings_file: String = settings.PATH
	var had_settings := FileAccess.file_exists(settings_file)
	var settings_bytes := FileAccess.get_file_as_bytes(settings_file) if had_settings else PackedByteArray()
	var saved_video := [settings.display_mode, settings.window_size, settings.resolution]
	var probe := func(path: String, level: int) -> Dictionary:
		settings.graphics = level
		var stage: Node = (load(path) as PackedScene).instantiate()
		root.add_child(stage) # Stage._ready applies the preset
		var env: Environment = (stage.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
		var info := {fog = env.volumetric_fog_enabled, glow = env.glow_enabled, shadows = 0, particles = 0, ratio = 1.0, probes = 0}
		for l in stage.find_children("*", "Light3D", true, false):
			if (l as Light3D).shadow_enabled: info.shadows += 1
		for p in stage.find_children("*", "GPUParticles3D", true, false):
			if (p as GPUParticles3D).visible: info.particles += 1
			info.ratio = minf(info.ratio, (p as GPUParticles3D).amount_ratio)
		for p in stage.find_children("*", "ReflectionProbe", true, false):
			if (p as ReflectionProbe).visible: info.probes += 1
		stage.free()
		return info
	var high: Dictionary = probe.call(gs.DEFAULT_STAGE, settings.Graphics.HIGH)
	check("Graphics High: ring keeps fog, glow, both shadowed lights and its particles",
		high.fog and high.glow and high.shadows == 2 and high.particles >= 2 and high.ratio == 1.0, str(high))
	var low: Dictionary = probe.call(gs.DEFAULT_STAGE, settings.Graphics.LOW)
	check("Graphics Low: ring drops fog, glow, particles and the extra shadow (key light keeps its own)",
		not low.fog and not low.glow and low.shadows == 1 and low.particles == 0, str(low))
	var medium: Dictionary = probe.call(gs.DEFAULT_STAGE, settings.Graphics.MEDIUM)
	check("Graphics Medium: ring keeps fog and glow, one shadow, half the particles",
		medium.fog and medium.glow and medium.shadows == 1 and medium.particles >= 2 and medium.ratio == 0.5, str(medium))
	var again: Dictionary = probe.call(gs.DEFAULT_STAGE, settings.Graphics.HIGH)
	check("Graphics: High after Low gets the shared environment back untouched", again == high, str(again))
	var roof_low: Dictionary = probe.call(gs.ROOFTOP_STAGE, settings.Graphics.LOW)
	var roof_high: Dictionary = probe.call(gs.ROOFTOP_STAGE, settings.Graphics.HIGH)
	check("Graphics Low: rooftop hides its reflection probe (High keeps it)", roof_low.probes == 0 and roof_high.probes == 1,
		"%d / %d" % [roof_low.probes, roof_high.probes])

	settings.graphics = settings.Graphics.LOW
	settings.apply_graphics(root)
	check("Graphics Low: 75% render scale, FXAA instead of MSAA",
		root.msaa_3d == Viewport.MSAA_DISABLED and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA
		and is_equal_approx(root.scaling_3d_scale, 0.75))
	settings.graphics = settings.Graphics.MEDIUM
	settings.apply_graphics(root)
	check("Graphics Medium: 85% render scale, 2× MSAA", root.msaa_3d == Viewport.MSAA_2X and is_equal_approx(root.scaling_3d_scale, 0.85))
	settings.graphics = settings.Graphics.LOW
	settings.save_settings()
	settings.graphics = settings.Graphics.HIGH
	settings.load_settings()
	check("Graphics: the setting is saved and loaded", settings.graphics == settings.Graphics.LOW)
	settings.graphics = settings.Graphics.HIGH
	settings.apply_graphics(root)
	check("Graphics High: 4× MSAA at full resolution (the project default)",
		root.msaa_3d == Viewport.MSAA_4X and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and root.scaling_3d_scale == 1.0)

	# Resolution caps the 3D render height; the preset scales on top; Native never caps.
	settings.resolution = 2 # 1080p
	check("Resolution: 1080p on a 3024×1898 screen draws 1080 lines", is_equal_approx(settings.render_scale(1898), 1080.0 / 1898.0))
	check("Resolution: a window smaller than the cap renders at its own size", settings.render_scale(720) == 1.0)
	settings.graphics = settings.Graphics.LOW
	check("Resolution: Low scales on top of the cap (75% of 1080p)", is_equal_approx(settings.render_scale(1898), 0.75 * 1080.0 / 1898.0))
	settings.resolution = settings.RESOLUTIONS.size() - 1
	settings.graphics = settings.Graphics.HIGH
	check("Resolution: Native at High is full resolution", settings.render_scale(1898) == 1.0)

	# Display settings are saved; an old file with only "fullscreen" becomes borderless.
	settings.display_mode = settings.DisplayMode.EXCLUSIVE
	settings.window_size = 1
	settings.resolution = 0
	settings.save_settings()
	settings.display_mode = settings.DisplayMode.WINDOWED
	settings.window_size = 0
	settings.resolution = 2
	settings.load_settings()
	check("Display: mode, window size and resolution are saved",
		settings.display_mode == settings.DisplayMode.EXCLUSIVE and settings.window_size == 1 and settings.resolution == 0)
	var legacy := ConfigFile.new()
	legacy.set_value("video", "fullscreen", true)
	legacy.save(settings_file)
	settings.display_mode = settings.DisplayMode.WINDOWED
	settings.load_settings()
	check("Display: an old fullscreen setting loads as borderless fullscreen", settings.display_mode == settings.DisplayMode.BORDERLESS)
	check("Display: the window size always fits the screen", settings.fitting_window_size(3) in settings.WINDOW_SIZES)

	if had_settings:
		var f := FileAccess.open(settings_file, FileAccess.WRITE)
		f.store_buffer(settings_bytes)
		f.close()
		settings.load_settings()
	else:
		DirAccess.remove_absolute(settings_file)
	settings.display_mode = saved_video[0] # an old-format file has no keys to reload these from
	settings.window_size = saved_video[1]
	settings.resolution = saved_video[2]
	settings.graphics = settings.Graphics.HIGH
	settings.apply_graphics(root)


## Average distance (and fireball count) the CPU keeps from a standing P1 over 30 s.
func _cpu_spacing(gs, cpu_index: int) -> Dictionary:
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[cpu_index]
	gs.stage_path = gs.DEFAULT_STAGE
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	var a: Fighter = m.fighters[0]
	var b: Fighter = m.fighters[1]
	a.controller = m.dummy
	m.dummy.mode = DummyController.Mode.STAND
	var cpu := AIController.new(AIController.Difficulty.HARD, 3)
	cpu.attach(b)
	b.controller = cpu
	m.start_fight_immediately()
	for f in m.fighters: f.immortal = true
	var result := {dist = 0.0, fireballs = 0, name = cpu.personality_name()}
	b.attack_started.connect(func(mv: MoveData) -> void:
		if mv.projectile_speed > 0.0: result.fireballs += 1)
	for i in 1800:
		m._physics_process(1.0 / 60.0)
		result.dist += Vector2(b.position.x - a.position.x, b.position.z - a.position.z).length() / 1800.0
	return result


func personality_tests() -> void:
	var gs = root.get_node("GameState")
	var kenji: Dictionary = await _cpu_spacing(gs, 0)
	var rhea: Dictionary = await _cpu_spacing(gs, 1)
	var brutus: Dictionary = await _cpu_spacing(gs, 2)
	check("CPU personalities: Zoner / Rushdown / Punisher", kenji.name == "Zoner" and rhea.name == "Rushdown" and brutus.name == "Punisher")
	check("CPU spacing: Kenji zones far, Brutus mid, Rhea up close", kenji.dist > brutus.dist + 0.4 and brutus.dist > rhea.dist + 0.15,
		"%.2f / %.2f / %.2f" % [kenji.dist, brutus.dist, rhea.dist])
	check("CPU: Kenji zones with fireballs", kenji.fireballs >= 8, "%d fireballs" % kenji.fireballs)

	# The accidental-dash filter: walk 6, neutral, 6 holds neutral instead of dashing;
	# planned dashes pass; a block that would backdash becomes a crouch block.
	var cpu := AIController.new()
	var outputs := []
	for d in [6, 5, 6]:
		outputs.append(cpu._without_accidental_dash(InputBuffer.pack(d, 0)) & 0xF)
	cpu._dashing = true
	outputs.append(cpu._without_accidental_dash(InputBuffer.pack(5, 0)) & 0xF)
	outputs.append(cpu._without_accidental_dash(InputBuffer.pack(6, 0)) & 0xF)
	cpu._dashing = false
	cpu._recent_dirs.clear()
	cpu._blocking = true
	cpu._block_level = MoveData.HitLevel.HIGH
	for d in [4, 5, 4]:
		outputs.append(cpu._without_accidental_dash(InputBuffer.pack(d, 0)) & 0xF)
	check("CPU: no accidental dashes (walk -> neutral, block -> crouch block)", outputs == [6, 5, 5, 5, 6, 4, 5, 1], str(outputs))

	# Brutus punishes a whiffed roundhouse from long range with Bull Charge.
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2]
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	var brute := AIController.new(AIController.Difficulty.HARD, 5)
	brute.attach(p2)
	p2.controller = brute
	var charges := [0]
	p2.attack_started.connect(func(mv: MoveData) -> void:
		if mv.name == "Bull Charge": charges[0] += 1)
	for attempt in 6:
		m.start_match(); m.start_fight_immediately()
		p1.position.x = -1.3; p2.position.x = 1.3 # 2.6 m: out of normal reach
		for f in m.fighters: f.reset_physics_interpolation()
		brute.reset()
		step(20)
		p1.position.x = p2.position.x - 2.6
		press(InputBuffer.HK) # whiffs
		step(70)
	check("CPU: Brutus whiff-punishes from range with Bull Charge", charges[0] >= 2, "%d charges in 6 whiffs" % charges[0])


func showcase_tests() -> void:
	var gs = root.get_node("GameState")
	gs.mode = gs.Mode.VS_CPU
	change_scene_to_file("res://scenes/character_select.tscn")
	await process_frame; await process_frame
	var cs = current_scene
	var progressed := []
	for i in gs.roster.size():
		(cs.get_node("%Roster").get_child(i) as Button).grab_focus()
		await process_frame
		var show: FighterShowcase = cs._showcase
		var steps_seen := {}
		for f in 420: # 7 s of routine
			show.process(1.0 / 60.0)
			steps_seen[show._index] = true
		progressed.append(steps_seen.size() >= 4 and show.data == gs.roster[i])
	check("Character select: each fighter performs a personality routine", not progressed.has(false), str(progressed))


func loading_tests() -> void:
	var gs = root.get_node("GameState")
	# The title screen preloads every fighter's textures and keeps them, then opens the menu.
	check("Title: the game starts on the title screen", ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/title.tscn")
	var listed := true
	var model := FighterModel.new()
	root.add_child(model)
	model.build(gs.roster[0])
	for outfit: MeshInstance3D in model.skeleton.find_children("Outfit", "MeshInstance3D", true, false):
		for surface in outfit.mesh.get_surface_count():
			var cloth := outfit.get_surface_override_material(surface) as StandardMaterial3D
			for texture in [cloth.normal_texture, cloth.roughness_texture, cloth.albedo_texture]:
				if texture and not texture.resource_path in FighterModel.texture_paths(gs.roster[0]):
					listed = false
	model.free()
	check("Title: FighterModel.texture_paths lists every texture a build loads by path", listed)
	change_scene_to_file("res://scenes/title.tscn")
	var title_frames := 0
	while (current_scene == null or current_scene.scene_file_path != "res://scenes/main_menu.tscn") and title_frames < 2400:
		await process_frame
		title_frames += 1
	var held: Array = gs._fighter_textures
	check("Title: loads the fighters, then opens the main menu", current_scene != null and current_scene.scene_file_path == "res://scenes/main_menu.tscn",
		"%d frames" % title_frames)
	check("Title: every fighter texture is loaded and kept for the session", held.size() > 0 and held.size() == gs._fighter_texture_paths.size()
		and held.all(func(t) -> bool: return t is Texture2D) and Array(gs._fighter_texture_paths).all(func(p: String) -> bool: return ResourceLoader.has_cached(p)),
		"%d of %d" % [held.size(), gs._fighter_texture_paths.size()])
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = gs.roster[1]; gs.p2_character = gs.roster[2]
	gs.stage_path = gs.ROOFTOP_STAGE
	gs.go_to_fight(self)
	await process_frame; await process_frame
	check("Loading screen: shown on the way to a fight", current_scene.scene_file_path == "res://scenes/loading_screen.tscn")
	var bar_moved := false
	var frames := 0
	while current_scene.scene_file_path != "res://scenes/fight.tscn" and frames < 1200:
		if current_scene.get("_bar") and current_scene._bar.value > 0.0:
			bar_moved = true
		await process_frame
		frames += 1
	check("Loading screen: progress bar fills, then the fight starts on the chosen stage",
		bar_moved and current_scene.scene_file_path == "res://scenes/fight.tscn" and current_scene.stage.name == "Rooftop", "%d frames" % frames)
	gs.stage_path = gs.DEFAULT_STAGE


class Masher extends FighterController:
	## Once grabbed, mashes the throw-tech input (fresh LP+LK presses every other tick).
	var tick := 0
	func read(f: Fighter) -> int:
		tick += 1
		var mash := f.state == Fighter.State.THROWN and tick % 2 == 0
		return InputBuffer.pack(5, InputBuffer.LP | InputBuffer.LK if mash else 0)


func valka_tests() -> void:
	var gs = root.get_node("GameState")
	var valka: CharacterData = gs.roster.filter(func(c): return c.id == &"valka").front()
	check("Valka: in the roster as the fourth fighter", valka != null and gs.roster[3] == valka)
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = valka; gs.p2_character = gs.roster[0]
	gs.stage_path = gs.DEFAULT_STAGE
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	var cpu := AIController.new()
	cpu.attach(p1)
	check("Valka: Grappler CPU personality", cpu.personality_name() == "Grappler")

	# Command grab: unblockable.
	reset(DummyController.Mode.STAND_BLOCK); p1.position.x = -0.4; p2.position.x = 0.4
	var hp := p2.health
	motion("63214", InputBuffer.HP)
	wait_until(func() -> bool: return p2.state == Fighter.State.THROWN, 12)
	check("Valka Slam grabs a blocking opponent", p2.state == Fighter.State.THROWN and p1.state == Fighter.State.THROW, "%s / %s" % [state_name(p1), state_name(p2)])
	wait_until(func() -> bool: return p2.state == Fighter.State.AIR_HIT, 60)
	check("Valka Slam deals its damage and slams", p2.health == hp - dmg(p1, "63214P") and p2.state == Fighter.State.AIR_HIT, "hp %d -> %d" % [hp, p2.health])
	step(150)

	# ...and can't be teched.
	reset(DummyController.Mode.STAND); p1.position.x = -0.4; p2.position.x = 0.4
	p2.controller = Masher.new()
	hp = p2.health
	motion("63214", InputBuffer.HP)
	step(50)
	check("Valka Slam can't be teched", p2.health == hp - dmg(p1, "63214P") and p2.state != Fighter.State.TECH, "hp %d, %s" % [p2.health, state_name(p2)])
	step(150)
	# Control: the same masher does break a normal throw.
	reset(DummyController.Mode.STAND); p1.position.x = -0.4; p2.position.x = 0.4
	p2.controller = Masher.new()
	press(InputBuffer.LP | InputBuffer.LK)
	wait_until(func() -> bool: return p1.state == Fighter.State.TECH, 30)
	check("...while a normal throw still gets teched by the same input", p1.state == Fighter.State.TECH, state_name(p1))
	step(60)

	# A whiff is punishable.
	reset(DummyController.Mode.STAND); p1.position.x = -1.3; p2.position.x = 1.3
	motion("63214", InputBuffer.HP)
	step(12)
	check("Valka Slam whiff leaves her recovering", p1.state == Fighter.State.ATTACK and p2.state != Fighter.State.THROWN, state_name(p1))
	step(60)

	# Spinning Lariat goes straight through a fireball.
	reset(DummyController.Mode.STAND); p1.position.x = -1.5; p2.position.x = 1.5
	ctl2.dir = 5
	p2.controller = ctl2
	hp = p1.health
	for d in [2, 3, 6]:
		ctl2.dir = d
		if d == 6: ctl2.buttons = InputBuffer.HP
		step(1)
	ctl2.dir = 5
	wait_until(func() -> bool: return p2.projectile != null and p2.projectile.position.distance_to(p1.position + Vector3.UP) < 2.2, 60)
	motion("623", InputBuffer.HP)
	check("Spinning Lariat starts", p1.current_move != null and p1.current_move.name == "Spinning Lariat")
	wait_until(func() -> bool: return p2.projectile == null, 90)
	check("Spinning Lariat passes through the fireball", p1.health == hp, "hp %d -> %d" % [hp, p1.health])
	step(90)

	# Super command grab.
	reset(DummyController.Mode.STAND_BLOCK); p1.position.x = -0.5; p2.position.x = 0.5
	p1.add_meter(Fighter.MAX_METER)
	hp = p2.health
	motion("236236", InputBuffer.HP)
	step(m.SUPER_FREEZE_TICKS + 60)
	check("Thunder Valkyrie: super grab through a block", p2.health == hp - dmg(p1, "236236P") and p1.meter == 0, "hp %d -> %d" % [hp, p2.health])
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2]


func beach_tests() -> void:
	var gs = root.get_node("GameState")
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2]
	gs.stage_path = gs.BEACH_STAGE
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	reset(DummyController.Mode.STAND); approach(1.1)
	var hp := p2.health
	press(InputBuffer.LP); step(6)
	check("Beach: loads with the standard bounds and combat works", m.stage.name == "Beach" and m.stage.bounds_half_extent == 3.6
		and p2.health == hp - dmg(p1, "LP"), "hp %d -> %d" % [hp, p2.health])
	gs.stage_path = gs.DEFAULT_STAGE


## The night market: loads with the standard bounds, combat works, its grill light
## flickers and the neon is wired up.
func market_tests() -> void:
	var gs = root.get_node("GameState")
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = gs.roster[5]; gs.p2_character = gs.roster[0]
	gs.stage_path = gs.MARKET_STAGE
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	reset(DummyController.Mode.STAND); approach(1.1)
	var hp := p2.health
	press(InputBuffer.LP); step(6)
	check("Market: loads with the standard bounds and combat works", m.stage.name == "Market" and m.stage.bounds_half_extent == 3.6
		and p2.health == hp - dmg(p1, "LP"), "hp %d -> %d" % [hp, p2.health])
	var grill := m.stage.get_node_or_null("GrillFlicker") as FireFlicker
	var neon := m.stage.get_node_or_null("Ambience") as NeonAmbience
	check("Market: grill light flickers and the neon is wired", grill != null and grill._lights.size() == 2
		and neon != null and neon._labels.size() == 1 and neon._hums.size() == 1)
	check("Market: in the stage list as the Night Market", gs.stage_name(gs.MARKET_STAGE) == "Night Market")
	# Ambient sound: the loops play on the Ambience bus (its own volume), the crowd roars on
	# a K.O. (applause follows), and not while rollback re-simulates frames.
	var sound := m.stage.get_node_or_null("Sound") as StageAmbience
	check("Market: ambient loops play on the Ambience bus", sound != null and sound._loop_players.size() == 3
		and sound._loop_players.all(func(pl: AudioStreamPlayer) -> bool: return pl.playing and pl.bus == &"Ambience"))
	if sound:
		var shouting := func() -> bool: return sound._shout_players.any(func(pl: AudioStreamPlayer) -> bool: return pl.playing)
		sound.excitement = 0.0 # the jab above already stirred it
		m.resimulating = true
		p2.knocked_out.emit(p2)
		var quiet_in_rollback: bool = not shouting.call() and sound.excitement == 0.0
		m.resimulating = false
		p2.knocked_out.emit(p2)
		check("Market: the crowd roars on a K.O., but not during rollback", quiet_in_rollback and shouting.call()
			and str(sound._last_clip.resource_path).contains("roar") and sound.excitement == 1.0)
		for i in 90: sound._process(1.0 / 60.0)
		check("Market: applause follows the roar", sound._reaction_player.playing)
		_crowd_tests(sound)
	var jeeps := [m.stage.get_node_or_null("Jeepney0"), m.stage.get_node_or_null("Jeepney1")]
	var painted := jeeps.all(func(j) -> bool:
		if not j is MeshInstance3D or (j as MeshInstance3D).mesh.resource_path != "res://assets/stages/market/jeepney.res":
			return false
		for i in (j as MeshInstance3D).mesh.get_surface_count():
			if (j as MeshInstance3D).get_surface_override_material(i) == null:
				return false
		return true)
	check("Market: two modelled jeepneys, every surface painted", painted)
	check("Market: the jeepneys are painted differently", painted
		and (jeeps[0] as MeshInstance3D).get_surface_override_material(1) != (jeeps[1] as MeshInstance3D).get_surface_override_material(1))
	gs.stage_path = gs.DEFAULT_STAGE
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2]


func temple_tests() -> void:
	var gs = root.get_node("GameState")
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2]
	gs.stage_path = gs.TEMPLE_STAGE
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	reset(DummyController.Mode.STAND); approach(1.1)
	var hp := p2.health
	press(InputBuffer.LP); step(6)
	check("Temple: loads with the standard bounds and combat works", m.stage.name == "Temple" and m.stage.bounds_half_extent == 3.6
		and p2.health == hp - dmg(p1, "LP"), "hp %d -> %d" % [hp, p2.health])
	gs.stage_path = gs.DEFAULT_STAGE


func scores_credits_tests() -> void:
	var gs = root.get_node("GameState")
	var real_path: String = ArcadeRun.save_path
	ArcadeRun.save_path = "user://arcade_test.cfg" # never touch the player's real records
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ArcadeRun.save_path))
	var run := ArcadeRun.create(gs.roster[0], gs.roster, 1, 4, gs.arcade_arenas(), gs.DOJO_STAGE)
	run.score = 123456; run.ticks = 60 * 125; run.continues = 2; run.perfects = 3; run.cleared = true
	check("Best scores: a record is saved", run.record_best())
	var best := ArcadeRun.best_run(gs.roster[0])
	check("Best scores: saved with its details", best.score == 123456 and best.ticks == 7500 and best.continues == 2
		and best.perfects == 3 and best.cleared and best.stages == gs.roster.size(), str(best))
	run.score = 1000
	check("Best scores: a lower score doesn't replace it", not run.record_best() and ArcadeRun.best_score(gs.roster[0]) == 123456)
	var old := ConfigFile.new() # a record saved before details were kept
	old.load(ArcadeRun.save_path)
	old.set_value("best", String(gs.roster[1].id), 77777)
	old.save(ArcadeRun.save_path)
	var legacy := ArcadeRun.best_run(gs.roster[1])
	check("Best scores: old score-only records still load", legacy.score == 77777 and not legacy.has("ticks"), str(legacy))
	change_scene_to_file("res://scenes/best_scores.tscn")
	await process_frame; await process_frame
	check("Best scores screen: a row per fighter", current_scene._rows.size() == gs.roster.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ArcadeRun.save_path))
	ArcadeRun.save_path = real_path

	change_scene_to_file("res://scenes/credits.tscn")
	await process_frame; await process_frame
	var roll: CreditsRoll = current_scene._roll
	var y0 := roll.position.y
	for i in 30: await process_frame
	check("Credits screen: the roll scrolls and credits the creator", roll.rolling and roll.position.y < y0
		and CreditsRoll.CREDITS.any(func(e): return e[1] == "Clint Christopher Canada"))


func _has_key(action: String, key: int) -> bool:
	return InputMap.action_get_events(action).any(func(e): return e is InputEventKey and e.physical_keycode == key)


func _has_pad(action: String, button: int) -> bool:
	return InputMap.action_get_events(action).any(func(e): return e is InputEventJoypadButton and e.button_index == button)


func controls_tests() -> void:
	var setup = root.get_node("InputSetup")
	var settings = root.get_node("Settings")
	var saved: Dictionary = setup.bindings.duplicate(true)
	# The Controls screen saves settings; snapshot the player's file and put it back after.
	var settings_file: String = settings.PATH
	var had_settings := FileAccess.file_exists(settings_file)
	var settings_bytes := FileAccess.get_file_as_bytes(settings_file) if had_settings else PackedByteArray()
	setup.reset_player("p1")
	check("Controls: defaults (P1 LP = U / X)", _has_key("p1_lp", KEY_U) and _has_pad("p1_lp", JOY_BUTTON_X))

	setup.set_binding("p1", "lp", "key", KEY_O)
	check("Controls: rebinding a key updates the action", _has_key("p1_lp", KEY_O) and not _has_key("p1_lp", KEY_U))
	setup.set_binding("p1", "lp", "key", KEY_K) # K is Heavy Kick's: they swap
	check("Controls: a taken key swaps with its action", _has_key("p1_lp", KEY_K) and _has_key("p1_hk", KEY_O),
		"lp %s hk %s" % [setup.key_name(setup.bindings.p1.lp.key), setup.key_name(setup.bindings.p1.hk.key)])
	setup.set_binding("p1", "sidestep", "pad", setup.PAD_TRIGGER_RIGHT)
	var trigger: bool = InputMap.action_get_events("p1_sidestep").any(func(e): return e is InputEventJoypadMotion and e.axis == JOY_AXIS_TRIGGER_RIGHT)
	check("Controls: a trigger can be bound", trigger)

	# Saved and loaded with the settings file.
	var cfg := ConfigFile.new()
	setup.save_bindings(cfg)
	setup.reset_player("p1")
	setup.load_bindings(cfg)
	setup.apply(false)
	check("Controls: bindings survive save / load", _has_key("p1_lp", KEY_K) and setup.bindings.p1.sidestep.pad == setup.PAD_TRIGGER_RIGHT)

	# The screen: capturing a new gamepad button through the UI.
	change_scene_to_file("res://scenes/controls.tscn")
	await process_frame; await process_frame
	var screen = current_scene
	var button: Button
	for b in screen._list.get_children():
		if b is Button and b.get_meta(&"action", "") == "hp" and b.get_meta(&"kind", "") == "pad":
			button = b
	screen._start_capture("hp", "pad", button)
	screen.finish_capture(JOY_BUTTON_LEFT_SHOULDER)
	check("Controls screen: capture binds the button and the controller shows it", _has_pad("p1_hp", JOY_BUTTON_LEFT_SHOULDER)
		and screen._controller.player == "p1" and screen._list.get_child_count() > 9)

	# Restore the player's real bindings and settings file exactly.
	setup.bindings = saved
	setup.apply(false)
	if had_settings:
		var f := FileAccess.open(settings_file, FileAccess.WRITE)
		f.store_buffer(settings_bytes)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_file))


func jin_tests() -> void:
	var gs = root.get_node("GameState")
	var jin: CharacterData = gs.roster.filter(func(c): return c.id == &"jin").front()
	check("Jin: in the roster as the fifth fighter", jin != null and gs.roster.size() >= 5 and gs.roster[4] == jin)
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = jin; gs.p2_character = gs.roster[0]
	gs.stage_path = gs.DEFAULT_STAGE
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	var cpu := AIController.new()
	cpu.attach(p1)
	check("Jin: Footsies CPU personality", cpu.personality_name() == "Footsies")

	# Long legs: his normals out-reach the same move on Kenji.
	var kenji: CharacterData = gs.roster[0]
	var kenji_hk: MoveData = kenji.moves.filter(func(mv): return mv.input == "HK").front()
	check("Jin: kicks reach further than Kenji's", absf(p1._move_for_input("HK").hitbox_offset.z) > absf(kenji_hk.hitbox_offset.z) + 0.05)

	# Axe kick is an overhead: crouch-blocking doesn't stop it.
	reset(DummyController.Mode.CROUCH_BLOCK); step(20); approach(1.3)
	step(16) # forward again right after walking would be a dash
	var hp := p2.health
	press(InputBuffer.HK, 6); step(30)
	check("Jin: Axe Kick hits through a crouch block (overhead)", p2.health == hp - dmg(p1, "6HK"), "hp %d -> %d" % [hp, p2.health])
	step(60)

	# Spinning back kick travels in from range.
	reset(DummyController.Mode.STAND); p1.position.x = -1.1; p2.position.x = 1.1
	hp = p2.health
	motion("236", InputBuffer.HK)
	wait_until(func() -> bool: return p2.health < hp, 40)
	check("Jin: Spinning Back Kick steps in from 2.2 m", p2.health == hp - dmg(p1, "236K"), "hp %d -> %d" % [hp, p2.health])
	step(80)

	# Tornado kick: invincible start, rises, launches.
	reset(DummyController.Mode.STAND); approach(1.0); step(16)
	motion("623", InputBuffer.HK)
	check("Jin: Tornado Kick starts invincible", p1.current_move != null and p1.current_move.name == "Tornado Kick" and p1.is_invulnerable())
	wait_until(func() -> bool: return p2.state == Fighter.State.AIR_HIT, 30)
	check("Jin: Tornado Kick launches", p2.state == Fighter.State.AIR_HIT, state_name(p2))
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2]


## Mira (Brawler): Lakas Stance builds Focus (no hitbox, capped at 3), Focus powers
## Bagyo Rush and picks the super's finisher, knockdowns take it away, it survives a
## rollback snapshot, the dive kick changes the jump arc, and the detailed textures
## (hers first, now every fighter's).
## Lian, the counter fighter: the reversal stance catches high, mid and overhead strikes
## and throws the attacker; lows, throws and projectiles beat it; a miss is punishable;
## Willow Step glides through fireballs; the CPU uses the stance only on purpose and
## never strikes into one.
func lian_tests() -> void:
	var gs = root.get_node("GameState")
	var lian: CharacterData = gs.roster.filter(func(c): return c.id == &"lian").front()
	check("Lian: in the roster as the seventh fighter", lian != null and gs.roster.size() >= 7 and gs.roster[6] == lian)
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = lian; gs.p2_character = gs.roster[0]
	gs.stage_path = gs.DEFAULT_STAGE
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	var cpu := AIController.new()
	cpu.attach(p1)
	check("Lian: Counter CPU personality", cpu.personality_name() == "Counter")
	check("Lian: the CPU never picks a stance as an attack",
		cpu._special_with(func(mv: MoveData) -> bool: return mv.motion() == "214") == null and cpu._reversal_move() != null)

	# p2 (Kenji) is scripted for these: `p2_move` presses its button on the tick Lian's
	# stance starts.
	var stance_vs := func(button: int, d: int, distance: float) -> Dictionary:
		reset(DummyController.Mode.STAND)
		p2.controller = ctl2
		approach(distance); step(10)
		var hp1 := p1.health
		var hp2 := p2.health
		ctl.dir = 2; step(1); ctl.dir = 1; step(1)
		ctl.dir = 4; ctl.buttons = InputBuffer.LP; ctl2.dir = d; ctl2.buttons = button; step(1)
		ctl.dir = 5; ctl2.dir = 5
		var caught := false
		var lian_thrown := false
		for t in 50:
			step()
			caught = caught or (p1.state == Fighter.State.THROW and p2.state == Fighter.State.THROWN)
			lian_thrown = lian_thrown or p1.state == Fighter.State.THROWN
		step(60)
		return {caught = caught, lian_thrown = lian_thrown, lian_lost = hp1 - p1.health, kenji_lost = hp2 - p2.health}
	var high: Dictionary = stance_vs.call(InputBuffer.HP, 5, 1.0)
	check("Lian: Still Water catches a straight and throws for its damage",
		high.caught and high.lian_lost == 0 and high.kenji_lost == dmg(p1, "214P"), "%s" % high)
	var low: Dictionary = stance_vs.call(InputBuffer.LK, 2, 1.0)
	check("Lian: a low kick goes under the stance", not low.caught and low.lian_lost > 0, "%s" % low)
	var thrown: Dictionary = stance_vs.call(InputBuffer.LP | InputBuffer.LK, 5, 0.7)
	check("Lian: a throw beats the stance", not thrown.caught and thrown.lian_thrown and thrown.lian_lost > 0, "%s" % thrown)
	var still_water := p1._move_for_input("214P")
	check("Lian: the stance catches overheads, not lows",
		still_water.reversal and _reverses_at(p1, still_water, p2._move_for_input("j.HK"))
		and not _reverses_at(p1, still_water, p2._move_for_input("2LK")))

	# A stance that catches nothing leaves her open.
	reset(DummyController.Mode.STAND); step(4)
	motion("214", InputBuffer.LP)
	step(still_water.startup + still_water.active + 4)
	check("Lian: a missed stance plays out its recovery", p1.state == Fighter.State.ATTACK and not p1.is_actionable(), state_name(p1))

	# Fireballs: the stance doesn't catch them, Willow Step glides through.
	for glide in [false, true]:
		reset(DummyController.Mode.STAND)
		p2.controller = ctl2
		step(10)
		var hp := p1.health
		ctl2.dir = 2; step(1); ctl2.dir = 3; step(1); ctl2.dir = 6; ctl2.buttons = InputBuffer.LP; step(1); ctl2.dir = 5
		wait_until(func() -> bool: return p2.projectile != null 			and Vector2(p2.projectile.position.x - p1.position.x, p2.projectile.position.z - p1.position.z).length() < 1.4, 120)
		var start_gap := dist()
		motion("214", InputBuffer.LK if glide else InputBuffer.LP)
		var caught := false
		var moves := {}
		var hit_at := -1
		for t in 40:
			step()
			caught = caught or p1.state == Fighter.State.THROW
			if p1.current_move:
				moves[p1.current_move.name] = true
			if hit_at < 0 and p1.health < hp:
				hit_at = t
		var hit := p1.health < hp
		if glide:
			check("Lian: Willow Step glides through a fireball", not hit and dist() < start_gap,
				"hp %d -> %d at tick %d, moves %s" % [hp, p1.health, hit_at, moves.keys()])
		else:
			check("Lian: Still Water doesn't catch a fireball", hit and not caught, "hp %d -> %d" % [hp, p1.health])
		step(60)

	# Any CPU facing a reversal stance throws, goes low or waits, never strikes into it.
	var kenji_cpu := AIController.new()
	kenji_cpu.attach(p2)
	var striking := 0
	for t in 40:
		kenji_cpu._plan.clear()
		var seen := {state = Fighter.State.ATTACK, state_frame = 6, move = still_water, position = p1.position,
			velocity = Vector3.ZERO, crouching = false, start_tick = 0}
		kenji_cpu._decide(p2, seen, [0.7, 1.1, 2.0][t % 3])
		for planned: Array in kenji_cpu._plan:
			var buttons: int = planned[1]
			if buttons != 0 and buttons != (InputBuffer.LP | InputBuffer.LK) and not (buttons == InputBuffer.LK and planned[0] == 2):
				striking += 1
	check("Lian: CPUs don't strike into the reversal stance", striking == 0, "%d" % striking)
	p2.controller = m.dummy


## True if `fighter` in `stance` (on its first active frame) would catch `move`.
func _reverses_at(fighter: Fighter, stance: MoveData, move: MoveData) -> bool:
	var saved := fighter.save_state()
	fighter.current_move = stance
	fighter._set_state(Fighter.State.ATTACK)
	fighter.state_frame = stance.startup + 1
	var result := fighter.reverses(move)
	fighter.load_state(saved)
	return result


func mira_tests() -> void:
	var gs = root.get_node("GameState")
	var mira: CharacterData = gs.roster.filter(func(c): return c.id == &"mira").front()
	check("Mira: in the roster as the sixth fighter", mira != null and gs.roster.size() >= 6 and gs.roster[5] == mira)
	gs.mode = gs.Mode.VS_CPU
	gs.player_character = mira; gs.p2_character = gs.roster[0]
	gs.stage_path = gs.DEFAULT_STAGE
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame; await process_frame
	m = current_scene
	m.set_physics_process(false)
	p1 = m.fighters[0]; p2 = m.fighters[1]
	p1.controller = ctl
	var cpu := AIController.new()
	cpu.attach(p1)
	check("Mira: Brawler CPU personality", cpu.personality_name() == "Brawler")
	check("Mira: the CPU never picks Lakas Stance as an attack",
		cpu._special_with(func(mv: MoveData) -> bool: return mv.motion() == "214") == null and cpu._stance(p1) != null)

	# Lakas Stance: one level each, capped at 3, and it never hits.
	reset(DummyController.Mode.STAND); approach(0.9); step(16)
	var hp := p2.health
	for i in 4:
		motion("214", InputBuffer.LP)
		step(40)
	check("Mira: Lakas Stance raises Focus to 3 and no further", p1.focus == Fighter.MAX_FOCUS, "focus %d" % p1.focus)
	check("Mira: Lakas Stance has no hitbox", p2.health == hp, "hp %d -> %d" % [hp, p2.health])

	# Bagyo Rush: 3 hits at Focus 0; at Focus 3, 6 hits and much more damage.
	var rush := [[0, 0, 0], [0, 0, 0]] # [focus, hits, damage]
	for k in 2:
		reset(DummyController.Mode.STAND); approach(1.0); step(16)
		p1._set_focus(3 * k)
		hp = p2.health
		var most := 0
		motion("236", InputBuffer.LP)
		for t in 90:
			step()
			most = maxi(most, p2.combo_hits)
		rush[k] = [3 * k, most, hp - p2.health]
	check("Mira: Bagyo Rush hits 3 times, 6 at full Focus", rush[0][1] == 3 and rush[1][1] == 6, "%s" % [rush])
	check("Mira: full Focus more than doubles Bagyo Rush's damage", rush[1][2] > rush[0][2] * 2, "%s" % [rush])

	# A knockdown takes her Focus away.
	reset(DummyController.Mode.STAND); step(4)
	p1._set_focus(2)
	p1.receive_hit(p2, p2._move_for_input("2HK"))
	wait_until(func() -> bool: return p1.state == Fighter.State.KNOCKDOWN, 60)
	check("Mira: a knockdown resets Focus", p1.state == Fighter.State.KNOCKDOWN and p1.focus == 0, "%s, focus %d" % [state_name(p1), p1.focus])

	# Focus is simulation state: it comes back with a rollback snapshot.
	reset(DummyController.Mode.STAND); step(4)
	p1._set_focus(2)
	var snapshot: Dictionary = p1.save_state()
	p1._set_focus(0)
	p1.load_state(snapshot)
	check("Mira: Focus is part of the rollback snapshot", p1.focus == 2)

	# The super uses Focus up; at full Focus it ends in the stronger finisher.
	for full in [false, true]:
		reset(DummyController.Mode.STAND); approach(1.0); step(16)
		p1.add_meter(Fighter.MAX_METER)
		p1._set_focus(Fighter.MAX_FOCUS if full else 0)
		motion("236236", InputBuffer.LP)
		var used := p1.focus == 0
		var finisher := ""
		for t in 160:
			step()
			if p1.current_move and p1.current_move.input.begins_with("~"):
				finisher = p1.current_move.input
				break
		var expected := "~hagupit_max" if full else "~hagupit_finish"
		check("Mira: the super%s ends in %s" % [" at full Focus" if full else "", expected], used and finisher == expected,
			"focus used %s, finisher '%s'" % [used, finisher])
		step(120)

	# Lawin Drop: down + kick in the air dives down and forward.
	reset(DummyController.Mode.STAND); step(4)
	ctl.dir = 8; step(1); ctl.dir = 5; step(12)
	var height := p1.position.y
	press(InputBuffer.LK, 2); ctl.dir = 5
	var dove := false
	for t in 12:
		step()
		if p1.current_move and p1.current_move.input == "j.2K" and p1.velocity.y < -5.0 and p1.velocity.dot(p1.forward) > 3.0:
			dove = true
	check("Mira: Lawin Drop dives down and forward from a jump", height > 0.3 and dove, "height %.2f" % height)
	step(60)
	check("Mira: the move list shows the dive kick with an arrow", FightHud.notation("j.2K") == "j.↓ K", FightHud.notation("j.2K"))

	# Detailed textures: hem shading and stitch lines in the outfit, a second UV set for the
	# skin detail, and the materials that use them (other fighters keep the plain ones).
	var outfit := mira.outfit_mesh as ArrayMesh
	var darkest := 1.0
	var brightest := 0.0
	for surface in outfit.get_surface_count():
		var colors = outfit.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
		if colors == null:
			darkest = -1.0
			break
		for c: Color in colors:
			darkest = minf(darkest, c.r)
			brightest = maxf(brightest, c.r)
	check("Mira: the outfit has hem shading and stitch lines", mira.detailed_textures and darkest > 0.5 and darkest < 0.7 and brightest > 0.99,
		"%.2f .. %.2f" % [darkest, brightest])
	check("Mira: her body carries a second UV set", (mira.outfit_body_mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2] != null)
	var looks := {}
	for character: CharacterData in [mira, gs.roster[0]]:
		var model := FighterModel.new()
		root.add_child(model)
		model.build(character)
		var cloth := (model.skeleton.get_node("Outfit") as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		var skin: StandardMaterial3D
		for mi: MeshInstance3D in model.skeleton.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == character.outfit_body_mesh:
				skin = mi.get_surface_override_material(0)
		looks[character.id] = [cloth.albedo_texture != null and cloth.vertex_color_use_as_albedo,
			skin.detail_enabled and skin.detail_uv_layer == BaseMaterial3D.DETAIL_UV_2 and skin.detail_normal != null]
		model.queue_free()
	check("Mira: detailed cloth (weave, hem shading) and skin detail", looks[&"mira"] == [true, true], "%s" % [looks])
	check("Kenji gets the detailed materials too", looks[&"kenji"] == [true, true], "%s" % [looks])
	check("Every fighter has detailed textures", gs.roster.all(func(c: CharacterData) -> bool: return c.detailed_textures))

	# Realistic shading (every fighter): wrapped skin with a backlight (never screen-space
	# scattering: it costs a third of the frame rate), wet eyes with their own eye light,
	# anisotropic hair; off on the Low preset.
	var settings: Node = root.get_node("Settings")
	var kenji := gs.roster[0] as CharacterData
	check("Every fighter uses realistic shading", kenji.id == &"kenji" and gs.roster.all(func(c: CharacterData) -> bool: return c.realistic_shading))
	var shading := {}
	for run: Array in [[kenji, settings.Graphics.HIGH], [mira, settings.Graphics.HIGH], [kenji, settings.Graphics.LOW]]:
		settings.graphics = run[1]
		var model := FighterModel.new()
		root.add_child(model)
		model.build(run[0])
		var found := {"skin": false, "sss": false, "eyes": false, "hair": false, "eye_layer": false}
		for mi: MeshInstance3D in model.skeleton.find_children("*", "MeshInstance3D", true, false):
			for surface in mi.get_surface_override_material_count():
				var m := mi.get_surface_override_material(surface) as StandardMaterial3D
				if m == null:
					continue
				found.sss = found.sss or m.subsurf_scatter_enabled
				if m.resource_name.begins_with("MI_Superhero"):
					found.skin = m.diffuse_mode == BaseMaterial3D.DIFFUSE_LAMBERT_WRAP and m.backlight_enabled
				elif m.resource_name.begins_with("MI_Eyes"):
					found.eyes = m.clearcoat_enabled
					found.eye_layer = mi.layers & FighterModel.EYE_LAYER != 0
				elif m.resource_name.begins_with("MI_Hair"):
					found.hair = found.hair or m.anisotropy_enabled
		var light := model.skeleton.find_child("EyeLight", true, false) as OmniLight3D
		found["eye_light"] = light != null and light.light_cull_mask == FighterModel.EYE_LAYER
		shading["%s_%d" % [run[0].id, run[1]]] = found
		model.free()
	settings.graphics = settings.Graphics.HIGH
	var all_on := {"skin": true, "sss": false, "eyes": true, "hair": true, "eye_layer": true, "eye_light": true}
	var all_off := {"skin": false, "sss": false, "eyes": false, "hair": false, "eye_layer": false, "eye_light": false}
	check("Kenji: wrapped skin, wet eyes with an eye light, anisotropic hair, no scattering pass",
		shading["kenji_%d" % settings.Graphics.HIGH] == all_on, "%s" % [shading])
	check("Mira (female body, matte bob) gets it too", shading["mira_%d" % settings.Graphics.HIGH] == all_on, "%s" % [shading])
	check("The Low preset skips realistic shading", shading["kenji_%d" % settings.Graphics.LOW] == all_off, "%s" % [shading])
	gs.player_character = gs.roster[0]; gs.p2_character = gs.roster[2]


## Facial expressions (tools/face_shapes.gd): every body and face piece carries the blend
## shapes, the mouth opens without moving the face above it, the eyelids close without
## moving the brows, and fighters pull faces that match what is happening to them.
func face_tests() -> void:
	var gs = root.get_node("GameState")
	check("FighterModel and the shape builder agree on the shapes", FighterModel.FACE_SHAPES == FaceShapes.SHAPES)
	for character: CharacterData in gs.roster:
		var id := String(character.id)
		var body := character.outfit_body_mesh as ArrayMesh
		var names := []
		for i in body.get_blend_shape_count():
			names.append(body.get_blend_shape_name(i))
		var surfaces := []
		for i in body.get_surface_count():
			surfaces.append(body.surface_get_name(i))
		check("%s: the body has every expression and a mouth" % id,
			FighterModel.FACE_SHAPES.all(func(n): return n in names) and "mouth" in surfaces, "%s %s" % [names, surfaces])
		var model := FighterModel.new()
		root.add_child(model)
		model.build(character)
		var pieces := model._face_meshes.map(func(mi: MeshInstance3D) -> String: return mi.name)
		check("%s: the face pieces (eyebrows, lashes%s) are expression-ready too" % [id, ", beard" if id == "brutus" else ""],
			"Eyebrows" in pieces and pieces.size() >= 2 and (id != "brutus" or "Hair_Beard" in pieces), "%s" % [pieces])
		model.free()
	# The shapes themselves, on Kenji's body.
	var kenji := gs.roster[0] as CharacterData
	var base := kenji.model_scene.instantiate()
	var face := FaceShapes.landmarks(base)
	base.free()
	var body := kenji.outfit_body_mesh as ArrayMesh
	var rest: PackedVector3Array = body.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shapes := body.surface_get_blend_shape_arrays(0)
	var moved := func(shape: StringName, region: Callable) -> float:
		var target: PackedVector3Array = shapes[FighterModel.FACE_SHAPES.find(shape)][Mesh.ARRAY_VERTEX]
		var most := 0.0
		for i in rest.size():
			if region.call(rest[i]):
				most = maxf(most, rest[i].distance_to(target[i]))
		return most
	var seam: float = face.seam
	var eye: Vector3 = face.eye
	var chin := func(p: Vector3) -> bool: return absf(p.x) < 0.02 and p.y < seam - 0.02 and p.y > seam - 0.05 and p.z > 0.04
	var above_mouth := func(p: Vector3) -> bool: return p.y > seam + 0.012
	var lids := func(p: Vector3) -> bool: return absf(absf(p.x) - eye.x) < 0.008 and p.y > eye.y and p.y < eye.y + 0.006 and p.z > eye.z
	var far_from_eyes := func(p: Vector3) -> bool: return p.y > eye.y + 0.03 or p.y < eye.y - 0.05
	check("jaw_open drops the chin; nothing above the mouth moves",
		moved.call(&"jaw_open", chin) > 0.012 and moved.call(&"jaw_open", above_mouth) < 0.002,
		"chin %.4f, above %.4f" % [moved.call(&"jaw_open", chin), moved.call(&"jaw_open", above_mouth)])
	check("blink closes the lids and leaves the forehead and mouth alone",
		moved.call(&"blink", lids) > 0.004 and moved.call(&"blink", far_from_eyes) < 0.0005,
		"lids %.4f, elsewhere %.4f" % [moved.call(&"blink", lids), moved.call(&"blink", far_from_eyes)])
	var at_rest := 0
	var indices: PackedInt32Array = body.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	for t in range(0, indices.size(), 3):
		var spans_mouth := true
		for c in 3:
			var p := rest[indices[t + c]]
			spans_mouth = spans_mouth and absf(p.x) < 0.01 and absf(p.y - seam) < 0.0008 and absf(p.z - face.inner_z) < 0.0008
		if spans_mouth:
			at_rest += 1
	check("The lips are cut apart (no triangle seals the mouth)", at_rest == 0, "%d" % at_rest)

	# Gaze: the eyeballs turn about their centres; only the iris moves.
	var eyes_mesh := load(FighterModel.face_piece_path(kenji.model_scene.resource_path,
		kenji.model_scene.resource_path, "Eyes")) as ArrayMesh
	var eye_rest: PackedVector3Array = eyes_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var centres := FaceShapes.eyeball_centres(eye_rest)
	var look_left: PackedVector3Array = eyes_mesh.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
	var off_sphere := 0.0
	var front := 0
	for i in eye_rest.size():
		var c: Vector3 = centres[0] if eye_rest[i].x >= 0.0 else centres[1]
		off_sphere = maxf(off_sphere, absf(look_left[i].distance_to(c) - eye_rest[i].distance_to(c)))
		if eye_rest[i].x > 0.0 and eye_rest[i].z > eye_rest[front].z:
			front = i
	check("The eyes have the gaze shapes, in FighterModel's order",
		range(eyes_mesh.get_blend_shape_count()).map(func(i): return eyes_mesh.get_blend_shape_name(i)) == Array(FighterModel.GAZE_SHAPES))
	check("Looking left turns the eyeball in place (the pupil moves, the sphere doesn't)",
		off_sphere < 0.0001 and look_left[front].x - eye_rest[front].x > 0.004,
		"off sphere %.5f, pupil %.4f" % [off_sphere, look_left[front].x - eye_rest[front].x])
	var watcher := FighterModel.new()
	root.add_child(watcher)
	watcher.build(kenji)
	check("Fighters' eyes can turn", watcher.has_gaze())
	var head := watcher.skeleton.global_transform * watcher.skeleton.get_bone_global_pose(watcher._head_bone)
	var face_axis := func(v: Vector3) -> Vector3: return (head.basis * (watcher._head_rest.inverse() * v)).normalized()
	var eye_point := watcher.eye_position()
	for i in 30:
		watcher.set_gaze(eye_point + face_axis.call(Vector3(0.6, 0, 1)), 1.0 / 60.0)
	check("The eyes follow a target to the side", watcher.gaze.x > 0.15 and absf(watcher.gaze.y) < 0.05, "%s" % watcher.gaze)
	for i in 30:
		watcher.set_gaze(eye_point + face_axis.call(Vector3(0, 0.3, 1)), 1.0 / 60.0)
	check("... and one above", watcher.gaze.y > 0.15 and absf(watcher.gaze.x) < 0.05, "%s" % watcher.gaze)
	for i in 30:
		watcher.set_gaze(eye_point + face_axis.call(Vector3(0, 0, -1)), 1.0 / 60.0)
	check("A target behind the head is ignored", watcher.gaze.length() < 0.01, "%s" % watcher.gaze)

	# The voice moves the mouth.
	var envelopes := (load(FighterModel.VOICE_ENVELOPES) as JSON).data as Dictionary
	var clips := Array(ResourceLoader.list_directory("res://assets/audio/voice/fighters/")).filter(
		func(f: String) -> bool: return f.ends_with(".ogg")).map(func(f: String) -> String: return f.get_basename())
	check("Every fighter voice clip has a mouth envelope", clips.all(func(c): return envelopes.has(c)) and clips.size() == envelopes.size(),
		"%d clips, %d envelopes" % [clips.size(), envelopes.size()])
	var voice := AudioStreamPlayer.new()
	root.add_child(voice)
	voice.stream = load("res://assets/audio/voice/fighters/kenji_special_1.ogg")
	voice.play()
	watcher.speak(voice)
	var widest := 0.0
	for i in 30:
		await process_frame
		watcher.set_face(&"neutral", 1.0 / 60.0)
		widest = maxf(widest, watcher._face_meshes[0].get_blend_shape_value(watcher._face_indices[0][4]))
	check("A shout opens the jaw", widest > 0.5, "%.2f" % widest)
	voice.stop()
	for i in 30:
		watcher.set_face(&"neutral", 1.0 / 60.0)
	check("... and it closes again when the shout ends",
		watcher._face_meshes[0].get_blend_shape_value(watcher._face_indices[0][4]) < 0.01)
	voice.free()
	watcher.free()

	# Expressions follow the fight.
	var D := DummyController.Mode
	reset(D.STAND)
	check("Fighters start the round with a focused face", p1.face_expression() == &"neutral")
	approach(1.0)
	press(InputBuffer.HP); step(4)
	check("A heavy attack shouts or strains", p1.face_expression() in [&"shout", &"effort"], String(p1.face_expression()))
	wait_until(func() -> bool: return p2.state == Fighter.State.HITSTUN, 20)
	check("Getting hit hurts", p2.face_expression() == &"pain", String(p2.face_expression()))
	for i in 10:
		p2.model.set_face(p2.face_expression(), 1.0 / 60.0)
	check("The face eases toward the expression", p2.model.face_weights[&"grimace"] > 0.5 and p2.model.face_weights[&"grimace"] <= 0.8,
		"%.2f" % p2.model.face_weights[&"grimace"])
	var watched := p1.gaze_target()
	check("Fighters watch the opponent's upper body", watched.is_finite()
		and Vector2(watched.x - p2.global_position.x, watched.z - p2.global_position.z).length() < 0.4
		and watched.y > p2.global_position.y + 0.9, "%s vs %s" % [watched, p2.global_position])
	p2._set_state(Fighter.State.KO)
	check("A K.O. shuts the eyes", p2.face_expression() == &"out")
	check("... and the K.O.'d fighter looks at nothing", not p2.gaze_target().is_finite())
	reset(D.STAND)


## Generated clothing (tools/build_outfits.gd): every fighter is dressed, the outfit is
## a valid skinned mesh on the body's skin, the covered skin is removed, and mirror
## matches get the alternate colours.
func outfit_tests() -> void:
	var gs = root.get_node("GameState")
	for character: CharacterData in gs.roster:
		var id := String(character.id)
		var outfit := character.outfit_mesh as ArrayMesh
		check("%s has an outfit" % id, outfit != null and character.outfit_body_mesh != null and outfit.get_surface_count() >= 2)
		if outfit == null:
			continue
		var names := []
		for surface in outfit.get_surface_count():
			names.append(outfit.surface_get_name(surface))
		var slots := character.outfit_colors.size()
		check("%s outfit surfaces are colour slots with colours and fabrics" % id,
			names.all(func(n): return n in ["main", "trim", "accent", "extra"]) and slots >= names.size()
			and character.alt_outfit_colors.size() == slots and character.outfit_fabrics.size() == slots
			and character.alt_outfit_colors != character.outfit_colors, "%s" % [names])
		var base_triangles := 0
		var base_scene := character.model_scene.instantiate()
		var bind_count := 0
		for mi: MeshInstance3D in base_scene.find_children("*", "MeshInstance3D", true, false):
			var material := mi.mesh.surface_get_material(0)
			if material and material.resource_name.begins_with("MI_Superhero"):
				base_triangles = mi.mesh.surface_get_array_index_len(0) / 3
				bind_count = mi.skin.get_bind_count()
		base_scene.free()
		var body_triangles := (character.outfit_body_mesh as ArrayMesh).surface_get_array_index_len(0) / 3
		check("%s: the skin under the clothes is removed" % id, body_triangles < base_triangles and body_triangles > base_triangles / 3,
			"%d of %d triangles kept" % [body_triangles, base_triangles])
		var weights_ok := true
		for surface in outfit.get_surface_count():
			var arrays := outfit.surface_get_arrays(surface)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for v in weights.size() / 4:
				var total := weights[v * 4] + weights[v * 4 + 1] + weights[v * 4 + 2] + weights[v * 4 + 3]
				if absf(total - 1.0) > 0.01:
					weights_ok = false
				for k in 4:
					if bones[v * 4 + k] < 0 or bones[v * 4 + k] >= bind_count:
						weights_ok = false
		check("%s outfit vertices have valid bone weights" % id, weights_ok)

	# FighterModel dresses the fighter on the body's skin, with alt colours for mirrors.
	var kenji: CharacterData = gs.roster[0]
	for alt in [false, true]:
		var model := FighterModel.new()
		root.add_child(model)
		model.build(kenji, alt)
		var dressed := model.skeleton.get_node_or_null("Outfit") as MeshInstance3D
		var body: MeshInstance3D
		for mi: MeshInstance3D in model.skeleton.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == kenji.outfit_body_mesh:
				body = mi
		var colors := kenji.alt_outfit_colors if alt else kenji.outfit_colors
		var expected: Color = colors[0]
		var brightest := maxf(expected.r, maxf(expected.g, expected.b))
		if brightest > FighterModel.MAX_FABRIC_ALBEDO:
			expected = Color(expected * (FighterModel.MAX_FABRIC_ALBEDO / brightest), 1.0)
		var material := dressed.get_surface_override_material(0) as StandardMaterial3D if dressed else null
		check("FighterModel dresses Kenji%s on the body's skin" % (" (alt)" if alt else ""),
			dressed != null and body != null and dressed.skin == body.skin and dressed.get_node_or_null(dressed.skeleton) == model.skeleton
			and material != null and material.albedo_color.is_equal_approx(expected) and material.normal_texture != null)
		var max_specular := 0.0
		var max_albedo := 0.0
		for surface in dressed.mesh.get_surface_count():
			var cloth := dressed.get_surface_override_material(surface) as StandardMaterial3D
			max_specular = maxf(max_specular, cloth.metallic_specular)
			max_albedo = maxf(max_albedo, maxf(cloth.albedo_color.r, maxf(cloth.albedo_color.g, cloth.albedo_color.b)))
		check("Kenji%s's outfit is matte (low specular, no blown-out whites)" % (" (alt)" if alt else ""),
			max_specular <= 0.35 and max_albedo <= FighterModel.MAX_FABRIC_ALBEDO + 0.001, "specular %.2f, albedo %.2f" % [max_specular, max_albedo])
		model.queue_free()
	await process_frame



# --- Rollback netcode -------------------------------------------------------------

## Random but fight-like screen-relative inputs: held directions (biased toward the
## opponent), button presses and the odd motion, from a seeded RNG.
func _net_inputs(count: int, seed: int, toward_right: bool) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := PackedInt32Array()
	var fwd := 6 if toward_right else 4
	var back := 4 if toward_right else 6
	var dfwd := 3 if toward_right else 1
	while out.size() < count:
		var roll := rng.randf()
		if roll < 0.08: # quarter-circle forward + punch or kick
			for d in [2, dfwd]:
				out.append(InputBuffer.pack(d, 0))
				out.append(InputBuffer.pack(d, 0))
			out.append(InputBuffer.pack(fwd, [InputBuffer.LP, InputBuffer.HK][rng.randi() % 2]))
			continue
		var dir: int = [fwd, fwd, fwd, 5, 5, back, 2, dfwd, 8][rng.randi() % 9]
		var buttons := 0
		if rng.randf() < 0.45:
			buttons = [InputBuffer.LP, InputBuffer.HP, InputBuffer.LK, InputBuffer.HK, InputBuffer.LP | InputBuffer.LK, InputBuffer.SIDESTEP][rng.randi() % 6]
		var hold := rng.randi_range(1, 10)
		for i in hold:
			out.append(InputBuffer.pack(dir, buttons if i == 0 else 0))
	out.resize(count)
	return out


func _net_fight() -> Node:
	var fight: Node = (load("res://scenes/fight.tscn") as PackedScene).instantiate()
	root.add_child(fight)
	fight.set_physics_process(false)
	return fight


## Runs two peers over a simulated network until both have confirmed `ticks` ticks.
## latency/jitter in ticks, loss 0..1.
## late_start: peer 2 joins this many ticks after peer 1. tamper_at: at this real tick
## peer 2's copy of P1 loses 1 health (a fake desync).
func _net_play(inputs: Array, ticks: int, delay: int, latency: int, jitter: int, loss: float, seed: int, late_start := 0, tamper_at := -1) -> Dictionary:
	var peers := [_net_fight(), _net_fight()]
	var sessions := [RollbackSession.new(peers[0], 0, delay), RollbackSession.new(peers[1], 1, delay)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var in_flight := [[], []] # packets heading to peer i: [deliver_at, bytes]
	var desyncs := [0]
	for s: RollbackSession in sessions:
		s.rtt_ticks = latency * 2 + jitter
		s.desynced.connect(func(_f, _a, _b): desyncs[0] += 1)
	var real := 0
	while real < ticks * 3 and (sessions[0].confirmed_frame() < ticks - 1 or sessions[1].confirmed_frame() < ticks - 1):
		real += 1
		if real == tamper_at:
			peers[1].fighters[0].health -= 1
		for i in 2:
			if i == 1 and real <= late_start:
				continue
			var s: RollbackSession = sessions[i]
			var stream: PackedInt32Array = inputs[i]
			var index := s.frame + delay
			s.advance(stream[index] if index < stream.size() else InputBuffer.pack(5, 0))
			if rng.randf() >= loss:
				in_flight[1 - i].append([real + latency + rng.randi_range(0, jitter), s.make_packet()])
		for i in 2:
			var still := []
			for packet: Array in in_flight[i]:
				if packet[0] <= real:
					sessions[i].receive_packet(packet[1])
				else:
					still.append(packet)
			in_flight[i] = still
	var result := {real = real, desyncs = desyncs[0], sessions = sessions,
		frames = [sessions[0].frame, sessions[1].frame], confirmed = [sessions[0].confirmed_frame(), sessions[1].confirmed_frame()]}
	for p in peers:
		p.queue_free()
	return result


func rollback_tests() -> void:
	var gs = root.get_node("GameState")
	gs.mode = gs.Mode.VERSUS
	gs.player_character = gs.roster[0] # Kenji (fireballs)
	gs.p2_character = gs.roster[3] # Valka (command grabs)
	gs.stage_path = gs.DEFAULT_STAGE

	# Reference: the same inputs run straight through, no network.
	const TICKS := 1500
	var inputs := [_net_inputs(TICKS + 40, 101, true), _net_inputs(TICKS + 40, 202, false)]
	var ref := _net_fight()
	var ctls: Array[NetInputController] = [NetInputController.new(), NetInputController.new()]
	for i in 2:
		ref.fighters[i].controller = ctls[i]
	var right_side: Fighter = ref.fighters[1] # P2 starts on the right, facing screen-left
	check("facing conversion mirrors left/right for the fighter on the right",
		not right_side.faces_screen_right() and PlayerController.to_facing(InputBuffer.pack(3, InputBuffer.LP), right_side) == InputBuffer.pack(1, InputBuffer.LP)
		and PlayerController.to_facing(InputBuffer.pack(3, 0), ref.fighters[0]) == InputBuffer.pack(3, 0))
	var hits := [0]
	ref.hit_landed.connect(func(_a, _d, _m, _r): hits[0] += 1)
	var expected := {} # tick -> checksum of the state before that tick
	var mid_state := {}
	for t in TICKS:
		if t % RollbackSession.CHECKSUM_INTERVAL == 0:
			expected[t] = ref.checksum(ref.save_state())
		if t == 700:
			mid_state = ref.save_state()
		for i in 2:
			ctls[i].raw = inputs[i][t]
		ref.step()
	check("netplay reference fight has real exchanges", hits[0] >= 8, "%d hits, health %d / %d" % [hits[0], ref.fighters[0].health, ref.fighters[1].health])

	# Save / load round trip: restoring a snapshot and replaying gives the same result.
	var end_sum: int = ref.checksum(ref.save_state())
	ref.load_state(mid_state)
	check("loaded snapshot hashes the same as when saved", ref.checksum(ref.save_state()) == ref.checksum(mid_state))
	for t in range(700, TICKS):
		for i in 2:
			ctls[i].raw = inputs[i][t]
		ref.step()
	check("replay from a loaded snapshot matches the original run", ref.checksum(ref.save_state()) == end_sum)
	ref.queue_free()

	# Low ping (inside the input delay): no rollbacks needed.
	var calm := _net_play(inputs, 600, 2, 1, 0, 0.0, 5)
	var calm_s: Array = calm.sessions
	check("netplay within the input delay never rolls back", calm_s[0].rollbacks == 0 and calm_s[1].rollbacks == 0 and calm.desyncs == 0,
		"rollbacks %d / %d" % [calm_s[0].rollbacks, calm_s[1].rollbacks])

	# Bad connection: ~90 ms ping with jitter and 15% packet loss.
	var rough := _net_play(inputs, TICKS, 2, 4, 3, 0.15, 9)
	var s0: RollbackSession = rough.sessions[0]
	var s1: RollbackSession = rough.sessions[1]
	check("lossy netplay finishes", rough.confirmed[0] >= TICKS - 1 and rough.confirmed[1] >= TICKS - 1, "confirmed %s in %d real ticks" % [rough.confirmed, rough.real])
	check("lossy netplay rolls back", s0.rollbacks > 10 and s1.rollbacks > 10, "rollbacks %d / %d, %d / %d ticks re-run" % [s0.rollbacks, s1.rollbacks, s0.rollback_ticks, s1.rollback_ticks])
	check("lossy netplay: no desync reported", rough.desyncs == 0 and s0.desync_frame < 0 and s1.desync_frame < 0)
	var compared := 0
	var mismatches := []
	for s: RollbackSession in [s0, s1]:
		for c: int in s.checksums:
			if expected.has(c):
				compared += 1
				if s.checksums[c] != expected[c]:
					mismatches.append(c)
	check("both peers reproduce the reference fight exactly", mismatches.is_empty() and compared >= 2 * (TICKS / RollbackSession.CHECKSUM_INTERVAL - 2),
		"%d checkpoints compared, mismatches at %s" % [compared, mismatches])
	check("time sync keeps the peers close", absi(s0.frame - s1.frame) <= RollbackSession.MAX_ROLLBACK, "frames %s" % [rough.frames])
	print("  netplay stats: %d real ticks, stalls %d/%d, sync waits %d/%d" % [rough.real, s0.stalls, s1.stalls, s0.sync_waits, s1.sync_waits])
	check("time sync doesn't wait on a steady connection", s0.sync_waits + s1.sync_waits <= rough.real / 100, "waits %d / %d" % [s0.sync_waits, s1.sync_waits])

	# Very high ping (beyond the rollback window): stalls, but still exact.
	var laggy := _net_play(inputs, 600, 2, 12, 2, 0.05, 13)
	var l0: RollbackSession = laggy.sessions[0]
	var exact := true
	for c: int in l0.checksums:
		if expected.has(c) and l0.checksums[c] != expected[c]:
			exact = false
	check("high-ping netplay stalls instead of rolling back too far", l0.stalls > 0 and l0.last_rollback <= RollbackSession.MAX_ROLLBACK + 1 and exact and laggy.desyncs == 0,
		"stalls %d, longest recent rollback %d" % [l0.stalls, l0.last_rollback])

	# A peer that starts late: time sync makes the early one wait until they're level.
	var late := _net_play(inputs, 900, 2, 3, 1, 0.0, 17, 8)
	var e0: RollbackSession = late.sessions[0]
	var e1: RollbackSession = late.sessions[1]
	check("time sync slows the peer that's ahead", e0.sync_waits > e1.sync_waits and absi(e0.frame - e1.frame) <= 2,
		"waits %d / %d, frames %s" % [e0.sync_waits, e1.sync_waits, late.frames])

	# A desync (here: faked by changing one peer's state) is detected.
	var broken := _net_play(inputs, 600, 2, 2, 1, 0.0, 21, 0, 200)
	check("netplay detects a desync", broken.desyncs > 0 and broken.sessions[0].desync_frame > 0,
		"desync at tick %d" % broken.sessions[0].desync_frame)

	# Packets from another match (the previous one, around a rematch) are ignored.
	var fresh := _net_fight()
	var old_match := _net_fight()
	var current := RollbackSession.new(fresh, 0, 2, 111)
	var stale := RollbackSession.new(old_match, 1, 2, 222)
	for i in 300:
		stale.add_remote_input(i, InputBuffer.pack(5, 0))
		stale.advance(InputBuffer.pack(6, 0))
	current.receive_packet(stale.make_packet())
	check("netplay ignores packets from another match", current.remote_frame == -1 and current.confirmed_frame() == -1, "remote frame %d" % current.remote_frame)
	var same := RollbackSession.new(old_match, 1, 2, 111)
	current.receive_packet(same.make_packet())
	check("netplay accepts packets from its own match", current.remote_frame == -1 and current._remote_confirmed == 1, "confirmed %d" % current._remote_confirmed)
	fresh.queue_free()
	old_match.queue_free()

	# The same fight over real UDP sockets (loopback), 50 ms lag, jitter and 10% loss.
	var udp := await _udp_play(inputs, 900, 50, 16, 0.1)
	var u_exact := true
	var u_compared := 0
	for us: RollbackSession in udp.sessions:
		for c: int in us.checksums:
			if expected.has(c):
				u_compared += 1
				u_exact = u_exact and us.checksums[c] == expected[c]
	check("netplay over UDP matches the reference fight", udp.ok and u_exact and u_compared >= 2 * 13 and udp.desyncs == 0,
		"connected %s, %d checkpoints, rollbacks %d / %d, rtt %.0f ms" % [udp.ok, u_compared, udp.sessions[0].rollbacks, udp.sessions[1].rollbacks, udp.rtt])
	gs.mode = gs.Mode.VS_CPU


# --- Online connection (NetPeer over loopback UDP) ----------------------------------

var _net_clock := [0]


## Advances the fake clock one tick per round and polls every peer.
func _pump(peers: Array, rounds: int) -> void:
	for i in rounds:
		_net_clock[0] += 17 if i % 3 == 0 else 16
		for peer in peers: # NetPeers and LanBrowsers
			if peer:
				peer.poll()
		OS.delay_usec(150) # loopback datagrams land almost at once


func _net_peer(version := "1.0", data_hash := 42, name := "P") -> NetPeer:
	var peer := NetPeer.new(version, data_hash, name)
	peer.clock = func() -> int: return _net_clock[0]
	peer.auto_accept = true # the join prompt has its own tests
	return peer


## A RollbackSession INPUT packet with any field values (for attack tests).
func _rb_packet(match_id: int, sender: int, ack: int, advantage: int, checksum_tick: int, checksum: int, first: int, inputs: Array) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(RollbackSession.PACKET_INPUT)
	out.put_u32(match_id)
	out.put_32(sender)
	out.put_32(ack)
	out.put_8(advantage)
	out.put_32(checksum_tick)
	out.put_u32(checksum)
	out.put_32(first)
	out.put_u8(inputs.size())
	for i: int in inputs:
		out.put_u16(i)
	return out.data_array


## Sends `bytes` from a fresh socket to the host and returns every reply within a few polls.
func _probe(host: NetPeer, bytes: PackedByteArray, times := 1) -> Array[PackedByteArray]:
	var probe := PacketPeerUDP.new()
	probe.bind(0)
	probe.set_dest_address("127.0.0.1", host.local_port())
	for i in times:
		probe.put_packet(bytes)
	var replies: Array[PackedByteArray] = []
	for round in 6:
		OS.delay_usec(300)
		host.poll()
		OS.delay_usec(300)
		while probe.get_available_packet_count() > 0:
			replies.append(probe.get_packet())
	probe.close()
	return replies


## A HELLO as a joiner would send it (cookie 0 = first contact).
func _hello_bytes(version: String, data_hash: int, name: String, nonce: int, cookie: int) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(NetPeer.T_HELLO)
	out.put_u16(NetPeer.PROTOCOL)
	out.put_utf8_string(version)
	out.put_u32(data_hash)
	out.put_utf8_string(name)
	out.put_u64(nonce)
	out.put_u64(cookie)
	return out.data_array


func net_tests() -> void:
	var gs = root.get_node("GameState")
	check("the host key is made in the background", _wait_host_key())
	# The key task starts at boot; quitting before it's done must not crash (it did).
	var boot_exit := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://scenes/main_menu.tscn", "--quit-after", "5"])
	check("the game exits cleanly right after boot (background key task)", boot_exit == 0, "exit code %d" % boot_exit)
	# The title screen (the main scene) loads the fighters on background threads: quitting
	# in the middle of that must not crash either.
	var title_exit := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--quit-after", "3"])
	check("the game exits cleanly during the title screen's loading", title_exit == 0, "exit code %d" % title_exit)
	check("game data hash is stable", gs.content_hash() == gs.content_hash() and gs.content_hash() != 0)

	var host := _net_peer("1.0", 42, "Hosty")
	check("host binds a UDP port", host.host(0) == OK and host.local_port() > 0)
	var guest := _net_peer("1.0", 42, "Guesty")
	guest.join("127.0.0.1", host.local_port())
	_pump([host, guest], 20)
	check("guest connects to host", host.is_connected_to_peer() and guest.is_connected_to_peer()
		and host.remote_name == "Guesty" and guest.remote_name == "Hosty", "%s / %s" % [host.status, guest.status])
	check("both players get the same 6-digit security code", host.security_code.length() == 7 and host.security_code == guest.security_code,
		"%s / %s" % [host.security_code, guest.security_code])

	var outsider := _net_peer("1.0", 42, "Late")
	var outsider_reason := [""]
	outsider.connect_failed.connect(func(r: String) -> void: outsider_reason[0] = r)
	outsider.join("127.0.0.1", host.local_port())
	_pump([host, guest, outsider], 20)
	check("a busy host turns away a second guest", outsider_reason[0].contains("already"), outsider_reason[0])

	var old := _net_peer("0.9", 42, "Old")
	var old_reason := [""]
	old.connect_failed.connect(func(r: String) -> void: old_reason[0] = r)
	var picky := _net_peer("1.0", 42, "Host2")
	picky.host(0)
	old.join("127.0.0.1", picky.local_port())
	_pump([picky, old], 20)
	check("different game versions can't connect", old_reason[0].contains("version") and not picky.is_connected_to_peer(), old_reason[0])
	var modded := _net_peer("1.0", 999, "Modded")
	var modded_reason := [""]
	modded.connect_failed.connect(func(r: String) -> void: modded_reason[0] = r)
	modded.join("127.0.0.1", picky.local_port())
	_pump([picky, modded], 20)
	check("different game data can't connect", modded_reason[0].contains("data"), modded_reason[0])
	picky.close()

	# Reliable messages arrive once each, in order, through 30% packet loss both ways.
	host.loss = 0.3
	guest.loss = 0.3
	var got: Array[int] = []
	guest.message_received.connect(func(type: int, payload: PackedByteArray) -> void: got.append(type * 1000 + payload[0]))
	for i in 20:
		host.send_reliable(1 + i % 3, PackedByteArray([i]))
	_pump([host, guest], 200)
	var want: Array[int] = []
	for i in 20:
		want.append((1 + i % 3) * 1000 + i)
	check("reliable messages: all delivered, in order, despite loss", got == want, "%d of 20" % got.size())
	host.loss = 0.0
	guest.loss = 0.0

	# Ping through the lag simulator (40 ms each way).
	host.lag_ms = 40
	guest.lag_ms = 40
	_pump([host, guest], 150)
	check("ping measures the round trip", absf(host.rtt_ms - 80.0) < 20.0 and absf(guest.rtt_ms - 80.0) < 20.0, "%.0f / %.0f ms" % [host.rtt_ms, guest.rtt_ms])
	host.lag_ms = 0
	guest.lag_ms = 0

	# Leaving tells the other side at once; silence times out.
	var left := [""]
	guest.disconnected.connect(func(r: String) -> void: left[0] = r)
	host.close()
	_pump([guest], 5)
	check("leaving notifies the opponent", left[0].contains("left") and not guest.is_connected_to_peer(), left[0])
	var host3 := _net_peer()
	host3.host(0)
	var guest3 := _net_peer()
	guest3.join("127.0.0.1", host3.local_port())
	_pump([host3, guest3], 20)
	var lost := [""]
	guest3.disconnected.connect(func(r: String) -> void: lost[0] = r)
	_pump([guest3], 700) # the host stops answering for ~11 s
	check("a silent connection times out", lost[0].contains("lost"), lost[0])
	host3.close()
	outsider.close()

	# LAN discovery: hosts answer the browser's queries.
	var lan_host := _net_peer("1.0", 42, "LanHost")
	lan_host.host(0)
	var old_host := _net_peer("0.9", 42, "OldHost")
	old_host.host(0)
	var browser := LanBrowser.new("1.0", 42)
	browser.clock = func() -> int: return _net_clock[0]
	browser.ports.assign([lan_host.local_port(), old_host.local_port()])
	check("LAN browser starts", browser.start() == OK)
	_pump([lan_host, old_host, browser], 10)
	var found: Array = browser.sorted_games()
	check("LAN browser finds each host once", found.size() == 2, "%d entries: %s" % [found.size(), found.map(func(g): return "%s@%s" % [g.name, g.ip])])
	check("LAN browser lists the joinable host first, with its port", found.size() == 2 and found[0].name == "LanHost" and found[0].compatible
		and found[0].status == 0 and found[0].port == lan_host.local_port())
	check("LAN browser flags a different version", found.size() == 2 and found[1].name == "OldHost" and not found[1].compatible and found[1].version == "0.9")
	# (Announce replies skip the lag simulator, so on loopback the ping is about one poll.)
	check("LAN browser reports a ping", found.size() == 2 and int(found[0].ping_ms) >= 0 and int(found[0].ping_ms) <= 50, "%s ms" % (found[0].ping_ms if not found.is_empty() else "-"))
	var lan_guest := _net_peer("1.0", 42, "LanGuest")
	lan_guest.join("127.0.0.1", lan_host.local_port())
	_pump([lan_host, old_host, lan_guest, browser], 80)
	var busy: Array = browser.sorted_games().filter(func(g): return g.name == "LanHost")
	check("LAN browser shows a host that's in a match", busy.size() == 1 and busy[0].status == 1)
	lan_guest.close()
	lan_host.close()
	old_host.close()
	_pump([browser], 260) # ~4 s without replies
	check("LAN browser drops hosts that stop answering", browser.games.is_empty(), "%d left" % browser.games.size())
	browser.stop()
	check("discovery answers only private addresses", NetPeer.is_private_address("192.168.1.5") and NetPeer.is_private_address("10.0.0.2")
		and NetPeer.is_private_address("172.20.1.1") and NetPeer.is_private_address("127.0.0.1")
		and not NetPeer.is_private_address("8.8.8.8") and not NetPeer.is_private_address("172.32.0.1") and not NetPeer.is_private_address("::1"))
	check("broadcast targets include the limited broadcast and localhost", "255.255.255.255" in LanBrowser.broadcast_targets() and "127.0.0.1" in LanBrowser.broadcast_targets())

	# Fuzz: garbage datagrams of every type must not crash, error or drop a connection.
	var fz_host := _net_peer("1.0", 42, "FuzzHost")
	fz_host.host(0)
	var fz_guest := _net_peer("1.0", 42, "FuzzGuest")
	fz_guest.join("127.0.0.1", fz_host.local_port())
	_pump([fz_host, fz_guest], 20)
	var lone_host := _net_peer("1.0", 42, "Lonely")
	lone_host.host(0)
	var fz_browser := LanBrowser.new("1.0", 42)
	fz_browser.ports.assign([lone_host.local_port()])
	fz_browser.start()
	var fz_fight := _net_fight()
	var fz_session := RollbackSession.new(fz_fight, 0, 2, 5)
	var attacker := PacketPeerUDP.new()
	attacker.bind(0)
	var fz_rng := RandomNumberGenerator.new()
	fz_rng.seed = 77
	var errors_before := errors.count
	var engine_before := errors.engine_count
	var kinds := [NetPeer.T_INPUT, NetPeer.T_HELLO, NetPeer.T_WELCOME, NetPeer.T_REJECT, NetPeer.T_PING, NetPeer.T_PONG,
		NetPeer.T_RELIABLE, NetPeer.T_ACK, NetPeer.T_DISCOVER, NetPeer.T_ANNOUNCE, 0, 255]
	for i in 600:
		var junk := PackedByteArray()
		junk.resize(fz_rng.randi_range(1, 64))
		for k in junk.size():
			junk[k] = fz_rng.randi() % 256
		junk[0] = kinds[i % kinds.size()]
		if junk[0] == NetPeer.T_INPUT and junk.size() > 4: # the right match id now and then
			junk.encode_u32(1, 5 if i % 2 == 0 else fz_rng.randi())
		for port in [fz_host.local_port(), lone_host.local_port(), fz_browser._socket.get_local_port()]:
			attacker.set_dest_address("127.0.0.1", port)
			attacker.put_packet(junk)
		fz_session.receive_packet(junk)
		if i % 20 == 0:
			_pump([fz_host, fz_guest, lone_host, fz_browser], 1)
	_pump([fz_host, fz_guest, lone_host, fz_browser], 30)
	var still_runs := true
	for t in 30:
		fz_session.advance(InputBuffer.pack(5, 0))
	check("fuzzed packets don't crash, error or disconnect", errors.count == errors_before and fz_host.is_connected_to_peer()
		and fz_guest.is_connected_to_peer() and lone_host.status == NetPeer.Status.HOSTING and still_runs,
		"script errors +%d, host %s, guest %s" % [errors.count - errors_before, fz_host.status, fz_guest.status])
	check("fuzzed packets don't make the engine log errors", errors.engine_count == engine_before,
		"+%d, last: %s" % [errors.engine_count - engine_before, errors.last_engine])
	attacker.close()
	fz_browser.stop()
	for peer: NetPeer in [fz_host, fz_guest, lone_host]:
		peer.close()
	fz_fight.queue_free()

	await security_tests()
	crypto_tests()

	# Lobby protocol: the Net autoload hosts, a test peer plays the guest.
	var net = root.get_node("Net")
	net.peer_clock = func() -> int: return _net_clock[0]
	check("Net hosts", net.host(0) == OK)
	net.peer.auto_accept = true # the join prompt has its own tests
	var g := _net_peer(gs.game_version(), gs.content_hash(), "Guest")
	var msgs: Array[Array] = []
	g.message_received.connect(func(t: int, payload: PackedByteArray) -> void: msgs.append([t, payload]))
	g.join("127.0.0.1", net.peer.local_port())
	_pump([net.peer, g], 20)
	check("Net: guest connects", net.is_active() and net.opponent_name() == "Guest")
	g.send_reliable(net.M_PICK, PackedByteArray([3]))
	_pump([net.peer, g], 10)
	check("Net: the guest's pick arrives", net.remote_pick == 3 and not net.both_picked())
	net.pick(4)
	_pump([net.peer, g], 10)
	check("Net: the host's pick reaches the guest", msgs.size() == 1 and msgs[0][0] == net.M_PICK and msgs[0][1][0] == 4)
	net.start_match(gs.BEACH_STAGE)
	_pump([net.peer, g], 10)
	var start_ok := false
	if msgs.size() == 2 and msgs[1][0] == net.M_START:
		var payload: PackedByteArray = msgs[1][1]
		start_ok = payload[0] == gs.stage_paths().find(gs.BEACH_STAGE) and payload[5] == 4 and payload[6] == 3 and payload[7] >= 1 and payload[7] <= 3
	check("Net: the host starts the match for both", start_ok and gs.player_character == gs.roster[4] and gs.p2_character == gs.roster[3]
		and gs.stage_path == gs.BEACH_STAGE and gs.is_online(), "%d messages" % msgs.size())
	g.send_reliable(net.M_REMATCH)
	_pump([net.peer, g], 10)
	check("Net: a rematch request arrives", net.rematch_remote and not net.rematch_local)
	net.request_rematch()
	_pump([net.peer, g], 10)
	check("Net: when both want a rematch the host restarts at once (no VS screen)", msgs.size() == 4 and msgs[2][0] == net.M_REMATCH
		and msgs[3][0] == net.M_START and msgs[3][1][8] == 1 and not net.rematch_local and not net.rematch_remote, "%s" % [msgs.map(func(m): return m[0])])
	net.back_to_lobby()
	_pump([net.peer, g], 10)
	check("Net: back to character select takes the guest too and clears the picks", msgs.size() == 5 and msgs[4][0] == net.M_LOBBY
		and net.local_pick == -1 and net.remote_pick == -1)
	g.close()
	_pump([net.peer], 5)
	check("Net: the guest leaving ends the session", net.peer == null and net.last_reason.contains("left"), net.last_reason)

	# Net as the guest: joins by "ip:port", takes the host's START.
	var h := _net_peer(gs.game_version(), gs.content_hash(), "Hosty")
	h.host(0)
	var host_saw := [""]
	h.disconnected.connect(func(r: String) -> void: host_saw[0] = r)
	check("Net joins an ip:port address", net.join("127.0.0.1:%d" % h.local_port()) == OK and net.local_index == 1)
	_pump([h, net.peer], 20)
	check("Net: connected as the guest", net.is_active() and net.opponent_name() == "Hosty" and not net.is_host())
	net.pick(0)
	var start := StreamPeerBuffer.new()
	for v in [1]: start.put_u8(v) # stage 1
	start.put_u32(99) # seed
	for v in [2, 0, 3, 0]: start.put_u8(v) # P1 fighter, P2 fighter, delay, not a rematch
	h.send_reliable(net.M_PICK, PackedByteArray([2]))
	h.send_reliable(net.M_START, start.data_array)
	_pump([h, net.peer], 10)
	check("Net: the guest applies the host's START", gs.player_character == gs.roster[2] and gs.p2_character == gs.roster[0]
		and gs.stage_path == gs.stage_paths()[1] and gs.match_seed == 99 and net.input_delay == 3 and net.local_pick == 0 and net.remote_pick == 2)
	net.leave()
	_pump([h], 5)
	check("Net: leaving tells the host", host_saw[0].contains("left") and net.peer == null, host_saw[0])
	h.close()
	check("Net: a bad address is refused", net.join("not a real host name!") != OK and net.peer == null)
	net.peer_clock = Callable()
	await process_frame
	gs.mode = gs.Mode.VS_CPU


## Hosts need the RSA key, made in a background thread; wait for it (up to 20 s).
func _wait_host_key() -> bool:
	NetPeer.prepare_host_key()
	var started := Time.get_ticks_msec()
	while not NetPeer.host_key_ready() and Time.get_ticks_msec() - started < 20000:
		OS.delay_msec(20)
	return NetPeer.host_key_ready()


## Two fight scenes playing over real UDP sockets on this machine.
func _udp_play(inputs: Array, ticks: int, lag: int, jitter: int, loss: float) -> Dictionary:
	_wait_host_key()
	var host := _net_peer()
	var guest := _net_peer()
	host.host(0)
	guest.join("127.0.0.1", host.local_port())
	_pump([host, guest], 20)
	var ok := host.is_connected_to_peer() and guest.is_connected_to_peer()
	var net_peers := [host, guest]
	for peer: NetPeer in net_peers:
		peer.lag_ms = lag
		peer.jitter_ms = jitter
		peer.loss = loss
	var fights := [_net_fight(), _net_fight()]
	var sessions := [RollbackSession.new(fights[0], 0, 2), RollbackSession.new(fights[1], 1, 2)]
	var desyncs := [0]
	for i in 2:
		(net_peers[i] as NetPeer).input_received.connect((sessions[i] as RollbackSession).receive_packet)
		(sessions[i] as RollbackSession).desynced.connect(func(_f, _a, _b): desyncs[0] += 1)
	var real := 0
	while ok and real < ticks * 3 and (sessions[0].confirmed_frame() < ticks - 1 or sessions[1].confirmed_frame() < ticks - 1):
		real += 1
		_pump(net_peers, 1)
		for i in 2:
			var s: RollbackSession = sessions[i]
			var peer: NetPeer = net_peers[i]
			s.rtt_ticks = peer.rtt_ms * 60.0 / 1000.0
			var index := s.frame + 2
			var stream: PackedInt32Array = inputs[i]
			s.advance(stream[index] if index < stream.size() else InputBuffer.pack(5, 0))
			peer.send_input(s.make_packet())
	var result := {ok = ok, sessions = sessions, desyncs = desyncs[0], rtt = host.rtt_ms}
	host.close()
	guest.close()
	for f in fights:
		f.queue_free()
	await process_frame
	return result


# --- Online security (attack tests) ---------------------------------------------------

func security_tests() -> void:
	# A HELLO from an unproven address only gets a small CHALLENGE: no slot, no detail.
	var host := _net_peer("1.0", 42, "Victim")
	host.host(0)
	var hello := _hello_bytes("1.0", 42, "Spoofer", 12345, 0)
	var replies := _probe(host, hello)
	check("a HELLO from an unproven address only gets a challenge", replies.size() == 1 and replies[0][0] == NetPeer.T_CHALLENGE
		and host.status == NetPeer.Status.HOSTING and not host.is_connected_to_peer(), "%d replies, status %s" % [replies.size(), host.status])
	check("the challenge is no bigger than the HELLO (no amplification)", replies.size() == 1 and replies[0].size() <= hello.size(),
		"%d vs %d bytes" % [replies[0].size() if replies.size() else -1, hello.size()])
	var wrong_version := _probe(host, _hello_bytes("0.1", 42, "Spoofer", 7, 0))
	check("an unproven wrong-version HELLO gets no detailed (larger) reply", wrong_version.size() == 1 and wrong_version[0][0] == NetPeer.T_CHALLENGE)
	var forged := _probe(host, _hello_bytes("1.0", 42, "Spoofer", 12345, 987654321))
	check("a forged cookie doesn't get in", forged.size() == 1 and forged[0][0] == NetPeer.T_CHALLENGE and not host.is_connected_to_peer())
	_net_clock[0] += 1000 # a fresh rate-limit window
	var flood := _probe(host, hello, 200)
	check("unverified replies are rate limited", flood.size() <= NetPeer.MAX_UNVERIFIED_REPLIES and flood.size() >= 1, "%d replies to 200 HELLOs" % flood.size())
	host.close()

	# Join confirmation.
	var asked := _net_peer("1.0", 42, "Asker")
	var picky := _net_peer("1.0", 42, "Picky")
	picky.auto_accept = false
	picky.host(0)
	var requests: Array[String] = []
	picky.join_requested.connect(func(n: String) -> void: requests.append(n))
	var pending_seen := [""]
	asked.join_pending.connect(func(n: String) -> void: pending_seen[0] = n)
	var refused := [""]
	asked.connect_failed.connect(func(r: String) -> void: refused[0] = r)
	asked.join("127.0.0.1", picky.local_port())
	_pump([picky, asked], 30)
	check("the host is asked before anyone joins", requests == ["Asker"] and not picky.is_connected_to_peer()
		and asked.awaiting_accept and pending_seen[0] == "Picky", "%s / pending %s" % [requests, pending_seen[0]])
	picky.decline_join()
	_pump([picky, asked], 10)
	check("declining turns the player away", refused[0].contains("declined") and not picky.is_connected_to_peer(), refused[0])
	var again := _net_peer("1.0", 42, "Asker")
	again.join("127.0.0.1", picky.local_port())
	_pump([picky, again], 30)
	check("a declined address can't keep asking", requests.size() == 1 and again.status == NetPeer.Status.JOINING, "%d requests" % requests.size())
	again.close()
	picky.close()

	var host2 := _net_peer("1.0", 42, "Kind")
	host2.auto_accept = false
	host2.host(0)
	var joiner := _net_peer("1.0", 42, "Friend")
	joiner.join("127.0.0.1", host2.local_port())
	_pump([host2, joiner], 30)
	host2.accept_join()
	_pump([host2, joiner], 10)
	check("accepting lets the player in", host2.is_connected_to_peer() and joiner.is_connected_to_peer() and host2.remote_name == "Friend")

	# Connected traffic needs the session token (simulated forged datagrams from the
	# guest's own address, as an attacker who can spoof it would send).
	var forged_bye := PackedByteArray([NetPeer.T_BYE])
	forged_bye.resize(9)
	forged_bye.encode_u64(1, 1234)
	host2._receive(forged_bye, host2.remote_ip, host2.remote_port, _net_clock[0])
	var forged_msg := PackedByteArray([NetPeer.T_RELIABLE])
	forged_msg.resize(15)
	forged_msg.encode_u64(1, 1234)
	forged_msg.encode_u32(9, 1)
	forged_msg[13] = 4 # M_LOBBY
	var delivered: Array[int] = []
	host2.message_received.connect(func(t: int, _p: PackedByteArray) -> void: delivered.append(t))
	host2._receive(forged_msg, host2.remote_ip, host2.remote_port, _net_clock[0])
	check("forged BYE / lobby messages without the token are ignored", host2.is_connected_to_peer() and delivered.is_empty())
	var far := joiner._reliable_datagram(1000, 4, PackedByteArray())
	host2._receive(far, host2.remote_ip, host2.remote_port, _net_clock[0])
	for seq in range(2, 2 + NetPeer.RELIABLE_WINDOW + 50):
		host2._receive(joiner._reliable_datagram(seq, 4, PackedByteArray()), host2.remote_ip, host2.remote_port, _net_clock[0])
	check("out-of-order reliable messages are held only within the window", host2._held.size() <= NetPeer.RELIABLE_WINDOW and delivered.is_empty(),
		"%d held" % host2._held.size())
	var real_bye := joiner._seal(NetPeer.T_BYE, PackedByteArray())
	host2._receive(real_bye, host2.remote_ip, host2.remote_port, _net_clock[0])
	check("the real guest's BYE (with the token) still works", not host2.is_connected_to_peer())
	joiner.close()

	# A forged REJECT during a join (wrong nonce) is ignored.
	var j2 := _net_peer("1.0", 42, "J")
	j2.join("127.0.0.1", 9) # nobody there; we only feed it datagrams
	var fake_reject := j2._reject(555, "go away")
	j2._receive(fake_reject, "127.0.0.1", 9, _net_clock[0])
	check("a forged REJECT (wrong nonce) can't break a join", j2.status == NetPeer.Status.JOINING)
	j2.close()

	# Candidate expiry: a joiner who stops asking is forgotten.
	var host3 := _net_peer("1.0", 42, "Patient")
	host3.auto_accept = false
	host3.host(0)
	var cancelled := [""]
	host3.join_cancelled.connect(func(n: String) -> void: cancelled[0] = n)
	var quitter := _net_peer("1.0", 42, "Quitter")
	quitter.join("127.0.0.1", host3.local_port())
	_pump([host3, quitter], 30)
	quitter.close()
	_pump([host3], 300)
	check("a joiner who gives up stops blocking the host", cancelled[0] == "Quitter" and host3.pending.is_empty())
	host3.close()

	# Names can't hide behind control or direction-override characters.
	check("names are cleaned of control / bidi characters", NetPeer.clean_name("Ri\u202Eval\n\u200B") == "Rival"
		and NetPeer.clean_name("\t\u0007") == "Player" and NetPeer.clean_name("A".repeat(40)).length() == NetPeer.MAX_NAME)

	# Rollback packets with impossible values are bounded.
	var fight := _net_fight()
	var session := RollbackSession.new(fight, 0, 2, 9)
	session.receive_packet(_rb_packet(9, 100000, 0, 0, 0, 0, 0, [5]))
	check("a packet claiming a far-future frame is dropped", session.remote_frame == -1 and session._remote_confirmed == -1)
	session.receive_packet(_rb_packet(9, 0, 1000000, 0, 0, 0, 0, [5]))
	var acked_now: int = session._remote_acked
	session.advance(InputBuffer.pack(6, 0)) # a new local input after the fake ack
	check("a fake ack can't stop us sending new inputs", acked_now <= session._local_newest - 1
		and session.make_packet()[RollbackSession.HEADER_SIZE - 1] > 0, "acked %d, newest %d" % [acked_now, session._local_newest])
	check("the INPUT header size matches the packet layout", session.make_packet().size() == RollbackSession.HEADER_SIZE + 2 * session.make_packet()[RollbackSession.HEADER_SIZE - 1])
	var truncated := _rb_packet(9, 0, 0, 0, 0, 0, 2, [5, 5])
	truncated.resize(truncated.size() - 1) # claims 2 inputs, carries 1.5
	var engine_errors := errors.engine_count
	session.receive_packet(truncated)
	check("a packet one byte short is dropped cleanly", not session._inputs[1].has(2) and errors.engine_count == engine_errors)
	var before: int = session._inputs[1].size()
	session.receive_packet(_rb_packet(9, 0, 0, 0, 0, 0, 5000, [5, 5, 5]))
	check("far-future inputs are ignored", session._inputs[1].size() == before)
	session.receive_packet(_rb_packet(9, 0, 0, 0, 6000, 1, 1, []))
	session.receive_packet(_rb_packet(9, 0, 0, 0, 61, 1, 1, []))
	check("checksums for impossible ticks are ignored", session._remote_checksums.is_empty())
	session.receive_packet(_rb_packet(9, 0, 0, 127, 0, 0, 1, [0xFFFF]))
	check("garbage inputs are reduced to a real direction and buttons", session._inputs[1].get(1) == InputBuffer.pack(5, 0x1F)
		and session.remote_advantage == RollbackSession.MAX_ADVANTAGE, "%s" % session._inputs[1].get(1))
	fight.queue_free()

	# LAN list: no unsolicited entries, a capped list.
	var browser := LanBrowser.new("1.0", 42)
	browser.clock = func() -> int: return _net_clock[0]
	browser.start()
	browser.poll() # sends a query, so there's a recent time stamp
	var stamp: int = browser._recent_queries[-1]
	browser._on_announce(_announce_bytes(stamp ^ 0x5555, 1, "Ghost"), "192.168.1.66", _net_clock[0])
	check("unsolicited LAN announcements are ignored", browser.games.is_empty())
	for id in 200:
		browser._on_announce(_announce_bytes(stamp, 1000 + id, "Spam\u202E%d" % id), "192.168.1.66", _net_clock[0])
	check("the LAN list is capped", browser.games.size() == LanBrowser.MAX_GAMES, "%d entries" % browser.games.size())
	check("LAN names are cleaned", browser.games.values().all(func(g: Dictionary) -> bool: return not String(g.name).contains("\u202E")))
	browser.stop()
	await process_frame


func _announce_bytes(sent: int, id: int, name: String) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(NetPeer.T_ANNOUNCE)
	out.put_u32(sent)
	out.put_u16(NetPeer.PROTOCOL)
	out.put_utf8_string("1.0")
	out.put_u32(42)
	out.put_u32(id)
	out.put_u8(0)
	out.put_u16(7777)
	out.put_utf8_string(name)
	return out.data_array


## Key exchange and sealed packets.
func crypto_tests() -> void:
	# Someone in the middle who runs their own key exchange with each side: the two
	# players' codes differ (each pair agrees internally), so comparing them exposes it.
	var real_host := _net_peer("1.0", 42, "Host")
	real_host.host(0)
	var mitm_guest := _net_peer("1.0", 42, "Guest")
	mitm_guest.join("127.0.0.1", real_host.local_port())
	var mitm_host := _net_peer("1.0", 42, "Host")
	mitm_host.host(0)
	var real_guest := _net_peer("1.0", 42, "Guest")
	real_guest.join("127.0.0.1", mitm_host.local_port())
	_pump([real_host, mitm_guest, mitm_host, real_guest], 40)
	check("a man in the middle connects to both sides", real_host.is_connected_to_peer() and real_guest.is_connected_to_peer()
		and mitm_host.is_connected_to_peer() and mitm_guest.is_connected_to_peer())
	check("...but the two players' security codes differ", real_host.security_code != real_guest.security_code
		and real_host.security_code == mitm_guest.security_code and real_guest.security_code == mitm_host.security_code,
		"host %s, guest %s" % [real_host.security_code, real_guest.security_code])
	for peer: NetPeer in [mitm_guest, mitm_host, real_guest]:
		peer.close()

	# Sealed packets: unreadable, tamper-proof, no replays.
	var host := real_host
	var guest := _net_peer("1.0", 42, "G")
	host.close()
	host = _net_peer("1.0", 42, "H")
	host.host(0)
	guest.join("127.0.0.1", host.local_port())
	_pump([host, guest], 40)
	var secret_text := "SECRET-INPUTS-1234".to_utf8_buffer()
	var sealed := guest._seal(NetPeer.T_INPUT, secret_text)
	var readable := false
	for i in sealed.size() - secret_text.size():
		if sealed.slice(i, i + secret_text.size()) == secret_text:
			readable = true
	check("sealed packets don't show their contents", not readable and host._open(sealed) == secret_text)
	check("a replayed packet is refused", host._open(sealed) == null)
	var tampered := guest._seal(NetPeer.T_INPUT, secret_text)
	tampered[NetPeer.SEALED_HEADER + 3] ^= 0x01
	check("a tampered packet is refused", host._open(tampered) == null)
	var later := guest._seal(NetPeer.T_INPUT, PackedByteArray([1]))
	var earlier_ok := guest._seal(NetPeer.T_INPUT, PackedByteArray([2]))
	var newest := guest._seal(NetPeer.T_INPUT, PackedByteArray([3]))
	check("out-of-order packets inside the window still arrive", host._open(newest) != null and host._open(later) != null and host._open(earlier_ok) != null)
	var forged_type := guest._seal(NetPeer.T_INPUT, secret_text)
	forged_type[0] = NetPeer.T_BYE # the type byte is covered by the tag too
	host._receive(forged_type, host.remote_ip, host.remote_port, _net_clock[0])
	check("changing a packet's type breaks its tag", host.is_connected_to_peer())
	var own := host._seal(NetPeer.T_INPUT, secret_text)
	check("a packet can't be bounced back to its sender (keys per direction)", host._open(own) == null)
	var inputs_seen: Array[PackedByteArray] = []
	host.input_received.connect(func(b: PackedByteArray) -> void: inputs_seen.append(b))
	guest.send_input(PackedByteArray([7, 7, 7]))
	_pump([host, guest], 5)
	check("real traffic flows through the encryption", inputs_seen.size() == 1 and inputs_seen[0] == PackedByteArray([7, 7, 7]))
	host.close()
	guest.close()

	# The host decrypts only the first KEY: a bogus one first means no connection (and no
	# decryption oracle), not a crash.
	var h2 := _net_peer("1.0", 42, "H2")
	h2.host(0)
	var g2 := _net_peer("1.0", 42, "G2")
	g2.join("127.0.0.1", h2.local_port())
	for i in 30: # until the guest has the WELCOME (and sent its KEY), before the host reads it
		if g2.status == NetPeer.Status.SECURING:
			break
		_net_clock[0] += 16
		h2.poll()
		OS.delay_usec(300)
		g2.poll()
		OS.delay_usec(300)
	var bogus_sent := g2.status == NetPeer.Status.SECURING and h2.status == NetPeer.Status.SECURING
	if bogus_sent:
		var bogus := PackedByteArray()
		bogus.resize(2)
		bogus.encode_u16(0, NetPeer.KEY_CIPHER_SIZE)
		var junk := Crypto.new().generate_random_bytes(NetPeer.KEY_CIPHER_SIZE + 16)
		bogus.append_array(junk)
		var forged_key := PackedByteArray([NetPeer.T_KEY])
		forged_key.resize(9)
		forged_key.encode_u64(1, h2._token)
		forged_key.append_array(bogus)
		h2._receive(forged_key, h2.remote_ip, h2.remote_port, _net_clock[0])
	_pump([h2, g2], 30)
	check("a bogus KEY before the real one blocks the exchange (one decryption per connection)", bogus_sent and not h2.is_connected_to_peer()
		and not g2.is_connected_to_peer(), "injected %s, host status %s" % [bogus_sent, h2.status])
	h2.close()
	g2.close()

	# A forged KEYOK (wrong nonce) makes the guest give up rather than accept bad keys.
	var h3 := _net_peer("1.0", 42, "H3")
	h3.host(0)
	var g3 := _net_peer("1.0", 42, "G3")
	var failed := [""]
	g3.connect_failed.connect(func(r: String) -> void: failed[0] = r)
	g3.join("127.0.0.1", h3.local_port())
	for i in 30: # until the guest is waiting for KEYOK, before the host has answered
		if g3.status == NetPeer.Status.SECURING:
			break
		_net_clock[0] += 16
		h3.poll()
		OS.delay_usec(300)
		g3.poll()
		OS.delay_usec(300)
	if g3.status == NetPeer.Status.SECURING:
		var fake_ok := PackedByteArray([NetPeer.T_KEYOK])
		fake_ok.resize(9)
		fake_ok.encode_u64(1, g3._token)
		fake_ok.append_array(Crypto.new().generate_random_bytes(16))
		g3._receive(fake_ok, g3.remote_ip, g3.remote_port, _net_clock[0])
	check("a forged KEYOK fails the security check", failed[0].contains("security"), "%s (status %s)" % [failed[0], g3.status])
	h3.close()
	g3.close()


# --- Internet lobby server (client side) -----------------------------------------------

## A stand-in for the lobby server's UDP side (rendezvous + relay, AGENTS.md section 7):
## BIND → BOUND with the address seen, RELAY [key] → RELAYED to the other player.
class FakeRendezvous:
	var socket := PacketPeerUDP.new()
	var endpoints := {} # token hex -> [ip, port]
	var keys := {} # relay key hex -> token hex of the sender
	var peer_of := {} # token hex -> token hex
	var relayed := 0
	var binds := []

	func _init() -> void:
		socket.bind(0, "127.0.0.1")

	func port() -> int:
		return socket.get_local_port()

	## Registers a matched pair: [token, key] for the host and the guest.
	func pair(host_token: PackedByteArray, host_key: PackedByteArray, guest_token: PackedByteArray, guest_key: PackedByteArray) -> void:
		keys[host_key.hex_encode()] = host_token.hex_encode()
		keys[guest_key.hex_encode()] = guest_token.hex_encode()
		peer_of[host_token.hex_encode()] = guest_token.hex_encode()
		peer_of[guest_token.hex_encode()] = host_token.hex_encode()

	func poll() -> void:
		while socket.get_available_packet_count() > 0:
			var bytes := socket.get_packet()
			var ip := socket.get_packet_ip()
			var from := socket.get_packet_port()
			if bytes.is_empty():
				continue
			if bytes[0] == NetPeer.S_BIND and bytes.size() >= 19:
				binds.append(bytes)
				var token := bytes.slice(1, 17).hex_encode()
				if not peer_of.has(token):
					continue
				endpoints[token] = [ip, from]
				var bound := PackedByteArray([NetPeer.S_BOUND])
				for part in ip.split("."):
					bound.append(int(part))
				bound.resize(7)
				bound.encode_u16(5, from)
				socket.set_dest_address(ip, from)
				socket.put_packet(bound)
			elif bytes[0] == NetPeer.S_RELAY and bytes.size() > 9:
				var sender: String = keys.get(bytes.slice(1, 9).hex_encode(), "")
				if sender == "" or endpoints.get(sender, []) != [ip, from]:
					continue # unknown key, or not from the address that bound it
				var to: Array = endpoints.get(peer_of[sender], [])
				if to.is_empty():
					continue
				var out := PackedByteArray([NetPeer.S_RELAYED])
				out.append_array(bytes.slice(9))
				socket.set_dest_address(to[0], to[1])
				socket.put_packet(out)
				relayed += 1


## A "direct path" between the guest and the host that can fail: it forwards both ways,
## but lets only the host's first `pass_from_host` replies through (-1 = all), and drops
## everything once `blocked`. The host sees it as the guest's address (127.0.0.1).
class FakeForward:
	var socket := PacketPeerUDP.new()
	var host_port := 0
	var guest := []
	var from_host := 0
	var pass_from_host := -1
	var blocked := false

	func _init(port_of_host: int) -> void:
		host_port = port_of_host
		socket.bind(0, "127.0.0.1")

	func port() -> int:
		return socket.get_local_port()

	func poll() -> void:
		while socket.get_available_packet_count() > 0:
			var bytes := socket.get_packet()
			var ip := socket.get_packet_ip()
			var from := socket.get_packet_port()
			if blocked:
				continue
			if from == host_port:
				from_host += 1
				if guest.is_empty() or (pass_from_host >= 0 and from_host > pass_from_host):
					continue
				socket.set_dest_address(guest[0], guest[1])
			else:
				guest = [ip, from]
				socket.set_dest_address("127.0.0.1", host_port)
			socket.put_packet(bytes)


## Host and guest matched through a FakeRendezvous, the guest's only candidate being a
## FakeForward to the host. Returns {fake, fwd, host, guest}.
func _forwarded_pair(pass_from_host: int) -> Dictionary:
	var fake := FakeRendezvous.new()
	var host := _net_peer("1.0", 42, "FwdHost")
	var guest := _net_peer("1.0", 42, "FwdGuest")
	host.auto_accept = false
	guest.auto_accept = false
	var tokens := [Crypto.new().generate_random_bytes(16), Crypto.new().generate_random_bytes(16)]
	var keys := [Crypto.new().generate_random_bytes(8), Crypto.new().generate_random_bytes(8)]
	fake.pair(tokens[0], keys[0], tokens[1], keys[1])
	host.host(0)
	guest.join_via_server()
	var secret := Crypto.new().generate_random_bytes(16)
	host.use_server("127.0.0.1", fake.port(), tokens[0], keys[0], true, secret)
	guest.use_server("127.0.0.1", fake.port(), tokens[1], keys[1], false, secret)
	var fwd := FakeForward.new(host.local_port())
	fwd.pass_from_host = pass_from_host
	for i in 10:
		_pump([host, guest, fake, fwd], 1)
	guest.set_peer_candidates([{ip = "127.0.0.1", port = fwd.port()}], 100)
	host.set_peer_candidates([{ip = "127.0.0.1", port = guest.local_port()}], 100)
	return {fake = fake, fwd = fwd, host = host, guest = guest}


## Two NetPeers matched through a FakeRendezvous; `candidates` decides the path:
## "relay" (none: the relay only), "direct" (each other's real address) or "dead" (an
## address nobody answers: the guest must give up on it and fall back to the relay).
## `guest_secret`: the guest's pair_secret is the host's ("same"), another one ("wrong"),
## missing ("none"), or neither has one ("legacy": a server that doesn't send it).
func _server_pair(candidates: String, guest_secret := "same") -> Dictionary:
	var fake := FakeRendezvous.new()
	var host := _net_peer("1.0", 42, "NetHost")
	var guest := _net_peer("1.0", 42, "NetGuest")
	host.auto_accept = false # the server already asked: no prompt needed, nobody else gets in
	guest.auto_accept = false
	var tokens := [Crypto.new().generate_random_bytes(16), Crypto.new().generate_random_bytes(16)]
	var keys := [Crypto.new().generate_random_bytes(8), Crypto.new().generate_random_bytes(8)]
	fake.pair(tokens[0], keys[0], tokens[1], keys[1])
	host.host(0)
	guest.join_via_server()
	var secret := PackedByteArray() if guest_secret == "legacy" else Crypto.new().generate_random_bytes(16)
	var theirs: PackedByteArray = {same = secret, wrong = Crypto.new().generate_random_bytes(16)}.get(guest_secret, PackedByteArray())
	host.use_server("127.0.0.1", fake.port(), tokens[0], keys[0], true, secret)
	guest.use_server("127.0.0.1", fake.port(), tokens[1], keys[1], false, theirs)
	for i in 10:
		_pump([host, guest, fake], 1)
	var bound := host.bound and guest.bound
	var to_host := []
	var to_guest := []
	if candidates == "direct":
		to_host = [{ip = "127.0.0.1", port = host.local_port()}]
		to_guest = [{ip = "127.0.0.1", port = guest.local_port()}]
	elif candidates == "dead":
		var dead := PacketPeerUDP.new()
		dead.bind(0, "127.0.0.1")
		to_host = [{ip = "127.0.0.1", port = dead.get_local_port()}]
		dead.close() # nothing listens there now
	guest.set_peer_candidates(to_host, 100)
	host.set_peer_candidates(to_guest, 100)
	var rounds := 0
	while rounds < 400 and not (host.is_connected_to_peer() and guest.is_connected_to_peer()):
		_pump([host, guest, fake], 1)
		rounds += 1
	return {fake = fake, host = host, guest = guest, bound = bound, rounds = rounds}


## A tiny stand-in for the lobby server's WebSocket side: accepts connections, answers
## hello with welcome (counting resumes) and ping with pong, and can send anything.
class FakeLobby:
	var tcp := TCPServer.new()
	var ws: WebSocketPeer
	var hellos: Array[Dictionary] = []
	var received: Array[Dictionary] = []
	var binary: Array[PackedByteArray] = []

	func _init() -> void:
		tcp.listen(0, "127.0.0.1")

	func url() -> String:
		return "ws://127.0.0.1:%d/v1/ws" % tcp.get_local_port()

	func poll() -> void:
		if tcp.is_connection_available():
			ws = WebSocketPeer.new()
			ws.supported_protocols = PackedStringArray([LobbyClient.SUBPROTOCOL])
			ws.accept_stream(tcp.take_connection())
		if ws == null:
			return
		ws.poll()
		while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			var bytes := ws.get_packet()
			if not ws.was_string_packet():
				binary.append(bytes)
				continue
			var msg: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
			received.append(msg)
			match msg.type:
				"hello":
					hellos.append(msg)
					send({type = "welcome", protocol = 1, session_id = "s_1", resume_token = "tok%d" % hellos.size(),
						server_time = 5000000, region = "test", udp = {host = "127.0.0.1", port = 7780},
						limits = {max_room_name = 32, max_spectators = 50, reaction_interval_ms = 2000}})
				"ping":
					send({type = "pong", t = msg.t, server_time = 5000000})

	func send(msg: Dictionary) -> void:
		ws.send_text(JSON.stringify(msg))


func _lobby_pump(lobby: FakeLobby, client: LobbyClient, rounds: int, until := Callable()) -> void:
	for i in rounds:
		_net_clock[0] += 16
		lobby.poll()
		client.poll()
		if until.is_valid() and until.call():
			return
		OS.delay_msec(2)


func server_tests() -> void:
	var gs = root.get_node("GameState")
	var net = root.get_node("Net")

	# Feed frames: the byte layout from the server's AGENTS.md (its conformance vector).
	var vector := SpectatorFeed.inputs(7, 0, PackedInt32Array([0x16, 0x16]), PackedInt32Array([5, 5]))
	check("feed INPUTS matches the protocol vector", vector.hex_encode() == "02070000000000000002001600050016000500", vector.hex_encode())
	var decoded := SpectatorFeed.decode(vector)
	check("feed INPUTS decodes", decoded.get("type") == SpectatorFeed.F_INPUTS and decoded.match_id == 7 and decoded.first == 0
		and decoded.p1 == PackedInt32Array([0x16, 0x16]) and decoded.p2 == PackedInt32Array([5, 5]))
	var long_name := "龍".repeat(30) # 90 bytes of UTF-8: cut to whole characters within 64
	var start := SpectatorFeed.decode(SpectatorFeed.match_start(0xDEADBEEF, 4, 4, 3,
		PackedStringArray(["0.4.1", "beach", "jin", "valka", long_name, "Lufi" + char(0x202E)])))
	check("feed MATCH_START round trip (long names cut, names cleaned)", start.get("match_id") == 0xDEADBEEF and start.stage == 4
		and start.p1_id == "jin" and start.p2_id == "valka" and start.p1_name == "龍".repeat(21).left(24) and start.p2_name == "Lufi",
		"%s / %s" % [start.get("p1_name"), start.get("p2_name")])
	var bad_bits := SpectatorFeed.inputs(1, 0, PackedInt32Array([0x205]), PackedInt32Array([5]))
	var no_dir := SpectatorFeed.inputs(1, 0, PackedInt32Array([0x10]), PackedInt32Array([5]))
	check("feed decoding refuses bad input words, sizes and versions", SpectatorFeed.decode(bad_bits).is_empty()
		and SpectatorFeed.decode(no_dir).is_empty() and SpectatorFeed.decode(vector.slice(0, vector.size() - 1)).is_empty()
		and SpectatorFeed.decode(SpectatorFeed.checksum(1, 60, 5) + PackedByteArray([0])).is_empty()
		and SpectatorFeed.decode(PackedByteArray([1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])).is_empty())
	var garbage_errors := errors.count
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 400:
		var junk := PackedByteArray()
		junk.resize(rng.randi_range(0, 80))
		for j in junk.size():
			junk[j] = rng.randi() % 256
		if i % 3 == 0 and junk.size() > 0:
			junk[0] = rng.randi_range(1, 5)
		SpectatorFeed.decode(junk)
	check("feed decoding survives garbage without errors", errors.count == garbage_errors)

	# Publish a real netplay match and replay it as a spectator from the feed alone.
	gs.mode = gs.Mode.VERSUS # the players' fights (the simulation is the same as online)
	gs.player_character = gs.roster[0]
	gs.p2_character = gs.roster[4]
	gs.stage_path = gs.stage_paths()[2]
	gs.match_seed = 4242
	const TICKS := 1300
	var inputs := [_net_inputs(TICKS + 40, 31, true), _net_inputs(TICKS + 40, 32, false)]
	var fights := [_net_fight(), _net_fight()]
	var sessions := [RollbackSession.new(fights[0], 0, 2, 4242), RollbackSession.new(fights[1], 1, 2, 4242)]
	var frames: Array[PackedByteArray] = []
	var publisher := SpectatorFeed.Publisher.new(sessions[0], func(b: PackedByteArray) -> void: frames.append(b))
	# A second publisher flushing every tick, right after packets confirm new inputs:
	# a checksum's tick can then be published before the session has computed it.
	var eager_sums := {}
	var eager := SpectatorFeed.Publisher.new(sessions[1], func(b: PackedByteArray) -> void:
		var f := SpectatorFeed.decode(b)
		if f.get("type") == SpectatorFeed.F_CHECKSUM:
			eager_sums[f.tick] = f.checksum)
	publisher.start(2, 0, 4, PackedStringArray([gs.game_version(), "rooftop", "kenji", "jin", "Host", "Guest"]))
	var in_flight := [[], []]
	var real := 0
	while real < TICKS * 3 and sessions[0].confirmed_frame() < TICKS - 1:
		real += 1
		for i in 2:
			var s: RollbackSession = sessions[i]
			var index := s.frame + 2
			s.advance(inputs[i][index] if index < inputs[i].size() else InputBuffer.pack(5, 0))
			in_flight[1 - i].append([real + 3 + (real * 7 + i) % 3, s.make_packet()]) # ~50 ms with jitter: rollbacks happen
		for i in 2:
			var still := []
			for packet: Array in in_flight[i]:
				if packet[0] <= real:
					sessions[i].receive_packet(packet[1])
				else:
					still.append(packet)
			in_flight[i] = still
		publisher.update(real * 16)
		eager.update(real * 1000)
	publisher.finish(SpectatorFeed.Result.DRAW, 0, 0, real * 16)
	eager.finish(SpectatorFeed.Result.DRAW, 0, 0, real * 1000)
	var guest_due := (sessions[1] as RollbackSession).checksums.keys().filter(func(t: int) -> bool: return t <= eager.published)
	check("a publisher flushing every tick still sends every checksum", guest_due.size() >= TICKS / 60
		and guest_due.all(func(t: int) -> bool: return eager_sums.get(t) == sessions[1].checksums[t]),
		"%d of %d" % [eager_sums.size(), guest_due.size()])
	var host_sums: Dictionary = (sessions[0] as RollbackSession).checksums.duplicate()
	check("the published match had rollbacks to hide", sessions[0].rollbacks + sessions[1].rollbacks > 0)
	for f in fights:
		f.queue_free()
	var log := SpectatorFeed.Log.new()
	var fitted := frames.all(func(b: PackedByteArray) -> bool: return log.add(SpectatorFeed.decode(b)))
	check("every published frame is valid and contiguous", fitted and log.ticks() == publisher.published and log.ticks() >= TICKS
		and not log.end.is_empty() and log.end.final_tick == log.ticks(), "%d frames, %d ticks" % [frames.size(), log.ticks()])
	var due := host_sums.keys().filter(func(t: int) -> bool: return t <= log.ticks())
	check("feed carries every host checksum up to the last published tick", due.size() >= TICKS / 60
		and due.all(func(t: int) -> bool: return log.checksums.get(t) == host_sums[t]),
		"%d of %d" % [due.filter(func(t: int) -> bool: return log.checksums.has(t)).size(), due.size()])
	var input_bytes := 0
	for b in frames:
		if b[0] == SpectatorFeed.F_INPUTS:
			input_bytes += b.size()
	check("feed is small (about 4 bytes a tick)", input_bytes < log.ticks() * 6, "%d bytes for %d ticks" % [input_bytes, log.ticks()])

	# The fight scene makes its own SpectatorMatch when Net is spectating (ONLINE mode).
	gs.mode = gs.Mode.ONLINE
	net.spectating = true
	net.feed = log
	var watch := _net_fight()
	var spectator: Node = watch.netplay
	spectator.set_physics_process(false)
	check("watching uses a SpectatorMatch", spectator.name == "SpectatorMatch")
	var guard := 0
	while spectator.frame < log.ticks() and not spectator.ended and guard < 2000:
		spectator._physics_process(0.0)
		guard += 1
	check("a late spectator replays the whole match from the feed", spectator.frame >= log.ticks() and not spectator.diverged
		and spectator.checks_passed == log.checksums.size(), "frame %d / %d, %d of %d checks, %d calls" % [spectator.frame, log.ticks(),
		spectator.checks_passed, log.checksums.size(), guard])
	check("the spectator caught up fast (fast-forward)", guard < log.ticks() / 4, "%d calls" % guard)
	var behind: int = spectator.frame
	for i in 30:
		spectator._physics_process(0.0)
	check("after MATCH_END the spectator plays on (victory scene)", spectator.frame == behind + 30 and not spectator.ended)
	watch.queue_free()

	# A tampered feed (one input changed) is caught by the next checksum.
	var tampered := SpectatorFeed.Log.new()
	for b in frames:
		tampered.add(SpectatorFeed.decode(b))
	tampered.p1[200] = InputBuffer.pack(9, InputBuffer.HK) if tampered.p1[200] != InputBuffer.pack(9, InputBuffer.HK) else InputBuffer.pack(1, 0)
	tampered.p2[201] = InputBuffer.pack(3, InputBuffer.HP)
	net.feed = tampered
	var watch2 := _net_fight()
	var spectator2: Node = watch2.netplay
	spectator2.set_physics_process(false)
	var warnings := errors.count
	guard = 0
	while not spectator2.ended and spectator2.frame < tampered.ticks() and guard < 2000:
		spectator2._physics_process(0.0)
		guard += 1
	check("a feed that doesn't match the host's checksums stops the replay", spectator2.diverged and spectator2.frame <= 300,
		"diverged %s at %d" % [spectator2.diverged, spectator2.frame])
	errors.count = warnings # the divergence warning is expected
	watch2.queue_free()
	net.spectating = false
	net.feed = SpectatorFeed.Log.new()
	var ours := SpectatorFeed.decode(SpectatorFeed.match_start(1, 0, 0, 1, PackedStringArray([gs.game_version(), "ring",
		str(gs.roster[0].id), str(gs.roster[1].id), "A", "B"])))
	var other_version := ours.duplicate()
	other_version.game_version = "0.0.1"
	var other_fighter := ours.duplicate()
	other_fighter.p2_id = "nobody"
	check("watch_problem accepts this version and refuses others", net.watch_problem(ours) == ""
		and net.watch_problem(other_version) != "" and net.watch_problem(other_fighter) != "")
	await process_frame

	# NetPeer through the lobby server's rendezvous: the relay, direct, and a dead address.
	_wait_host_key()
	var relay := _server_pair("relay")
	var rh: NetPeer = relay.host
	var rg: NetPeer = relay.guest
	var fake: FakeRendezvous = relay.fake
	check("both players BIND and get BOUND", relay.bound and rh.public_endpoint.begins_with("127.0.0.1:") and rg.public_endpoint.begins_with("127.0.0.1:"),
		"%s / %s" % [rh.public_endpoint, rg.public_endpoint])
	var bind: PackedByteArray = fake.binds[0]
	check("BIND is token, role and up to 4 LAN candidates", bind.size() == 19 + bind[18] * 6 and bind[18] <= 4 and bind[17] <= 1)
	check("no addresses: the players connect through the relay", rh.is_connected_to_peer() and rg.is_connected_to_peer()
		and rh.connection_path() == "relay" and rg.connection_path() == "relay" and fake.relayed > 4,
		"%s / %s, %d relayed" % [rh.status, rg.status, fake.relayed])
	check("the relayed connection is encrypted end to end (same security code)", rh.security_code != "" and rh.security_code == rg.security_code)
	var got := [""]
	rg.message_received.connect(func(_t: int, p: PackedByteArray) -> void: got[0] = p.get_string_from_utf8())
	rh.send_reliable(9, "through the relay".to_utf8_buffer())
	_pump([rh, rg, fake], 10)
	check("lobby messages cross the relay", got[0] == "through the relay")
	# A stranger can't use the host's open port: in server mode only the matched peer gets in.
	var strangers := _probe(rh, _hello_bytes("1.0", 42, "Stranger", 5, 0))
	check("an internet host ignores everyone it wasn't matched with", strangers.is_empty(), "%d replies" % strangers.size())
	var before := fake.relayed
	rg.close()
	_pump([rh, rg, fake], 10)
	check("BYE goes through the relay too", rh.status == NetPeer.Status.CLOSED and fake.relayed > before)
	rh.close()

	var direct := _server_pair("direct")
	var dh: NetPeer = direct.host
	var dg: NetPeer = direct.guest
	check("with each other's address the players connect directly (hole punched)", dh.is_connected_to_peer() and dg.is_connected_to_peer()
		and dh.connection_path() == "direct" and dg.connection_path() == "direct" and (direct.fake as FakeRendezvous).relayed == 0,
		"%s / %s via %s, %d relayed" % [dh.status, dg.status, dg.connection_path(), direct.fake.relayed])
	check("direct connection security codes match", dh.security_code != "" and dh.security_code == dg.security_code)
	dh.close()
	dg.close()

	var dead := _server_pair("dead")
	check("an address that never answers falls back to the relay after %d ms" % NetPeer.PUNCH_TIMEOUT_MS,
		dead.host.is_connected_to_peer() and dead.guest.is_connected_to_peer() and dead.guest.connection_path() == "relay"
		and dead.rounds * 16 >= NetPeer.PUNCH_TIMEOUT_MS, "%s via %s after %d rounds" % [dead.guest.status, dead.guest.connection_path(), dead.rounds])
	dead.host.close()
	dead.guest.close()

	# pair_secret: only the player the server gave it to gets in, even from the right address.
	for kind in ["wrong", "none"]:
		var outsider := _server_pair("direct", kind)
		check("a HELLO with a %s pair_secret proof is ignored (direct and relay)" % kind,
			not outsider.host.is_connected_to_peer() and not outsider.guest.is_connected_to_peer()
			and outsider.host.status == NetPeer.Status.HOSTING and outsider.host.remote_ip == "",
			"%s / %s, host talking to '%s'" % [outsider.host.status, outsider.guest.status, outsider.host.remote_ip])
		outsider.host.close()
		outsider.guest.close()
	var legacy := _server_pair("direct", "legacy")
	check("a server without pair_secret still connects the players", legacy.host.is_connected_to_peer()
		and legacy.guest.is_connected_to_peer() and legacy.host.security_code == legacy.guest.security_code)
	legacy.host.close()
	legacy.guest.close()
	# A proof seen on the wire can't be reused from another address (it's tied to the cookie):
	# otherwise the "same guest on another path" restart would hand the exchange to a stranger.
	var paired := _net_peer("1.0", 42, "PairHost")
	paired.auto_accept = false
	paired.host(0)
	paired.use_server("127.0.0.1", 9, Crypto.new().generate_random_bytes(16), Crypto.new().generate_random_bytes(8), true,
		Crypto.new().generate_random_bytes(16))
	paired.set_peer_candidates([{ip = "127.0.0.1", port = 9}], 0)
	var matched := PacketPeerUDP.new()
	var thief := PacketPeerUDP.new()
	var nonce := 0x51C0FFEE
	var cookie_of := func(sock: PacketPeerUDP) -> int:
		sock.put_packet(_hello_bytes("1.0", 42, "X", nonce, 0))
		for i in 6:
			OS.delay_usec(300)
			paired.poll()
		while sock.get_available_packet_count() > 0:
			var reply := sock.get_packet()
			if reply.size() == 17 and reply[0] == NetPeer.T_CHALLENGE:
				return reply.decode_u64(9)
		return 0
	var send_hello := func(sock: PacketPeerUDP, cookie: int, proof: PackedByteArray) -> void:
		var hello := _hello_bytes("1.0", 42, "X", nonce, cookie)
		hello.append_array(proof)
		sock.put_packet(hello)
		for i in 6:
			OS.delay_usec(300)
			paired.poll()
	for sock: PacketPeerUDP in [matched, thief]:
		sock.bind(0, "127.0.0.1")
		sock.set_dest_address("127.0.0.1", paired.local_port())
	var matched_cookie: int = cookie_of.call(matched)
	var matched_proof: PackedByteArray = paired._pair_proof(nonce, matched_cookie)
	send_hello.call(matched, matched_cookie, matched_proof)
	var with_matched := paired.status == NetPeer.Status.SECURING and paired.remote_port == matched.get_local_port()
	var thief_cookie: int = cookie_of.call(thief)
	send_hello.call(thief, thief_cookie, matched_proof)
	var kept := paired.remote_port == matched.get_local_port()
	send_hello.call(thief, thief_cookie, paired._pair_proof(nonce, thief_cookie))
	var moved := paired.remote_port == thief.get_local_port() # control: a valid proof does move it
	check("a replayed pair_secret proof can't move the key exchange to another address", with_matched and kept and moved,
		"secured with the guest %s, kept %s, valid proof moves it %s" % [with_matched, kept, moved])
	matched.close()
	thief.close()
	paired.close()

	# A direct path that answers once and then stalls: the guest must not stay stuck on it.
	var stall := _forwarded_pair(1)
	var sh: NetPeer = stall.host
	var sg: NetPeer = stall.guest
	var stall_fail := [""]
	sg.connect_failed.connect(func(r: String) -> void: stall_fail[0] = r)
	var locked_direct := false
	var rounds := 0
	while rounds < 900 and not (sh.is_connected_to_peer() and sg.is_connected_to_peer()) and stall_fail[0] == "":
		_pump([sh, sg, stall.fake, stall.fwd], 1)
		locked_direct = locked_direct or (sg.remote_ip == "127.0.0.1")
		rounds += 1
	check("a direct path that stalls after one reply falls back to the relay", locked_direct and sh.is_connected_to_peer()
		and sg.is_connected_to_peer() and sg.connection_path() == "relay" and stall_fail[0] == ""
		and rounds * 16 >= NetPeer.DIRECT_DEADLINE_MS,
		"locked %s, %s / %s via %s after %d ms, failure '%s'" % [locked_direct, sh.status, sg.status, sg.connection_path(), rounds * 16, stall_fail[0]])
	check("the restarted exchange still agrees on one security code", sh.security_code != "" and sh.security_code == sg.security_code)
	sh.close()
	sg.close()

	# A direct path that dies during a match: both players carry on through the relay.
	var mid := _forwarded_pair(-1)
	var mh: NetPeer = mid.host
	var mg: NetPeer = mid.guest
	rounds = 0
	while rounds < 400 and not (mh.is_connected_to_peer() and mg.is_connected_to_peer()):
		_pump([mh, mg, mid.fake, mid.fwd], 1)
		rounds += 1
	var was_direct := mg.connection_path() == "direct" and mh.connection_path() == "direct"
	var dropped := [""]
	var paths: Array[String] = []
	mh.disconnected.connect(func(r: String) -> void: dropped[0] = "host: " + r)
	mg.disconnected.connect(func(r: String) -> void: dropped[0] = "guest: " + r)
	mh.path_changed.connect(func(p: String) -> void: paths.append("host " + p))
	mg.path_changed.connect(func(p: String) -> void: paths.append("guest " + p))
	var got_mid := [""]
	mg.message_received.connect(func(_t: int, payload: PackedByteArray) -> void: got_mid[0] = payload.get_string_from_utf8())
	(mid.fwd as FakeForward).blocked = true # the direct path goes dead
	mh.send_reliable(9, "after the failover".to_utf8_buffer())
	for i in 800: # 12.8 s: longer than the 10 s connection timeout
		_pump([mh, mg, mid.fake, mid.fwd], 1)
	check("a direct path that dies mid-match moves both players to the relay", was_direct and dropped[0] == ""
		and mh.is_connected_to_peer() and mg.is_connected_to_peer() and mh.connection_path() == "relay" and mg.connection_path() == "relay",
		"was direct %s, now %s / %s, lost '%s', switches %s" % [was_direct, mh.connection_path(), mg.connection_path(), dropped[0], paths])
	check("messages keep arriving after the failover", got_mid[0] == "after the failover", got_mid[0])
	mh.close()
	mg.close()

	# A guest whose server never sends the host's addresses gives up.
	var lonely := _net_peer("1.0", 42, "Lonely")
	var lonely_fail := [""]
	lonely.connect_failed.connect(func(r: String) -> void: lonely_fail[0] = r)
	lonely.join_via_server()
	lonely.use_server("127.0.0.1", 9, Crypto.new().generate_random_bytes(16), Crypto.new().generate_random_bytes(8), false)
	for i in 1000:
		_net_clock[0] += 16
		lonely.poll()
		if lonely_fail[0] != "":
			break
	check("no peer endpoints from the server: the join gives up", lonely_fail[0] != "", lonely_fail[0])
	lonely.close()

	# LobbyClient against a stand-in WebSocket server.
	var lobby_server := FakeLobby.new()
	var client := LobbyClient.new()
	client.clock = func() -> int: return _net_clock[0]
	var welcomed := [{}]
	var lost := [""]
	var messages: Array[Dictionary] = []
	var feed_in: Array[PackedByteArray] = []
	client.connected.connect(func(w: Dictionary) -> void: welcomed[0] = w)
	client.disconnected.connect(func(r: String) -> void: lost[0] = r)
	client.message.connect(func(m: Dictionary) -> void: messages.append(m))
	client.feed_frame.connect(func(b: PackedByteArray) -> void: feed_in.append(b))
	client.open(lobby_server.url(), {game_version = "1.0", content_hash = 42, client_id = "c-1", name = "Tester"})
	_lobby_pump(lobby_server, client, 300, func() -> bool: return client.is_open())
	check("LobbyClient says hello and gets welcome", client.is_open() and welcomed[0].get("region") == "test"
		and lobby_server.hellos.size() == 1 and lobby_server.hellos[0].protocol == 1 and lobby_server.hellos[0].name == "Tester",
		"status %s" % client.status)
	check("LobbyClient learns the server clock", absi(client.server_now() - 5000000) < 1000)
	client.send("list_rooms", {status = "any"})
	lobby_server.send({type = "rooms", rooms = [{id = "r_1", name = "A"}]})
	lobby_server.ws.send(SpectatorFeed.checksum(3, 60, 9), WebSocketPeer.WRITE_MODE_BINARY)
	_lobby_pump(lobby_server, client, 100, func() -> bool: return not feed_in.is_empty() and not messages.is_empty())
	check("LobbyClient sends messages and passes on server messages and feed frames", lobby_server.received.any(func(m: Dictionary) -> bool:
		return m.type == "list_rooms") and messages.any(func(m: Dictionary) -> bool: return m.type == "rooms") and feed_in.size() == 1)
	_net_clock[0] += LobbyClient.KEEPALIVE_MS
	_lobby_pump(lobby_server, client, 50, func() -> bool: return lobby_server.received.any(func(m: Dictionary) -> bool: return m.type == "ping"))
	check("LobbyClient pings when it has been quiet (keeps the latency and clock fresh)", lobby_server.received.any(func(m: Dictionary) -> bool:
		return m.type == "ping"))
	# A dropped connection comes back with the resume token, without a second `connected`.
	lobby_server.ws.close(1001, "going away")
	_lobby_pump(lobby_server, client, 600, func() -> bool: return lobby_server.hellos.size() >= 2 and client.is_open())
	check("a dropped lobby connection resumes with the token", lobby_server.hellos.size() == 2
		and lobby_server.hellos[1].get("resume_token") == "tok1" and client.is_open() and lost[0] == "",
		"%d hellos, status %s, lost '%s'" % [lobby_server.hellos.size(), client.status, lost[0]])
	lobby_server.ws.close(4000, "banned")
	_lobby_pump(lobby_server, client, 300, func() -> bool: return lost[0] != "")
	check("a deliberate close from the server isn't retried", lost[0].contains("banned") and client.status == LobbyClient.Status.CLOSED, lost[0])
	client.close()
	lobby_server.tcp.stop()
	check("server error codes read as sentences", LobbyClient.error_text({code = "wrong_password"}) == "Wrong password"
		and LobbyClient.error_text({code = "something_new", message = "x"}) == "x")
	var lobby_screen: GDScript = load("res://scripts/ui/server_lobby.gd")
	check("the official server address comes from servers.json", lobby_screen.official_server(
		'{"version": 1, "servers": [{"name": "Asia", "url": "wss://lobby.example.com/v1/ws"}]}') == "wss://lobby.example.com/v1/ws"
		and lobby_screen.official_server('{"servers": [{"url": "http://evil"}, {"url": "ws://ok/v1/ws"}]}') == "ws://ok/v1/ws"
		and lobby_screen.official_server("not json") == "" and lobby_screen.official_server('{"servers": 5}') == "")
	var shipped := FileAccess.get_file_as_string("res://online/servers.json")
	check("online/servers.json in the repository names the default server", lobby_screen.official_server(shipped) == lobby_screen.DEFAULT_SERVER,
		lobby_screen.official_server(shipped))
	check("the lobby header reads the server's online counts", lobby_screen.online_text({players = 23, in_match = 6, spectating = 3, rooms = 7}) == "23 online  ·  6 in matches  ·  3 watching"
		and lobby_screen.online_text({players = 1, in_match = 0, spectating = 0, rooms = 0}) == "under 5 online"
		and lobby_screen.online_text({players = 4.0, in_match = 2, spectating = 2}) == "under 5 online"
		and lobby_screen.online_text({players = 5}) == "5 online",
		lobby_screen.online_text({players = 23, in_match = 6, spectating = 3, rooms = 7}))
	check("no online counts from an older server or bad data", lobby_screen.online_text(null) == "" and lobby_screen.online_text({}) == ""
		and lobby_screen.online_text("23") == "" and lobby_screen.online_text({players = "lots"}) == "" and lobby_screen.online_text({players = -5}) == ""
		and lobby_screen.online_text({players = 7, in_match = "x", spectating = [1]}) == "7 online")
	check("room codes are typed in any case", net._room_key(" kx7q2m ") == "KX7Q2M" and net._room_key("r_7f3a9c2e") == "r_7f3a9c2e")
	gs.mode = gs.Mode.VS_CPU
	await process_frame
