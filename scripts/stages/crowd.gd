class_name Crowd
extends MultiMeshInstance3D
## Low-poly spectators on tiered seating around the ring, generated at runtime (a
## MultiMesh built in a headless tool doesn't keep its instance data). One merged
## torso + head mesh, instanced per seat with a random shirt color.

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


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = crowd_seed
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var seats: Array[Transform3D] = []
	var colors: Array[Color] = []
	var seats_per_row := int(row_width / seat_spacing) - 2
	for side in 4:
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
				colors.append(Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.8), rng.randf_range(0.08, 0.3)))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _spectator_mesh()
	mm.instance_count = seats.size()
	for i in seats.size():
		mm.set_instance_transform(i, seats[i])
		mm.set_instance_color(i, colors[i])
	multimesh = mm


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
