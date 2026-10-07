extends SceneTree
## Builds the train stage (res://scenes/stages/train.tscn): a fight on the roof of an
## express train racing through hill country in the late-afternoon sun. The train stands
## still and the world streams past (TrainMotion, scripts/stages/train_motion.gd): the
## ground's textures slide, and trees, telegraph poles and mountain ridges loop through
## the scenery shader. Now and then a train roars past the other way.
## Re-run after changing anything below.
##
## Run: godot_console --headless --path . -s res://tools/build_train_stage.gd
##
## Layout: the roof the fighters stand on is at y = 0, the train runs toward +X, the
## camera side is +Z. The roof is narrow, so the stage limits sideways movement
## (Stage.bounds_depth). Rail tops at y = -4, our line at z = 0 and the other at z = -4.5.
## Nothing tall stands on the camera side of the line.

const OUTPUT := "res://scenes/stages/train.tscn"
const SKY := "res://assets/stages/train/kloppenheim_06_puresky_2k.hdr"
const SCENERY_SHADER := "res://assets/stages/train/scenery.gdshader"
const GROUND_SHADER := "res://assets/stages/train/ground.gdshader"
const STAGE_SCRIPT := "res://scripts/stages/stage.gd"
const MOTION_SCRIPT := "res://scripts/stages/train_motion.gd"
const GRASS := "res://assets/stages/train/textures/aerial_grass_rock_"
const GRAVEL := "res://assets/stages/temple/textures/gravel_floor_03_"
const RIBBED := "res://assets/stages/market/textures/painted_metal_shutter_"

const CAR_LENGTH := 20.0
const CAR_GAP := 1.2
const BODY_HALF_WIDTH := 1.5
const BODY_BOTTOM := -3.1
const ROOF_EDGE := 0.25 # radius of the rounded roof edges
const RAIL_TOP := -4.0
const GROUND_Y := -4.2
const GAUGE_HALF := 0.72
const TRACK2_Z := -4.5
const SCENERY_PERIOD := 480.0
const MOUNTAIN_PERIOD := 2400.0
## Sky turned so the low sun (7° up) lights the fight from the left and a little in front.
const SKY_ROTATION := 3.6
const SUN_ELEVATION := 7.2

var stage: Node3D
var _batches := {}
var _rng := RandomNumberGenerator.new()
var _scroll_materials: Array[ShaderMaterial] = []
var mat_livery: StandardMaterial3D
var mat_stripe: StandardMaterial3D
var mat_roof: StandardMaterial3D
var mat_glass: StandardMaterial3D
var mat_dark: StandardMaterial3D
var mat_steel: StandardMaterial3D
var mat_rubber: StandardMaterial3D
var mat_light: StandardMaterial3D
var mat_red: StandardMaterial3D
var mat_white: StandardMaterial3D
var mat_seam: StandardMaterial3D


func _initialize() -> void:
	_rng.seed = 4242
	stage = Node3D.new()
	stage.name = "Train"
	stage.set_script(load(STAGE_SCRIPT))
	stage.set("rope_line", 50.0) # nothing to hide
	stage.set("music", &"train")
	stage.set("bounds_depth", 1.1) # the roof is 3 m wide

	_make_materials()
	_build_environment()
	_build_lights()
	_build_train()
	_build_rails()
	_flush_batches()
	_build_ground()
	_build_mountains()
	var passing := _build_passing_train()
	_build_motion(passing)
	_build_wind()
	_add(stage, StageFX.ambience([["res://assets/audio/ambience/train_rumble.ogg", -9.0], ["res://assets/audio/ambience/train_clack.ogg", -13.0], ["res://assets/audio/ambience/wind.ogg", -17.0]]), "Sound")
	_add(stage, _marker(Vector3(-2, 0, 0)), "P1Spawn")
	_add(stage, _marker(Vector3(2, 0, 0)), "P2Spawn")

	var scene := PackedScene.new()
	var err := scene.pack(stage)
	if err == OK:
		err = ResourceSaver.save(scene, OUTPUT)
	print("saved ", OUTPUT, " err=", err)
	stage.free()
	quit()


