extends SceneTree
## Generates each fighter's clothing from their base body mesh and saves it into the
## character data. Run: godot_console --headless --path . -s res://tools/build_outfits.gd
##
## A garment is the part of the body surface inside a region, pushed out along the normals
## by the garment's thickness. Regions are signed-distance functions of the T-pose
## position (positive inside), built from the skeleton's bone landmarks; triangles that
## cross a region's edge are clipped exactly at the zero line, so hems, necklines and
## sleeve ends are clean lines instead of stair-steps. Every vertex keeps (or blends) the
## body's bone weights, so the cloth deforms exactly with the skin under it.
## Layering comes from thickness (a gi jacket sits outside its pants, the belt outside
## both). Trims are split off the same way into their own colour slot: a dobok's black V
## collar, a singlet's gold edging along every opening. Belt knots and tails are small
## boxes bound to the pelvis.
## The body is saved again without the skin triangles a garment fully covers (1.5 cm
## inset), so nothing pokes through and no gap opens at the hems.
## Outfit references: karate gi (cross-over jacket with a V opening, belt, headband),
## Tae Kwon Do dobok (closed V-neck pullover, black collar for black belts), kickboxing
## gear, pro-wrestling singlet with knee pads and boots, brawler tank top and work pants.

const OUT_DIR := "res://assets/characters/outfits/"
const CHARACTER_DIR := "res://data/characters/"
const HIDE_INSET := 0.015 # body skin this far inside a garment's edge is removed
const NECK_RADIUS := 0.072 # the neck hole of tops and jackets
const ARM_LIMIT := 0.35 # |x| beyond this (T-pose) is arm, never legs or torso

enum Slot { MAIN, TRIM, ACCENT }

var _body_skin: Skin
var _pelvis_bind := 0


func _initialize() -> void:
	await process_frame
	var specs := _specs()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for id: String in specs:
		var spec: Dictionary = specs[id]
		var data := load(CHARACTER_DIR + id + ".tres") as CharacterData
		if data == null:
			push_error("No character data for %s" % id)
			continue
		var result := _build(data.model_scene, spec)
		var outfit_path := OUT_DIR + id + "_outfit.res"
		var body_path := OUT_DIR + id + "_body.res"
		ResourceSaver.save(result.outfit, outfit_path)
		ResourceSaver.save(result.body, body_path)
		data.outfit_mesh = load(outfit_path)
		data.outfit_body_mesh = load(body_path)
		data.outfit_colors = spec.colors
		data.alt_outfit_colors = spec.alt_colors
		data.outfit_fabrics.assign(spec.fabrics)
		ResourceSaver.save(data, data.resource_path)
		print("%-7s outfit: %d surfaces, %d triangles; body %d -> %d triangles" % [id, result.outfit.get_surface_count(),
			result.outfit_triangles, result.body_before, result.body_after])
	quit()


# --- Outfits -------------------------------------------------------------------------

