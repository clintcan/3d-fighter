extends SceneTree
## Renders a head-and-shoulders portrait (transparent PNG) for every character and
## assigns it to CharacterData.portrait.
##
## Run WINDOWED (needs the renderer): godot --path . -s res://tools/render_portraits.gd
## Append `-- <id> ...` to render only those characters.

const OUT_DIR := "res://assets/ui/portraits/"
const SIZE := Vector2i(512, 512)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	var roster: Array = root.get_node("GameState").roster
	var only := OS.get_cmdline_user_args()
	for character: CharacterData in roster:
		if only.is_empty() or String(character.id) in only:
			await _render(character)
	print("portraits done")
	quit()


func _render(character: CharacterData) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.7)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.95, 0.88)
	vp.add_child(key)
	key.look_at_from_position(Vector3(1.5, 2.5, -2.0), Vector3(0, 1.5, 0))
	var rim := DirectionalLight3D.new()
	rim.light_energy = 2.2
	rim.light_color = Color(0.55, 0.7, 1.0)
	vp.add_child(rim)
	rim.look_at_from_position(Vector3(-1.5, 2.0, 2.0), Vector3(0, 1.5, 0))

	var model := FighterModel.new()
	vp.add_child(model)
	model.build(character)
	for i in 3:
		model.show_clip(&"fight/guard", 0.5, 1.0, 1.0 / 60.0)
		await process_frame

	# Fighters face -Z; frame the head from a 3/4 front angle.
	var head := model.skeleton.global_transform * model.skeleton.get_bone_global_pose(model.skeleton.find_bone("Head")).origin
	var camera := Camera3D.new()
	camera.fov = 30.0
	vp.add_child(camera)
	camera.look_at_from_position(head + Vector3(0.45, 0.14, -1.1), head + Vector3(0, 0.06, 0))
	camera.current = true
	for i in 4:
		await process_frame

	var path := OUT_DIR + String(character.id) + ".png"
	vp.get_texture().get_image().save_png(path)
	print("rendered ", path)
	vp.queue_free()
	await process_frame
