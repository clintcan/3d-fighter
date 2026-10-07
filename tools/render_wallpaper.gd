extends SceneTree
## Renders the key-art wallpaper: the six fighters posed mid-move on the rooftop stage
## with the skyline behind them. Saves res://assets/ui/wallpaper.png (no text; used by the
## loading screen and main menu) and res://assets/ui/splash.png (the title screen: the
## brush logo from tools/build_logo.py and a name plate under each fighter; used as the
## boot splash), plus the itch.io cover (dist/itch/01_cover_630x500.png, a taller framing
## with the logo). Run windowed at 1920×1080:
##   godot --path . --resolution 1920x1080 -s res://tools/render_wallpaper.gd

const STAGE := "res://scenes/stages/rooftop.tscn"
const WALLPAPER := "res://assets/ui/wallpaper.png"
const SPLASH := "res://assets/ui/splash.png"
const COVER := "res://dist/itch/01_cover_630x500.png"
const LOGO := "res://assets/ui/logo.png"
## Name-plate colours (the glowing underline), per character id.
const PLATE_COLORS := {
	&"kenji": Color(0.3, 0.6, 1.0), &"rhea": Color(1.0, 0.3, 0.45), &"brutus": Color(1.0, 0.5, 0.12),
	&"valka": Color(0.72, 0.4, 1.0), &"jin": Color(0.2, 0.88, 1.0), &"mira": Color(1.0, 0.84, 0.25),
}
const PLATE_Y := 1004.0 # baseline row of the name plates (1080p)
const PLATE_SPACING := 250.0 # closest two plates may be
## [character index, clip, clip time, position, yaw (radians; 0 = facing away from the camera)]
const POSES := [
	[0, &"fight/palm_blast", 0.22, Vector3(-2.45, 0, 0.3), PI + 0.8], # Kenji: Ki Blast at Rhea
	[1, &"fight/high_kick", 0.27, Vector3(-0.9, 0, -0.55), PI - 1.0], # Rhea: head kick at Kenji
	[3, &"fight/lariat", 0.40, Vector3(1.75, 0, -0.25), PI + 0.3], # Valka: Spinning Lariat, arms out
	[2, &"fight/victory_flex", 2.0, Vector3(3.0, 0, 0.5), PI + 0.45], # Brutus: double-biceps flex
	[4, &"fight/axe_kick", 0.22, Vector3(3.2, 0, -1.9), PI - 1.0], # Jin: axe kick raised high, at the back
	[5, &"fight/flip_kick", 0.14, Vector3(0.45, 0, 0.35), PI + 1.15], # Mira: Sipa Flip at Valka
]


func _initialize() -> void:
	await process_frame
	var settings: Node = root.get_node("Settings") # render at full quality whatever the player's setting
	settings.graphics = settings.Graphics.HIGH
	settings.resolution = settings.RESOLUTIONS.size() - 1 # native
	settings.apply_graphics(root)
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
	camera.fov = 50.0
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0.2, 0.85, 5.0), Vector3(0.25, 1.35, 0.0))
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

	# Title screen for the splash: the brush logo and a name plate under each fighter.
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var title := TextureRect.new()
	title.texture = load(LOGO)
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.custom_minimum_size = Vector2(1380, 256)
	title.offset_left = -690
	title.offset_right = 690
	title.offset_top = 36
	title.offset_bottom = 292
	layer.add_child(title)
	var plates := Control.new()
	plates.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(plates)
	# Each plate sits under its fighter, nudged apart where fighters stand close together.
	var row := []
	for i in models.size():
		var character: CharacterData = gs.roster[POSES[i][0]]
		row.append([camera.unproject_position((models[i] as Node3D).global_position).x, character])
	row.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	for pass_index in 30:
		for i in row.size() - 1:
			var overlap: float = PLATE_SPACING - (row[i + 1][0] - row[i][0])
			if overlap > 0.0:
				row[i][0] -= overlap * 0.5
				row[i + 1][0] += overlap * 0.5
	for plate: Array in row:
		var character: CharacterData = plate[1]
		_name_plate(plates, character.display_name.to_upper(), plate[0], PLATE_COLORS.get(character.id, Color.WHITE))
	for frame in 3:
		await process_frame
	_save(SPLASH)
	plates.queue_free() # the cover's framing is different: logo only

	# itch.io cover: 630×500 is much taller than 16:9, so pull the camera back to keep all
	# six fighters in frame and shrink the title to fit the narrower width.
	root.size = Vector2i(1260, 1000)
	DisplayServer.window_set_size(root.size)
	camera.look_at_from_position(Vector3(0.25, 0.9, 7.2), Vector3(0.25, 1.85, 0.0))
	title.offset_left = -600
	title.offset_right = 600
	title.offset_top = 28
	title.offset_bottom = 251
	for frame in 6:
		await process_frame
	var cover := root.get_texture().get_image()
	cover.resize(630, 500, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(COVER.get_base_dir())) # the kit is git-ignored
	cover.save_png(COVER)
	print("saved ", COVER)
	quit()


## A fighter's name in white with a glowing coloured underline that fades at both ends,
## centred on `x`.
func _name_plate(parent: Control, text: String, x: float, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", Color(color.darkened(0.75), 0.9))
	label.add_theme_color_override("font_shadow_color", Color(color, 0.55))
	label.add_theme_constant_override("shadow_outline_size", 22)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(320, 60)
	label.position = Vector2(x - 160, PLATE_Y - 58)
	parent.add_child(label)
	for line in [[230.0, 14.0, 0.35], [200.0, 4.0, 1.0]]: # soft glow, then the bright core
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
		gradient.colors = PackedColorArray([Color(color, 0.0), Color(color.lightened(0.25), line[2]),
			Color(color.lightened(0.25), line[2]), Color(color, 0.0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 256
		texture.height = 4
		var bar := TextureRect.new()
		bar.texture = texture
		bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bar.size = Vector2(line[0], line[1])
		bar.position = Vector2(x - line[0] * 0.5, PLATE_Y + 6.0 - line[1] * 0.5)
		parent.add_child(bar)


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	if image.get_size() != Vector2i(1920, 1080):
		image.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	image.save_png(path)
	print("saved ", path)