func _make_materials() -> void:
	mat_livery = _material(Color(0.07, 0.13, 0.3), 0.35, 0.42) # midnight blue
	mat_stripe = _material(Color(0.86, 0.64, 0.26), 0.65, 0.35) # gold
	mat_roof = StandardMaterial3D.new()
	mat_roof.albedo_color = Color(0.27, 0.28, 0.3) # weathered, so the fighters stand out
	mat_roof.normal_enabled = true
	mat_roof.normal_texture = load(RIBBED + "nor_gl_1k.jpg")
	mat_roof.roughness_texture = load(RIBBED + "rough_1k.jpg")
	mat_roof.metallic = 0.45
	mat_roof.uv1_scale = Vector3.ONE * 0.22 # wide ribs
	mat_roof.uv1_triplanar = true
	mat_roof.uv1_world_triplanar = true
	mat_glass = _material(Color(0.05, 0.07, 0.1), 0.2, 0.08)
	mat_dark = _material(Color(0.06, 0.06, 0.07), 0.2, 0.7)
	mat_steel = _material(Color(0.55, 0.56, 0.58), 0.85, 0.35)
	mat_rubber = _material(Color(0.04, 0.04, 0.04), 0.0, 0.9)
	mat_light = _emissive(Color(1.0, 0.9, 0.7), 3.0)
	mat_red = _material(Color(0.75, 0.12, 0.1), 0.2, 0.5)
	mat_white = _material(Color(0.9, 0.9, 0.88), 0.1, 0.5)
	mat_seam = _material(Color(0.13, 0.13, 0.14), 0.4, 0.6)


# --- Environment & lighting ------------------------------------------------------

func _build_environment() -> void:
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load(SKY)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, SKY_ROTATION, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.06
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.ssao_enabled = false # too costly on integrated GPUs (see the stage notes)
	env.fog_enabled = true # haze over the hills
	env.fog_light_color = Color(0.95, 0.8, 0.62)
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_add(stage, world_env, "WorldEnvironment")


## Direction toward the sun in the world, from where it sits in the sky panorama
## (u = 0.609 of the width, 7.2° up) and the sky's rotation.
func _sun_direction() -> Vector3:
	var azimuth := 0.609 * TAU # Godot's panorama: u = atan2(x, z) / TAU
	var sky_dir := Vector3(sin(azimuth), 0.0, cos(azimuth)) * cos(deg_to_rad(SUN_ELEVATION))
	sky_dir.y = sin(deg_to_rad(SUN_ELEVATION))
	return Basis(Vector3.UP, SKY_ROTATION) * sky_dir


func _build_lights() -> void:
	var to_sun := _sun_direction()
	var sun := DirectionalLight3D.new()
	# Lit a little higher than the sun really is, so the roof and faces aren't grazed flat.
	var light_dir := Vector3(to_sun.x, maxf(to_sun.y, 0.35), to_sun.z).normalized()
	sun.transform = Transform3D(Basis.looking_at(-light_dir), Vector3.ZERO)
	sun.light_energy = 2.3
	sun.light_color = Color(1.0, 0.76, 0.5)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	_add(stage, sun, "Sun")
	var fill := DirectionalLight3D.new() # cool sky light from the other side
	fill.transform = Transform3D(Basis.looking_at(Vector3(light_dir.x, -0.5, light_dir.z)), Vector3.ZERO) # shines from the side away from the sun
	fill.light_energy = 0.3
	fill.light_color = Color(0.7, 0.8, 1.0)
	_add(stage, fill, "SkyFill")


# --- The train -----------------------------------------------------------------------

func _build_train() -> void:
	var step := CAR_LENGTH + CAR_GAP
	for i in [-2, -1, 0, 1]:
		_car(i * step, false)
	_car(2 * step - 1.0, true) # the locomotive leads
	for i in [-2, -1, 0, 1]: # gangway bellows between the cars
		var x: float = i * step + CAR_LENGTH * 0.5 + CAR_GAP * 0.5
		_batch(mat_rubber, Vector3(CAR_GAP + 0.1, 2.5, 2.2), Transform3D(Basis(), Vector3(x, -1.75, 0)))


