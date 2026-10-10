extends SceneTree
## Balance simulator: CPU vs CPU matches for every pairing, played both ways round so the
## P1/P2 side doesn't bias the result, plus a frame-data audit of every move.
##
## Run: godot_console --headless --path . -s res://tools/balance_sim.gd -- [matches] [difficulty] [id]
##   matches     per ordered pairing (default 6; mirrors get the same)
##   difficulty  0 easy, 1 normal, 2 hard (default 2)
##   id          only the pairings that include this fighter (quicker re-checks; "all" for every one)
##   stage       a stage scene name (default ring: rope bounces; e.g. dojo for wall splats)
## Prints a win-rate matrix, per-fighter stats, and moves that are very unsafe on block.
## The CPU personalities shape the results, so treat them as a guide to outliers.

const TICK_CAP := 5 * 120 * 60 # up to five long rounds; a match never gets near this

var _stats := {} # id -> totals
var _matrix := {} # "a|b" -> [a wins, matches] (a vs b, either side)
var _m


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var matches := int(args[0]) if args.size() > 0 else 6
	var difficulty := int(args[1]) if args.size() > 1 else AIController.Difficulty.HARD
	await process_frame
	var gs = root.get_node("GameState")
	gs.mode = gs.Mode.VS_CPU
	gs.stage_path = "res://scenes/stages/%s.tscn" % args[3] if args.size() > 3 else gs.DEFAULT_STAGE
	var roster: Array = gs.roster
	for c: CharacterData in roster:
		_stats[c.id] = {name = c.display_name, matches = 0, wins = 0, rounds = 0, round_wins = 0,
			damage_dealt = 0, damage_taken = 0, perfects = 0, timeouts = 0, round_ticks = 0,
			specials = 0, specials_hit = 0, specials_blocked = 0, supers = 0, supers_hit = 0,
			throws = 0, grabs = 0, hits = 0, blocked = 0, counters = 0}
	var start := Time.get_ticks_msec()
	var only := args[2] if args.size() > 2 and args[2] != "all" else ""
	for a: CharacterData in roster:
		for b: CharacterData in roster:
			if only == "" or String(a.id) == only or String(b.id) == only:
				await _play_pairing(gs, a, b, matches, difficulty)
	print("\nSimulated in %d s" % ((Time.get_ticks_msec() - start) / 1000))
	_report(roster)
	_audit(roster)
	var out := FileAccess.open("user://balance_results.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({stats = _stats, matrix = _matrix, matches = matches, difficulty = difficulty}, "  "))
	out.close()
	print("
Raw results: %s" % ProjectSettings.globalize_path("user://balance_results.json"))
	quit()


func _play_pairing(gs, a: CharacterData, b: CharacterData, matches: int, difficulty: int) -> void:
	gs.player_character = a
	gs.p2_character = b
	change_scene_to_file("res://scenes/fight.tscn")
	await process_frame
	await process_frame
	_m = current_scene
	_m.set_physics_process(false)
	var p1: Fighter = _m.fighters[0]
	var p2: Fighter = _m.fighters[1]
	for i in matches:
		var seed_base := hash("%s|%s|%d" % [a.id, b.id, i])
		var ai1 := AIController.new(difficulty, seed_base)
		ai1.attach(p1)
		var ai2 := AIController.new(difficulty, seed_base + 7919)
		ai2.attach(p2)
		p1.controller = ai1
		p2.controller = ai2
		_m.start_match()
		_play_match(p1, p2, a, b)
	print("  %-7s vs %-7s done" % [a.display_name, b.display_name])


func _play_match(p1: Fighter, p2: Fighter, a: CharacterData, b: CharacterData) -> void:
	var fighters := [p1, p2]
	var ids := [a.id, b.id]
	var last_health := [p1.health, p2.health]
	var super_connected := [false, false] # count each super once, however many hits
	var round_start := 0
	var round_was := 1
	var connections := []
	var on_hit := func(attacker: Fighter, defender: Fighter, move: MoveData, result: Fighter.HitResult) -> void:
		var s: Dictionary = _stats[ids[fighters.find(attacker)]]
		if result == Fighter.HitResult.BLOCKED:
			s.blocked += 1
		else:
			s.hits += 1
			if result == Fighter.HitResult.COUNTER:
				s.counters += 1
		var side := fighters.find(attacker)
		if move.is_special() or move.input.begins_with("~"):
			if move.super_move or move.input.begins_with("~"):
				if result != Fighter.HitResult.BLOCKED and not super_connected[side]:
					super_connected[side] = true
					s.supers_hit += 1
			elif result == Fighter.HitResult.BLOCKED:
				s.specials_blocked += 1
			else:
				s.specials_hit += 1
	var on_throw := func(attacker: Fighter, _defender: Fighter) -> void:
		var s: Dictionary = _stats[ids[fighters.find(attacker)]]
		if attacker.grab_move:
			if attacker.grab_move.super_move:
				s.supers_hit += 1
			else:
				s.grabs += 1
		else:
			s.throws += 1
	_m.hit_landed.connect(on_hit)
	_m.throw_landed.connect(on_throw)
	for i in 2:
		var f: Fighter = fighters[i]
		var id: StringName = ids[i]
		var side := i
		var started := func(move: MoveData) -> void:
			if move.super_move:
				_stats[id].supers += 1
				super_connected[side] = false
			elif move.is_special():
				_stats[id].specials += 1
		f.attack_started.connect(started)
		connections.append([f, started])

	var ticks := 0
	var rounds_counted := 0
	while _m.phase != _m.Phase.MATCH_OVER and ticks < TICK_CAP:
		_m._physics_process(1.0 / 60.0)
		ticks += 1
		for i in 2:
			var f: Fighter = fighters[i]
			var drop: int = last_health[i] - f.health
			if drop > 0:
				_stats[ids[1 - i]].damage_dealt += drop
				_stats[ids[i]].damage_taken += drop
			last_health[i] = f.health
		if _m.phase == _m.Phase.ROUND_OVER and _m.phase_ticks == 1:
			rounds_counted += 1
			var winner: Fighter = _m.round_winner
			for i in 2:
				var s: Dictionary = _stats[ids[i]]
				s.rounds += 1
				s.round_ticks += ticks - round_start
				if _m.timer_ticks <= 0:
					s.timeouts += 1
				if winner == fighters[i]:
					s.round_wins += 1
					if fighters[i].health == fighters[i].data.max_health:
						s.perfects += 1
		if _m.phase == _m.Phase.FIGHT and _m.round_number != round_was:
			round_was = _m.round_number
			round_start = ticks
		if _m.phase == _m.Phase.INTRO and _m.phase_ticks == 1:
			last_health = [p1.health, p2.health]
	_m.hit_landed.disconnect(on_hit)
	_m.throw_landed.disconnect(on_throw)
	for c in connections:
		(c[0] as Fighter).attack_started.disconnect(c[1])
	var p1_won: bool = _m.round_wins[0] > _m.round_wins[1]
	var draw: bool = _m.round_wins[0] == _m.round_wins[1]
	for i in 2:
		_stats[ids[i]].matches += 1
	if not draw:
		_stats[ids[0] if p1_won else ids[1]].wins += 1
	if a != b:
		var key := "%s|%s" % [a.id, b.id] if String(a.id) < String(b.id) else "%s|%s" % [b.id, a.id]
		var entry: Array = _matrix.get(key, [0, 0])
		var first_is_a := String(a.id) < String(b.id)
		if not draw and (p1_won == first_is_a):
			entry[0] += 1
		elif draw:
			entry[0] += 0.5
		entry[1] += 1
		_matrix[key] = entry


func _report(roster: Array) -> void:
	print("\n=== WIN RATE MATRIX (row vs column, both sides) ===")
	var header := "        "
	for c: CharacterData in roster:
		header += "%9s" % c.display_name
	print(header)
	for r: CharacterData in roster:
		var line := "%-8s" % r.display_name
		for c: CharacterData in roster:
			if r == c:
				line += "%9s" % "-"
				continue
			var first := String(r.id) < String(c.id)
			var key := "%s|%s" % [r.id, c.id] if first else "%s|%s" % [c.id, r.id]
			if not _matrix.has(key): # not played (only one fighter's pairings were run)
				line += "%9s" % "."
				continue
			var e: Array = _matrix[key]
			var share := float(e[0]) / float(e[1]) # float: the counts are ints
			var rate := share if first else 1.0 - share
			line += "%8d%%" % roundi(rate * 100)
		print(line)
	print("\n=== PER FIGHTER (all matches incl. mirrors) ===")
	print("%-7s %6s %6s %7s %7s %6s %6s %5s %7s %7s %6s %6s %6s" % ["", "win%", "rnd%", "dmg/rd", "taken", "rd sec", "TO%", "perf", "spec", "spec%", "super", "throw", "grab"])
	for c: CharacterData in roster:
		var s: Dictionary = _stats[c.id]
		var rounds := maxi(s.rounds, 1)
		var spec_landed: int = s.specials_hit + s.specials_blocked
		print("%-7s %5d%% %5d%% %7d %7d %6.1f %5d%% %5d %7d %6d%% %6s %6d %6d" % [s.name,
			roundi(100.0 * s.wins / maxi(s.matches, 1)), roundi(100.0 * s.round_wins / rounds),
			s.damage_dealt / rounds, s.damage_taken / rounds, s.round_ticks / 60.0 / rounds,
			roundi(100.0 * s.timeouts / rounds), s.perfects, s.specials,
			roundi(100.0 * s.specials_hit / maxi(s.specials, 1)), "%d/%d" % [s.supers_hit, s.supers],
			s.throws, s.grabs])
	print("(spec% = specials that hit / specials started; super = landed/started)")


## Frame advantage on block if the move connects on its first active frame:
## blockstun - (remaining active frames + recovery). Hitstop delays both sides equally.
func _audit(roster: Array) -> void:
	print("\n=== FRAME DATA AUDIT (block advantage; <= -8 is punishable by a jab string) ===")
	for c: CharacterData in roster:
		var unsafe := []
		var fastest := 99
		for move: MoveData in c.moves:
			if move.input.begins_with("j.") or move.command_grab or move.projectile_speed > 0.0:
				continue # air moves, grabs and projectiles aren't judged by point-blank block advantage
			if not move.input.begins_with("~"):
				fastest = mini(fastest, move.startup + 1)
			var adv: int = move.blockstun - (move.active - 1 + move.recovery)
			if move.hits > 1:
				adv = move.blockstun - (move.recovery)
			if adv <= -8 and not move.input.begins_with("~"):
				unsafe.append("%s %s %+d" % [move.input, move.name, adv])
		print("%-7s fastest normal/special: %df | very unsafe: %s" % [c.display_name, fastest, ", ".join(unsafe) if not unsafe.is_empty() else "none"])
