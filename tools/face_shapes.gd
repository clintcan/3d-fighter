class_name FaceShapes
extends RefCounted
## Procedural facial expressions for the Quaternius base heads, which ship with no blend
## shapes and no face bones. Every shape is a smooth displacement field over the rest-pose
## face, placed from landmarks measured on the mesh itself (eyeball spheres, the lip
## crease), so the same code fits the male and female heads and anything attached to
## them (eyebrows and lashes, beards).
##
## - Eyelids rotate about the eyeball's horizontal axis, like real lids: they keep their
##   distance from the eyeball's centre and so slide over it instead of through it.
##   How far each column of the lid travels comes from the measured eye opening there.
## - The lips are sealed by a thin strip of triangles at the bottom of the lip crease;
##   cut_mouth() removes it so the jaw can open, and mouth_interior() adds a dark mouth
##   with teeth behind the lips (a second surface, mouth_material()).
## - The jaw rotates about a hinge in front of the ears; everything under the lip seam
##   follows, fading out toward the throat, the ears and past the mouth corners.
##
## build_outfits.gd runs this on every fighter's body; build_face_shapes.gd on the
## eyebrows and beard pieces (saved under FACE_DIR, swapped in by FighterModel).

const SHAPES: Array[StringName] = [&"blink", &"squint", &"brow_down", &"brow_up", &"jaw_open", &"smile", &"grimace"]
const FACE_DIR := "res://assets/characters/face/"

const JAW_ANGLE := 0.26 # radians at jaw_open = 1
const BROW_DROP := 0.0065
const BROW_RAISE := 0.007
const SMILE_LIFT := 0.0065
const EYE_CLEARANCE := 0.0008 # lids stay this far outside the eyeball


## Measures the head of a base model scene (an instance): the right eyeball (x > 0;
## the left mirrors it), the lip crease and the jaw hinge.
static func landmarks(scene: Node) -> Dictionary:
	var eyes: PackedVector3Array
	var body: PackedVector3Array
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var material := mi.mesh.surface_get_material(0)
		if material == null:
			continue
		if material.resource_name.begins_with("MI_Eyes"):
			eyes = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		elif material.resource_name.begins_with("MI_Superhero"):
			body = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in eyes:
		if p.x > 0.0:
			lo = lo.min(p)
			hi = hi.max(p)
	var radius := (hi.x - lo.x) * 0.5
	var eye := Vector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, hi.z - radius)

	# The lip crease: the deepest points between the lips, two rows a millimetre apart.
	var mouth_top := eye.y - 0.06
	var mouth_bottom := eye.y - 0.09
	var deepest := INF
	for p in body:
		if absf(p.x) < 0.004 and p.y < mouth_top and p.y > mouth_bottom and p.z > eye.z - 0.02:
			deepest = minf(deepest, p.z)
	var mid_seam := 0.0
	var mid_count := 0
	for p in body:
		if absf(p.x) < 0.004 and p.y < mouth_top and p.y > mouth_bottom and absf(p.z - deepest) < 0.0008:
			mid_seam += p.y
			mid_count += 1
	mid_seam /= mid_count
	var crease := PackedVector3Array()
	for p in body:
		if absf(p.x) < 0.045 and absf(p.y - mid_seam) < 0.002 and absf(p.z - deepest) < 0.0008:
			crease.append(p)
	var seam := 0.0
	var corner := 0.0
	for p in crease:
		seam += p.y
		corner = maxf(corner, absf(p.x))
	seam /= crease.size()
	var lip_front := -INF
	for p in body:
		if absf(p.x) < 0.004 and absf(p.y - seam) < 0.012:
			lip_front = maxf(lip_front, p.z)
	return {
		eye = eye, eye_radius = radius,
		seam = seam, inner_z = deepest, corner = corner, lip_front = lip_front,
		hinge = Vector3(0.0, eye.y - 0.03, eye.z - 0.075),
		crease = crease,
	}


