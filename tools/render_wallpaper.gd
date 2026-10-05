extends SceneTree
## Renders the key-art wallpaper: the five fighters posed mid-move on the rooftop stage
## with the skyline behind them. Saves res://assets/ui/wallpaper.png (no text; used by the
## loading screen and main menu) and res://assets/ui/splash.png (with the title; used as
## the boot splash), plus the itch.io cover (dist/itch/01_cover_630x500.png, a taller
## framing with the title). Run windowed at 1920×1080:
##   godot --path . --resolution 1920x1080 -s res://tools/render_wallpaper.gd

const STAGE := "res://scenes/stages/rooftop.tscn"
const WALLPAPER := "res://assets/ui/wallpaper.png"
const SPLASH := "res://assets/ui/splash.png"
const COVER := "res://dist/itch/01_cover_630x500.png"
## [character index, clip, clip time, position, yaw (radians; 0 = facing away from the camera)]
const POSES := [
	[0, &"fight/palm_blast", 0.22, Vector3(-2.45, 0, 0.3), PI + 0.8], # Kenji: Ki Blast at Rhea
	[1, &"fight/high_kick", 0.27, Vector3(-0.9, 0, -0.55), PI - 1.0], # Rhea: head kick at Kenji
	[3, &"fight/lariat", 0.40, Vector3(1.4, 0, -0.2), PI + 0.3], # Valka: Spinning Lariat, arms out
	[2, &"fight/victory_flex", 2.0, Vector3(2.65, 0, 0.5), PI + 0.45], # Brutus: double-biceps flex
	[4, &"fight/axe_kick", 0.22, Vector3(0.3, 0, -1.4), PI - 1.15], # Jin: axe kick raised high
]


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var stage := (load(STAGE) as PackedScene).instantiate()
	world.add_child(stage)
	await process_frame
	var gs = root.get_node("GameState")
	var models := []
	for pose in POSES:
		var model := FighterModel.new()
		world.add_child(model)
		model.build(gs.roster[pose[0]])
		model.position = pose[3]
		model.rotation.y = pose[4]
		models.append(model)
	# A glowing Ki Blast leaving Kenji's palms.
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	var orb_mat := StandardMaterial3D.new()
	orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb_mat.albedo_color = Color(1.0, 1.0, 1.0)
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.material = orb_mat
	orb.mesh = sphere
	for shell in [[0.16, 0.6], [0.26, 0.3], [0.4, 0.14]]: # additive glow shells
		var glow := MeshInstance3D.new()
		var glow_mesh := SphereMesh.new()
		glow_mesh.radius = shell[0]
		glow_mesh.height = shell[0] * 2.0
		var glow_mat := StandardMaterial3D.new()
		glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow_mat.albedo_color = Color(0.4, 0.75, 1.0, shell[1])
		glow_mesh.material = glow_mat
		glow.mesh = glow_mesh
		orb.add_child(glow)
	var orb_light := OmniLight3D.new()
	orb_light.light_color = Color(0.4, 0.75, 1.0)
	orb_light.light_energy = 3.0
	orb_light.omni_range = 3.0
	orb.add_child(orb_light)
	world.add_child(orb)

	var camera := Camera3D.new()
	camera.fov = 46.0
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 0.85, 5.0), Vector3(0.05, 1.35, 0.0))
	camera.current = true

	for frame in 40:
		for i in models.size():
			(models[i] as FighterModel).show_clip(POSES[i][1], POSES[i][2], 1.0, 1.0 / 60.0)
		await process_frame
	var kenji: FighterModel = models[0]
	orb.global_position = kenji.global_transform * Vector3(0, 1.15, -0.95)
	for frame in 4:
		await process_frame
	_save(WALLPAPER)

	# Title for the splash.
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var title := Label.new()
	title.text = "3D FIGHTER"
	title.add_theme_font_size_override("font_size", 190)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.32))
	title.add_theme_constant_override("outline_size", 34)
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.02, 0.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 60
	layer.add_child(title)
	for frame in 3:
		await process_frame
	_save(SPLASH)

	# itch.io cover: 630×500 is much taller than 16:9, so pull the camera back to keep all
	# five fighters in frame and shrink the title to fit the narrower width.
	root.size = Vector2i(1260, 1000)
	DisplayServer.window_set_size(root.size)
	camera.look_at_from_position(Vector3(0.1, 0.9, 6.9), Vector3(0.1, 1.85, 0.0))
	title.add_theme_font_size_override("font_size", 215)
	title.add_theme_constant_override("outline_size", 36)
	title.offset_top = 30
	for frame in 6:
		await process_frame
	var cover := root.get_texture().get_image()
	cover.resize(630, 500, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(COVER.get_base_dir())) # the kit is git-ignored
	cover.save_png(COVER)
	print("saved ", COVER)
	quit()


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	if image.get_size() != Vector2i(1920, 1080):
		image.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	image.save_png(path)
	print("saved ", path)
