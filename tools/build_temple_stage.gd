extends SceneTree
## Builds the temple stage (res://scenes/stages/temple.tscn): a mountain temple courtyard
## at sunset. A raised stone platform for the fight, raked gravel, a vermilion torii gate
## framing the background, a five-tier pagoda and a temple hall beyond it, stone lanterns,
## cherry trees with drifting petals, low stone walls, and layered mountain ridges fading
## into the sunset haze under a Poly Haven sky. Re-run after changing anything below.
##
## Run: godot_console --headless --path . -s res://tools/build_temple_stage.gd
##
## Layout: platform top at y = 0 (10 m square; fight bounds ±3.6 m), gravel at y = -0.4.
## Everything tall sits outside the camera's reach (> 8.5 m from the center), so nothing
## needs hiding. Repeated geometry is merged into one mesh per material.

const OUTPUT := "res://scenes/stages/temple.tscn"
const TEX := "res://assets/stages/temple/textures/"
const SKY := "res://assets/stages/temple/belfast_sunset_puresky_2k.hdr"
const STAGE_SCRIPT := "res://scripts/stages/stage.gd"
const FLICKER_SCRIPT := "res://scripts/stages/fire_flicker.gd"
const AO_PATH := "res://assets/stages/temple/gravel_ao.res"

const PLATFORM := 5.0 # half size
const PLATFORM_HEIGHT := 0.4
const GRAVEL_Y := -PLATFORM_HEIGHT
const VERMILION := Color(0.78, 0.17, 0.08)
const SUN_COLOR := Color(1.0, 0.56, 0.28)
const BLOSSOM := Color(0.98, 0.72, 0.8)
## The sky's sun sits about 43° right of straight behind the gate, just above the
## horizon; the directional light comes from there (backlight and rim on the fighters).
const SKY_ROTATION_DEGREES := 0.0

var stage: Node3D
var _batches := {}
var _footprints := [] # everything standing on the gravel (contact shadows)
var mat_floor: StandardMaterial3D
var mat_stone_wall: StandardMaterial3D
var mat_gravel: StandardMaterial3D
var mat_roof: StandardMaterial3D
var mat_vermilion: StandardMaterial3D
var mat_black: StandardMaterial3D
var mat_white_wall: StandardMaterial3D
var mat_stone: StandardMaterial3D
var mat_lantern_glow: StandardMaterial3D
var mat_bark: StandardMaterial3D
var mat_blossom: StandardMaterial3D
var mat_gold: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 1868
	stage = Node3D.new()
	stage.name = "Temple"
	stage.set_script(load(STAGE_SCRIPT))
	stage.set("rope_line", 50.0) # nothing sits between the camera and the fight
	stage.set("music", &"temple")

	_make_materials()
	_build_environment()
	_build_lights()
	_build_ground()
	_build_torii()
	_build_pagoda(Vector3(-7.5, GRAVEL_Y, -21.0))
	_build_hall(Vector3(9.0, GRAVEL_Y, -19.0))
	_build_lanterns()
	_build_walls()
	_build_trees()
	_build_petals()
	_build_mountains()
	_build_lantern_flicker()
	_flush_batches()
	_bake_contact_shadows()
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
	mat_floor = _textured("monastery_stone_floor", Color(1.0, 0.95, 0.9), 0.35)
	mat_stone_wall = _textured("japanese_stone_wall", Color(0.85, 0.82, 0.78), 0.5)
	mat_gravel = _textured("gravel_floor_03", Color(0.92, 0.9, 0.86), 0.5)
	mat_roof = _textured("grey_roof_tiles", Color(0.42, 0.44, 0.48), 0.6)
	mat_vermilion = _material(VERMILION, 0.0, 0.45)
	mat_black = _material(Color(0.05, 0.05, 0.05), 0.0, 0.5)
	mat_white_wall = _material(Color(0.9, 0.86, 0.78), 0.0, 0.9)
	mat_stone = _textured("japanese_stone_wall", Color(0.7, 0.68, 0.64), 1.2)
	mat_lantern_glow = _emissive(Color(1.0, 0.7, 0.35), 3.0)
	mat_bark = _material(Color(0.2, 0.13, 0.1), 0.0, 0.9)
	mat_blossom = _material(BLOSSOM, 0.0, 0.8)
	mat_gold = _material(Color(0.85, 0.65, 0.25), 0.8, 0.35)


