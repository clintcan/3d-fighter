extends SceneTree
## Renders the stage select thumbnails (res://assets/ui/stages/<stage>.png, 640×360)
## from the fight camera's neutral position, with the two fighters in their stances.
##
## Run windowed (needs a renderer): godot --path . -s res://tools/render_stage_thumbs.gd

const OUT_DIR := "res://assets/ui/stages/"
const SIZE := Vector2i(640, 360)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	var gs = root.get_node("GameState")
	gs.player_character = gs.roster[0]
	gs.p2_character = gs.roster[1]
	for stage: Dictionary in gs.STAGES:
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
