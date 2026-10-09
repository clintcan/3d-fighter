extends SceneTree
## Renders a head-and-shoulders portrait (transparent PNG) for every character and
## assigns it to CharacterData.portrait.
##
## Run WINDOWED (needs the renderer): godot --path . -s res://tools/render_portraits.gd
## Append `-- <id> ...` to render only those characters.

const OUT_DIR := "res://assets/ui/portraits/"
const SIZE := Vector2i(512, 512)
const HEAD_TURN := 0.5 # share of the way the head turns from the guard toward the viewer
## Each fighter's look (blend shape weights, FighterModel.FACE_SHAPES), eyes on the viewer.
const FACES := {
	&"kenji": {&"brow_down": 1.0, &"squint": 0.35}, # calm, set
	&"rhea": {&"smile": 0.7, &"brow_down": 0.5, &"squint": 0.3}, # cocky
	&"brutus": {&"brow_down": 1.0, &"squint": 0.5, &"grimace": 0.6}, # glowering
	&"valka": {&"smile": 0.5, &"brow_down": 0.8, &"squint": 0.4}, # predatory
	&"jin": {&"brow_down": 1.0, &"squint": 0.6}, # cold focus
	&"mira": {&"smile": 1.0, &"squint": 0.3, &"brow_up": 0.25}, # grinning
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	var settings: Node = root.get_node("Settings") # render at full quality whatever the player's setting
	settings.graphics = settings.Graphics.HIGH
	settings.resolution = settings.RESOLUTIONS.size() - 1 # native
	settings.apply_graphics(root)
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

	# Fighters face -Z; frame the head from a 3/4 front angle, at eye level: the guard
	# holds the chin down, so the fighter glares at the viewer from under the brows.
	var head := model.skeleton.global_transform * model.skeleton.get_bone_global_pose(model.skeleton.find_bone("Head")).origin
	var camera := Camera3D.new()
	camera.fov = 30.0
	vp.add_child(camera)
	camera.look_at_from_position(head + Vector3(0.42, 0.04, -1.1), head + Vector3(0, 0.05, 0))
	camera.current = true
	turn_head(model, camera.global_position, HEAD_TURN)
	var face: Dictionary = FACES.get(character.id, FighterModel.EXPRESSIONS[&"neutral"])
	model._blink_in = INF
	for i in 4:
		for m in model._face_meshes.size():
			for s in FighterModel.FACE_SHAPES.size():
				if model._face_indices[m][s] >= 0:
					model._face_meshes[m].set_blend_shape_value(model._face_indices[m][s], face.get(FighterModel.FACE_SHAPES[s], 0.0))
		model.set_gaze(camera.global_position, 1.0)
		await process_frame

	var path := OUT_DIR + String(character.id) + ".png"
	vp.get_texture().get_image().save_png(path)
	print("rendered ", path)
	vp.queue_free()
	await process_frame


## Turns the head part of the way toward `target` (world), on top of the pose, so the eyes
## can reach the viewer: the guard holds it down and away. Also used by render_wallpaper.gd.
static func turn_head(model: FighterModel, target: Vector3, share: float) -> void:
	var skeleton := model.skeleton
	var bone := skeleton.find_bone("Head")
	var pose := skeleton.get_bone_global_pose(bone)
	var face := (pose.basis * (skeleton.get_bone_global_rest(bone).basis.inverse() * Vector3.BACK)).normalized()
	var eye := skeleton.global_transform.affine_inverse() * model.eye_position()
	var to := (skeleton.global_transform.affine_inverse() * target - eye).normalized()
	var turn := Quaternion(face, face.slerp(to, share).normalized())
	skeleton.set_bone_global_pose(bone, Transform3D(Basis(turn) * pose.basis, pose.origin))
