extends SceneTree
## Builds the rooftop stage (res://scenes/stages/rooftop.tscn): a skyscraper roof at
## night above a city skyline. Helipad markings on a concrete deck, parapet walls with
## railings, a stairwell hut, AC units, a water tower, an antenna mast, a neon sign,
## floodlights and string lights. Re-run after changing anything below.
##
## Run: godot_console --headless --path . -s res://tools/build_rooftop_stage.gd
##
## Layout: deck top at y = 0, roof 26 m square (parapet at ±13 m, outside the camera's
## reach, so nothing needs hiding). The sky is a custom shader over a cropped band of the
## Shanghai Bund panorama (assets/stages/rooftop/night_skyline.gdshader).
## Repeated geometry is merged into one mesh per material.

const OUTPUT := "res://scenes/stages/rooftop.tscn"
const SKY_SHADER := "res://assets/stages/rooftop/night_skyline.gdshader"
const SKYLINE := "res://assets/stages/rooftop/shanghai_bund_skyline.jpg"
const CONCRETE := "res://assets/stages/ring/textures/concrete_floor_worn_001"
const STAGE_SCRIPT := "res://scripts/stages/stage.gd"

const ROOF := 13.0 # half size
const PARAPET_HEIGHT := 1.1
const HELIPAD_RADIUS := 4.2
const NEON_PINK := Color(1.0, 0.18, 0.62)
const NEON_CYAN := Color(0.2, 0.85, 1.0)
const FLOOD := Color(1.0, 0.92, 0.78)

var stage: Node3D
var _batches := {}
var mat_deck: StandardMaterial3D
var mat_wall: StandardMaterial3D
var mat_paint_yellow: StandardMaterial3D
var mat_paint_white: StandardMaterial3D
var mat_metal: StandardMaterial3D
var mat_dark_metal: StandardMaterial3D
var mat_rail: StandardMaterial3D
var mat_tank: StandardMaterial3D
var mat_bulb: StandardMaterial3D
var mat_red_light: StandardMaterial3D
var mat_window: StandardMaterial3D
var mat_door: StandardMaterial3D
var mat_seam: StandardMaterial3D


func _initialize() -> void:
	stage = Node3D.new()
	stage.name = "Rooftop"
	stage.set_script(load(STAGE_SCRIPT))
	stage.set("rope_line", 50.0) # nothing sits between the camera and the fight
	stage.set("music", &"rooftop")

	_make_materials()
	_build_environment()
	_build_lights()
	_build_deck()
	_build_parapet()
	_build_structures()
	_build_neon_sign()
	_build_string_lights()
	_flush_batches()
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
	mat_deck = _textured(CONCRETE, Color(0.62, 0.62, 0.66), 0.35)
	mat_deck.roughness = 0.75
	mat_wall = _textured(CONCRETE, Color(0.5, 0.5, 0.54), 0.5)
	mat_paint_yellow = _material(Color(0.95, 0.75, 0.12), 0.0, 0.7)
	mat_paint_white = _material(Color(0.88, 0.88, 0.86), 0.0, 0.7)
	mat_metal = _material(Color(0.55, 0.57, 0.6), 0.7, 0.45)
	mat_dark_metal = _material(Color(0.16, 0.17, 0.19), 0.6, 0.55)
	mat_rail = _material(Color(0.3, 0.32, 0.35), 0.8, 0.35)
	mat_tank = _material(Color(0.34, 0.24, 0.18), 0.1, 0.8)
	mat_bulb = _emissive(Color(1.0, 0.78, 0.45), 3.0)
	mat_red_light = _emissive(Color(1.0, 0.1, 0.05), 6.0)
	mat_window = _emissive(Color(1.0, 0.85, 0.55), 1.5)
	mat_door = _material(Color(0.22, 0.24, 0.27), 0.5, 0.5)
	mat_seam = _material(Color(0.08, 0.08, 0.09), 0.0, 0.9)


