extends SceneTree
## Renders a face close-up of each fighter for every FighterModel.EXPRESSIONS preset, in
## the dojo, into <out dir>/p_<id>_<preset>.png.
##
## Run WINDOWED: godot --path . -s res://tools/render_expressions.gd -- <out dir> <id> ...
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var ids := args.slice(1)
	for id in ids:
		var character: CharacterData
		for c: CharacterData in root.get_node("GameState").roster:
			if c.id == StringName(id): character = c
		var vp := SubViewport.new()
		vp.size = Vector2i(600, 600)
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var stage := (load("res://scenes/stages/dojo.tscn") as PackedScene).instantiate()
		vp.add_child(stage)
		var model := FighterModel.new()
		vp.add_child(model)
		model.build(character)
		model.rotation.y = PI + deg_to_rad(20)
		print(id, " has_face ", model.has_face())
		for i in 3:
			model.show_clip(&"fight/guard", 0.5, 1.0, 1.0 / 60.0)
			await process_frame
		var skel := model.skeleton
		var head := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Head")).origin
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.current = true
		cam.fov = 26
		var fwd := Vector3(sin(deg_to_rad(20)), 0, cos(deg_to_rad(20)))
		cam.look_at_from_position(head + Vector3(0, 0.05, 0) + fwd * 0.62, head + Vector3(0, 0.02, 0) + fwd * 0.05)
		stage.update_camera_occlusion(cam.global_position)
		for preset: StringName in FighterModel.EXPRESSIONS:
			model._blink_in = 999.0
			for i in 3:
				model.set_face(preset, 1.0)
				await process_frame
			for i in 3: await process_frame
			vp.get_texture().get_image().save_png(out + "/p_%s_%s.png" % [id, preset])
		vp.queue_free()
		await process_frame
	quit()
