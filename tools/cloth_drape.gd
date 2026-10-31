class_name ClothDrape
extends RefCounted
## Loose cloth for the generated outfits (tools/build_outfits.gd; tools only, not exported).
##
## A plain outfit piece is the body surface pushed out by a fixed thickness, so it clings
## like spandex: every muscle shows through. A draped piece (`drape` in its spec) is
## subdivided once, then each vertex's height above the skin (along the skin's normal,
## so it keeps the skin vertex's bone weights) is relaxed toward the average of its
## neighbours, never below the piece's minimum (`min`, which can flare toward a cuff or
## hem) or above its maximum. Convex places stay at the minimum and hollows fill in, like
## a stretched membrane: the cloth bridges the spine, the small of the back and the gaps
## between muscles, and hangs from the shoulders and chest. `pin` holds a band at the
## minimum (the belt cinching the jacket). Then `folds` displaces the cloth (noise
## stretched along the fold direction, built with `fold()`), and normals are recomputed.
## Pieces in the same `group` (a jacket and its collar band) share the relaxed heights;
## `extra` raises a piece above the rest of its group, with a strip closing the step.
## `hull` (a func(p) -> [part name, slice axis 0 = X / 1 = Y, slices above, slices
## below] or []) raises the minimum to the convex hull of the body's cross-sections
## there, plus the thickness: loose cloth wraps the body like a string pulled tight, so it
## spans the gaps between muscles instead of hugging each one, and below its widest point
## it falls straight (the hull takes in the slices above too: the chest hangs to the
## belt, the pants from the seat and thighs). The torso and legs are sliced across Y, the
## arms (held out along X in the T-pose) across X.
## Cloth standing off the skin also gets smoothed bone weights (`WEIGHT_PASSES`, more the
## farther out it is): with the skin's exact weights, a bending spine turns every place
## the weights change into a ridge. Pieces with a `hull` don't blend across body parts
## named in `keep_apart` (the two legs of the pants).
## Openings (hems, cuffs, the neckline) get a turned edge `HEM_THICKNESS` thick and a dark
## lining `LINING_DEPTH` deep, so a sleeve seen from below shows its inside, not a hole.

const ITERATIONS := 160
const HEM_THICKNESS := 0.004
const LINING_DEPTH := 0.025
const LINING_SHADE := 0.32
const RIM_SHADE := 0.72
const VALLEY_SHADE := 0.3 # fold valleys darken by up to this (baked occlusion)
const WELD := 2000.0 # 0.5 mm: the base bodies' halves aren't merged down the middle
const HULL_SLICE := 0.015 # m: body cross-sections for `hull`, each from three slices
const HULL_MIN_NORMAL := 0.35 # normals more along the slice axis than this skip the hull
const SURFACE_PASSES := 12 # Taubin passes over the cloth's own positions
const WEIGHT_PASSES := 40
const WEIGHT_FULL_AT := 0.025 # m (past the first 1 cm) above the skin where the weights blend fully
const NORMAL_PASSES := 80
const MIN_SMOOTHING := 16 # passes evening out the minimum where hull slices change

static var _noise: FastNoiseLite


## Noise folds: `scale` stretches the noise (small along the folds, large across them,
## in 1/m), `amplitude` in metres. Returns a signed displacement.
static func fold(p: Vector3, scale: Vector3, amplitude: float, seed_offset := 0.0) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.seed = 7
		_noise.frequency = 1.0
		_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	if amplitude <= 0.0:
		return 0.0
	var q := p * scale
	return amplitude * clampf(_noise.get_noise_3d(q.x + seed_offset, q.y, q.z) * 1.6, -1.0, 1.0)


## Folds around a body part: `axis` 1 = a vertical part (torso, leg) centred on
## (x, z) = `center`, 0 = an arm along X centred on (y, z) = `center`. The noise is sampled
## on a cylinder `radius` round, `around` (1/m) across the folds and `along` (1/m) down
## them, so the folds follow the part however its surface curves, with no seam.
static func fold_around(p: Vector3, axis: int, center: Vector2, radius: float, around: float, along: float,
		amplitude: float, seed_offset := 0.0) -> float:
	var flat := Vector2(p.x, p.z) if axis == 1 else Vector2(p.y, p.z)
	var angle := (flat - center).angle()
	var ring := Vector2(cos(angle), sin(angle)) * radius * around
	return fold(Vector3(ring.x, p[axis] * along, ring.y), Vector3.ONE, amplitude, seed_offset)


