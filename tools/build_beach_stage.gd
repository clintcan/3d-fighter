extends SceneTree
## Builds the beach stage (res://scenes/stages/beach.tscn): a tropical beach at midday.
## A sand arena marked by a ring of tiki torches, turquoise sea (custom shader) rolling
## onto the shore behind the fight, leaning palm trees, a thatched tiki bar, a lifeguard
## tower, beach umbrellas and surfboards, rocks, and a beach crowd on the sand.
## Re-run after changing anything below.
##
## Run: godot_console --headless --path . -s res://tools/build_beach_stage.gd
##
## Layout: sand top at y = 0; the waterline is at z = -12.5 (sea toward -Z, behind the
## fight). Everything tall is more than 8 m out, so nothing needs hiding. Repeated
## geometry is merged into one mesh per material.

const OUTPUT := "res://scenes/stages/beach.tscn"
const TEX := "res://assets/stages/beach/textures/"
const SKY := "res://assets/stages/beach/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
const OCEAN_SHADER := "res://assets/stages/beach/ocean.gdshader"
const STAGE_SCRIPT := "res://scripts/stages/stage.gd"
const CROWD_SCRIPT := "res://scripts/stages/crowd.gd"

const SHORE_Z := -12.5
## Direction toward the sun once the sky is turned 180° (sun high behind the camera, a
## little to the left), measured from the HDRI: 48° elevation.
const SUN_DIR := Vector3(-0.376, 0.743, 0.553)

var stage: Node3D
var _batches := {}
var _rng := RandomNumberGenerator.new()
var mat_sand: StandardMaterial3D
var mat_wet_sand: StandardMaterial3D
var mat_bark: StandardMaterial3D
var mat_leaf: StandardMaterial3D
var mat_bamboo: StandardMaterial3D
var mat_thatch: StandardMaterial3D
var mat_white_wood: StandardMaterial3D
var mat_red: StandardMaterial3D
var mat_rock: StandardMaterial3D
var mat_coconut: StandardMaterial3D
var mat_flame: StandardMaterial3D
var mat_dark: StandardMaterial3D
var mat_rope: StandardMaterial3D
var _fabric := []


func _initialize() -> void:
	_rng.seed = 808
	stage = Node3D.new()
	stage.name = "Beach"
	stage.set_script(load(STAGE_SCRIPT))
	stage.set("rope_line", 50.0)
	stage.set("music", &"beach")

	_make_materials()
	_build_environment()
	_build_lights()
	_build_ground()
	_build_sea()
	_build_torches()
	_build_palms()
	_build_tiki_bar(Vector3(10.5, 0, -6.5))
	_build_lifeguard_tower(Vector3(-11.0, 0, -8.5))
	_build_umbrellas()
	_build_rocks()
	_build_crowd()
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
	mat_sand = _textured("coast_sand_01", Color(1.18, 1.05, 0.86), 0.35)
	mat_wet_sand = _textured("coast_sand_01", Color(0.78, 0.66, 0.52), 0.35)
	mat_wet_sand.roughness = 0.35
	mat_bark = _textured("palm_tree_bark", Color(0.85, 0.75, 0.62), 1.0)
	mat_leaf = _material(Color(0.24, 0.55, 0.16), 0.0, 0.6)
	mat_leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_bamboo = _textured("bamboo_wall", Color(1.0, 0.92, 0.75), 1.0)
	mat_thatch = _textured("thatch_roof_angled", Color(1.0, 0.9, 0.7), 0.7)
	mat_white_wood = _material(Color(0.93, 0.93, 0.9), 0.0, 0.7)
	mat_red = _material(Color(0.85, 0.15, 0.12), 0.0, 0.6)
	mat_rock = _material(Color(0.42, 0.4, 0.38), 0.0, 0.85)
	mat_coconut = _material(Color(0.32, 0.2, 0.1), 0.0, 0.7)
	mat_flame = _emissive(Color(1.0, 0.6, 0.2), 4.0)
	mat_dark = _material(Color(0.12, 0.09, 0.07), 0.0, 0.8)
	mat_rope = _material(Color(0.75, 0.62, 0.42), 0.0, 0.9)
	for c in [Color(0.92, 0.2, 0.2), Color(0.98, 0.78, 0.15), Color(0.1, 0.6, 0.78), Color(0.95, 0.45, 0.65), Color(0.2, 0.72, 0.45), Color(0.98, 0.98, 0.95)]:
		_fabric.append(_material(c, 0.0, 0.8))


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
	env.sky_rotation = Vector3(0, PI, 0) # sun behind the camera, the sea toward the clouds
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.95
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.ssao_enabled = false # too costly on integrated GPUs (see the stage notes)
	env.fog_enabled = true # light haze toward the horizon
	env.fog_light_color = Color(0.75, 0.85, 0.95)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_add(stage, world_env, "WorldEnvironment")


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(Basis.looking_at(-SUN_DIR), Vector3.ZERO)
	sun.light_energy = 2.0
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	_add(stage, sun, "Sun")
	var bounce := DirectionalLight3D.new() # warm light bounced off the sand
	bounce.rotation_degrees = Vector3(35, 20, 0)
	bounce.light_energy = 0.25
	bounce.light_color = Color(1.0, 0.85, 0.65)
	_add(stage, bounce, "SandBounce")