## One coach (or the locomotive), centred at `x`. The roof top is flat and level at y = 0
## between rounded edges; the fighters stand on it.
func _car(x: float, locomotive: bool) -> void:
	var half := CAR_LENGTH * 0.5
	var length := CAR_LENGTH
	# Body sides and floor, then the roof slab and its rounded edges.
	var flat := BODY_HALF_WIDTH - ROOF_EDGE
	_batch(mat_livery, Vector3(length, -ROOF_EDGE - BODY_BOTTOM, BODY_HALF_WIDTH * 2.0), Transform3D(Basis(), Vector3(x, (BODY_BOTTOM - ROOF_EDGE) * 0.5, 0)))
	_batch(mat_roof, Vector3(length, ROOF_EDGE, flat * 2.0), Transform3D(Basis(), Vector3(x, -ROOF_EDGE * 0.5, 0)))
	for side in [-1.0, 1.0]:
		var edge := CylinderMesh.new()
		edge.top_radius = ROOF_EDGE
		edge.bottom_radius = ROOF_EDGE
		edge.height = length
		edge.radial_segments = 16
		_append(mat_roof, edge, Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(x, -ROOF_EDGE, side * flat)))
	# Panel seams across the roof every 2 m, and dark gutters along its edges (1 cm high:
	# feet stay on the roof surface).
	var seams := int(length / 2.0)
	for k in seams + 1:
		_batch(mat_seam, Vector3(0.05, 0.012, flat * 2.0), Transform3D(Basis(), Vector3(x - half + k * length / seams, 0.006, 0)))
	for side in [-1.0, 1.0]:
		_batch(mat_seam, Vector3(length, 0.014, 0.1), Transform3D(Basis(), Vector3(x, 0.007, side * (flat - 0.05))))
	# Ends.
	for end in [-1.0, 1.0]:
		_batch(mat_livery, Vector3(0.12, -BODY_BOTTOM - 0.1, BODY_HALF_WIDTH * 2.0 - 0.1), Transform3D(Basis(), Vector3(x + end * (half - 0.06), BODY_BOTTOM * 0.5, 0)))
	for side in [-1.0, 1.0]:
		var z: float = side * (BODY_HALF_WIDTH + 0.01)
		# Gold stripes and a dark belt under the windows.
		_batch(mat_stripe, Vector3(length - 0.2, 0.12, 0.04), Transform3D(Basis(), Vector3(x, -2.25, z)))
		_batch(mat_stripe, Vector3(length - 0.2, 0.06, 0.04), Transform3D(Basis(), Vector3(x, -0.62, z)))
		if locomotive:
			_batch(mat_glass, Vector3(1.2, 0.8, 0.04), Transform3D(Basis(), Vector3(x + half - 2.2, -1.45, z))) # cab windows
			for g in 6: # engine-room grilles
				_batch(mat_dark, Vector3(1.4, 0.9, 0.04), Transform3D(Basis(), Vector3(x - half + 2.0 + g * 2.2, -1.5, z)))
		else:
			for w in 10:
				_batch(mat_glass, Vector3(1.25, 0.85, 0.04), Transform3D(Basis(), Vector3(x - 7.2 + w * 1.6, -1.45, z)))
			for end in [-1.0, 1.0]: # doors
				_batch(mat_dark, Vector3(1.05, 2.15, 0.035), Transform3D(Basis(), Vector3(x + end * (half - 1.15), -1.75, z)))
				_batch(mat_glass, Vector3(0.45, 0.7, 0.05), Transform3D(Basis(), Vector3(x + end * (half - 1.15), -1.35, z)))
	# Underframe: equipment boxes and two bogies.
	_batch(mat_dark, Vector3(length - 6.5, 0.55, 2.3), Transform3D(Basis(), Vector3(x, BODY_BOTTOM - 0.28, 0)))
	for b in [-1.0, 1.0]:
		var bx: float = x + b * (half - 3.0)
		_batch(mat_dark, Vector3(2.8, 0.35, 2.2), Transform3D(Basis(), Vector3(bx, BODY_BOTTOM - 0.35, 0)))
		for axle in [-1.0, 1.0]:
			for side in [-1.0, 1.0]:
				var wheel := CylinderMesh.new()
				wheel.top_radius = 0.45
				wheel.bottom_radius = 0.45
				wheel.height = 0.14
				wheel.radial_segments = 18
				_append(mat_steel, wheel, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(bx + axle * 1.1, RAIL_TOP + 0.45, side * GAUGE_HALF)))
	# Roof details at the ends, clear of the fighting area (|x| < 3.6 on the middle car).
	if locomotive:
		_batch(mat_dark, Vector3(1.0, 0.5, 0.7), Transform3D(Basis(), Vector3(x - 3.0, 0.25, 0))) # exhaust stack
		_batch(mat_steel, Vector3(0.6, 0.25, 0.25), Transform3D(Basis(), Vector3(x + half - 3.5, 0.12, 0.5))) # horns
		_nose(x + half)
	else:
		for end in [-1.0, 1.0]:
			_batch(mat_steel, Vector3(1.8, 0.3, 1.4), Transform3D(Basis(), Vector3(x + end * (half - 2.4), 0.15, 0))) # air-con housings