## Per character: pieces, colours, alt colours and fabrics per slot. A piece has a slot,
## a thickness (`offset`), a `region` func(p: Vector3, n: Vector3) -> float (signed
## distance, positive inside; `offset` may also be a func(n: Vector3) -> float) and optionally a `trim` func of the same shape (positive =
## trim slot), `hide = false` (don't remove skin under it) and `flat_soles`.
func _specs() -> Dictionary:
	return {
		"kenji": {
			pieces = func(L: Dictionary) -> Array:
				return [
					# Gi jacket: past the hips, sleeves to mid-forearm, a deep V at the chest.
					{slot = Slot.MAIN, offset = 0.026, region = func(p, n):
						return minf(_top(p, L, L.hip - 0.06, L.elbow + (L.wrist - L.elbow) * 0.45), -_v_cut(p, n, L, L.chest - 0.07, 0.075))},
					# Loose gi pants to just above the ankle.
					{slot = Slot.MAIN, offset = 0.018, region = func(p, n): return _legs(p, L.ankle + 0.07, L.waist - 0.02)},
					# Black belt.
					{slot = Slot.TRIM, offset = 0.036, hide = false, region = func(p, n): return _legs(p, L.hip + 0.04, L.hip + 0.085)},
					# Red headband: snug on the forehead, standing off over the hair at the sides
					# and back.
					{slot = Slot.ACCENT, offset = func(n: Vector3) -> float: return lerpf(0.02, 0.009, clampf(n.z * 1.6 - 0.4, 0.0, 1.0)),
						hide = false, region = func(p, n):
						return minf(minf(p.y - (L.head_top - 0.078), (L.head_top - 0.05) - p.y), 0.15 - absf(p.x))},
				],
			belt_knot = {slot = Slot.TRIM, y = 0.0625, offset = 0.036},
			colors = [Color(0.8, 0.79, 0.76), Color(0.07, 0.07, 0.08), Color(0.78, 0.07, 0.07)],
			alt_colors = [Color(0.15, 0.16, 0.2), Color(0.42, 0.24, 0.1), Color(0.8, 0.8, 0.78)],
			fabrics = [&"cotton", &"cotton", &"cotton"],
		},
		"jin": {
			pieces = func(L: Dictionary) -> Array:
				var v_bottom: float = L.chest
				return [
					# Dobok: V-neck pullover to the hips, long sleeves, black V collar.
					{slot = Slot.MAIN, offset = 0.022, trim_slot = Slot.TRIM,
						trim = func(p, n): return _v_cut(p, n, L, v_bottom - 0.035, 0.08) + 0.03,
						region = func(p, n): return minf(_top(p, L, L.hip - 0.05, L.wrist - 0.05), -_v_cut(p, n, L, v_bottom, 0.08))},
					{slot = Slot.MAIN, offset = 0.016, region = func(p, n): return _legs(p, L.ankle + 0.05, L.waist - 0.02)},
					{slot = Slot.TRIM, offset = 0.032, hide = false, region = func(p, n): return _legs(p, L.hip + 0.04, L.hip + 0.085)},
				],
			belt_knot = {slot = Slot.TRIM, y = 0.0625, offset = 0.032},
			colors = [Color(0.8, 0.8, 0.8), Color(0.06, 0.06, 0.07), Color(0.0, 0.0, 0.0)],
			alt_colors = [Color(0.1, 0.1, 0.11), Color(0.72, 0.1, 0.1), Color(0.0, 0.0, 0.0)],
			fabrics = [&"cotton", &"cotton", &"cotton"],
		},
		"rhea": {
			pieces = func(L: Dictionary) -> Array:
				return [
					# Sports crop top: under the bust to the shoulders, scooped neck, sleeveless.
					{slot = Slot.MAIN, offset = 0.005, region = func(p, n):
						return minf(_sleeveless(p, L, L.chest - 0.11, L.shoulder * 0.95), -_scoop(p, L, 0.10, 0.07))},
					# Fight shorts to mid-thigh, covering the waistband.
					{slot = Slot.TRIM, offset = 0.006, region = func(p, n): return _legs(p, L.knee + 0.2, L.waist + 0.03)},
					# Hand wraps over the wrists and palms.
					{slot = Slot.ACCENT, offset = 0.004, region = func(p, n):
						return minf(minf(p.y - (L.arm_y - 0.12), absf(p.x) - (L.wrist - 0.08)), (L.wrist + 0.07) - absf(p.x))},
				],
			colors = [Color(0.8, 0.12, 0.16), Color(0.08, 0.08, 0.1), Color(0.8, 0.79, 0.75)],
			alt_colors = [Color(0.12, 0.32, 0.78), Color(0.8, 0.8, 0.82), Color(0.15, 0.15, 0.18)],
			fabrics = [&"stretch", &"stretch", &"cotton"],
		},
		"valka": {
			pieces = func(L: Dictionary) -> Array:
				var singlet := func(p, n):
					return minf(_sleeveless(p, L, L.knee + 0.24, L.shoulder * 0.95), -_scoop(p, L, 0.11, 0.06))
				return [
					# Wrestling singlet: short legs, scooped neck front and back, gold edging
					# along every opening.
					{slot = Slot.MAIN, offset = 0.006, trim_slot = Slot.TRIM, region = singlet,
						trim = func(p, n): return 0.014 - singlet.call(p, n)},
					# Knee pads and wrestling boots.
					{slot = Slot.ACCENT, offset = 0.028, region = func(p, n): return _legs(p, L.knee - 0.065, L.knee + 0.065)},
					{slot = Slot.ACCENT, offset = 0.012, flat_soles = true, region = func(p, n): return _legs(p, -1.0, L.ankle + 0.22)},
				],
			colors = [Color(0.08, 0.1, 0.3), Color(0.88, 0.67, 0.2), Color(0.06, 0.06, 0.07)],
			alt_colors = [Color(0.55, 0.05, 0.08), Color(0.78, 0.78, 0.82), Color(0.06, 0.06, 0.07)],
			fabrics = [&"stretch", &"stretch", &"leather"],
		},
		"brutus": {
			pieces = func(L: Dictionary) -> Array:
				return [
					# Tank top, tucked into the pants.
					{slot = Slot.MAIN, offset = 0.009, region = func(p, n):
						return minf(_sleeveless(p, L, L.waist - 0.1, L.shoulder * 0.85), -_scoop(p, L, 0.09, 0.07))},
					# Work pants over the boot tops.
					{slot = Slot.TRIM, offset = 0.016, region = func(p, n): return _legs(p, L.ankle + 0.17, L.waist)},
					{slot = Slot.ACCENT, offset = 0.014, flat_soles = true, region = func(p, n): return _legs(p, -1.0, L.ankle + 0.21)},
				],
			colors = [Color(0.34, 0.37, 0.2), Color(0.15, 0.18, 0.26), Color(0.08, 0.06, 0.05)],
			alt_colors = [Color(0.52, 0.52, 0.54), Color(0.22, 0.32, 0.52), Color(0.27, 0.16, 0.08)],
			fabrics = [&"cotton", &"denim", &"leather"],
		},
	}