## Opens the mouth: removes the strip of triangles at the bottom of the lip crease that
## joins the two crease rows. Returns {indices, lip}: `lip` tells, per vertex, which lip
## it belongs to (0 upper, 1 lower, -1 neither), found by flooding each lip from its
## crease row: the lip edges curve, so the side of the seam a vertex lies on doesn't say.
static func cut_mouth(vertices: PackedVector3Array, indices: PackedInt32Array, L: Dictionary) -> Dictionary:
	var kept := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		var on_crease := 0
		var upper := false
		var lower := false
		for c in 3:
			var p := vertices[indices[t + c]]
			if _on_crease(p, L):
				on_crease += 1
				upper = upper or p.y > L.seam
				lower = lower or p.y < L.seam
		if on_crease == 3 and upper and lower:
			continue
		kept.append_array(indices.slice(t, t + 3))
	# Flood each lip from its crease row, staying near the mouth.
	var weld := _weld(vertices)
	var neighbours := {}
	for t in range(0, kept.size(), 3):
		for c in 3:
			var a := weld[kept[t + c]]
			var b := weld[kept[t + (c + 1) % 3]]
			if not neighbours.has(a):
				neighbours[a] = []
			if not neighbours.has(b):
				neighbours[b] = []
			neighbours[a].append(b)
			neighbours[b].append(a)
	var side := {}
	for lip in [0, 1]:
		var queue := []
		for i in vertices.size():
			var p := vertices[i]
			if _on_crease(p, L) and (p.y < L.seam) == (lip == 1):
				queue.append(weld[i])
		while not queue.is_empty():
			var v: int = queue.pop_back()
			if side.has(v):
				if side[v] != lip:
					side[v] = -1 # reached from both lips: the sealed corners
				continue
			side[v] = lip
			for n: int in neighbours.get(v, []):
				var q := vertices[n]
				if absf(q.x) < L.corner - 0.0015 and absf(q.y - L.seam) < 0.008 and q.z > L.inner_z - 0.003 and side.get(n, -2) != lip:
					queue.append(n)
	var lips := PackedFloat32Array()
	lips.resize(vertices.size())
	for i in vertices.size():
		lips[i] = side.get(weld[i], -1)
	return {indices = kept, lip = lips}


static func _on_crease(p: Vector3, L: Dictionary) -> bool:
	return absf(p.x) <= L.corner + 0.0005 and absf(p.y - L.seam) < 0.002 and absf(p.z - L.inner_z) < 0.0008


## Displaced positions of `points` for every shape at weight 1: {shape: PackedVector3Array}.
## `eye_openings` comes from eye_openings() on the head mesh.
## `lip` (from cut_mouth, head mesh only) overrides which side of the seam a vertex is on.
## `anchor` (pieces on the head) is where the eyelids decide how much a vertex follows
## them: the lowest point of its piece, so a lash strip turns with the lid as one and a
## brow above it stays.
static func displace(points: PackedVector3Array, L: Dictionary, eye_openings: Array, lip := PackedFloat32Array(),
		anchor := PackedVector3Array()) -> Dictionary:
	var result := {}
	for shape in SHAPES:
		var moved := PackedVector3Array()
		moved.resize(points.size())
		for i in points.size():
			moved[i] = _shape_point(shape, points[i], L, eye_openings, lip[i] if i < lip.size() else -1.0,
				anchor[i] if i < anchor.size() else points[i], not anchor.is_empty())
		result[shape] = moved
	return result


