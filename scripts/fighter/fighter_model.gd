class_name FighterModel
extends Node3D
## Skinned character visual for a Fighter. Built from CharacterData (body, skin texture,
## hair pieces) and driven by the fighter's logic each frame: logic picks the clip and,
## for timed clips, the exact playback time. The animation never drives gameplay.

const LIBRARIES := {
	&"ual1": preload("res://assets/animations/UAL1_Standard.glb"),
	&"ual2": preload("res://assets/animations/UAL2_Standard.glb"),
	&"fight": preload("res://assets/animations/fight_anims.res"),
}
const BLEND_TIME := 0.08
## Outfit fabrics: weave normal map, roughness map ("" = flat roughness), UV tiling,
## roughness (multiplies the map) and specular. Cloth is matte: full roughness from the
## maps (about 0.8-0.9) and low specular, so the ring's spotlights don't make it glare.
## Leather keeps a soft satin sheen with a flat roughness (its map has near-mirror specks).
## Colour comes from the character's outfit_colors (CC0 Poly Haven textures).
const FABRICS := {
	&"cotton": ["res://assets/characters/outfits/textures/cotton_jersey_nor_gl_1k.jpg",
		"res://assets/characters/outfits/textures/cotton_jersey_rough_1k.jpg", 6.0, 1.0, 0.12],
	&"stretch": ["res://assets/characters/outfits/textures/bi_stretch_nor_gl_1k.jpg",
		"res://assets/characters/outfits/textures/bi_stretch_rough_1k.jpg", 8.0, 1.0, 0.12],
	&"denim": ["res://assets/characters/outfits/textures/denim_fabric_06_nor_gl_1k.jpg",
		"res://assets/characters/outfits/textures/denim_fabric_06_rough_1k.jpg", 5.0, 1.0, 0.12],
	&"leather": ["res://assets/stages/ring/textures/fabric_leather_02_nor_gl_1k.jpg", "", 3.0, 0.55, 0.35],
}
## Detailed fabrics (CharacterData.detailed_textures): 2K normal and roughness maps plus
## a greyscale weave map that textures the colour (averaging 0.9), same tiling and
## material values as above. Fabrics without an entry use FABRICS.
const DETAILED_FABRICS := {
	&"cotton": ["res://assets/characters/outfits/textures/detail/cotton_jersey_nor_gl_2k.jpg",
		"res://assets/characters/outfits/textures/detail/cotton_jersey_rough_2k.jpg",
		"res://assets/characters/outfits/textures/detail/cotton_jersey_weave_2k.jpg", 6.0, 1.0, 0.12],
	&"stretch": ["res://assets/characters/outfits/textures/detail/bi_stretch_nor_gl_2k.jpg",
		"res://assets/characters/outfits/textures/detail/bi_stretch_rough_2k.jpg",
		"res://assets/characters/outfits/textures/detail/bi_stretch_weave_2k.jpg", 8.0, 1.0, 0.12],
	&"denim": ["res://assets/characters/outfits/textures/detail/denim_fabric_06_nor_gl_2k.jpg",
		"res://assets/characters/outfits/textures/detail/denim_fabric_06_rough_2k.jpg",
		"res://assets/characters/outfits/textures/detail/denim_fabric_06_weave_2k.jpg", 5.0, 1.0, 0.12],
	&"leather": ["res://assets/characters/outfits/textures/detail/fabric_leather_02_nor_gl_2k.jpg", "",
		"res://assets/characters/outfits/textures/detail/fabric_leather_02_weave_2k.jpg", 3.0, 0.55, 0.35],
}
## Skin pore detail (detailed characters): a tiling normal map over the body's second UV
## set, mixed in at SKIN_DETAIL_AMOUNT so it adds fine grain without flattening the
## body's own normal map. Visible in close-ups, invisible at fight distance.
const SKIN_DETAIL_NORMAL := "res://assets/characters/detail/skin_pores_nor.png"
const SKIN_DETAIL_SCALE := 28.0
const SKIN_DETAIL_AMOUNT := 0.3
## Brightest fabric albedo: real white cloth reflects about 80%; brighter blooms under the
## stage lights.
const MAX_FABRIC_ALBEDO := 0.72
## Realistic shading (CharacterData.realistic_shading). Skin: wrapped diffuse and a faint
## red backlight stand in for subsurface scattering (Godot's screen-space scattering cost
## 45% of the frame rate on integrated graphics, a third even at quality 0, because any
## material using it adds render buffers), real skin's specular (F0 about 0.028) and a faint
## rim tinted by the skin colour. Eyes: a clear wet coat over the iris. Hair: a stretched highlight along
## the strands.
const SKIN_BACKLIGHT := Color(0.16, 0.05, 0.03)
const SKIN_SPECULAR := 0.35
const SKIN_RIM := 0.06
const SKIN_RIM_TINT := 0.6
const EYE_ROUGHNESS := 0.12
const EYE_CLEARCOAT_ROUGHNESS := 0.02
const HAIR_ANISOTROPY := 0.7
const HAIR_RIM := 0.15
## Eye light: a small light in front of the face that only the eyes see (their own render
## layer), so the wet coat always has a catchlight, as in film and game close-ups.
const EYE_LAYER := 1 << 19
const EYE_LIGHT_OFFSET := Vector3(0.0, 0.02, 0.6) # from the head bone, skeleton space (+Z = face)
const EYE_LIGHT_ENERGY := 0.18
const EYE_LIGHT_SPECULAR := 10.0
## Bones whose lowest point must stay above the floor, with the distance from each bone
## to the sole measured in the rest pose (filled in build()).
## Facial expressions: blend shapes baked into every body (tools/build_outfits.gd) and
## into the eyebrow, lash and beard pieces (tools/build_face_shapes.gd, FACE_DIR) by
## tools/face_shapes.gd. A preset is a weight per shape; set_face() eases toward one.
const FACE_DIR := "res://assets/characters/face/"
const FACE_SHAPES: Array[StringName] = [&"blink", &"squint", &"brow_down", &"brow_up", &"jaw_open", &"smile", &"grimace"]
const EXPRESSIONS := {
	&"neutral": {&"brow_down": 0.35, &"squint": 0.15},
	&"effort": {&"brow_down": 0.85, &"squint": 0.35, &"grimace": 0.35},
	&"shout": {&"brow_down": 1.0, &"squint": 0.4, &"jaw_open": 0.6},
	&"roar": {&"brow_down": 1.0, &"squint": 0.5, &"jaw_open": 1.0, &"grimace": 0.3},
	&"pain": {&"squint": 1.0, &"blink": 0.5, &"brow_down": 0.45, &"brow_up": 0.45, &"grimace": 0.8, &"jaw_open": 0.2},
	&"guard": {&"brow_down": 1.0, &"squint": 0.6, &"grimace": 0.6},
	&"dazed": {&"blink": 0.6, &"brow_up": 0.35, &"grimace": 0.35, &"jaw_open": 0.15},
	&"out": {&"blink": 1.0, &"brow_up": 0.15, &"jaw_open": 0.3},
	&"surprise": {&"brow_up": 0.9, &"jaw_open": 0.2},
	&"grin": {&"smile": 0.9, &"squint": 0.25, &"brow_up": 0.15},
	&"smirk": {&"smile": 0.5, &"brow_down": 0.2},
}
const FACE_RISE := 14.0 # weight per second toward a stronger expression
const FACE_FALL := 5.0 # ... and back
const BLINK_TIME := 0.16
const BLINK_INTERVAL := Vector2(1.8, 5.0)