## Splits a triangle (three vertex dictionaries) at the midpoints of its `marked`
## edges (0: v0-v1, 1: v1-v2, 2: v2-v0): all three make four triangles, fewer make a fan,
## so a split triangle next to an unsplit one leaves no crack. Winding is kept.
static func subdivide(tri: Array, marked: Array, blend: Callable) -> Array:
	var count := marked.count(true)
	if count == 0:
		return [tri]
	if count == 3:
		var ab: Dictionary = blend.call(tri[0], tri[1], 0.5)
		var bc: Dictionary = blend.call(tri[1], tri[2], 0.5)
		var ca: Dictionary = blend.call(tri[2], tri[0], 0.5)
		return [[tri[0], ab, ca], [ab, tri[1], bc], [ca, bc, tri[2]], [ab, bc, ca]]
	if count == 1:
		var e: int = marked.find(true)
		var a: Dictionary = tri[e]
		var b: Dictionary = tri[(e + 1) % 3]
		var c: Dictionary = tri[(e + 2) % 3]
		var m: Dictionary = blend.call(a, b, 0.5)
		return [[a, m, c], [m, b, c]]
	# Two: turn the triangle so the unmarked edge is c-a.
	var u: int = marked.find(false)
	var a: Dictionary = tri[(u + 1) % 3]
	var b: Dictionary = tri[(u + 2) % 3]
	var c: Dictionary = tri[u]
	var ab: Dictionary = blend.call(a, b, 0.5)
	var bc: Dictionary = blend.call(b, c, 0.5)
	return [[ab, b, bc], [a, ab, bc], [a, bc, c]]


## `faces`: [[v0, v1, v2], piece index, slot, [shade0, shade1, shade2]], vertices being
## the skin dictionaries (p, n, uv, bones, weights). `pieces`: the specs. Returns
## [[corner, corner, corner], slot] with corners {pos, normal, uv, bones, weights, shade}.
static func process(faces: Array, pieces: Array, body: PackedVector3Array) -> Array:
	var out: Array = []
	var groups := {}
	for face: Array in faces:
		var group: String = (pieces[face[1]] as Dictionary).drape.get("group", str(face[1]))
		if not groups.has(group):
			groups[group] = []
		groups[group].append(face)
	for group: String in groups:
		out.append_array(_process_group(groups[group], pieces, body))
	return out


