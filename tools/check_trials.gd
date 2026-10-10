extends SceneTree
## Plays every combo trial's demo (TrialDemoController) against every dummy and reports
## any the demo can't complete. Run after changing trials, moves or the wall rules:
##   godot_console --headless --path . -s res://tools/check_trials.gd -- [stage=<name>] [fighter ids...]
## The stage defaults to the ring (rope bounce); run it with stage=dojo for a wall too.
## Exit code 1 if any trial fails. sim_test plays Kenji's trials only (this takes minutes).

func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	TrainingMode.trials_path = "user://trials_check.cfg" # never touch the player's progress
	var args := OS.get_cmdline_user_args()
	var stage: String = gs.DEFAULT_STAGE
	var only := []
	for arg in args:
		if arg.begins_with("stage="):
			stage = "res://scenes/stages/%s.tscn" % arg.substr(6)
		else:
			only.append(arg)
	var failures := 0
	for player: CharacterData in gs.roster:
		if not only.is_empty() and player.id not in only:
			continue
		for dummy: CharacterData in gs.roster:
			gs.mode = gs.Mode.TRAINING
			gs.player_character = player
			gs.p2_character = dummy
			gs.stage_path = stage
			change_scene_to_file("res://scenes/fight.tscn")
			await process_frame
			await process_frame
			var manager = current_scene
			manager.set_physics_process(false)
			var training: TrainingMode = manager.get_node("TrainingMode")
			var line := "%-7s vs %-7s %s " % [player.id, dummy.id, stage.get_file().get_basename()]
			for i in training.trials.size():
				training.start_trial(i)
				training.start_demo()
				var result := {done = false, best = 0, log = []}
				training.trial.completed.connect(func() -> void: result.done = true)
				training.trial.progressed.connect(func(n: int) -> void: result.best = maxi(result.best, n))
				var log_start := func(move: MoveData) -> void: result.log.append(move.input)
				training.player.attack_started.connect(log_start)
				var ticks := 0
				while training.demo != null and ticks < 1200:
					manager._physics_process(1.0 / 60.0)
					ticks += 1
				training.player.attack_started.disconnect(log_start)
				if result.done:
					line += " ok"
				else:
					failures += 1
					line += "  FAIL %d \"%s\" (best %d/%d; moves %s)" % [i + 1, training.trials[i].name, result.best,
						training.trials[i].steps.size(), ",".join(result.log)]
			print(line)
	print("combo trials: %d failed" % failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://trials_check.cfg"))
	quit(1 if failures > 0 else 0)