const CONTACT_BONES := [&"foot_l", &"foot_r", &"ball_l", &"ball_r"]
const SOLE_BELOW_ORIGIN := 0.01

var skeleton: Skeleton3D
var player: AnimationPlayer
var _body: Node3D
var _clip: StringName
var _contacts := {} # bone index -> rest height above the sole
var _flash_material: StandardMaterial3D
var _flash_tween: Tween
var face_weights := {} # shape -> current weight (without the blink)
var _face_meshes: Array[MeshInstance3D] = []
var _face_indices: Array[PackedInt32Array] = [] # per face mesh, its blend shape index per FACE_SHAPES
var _face_target: Dictionary = EXPRESSIONS[&"neutral"]
var _blink_rng := RandomNumberGenerator.new() # cosmetic: never the match RNG
var _blink_in := 2.0
var _blink_time := -1.0


## `alt` uses the character's alternate skin texture and hair colour (mirror matches).
func build(data: CharacterData, alt: bool = false) -> void:
	var body := data.model_scene.instantiate() as Node3D
	_body = body
	add_child(body)
	# glTF models face +Z; fighters face -Z.
	body.rotation.y = PI
	scale = Vector3.ONE * data.model_scale

	skeleton = body.find_child("Skeleton3D") as Skeleton3D
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		_use_face_piece(mesh, data.model_scene.resource_path, data.model_scene.resource_path)
	for bone_name: StringName in CONTACT_BONES:
		var bone := skeleton.find_bone(bone_name)
		# The rest-pose sole sits ~1 cm below the origin.
		_contacts[bone] = skeleton.get_bone_global_rest(bone).origin.y + SOLE_BELOW_ORIGIN
	for hair_scene in data.hair_scenes:
		_attach_skinned(hair_scene, data.model_scene.resource_path)
	var albedo := data.alt_body_albedo if alt and data.alt_body_albedo else data.body_albedo
	var realistic := data.realistic_shading and not _low_graphics()
	_customize_materials(albedo, data.alt_hair_color if alt else data.hair_color, data.detailed_textures, realistic)
	if realistic:
		_add_eye_light()
	if data.outfit_mesh:
		_dress(data, alt)
	_find_face()

	player = AnimationPlayer.new()
	body.add_child(player)
	player.root_node = player.get_path_to(body)
	for library_name: StringName in LIBRARIES:
		player.add_animation_library(library_name, LIBRARIES[library_name])
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func clip_length(clip: StringName) -> float:
	return player.get_animation(clip).length if player.has_animation(clip) else 1.0


