extends SceneTree
## Renders each fighter's super cut-in: a wide close-up of the face roaring, eyes on the
## viewer, lit hard with a rim in the fighter's colour, on a transparent background.
## Saves res://assets/ui/cutins/<id>.png and <id>_alt.png (mirror-match look); FightHud
## slides it across the screen when that fighter starts a super.
##
## Run WINDOWED (needs the renderer): godot --path . -s res://tools/render_cutins.gd
## Append `-- <id> ...` to render only those characters.

const OUT_DIR := "res://assets/ui/cutins/"
const SIZE := Vector2i(1024, 400)
const Portraits := preload("res://tools/render_portraits.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	var settings: Node = root.get_node("Settings") # full quality whatever the player's setting
	settings.graphics = settings.Graphics.HIGH
	settings.resolution = settings.RESOLUTIONS.size() - 1
	settings.apply_graphics(root)
	var only := OS.get_cmdline_user_args()
	for character: CharacterData in root.get_node("GameState").roster:
		if only.is_empty() or String(character.id) in only:
			for alt in [false, true]:
				await _render(character, alt)
	print("cut-ins done")
	quit()


static func path_for(id: StringName, alt: bool) -> String:
	return OUT_DIR + String(id) + ("_alt" if alt else "") + ".png"


func _render(character: CharacterData, alt: bool) -> void:
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
	env.ambient_light_color = Color(0.45, 0.45, 0.55)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)

	var model := FighterModel.new()
	vp.add_child(model)
	model.build(character, alt)
	for i in 3:
		# The power stance (fists at the hips, chin up): nothing in front of the face.
		model.show_clip(&"fight/focus_stance", 0.35, 1.0, 1.0 / 60.0)
		await process_frame
	var head := model.skeleton.global_transform * model.skeleton.get_bone_global_pose(model.skeleton.find_bone("Head")).origin
	var eyes := model.eye_position()
	# Fighters face -Z. A 3/4 view from the fighter's left, so on screen they look right
	# (P1's side; P2's copy is flipped).
	var camera := Camera3D.new()
	camera.fov = 19.0
	vp.add_child(camera)
	camera.look_at_from_position(eyes + Vector3(-0.42, 0.0, -0.95), eyes)
	camera.current = true

	var key := DirectionalLight3D.new()
	key.light_energy = 2.0
	key.light_color = Color(1.0, 0.94, 0.85)
	vp.add_child(key)
	key.look_at_from_position(head + Vector3(-1.2, 0.8, -1.6), head)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 3.0
	rim.light_color = character.placeholder_color.lerp(Color.WHITE, 0.25)
	vp.add_child(rim)
	rim.look_at_from_position(head + Vector3(1.5, 0.5, 1.2), head)

	Portraits.turn_head(model, camera.global_position, 0.75)
	# Re-aim at the turned head: eyes a little above the middle, the face centred.
	eyes = model.eye_position()
	camera.look_at_from_position(eyes + (camera.global_position - eyes).normalized() * 1.03, eyes + Vector3(0, -0.035, 0))
	model._blink_in = INF
	var roar: Dictionary = FighterModel.EXPRESSIONS[&"roar"]
	for i in 6:
		for m in model._face_meshes.size():
			for s in FighterModel.FACE_SHAPES.size():
				if model._face_indices[m][s] >= 0:
					model._face_meshes[m].set_blend_shape_value(model._face_indices[m][s], roar.get(FighterModel.FACE_SHAPES[s], 0.0))
		model.set_gaze(camera.global_position, 1.0)
		await process_frame
	var path := path_for(character.id, alt)
	vp.get_texture().get_image().save_png(path)
	print("rendered ", path)
	vp.queue_free()
	await process_frame