static func _process_group(faces: Array, pieces: Array, body: PackedVector3Array) -> Array:
	# Weld corners by skin position: one id per skin point, shared by every piece here.
	var index := {}
	var points: Array[Vector3] = []
	var normal_sum: Array[Vector3] = []
	var face_ids: Array = []
	for face: Array in faces:
		var ids := PackedInt32Array()
		for v: Dictionary in face[0]:
			var key := Vector3i(((v.p as Vector3) * WELD).round())
			if not index.has(key):
				index[key] = points.size()
				points.append(v.p)
				normal_sum.append(Vector3.ZERO)
			var id: int = index[key]
			normal_sum[id] += v.n
			ids.append(id)
		face_ids.append(ids)
	var count := points.size()
	var normals: Array[Vector3] = []
	for id in count:
		normals.append(normal_sum[id].normalized())

	# Limits per id (the first piece that uses it decides; pieces of a group agree).
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	var pinned := PackedByteArray()
	lo.resize(count)
	hi.resize(count)
	pinned.resize(count)
	var seen := PackedByteArray()
	seen.resize(count)
	var neighbours: Array = []
	neighbours.resize(count)
	for id in count:
		neighbours[id] = [] # plain Arrays: a packed array cast out of an Array is a copy
	for f in faces.size():
		var drape: Dictionary = (pieces[faces[f][1]] as Dictionary).drape
		var ids: PackedInt32Array = face_ids[f]
		for k in 3:
			var id := ids[k]
			for other in [ids[(k + 1) % 3], ids[(k + 2) % 3]]:
				if not (neighbours[id] as Array).has(other):
					(neighbours[id] as Array).append(other)
			if seen[id]:
				continue
			seen[id] = 1
			lo[id] = _value(drape.get("min", (pieces[faces[f][1]] as Dictionary).offset), points[id], normals[id])
			hi[id] = maxf(_value(drape.get("max", 0.1), points[id], normals[id]), lo[id])
			if drape.has("pin") and (drape.pin as Callable).call(points[id]):
				pinned[id] = 1

	# The cloth stands off along smoothed normals: the skin's swing over every muscle,
	# and offsetting along them prints the muscles into the cloth.
	var skin_normals := normals
	normals = normals.duplicate()
	for pass_index in NORMAL_PASSES:
		var next := normals.duplicate()
		for id in count:
			var sum := normals[id]
			for j: int in neighbours[id]:
				sum += normals[j]
			next[id] = sum.normalized()
		normals = next
	for id in count:
		# Never so far from the skin's own normal that the cloth would sink into it.
		if normals[id].dot(skin_normals[id]) < 0.5:
			normals[id] = skin_normals[id].slerp(normals[id], 0.5).normalized()

	# Loose cloth: at least on the hull of the body's cross-section.
	var hull: Variant = (pieces[faces[0][1]] as Dictionary).drape.get("hull")
	if hull is Callable:
		var hulls := _Hulls.new(hull, body)
		var raised := lo.duplicate()
		for id in count:
			raised[id] = minf(lo[id] + hulls.depth(points[id], normals[id]), hi[id])
		for pass_index in MIN_SMOOTHING:
			var next := raised.duplicate()
			for id in count:
				var ring: Array = neighbours[id]
				var total := raised[id]
				for j in ring:
					total += raised[j]
				next[id] = total / (ring.size() + 1)
			raised = next
		for id in count:
			if not pinned[id]:
				lo[id] = clampf(raised[id], lo[id], hi[id])

	# Relax the heights: hollows fill, convex places stay at the minimum.
	var h := lo.duplicate()
	for iteration in ITERATIONS:
		var next := h.duplicate()
		for id in count:
			if pinned[id]:
				continue
			var ring: Array = neighbours[id]
			if ring.is_empty():
				continue
			var average := Vector3.ZERO
			for j in ring:
				average += points[j] + normals[j] * h[j]
			average /= ring.size()
			next[id] = clampf((average - points[id]).dot(normals[id]), lo[id], hi[id])
		h = next

	var influences := _smooth_weights(faces, face_ids, pieces, points, neighbours, h, lo)

	# Each height runs along its own skin normal, and those swing over every muscle, so
	# the surface keeps small lumps: smooth the cloth's own positions (Taubin: a shrink
	# step, then a slightly larger grow step, so it keeps its size), never closer to the
	# skin than the minimum.
	var base: Array[Vector3] = []
	for id in count:
		base.append(points[id] + normals[id] * h[id])
	for pass_index in SURFACE_PASSES * 2:
		var factor := 0.5 if pass_index % 2 == 0 else -0.53
		var next := base.duplicate()
		for id in count:
			var ring: Array = neighbours[id]
			if pinned[id] or ring.size() < 3:
				continue
			var average := Vector3.ZERO
			for j: int in ring:
				average += base[j]
			average /= ring.size()
			# Along the normal only: sliding sideways shuffles the slivers along clipped
			# edges, and straight trims and stitch rows turn jagged.
			var moved := base[id] + normals[id] * (average - base[id]).dot(normals[id]) * factor
			var height := (moved - points[id]).dot(normals[id])
			if height < lo[id]:
				moved += normals[id] * (lo[id] - height)
			next[id] = moved
		base = next

	# Final positions per piece (folds and `extra` differ per piece), then normals.
	var piece_list: Array[int] = []
	for face: Array in faces:
		if not piece_list.has(face[1]):
			piece_list.append(face[1])
	var position := {} # Vector2i(piece, id) -> Vector3
	var displacement := {} # Vector2i(piece, id) -> fold displacement
	for f in faces.size():
		var piece: int = faces[f][1]
		var drape: Dictionary = (pieces[piece] as Dictionary).drape
		for id in face_ids[f]:
			var key := Vector2i(piece, id)
			if position.has(key):
				continue
			var d := 0.0 if pinned[id] else _value(drape.get("folds", 0.0), points[id], normals[id])
			displacement[key] = d
			position[key] = base[id] + normals[id] * (float(drape.get("extra", 0.0)) + d)
	var smooth := {} # Vector2i(piece, id) -> normal
	for f in faces.size():
		var piece: int = faces[f][1]
		var ids: PackedInt32Array = face_ids[f]
		var a: Vector3 = position[Vector2i(piece, ids[0])]
		var b: Vector3 = position[Vector2i(piece, ids[1])]
		var c: Vector3 = position[Vector2i(piece, ids[2])]
		var face_normal := (b - a).cross(c - a) # area weighted
		# The skin triangles wind so that this points out; keep it agreeing with the skin.
		if face_normal.dot(normals[ids[0]]) < 0.0:
			face_normal = -face_normal
		for id in ids:
			var key := Vector2i(piece, id)
			smooth[key] = smooth.get(key, Vector3.ZERO) + face_normal

	# The cloth triangles.
	var out: Array = []
	for f in faces.size():
		var face: Array = faces[f]
		var piece: int = face[1]
		var drape: Dictionary = (pieces[piece] as Dictionary).drape
		var amplitude := maxf(float(drape.get("fold_amplitude", 0.01)), 0.001)
		var corners: Array = []
		for k in 3:
			var v: Dictionary = face[0][k]
			var key := Vector2i(piece, face_ids[f][k])
			var valley := clampf(-float(displacement[key]) / amplitude, 0.0, 1.0)
			var shade: float = face[3][k] * (1.0 - VALLEY_SHADE * valley * valley)
			var influence: Array = influences[face_ids[f][k]]
			corners.append({pos = position[key], normal = (smooth[key] as Vector3).normalized(), uv = v.uv,
				bones = influence[0], weights = influence[1], shade = shade})
		out.append([corners, face[2]])

	# Edges: count each piece's edges to find its boundary.
	for piece in piece_list:
		var edges := {} # Vector2i(min id, max id) -> [face index, count]
		for f in faces.size():
			if faces[f][1] != piece:
				continue
			var ids: PackedInt32Array = face_ids[f]
			for k in 3:
				var e := Vector2i(mini(ids[k], ids[(k + 1) % 3]), maxi(ids[k], ids[(k + 1) % 3]))
				if edges.has(e):
					edges[e][1] += 1
				else:
					edges[e] = [f, 1]
		var others := {} # ids used by the other pieces of the group
		for f in faces.size():
			if faces[f][1] != piece:
				for id in face_ids[f]:
					others[id] = true
		var opening := {} # boundary ids on an opening (not against another piece)
		for e: Vector2i in edges:
			if edges[e][1] != 1:
				continue
			var f: int = edges[e][0]
			var ids: PackedInt32Array = face_ids[f]
			var third := -1
			for id in ids:
				if id != e.x and id != e.y:
					third = id
			var seam: bool = others.has(e.x) and others.has(e.y)
			var a_key := Vector2i(piece, e.x)
			var b_key := Vector2i(piece, e.y)
			var a: Vector3 = position[a_key]
			var b: Vector3 = position[b_key]
			var a_in: Vector3
			var b_in: Vector3
			if seam:
				# Down to the neighbouring piece's surface at the same skin points.
				a_in = _other_position(position, piece_list, piece, e.x, a)
				b_in = _other_position(position, piece_list, piece, e.y, b)
			else:
				opening[e.x] = true
				opening[e.y] = true
				a_in = a - (smooth[a_key] as Vector3).normalized() * HEM_THICKNESS
				b_in = b - (smooth[b_key] as Vector3).normalized() * HEM_THICKNESS
			if a.distance_to(a_in) < 0.0005 and b.distance_to(b_in) < 0.0005:
				continue
			var edge := (b - a).normalized()
			var away := (a + b) * 0.5 - (position[Vector2i(piece, third)] as Vector3)
			var rim_normal := (away - edge * away.dot(edge)).normalized()
			var va: Dictionary = _skinned(_corner_of(faces[f], face_ids[f], e.x), influences[e.x])
			var vb: Dictionary = _skinned(_corner_of(faces[f], face_ids[f], e.y), influences[e.y])
			var rim := [_rim_corner(a, rim_normal, va), _rim_corner(b, rim_normal, vb),
				_rim_corner(b_in, rim_normal, vb), _rim_corner(a_in, rim_normal, va)]
			# Wound like the cloth (Godot's front faces are clockwise: the cross product
			# points into the surface), so the outfit can be drawn single-sided.
			var order := [0, 1, 2, 0, 2, 3]
			if (b - a).cross(b_in - a).dot(rim_normal) > 0.0:
				order = [0, 2, 1, 0, 3, 2]
			out.append([[rim[order[0]], rim[order[1]], rim[order[2]]], faces[f][2]])
			out.append([[rim[order[3]], rim[order[4]], rim[order[5]]], faces[f][2]])
		if not drape_lining(pieces[piece]) or opening.is_empty():
			continue
		# Lining: the faces within LINING_DEPTH of an opening, copied inward and flipped.
		var depth := _distances(opening, neighbours, points, LINING_DEPTH)
		for f in faces.size():
			if faces[f][1] != piece:
				continue
			var ids: PackedInt32Array = face_ids[f]
			if not (depth.has(ids[0]) and depth.has(ids[1]) and depth.has(ids[2])):
				continue
			var corners: Array = []
			for k in [0, 2, 1]:
				var key := Vector2i(piece, ids[k])
				var n := (smooth[key] as Vector3).normalized()
				var v: Dictionary = faces[f][0][k]
				var influence: Array = influences[ids[k]]
				corners.append({pos = (position[key] as Vector3) - n * HEM_THICKNESS, normal = -n, uv = v.uv,
					bones = influence[0], weights = influence[1], shade = LINING_SHADE})
			out.append([corners, faces[f][2]])
	return out