static func _shape_point(shape: StringName, p: Vector3, L: Dictionary, openings: Array, lip: float, anchor: Vector3, piece: bool) -> Vector3:
	var side := 1.0 if p.x >= 0.0 else -1.0
	var q := Vector3(absf(p.x), p.y, p.z) # mirrored onto the right side
	# Skin fades out up the lid; a piece follows the lid whole or not at all (lashes start
	# below the eye's centre, brows well above it).
	var lid_height: float = anchor.y - L.eye.y
	if piece:
		lid_height = -1.0 if lid_height < 0.2 * L.eye_radius else 1.0
	match shape:
		&"blink":
			q = _lids(q, L, openings, 0.3, 1.0, 1.0, lid_height, piece)
		&"squint":
			q = _lids(q, L, openings, 0.3, 0.15, 0.45, lid_height, piece)
			q += _cheek_raise(q, L) * 0.8
		&"brow_down":
			q += _brow(q, L, Vector3(-0.0045, -BROW_DROP, 0.0015), 1.0, 0.35)
		&"brow_up":
			q += _brow(q, L, Vector3(0.0, BROW_RAISE, 0.0), 1.0, 0.7)
		&"jaw_open":
			q = _rotate_about(q, L.hinge, -JAW_ANGLE * _jaw_weight(q, L, lip))
			q += _lip_part(q, L, 0.0012, 0.0, lip) # the upper lip lifts off the teeth
		&"smile":
			q += _mouth_corner(q, L, Vector3(0.0045, SMILE_LIFT, -0.004))
			q += _cheek_raise(q, L) * 0.6
			q = _lids(q, L, openings, 0.3, 0.0, 0.25, lid_height, piece)
		&"grimace":
			q += _mouth_corner(q, L, Vector3(0.004, -0.0015, -0.002))
			q += _lip_part(q, L, 0.0028, 0.003, lip)
	return Vector3(q.x * side, q.y, q.z)


# --- Eyelids ---------------------------------------------------------------------------

## Per column of the eye (lateral offset from the eyeball centre), the angles (about the
## eyeball's X axis, 0 = straight ahead, + = up) of the upper and lower lid edges: the
## largest gap in the skin in front of the eyeball. [[dx, upper, lower], ...]
static func eye_openings(vertices: PackedVector3Array, L: Dictionary) -> Array:
	var eye: Vector3 = L.eye
	var r: float = L.eye_radius
	var columns := 16
	var angle_lists := []
	var column_dx := PackedFloat32Array()
	for c in columns:
		var dx := lerpf(-1.3 * r, 1.3 * r, (c + 0.5) / columns)
		var half := 1.3 * r / columns * 1.5
		var angles := PackedFloat32Array()
		for p in vertices:
			var d := Vector3(absf(p.x), p.y, p.z) - eye
			# Skin in front of the eyeball (the socket folds inside it don't count).
			if absf(d.x - dx) > half or d.z < 0.0 or d.length() < r + 0.001:
				continue
			if Vector2(d.y, d.z).length() > 2.0 * r:
				continue
			angles.append(atan2(d.y, d.z))
		angles.sort()
		angle_lists.append(angles)
		column_dx.append(dx)
	# The middle of the eye: the widest gap in the central columns.
	var reference := 0.0
	var samples := 0
	for c in columns:
		if absf(column_dx[c]) > 0.3 * r:
			continue
		var angles: PackedFloat32Array = angle_lists[c]
		var best := -1.0
		var middle := 0.0
		for i in angles.size() - 1:
			if angles[i + 1] - angles[i] > best and angles[i + 1] > -0.9 and angles[i] < 0.6:
				best = angles[i + 1] - angles[i]
				middle = (angles[i + 1] + angles[i]) * 0.5
		reference += middle
		samples += 1
	reference /= maxi(samples, 1)
	# Each column's lid edges: the nearest skin above and below that line. Past the eye's
	# corners the skin crosses the line, and the opening closes.
	var result := []
	for c in columns:
		var upper := reference
		var lower := reference
		var angles: PackedFloat32Array = angle_lists[c]
		for i in angles.size() - 1:
			if angles[i] <= reference and angles[i + 1] > reference:
				lower = angles[i]
				upper = angles[i + 1]
		if upper - lower < 0.08:
			upper = reference
			lower = reference
		result.append([column_dx[c], upper, lower])
	# Sparse columns make the measured edges noisy; the opening is an almond, so fit each
	# edge with a parabola and use that (never letting the lids cross).
	var upper_fit := _fit_parabola(result, 1)
	var lower_fit := _fit_parabola(result, 2)
	var first := INF
	var last := -INF
	for column: Array in result:
		if column[1] - column[2] >= 0.01:
			first = minf(first, column[0])
			last = maxf(last, column[0])
	var fitted := []
	for c in 25:
		var dx := lerpf(-1.3 * r, 1.3 * r, c / 24.0)
		var up := upper_fit.x * dx * dx + upper_fit.y * dx + upper_fit.z
		var down := lower_fit.x * dx * dx + lower_fit.y * dx + lower_fit.z
		# Closed beyond the outermost open columns (eased over one column).
		var spacing := 2.6 * r / columns
		var open := smoothstep(first - spacing, first, dx) * (1.0 - smoothstep(last, last + spacing, dx))
		var middle := (up + down) * 0.5
		up = lerpf(middle, maxf(up, middle), open)
		down = lerpf(middle, minf(down, middle), open)
		fitted.append([dx, up, down])
	result = fitted
	return result


