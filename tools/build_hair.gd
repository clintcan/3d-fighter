extends SceneTree
## Generates extra hairstyles from the Quaternius hair pieces.
## Run: godot_console --headless --path . -s res://tools/build_hair.gd
##
## Hair_Bob (Mira): Hair_Long cut to an A-line bob, chin length at the front and shorter
## at the nape. Triangles are clipped exactly at the cut line (positions, normals, UVs and
## bone weights interpolated), so the ends are a clean line. Saved as a scene holding one
## skinned MeshInstance3D, like the imported pieces, so FighterModel attaches it the same way.
##
## Hair_Bun (Lian): Hair_Long cut close all round (a sleek, pulled-back cap), plus a bun
## at the back of the head and a lacquered hairpin through it, both bound to the Head bone.

const SOURCE := "res://assets/characters/hair/Hair_Long.gltf"
const HAIR_DIR := "res://assets/characters/hair/"
const FRONT_CUT := 1.555 # metres (T-pose); the female neck joint is at 1.485
const NAPE_RAISE := 0.035 # the back is cut this much higher
const BUN_CUT := 1.665 # the bun style: cut above the ears at the sides and front...
const BUN_NAPE := 0.07 # ...and lower toward the nape, where it's gathered up
const BUN_CENTER := Vector3(0.0, 1.705, -0.138)
const BUN_RADII := Vector3(0.056, 0.05, 0.042)
const BUN_UV := Rect2(0.32, 0.3, 0.3, 0.35) # a patch of strands in the hair texture
const HEAD_BIND := 6 # Hair_Long's skin bind for the Head bone
const PIN_FROM := Vector3(-0.078, 1.752, -0.135) # the hairpin, through the bun
const PIN_TO := Vector3(0.07, 1.668, -0.15)
const PIN_RADIUS := 0.0045
const PIN_COLOR := Color(0.55, 0.06, 0.05) # red lacquer
const HAIR_ROUGHNESS := 1.0 # like Hair_SimpleParted's material
const HAIR_SPECULAR := 0.25


var _cut: Callable # signed distance above the cut (positive = kept)


func _initialize() -> void:
	_build_style("Hair_Bob", _above_cut, false)
	_build_style("Hair_Bun", _above_bun_cut, true)
	quit()


func _build_style(style: String, cut: Callable, bun: bool) -> void:
	_cut = cut
	var out_mesh := HAIR_DIR + style + "_mesh.res"
	var out_scene := HAIR_DIR + style + ".tscn"
	var source := (load(SOURCE) as PackedScene).instantiate()
	var mi := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kept := 0
	for t in indices.size() / 3:
		var polygon: Array = []
		for k in 3:
			var c := indices[t * 3 + k]
			polygon.append({p = verts[c], n = normals[c], uv = uvs[c],
				bones = bones.slice(c * 4, c * 4 + 4), weights = weights.slice(c * 4, c * 4 + 4)})
		polygon = _clip(polygon)
		for i in range(1, polygon.size() - 1):
			for v: Dictionary in [polygon[0], polygon[i], polygon[i + 1]]:
				st.set_normal(v.n)
				st.set_uv(v.uv)
				st.set_bones(v.bones)
				st.set_weights(v.weights)
				st.add_vertex(v.p)
			kept += 1
	st.index()
	st.generate_tangents()
	var mesh := st.commit()
	# Hair_Long's material is fairly glossy (roughness 0.71): fine on blonde hair, but on
	# dark hair the ring's reflections turn it grey. The bob gets a more matte copy
	# (the name keeps the MI_Hair prefix, so FighterModel still tints it).
	var material := mi.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	material.roughness = HAIR_ROUGHNESS
	material.metallic_specular = HAIR_SPECULAR
	mesh.surface_set_material(0, material)
	if bun:
		_add_bun(mesh, material)
	ResourceSaver.save(mesh, out_mesh)

	var root := Node3D.new()
	root.name = style
	var piece := MeshInstance3D.new()
	piece.name = style
	piece.mesh = load(out_mesh)
	piece.skin = mi.skin
	root.add_child(piece)
	piece.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	var err := ResourceSaver.save(scene, out_scene)
	print("%s: %d -> %d triangles, err=%d" % [style, indices.size() / 3, kept, err])
	root.free()
	source.free()