## Per id [bones, weights]: the skin's, blended with the neighbours' the farther the
## cloth stands off the skin.
static func _smooth_weights(faces: Array, face_ids: Array, pieces: Array, points: Array[Vector3],
		neighbours: Array, h: PackedFloat32Array, lo: PackedFloat32Array) -> Array:
	var count := points.size()
	var maps: Array = [] # id -> {bone: weight}
	maps.resize(count)
	for f in faces.size():
		for k in 3:
			var id: int = face_ids[f][k]
			if maps[id] != null:
				continue
			var v: Dictionary = faces[f][0][k]
			var map := {}
			for i in 4:
				if v.weights[i] > 0.0:
					map[v.bones[i]] = map.get(v.bones[i], 0.0) + v.weights[i]
			maps[id] = map
	var drape: Dictionary = (pieces[faces[0][1]] as Dictionary).drape
	var part_of: Variant = drape.get("hull")
	var apart: Array = drape.get("keep_apart", [])
	var parts: Array = []
	parts.resize(count)
	if part_of is Callable and not apart.is_empty():
		for id in count:
			var part: Array = (part_of as Callable).call(points[id])
			parts[id] = part[0] if not part.is_empty() else ""
	var blend := PackedFloat32Array()
	blend.resize(count)
	for id in count:
		blend[id] = clampf((h[id] - 0.01) / WEIGHT_FULL_AT, 0.0, 1.0)
	for pass_index in WEIGHT_PASSES:
		var next: Array = []
		next.resize(count)
		for id in count:
			var map: Dictionary = maps[id]
			if blend[id] <= 0.0:
				next[id] = map
				continue
			var sum := {}
			var taken := 0
			for j: int in neighbours[id]:
				if parts[id] != parts[j] and (apart.has(parts[id]) or apart.has(parts[j])):
					continue
				taken += 1
				for bone in maps[j]:
					sum[bone] = sum.get(bone, 0.0) + maps[j][bone]
			if taken == 0:
				next[id] = map
				continue
			var mixed := {}
			for bone in map:
				mixed[bone] = map[bone] * (1.0 - blend[id])
			for bone in sum:
				mixed[bone] = mixed.get(bone, 0.0) + sum[bone] / taken * blend[id]
			next[id] = mixed
		maps = next
	var out: Array = []
	out.resize(count)
	for id in count:
		var map: Dictionary = maps[id]
		var order := map.keys()
		order.sort_custom(func(a, b): return map[a] > map[b])
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		var total := 0.0
		for i in 4:
			bones.append(order[i] if i < order.size() else 0)
			weights.append(map[order[i]] if i < order.size() else 0.0)
			total += weights[i]
		for i in 4:
			weights[i] /= maxf(total, 0.0001)
		out[id] = [bones, weights]
	return out


