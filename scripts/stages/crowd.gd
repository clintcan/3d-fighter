class_name Crowd
extends MultiMeshInstance3D
## Low-poly spectators on tiered seating around the ring (or kneeling students along a
## dojo's walls), generated at runtime (a MultiMesh built in a headless tool doesn't keep
## its instance data). One merged torso + head mesh, instanced per seat with a random
## shirt color, or a color from `palette`.

@export var rows := 9
## Distance from the ring center to the first row, and per-row depth/rise.
@export var tier_start := 9.5
@export var tier_depth := 0.9
@export var tier_rise := 0.45
@export var row_width := 24.0
@export var seat_spacing := 0.62
@export var floor_y := -1.0
@export_range(0.0, 1.0) var empty_seat_chance := 0.18
@export var crowd_seed := 1984
## Which sides to fill (0 = +Z, 1 = +X, 2 = -Z, 3 = -X).
@export var sides := PackedInt32Array([0, 1, 2, 3])
## If set, clothing colors are picked from here (with slight variation).
@export var palette := PackedColorArray()
## Kneeling (seiza) students in gi and hakama instead of seated spectators. The figure
## carries its own colors; the instance color only varies it slightly.
@export var kneeling := false
## Life in the seats (assets/stages/shared/crowd.gdshader): metres each figure sways, and
## how far cheering spectators spring up now and then (0 = they stay seated).
@export var sway := 0.0
@export var jump := 0.0

const CROWD_SHADER := "res://assets/stages/shared/crowd.gdshader"


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = crowd_seed
	if sway > 0.0 or jump > 0.0:
		var animated := ShaderMaterial.new()
		animated.shader = load(CROWD_SHADER)
		animated.set_shader_parameter("sway", sway)
		animated.set_shader_parameter("jump", jump)
		material_override = animated
	else:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.9
		material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var seats: Array[Transform3D] = []
	var colors: Array[Color] = []
	var seats_per_row := int(row_width / seat_spacing) - 2
	for side in sides:
		var angle := side * PI / 2.0
		var out := Vector3(sin(angle), 0, cos(angle))
		var tangent := Vector3(cos(angle), 0, -sin(angle))
		for row in rows:
			for seat in seats_per_row:
				if rng.randf() < empty_seat_chance:
					continue
				var along := (seat - seats_per_row / 2.0) * seat_spacing + rng.randf_range(-0.08, 0.08)
				var dist := tier_start + row * tier_depth + rng.randf_range(-0.1, 0.1)
				var pos := out * dist + tangent * along + Vector3.UP * (floor_y + tier_rise * (row + 1))
				# Face the ring, with a little variety.
				var facing := Basis(Vector3.UP, angle + PI + rng.randf_range(-0.3, 0.3))
				seats.append(Transform3D(facing.scaled(Vector3.ONE * rng.randf_range(0.9, 1.1)), pos))
				if palette.is_empty():
					colors.append(Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.8), rng.randf_range(0.08, 0.3)))
				else:
					colors.append(palette[rng.randi() % palette.size()].darkened(rng.randf_range(0.0, 0.15)))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _kneeling_mesh() if kneeling else _spectator_mesh()
	mm.instance_count = seats.size()
	for i in seats.size():
		mm.set_instance_transform(i, seats[i])
		mm.set_instance_color(i, colors[i])
	multimesh = mm


## Seiza figure facing +Z: folded legs in a dark hakama, white gi torso with a black
## belt, skin-toned head with dark hair. Colors are baked into the vertices.
func _kneeling_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hakama := Color(0.1, 0.11, 0.2)
	var gi := Color(0.93, 0.92, 0.89)
	var legs := CapsuleMesh.new()
	legs.radius = 0.19
	legs.height = 0.62
	_append_colored(st, legs, Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3(1.25, 1.0, 1.0)), Vector3(0, 0.17, -0.05)), hakama)
	var hips := SphereMesh.new()
	hips.radius = 0.2
	hips.height = 0.36
	_append_colored(st, hips, Transform3D(Basis().scaled(Vector3(1.15, 1.0, 1.0)), Vector3(0, 0.3, -0.12)), hakama)
	var torso := CapsuleMesh.new()
	torso.radius = 0.17
	torso.height = 0.56
	_append_colored(st, torso, Transform3D(Basis().scaled(Vector3(1.1, 1.0, 0.85)), Vector3(0, 0.6, -0.1)), gi)
	var belt := CylinderMesh.new()
	belt.top_radius = 0.19
	belt.bottom_radius = 0.19
	belt.height = 0.05
	_append_colored(st, belt, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.82)), Vector3(0, 0.44, -0.1)), Color(0.03, 0.03, 0.03))
	var head := SphereMesh.new()
	head.radius = 0.105
	head.height = 0.23
	_append_colored(st, head, Transform3D(Basis(), Vector3(0, 0.98, -0.08)), Color(0.82, 0.62, 0.48))
	var hair := SphereMesh.new()
	hair.radius = 0.11
	hair.height = 0.2
	_append_colored(st, hair, Transform3D(Basis(), Vector3(0, 1.02, -0.11)), Color(0.06, 0.05, 0.04))
	return st.commit()


func _append_colored(st: SurfaceTool, mesh: PrimitiveMesh, xform: Transform3D, color: Color) -> void:
	var arrays := mesh.get_mesh_arrays()
	var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var colors := PackedColorArray()
	colors.resize(count)
	colors.fill(color)
	arrays[Mesh.ARRAY_COLOR] = colors
	var colored := ArrayMesh.new()
	colored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	st.append_from(colored, 0, xform)


func _spectator_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var torso := CapsuleMesh.new()
	torso.radius = 0.2
	torso.height = 0.75
	torso.radial_segments = 8
	torso.rings = 2
	var head := SphereMesh.new()
	head.radius = 0.11
	head.height = 0.22
	head.radial_segments = 8
	head.rings = 4
	st.append_from(torso, 0, Transform3D(Basis(), Vector3(0, 0.375, 0)))
	st.append_from(head, 0, Transform3D(Basis(), Vector3(0, 0.86, 0)))
	return st.commit()
