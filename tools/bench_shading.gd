extends SceneTree
## Frame-rate comparison for CharacterData.realistic_shading: a mirror match of the given
## character (P2 is the CPU) on a stage, alternating off/on runs, vsync off.
##
## Run WINDOWED: godot --path . -s res://tools/bench_shading.gd -- <id> [stage path] [seconds] [off|on|both]
## Runs in one process slow down over time, so compare one-mode runs in fresh processes.

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var id := StringName(args[0]) if args.size() > 0 else &"kenji"
	var stage_path := args[1] if args.size() > 1 else "res://scenes/stages/ring.tscn"
	var seconds := float(args[2]) if args.size() > 2 else 12.0
	var mode := args[3] if args.size() > 3 else "both"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if OS.has_environment("BENCH_SSS_QUALITY"): # 0 off, 1 low, 2 medium (default), 3 high
		RenderingServer.sub_surface_scattering_set_quality(int(OS.get_environment("BENCH_SSS_QUALITY")) as RenderingServer.SubSurfaceScatteringQuality)
	root.size = Vector2i(1280, 720)
	var settings: Node = root.get_node("Settings")
	settings.graphics = settings.Graphics.HIGH
	settings.resolution = settings.RESOLUTIONS.size() - 1
	settings.apply_graphics(root)
	var game_state: Node = root.get_node("GameState")
	var character: CharacterData
	for c: CharacterData in game_state.roster:
		if c.id == id:
			character = c
	var results := {false: [], true: []}
	for realistic: bool in results:
		if mode == "both" or (mode == "on") == realistic:
			character.realistic_shading = realistic
			results[realistic].append(await _run(game_state, character, stage_path, seconds))
			print("BENCH realistic=%s fps=%s" % [realistic, results[realistic]])
	quit()


func _run(game_state: Node, character: CharacterData, stage_path: String, seconds: float) -> float:
	game_state.mode = game_state.Mode.VS_CPU
	game_state.player_character = character
	game_state.p2_character = character
	game_state.stage_path = stage_path
	var fight := (load("res://scenes/fight.tscn") as PackedScene).instantiate()
	root.add_child(fight)
	await create_timer(2.0).timeout # warm-up: shaders, intro
	var frames := Engine.get_frames_drawn()
	var start := Time.get_ticks_usec()
	await create_timer(seconds).timeout
	var fps := (Engine.get_frames_drawn() - frames) / ((Time.get_ticks_usec() - start) / 1e6)
	fight.queue_free()
	await process_frame
	await process_frame
	return snappedf(fps, 0.1)