# --- Environment & lighting ------------------------------------------------------

func _build_environment() -> void:
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load(SKY)
	sky_material.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(SKY_ROTATION_DEGREES), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	# A warmer, punchier grade: the sky alone reads grey.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.3
	env.adjustment_contrast = 1.08
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.ssao_enabled = false # too costly on integrated GPUs (see CLAUDE.md)
	# Distance haze in the sunset's color (the mountains melt into it) and light shafts.
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.68, 0.55)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(1.0, 0.85, 0.75)
	env.volumetric_fog_length = 30.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_add(stage, world_env, "WorldEnvironment")


func _build_lights() -> void:
	var lights := _add(stage, Node3D.new(), "Lights")
	# Low golden sun from behind-left, with shadows: long shadows across the platform.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-9, 137, 0) # from the sky's sun
	sun.light_energy = 2.2
	sun.light_color = SUN_COLOR
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 35.0
	sun.light_volumetric_fog_energy = 1.5
	_add(lights, sun, "Sun")
	# Cool sky fill from the opposite side so the shadow sides aren't black.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 40, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.65, 0.9)
	_add(lights, fill, "SkyFill")


# --- Ground ------------------------------------------------------------------------

func _build_ground() -> void:
	# Raked gravel all around.
	_batch(mat_gravel, Vector3(64, 0.2, 64), Transform3D(Basis(), Vector3(0, GRAVEL_Y - 0.1, 0)))
	# Raked lines: shallow grooves in rings around the platform.
	for ring in range(1, 8):
		var half := PLATFORM + 0.6 * ring
		for side in 4:
			var horizontal := side < 2
			var sign := -1.0 if side % 2 == 0 else 1.0
			var size := Vector3(half * 2.0, 0.015, 0.05) if horizontal else Vector3(0.05, 0.015, half * 2.0)
			var pos := Vector3(0, GRAVEL_Y + 0.004, sign * half) if horizontal else Vector3(sign * half, GRAVEL_Y + 0.004, 0)
			_batch(mat_stone, size, Transform3D(Basis(), pos))
	# The stone platform: paved top, stone-block sides, a darker lip.
	_batch(mat_floor, Vector3(PLATFORM * 2.0, 0.1, PLATFORM * 2.0), Transform3D(Basis(), Vector3(0, -0.05, 0)))
	_batch(mat_stone_wall, Vector3(PLATFORM * 2.0, PLATFORM_HEIGHT - 0.1, PLATFORM * 2.0), Transform3D(Basis(), Vector3(0, GRAVEL_Y + (PLATFORM_HEIGHT - 0.1) / 2.0, 0)))
	for side in 4:
		var horizontal := side < 2
		var sign := -1.0 if side % 2 == 0 else 1.0
		var size := Vector3(PLATFORM * 2.0 + 0.3, 0.08, 0.3) if horizontal else Vector3(0.3, 0.08, PLATFORM * 2.0 + 0.3)
		var pos := Vector3(0, 0.0, sign * PLATFORM) if horizontal else Vector3(sign * PLATFORM, 0.0, 0)
		_batch(mat_stone, size, Transform3D(Basis(), pos))
	# Steps down at the back, toward the gate.
	for i in 3:
		_batch(mat_stone, Vector3(3.0, 0.14, 0.4), Transform3D(Basis(), Vector3(0, -0.07 - i * 0.13, -PLATFORM - 0.2 - i * 0.4)))
	# Stone path from the steps to the gate.
	_batch(mat_floor, Vector3(2.6, 0.05, 6.0), Transform3D(Basis(), Vector3(0, GRAVEL_Y + 0.02, -PLATFORM - 4.0)))


# --- Torii gate ----------------------------------------------------------------------

