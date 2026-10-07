extends SceneTree
## Renders the stage select thumbnails (res://assets/ui/stages/<stage>.png, 640×360)
## from the fight camera's neutral position, with the two fighters in their stances.
##
## Run windowed (needs a renderer): godot --path . -s res://tools/render_stage_thumbs.gd [-- <stage> ...]

const OUT_DIR := "res://assets/ui/stages/"
const SIZE := Vector2i(640, 360)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	var settings: Node = root.get_node("Settings") # render at full quality whatever the player's setting
	settings.graphics = settings.Graphics.HIGH
	settings.resolution = settings.RESOLUTIONS.size() - 1 # native
	settings.display_mode = settings.DisplayMode.WINDOWED # 16:9 whatever the player's display setting
	settings.window_size = settings.WINDOW_SIZES.find(Vector2i(1920, 1080))
	settings.apply_display()
	for i in 10:
		await process_frame
	settings.apply_graphics(root)
	var gs = root.get_node("GameState")
	gs.player_character = gs.roster[0]
	gs.p2_character = gs.roster[1]
	var only := OS.get_cmdline_user_args() # `-- train dojo` renders just those stages
	for stage: Dictionary in gs.STAGES:
		if not only.is_empty() and not String(stage.path).get_file().get_basename() in only:
			continue
		gs.stage_path = stage.path
		change_scene_to_file("res://scenes/fight.tscn")
		for i in 4:
			await process_frame
		var manager = current_scene
		manager.set_physics_process(false)
		manager.hud.visible = false
		manager.start_fight_immediately()
		for i in 40: # let the stance animations, reflection probe and camera settle
			await process_frame
		var image := root.get_texture().get_image()
		image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
		var file := OUT_DIR + String(stage.path).get_file().get_basename() + ".png"
		image.save_png(file)
		print("saved ", file)
	quit()
