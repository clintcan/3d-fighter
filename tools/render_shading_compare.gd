extends SceneTree
## Renders a character with and without CharacterData.realistic_shading on real stages,
## for side-by-side comparison: close-up, medium and fight-distance shots.
##
## Run WINDOWED: godot --path . -s res://tools/render_shading_compare.gd -- <id> <out dir> [stage ...]

const SIZE := Vector2i(1280, 720)
const STAGES := {
	"ring": "res://scenes/stages/ring.tscn",
	"temple": "res://scenes/stages/temple.tscn",
	"dojo": "res://scenes/stages/dojo.tscn",
	"rooftop": "res://scenes/stages/rooftop.tscn",
	"beach": "res://scenes/stages/beach.tscn",
}


func _initialize() -> void:
	await process_frame
	var settings: Node = root.get_node("Settings")
	settings.graphics = settings.Graphics.HIGH
	settings.resolution = settings.RESOLUTIONS.size() - 1
	var args := OS.get_cmdline_user_args()
	var id := StringName(args[0]) if args.size() > 0 else &"kenji"
	var out_dir := args[1] if args.size() > 1 else "user://shading"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var stages := args.slice(2) if args.size() > 2 else PackedStringArray(["ring", "temple"])
	var character: CharacterData
	for c: CharacterData in root.get_node("GameState").roster:
		if c.id == id:
			character = c
	for stage in stages:
		for realistic in [false, true]:
			character.realistic_shading = realistic
			await _render(character, stage, out_dir, "on" if realistic else "off")
	print("compare done")
	quit()


func _render(character: CharacterData, stage_name: String, out_dir: String, tag: String) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	root.get_node("Settings").apply_graphics(vp)
	var stage := (load(STAGES[stage_name]) as PackedScene).instantiate()
	vp.add_child(stage)

	var model := FighterModel.new()
	vp.add_child(model)
	model.build(character)
	# Fighters face -Z: turn to face the cameras on +Z, 3/4 to the right.
	model.rotation.y = PI + deg_to_rad(25.0)
	for i in 3:
		model.show_clip(&"fight/guard", 0.5, 1.0, 1.0 / 60.0)
		await process_frame

	var skel := model.skeleton
	var head := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Head")).origin
	var chest := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("spine_03")).origin
	var camera := Camera3D.new()
	vp.add_child(camera)
	camera.current = true
	var shots := {
		"face": [head + Vector3(0.12, -0.04, 0.55), head + Vector3(0, 0.06, 0), 30.0],
		"close": [head + Vector3(0.25, 0.08, 0.9), head + Vector3(0, 0.03, 0), 30.0],
		"medium": [chest + Vector3(0.5, 0.2, 2.0), chest + Vector3(0, 0.05, 0), 35.0],
		"fight": [Vector3(0, 1.6, 4.6), Vector3(0, 1.0, 0), 45.0],
	}
	for shot: String in shots:
		var s: Array = shots[shot]
		camera.fov = s[2]
		camera.look_at_from_position(s[0], s[1])
		if stage.has_method("update_camera_occlusion"):
			stage.update_camera_occlusion(camera.global_position)
		for i in 8:
			await process_frame
		var path := out_dir.path_join("%s_%s_%s_%s.png" % [character.id, stage_name, shot, tag])
		vp.get_texture().get_image().save_png(path)
		print("rendered ", path)
	vp.queue_free()
	await process_frame