func _build_torii() -> void:
	var z := -10.5
	var height := 6.2
	for x in [-2.7, 2.7]:
		var pillar := _cylinder(0.3, height, mat_vermilion, 20)
		pillar.position = Vector3(x, GRAVEL_Y + height / 2.0, z)
		_add(stage, pillar, "ToriiPillar%s" % ("L" if x < 0 else "R"))
		var base := _cylinder(0.38, 0.5, mat_black, 20)
		base.position = Vector3(x, GRAVEL_Y + 0.25, z)
		_add(stage, base, "ToriiBase%s" % ("L" if x < 0 else "R"))
	# Nuki (tie beam), gakuzuka (center strut) with a name plaque, kasagi (top beam).
	_batch(mat_vermilion, Vector3(7.4, 0.32, 0.3), Transform3D(Basis(), Vector3(0, GRAVEL_Y + height - 1.35, z)))
	_batch(mat_vermilion, Vector3(0.3, 0.9, 0.25), Transform3D(Basis(), Vector3(0, GRAVEL_Y + height - 0.75, z)))
	_batch(mat_black, Vector3(0.7, 0.95, 0.06), Transform3D(Basis(), Vector3(0, GRAVEL_Y + height - 0.8, z + 0.16)))
	_batch(mat_gold, Vector3(0.55, 0.8, 0.02), Transform3D(Basis(), Vector3(0, GRAVEL_Y + height - 0.8, z + 0.2)))
	_batch(mat_vermilion, Vector3(7.8, 0.4, 0.5), Transform3D(Basis(), Vector3(0, GRAVEL_Y + height - 0.1, z)))
	_batch(mat_black, Vector3(8.6, 0.22, 0.62), Transform3D(Basis(), Vector3(0, GRAVEL_Y + height + 0.2, z)))
	# Upswept ends of the top beam.
	for x in [-1.0, 1.0]:
		var tip := Transform3D(Basis(Vector3(0, 0, 1), x * 0.18), Vector3(x * 4.6, GRAVEL_Y + height + 0.32, z))
		_batch(mat_black, Vector3(1.1, 0.22, 0.62), tip)


# --- Buildings -----------------------------------------------------------------------

## Five-tier pagoda: stone base, tiers shrinking upward, each with wide eaves, and a
## bronze spire with rings.
func _build_pagoda(at: Vector3) -> void:
	_batch(mat_stone_wall, Vector3(6.0, 1.0, 6.0), Transform3D(Basis(), at + Vector3(0, 0.5, 0)))
	var y := 1.0
	var width := 4.4
	for tier in 5:
		var body := 1.7 if tier == 0 else 1.25
		_batch(mat_white_wall, Vector3(width, body, width), Transform3D(Basis(), at + Vector3(0, y + body / 2.0, 0)))
		for x in [-0.5, 0.5]: # corner posts
			for zz in [-0.5, 0.5]:
				_batch(mat_vermilion, Vector3(0.18, body, 0.18), Transform3D(Basis(), at + Vector3(x * width, y + body / 2.0, zz * width)))
		y += body
		_batch(mat_vermilion, Vector3(width + 0.5, 0.2, width + 0.5), Transform3D(Basis(), at + Vector3(0, y + 0.1, 0)))
		_batch(mat_roof, Vector3(width + 2.6, 0.3, width + 2.6), Transform3D(Basis(), at + Vector3(0, y + 0.35, 0)))
		_batch(mat_roof, Vector3(width + 1.4, 0.35, width + 1.4), Transform3D(Basis(), at + Vector3(0, y + 0.62, 0)))
		y += 0.8
		width -= 0.6
	var spire := _cylinder(0.08, 3.2, mat_gold, 8)
	spire.position = at + Vector3(0, y + 1.6, 0)
	_add(stage, spire, "PagodaSpire")
	for r in 5:
		var ring := _cylinder(0.32 - r * 0.03, 0.08, mat_gold, 12)
		ring.position = at + Vector3(0, y + 0.6 + r * 0.45, 0)
		_add(stage, ring, "SpireRing%d" % r)