static func _skinned(v: Dictionary, influence: Array) -> Dictionary:
	var copy := v.duplicate()
	copy.bones = influence[0]
	copy.weights = influence[1]
	return copy


static func drape_lining(piece: Dictionary) -> bool:
	return piece.drape.get("lining", true)


## A float or a func(p: Vector3, n: Vector3) -> float.
static func _value(value: Variant, p: Vector3, n: Vector3) -> float:
	return (value as Callable).call(p, n) if value is Callable else float(value)


static func _other_position(position: Dictionary, piece_list: Array[int], piece: int, id: int, fallback: Vector3) -> Vector3:
	for other in piece_list:
		if other != piece and position.has(Vector2i(other, id)):
			return position[Vector2i(other, id)]
	return fallback


static func _corner_of(face: Array, ids: PackedInt32Array, id: int) -> Dictionary:
	for k in 3:
		if ids[k] == id:
			return face[0][k]
	return face[0][0]


static func _rim_corner(pos: Vector3, normal: Vector3, v: Dictionary) -> Dictionary:
	return {pos = pos, normal = normal, uv = v.uv, bones = v.bones, weights = v.weights, shade = RIM_SHADE}


## Distance along the surface from the `sources` ids, up to `limit` (id -> metres).
static func _distances(sources: Dictionary, neighbours: Array, points: Array[Vector3], limit: float) -> Dictionary:
	var distance := {}
	var frontier: Array = []
	for id: int in sources:
		distance[id] = 0.0
		frontier.append(id)
	while not frontier.is_empty():
		var next: Array = []
		for id: int in frontier:
			for j in neighbours[id]:
				var d: float = distance[id] + points[id].distance_to(points[j])
				if d <= limit and d < distance.get(j, INF):
					distance[j] = d
					next.append(j)
		frontier = next
	return distance