# --- Ground and sea ------------------------------------------------------------------

func _build_ground() -> void:
	# Dry sand, then a darker wet strip sloping gently into the water.
	# Dry sand (z -9 .. 40), level wet sand to the waterline, then a slope under the sea:
	# all tops meet at y = 0, so there's no ledge.
	_batch(mat_sand, Vector3(80, 0.4, 49), Transform3D(Basis(), Vector3(0, -0.2, 15.5)))
	_batch(mat_wet_sand, Vector3(80, 0.4, 3.5), Transform3D(Basis(), Vector3(0, -0.2, -10.75)))
	# Negative angle: the far (-z) end goes down, under the sea.
	var slope := Basis(Vector3.RIGHT, deg_to_rad(-6.0))
	_batch(mat_wet_sand, Vector3(80, 0.4, 12.0), Transform3D(slope, Vector3(0, -0.2 - sin(deg_to_rad(6.0)) * 6.0, SHORE_Z - 6.0 * cos(deg_to_rad(6.0)) + 0.05)))
	# A ring raked into the sand marks the fighting area.
	var segments := 64
	for i in segments:
		var a := TAU * i / segments
		var p := Vector3(cos(a), 0.004, sin(a)) * 4.4
		_batch(mat_wet_sand, Vector3(TAU * 4.4 / segments + 0.03, 0.01, 0.12), Transform3D(Basis(Vector3.UP, -a + PI / 2.0), p))


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 450)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	var material := ShaderMaterial.new()
	material.shader = load(OCEAN_SHADER)
	material.set_shader_parameter("shore_z", SHORE_Z)
	plane.material = material
	var sea := MeshInstance3D.new()
	sea.mesh = plane
	sea.position = Vector3(0, -0.06, SHORE_Z - 225.0 + 0.6)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(stage, sea, "Sea")


# --- Props -----------------------------------------------------------------------------

## Tiki torches around the back and sides of the arena (none in front of the camera).
func _build_torches() -> void:
	var count := 7
	for i in count:
		var a := deg_to_rad(205.0 + i * (130.0 / (count - 1))) # arc behind the fight
		var p := Vector3(cos(a) * 7.5, 0, sin(a) * 7.5)
		_batch(mat_bamboo, Vector3(0.09, 1.9, 0.09), Transform3D(Basis(), p + Vector3(0, 0.95, 0)))
		_batch(mat_dark, Vector3(0.18, 0.22, 0.18), Transform3D(Basis(), p + Vector3(0, 1.98, 0)))
		var flame := CylinderMesh.new()
		flame.top_radius = 0.0
		flame.bottom_radius = 0.1
		flame.height = 0.32
		flame.radial_segments = 8
		flame.material = mat_flame
		var mi := MeshInstance3D.new()
		mi.mesh = flame
		mi.position = p + Vector3(0, 2.24, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(stage, mi, "TorchFlame%d" % i)


## Leaning palm trees: a curved, ringed trunk, a crown of arching fronds, coconuts.
func _build_palms() -> void:
	var spots := [Vector3(-8.5, 0, -4.5), Vector3(-13.0, 0, -1.0), Vector3(8.8, 0, -2.5), Vector3(14.0, 0, 2.0),
		Vector3(-6.0, 0, -10.0), Vector3(6.5, 0, -10.5), Vector3(-16.0, 0, -7.0), Vector3(17.0, 0, -5.0)]
	for spot: Vector3 in spots:
		var lean_dir := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-0.6, 1.0)).normalized()
		var height := _rng.randf_range(5.5, 7.5)
		var lean := _rng.randf_range(1.2, 2.6)
		var prev := spot
		var segments := 12
		for s in range(1, segments + 1):
			var t := float(s) / segments
			var p := spot + Vector3.UP * height * t + lean_dir * lean * t * t
			var dir := (p - prev).normalized()
			var basis := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir)) if dir.cross(Vector3.UP).length() > 0.001 else Basis()
			var radius := lerpf(0.26, 0.16, t)
			_batch_cylinder(mat_bark, radius * 0.92, radius, prev.distance_to(p) + 0.04, Transform3D(basis, (prev + p) / 2.0))
			prev = p
		var top := prev
		for c in 4:
			var a := TAU * c / 4.0 + 0.4
			_batch_sphere(mat_coconut, 0.14, top + Vector3(cos(a) * 0.22, -0.25, sin(a) * 0.22))
		var fronds := 9
		for f in fronds:
			var a := TAU * f / fronds + _rng.randf_range(-0.2, 0.2)
			_frond(top, Vector3(cos(a), 0, sin(a)), _rng.randf_range(2.4, 3.2))