## A top with sleeves: from `y0` up over the shoulders to the base of the head, sleeves
## ending at |x| = `sleeve_end` (arms run along X in the T-pose), with a neck hole.
func _top(p: Vector3, L: Dictionary, y0: float, sleeve_end: float) -> float:
	var band := minf(minf(p.y - y0, (L.neck + 0.03) - p.y), sleeve_end - absf(p.x))
	return minf(band, -_neck_hole(p, L))


## A sleeveless top from `y0`: armholes at |x| = `armhole` above the armpits, full width
## below them, with a neck hole.
func _sleeveless(p: Vector3, L: Dictionary, y0: float, armhole: float) -> float:
	var side := maxf(armhole - absf(p.x), (L.chest - 0.06) - p.y)
	var band := minf(minf(p.y - y0, (L.neck + 0.03) - p.y), minf(side, ARM_LIMIT - absf(p.x)))
	return minf(band, -_neck_hole(p, L))


## Legs (and hips) between two heights; the arms sit far out along X and are excluded.
func _legs(p: Vector3, y0: float, y1: float) -> float:
	return minf(minf(p.y - y0, y1 - p.y), ARM_LIMIT - absf(p.x))


## An elliptical hole around the neck (positive inside), so the collar line is smooth.
func _neck_hole(p: Vector3, L: Dictionary) -> float:
	var ellipse := Vector2(p.x / NECK_RADIUS, (p.z - L.neck_z) / (NECK_RADIUS * 0.95))
	return minf(NECK_RADIUS * (1.0 - ellipse.length()), p.y - (L.neck - 0.035))


## The front V opening (positive inside it): from the neck down to `bottom`, `width` wide
## at the neck. Only the front of the body.
func _v_cut(p: Vector3, n: Vector3, L: Dictionary, bottom: float, width: float) -> float:
	if p.z <= 0.0 or n.z < 0.15:
		return -1.0
	var half_width: float = width * (p.y - bottom) / (L.neck - bottom)
	return minf(half_width - absf(p.x), p.y - bottom)