## The locomotive's front: a sloped windscreen, headlights and a red buffer beam.
func _nose(front: float) -> void:
	var slope := Basis(Vector3.BACK, deg_to_rad(28.0))
	_batch(mat_livery, Vector3(1.6, 0.25, BODY_HALF_WIDTH * 2.0), Transform3D(slope, Vector3(front + 0.25, -0.55, 0)))
	_batch(mat_glass, Vector3(1.2, 0.05, BODY_HALF_WIDTH * 1.6), Transform3D(slope, Vector3(front + 0.32, -0.45, 0)))
	_batch(mat_livery, Vector3(1.0, 2.6, BODY_HALF_WIDTH * 2.0), Transform3D(Basis(), Vector3(front + 0.5, -1.95, 0)))
	_batch(mat_red, Vector3(0.3, 0.45, BODY_HALF_WIDTH * 2.0), Transform3D(Basis(), Vector3(front + 1.05, -3.0, 0)))
	for side in [-1.0, 1.0]:
		_batch(mat_light, Vector3(0.06, 0.22, 0.32), Transform3D(Basis(), Vector3(front + 1.02, -2.3, side * 0.95)))


func _build_rails() -> void:
	for center in [0.0, TRACK2_Z]:
		for side in [-1.0, 1.0]:
			_batch(mat_steel, Vector3(1400.0, RAIL_TOP - GROUND_Y, 0.08), Transform3D(Basis(), Vector3(0, (RAIL_TOP + GROUND_Y) * 0.5, center + side * GAUGE_HALF)))


# --- The moving world ------------------------------------------------------------------

func _scroll_material(shader_path: String, period: float = SCENERY_PERIOD) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	if shader_path == SCENERY_SHADER:
		m.set_shader_parameter("period", period)
	_scroll_materials.append(m)
	return m


func _build_ground() -> void:
	var m := _scroll_material(GROUND_SHADER)
	m.set_shader_parameter("track2_z", TRACK2_Z)
	m.set_shader_parameter("grass_albedo", load(GRASS + "diff_1k.jpg"))
	m.set_shader_parameter("grass_normal", load(GRASS + "nor_gl_1k.jpg"))
	m.set_shader_parameter("gravel_albedo", load(GRAVEL + "diff_1k.jpg"))
	m.set_shader_parameter("gravel_normal", load(GRAVEL + "nor_gl_1k.jpg"))
	m.set_shader_parameter("grass_tint", Color(0.95, 1.0, 0.8))
	m.set_shader_parameter("gravel_tint", Color(0.85, 0.82, 0.78))
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 900)
	plane.subdivide_width = 16
	plane.subdivide_depth = 16
	plane.material = m
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.position = Vector3(0, GROUND_Y, -150)
	_add(stage, ground, "Ground")