## One frond: a leaf strip that arcs up and droops, made of short, tapering, V-angled
## segments.
func _frond(base: Vector3, dir: Vector3, length: float) -> void:
	var steps := 8
	var prev := base
	var side := dir.cross(Vector3.UP).normalized()
	for s in range(1, steps + 1):
		var t := float(s) / steps
		var p := base + dir * length * t + Vector3.UP * (0.9 * t - 2.0 * t * t)
		var along := (p - prev).normalized()
		var width := lerpf(0.75, 0.12, t)
		for tilt in [-0.45, 0.45]: # two halves angled up into a shallow V
			var normal := along.cross(side).normalized().rotated(along, tilt)
			var x_axis := along.cross(normal).normalized()
			var basis := Basis(x_axis, normal, along)
			var offset := x_axis * width * 0.25 * signf(tilt)
			_batch(mat_leaf, Vector3(width * 0.5, 0.02, prev.distance_to(p) + 0.05), Transform3D(basis, (prev + p) / 2.0 + offset))
		prev = p


## A thatched tiki bar: bamboo counter, posts, stools and a thatch roof.
func _build_tiki_bar(at: Vector3) -> void:
	_batch(mat_bamboo, Vector3(3.6, 1.1, 0.7), Transform3D(Basis(), at + Vector3(0, 0.55, 1.2)))
	_batch(mat_dark, Vector3(3.8, 0.08, 0.9), Transform3D(Basis(), at + Vector3(0, 1.14, 1.2)))
	for x in [-1.8, 1.8]:
		for z in [-1.4, 1.4]:
			_batch(mat_bamboo, Vector3(0.14, 2.7, 0.14), Transform3D(Basis(), at + Vector3(x, 1.35, z)))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.05
	roof.bottom_radius = 3.1
	roof.height = 1.5
	roof.radial_segments = 4
	roof.material = mat_thatch
	var roof_mi := MeshInstance3D.new()
	roof_mi.mesh = roof
	roof_mi.position = at + Vector3(0, 3.4, 0)
	roof_mi.rotation.y = PI / 4.0
	_add(stage, roof_mi, "TikiRoof")
	for i in 3:
		var stool := at + Vector3(-1.2 + i * 1.2, 0, 2.1)
		_batch(mat_bamboo, Vector3(0.08, 0.75, 0.08), Transform3D(Basis(), stool + Vector3(0, 0.37, 0)))
		_batch_cylinder(mat_dark, 0.22, 0.22, 0.06, Transform3D(Basis(), stool + Vector3(0, 0.77, 0)))
	_batch(mat_white_wood, Vector3(1.6, 0.5, 0.05), Transform3D(Basis(), at + Vector3(0, 2.45, 1.45))) # sign