## Shows `clip`. With time >= 0 the clip is posed at that exact time (timed clips such as
## attacks); otherwise it free-runs at `speed` (loops such as idle and walk).
func show_clip(clip: StringName, time: float, speed: float, delta: float) -> void:
	if not player.has_animation(clip):
		push_warning("Missing animation clip: %s" % clip)
		return
	if clip != _clip:
		_clip = clip
		player.play(clip, BLEND_TIME)
	if time >= 0.0:
		# Seek just short of the target and advance onto it, so cross-fades still progress.
		# Always advance the full delta: near time 0 this overshoots by under a frame, but
		# advancing 0 would freeze the cross-fade (e.g. static block poses at time 0).
		var target := minf(time, player.current_animation_length)
		player.speed_scale = 1.0
		player.seek(maxf(target - delta, 0.0), false)
		player.advance(delta)
	else:
		player.speed_scale = speed
		player.advance(delta)
	_keep_feet_above_floor()


## The UAL clips were authored for slightly different proportions and sink these bodies'
## feet a few cm into the floor. Lift the body so the lowest sole sits on the floor.
## Only ever lifts, so jumps and other airborne poses are unaffected.
func _keep_feet_above_floor() -> void:
	var lowest := INF
	for bone: int in _contacts:
		lowest = minf(lowest, skeleton.get_bone_global_pose(bone).origin.y - _contacts[bone])
	_body.position.y = maxf(-lowest, 0.0)


## Brief additive color flash over the whole character (hit/block feedback).
func flash(color: Color, duration: float) -> void:
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
			mesh.material_overlay = _flash_material
	if _flash_tween:
		_flash_tween.kill()
	_flash_material.albedo_color = Color(color, 0.4)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material, "albedo_color:a", 0.0, duration)


## Clothing: swaps in the body without the covered skin and adds the outfit mesh on the
## same skeleton and skin (its vertices carry the body's bone weights).
func _dress(data: CharacterData, alt: bool) -> void:
	var body_mesh: MeshInstance3D
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.mesh.surface_get_material(0)
		if material and material.resource_name.begins_with("MI_Superhero"):
			body_mesh = mesh
	if body_mesh == null:
		return
	if data.outfit_body_mesh:
		var skin_material := body_mesh.get_surface_override_material(0)
		body_mesh.mesh = data.outfit_body_mesh
		body_mesh.set_surface_override_material(0, skin_material)
	var outfit := MeshInstance3D.new()
	outfit.name = "Outfit"
	outfit.mesh = data.outfit_mesh
	outfit.skin = body_mesh.skin
	skeleton.add_child(outfit)
	outfit.skeleton = outfit.get_path_to(skeleton)
	var colors := data.alt_outfit_colors if alt and not data.alt_outfit_colors.is_empty() else data.outfit_colors
	for surface in data.outfit_mesh.get_surface_count():
		var slot := _surface_slot(data, surface)
		var fabric_name := _fabric_name(data, slot)
		var fabric := _fabric(data, fabric_name)
		var detailed: bool = data.detailed_textures and DETAILED_FABRICS.has(fabric_name)
		var color: Color = colors[slot] if slot < colors.size() else Color.WHITE
		var brightest := maxf(color.r, maxf(color.g, color.b))
		if brightest > MAX_FABRIC_ALBEDO:
			color = Color(color * (MAX_FABRIC_ALBEDO / brightest), 1.0)
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = color
		cloth.normal_enabled = true
		cloth.normal_texture = load(fabric[0])
		cloth.normal_scale = 0.8
		if fabric[1] != "":
			cloth.roughness_texture = load(fabric[1])
		cloth.roughness = fabric[3]
		cloth.metallic_specular = fabric[4]
		cloth.uv1_scale = Vector3.ONE * fabric[2]
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED # the inside shows at hems and sleeves
		if detailed:
			cloth.albedo_texture = load(DETAILED_FABRICS[fabric_name][2])
		if data.detailed_textures:
			cloth.vertex_color_use_as_albedo = true # hem shading and stitch lines
		outfit.set_surface_override_material(surface, cloth)