## Least-squares y = a·x² + b·x + c through the columns that have an opening;
## returns (a, b, c).
static func _fit_parabola(columns: Array, k: int) -> Vector3:
	# Fitted in units of the widest column so the sums stay well-conditioned in floats.
	var scale := 0.0
	for column: Array in columns:
		scale = maxf(scale, absf(column[0]))
	var sums := PackedFloat64Array()
	sums.resize(5) # Σu⁰..u⁴
	var sy := 0.0
	var suy := 0.0
	var su2y := 0.0
	for column: Array in columns:
		if column[1] - column[2] < 0.01:
			continue
		var u: float = column[0] / scale
		var y: float = column[k]
		for e in 5:
			sums[e] += pow(u, e)
		sy += y
		suy += u * y
		su2y += u * u * y
	var m := Basis(Vector3(sums[4], sums[3], sums[2]), Vector3(sums[3], sums[2], sums[1]), Vector3(sums[2], sums[1], sums[0]))
	var f := m.inverse() * Vector3(su2y, suy, sy)
	return Vector3(f.x / (scale * scale), f.y / scale, f.z)


static func _nearest_open(dx: float, openings: Array) -> Vector2:
	var best := Vector2.ZERO
	var best_distance := INF
	for column: Array in openings:
		if column[1] - column[2] >= 0.01 and absf(column[0] - dx) < best_distance:
			best_distance = absf(column[0] - dx)
			best = Vector2(column[1], column[2])
	return best


static func _opening_at(dx: float, openings: Array) -> Vector2:
	if dx <= openings[0][0]:
		return Vector2(openings[0][1], openings[0][2])
	for i in openings.size() - 1:
		var a: Array = openings[i]
		var b: Array = openings[i + 1]
		if dx <= b[0]:
			var t: float = (dx - a[0]) / (b[0] - a[0])
			return Vector2(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t))
	var last: Array = openings[-1]
	return Vector2(last[1], last[2])