## Lifeguard tower: white stilts, a platform with a striped cabin, ladder and red flag.
func _build_lifeguard_tower(at: Vector3) -> void:
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_batch(mat_white_wood, Vector3(0.14, 2.4, 0.14), Transform3D(Basis(), at + Vector3(x, 1.2, z)))
	_batch(mat_white_wood, Vector3(2.6, 0.12, 2.6), Transform3D(Basis(), at + Vector3(0, 2.45, 0)))
	_batch(mat_white_wood, Vector3(1.9, 1.6, 1.9), Transform3D(Basis(), at + Vector3(0, 3.3, 0)))
	for y in [2.75, 3.25, 3.75]:
		_batch(mat_red, Vector3(1.94, 0.16, 1.94), Transform3D(Basis(), at + Vector3(0, y, 0)))
	_batch(mat_red, Vector3(2.4, 0.12, 2.4), Transform3D(Basis(), at + Vector3(0, 4.15, 0)))
	var ramp := Basis(Vector3.RIGHT, deg_to_rad(-35.0))
	_batch(mat_white_wood, Vector3(0.7, 0.06, 3.0), Transform3D(ramp, at + Vector3(0, 1.2, 2.3)))
	_batch(mat_white_wood, Vector3(0.05, 1.5, 0.05), Transform3D(Basis(), at + Vector3(1.1, 4.9, -1.1)))
	_batch(mat_red, Vector3(0.6, 0.4, 0.02), Transform3D(Basis(), at + Vector3(1.4, 5.4, -1.1)))


## Striped umbrellas with towels beneath, and surfboards stuck upright in the sand.
func _build_umbrellas() -> void:
	var spots := [Vector3(-9.5, 0, 3.5), Vector3(-12.5, 0, 6.0), Vector3(9.5, 0, 4.5), Vector3(12.0, 0, 7.5), Vector3(-4.5, 0, -11.0), Vector3(3.0, 0, -11.5)]
	for i in spots.size():
		var at: Vector3 = spots[i]
		var tilt := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.05, 0.18))
		_batch(mat_white_wood, Vector3(0.05, 2.2, 0.05), Transform3D(tilt, at + tilt * Vector3(0, 1.1, 0)))
		var canopy := CylinderMesh.new()
		canopy.top_radius = 0.04
		canopy.bottom_radius = 1.25
		canopy.height = 0.45
		canopy.radial_segments = 12
		canopy.material = _fabric[i % _fabric.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = canopy
		mi.transform = Transform3D(tilt, at + tilt * Vector3(0, 2.2, 0))
		_add(stage, mi, "Umbrella%d" % i)
		_batch(_fabric[(i + 2) % _fabric.size()], Vector3(0.8, 0.02, 1.7), Transform3D(Basis(Vector3.UP, _rng.randf() * PI), at + Vector3(0.6, 0.01, 0.4)))
	for i in 4:
		var at := Vector3(-7.5 + i * 0.7, 0, 7.5) if i < 2 else Vector3(10.5 + (i - 2) * 0.7, 0, -1.5)
		var board := Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3)) * Basis(Vector3.RIGHT, _rng.randf_range(-0.1, 0.1))
		_batch(_fabric[(i + 1) % _fabric.size()], Vector3(0.5, 2.1, 0.07), Transform3D(board, at + Vector3(0, 0.95, 0)))


func _build_rocks() -> void:
	for i in 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * _rng.randf_range(9.0, 22.0), -0.15, SHORE_Z + _rng.randf_range(-2.0, 2.5))
		var size := _rng.randf_range(0.4, 1.4)
		var rock := SphereMesh.new()
		rock.radius = size
		rock.height = size * 1.3
		rock.radial_segments = 7
		rock.rings = 4
		_append(mat_rock, rock, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(1.3, 0.7, 1.0)), at))


## Spectators sitting on the sand along both sides.
func _build_crowd() -> void:
	var crowd := MultiMeshInstance3D.new()
	crowd.set_script(load(CROWD_SCRIPT))
	crowd.set("rows", 3)
	crowd.set("tier_start", 8.6)
	crowd.set("tier_depth", 0.85)
	crowd.set("tier_rise", 0.0)
	crowd.set("row_width", 13.0)
	crowd.set("seat_spacing", 0.75)
	crowd.set("floor_y", -0.15)
	crowd.set("empty_seat_chance", 0.4)
	crowd.set("crowd_seed", 1401)
	crowd.set("sides", PackedInt32Array([1, 3]))
	crowd.set("palette", PackedColorArray([Color(0.95, 0.3, 0.3), Color(0.98, 0.8, 0.2), Color(0.2, 0.65, 0.85),
		Color(0.95, 0.5, 0.7), Color(0.3, 0.8, 0.5), Color(0.98, 0.98, 0.95), Color(0.95, 0.6, 0.2)]))
	_add(stage, crowd, "Crowd")


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


func _batch_sphere(material: Material, radius: float, at: Vector3) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	_append(material, sphere, Transform3D(Basis(), at))


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