## The textures build() loads by path for `data` (everything else comes with the
## character's own resources). WebP textures take about 0.4 s each to decode and nothing
## else keeps them loaded between screens, so GameState.preload_fighters() loads these
## once at startup and holds them.
static func texture_paths(data: CharacterData) -> PackedStringArray:
	var paths := PackedStringArray()
	if data.outfit_mesh:
		for surface in data.outfit_mesh.get_surface_count():
			var fabric_name := _fabric_name(data, _surface_slot(data, surface))
			var fabric := _fabric(data, fabric_name)
			paths.append(fabric[0])
			if fabric[1] != "":
				paths.append(fabric[1])
			if data.detailed_textures and DETAILED_FABRICS.has(fabric_name):
				paths.append(DETAILED_FABRICS[fabric_name][2])
	if data.detailed_textures:
		paths.append(SKIN_DETAIL_NORMAL)
	return paths


## The colour slot of an outfit surface (named main / trim / accent / extra).
static func _surface_slot(data: CharacterData, surface: int) -> int:
	var slot := ["main", "trim", "accent", "extra"].find(data.outfit_mesh.surface_get_name(surface))
	return slot if slot >= 0 else surface


static func _fabric_name(data: CharacterData, slot: int) -> StringName:
	return data.outfit_fabrics[slot] if slot < data.outfit_fabrics.size() else &"cotton"


## [normal map, roughness map, tiling, roughness, specular] for a fabric, using the
## detailed maps when the character has them.
static func _fabric(data: CharacterData, fabric_name: StringName) -> Array:
	if data.detailed_textures and DETAILED_FABRICS.has(fabric_name):
		var d: Array = DETAILED_FABRICS[fabric_name] # same layout as FABRICS, the weave map in the middle
		return [d[0], d[1], d[3], d[4], d[5]]
	return FABRICS.get(fabric_name, FABRICS[&"cotton"])


## The detail albedo is white (multiplying changes nothing); its alpha sets how much of
## the pore normal map is mixed in.
func _add_skin_detail(skin: StandardMaterial3D) -> void:
	var mix := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	mix.fill(Color(1, 1, 1, SKIN_DETAIL_AMOUNT))
	skin.detail_enabled = true
	skin.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	skin.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	skin.detail_albedo = ImageTexture.create_from_image(mix)
	skin.detail_normal = load(SKIN_DETAIL_NORMAL)
	skin.uv2_scale = Vector3.ONE * SKIN_DETAIL_SCALE


func _attach_skinned(scene: PackedScene, base_path: String) -> void:
	# Hair pieces are rigged to the same skeleton (Head bone). Move their meshes onto our
	# skeleton; skins bind by bone name.
	var piece := scene.instantiate()
	for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		mesh.owner = null
		mesh.get_parent().remove_child(mesh)
		skeleton.add_child(mesh)
		mesh.skeleton = mesh.get_path_to(skeleton)
		_use_face_piece(mesh, base_path, scene.resource_path)
	piece.free()


## Swaps the body's skin texture and tints hair, working on per-instance material copies.
## `detailed` adds the skin pore detail (the dressed body carries the second UV set);
## `realistic` the realistic skin, eye and hair shading.
func _customize_materials(body_albedo: Texture2D, hair_color: Color, detailed: bool, realistic: bool) -> void:
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.get_surface_override_material_count():
			var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null:
				continue
			if material.resource_name.begins_with("MI_Superhero") and body_albedo:
				var skin := material.duplicate() as StandardMaterial3D
				skin.albedo_texture = body_albedo
				if detailed:
					_add_skin_detail(skin)
				if realistic:
					_realistic_skin(skin)
				mesh.set_surface_override_material(surface, skin)
			elif material.resource_name.begins_with("MI_Hair"):
				var hair := material.duplicate() as StandardMaterial3D
				hair.albedo_color = hair_color
				if realistic:
					hair.anisotropy_enabled = true
					hair.anisotropy = HAIR_ANISOTROPY
					hair.rim_enabled = true
					hair.rim = HAIR_RIM
					hair.rim_tint = 1.0
				mesh.set_surface_override_material(surface, hair)
			elif material.resource_name.begins_with("MI_Eyes") and realistic:
				var eyes := material.duplicate() as StandardMaterial3D
				eyes.roughness = EYE_ROUGHNESS
				eyes.clearcoat_enabled = true
				eyes.clearcoat = 1.0
				eyes.clearcoat_roughness = EYE_CLEARCOAT_ROUGHNESS
				mesh.set_surface_override_material(surface, eyes)