## Temple hall: stone base, vermilion pillars, white walls, a big tiled hip roof.
func _build_hall(at: Vector3) -> void:
	_batch(mat_stone_wall, Vector3(11.0, 1.0, 7.5), Transform3D(Basis(), at + Vector3(0, 0.5, 0)))
	_batch(mat_white_wall, Vector3(9.0, 3.2, 5.6), Transform3D(Basis(), at + Vector3(0, 2.6, 0)))
	for i in 6:
		var x := -4.5 + i * 1.8
		_batch(mat_vermilion, Vector3(0.3, 3.4, 0.3), Transform3D(Basis(), at + Vector3(x, 2.7, 2.95)))
	_batch(mat_vermilion, Vector3(9.6, 0.35, 0.4), Transform3D(Basis(), at + Vector3(0, 4.35, 2.95)))
	# Hip roof: two sloped planes, end slopes, a ridge, flared eave edges.
	for side in [-1.0, 1.0]:
		var slope := Transform3D(Basis(Vector3.RIGHT, side * 0.42), at + Vector3(0, 5.5, side * 2.1))
		_batch(mat_roof, Vector3(12.5, 0.3, 5.4), slope)
		var eave := Transform3D(Basis(Vector3.RIGHT, side * 0.15), at + Vector3(0, 4.55, side * 4.4))
		_batch(mat_roof, Vector3(13.0, 0.25, 1.4), eave)
	for side in [-1.0, 1.0]:
		var end := Transform3D(Basis(Vector3(0, 0, 1), -side * 0.55), at + Vector3(side * 5.6, 5.3, 0))
		_batch(mat_roof, Vector3(2.6, 0.3, 7.0), end)
	_batch(mat_black, Vector3(9.5, 0.45, 0.5), Transform3D(Basis(), at + Vector3(0, 6.45, 0)))
	for side in [-1.0, 1.0]: # ridge-end ornaments
		_batch(mat_gold, Vector3(0.4, 0.8, 0.4), Transform3D(Basis(), at + Vector3(side * 4.8, 6.9, 0)))


# --- Lanterns, walls, trees ------------------------------------------------------------

## Stone lanterns (toro): base, post, glowing fire box, roof, finial.
func _build_lanterns() -> void:
	var spots := [Vector3(-6.0, GRAVEL_Y, -6.0), Vector3(6.0, GRAVEL_Y, -6.0), Vector3(-6.2, GRAVEL_Y, -12.5),
		Vector3(6.2, GRAVEL_Y, -12.5), Vector3(-9.5, GRAVEL_Y, 1.0), Vector3(9.5, GRAVEL_Y, 1.0)]
	for i in spots.size():
		var at: Vector3 = spots[i]
		_add_mesh(_hex(0.55, 0.3, mat_stone), at + Vector3(0, 0.15, 0), "LanternBase%d" % i)
		_add_mesh(_hex(0.18, 1.0, mat_stone), at + Vector3(0, 0.8, 0), "LanternPost%d" % i)
		_add_mesh(_hex(0.42, 0.18, mat_stone), at + Vector3(0, 1.39, 0), "LanternShelf%d" % i)
		_add_mesh(_hex(0.3, 0.42, mat_lantern_glow), at + Vector3(0, 1.69, 0), "LanternFire%d" % i)
		var roof := CylinderMesh.new()
		roof.top_radius = 0.08
		roof.bottom_radius = 0.62
		roof.height = 0.42
		roof.radial_segments = 6
		roof.material = mat_stone
		_add_mesh(roof, at + Vector3(0, 2.11, 0), "LanternRoof%d" % i)
		var finial := SphereMesh.new()
		finial.radius = 0.1
		finial.height = 0.2
		finial.material = mat_stone
		_add_mesh(finial, at + Vector3(0, 2.38, 0), "LanternFinial%d" % i)
		if i < 4:
			var glow := OmniLight3D.new()
			glow.position = at + Vector3(0, 1.7, 0)
			glow.light_color = Color(1.0, 0.65, 0.35)
			glow.light_energy = 1.2
			glow.omni_range = 4.0
			_add(stage, glow, "LanternLight%d" % i)