## A rounded neckline front and back (positive inside it): `depth` below the neck,
## `half_width` wide.
func _scoop(p: Vector3, L: Dictionary, depth: float, half_width: float) -> float:
	return minf(p.y - (L.neck - depth), half_width - absf(p.x))


# --- Building ------------------------------------------------------------------------

func _build(model_scene: PackedScene, spec: Dictionary) -> Dictionary:
	var scene := model_scene.instantiate()
	var skeleton := scene.find_child("Skeleton3D") as Skeleton3D
	var body_instance: MeshInstance3D
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var material := mi.mesh.surface_get_material(0)
		if material and material.resource_name.begins_with("MI_Superhero"):
			body_instance = mi
	_body_skin = body_instance.skin
	_pelvis_bind = _bind_index(skeleton, "pelvis")
	var L := _landmarks(skeleton, body_instance.mesh)
	var arrays := body_instance.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var pieces: Array = spec.pieces.call(L)

	var tools: Array[SurfaceTool] = []
	var used: Array[bool] = [false, false, false]
	for i in 3:
		var st := SurfaceTool.new()
		st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
	var hidden := PackedByteArray()
	hidden.resize(indices.size() / 3)
	var triangles := 0
	for piece: Dictionary in pieces:
		var region: Callable = piece.region
		var distance := PackedFloat32Array()
		distance.resize(verts.size())
		for v in verts.size():
			distance[v] = region.call(verts[v], normals[v])
		for t in indices.size() / 3:
			var corners := [indices[t * 3], indices[t * 3 + 1], indices[t * 3 + 2]]
			var d := [distance[corners[0]], distance[corners[1]], distance[corners[2]]]
			if piece.get("hide", true) and d.min() >= HIDE_INSET:
				hidden[t] = 1
			if d.max() < 0.0:
				continue
			var polygon: Array = []
			for c: int in corners:
				polygon.append({p = verts[c], n = normals[c], uv = uvs[c],
					bones = bones.slice(c * 4, c * 4 + 4), weights = weights.slice(c * 4, c * 4 + 4)})
			polygon = _clip(polygon, region, d.min() >= 0.0)
			if polygon.size() < 3:
				continue
			var parts := [[polygon, piece.slot]]
			if piece.has("trim"):
				var trim: Callable = piece.trim
				parts = [[_clip(polygon, trim, false), piece.trim_slot],
					[_clip(polygon, func(p, n): return -trim.call(p, n), false), piece.slot]]
			for part: Array in parts:
				var poly: Array = part[0]
				var slot: int = part[1]
				for i in range(1, poly.size() - 1):
					for vertex: Dictionary in [poly[0], poly[i], poly[i + 1]]:
						_emit(tools[slot], vertex, piece)
					used[slot] = true
					triangles += 1
	if spec.has("belt_knot"):
		triangles += _add_belt_knot(tools[spec.belt_knot.slot], spec.belt_knot, L, verts)
		used[spec.belt_knot.slot] = true

	var outfit := ArrayMesh.new()
	for slot in 3:
		if not used[slot]:
			continue
		tools[slot].index()
		tools[slot].generate_tangents()
		tools[slot].commit(outfit)
		outfit.surface_set_name(outfit.get_surface_count() - 1, Slot.keys()[slot].to_lower())

	# The body without the covered skin (same vertices, fewer triangles).
	var kept := PackedInt32Array()
	for t in indices.size() / 3:
		if not hidden[t]:
			kept.append_array(indices.slice(t * 3, t * 3 + 3))
	var body_arrays := arrays.duplicate()
	body_arrays[Mesh.ARRAY_INDEX] = kept
	# Custom vertex channels (the female body has some) need extra format flags to
	# re-add, and standard materials never read them.
	for channel in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		body_arrays[channel] = null
	var body := ArrayMesh.new()
	body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, body_arrays)
	body.surface_set_material(0, body_instance.mesh.surface_get_material(0).duplicate())
	body.surface_set_name(0, body_instance.mesh.surface_get_name(0))
	scene.free()
	return {outfit = outfit, body = body, outfit_triangles = triangles,
		body_before = indices.size() / 3, body_after = kept.size() / 3}


