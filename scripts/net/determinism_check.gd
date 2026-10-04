class_name DeterminismCheck
extends RefCounted
## `-- --smoke-test --determinism`: plays a fixed fight for every fighter pairing with
## seeded random inputs and prints one combined checksum. Run it on each platform (and
## each build): online play needs every machine to print the same number.

const TICKS := 1800


static func run(tree: SceneTree) -> int:
	var gs: Node = tree.root.get_node("GameState")
	gs.mode = gs.Mode.VERSUS
	gs.stage_path = gs.DEFAULT_STAGE
	var combined := []
	var roster: Array = gs.roster
	for i in roster.size():
		gs.player_character = roster[i]
		gs.p2_character = roster[(i + 1) % roster.size()]
		var fight: Node = (load("res://scenes/fight.tscn") as PackedScene).instantiate()
		tree.root.add_child(fight)
		fight.set_physics_process(false)
		var controllers: Array[NetInputController] = [NetInputController.new(), NetInputController.new()]
		for k in 2:
			fight.fighters[k].controller = controllers[k]
		var rngs := [RandomNumberGenerator.new(), RandomNumberGenerator.new()]
		rngs[0].seed = 1000 + i
		rngs[1].seed = 2000 + i
		var held := [5, 5]
		var hold := [0, 0]
		for t in TICKS:
			for k in 2:
				var buttons := 0
				if hold[k] <= 0:
					var toward := 6 if k == 0 else 4
					held[k] = [toward, toward, 5, 2, 3 if k == 0 else 1, 4 if k == 0 else 6, 8][rngs[k].randi() % 7]
					hold[k] = rngs[k].randi_range(2, 10)
					if rngs[k].randf() < 0.5:
						buttons = [InputBuffer.LP, InputBuffer.HP, InputBuffer.LK, InputBuffer.HK, InputBuffer.LP | InputBuffer.LK][rngs[k].randi() % 5]
				hold[k] -= 1
				controllers[k].raw = InputBuffer.pack(held[k], buttons)
			fight.step()
		var checksum: int = fight.checksum(fight.save_state())
		print("SMOKE TEST: determinism %s vs %s: %08x (health %d / %d)" % [roster[i].display_name,
			roster[(i + 1) % roster.size()].display_name, checksum, fight.fighters[0].health, fight.fighters[1].health])
		combined.append(checksum)
		fight.free()
	var total := hash(combined) & 0xFFFFFFFF
	print("SMOKE TEST: determinism combined %08x" % total)
	return total