## Low stone walls bounding the courtyard, open at the back for the gate path.
func _build_walls() -> void:
	var r := 15.0
	var height := 1.2
	for side in 4:
		var basis := Basis(Vector3.UP, side * PI / 2.0)
		var out := basis * Vector3(0, 0, 1)
		var tangent := basis * Vector3(1, 0, 0)
		var gap := side == 2 # back (-Z): open for the path to the gate
		for segment: float in ([-1.0, 1.0] if gap else [0.0]):
			var length: float = r * 2.0 if not gap else r - 2.5
			var along: float = segment * (r + 2.5) / 2.0 if gap else 0.0
			var center: Vector3 = out * r + tangent * along + Vector3.UP * (GRAVEL_Y + height / 2.0)
			_batch(mat_stone_wall, Vector3(length, height, 0.6), Transform3D(basis, center))
			_batch(mat_roof, Vector3(length, 0.18, 0.9), Transform3D(basis, center + Vector3.UP * (height / 2.0 + 0.09)))


## Cherry trees: a leaning trunk, a few branches, and clusters of blossom.
func _build_trees() -> void:
	var spots := [Vector3(-10.5, GRAVEL_Y, -7.0), Vector3(11.0, GRAVEL_Y, -8.5), Vector3(-12.0, GRAVEL_Y, -13.0),
		Vector3(12.5, GRAVEL_Y, -3.0), Vector3(-11.5, GRAVEL_Y, 3.5), Vector3(4.5, GRAVEL_Y, -14.5)]
	for at: Vector3 in spots:
		var lean := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.05, 0.18))
		var trunk_height := _rng.randf_range(3.0, 4.0)
		_batch_cylinder(mat_bark, 0.22, 0.32, trunk_height, Transform3D(lean, at + lean * Vector3(0, trunk_height / 2.0, 0)))
		var crown := at + lean * Vector3(0, trunk_height, 0)
		for b in 4:
			var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.6, 1.2), _rng.randf_range(-1, 1)).normalized()
			var length := _rng.randf_range(1.2, 2.0)
			var basis := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir)) if dir != Vector3.UP else Basis()
			_batch_cylinder(mat_bark, 0.06, 0.13, length, Transform3D(basis, crown + dir * length / 2.0))
		for c in 14:
			var offset := Vector3(_rng.randf_range(-2.2, 2.2), _rng.randf_range(0.0, 1.8), _rng.randf_range(-2.2, 2.2))
			var size := _rng.randf_range(0.7, 1.3)
			_batch_sphere(mat_blossom, size, crown + offset)


## Petals drifting down across the courtyard.
func _build_petals() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(14, 1, 14)
	process.direction = Vector3(0.4, -1, 0.2)
	process.spread = 25.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 0.9
	process.gravity = Vector3(0.15, -0.35, 0.05)
	process.angular_velocity_min = -180.0
	process.angular_velocity_max = 180.0
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.turbulence_noise_scale = 3.0
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.color = BLOSSOM
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.045)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BLOSSOM
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	quad.material = mat
	var petals := GPUParticles3D.new()
	petals.process_material = process
	petals.draw_pass_1 = quad
	petals.amount = 260
	petals.lifetime = 12.0
	petals.preprocess = 12.0
	petals.visibility_aabb = AABB(Vector3(-16, -2, -16), Vector3(32, 12, 32))
	petals.position = Vector3(0, 7.0, -2.0)
	petals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(stage, petals, "Petals")


