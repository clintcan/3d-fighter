extends SceneTree
## Generates extra hairstyles from the Quaternius hair pieces.
## Run: godot_console --headless --path . -s res://tools/build_hair.gd
##
## Hair_Bob (Mira): Hair_Long cut to an A-line bob, chin length at the front and shorter
## at the nape. Triangles are clipped exactly at the cut line (positions, normals, UVs and
## bone weights interpolated), so the ends are a clean line. Saved as a scene holding one
## skinned MeshInstance3D, like the imported pieces, so FighterModel attaches it the same way.

const SOURCE := "res://assets/characters/hair/Hair_Long.gltf"
const OUT_MESH := "res://assets/characters/hair/Hair_Bob_mesh.res"
const OUT_SCENE := "res://assets/characters/hair/Hair_Bob.tscn"
const FRONT_CUT := 1.555 # metres (T-pose); the female neck joint is at 1.485
const NAPE_RAISE := 0.035 # the back is cut this much higher
const HAIR_ROUGHNESS := 1.0 # like Hair_SimpleParted's material
const HAIR_SPECULAR := 0.25


func _initialize() -> void:
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
	ResourceSaver.save(mesh, OUT_MESH)

	var root := Node3D.new()
	root.name = "Hair_Bob"
	var piece := MeshInstance3D.new()
	piece.name = "Hair_Bob"
	piece.mesh = load(OUT_MESH)
	piece.skin = mi.skin
	root.add_child(piece)
	piece.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	var err := ResourceSaver.save(scene, OUT_SCENE)
	print("Hair_Bob: %d -> %d triangles, err=%d" % [indices.size() / 3, kept, err])
	root.free()
	source.free()
	quit()


## Signed distance above the cut (positive = kept). +Z is the face side.
func _above_cut(p: Vector3) -> float:
	var back := clampf(-p.z / 0.15, 0.0, 1.0)
	return p.y - (FRONT_CUT + NAPE_RAISE * back)


func _clip(polygon: Array) -> Array:
	var values := polygon.map(func(v: Dictionary) -> float: return _above_cut(v.p))
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