## Clips a polygon (vertex dictionaries) to where `field` >= 0, cutting edges at the zero
## crossing and blending every vertex attribute there.
func _clip(polygon: Array, field: Callable, all_inside: bool = false) -> Array:
	if all_inside:
		return polygon
	var values := polygon.map(func(v: Dictionary) -> float: return field.call(v.p, v.n))
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


func _emit(st: SurfaceTool, vertex: Dictionary, piece: Dictionary) -> void:
	var offset: float = piece.offset.call(vertex.n) if piece.offset is Callable else piece.offset
	if piece.get("flat_soles", false) and vertex.n.y < -0.6:
		offset = 0.002 # don't push boot soles into the floor
	st.set_normal(vertex.n)
	st.set_uv(vertex.uv)
	st.set_bones(vertex.bones)
	st.set_weights(vertex.weights)
	st.add_vertex(vertex.p + vertex.n * offset)


## Belt knot at the front centre plus two hanging tails, all bound to the pelvis.
func _add_belt_knot(st: SurfaceTool, knot: Dictionary, L: Dictionary, verts: PackedVector3Array) -> int:
	var y: float = L.hip + knot.y
	var front := -INF
	for v in verts:
		if absf(v.y - y) < 0.02 and absf(v.x) < 0.04:
			front = maxf(front, v.z)
	var z: float = front + knot.offset
	var boxes := [
		[Vector3(0.0, y, z + 0.008), Vector3(0.028, 0.02, 0.012), 0.0], # knot
		[Vector3(-0.022, y - 0.1, z + 0.006), Vector3(0.016, 0.085, 0.005), -0.18], # tails
		[Vector3(0.022, y - 0.11, z + 0.006), Vector3(0.016, 0.09, 0.005), 0.22],
	]
	var triangles := 0
	for box: Array in boxes:
		var basis := Basis(Vector3.BACK, box[2])
		var center: Vector3 = box[0]
		var half: Vector3 = box[1]
		for face in 6:
			var axis := face / 2
			var side := 1.0 if face % 2 == 0 else -1.0
			var normal := Vector3.ZERO
			normal[axis] = side
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var w := normal.cross(u)
			var quad := [-u - w, u - w, u + w, -u + w]
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_normal(basis * normal)
				st.set_uv(Vector2(0.5, 0.5))
				st.set_bones(PackedInt32Array([_pelvis_bind, 0, 0, 0]))
				st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
				st.add_vertex(center + basis * ((normal + (quad[i] as Vector3)) * half))
			triangles += 2
	return triangles


## Heights and widths of the T-pose body, from the skeleton's rest pose.
func _landmarks(skeleton: Skeleton3D, mesh: Mesh) -> Dictionary:
	var rest := func(bone: String) -> Vector3: return skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin
	var top := -INF
	for v: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		top = maxf(top, v.y)
	return {hip = rest.call("pelvis").y, waist = rest.call("spine_01").y, chest = rest.call("spine_03").y,
		neck = rest.call("neck_01").y, neck_z = rest.call("neck_01").z, shoulder = rest.call("upperarm_l").x, elbow = rest.call("lowerarm_l").x,
		wrist = rest.call("hand_l").x, arm_y = rest.call("upperarm_l").y, knee = rest.call("calf_l").y,
		ankle = rest.call("foot_l").y, head_top = top}


## The skin bind for a bone (by name, or through the skeleton's bone index).
func _bind_index(skeleton: Skeleton3D, bone: String) -> int:
	for i in _body_skin.get_bind_count():
		if String(_body_skin.get_bind_name(i)) == bone:
			return i
	var bone_index := skeleton.find_bone(bone)
	for i in _body_skin.get_bind_count():
		if _body_skin.get_bind_bone(i) == bone_index:
			return i
	push_error("No skin bind for %s" % bone)
	return 0