# --- Face ------------------------------------------------------------------------------

## Where build_face_shapes.gd saves the expression-ready copy of a head piece: a mesh
## node `node_name` from `piece_path`, fitted to the head of `base_path`.
static func face_piece_path(base_path: String, piece_path: String, node_name: String) -> String:
	return FACE_DIR + "%s__%s__%s.res" % [base_path.get_file().get_basename(),
		piece_path.get_file().get_basename(), node_name.validate_filename().replace(".", "_")]


func _use_face_piece(mesh: MeshInstance3D, base_path: String, piece_path: String) -> void:
	var path := face_piece_path(base_path, piece_path, mesh.name)
	if ResourceLoader.exists(path):
		mesh.mesh = load(path)


func _find_face() -> void:
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh and mesh.mesh.get_blend_shape_count() > 0 and mesh.find_blend_shape_by_name(&"blink") >= 0:
			_face_meshes.append(mesh)
			var indices := PackedInt32Array()
			for shape in FACE_SHAPES:
				indices.append(mesh.find_blend_shape_by_name(shape))
			_face_indices.append(indices)
	for shape in FACE_SHAPES:
		face_weights[shape] = 0.0
	_blink_rng.randomize()
	_blink_in = _blink_rng.randf_range(BLINK_INTERVAL.x, BLINK_INTERVAL.y)


## True when this model can show expressions.
func has_face() -> bool:
	return not _face_meshes.is_empty()


## Eases the face toward `expression` (a key of EXPRESSIONS) over real time `delta`, and
## blinks now and then. Purely cosmetic.
func set_face(expression: StringName, delta: float) -> void:
	if _face_meshes.is_empty():
		return
	_face_target = EXPRESSIONS.get(expression, EXPRESSIONS[&"neutral"])
	for shape in FACE_SHAPES:
		var target: float = _face_target.get(shape, 0.0)
		var current: float = face_weights[shape]
		face_weights[shape] = move_toward(current, target, (FACE_RISE if target > current else FACE_FALL) * delta)
	# Blinks (not while the eyes are already shut or squeezed).
	var blink := 0.0
	if _blink_time >= 0.0:
		_blink_time += delta
		blink = sin(clampf(_blink_time / BLINK_TIME, 0.0, 1.0) * PI)
		if _blink_time >= BLINK_TIME:
			_blink_time = -1.0
	else:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink_in = _blink_rng.randf_range(BLINK_INTERVAL.x, BLINK_INTERVAL.y)
			if face_weights[&"blink"] < 0.4:
				_blink_time = 0.0
	for m in _face_meshes.size():
		for i in FACE_SHAPES.size():
			var weight: float = face_weights[FACE_SHAPES[i]]
			if i == 0: # blink
				weight = maxf(weight, blink)
			if _face_indices[m][i] >= 0:
				_face_meshes[m].set_blend_shape_value(_face_indices[m][i], weight)


## The Low graphics preset skips realistic shading. Looked up at runtime: tool scripts
## compile this class without the autoloads.
func _low_graphics() -> bool:
	var settings := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Settings")
	return settings != null and settings.graphics == 0 # Settings.Graphics.LOW


func _add_eye_light() -> void:
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.mesh.surface_get_material(0)
		if material and material.resource_name.begins_with("MI_Eyes"):
			mesh.layers |= EYE_LAYER
	var head := skeleton.find_bone("Head")
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "Head"
	skeleton.add_child(attachment)
	var rest := skeleton.get_bone_global_rest(head)
	var light := OmniLight3D.new()
	light.name = "EyeLight"
	light.position = rest.affine_inverse() * (rest.origin + EYE_LIGHT_OFFSET)
	light.light_cull_mask = EYE_LAYER
	light.light_energy = EYE_LIGHT_ENERGY
	light.light_specular = EYE_LIGHT_SPECULAR
	light.omni_range = 1.2
	attachment.add_child(light)


func _realistic_skin(skin: StandardMaterial3D) -> void:
	skin.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	skin.backlight_enabled = true
	skin.backlight = SKIN_BACKLIGHT
	skin.metallic_specular = SKIN_SPECULAR
	skin.rim_enabled = true
	skin.rim = SKIN_RIM
	skin.rim_tint = SKIN_RIM_TINT