## Closes the lids toward a meeting line `meet` of the way up the opening: the upper lid
## travels `upper` of its way there, the lower lid `lower` of its.
static func _lids(q: Vector3, L: Dictionary, openings: Array, meet: float, upper: float, lower: float, height: float,
		piece := false) -> Vector3:
	var eye: Vector3 = L.eye
	var r: float = L.eye_radius
	var d := q - eye
	var reach := 2.6 * r if piece else 1.7 * r
	if d.z < -0.6 * r or absf(d.x) > reach:
		return q
	var radial := Vector2(d.y, d.z).length()
	if radial > 3.0 * r:
		return q
	var open := _opening_at(d.x, openings)
	if piece and open.x - open.y < 0.01:
		# Lash pieces run past the corners (eyeliner wings): there they turn with the
		# nearest open part of the lid, so the wing stays straight.
		open = _nearest_open(d.x, openings)
	if open.x - open.y < 0.01:
		return q
	var meet_angle := lerpf(open.y, open.x, meet)
	var angle := atan2(d.y, d.z)
	var lateral := 1.0 if piece else 1.0 - smoothstep(1.2 * r, 1.7 * r, absf(d.x))
	var turn := 0.0
	if angle >= meet_angle:
		# By height, not angle, so thick pieces (brows, lashes) move as one.
		var above := 1.0 - smoothstep(0.35 * r, 0.6 * r, height)
		turn = -(open.x - meet_angle) * upper * above
	else:
		var below := 1.0 - smoothstep(0.7 * r, 1.6 * r, -height)
		turn = (meet_angle - open.y) * lower * below
	return _rotate_about(q, eye, turn * lateral)


## Rotates `q` about the X axis through `pivot` (positive = the front turns up).
static func _rotate_about(q: Vector3, pivot: Vector3, angle: float) -> Vector3:
	if angle == 0.0:
		return q
	var d := q - pivot
	var c := cos(angle)
	var s := sin(angle)
	return pivot + Vector3(d.x, d.y * c + d.z * s, -d.y * s + d.z * c)


static func _cheek_raise(q: Vector3, L: Dictionary) -> Vector3:
	var eye: Vector3 = L.eye
	var r: float = L.eye_radius
	var d := q - eye
	if d.z < -0.01:
		return Vector3.ZERO
	var w := _bump(Vector2(d.x / (2.2 * r), (d.y + 2.6 * r) / (1.9 * r)).length())
	# Keep the lower lid edge itself to _lids, so the cheek doesn't push it into the eye.
	w *= smoothstep(-0.6 * r, -1.4 * r, d.y)
	return Vector3(0.0, 0.0035, 0.0018) * w


# --- Brows -----------------------------------------------------------------------------

## The brow and the skin around it move by `offset` (x = toward the nose when negative),
## the inner end weighted `inner`, the outer end `outer`.
static func _brow(q: Vector3, L: Dictionary, offset: Vector3, inner: float, outer: float) -> Vector3:
	var eye: Vector3 = L.eye
	var r: float = L.eye_radius
	var d := q - eye
	if d.z < -0.015:
		return Vector3.ZERO
	var brow_y := 1.25 * r # the brow's middle, above the eyeball centre
	var w := _bump(Vector2(d.x / (3.0 * r), (d.y - brow_y) / (1.8 * r)).length())
	# Nothing below the upper lid crease moves (the lid is _lids' job).
	w *= smoothstep(0.35 * r, 0.75 * r, d.y)
	var along := clampf(inverse_lerp(-1.4 * r, 1.6 * r, d.x), 0.0, 1.0)
	return offset * w * lerpf(inner, outer, along)


# --- Mouth -----------------------------------------------------------------------------

static func _jaw_weight(q: Vector3, L: Dictionary, lip := -1.0) -> float:
	var seam: float = L.seam
	var corner: float = L.corner
	var hinge: Vector3 = L.hinge
	# Sharp at the lip seam between the corners, softening into the cheeks past them.
	var band := 0.0005 + 0.9 * maxf(0.0, q.x - corner)
	var w := smoothstep(band, -band, q.y - seam) if lip < 0.0 else lip
	# Past the corners the cheek above the seam stays put.
	w *= 1.0 - smoothstep(corner + 0.005, corner + 0.03, q.x) * smoothstep(seam - 0.02, seam + 0.005, q.y)
	# Fade toward the ears and the back of the jaw.
	w *= 1.0 - smoothstep(0.058, 0.078, q.x)
	w *= smoothstep(hinge.z - 0.005, hinge.z + 0.03, q.z)
	# Under the chin, the throat stays.
	var under_chin := smoothstep(seam - 0.03, seam - 0.05, q.y)
	w *= lerpf(1.0, smoothstep(hinge.z + 0.03, hinge.z + 0.06, q.z), under_chin)
	return w