# --- Environment & lighting ------------------------------------------------------

func _build_environment() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load(SKY_SHADER)
	sky_material.set_shader_parameter("skyline", load(SKYLINE))
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.06
	env.ssao_enabled = false # too costly on integrated GPUs (see CLAUDE.md)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.75, 0.7, 0.9)
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_sky_affect = 0.0 # keep the skyline crisp
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_add(stage, world_env, "WorldEnvironment")


func _build_lights() -> void:
	var lights := _add(stage, Node3D.new(), "Lights")
	# Cool moonlight with shadows.
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-52, 35, 0)
	moon.light_energy = 0.6
	moon.light_color = Color(0.62, 0.7, 1.0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 30.0
	_add(lights, moon, "Moonlight")
	# Floodlights on poles at the front corners, aimed at the helipad.
	for x in [-1.0, 1.0]:
		var base := Vector3(x * 9.5, 0, 8.0)
		_batch(mat_dark_metal, Vector3(0.18, 6.0, 0.18), Transform3D(Basis(), base + Vector3(0, 3.0, 0)))
		_batch(mat_dark_metal, Vector3(1.2, 0.12, 0.12), Transform3D(Basis(), base + Vector3(0, 6.0, 0)))
		var head := base + Vector3(-x * 0.4, 5.85, -0.2)
		_batch(mat_bulb, Vector3(0.5, 0.35, 0.12), Transform3D(Basis.looking_at(Vector3(0, 1, 0) - head), head))
		var flood := SpotLight3D.new()
		flood.transform = Transform3D(Basis.looking_at(Vector3(0, 0.8, 0) - head), head)
		flood.light_energy = 7.0
		flood.spot_range = 22.0
		flood.spot_angle = 26.0
		flood.spot_attenuation = 0.6
		flood.light_color = FLOOD
		flood.light_volumetric_fog_energy = 2.5
		_add(lights, flood, "Floodlight%s" % ("L" if x < 0 else "R"))
	# Soft overhead fill so the fighters' tops aren't lost in the dark.
	var top := SpotLight3D.new()
	top.position = Vector3(0, 9, 1)
	top.rotation_degrees = Vector3(-90, 0, 0)
	top.light_energy = 3.0
	top.spot_range = 12.0
	top.spot_angle = 40.0
	top.light_color = Color(0.85, 0.88, 1.0)
	top.light_volumetric_fog_energy = 0.0
	_add(lights, top, "TopFill")


# --- Deck & helipad ----------------------------------------------------------------

func _build_deck() -> void:
	_batch(mat_deck, Vector3(ROOF * 2.0, 0.3, ROOF * 2.0), Transform3D(Basis(), Vector3(0, -0.15, 0)))
	# Expansion joints every 3 m.
	for i in range(-4, 5):
		var p := i * 3.0
		_batch(mat_seam, Vector3(ROOF * 2.0, 0.004, 0.04), Transform3D(Basis(), Vector3(0, 0.001, p)))
		_batch(mat_seam, Vector3(0.04, 0.004, ROOF * 2.0), Transform3D(Basis(), Vector3(p, 0.001, 0)))
	# Helipad: a white circle with a yellow "H", plus a square of yellow edge lines at
	# the fight bounds (±3.6 m).
	var segments := 48
	for i in segments:
		var a := TAU * i / segments
		var p := Vector3(cos(a), 0.003, sin(a)) * HELIPAD_RADIUS
		var length := TAU * HELIPAD_RADIUS / segments + 0.02
		_batch(mat_paint_white, Vector3(length, 0.006, 0.22), Transform3D(Basis(Vector3.UP, -a + PI / 2.0), p))
	for x in [-0.7, 0.7]:
		_batch(mat_paint_yellow, Vector3(0.38, 0.006, 2.6), Transform3D(Basis(), Vector3(x, 0.004, 0)))
	_batch(mat_paint_yellow, Vector3(1.4, 0.006, 0.38), Transform3D(Basis(), Vector3(0, 0.004, 0)))
	for side in 4:
		var horizontal := side < 2
		var sign := -1.0 if side % 2 == 0 else 1.0
		for dash in 12:
			var along := -3.6 + 0.3 + dash * 0.6
			var pos := Vector3(along, 0.003, sign * 3.6) if horizontal else Vector3(sign * 3.6, 0.003, along)
			var size := Vector3(0.38, 0.006, 0.1) if horizontal else Vector3(0.1, 0.006, 0.38)
			_batch(mat_paint_yellow, size, Transform3D(Basis(), pos))
	# Low perimeter lights around the helipad.
	for i in 16:
		var a := TAU * i / 16.0
		_batch(mat_bulb if i % 2 == 0 else mat_paint_white, Vector3(0.12, 0.05, 0.12), Transform3D(Basis(), Vector3(cos(a), 0.025, sin(a)) * (HELIPAD_RADIUS + 0.45)))


func _build_parapet() -> void:
	for side in 4:
		var basis := Basis(Vector3.UP, side * PI / 2.0)
		var out := basis * Vector3(0, 0, 1)
		_batch(mat_wall, Vector3(ROOF * 2.0 + 0.6, PARAPET_HEIGHT, 0.3), Transform3D(basis, out * (ROOF + 0.15) + Vector3.UP * PARAPET_HEIGHT / 2.0))
		_batch(mat_wall, Vector3(ROOF * 2.0 + 0.8, 0.08, 0.42), Transform3D(basis, out * (ROOF + 0.15) + Vector3.UP * (PARAPET_HEIGHT + 0.04)))
		# Railing on top of the parapet.
		_batch(mat_rail, Vector3(ROOF * 2.0, 0.05, 0.05), Transform3D(basis, out * (ROOF + 0.1) + Vector3.UP * (PARAPET_HEIGHT + 0.95)))
		_batch(mat_rail, Vector3(ROOF * 2.0, 0.035, 0.035), Transform3D(basis, out * (ROOF + 0.1) + Vector3.UP * (PARAPET_HEIGHT + 0.5)))
		for i in 27:
			var along := -ROOF + i * 1.0
			_batch(mat_rail, Vector3(0.04, 0.95, 0.04), Transform3D(basis, out * (ROOF + 0.1) + basis * Vector3(along, 0, 0) + Vector3.UP * (PARAPET_HEIGHT + 0.475)))


# --- Rooftop structures --------------------------------------------------------

func _build_structures() -> void:
	# Stairwell hut (back right) with a lit door window and a lamp over the door.
	var hut := Vector3(8.5, 0, -9.5)
	_batch(mat_wall, Vector3(4.0, 3.2, 3.0), Transform3D(Basis(), hut + Vector3(0, 1.6, 0)))
	_batch(mat_wall, Vector3(4.3, 0.15, 3.3), Transform3D(Basis(), hut + Vector3(0, 3.27, 0)))
	_batch(mat_door, Vector3(1.0, 2.1, 0.06), Transform3D(Basis(), hut + Vector3(-0.6, 1.05, 1.52)))
	_batch(mat_window, Vector3(0.5, 0.35, 0.07), Transform3D(Basis(), hut + Vector3(-0.6, 1.65, 1.53)))
	_batch(mat_bulb, Vector3(0.3, 0.12, 0.15), Transform3D(Basis(), hut + Vector3(-0.6, 2.45, 1.6)))
	var door_lamp := OmniLight3D.new()
	door_lamp.position = hut + Vector3(-0.6, 2.3, 1.9)
	door_lamp.light_color = Color(1.0, 0.8, 0.5)
	door_lamp.light_energy = 1.5
	door_lamp.omni_range = 4.0
	_add(stage, door_lamp, "DoorLamp")

	# AC units (left side and back), each with a fan grille on top.
	for spot in [Vector3(-9.5, 0, -2.0), Vector3(-9.5, 0, 1.2), Vector3(-3.5, 0, -10.5), Vector3(0.5, 0, -10.5)]:
		_batch(mat_metal, Vector3(1.8, 1.1, 1.4), Transform3D(Basis(), spot + Vector3(0, 0.55, 0)))
		_batch(mat_dark_metal, Vector3(1.85, 0.08, 1.45), Transform3D(Basis(), spot + Vector3(0, 0.06, 0)))
		var fan := _cylinder(0.5, 0.06, mat_dark_metal)
		fan.position = spot + Vector3(0, 1.12, 0)
		_add(stage, fan, "Fan%d" % _batches.size())
		for r in 4:
			_batch(mat_metal, Vector3(1.0, 0.02, 0.03), Transform3D(Basis(Vector3.UP, r * PI / 4.0), spot + Vector3(0, 1.16, 0)))
		# Ducts running into the deck.
		_batch(mat_metal, Vector3(0.35, 0.35, 1.2), Transform3D(Basis(), spot + Vector3(0.5, 0.25, -1.2)))

	# Water tower on steel legs (back left corner).
	var tower := Vector3(-9.0, 0, -9.0)
	for leg in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
		_batch(mat_dark_metal, Vector3(0.16, 3.0, 0.16), Transform3D(Basis(), tower + Vector3(leg.x, 1.5, leg.y) * Vector3(1.1, 1, 1.1)))
	for y in [1.0, 2.0]:
		_batch(mat_dark_metal, Vector3(2.3, 0.08, 0.08), Transform3D(Basis(), tower + Vector3(0, y, 1.1)))
		_batch(mat_dark_metal, Vector3(2.3, 0.08, 0.08), Transform3D(Basis(), tower + Vector3(0, y, -1.1)))
		_batch(mat_dark_metal, Vector3(0.08, 0.08, 2.3), Transform3D(Basis(), tower + Vector3(1.1, y, 0)))
		_batch(mat_dark_metal, Vector3(0.08, 0.08, 2.3), Transform3D(Basis(), tower + Vector3(-1.1, y, 0)))
	var tank := _cylinder(1.5, 2.6, mat_tank)
	tank.position = tower + Vector3(0, 4.3, 0)
	_add(stage, tank, "WaterTank")
	var roof := CylinderMesh.new()
	roof.top_radius = 0.05
	roof.bottom_radius = 1.65
	roof.height = 1.0
	roof.radial_segments = 20
	roof.material = mat_dark_metal
	var cone := MeshInstance3D.new()
	cone.mesh = roof
	cone.position = tower + Vector3(0, 6.1, 0)
	_add(stage, cone, "WaterTankRoof")
	for band_y in [3.4, 4.3, 5.2]:
		var band := _cylinder(1.53, 0.07, mat_dark_metal)
		band.position = tower + Vector3(0, band_y, 0)
		_add(stage, band, "TankBand%d" % int(band_y * 10))

	# Antenna mast with a red aircraft warning light (back, behind the fight).
	var mast := Vector3(3.0, 0, -11.8)
	_batch(mat_dark_metal, Vector3(0.12, 9.0, 0.12), Transform3D(Basis(), mast + Vector3(0, 4.5, 0)))
	for y in [3.0, 5.5, 7.5]:
		_batch(mat_dark_metal, Vector3(1.0 - y * 0.08, 0.05, 0.05), Transform3D(Basis(), mast + Vector3(0, y, 0)))
	_batch(mat_red_light, Vector3(0.22, 0.22, 0.22), Transform3D(Basis(), mast + Vector3(0, 9.1, 0)))
	var beacon := OmniLight3D.new()
	beacon.position = mast + Vector3(0, 9.1, 0)
	beacon.light_color = Color(1.0, 0.15, 0.08)
	beacon.light_energy = 1.0
	beacon.omni_range = 4.0
	_add(stage, beacon, "Beacon")


## Neon "FIGHT NIGHT" sign on a steel frame at the back left, glowing pink and cyan.
## Kept low enough to stay below the HUD in the fight camera.
func _build_neon_sign() -> void:
	var at := Vector3(-3.5, 0, -12.2)
	for x in [-2.6, 2.6]:
		_batch(mat_dark_metal, Vector3(0.14, 4.0, 0.14), Transform3D(Basis(), at + Vector3(x, 2.0, 0)))
	_batch(mat_dark_metal, Vector3(5.6, 2.0, 0.08), Transform3D(Basis(), at + Vector3(0, 2.9, -0.1)))
	for y in [1.9, 3.9]:
		_batch(mat_dark_metal, Vector3(5.6, 0.1, 0.12), Transform3D(Basis(), at + Vector3(0, y, 0)))
	var fight := _neon("FIGHT", 230, NEON_PINK)
	fight.position = at + Vector3(0, 3.3, 0.0)
	_add(stage, fight, "NeonFight")
	var night := _neon("NIGHT", 170, NEON_CYAN)
	night.position = at + Vector3(0, 2.4, 0.0)
	_add(stage, night, "NeonNight")
	for color_pos in [[NEON_PINK, Vector3(-1.2, 3.3, 1.2)], [NEON_CYAN, Vector3(1.2, 2.4, 1.2)]]:
		var glow := OmniLight3D.new()
		glow.position = at + color_pos[1]
		glow.light_color = color_pos[0]
		glow.light_energy = 2.2
		glow.omni_range = 7.0
		_add(stage, glow, "NeonGlow%d" % int(color_pos[1].x > 0))


## Two strings of warm bulbs sagging between the hut, the sign and the mast.
func _build_string_lights() -> void:
	var strands := [[Vector3(-6.2, 4.0, -12.0), Vector3(6.5, 3.2, -8.0)], [Vector3(-12.6, 2.6, -6.0), Vector3(-6.2, 4.0, -12.0)],
		[Vector3(6.5, 3.2, -8.0), Vector3(12.6, 2.5, -3.0)]]
	for strand in strands:
		var a: Vector3 = strand[0]
		var b: Vector3 = strand[1]
		var bulbs := int(a.distance_to(b) / 0.7)
		var previous := a
		for i in range(1, bulbs + 1):
			var t := float(i) / bulbs
			var p := a.lerp(b, t) + Vector3.DOWN * sin(t * PI) * 0.8 # sag
			var mid := (previous + p) / 2.0
			_batch(mat_dark_metal, Vector3(0.012, 0.012, previous.distance_to(p)), Transform3D(Basis.looking_at(p - previous), mid))
			if i < bulbs:
				_batch(mat_bulb, Vector3(0.07, 0.1, 0.07), Transform3D(Basis(), p + Vector3.DOWN * 0.07))
			previous = p


# --- Helpers ---------------------------------------------------------------------

func _batch(material: Material, size: Vector3, xform: Transform3D) -> void:
	var st: SurfaceTool = _batches.get(material)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[material] = st
	var box := BoxMesh.new()
	box.size = size
	st.append_from(box, 0, xform)


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


func _cylinder(radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
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


## Poly Haven PBR set (base path without _diff_1k.jpg etc.), world-triplanar.
func _textured(base: String, tint: Color, tiling: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = load(base + "_diff_1k.jpg")
	m.normal_enabled = true
	m.normal_texture = load(base + "_nor_gl_1k.jpg")
	m.roughness_texture = load(base + "_rough_1k.jpg")
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


## Glowing neon text facing +Z (toward the fight). HDR modulate drives the glow.
func _neon(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.004
	label.modulate = Color(color.r * 3.0, color.g * 3.0, color.b * 3.0)
	label.outline_size = 18
	label.outline_modulate = Color(color.r, color.g, color.b, 0.35)
	label.shaded = false
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label