## Signed distance above the cut (positive = kept). +Z is the face side.
func _above_cut(p: Vector3) -> float:
	var back := clampf(-p.z / 0.15, 0.0, 1.0)
	return p.y - (FRONT_CUT + NAPE_RAISE * back)


## The bun style's cut: close all round, a little lower at the nape.
func _above_bun_cut(p: Vector3) -> float:
	var back := clampf((-p.z - 0.02) / 0.1, 0.0, 1.0)
	return p.y - (BUN_CUT - BUN_NAPE * back)


func _clip(polygon: Array) -> Array:
	var values := polygon.map(func(v: Dictionary) -> float: return _cut.call(v.p))
	var out: Array = []
	for i in polygon.size():
		var a: Dictionary = polygon[i]
		var b: Dictionary = polygon[(i + 1) % polygon.size()]
		var da: float = values[i]
		var db: float = values[(i + 1) % polygon.size()]
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			out.append(_blend(a, b, da / (da - db)))
	return out


func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var influence := {}
	for k in 4:
		influence[a.bones[k]] = influence.get(a.bones[k], 0.0) + a.weights[k] * (1.0 - t)
		influence[b.bones[k]] = influence.get(b.bones[k], 0.0) + b.weights[k] * t
	var order := influence.keys()
	order.sort_custom(func(x, y): return influence[x] > influence[y])
	var bone_ids := PackedInt32Array()
	var bone_weights := PackedFloat32Array()
	var total := 0.0
	for k in 4:
		var bone: int = order[k] if k < order.size() else 0
		var weight: float = influence[bone] if k < order.size() else 0.0
		bone_ids.append(bone)
		bone_weights.append(weight)
		total += weight
	for k in 4:
		bone_weights[k] /= maxf(total, 0.0001)
	return {p = a.p.lerp(b.p, t), n = a.n.lerp(b.n, t).normalized(), uv = a.uv.lerp(b.uv, t),
		bones = bone_ids, weights = bone_weights}


## The bun (an ellipsoid with the hair material) and the hairpin through it (its own
## lacquer material, which FighterModel leaves alone), skinned to the Head bone.
func _add_bun(mesh: ArrayMesh, hair: Material) -> void:
	var st := _head_surface()
	var rings := 12
	var segments := 20
	for r in rings:
		for g in segments:
			var corners := [[r, g], [r + 1, g], [r + 1, g + 1], [r, g], [r + 1, g + 1], [r, g + 1]]
			for c: Array in corners:
				var lat := PI * float(c[0]) / rings - PI / 2.0
				var lon := TAU * float(c[1]) / segments
				var unit := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
				st.set_normal((unit / BUN_RADII).normalized())
				st.set_uv(BUN_UV.position + BUN_UV.size * Vector2(float(c[1]) / segments, float(c[0]) / rings))
				st.add_vertex(BUN_CENTER + unit * BUN_RADII)
	_commit_surface(st, mesh, hair, "bun")

	st = _head_surface()
	var axis := (PIN_TO - PIN_FROM).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()
	var up := side.cross(axis)
	var sides := 8
	for k in sides:
		for c in [[0, k], [1, k], [1, k + 1], [0, k], [1, k + 1], [0, k + 1]]:
			var a := TAU * float(c[1]) / sides
			var n := side * cos(a) + up * sin(a)
			st.set_normal(n)
			st.set_uv(Vector2(float(c[1]) / sides, c[0]))
			st.add_vertex((PIN_FROM if c[0] == 0 else PIN_TO) + n * PIN_RADIUS)
	var pin := StandardMaterial3D.new()
	pin.resource_name = "MI_Pin" # not MI_Hair*: FighterModel tints those
	pin.albedo_color = PIN_COLOR
	pin.roughness = 0.35
	_commit_surface(st, mesh, pin, "hairpin")


func _head_surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_bones(PackedInt32Array([HEAD_BIND, 0, 0, 0]))
	st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	return st


func _commit_surface(st: SurfaceTool, mesh: ArrayMesh, material: Material, surface_name: String) -> void:
	st.index()
	st.generate_tangents()
	st.commit(mesh)
	var s := mesh.get_surface_count() - 1
	mesh.surface_set_material(s, material)
	mesh.surface_set_name(s, surface_name)
