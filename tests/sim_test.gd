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
	check("counter hit: +25% damage", p2.health == hp - 38, "hp %d -> %d" % [hp, p2.health])
	p2.controller = dummy; ctl2.dir = 5; step(40)

	# Combo scaling: second hit of jab -> straight does 90%
	reset(D.STAND); approach(1.0)
	hp = p2.health
	press(InputBuffer.LP); step(5)
	press(InputBuffer.HP); step(20)
	check("combo scaling (30 + 80*0.9)", p2.health == hp - 102, "hp %d -> %d" % [hp, p2.health])

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
	await process_frame
	# Fixed matchup: per-character frame data makes timings depend on who's fighting.
	var gs = root.get_node("GameState")
	gs.player_character = gs.roster[0] # Kenji
	gs.p2_character = gs.roster[2] # Brutus
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
	check("jab hits", p2.health == hp - 30, "hp %d -> %d, p2 %s" % [hp, p2.health, state_name(p2)])

	# Chain jab -> straight via cancel
	reset(D.STAND); approach(1.0)
	press(InputBuffer.LP); step(5)
	press(InputBuffer.HP); step(20)
	check("jab -> straight cancel combo", p2.combo_hits == 2 or p2.health == p2.data.max_health - 110, "combo %d, hp %d" % [p2.combo_hits, p2.health])

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
	check("low kick (low) beats stand block", p2.health == hp - 35, "hp %d -> %d" % [hp, p2.health])

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
	await versus_tests()
	await training_tests()

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
	check("audio buses exist", AudioServer.get_bus_index("Music") > 0 and AudioServer.get_bus_index("SFX") > 0 and AudioServer.get_bus_index("Voice") > 0)

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