static func _mouth_corner(q: Vector3, L: Dictionary, offset: Vector3) -> Vector3:
	var c := Vector3(L.corner, L.seam, L.inner_z + 0.006)
	var d := q - c
	if q.z < L.inner_z - 0.02:
		return Vector3.ZERO
	var w := _bump(Vector3(d.x / 0.03, d.y / 0.022, d.z / 0.04).length())
	return offset * w


## Parts the lips (upper lip up, lower lip down) between the corners.
static func _lip_part(q: Vector3, L: Dictionary, up: float, down: float, lip: float) -> Vector3:
	var seam: float = L.seam
	var corner: float = L.corner
	if q.z < L.inner_z - 0.004 or q.x > corner + 0.01:
		return Vector3.ZERO
	var across := 1.0 - smoothstep(corner * 0.6, corner + 0.008, q.x)
	var dy := q.y - seam
	if lip == 0.0 or (lip < 0.0 and dy >= 0.0):
		return Vector3(0.0, up, 0.0) * across * (1.0 - smoothstep(0.004, 0.016, absf(dy)))
	return Vector3(0.0, -down, 0.0) * across * (1.0 - smoothstep(0.004, 0.016, absf(dy)))


## 1 at 0, easing to 0 at 1.
static func _bump(x: float) -> float:
	return 1.0 - smoothstep(0.0, 1.0, x)


# --- Mouth interior --------------------------------------------------------------------