## Convex hulls of the body's cross-sections, per part and slice, built on demand.
class _Hulls:
	var part_of: Callable
	var body: PackedVector3Array
	var parts := {} # part name -> {slice index -> Array of body points (Vector2)}
	var cache := {} # Vector2i-ish key -> hull


	func _init(part_func: Callable, body_points: PackedVector3Array) -> void:
		part_of = part_func
		body = body_points
		for p in body:
			var part: Array = part_of.call(p)
			if part.is_empty():
				continue
			var axis: int = part[1]
			var slices: Dictionary = parts.get_or_add(part[0], {})
			var index := floori(p[axis] / ClothDrape.HULL_SLICE)
			if not slices.has(index):
				slices[index] = [] # a plain Array: a packed one cast out of the Dictionary is a copy
			(slices[index] as Array).append(_flat(p, axis))


	## How far out along `n` from `p` the hull's edge is (0 without a hull).
	func depth(p: Vector3, n: Vector3) -> float:
		var part: Array = part_of.call(p)
		if part.is_empty() or not parts.has(part[0]):
			return 0.0
		var axis: int = part[1]
		var dir := _flat(n, axis)
		if dir.length() < ClothDrape.HULL_MIN_NORMAL:
			return 0.0
		# Faded in from the cutoff, so it leaves no step either.
		var weight := smoothstep(ClothDrape.HULL_MIN_NORMAL, ClothDrape.HULL_MIN_NORMAL + 0.2, dir.length())
		# Between the two nearest slices, so the cloth has no steps where they change.
		var at := p[axis] / ClothDrape.HULL_SLICE - 0.5
		var index := floori(at)
		var t := at - index
		var origin := _flat(p, axis)
		var unit := dir.normalized()
		var a := _exit(_hull(part, index), origin, unit)
		var b := _exit(_hull(part, index + 1), origin, unit)
		# Along the slice that's the exit distance; along the tilted normal, a little more.
		return weight * lerpf(a, b, t) / dir.length()


	func _hull(part: Array, index: int) -> PackedVector2Array:
		var key := "%s/%d" % [part[0], index]
		if not cache.has(key):
			var points := PackedVector2Array()
			var slices: Dictionary = parts[part[0]]
			var above: int = part[2] if part.size() > 2 else 1
			var below: int = part[3] if part.size() > 3 else 1
			for i in range(index - below, index + above + 1):
				if slices.has(i):
					points.append_array(PackedVector2Array(slices[i]))
			cache[key] = Geometry2D.convex_hull(points) if points.size() >= 3 else PackedVector2Array()
		return cache[key]


	## How far from `origin` along `unit` the ray leaves `polygon` (closed, convex).
	static func _exit(polygon: PackedVector2Array, origin: Vector2, unit: Vector2) -> float:
		if polygon.size() < 4:
			return 0.0
		var exit := INF
		for i in polygon.size() - 1:
			var a := polygon[i]
			var edge := polygon[i + 1] - a
			var outward := Vector2(edge.y, -edge.x).normalized()
			if (polygon[(i + 2) % (polygon.size() - 1)] - a).dot(outward) > 0.0:
				outward = -outward
			var facing := unit.dot(outward)
			if facing <= 0.0001:
				continue
			exit = minf(exit, outward.dot(a - origin) / facing)
		return 0.0 if exit == INF else maxf(exit, 0.0)


	static func _flat(v: Vector3, axis: int) -> Vector2:
		return Vector2(v.x, v.z) if axis == 1 else Vector2(v.y, v.z)