## Two ridges of hills in the distance, built as eight segments each so the shader can
## loop them (one jump per segment, far out of view). Heights are periodic over the loop.
func _build_mountains() -> void:
	var m := _scroll_material(SCENERY_SHADER, MOUNTAIN_PERIOD)
	m.set_shader_parameter("unlit", true)
	var ridges := [[-330.0, 55.0, Color(0.42, 0.5, 0.46), 3], [-560.0, 120.0, Color(0.6, 0.62, 0.68), 7]]
	var segments := 8
	var seg_len := MOUNTAIN_PERIOD / segments
	for r in ridges.size():
		var z: float = ridges[r][0]
		var peak: float = ridges[r][1]
		var color: Color = ridges[r][2]
		var phase: int = ridges[r][3]
		for s in segments:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var x0 := -MOUNTAIN_PERIOD * 0.5 + s * seg_len
			var steps := 30
			for i in steps:
				var xa := x0 + seg_len * i / steps
				var xb := x0 + seg_len * (i + 1) / steps
				var ha := _ridge_height(xa, peak, phase)
				var hb := _ridge_height(xb, peak, phase)
				var top_color := color.lerp(Color(1.0, 0.85, 0.7), 0.3) # the sun on the ridgeline haze
				for v in [[Vector3(xa, GROUND_Y - 20.0, z), color], [Vector3(xa, GROUND_Y + ha, z), top_color], [Vector3(xb, GROUND_Y + hb, z), top_color],
						[Vector3(xa, GROUND_Y - 20.0, z), color], [Vector3(xb, GROUND_Y + hb, z), top_color], [Vector3(xb, GROUND_Y - 20.0, z), color]]:
					st.set_color(v[1])
					st.add_vertex(v[0] - Vector3(x0, 0, 0)) # local to the segment's origin
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = m
			mi.position = Vector3(x0, 0, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.custom_aabb = AABB(Vector3(-MOUNTAIN_PERIOD, -50, -50), Vector3(MOUNTAIN_PERIOD * 2.0, 300, 100))
			_add(stage, mi, "Ridge%d_%d" % [r, s])


## A ridgeline that repeats exactly every MOUNTAIN_PERIOD metres (whole-number waves).
func _ridge_height(x: float, peak: float, phase: int) -> float:
	var t := TAU * x / MOUNTAIN_PERIOD
	var h := 0.0
	var waves := [[3, 0.5], [7, 0.3], [13, 0.18], [29, 0.08], [53, 0.04]]
	for w in waves:
		h += w[1] * (0.5 + 0.5 * sin(t * w[0] + phase * (w[0] as int) * 0.37))
	return peak * (0.25 + h)


## Low-poly trees (two kinds) and a telegraph pole with its wires, vertex coloured.
func _tree_meshes() -> Array[Mesh]:
	var trunk := Color(0.3, 0.22, 0.15)
	var pine := VertexMesh.new()
	pine.cylinder(Vector3.ZERO, 0.22, 3.0, trunk)
	for i in 3:
		pine.cone(Vector3(0, 2.2 + i * 2.1, 0), 2.4 - i * 0.6, 3.4, Color(0.06, 0.18, 0.09).lerp(Color(0.1, 0.26, 0.12), i * 0.3))
	var broad := VertexMesh.new()
	broad.cylinder(Vector3.ZERO, 0.3, 4.0, trunk)
	for blob in [[Vector3(0, 5.0, 0), 2.6], [Vector3(1.4, 4.3, 0.6), 1.9], [Vector3(-1.2, 4.6, -0.7), 2.0], [Vector3(0.2, 6.3, -0.3), 1.8]]:
		broad.sphere(blob[0], blob[1], Color(0.16, 0.3, 0.08).lerp(Color(0.26, 0.38, 0.1), _rng.randf()))
	var bush := VertexMesh.new()
	bush.sphere(Vector3(0, 0.6, 0), 1.3, Color(0.18, 0.3, 0.1))
	return [pine.commit(), broad.commit(), bush.commit()]


func _pole_mesh(spacing: float) -> Mesh:
	var wood := Color(0.25, 0.19, 0.14)
	var pole := VertexMesh.new()
	pole.cylinder(Vector3.ZERO, 0.13, 8.5, wood)
	pole.box(Vector3(0, 7.9, 0), Vector3(0.12, 0.12, 1.8), wood)
	for zi in [-0.75, 0.0, 0.75]:
		pole.cylinder(Vector3(0, 7.96, zi), 0.05, 0.22, Color(0.75, 0.8, 0.82))
		# The wire to the next pole, sagging 0.6 m in the middle.
		var segments := 12
		for i in segments:
			var a := float(i) / segments
			var b := float(i + 1) / segments
			var pa := Vector3(spacing * a, 8.12 - 0.6 * 4.0 * a * (1.0 - a), zi)
			var pb := Vector3(spacing * b, 8.12 - 0.6 * 4.0 * b * (1.0 - b), zi)
			pole.beam(pa, pb, 0.025, Color(0.08, 0.08, 0.08))
	return pole.commit()


func _build_motion(passing: Node3D) -> void:
	var motion := Node3D.new()
	motion.set_script(load(MOTION_SCRIPT))
	var tree_material := _scroll_material(SCENERY_SHADER)
	var pole_material := _scroll_material(SCENERY_SHADER)
	pole_material.set_shader_parameter("roughness", 0.8)
	motion.set("tree_meshes", _tree_meshes())
	motion.set("tree_material", tree_material)
	motion.set("pole_mesh", _pole_mesh(40.0))
	motion.set("pole_material", pole_material)
	motion.set("ground_y", GROUND_Y)
	motion.set("pole_z", TRACK2_Z - 3.1)
	motion.set("materials", _scroll_materials)
	motion.set("passing_train", passing)
	motion.set("passing_sound", passing.get_node("Sound"))
	_add(stage, motion, "Motion")


## The other train: five red-and-white coaches with a locomotive leading toward -X. Its
## nose is the node's origin (TrainMotion moves it); the coaches trail toward +X.
func _build_passing_train() -> Node3D:
	var root := Node3D.new()
	var st := {}
	var red := _material(Color(0.72, 0.1, 0.09), 0.25, 0.45)
	var cream := _material(Color(0.92, 0.88, 0.8), 0.1, 0.5)
	var parts := [] # [material, size, position]
	for c in 5:
		var x := 1.0 + c * (CAR_LENGTH + CAR_GAP) + CAR_LENGTH * 0.5
		parts.append([red, Vector3(CAR_LENGTH, -BODY_BOTTOM, BODY_HALF_WIDTH * 2.0), Vector3(x, BODY_BOTTOM * 0.5, 0)])
		parts.append([cream, Vector3(CAR_LENGTH - 0.2, 1.0, BODY_HALF_WIDTH * 2.0 + 0.02), Vector3(x, -1.45, 0)])
		parts.append([mat_glass, Vector3(CAR_LENGTH - 1.5, 0.75, BODY_HALF_WIDTH * 2.0 + 0.04), Vector3(x, -1.45, 0)])
		parts.append([mat_dark, Vector3(CAR_LENGTH - 4.0, 0.6, 2.3), Vector3(x, BODY_BOTTOM - 0.3, 0)])
		parts.append([mat_roof, Vector3(CAR_LENGTH, 0.2, BODY_HALF_WIDTH * 2.0 - 0.3), Vector3(x, 0.1, 0)])
		parts.append([cream, Vector3(CAR_LENGTH - 0.2, 0.22, BODY_HALF_WIDTH * 2.0 + 0.02), Vector3(x, -0.35, 0)]) # a band you see over our roof
		for end in [-1.0, 1.0]:
			parts.append([mat_steel, Vector3(2.0, 0.35, 1.4), Vector3(x + end * 6.5, 0.35, 0)]) # roof units flick past
	parts.append([red, Vector3(1.0, 2.6, BODY_HALF_WIDTH * 2.0), Vector3(0.5, -1.95, 0)]) # nose
	parts.append([mat_light, Vector3(0.06, 0.25, 0.4), Vector3(-0.02, -2.4, 0.9)])
	parts.append([mat_light, Vector3(0.06, 0.25, 0.4), Vector3(-0.02, -2.4, -0.9)])
	for p in parts:
		var box := BoxMesh.new()
		box.size = p[1]
		var tool: SurfaceTool = st.get(p[0])
		if tool == null:
			tool = SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			st[p[0]] = tool
		tool.append_from(box, 0, Transform3D(Basis(), p[2]))
	var i := 0
	for material: Material in st:
		var mesh := (st[material] as SurfaceTool).commit()
		mesh.surface_set_material(0, material)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "Part%d" % i
		root.add_child(mi)
		i += 1
	var sound := AudioStreamPlayer3D.new() # rides along with the train, so it sweeps past
	sound.name = "Sound"
	sound.stream = load("res://assets/audio/ambience/train_pass.ogg")
	sound.bus = &"Ambience"
	sound.unit_size = 25.0
	sound.volume_db = -2.0
	sound.position = Vector3(30.0, -1.5, 0)
	root.add_child(sound)
	root.position = Vector3(400.0, 0, TRACK2_Z)
	_add(stage, root, "PassingTrain")
	for child in root.get_children():
		child.owner = stage
	return root


## Wind: faint streaks rushing past the fighters.
func _build_wind() -> void:
	var wind := StageFX.streaks(Vector3(9.0, 2.0, 2.5), 26, Vector3(-38.0, 0.0, 0.0))
	wind.position = Vector3(0, 1.4, 0.6)
	_add(stage, wind, "Wind")


# --- Helpers ---------------------------------------------------------------------------

func _batch(material: Material, size: Vector3, xform: Transform3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	_append(material, box, xform)


func _append(material: Material, mesh: PrimitiveMesh, xform: Transform3D) -> void:
	var st: SurfaceTool = _batches.get(material)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[material] = st
	st.append_from(mesh, 0, xform)


func _flush_batches() -> void:
	var group := _add(stage, Node3D.new(), "Geometry")
	var i := 0
	for material: Material in _batches:
		var mesh := (_batches[material] as SurfaceTool).commit()
		mesh.surface_set_material(0, material)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		_add(group, mi, "Batch%d" % i)
		i += 1


func _add(parent: Node, node: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = stage
	return node


func _marker(pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.position = pos
	return m


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## A vertex-coloured mesh built from simple shapes (one material for a whole tree).
class VertexMesh:
	var st := SurfaceTool.new()

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func _add(mesh: PrimitiveMesh, xform: Transform3D, color: Color) -> void:
		var arrays := mesh.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in indices:
			st.set_color(color)
			st.set_normal((xform.basis * normals[i]).normalized())
			st.add_vertex(xform * verts[i])

	func cylinder(base: Vector3, radius: float, height: float, color: Color) -> void:
		var m := CylinderMesh.new()
		m.top_radius = radius * 0.8
		m.bottom_radius = radius
		m.height = height
		m.radial_segments = 6
		m.rings = 1
		_add(m, Transform3D(Basis(), base + Vector3(0, height * 0.5, 0)), color)

	func cone(base: Vector3, radius: float, height: float, color: Color) -> void:
		var m := CylinderMesh.new()
		m.top_radius = 0.0
		m.bottom_radius = radius
		m.height = height
		m.radial_segments = 7
		m.rings = 1
		_add(m, Transform3D(Basis(), base + Vector3(0, height * 0.5, 0)), color)

	func sphere(center: Vector3, radius: float, color: Color) -> void:
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 1.7
		m.radial_segments = 8
		m.rings = 5
		_add(m, Transform3D(Basis(), center), color)

	func box(center: Vector3, size: Vector3, color: Color) -> void:
		var m := BoxMesh.new()
		m.size = size
		_add(m, Transform3D(Basis(), center), color)

	## A thin square beam from a to b.
	func beam(a: Vector3, b: Vector3, thickness: float, color: Color) -> void:
		var m := BoxMesh.new()
		m.size = Vector3(thickness, thickness, a.distance_to(b))
		var basis := Basis.looking_at(b - a, Vector3.UP)
		_add(m, Transform3D(basis, (a + b) * 0.5), color)

	func commit() -> Mesh:
		return st.commit()