## A dark mouth cavity, a tongue and two rows of teeth behind the lips. Returns
## {arrays (vertices, normals, colours, skinning copied from the nearest lip vertex),
## jaw (per vertex, how much it follows the jaw)}.
static func mouth_interior(L: Dictionary, body_vertices: PackedVector3Array, bones: PackedInt32Array,
		weights: PackedFloat32Array, influences: int) -> Dictionary:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var seam: float = L.seam
	var corner: float = L.corner
	var inner: float = L.inner_z
	# Cavity: an ellipsoid just behind the teeth, seen from inside.
	var centre := Vector3(0.0, seam - 0.004, inner - 0.027)
	var radii := Vector3(corner * 1.05, 0.017, 0.0205)
	var rings := 10
	var segments := 16
	var cavity := Color(0.16, 0.045, 0.04)
	for i in rings + 1:
		var lat := lerpf(-PI / 2, PI / 2, float(i) / rings)
		for j in segments + 1:
			var lon := lerpf(-PI, PI, float(j) / segments)
			var n := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
			verts.append(centre + n * radii)
			normals.append(-n)
			colors.append(cavity.darkened(0.5 * (1.0 - n.z) * 0.6))
	for i in rings:
		for j in segments:
			var a := i * (segments + 1) + j
			var b := a + segments + 1
			indices.append_array([a, a + 1, b, b, a + 1, b + 1])
	# Tongue: a low dome on the floor of the mouth.
	var tongue := Color(0.42, 0.14, 0.13)
	var jaw := PackedFloat32Array()
	for p in verts: # the cavity: its floor goes with the jaw
		jaw.append(smoothstep(seam + 0.0005, seam - 0.0005, p.y))
	var tongue_base := verts.size()
	var tongue_centre := Vector3(0.0, seam - 0.009, inner - 0.0225)
	var tongue_radii := Vector3(corner * 0.72, 0.0055, 0.0165)
	for i in 5:
		var lat := lerpf(0.0, PI / 2, float(i) / 4)
		for j in segments + 1:
			var lon := lerpf(-PI, PI, float(j) / segments)
			var n := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
			verts.append(tongue_centre + n * tongue_radii)
			normals.append((n / tongue_radii).normalized())
			colors.append(tongue.darkened(0.45 * (1.0 - n.z)))
	for i in 4:
		for j in segments:
			var a := tongue_base + i * (segments + 1) + j
			var b := a + segments + 1
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	for i in verts.size() - tongue_base:
		jaw.append(1.0)
	# Teeth: a curved row each, just behind the crease. The biting edge is scalloped, with
	# a darker gap between neighbours.
	var tooth := Color(0.74, 0.71, 0.64)
	for row: float in [1.0, -1.0]:
		var base := verts.size()
		var teeth := 8
		var columns := teeth * 6
		for j in columns + 1:
			var x := lerpf(-corner * 0.8, corner * 0.8, float(j) / columns)
			var gap := pow(0.5 + 0.5 * cos(TAU * float(j) / 6.0), 4.0) # 1 between two teeth, 0 across the tooth
			# The lower row sits a little behind the upper one.
			var z := inner - (0.0018 if row > 0.0 else 0.0032) - 10.0 * x * x
			var near: float = seam + 0.0002 if row > 0.0 else seam + 0.0018 # the lower row tucks behind the upper (overbite)
			near += row * 0.0003 * gap
			var far: float = near + row * 0.008
			var n := Vector3(x * 18.0, 0.0, 1.0).normalized()
			verts.append(Vector3(x, near, z))
			verts.append(Vector3(x, far, z - 0.002))
			normals.append(n)
			normals.append(n)
			# Darker toward the corners, where they sit deeper in shadow.
			var shade := tooth.darkened(absf(x) / corner * 0.5 + 0.3 * gap * gap)
			colors.append(shade)
			colors.append(shade.darkened(0.4))
		for j in columns:
			var a := base + j * 2
			indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
		for i in verts.size() - base:
			jaw.append(0.0 if row > 0.0 else 1.0)
	# Skinning: the nearest lip vertex's.
	var out_bones := PackedInt32Array()
	var out_weights := PackedFloat32Array()
	for p in verts:
		var best := 0
		var best_d := INF
		for c in L.crease.size():
			var d: float = (L.crease[c] as Vector3).distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = c
		var source := body_vertices.find(L.crease[best])
		out_bones.append_array(bones.slice(source * influences, (source + 1) * influences))
		out_weights.append_array(weights.slice(source * influences, (source + 1) * influences))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = out_bones
	arrays[Mesh.ARRAY_WEIGHTS] = out_weights
	arrays[Mesh.ARRAY_INDEX] = indices
	return {arrays = arrays, jaw = jaw}


## The interior moves with the jaw by its `jaw` weights.
static func displace_interior(points: PackedVector3Array, jaw: PackedFloat32Array, L: Dictionary) -> Dictionary:
	var result := {}
	for shape in SHAPES:
		var moved := points.duplicate()
		for i in points.size():
			var p := points[i]
			var below := jaw[i]
			if shape == &"jaw_open":
				moved[i] = _rotate_about(p, L.hinge, -JAW_ANGLE * below)
			elif shape == &"grimace":
				moved[i] = p + Vector3(0.0, -0.002 * below, 0.0)
		result[shape] = moved
	return result


static func mouth_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "MI_Mouth"
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.55
	m.metallic_specular = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# --- Mesh assembly ---------------------------------------------------------------------

## A copy of `mesh` (any skinned mesh on the head) with every shape as a blend shape.
## `body` = true for the head mesh itself: cuts the mouth open and adds the interior.
static func build(mesh: ArrayMesh, L: Dictionary, openings: Array, body: bool) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED # absolute targets, blended linearly
	for shape in SHAPES:
		out.add_blend_shape(shape)
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var lip := PackedFloat32Array()
		if body and s == 0:
			var cut := cut_mouth(verts, arrays[Mesh.ARRAY_INDEX], L)
			arrays[Mesh.ARRAY_INDEX] = cut.indices
			lip = cut.lip
		var anchor := PackedVector3Array() if body else _piece_bottoms(verts, arrays[Mesh.ARRAY_INDEX])
		var moved := displace(verts, L, openings, lip, anchor)
		_add_surface(out, arrays, moved, mesh.surface_get_material(s), mesh.surface_get_name(s))
	if body:
		var arrays := mesh.surface_get_arrays(0)
		var influences: int = arrays[Mesh.ARRAY_BONES].size() / arrays[Mesh.ARRAY_VERTEX].size()
		var interior := mouth_interior(L, arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_BONES],
			arrays[Mesh.ARRAY_WEIGHTS], influences)
		_add_surface(out, interior.arrays, displace_interior(interior.arrays[Mesh.ARRAY_VERTEX], interior.jaw, L),
			mouth_material(), "mouth")
	return out