## Three rings of mountain ridges, darker near and hazier far, fading into the sky.
func _build_mountains() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.9
	noise.fractal_octaves = 4
	var ridges := [[110.0, 22.0, Color(0.2, 0.12, 0.2)], [160.0, 34.0, Color(0.38, 0.22, 0.32)], [230.0, 48.0, Color(0.62, 0.38, 0.4)]]
	for r in ridges.size():
		var radius: float = ridges[r][0]
		var peak: float = ridges[r][1]
		var color: Color = ridges[r][2]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segments := 160
		for i in segments:
			var a0 := TAU * i / segments
			var a1 := TAU * (i + 1) / segments
			var h0 := _ridge_height(noise, a0, r, peak)
			var h1 := _ridge_height(noise, a1, r, peak)
			var p0 := Vector3(sin(a0), 0, cos(a0)) * radius
			var p1 := Vector3(sin(a1), 0, cos(a1)) * radius
			var top0 := p0 + Vector3.UP * h0
			var top1 := p1 + Vector3.UP * h1
			var bottom0 := p0 + Vector3.DOWN * 30.0
			var bottom1 := p1 + Vector3.DOWN * 30.0
			var top_color := color.lerp(Color(0.95, 0.7, 0.6), 0.25) # sunlit haze on the peaks
			for v in [[bottom0, color], [top0, top_color], [top1, top_color], [bottom0, color], [top1, top_color], [bottom1, color]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_fog = true # colors are already "fogged"
		var mesh := st.commit()
		mesh.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(stage, mi, "Mountains%d" % r)


func _ridge_height(noise: FastNoiseLite, angle: float, ridge: int, peak: float) -> float:
	var n := noise.get_noise_2d(cos(angle) * 3.0 + ridge * 10.0, sin(angle) * 3.0) * 0.5 + 0.5
	return peak * (0.35 + 0.65 * n * n)


# --- Helpers ---------------------------------------------------------------------

func _batch(material: Material, size: Vector3, xform: Transform3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	_append(material, box, xform)


func _batch_cylinder(material: Material, top: float, bottom: float, height: float, xform: Transform3D) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	cylinder.radial_segments = 10
	cylinder.rings = 1
	_append(material, cylinder, xform)


func _batch_sphere(material: Material, size: float, at: Vector3) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 1.6
	sphere.radial_segments = 12
	sphere.rings = 6
	_append(material, sphere, Transform3D(Basis(), at))


## Candlelight wavering in the lit stone lanterns (FireFlicker).
func _build_lantern_flicker() -> void:
	var flicker := Node.new()
	flicker.set_script(load(FLICKER_SCRIPT))
	_add(stage, flicker, "LanternFlicker")
	var lights: Array[NodePath] = []
	for i in 4:
		lights.append(NodePath("../LanternLight%d" % i))
	flicker.set("lights", lights)
	flicker.set("amount", 0.15)


## Baked contact shadows on the gravel (StageAO) around the platform, its steps, the
## lanterns, walls and trees.
func _bake_contact_shadows() -> void:
	StageAO.collect(_footprints, stage, GRAVEL_Y, ["Geometry"])
	var half := Vector2(16.0, 16.0)
	var image := StageAO.bake(_footprints, Vector2.ZERO, half, 256)
	_add(stage, StageAO.overlay(StageAO.save(image, AO_PATH), Vector2.ZERO, half, GRAVEL_Y), "GravelShadows")
	print("baked contact shadows from %d footprints" % _footprints.size())


func _append(material: Material, mesh: PrimitiveMesh, xform: Transform3D) -> void:
	StageAO.add_aabb(_footprints, xform * mesh.get_aabb(), GRAVEL_Y)
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


func _add_mesh(mesh: Mesh, pos: Vector3, node_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	_add(stage, mi, node_name)


func _marker(pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.position = pos
	return m


func _hex(radius: float, height: float, material: Material) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	mesh.material = material
	return mesh


func _cylinder(radius: float, height: float, material: Material, segments: int) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


## Poly Haven PBR set (diff / nor_gl / rough), tinted, world-triplanar-tiled per meter.
func _textured(texture_name: String, tint: Color, tiling: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = load(TEX + texture_name + "_diff_1k.jpg")
	m.normal_enabled = true
	m.normal_texture = load(TEX + texture_name + "_nor_gl_1k.jpg")
	m.roughness_texture = load(TEX + texture_name + "_rough_1k.jpg")
	m.uv1_scale = Vector3(tiling, tiling, tiling)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
