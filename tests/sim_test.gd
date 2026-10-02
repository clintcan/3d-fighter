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
	m._reset_round(); m.dummy.mode = mode; ctl.dir = 5; step(2)

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
	check("throw damages and knocks down", p2.health == hp - Fighter.THROW_DAMAGE and p2.state in [Fighter.State.AIR_HIT, Fighter.State.KNOCKDOWN], "hp %d %s" % [p2.health, state_name(p2)])
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
	check("KO on lethal hit", p2.state == Fighter.State.KO and m.ko_timer > 0, state_name(p2))
	step(m.KO_RESET_TICKS + 1)
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

	print("\n%d failure(s)" % fails)
	quit(1 if fails else 0)