static func _add_surface(out: ArrayMesh, arrays: Array, moved: Dictionary, material: Material, surface_name: String) -> void:
	# Custom channels come back without their format flags, and no material reads them.
	for channel in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[channel] = null
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base_smooth := _smooth_normals(verts, indices)
	var shapes: Array[Array] = []
	for shape in SHAPES:
		var shape_verts: PackedVector3Array = moved[shape]
		var smooth := _smooth_normals(shape_verts, indices)
		var shape_normals := PackedVector3Array()
		shape_normals.resize(verts.size())
		for i in verts.size():
			# Keep the original (possibly split) normal, turned as much as the surface turned.
			var turn := Quaternion(base_smooth[i], smooth[i]) if base_smooth[i] != smooth[i] else Quaternion.IDENTITY
			shape_normals[i] = (turn * normals[i]).normalized()
		var shape_arrays := []
		shape_arrays.resize(Mesh.ARRAY_MAX)
		shape_arrays[Mesh.ARRAY_VERTEX] = shape_verts
		shape_arrays[Mesh.ARRAY_NORMAL] = shape_normals
		if arrays[Mesh.ARRAY_TANGENT] != null:
			shape_arrays[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
		shapes.append(shape_arrays)
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	var s := out.get_surface_count() - 1
	out.surface_set_material(s, material)
	out.surface_set_name(s, surface_name)


## Area-weighted vertex normals over the mesh welded by position (so UV seams don't show).
static func _smooth_normals(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var weld := _weld(verts)
	var acc := PackedVector3Array()
	acc.resize(verts.size())
	for t in range(0, indices.size(), 3):
		var a := indices[t]
		var b := indices[t + 1]
		var c := indices[t + 2]
		var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		acc[weld[a]] += n
		acc[weld[b]] += n
		acc[weld[c]] += n
	var result := PackedVector3Array()
	result.resize(verts.size())
	for i in verts.size():
		result[i] = acc[weld[i]].normalized()
	return result


## Per vertex, the first vertex at the same position (meshes split vertices at UV seams).
static func _weld(verts: PackedVector3Array) -> PackedInt32Array:
	var key := {}
	var weld := PackedInt32Array()
	weld.resize(verts.size())
	for i in verts.size():
		var k := Vector3i((verts[i] * 100000.0).round())
		if not key.has(k):
			key[k] = i
		weld[i] = key[k]
	return weld


## Per vertex, the lowest point of the connected piece it belongs to.
static func _piece_bottoms(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var weld := _weld(verts)
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for i in verts.size():
		parent[i] = i
	var find := func(i: int) -> int:
		while parent[i] != i:
			i = parent[i]
		return i
	for t in range(0, indices.size(), 3):
		var a: int = find.call(weld[indices[t]])
		for c in [1, 2]:
			var b: int = find.call(weld[indices[t + c]])
			if a != b:
				parent[b] = a
	var lowest := {}
	for i in verts.size():
		var root: int = find.call(weld[i])
		if not lowest.has(root) or verts[i].y < (lowest[root] as Vector3).y:
			lowest[root] = verts[i]
	var result := PackedVector3Array()
	result.resize(verts.size())
	for i in verts.size():
		result[i] = lowest[find.call(weld[i])]
	return result
