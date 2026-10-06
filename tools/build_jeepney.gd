extends SceneTree
## Generates the jeepney mesh (res://assets/stages/market/jeepney.res) for the night
## market stage. Local frame: front toward +X, ground at y = 0, centred on z = 0; about
## 5.6 m long, 2 m wide, 2.6 m tall with the sign board.
##
## Run: godot_console --headless --path . -s res://tools/build_jeepney.gd
##
## Curved parts are generated, not boxes: a lofted bonnet that narrows toward the nose,
## chrome fenders swept over the wheels, rounded body panels and roof (rounded-rectangle
## sections lofted along the length), turned tyres, rims and headlights, and the chrome
## horses on the bonnet extruded from a drawn silhouette. One surface per material, named
## (see SURFACES); tools/build_market_stage.gd paints each jeepney through them.

const OUTPUT := "res://assets/stages/market/jeepney.res"
const SURFACES := ["body", "paint", "accent", "accent2", "chrome", "glass", "interior", "seat", "tire", "light", "taillight"]

const WHEEL_R := 0.4
const FRONT_AXLE := 1.7
const REAR_AXLE := -1.75
const TRACK := 0.8 # wheel centre z
const HALF_W := 0.93 # body half width

var _st := {} # surface name -> SurfaceTool


func _initialize() -> void:
	for name: String in SURFACES:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[name] = st
	_body()
	_cabin()
	_roof()
	_interior()
	_front()
	_fenders()
	_wheels()
	_details()
	var mesh := ArrayMesh.new()
	for name: String in SURFACES:
		var st: SurfaceTool = _st[name]
		st.index()
		st.generate_normals()
		st.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, name)
	var err := ResourceSaver.save(mesh, OUTPUT)
	var triangles := 0
	for s in mesh.get_surface_count():
		triangles += mesh.surface_get_array_index_len(s) / 3
	print("saved %s: %d surfaces, %d triangles, err=%d" % [OUTPUT, mesh.get_surface_count(), triangles, err])
	quit()


# --- Parts -------------------------------------------------------------------------

## The passenger body: stainless lower panels (cut away over the rear wheels), with the
## fiesta stripes along both sides.
func _body() -> void:
	for span in [[-2.75, -2.28, 0.55], [-2.28, -1.22, 0.92], [-1.22, 1.22, 0.55]]:
		rounded_box("body", Vector3(span[0], span[2], -HALF_W), Vector3(span[1], 1.4, HALF_W), 0.05)
	for side in [-1.0, 1.0]:
		var z: float = side * (HALF_W + 0.006)
		rounded_box("accent", Vector3(-2.75, 1.0, z - 0.01), Vector3(1.22, 1.1, z + 0.01), 0.004)
		rounded_box("accent2", Vector3(-2.75, 1.16, z - 0.01), Vector3(1.22, 1.21, z + 0.01), 0.004)
		rounded_box("accent2", Vector3(-2.75, 0.78, z - 0.01), Vector3(-2.28, 0.84, z + 0.01), 0.004)
		rounded_box("accent2", Vector3(-1.22, 0.78, z - 0.01), Vector3(1.22, 0.84, z + 0.01), 0.004)


## Window bays: a chrome sill and header, painted pillars, open between them.
func _cabin() -> void:
	for side in [-1.0, 1.0]:
		var z: float = side * HALF_W
		rounded_box("chrome", Vector3(-2.78, 1.38, z - 0.035), Vector3(1.24, 1.43, z + 0.035), 0.015)
		rounded_box("paint", Vector3(-2.78, 2.04, z - 0.03), Vector3(1.24, 2.13, z + 0.03), 0.015)
		for x in [-2.72, -2.12, -1.52, -0.92, -0.32, 0.28, 0.88]:
			rounded_box("paint", Vector3(x - 0.04, 1.42, z - 0.03), Vector3(x + 0.04, 2.06, z + 0.03), 0.015)
		# A-pillar beside the windscreen.
		rounded_box("paint", Vector3(1.16, 1.42, z - 0.04), Vector3(1.26, 2.12, z + 0.04), 0.015)
	# Rear corner posts and the open back with its chrome grab rails.
	for side in [-1.0, 1.0]:
		rounded_box("paint", Vector3(-2.8, 1.4, side * HALF_W - 0.05), Vector3(-2.72, 2.12, side * HALF_W + 0.05), 0.015)
		tube("chrome", [Vector3(-2.82, 0.75, side * 0.62), Vector3(-2.82, 1.95, side * 0.62)], 0.018)


## Roof: a rounded slab overhanging the windscreen as a visor, roof rails on posts, the
## route-sign board and two chrome antennas at the front corners.
func _roof() -> void:
	loft("paint", [
		[-2.92, rounded_rect(1.98, 0.13, 0.05, 2.19)],
		[1.18, rounded_rect(1.98, 0.13, 0.05, 2.19)],
		[1.42, rounded_rect(1.9, 0.1, 0.04, 2.16)],
	], true)
	for side in [-1.0, 1.0]:
		tube("chrome", [Vector3(-2.8, 2.36, side * 0.88), Vector3(1.15, 2.36, side * 0.88)], 0.02)
		for x in [-2.7, -1.4, -0.1, 1.05]:
			tube("chrome", [Vector3(x, 2.25, side * 0.88), Vector3(x, 2.36, side * 0.88)], 0.012)
		tube("chrome", [Vector3(1.3, 2.25, side * 0.86), Vector3(1.38, 2.95, side * 0.86)], 0.007)
		sphere("chrome", Vector3(1.38, 2.96, side * 0.86), 0.025)
	rounded_box("interior", Vector3(1.0, 2.26, -0.55), Vector3(1.08, 2.6, 0.55), 0.02) # sign board


## Inside: the floor, two long bench seats facing each other with backrests, the
## partition behind the driver, the driver's seat and steering wheel.
func _interior() -> void:
	rounded_box("interior", Vector3(-2.74, 0.6, -0.9), Vector3(1.2, 0.66, 0.9), 0.01)
	for side in [-1.0, 1.0]:
		rounded_box("seat", Vector3(-2.6, 0.92, side * 0.62 - 0.18), Vector3(0.75, 1.0, side * 0.62 + 0.18), 0.03)
		rounded_box("interior", Vector3(-2.6, 0.66, side * 0.62 - 0.12), Vector3(0.75, 0.92, side * 0.62 + 0.12), 0.01)
		rounded_box("seat", Vector3(-2.6, 1.02, side * 0.86 - 0.03), Vector3(0.75, 1.42, side * 0.86 + 0.03), 0.02)
	rounded_box("interior", Vector3(0.82, 0.66, -0.88), Vector3(0.88, 1.6, 0.88), 0.01)
	rounded_box("seat", Vector3(0.92, 0.95, 0.15), Vector3(1.12, 1.03, 0.7), 0.03)
	rounded_box("seat", Vector3(0.9, 1.03, 0.15), Vector3(0.96, 1.45, 0.7), 0.02)
	torus("interior", Vector3(1.12, 1.48, 0.42), Vector3(0.75, 0.66, 0.0).normalized(), 0.17, 0.018)
	rounded_box("interior", Vector3(1.15, 1.25, -0.85), Vector3(1.28, 1.42, 0.85), 0.02) # dashboard


## The front: the windscreen (two reclined panes), the lofted bonnet, the chrome grille
## with its vertical bars, round headlights, the big bumper and the horses.
func _front() -> void:
	for side in [-1.0, 1.0]:
		var pane := Transform3D(Basis(Vector3.BACK, deg_to_rad(-9.0)), Vector3(1.24, 1.76, side * 0.43))
		box("glass", pane, Vector3(0.02, 0.62, 0.8))
	box("chrome", Transform3D(Basis(Vector3.BACK, deg_to_rad(-9.0)), Vector3(1.245, 1.76, 0)), Vector3(0.03, 0.64, 0.05))
	# Bonnet: narrows and dips slightly toward the nose.
	loft("paint", [
		[1.2, rounded_rect(1.44, 0.62, 0.12, 1.12)],
		[2.0, rounded_rect(1.4, 0.58, 0.12, 1.1)],
		[2.66, rounded_rect(1.32, 0.52, 0.11, 1.06)],
	], true)
	for side in [-1.0, 1.0]: # chrome strip along the bonnet's shoulder
		tube("chrome", [Vector3(1.22, 1.43, side * 0.6), Vector3(2.62, 1.33, side * 0.55)], 0.012)
	# Grille.
	rounded_box("chrome", Vector3(2.66, 0.86, -0.46), Vector3(2.72, 1.3, 0.46), 0.03)
	rounded_box("interior", Vector3(2.7, 0.9, -0.41), Vector3(2.73, 1.26, 0.41), 0.01)
	for i in 11:
		var z := -0.38 + i * 0.076
		rounded_box("chrome", Vector3(2.71, 0.9, z - 0.012), Vector3(2.75, 1.26, z + 0.012), 0.008)
	# Headlights: chrome rings with glowing lenses, and a pair of fog lamps.
	for side in [-1.0, 1.0]:
		lathe("chrome", Vector3(2.66, 1.12, side * 0.57), Vector3.RIGHT, [Vector2(0.0, -0.02), Vector2(0.13, -0.02), Vector2(0.135, 0.06), Vector2(0.11, 0.08)], 20)
		lathe("light", Vector3(2.66, 1.12, side * 0.57), Vector3.RIGHT, [Vector2(0.0, 0.085), Vector2(0.105, 0.075), Vector2(0.11, 0.07)], 20)
		lathe("chrome", Vector3(2.82, 0.86, side * 0.7), Vector3.RIGHT, [Vector2(0.0, -0.02), Vector2(0.07, -0.02), Vector2(0.075, 0.04)], 14)
		lathe("light", Vector3(2.82, 0.86, side * 0.7), Vector3.RIGHT, [Vector2(0.0, 0.045), Vector2(0.065, 0.04)], 14)
	# Bumper with two guards.
	loft("chrome", [
		[2.76, rounded_rect(2.0, 0.17, 0.06, 0.7)],
		[2.9, rounded_rect(1.94, 0.15, 0.06, 0.7)],
	], true)
	for side in [-1.0, 1.0]:
		rounded_box("chrome", Vector3(2.78, 0.6, side * 0.3 - 0.04), Vector3(2.95, 1.0, side * 0.3 + 0.04), 0.03)
	# The chrome horses, reared up facing forward on top of the bonnet.
	for side in [-1.0, 1.0]:
		extrude("chrome", HORSE, Transform3D(Basis(), Vector3(2.38, 1.32, side * 0.22)), 0.035, 0.34)


## Chrome fenders swept in arches over the four wheels; the front ones run back into
## the running boards.
func _fenders() -> void:
	for side in [-1.0, 1.0]:
		var z: float = side * (TRACK + 0.02)
		arch("chrome", Vector3(FRONT_AXLE, WHEEL_R, z), WHEEL_R + 0.12, -8.0, 188.0, 0.36, 0.05)
		arch("chrome", Vector3(REAR_AXLE, WHEEL_R, side * (HALF_W - 0.05)), WHEEL_R + 0.1, 0.0, 180.0, 0.24, 0.04)
		rounded_box("chrome", Vector3(1.05, 0.5, z - 0.17), Vector3(FRONT_AXLE - WHEEL_R - 0.12, 0.56, z + 0.17), 0.02) # running board


func _wheels() -> void:
	for axle in [FRONT_AXLE, REAR_AXLE]:
		for side in [-1.0, 1.0]:
			var c := Vector3(axle, WHEEL_R, side * TRACK)
			var out := Vector3(0, 0, side)
			# Tyre: a rounded section turned around the axle.
			lathe("tire", c, out, [Vector2(0.24, -0.12), Vector2(0.34, -0.125), Vector2(0.39, -0.1), Vector2(0.4, -0.04),
				Vector2(0.4, 0.04), Vector2(0.39, 0.1), Vector2(0.34, 0.125), Vector2(0.24, 0.12)], 28)
			# Rim and hubcap.
			lathe("chrome", c, out, [Vector2(0.24, 0.12), Vector2(0.2, 0.1), Vector2(0.12, 0.12), Vector2(0.06, 0.15), Vector2(0.0, 0.155)], 24)


## Mirrors, mudflaps, tail lights, the rear step.
func _details() -> void:
	for side in [-1.0, 1.0]:
		tube("chrome", [Vector3(1.28, 1.5, side * 0.95), Vector3(1.3, 1.78, side * 1.08)], 0.01)
		rounded_box("chrome", Vector3(1.26, 1.72, side * 1.08 - 0.07), Vector3(1.33, 1.92, side * 1.08 + 0.07), 0.03)
		rounded_box("interior", Vector3(REAR_AXLE - 0.62, 0.12, side * TRACK - 0.14), Vector3(REAR_AXLE - 0.6, 0.6, side * TRACK + 0.14), 0.01)
		rounded_box("accent", Vector3(REAR_AXLE - 0.625, 0.18, side * TRACK - 0.12), Vector3(REAR_AXLE - 0.595, 0.24, side * TRACK + 0.12), 0.005)
		rounded_box("taillight", Vector3(-2.79, 0.72, side * 0.82 - 0.06), Vector3(-2.75, 0.9, side * 0.82 + 0.06), 0.015)
	rounded_box("chrome", Vector3(-3.0, 0.42, -0.5), Vector3(-2.75, 0.47, 0.5), 0.015) # rear step
	loft("chrome", [[-2.92, rounded_rect(1.98, 0.12, 0.05, 0.62)], [-2.8, rounded_rect(1.98, 0.12, 0.05, 0.62)]], true) # rear bumper


## A rearing horse in profile (x forward, y up; unit height, scaled when extruded).
const HORSE := [
	Vector2(-0.30, 0.00), Vector2(-0.22, 0.00), Vector2(-0.18, 0.22), Vector2(-0.08, 0.30), Vector2(0.02, 0.30),
	Vector2(0.06, 0.22), Vector2(0.10, 0.00), Vector2(0.17, 0.00), Vector2(0.15, 0.30), Vector2(0.10, 0.42),
	Vector2(0.20, 0.55), Vector2(0.32, 0.50), Vector2(0.30, 0.58), Vector2(0.22, 0.66), Vector2(0.30, 0.78),
	Vector2(0.26, 0.86), Vector2(0.16, 0.80), Vector2(0.12, 0.92), Vector2(0.18, 1.00), Vector2(0.10, 1.00),
	Vector2(0.02, 0.88), Vector2(-0.08, 0.68), Vector2(-0.22, 0.58), Vector2(-0.36, 0.62), Vector2(-0.44, 0.48),
	Vector2(-0.34, 0.50), Vector2(-0.26, 0.40),
]


# --- Mesh builders -------------------------------------------------------------------

## A rounded rectangle section (z, y) centred on z = 0: `width` across, `height` tall,
## centred at height `cy`, corner radius `r`. Counter-clockwise.
func rounded_rect(width: float, height: float, r: float, cy: float, corner_steps := 3) -> PackedVector2Array:
	var points := PackedVector2Array()
	var hw := width / 2.0 - r
	var hh := height / 2.0 - r
	for corner in [[hw, hh, 0.0], [-hw, hh, 90.0], [-hw, -hh, 180.0], [hw, -hh, 270.0]]:
		for k in corner_steps + 1:
			var a := deg_to_rad(corner[2] + 90.0 * k / corner_steps)
			points.append(Vector2(corner[0] + cos(a) * r, cy + corner[1] + sin(a) * r))
	return points


## A box from `lo` to `hi` with rounded long edges (a rounded section lofted along X).
func rounded_box(surface: String, lo: Vector3, hi: Vector3, r: float) -> void:
	r = minf(r, minf(hi.y - lo.y, hi.z - lo.z) * 0.45)
	var section := rounded_rect(hi.z - lo.z, hi.y - lo.y, r, (lo.y + hi.y) / 2.0, 2)
	for i in section.size():
		section[i].x += (lo.z + hi.z) / 2.0
	loft(surface, [[lo.x, section], [hi.x, section]], true)


## Connects sections [x, PackedVector2Array of (z, y)] along X; all sections have the
## same number of points. `caps` closes both ends.
func loft(surface: String, sections: Array, caps: bool) -> void:
	var st: SurfaceTool = _st[surface]
	st.set_smooth_group(0)
	for s in sections.size() - 1:
		var x0: float = sections[s][0]
		var x1: float = sections[s + 1][0]
		var a: PackedVector2Array = sections[s][1]
		var b: PackedVector2Array = sections[s + 1][1]
		var ca := _centroid(a)
		var cb := _centroid(b)
		for i in a.size():
			var j := (i + 1) % a.size()
			var p0 := Vector3(x0, a[i].y, a[i].x)
			var p1 := Vector3(x0, a[j].y, a[j].x)
			var p2 := Vector3(x1, b[j].y, b[j].x)
			var p3 := Vector3(x1, b[i].y, b[i].x)
			var mid := (p0 + p1 + p2 + p3) / 4.0
			var axis := Vector3(mid.x, (ca.y + cb.y) / 2.0, (ca.x + cb.x) / 2.0)
			_quad(st, p0, p1, p2, p3, mid - axis)
	if caps:
		st.set_smooth_group(0xFFFFFFFF)
		_cap(st, sections[0][0], sections[0][1], Vector3.LEFT)
		_cap(st, sections[-1][0], sections[-1][1], Vector3.RIGHT)


## A plain box (any orientation).
func box(surface: String, xform: Transform3D, size: Vector3) -> void:
	var st: SurfaceTool = _st[surface]
	st.set_smooth_group(0xFFFFFFFF)
	var h := size / 2.0
	for axis in 3:
		for sign in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sign
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := n.cross(u)
			var c := n * h[axis]
			var pts := []
			for q in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				pts.append(xform * (c + u * h[(axis + 1) % 3] * q[0] + v * _abs_component(h, v) * q[1]))
			_quad(st, pts[0], pts[1], pts[2], pts[3], xform.basis * n)


## A round tube through `points` (straight segments).
func tube(surface: String, points: Array, radius: float, sides := 8) -> void:
	var st: SurfaceTool = _st[surface]
	st.set_smooth_group(0)
	for s in points.size() - 1:
		var a: Vector3 = points[s]
		var b: Vector3 = points[s + 1]
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(dir)
		for i in sides:
			var t0 := TAU * i / sides
			var t1 := TAU * (i + 1) / sides
			var o0 := side * cos(t0) * radius + up * sin(t0) * radius
			var o1 := side * cos(t1) * radius + up * sin(t1) * radius
			_quad(st, a + o0, a + o1, b + o1, b + o0, (o0 + o1) / 2.0)


func sphere(surface: String, center: Vector3, radius: float) -> void:
	lathe(surface, center - Vector3.UP * radius, Vector3.UP, [Vector2(0.0, 0.0), Vector2(radius * 0.7, radius * 0.3),
		Vector2(radius, radius), Vector2(radius * 0.7, radius * 1.7), Vector2(0.0, radius * 2.0)], 10)


## A profile of (radius, height along `axis`) points turned around `axis` through `base`.
func lathe(surface: String, base: Vector3, axis: Vector3, profile: Array, steps: int) -> void:
	var st: SurfaceTool = _st[surface]
	st.set_smooth_group(0)
	var a := axis.normalized()
	var u := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := a.cross(u)
	var c2 := Vector2.ZERO
	for p: Vector2 in profile:
		c2 += p
	c2 /= profile.size()
	for i in steps:
		var t0 := TAU * i / steps
		var t1 := TAU * (i + 1) / steps
		var r0 := u * cos(t0) + v * sin(t0)
		var r1 := u * cos(t1) + v * sin(t1)
		for k in profile.size() - 1:
			var p: Vector2 = profile[k]
			var q: Vector2 = profile[k + 1]
			var p0 := base + r0 * p.x + a * p.y
			var p1 := base + r0 * q.x + a * q.y
			var p2 := base + r1 * q.x + a * q.y
			var p3 := base + r1 * p.x + a * p.y
			var mid2 := (p + q) / 2.0
			var out2 := mid2 - Vector2(0.0, c2.y) if absf(mid2.x) > 1e-4 else Vector2(0, mid2.y - c2.y)
			var rmid := (r0 + r1).normalized()
			_quad(st, p0, p1, p2, p3, rmid * out2.x + a * out2.y)


## A ring around `axis` (steering wheel).
func torus(surface: String, center: Vector3, axis: Vector3, major: float, minor: float) -> void:
	var a := axis.normalized()
	var u := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := a.cross(u)
	var points := []
	for i in 21:
		var t := TAU * i / 20.0
		points.append(center + (u * cos(t) + v * sin(t)) * major)
	tube(surface, points, minor, 6)


## A strip of section `width` (along z) and `thickness` swept along an arc around `center`
## (in the XY plane) from `from_deg` to `to_deg` (0 = toward +X): a wheel arch.
func arch(surface: String, center: Vector3, radius: float, from_deg: float, to_deg: float, width: float, thickness: float) -> void:
	var st: SurfaceTool = _st[surface]
	st.set_smooth_group(0)
	var steps := 14
	var section := rounded_rect(width, thickness, thickness * 0.45, 0.0, 2)
	var rings := []
	for i in steps + 1:
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
		var radial := Vector3(cos(a), sin(a), 0)
		var ring := []
		for p: Vector2 in section:
			ring.append(center + radial * (radius + p.y) + Vector3(0, 0, p.x))
		rings.append([ring, center + radial * radius])
	for i in steps:
		var r0: Array = rings[i][0]
		var r1: Array = rings[i + 1][0]
		for k in r0.size():
			var j := (k + 1) % r0.size()
			var mid: Vector3 = (r0[k] + r0[j] + r1[j] + r1[k]) / 4.0
			_quad(st, r0[k], r0[j], r1[j], r1[k], mid - (rings[i][1] + rings[i + 1][1]) / 2.0)


## A 2D outline (x forward, y up, unit height) scaled to `height`, extruded `depth` along
## z and placed with `xform`.
func extrude(surface: String, outline: Array, xform: Transform3D, depth: float, height: float) -> void:
	var st: SurfaceTool = _st[surface]
	var polygon := PackedVector2Array()
	for p: Vector2 in outline:
		polygon.append(p * height)
	var indices := Geometry2D.triangulate_polygon(polygon)
	st.set_smooth_group(0xFFFFFFFF)
	for side in [-1.0, 1.0]:
		var z: float = side * depth / 2.0
		for t in range(0, indices.size(), 3):
			var a := xform * Vector3(polygon[indices[t]].x, polygon[indices[t]].y, z)
			var b := xform * Vector3(polygon[indices[t + 1]].x, polygon[indices[t + 1]].y, z)
			var c := xform * Vector3(polygon[indices[t + 2]].x, polygon[indices[t + 2]].y, z)
			_tri(st, a, b, c, xform.basis * Vector3(0, 0, side))
	var center := Vector2.ZERO
	for p in polygon:
		center += p
	center /= polygon.size()
	var clockwise := Geometry2D.is_polygon_clockwise(polygon)
	for i in polygon.size():
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		var edge := q - p
		var out2 := Vector2(edge.y, -edge.x) if not clockwise else Vector2(-edge.y, edge.x)
		var a := xform * Vector3(p.x, p.y, -depth / 2.0)
		var b := xform * Vector3(q.x, q.y, -depth / 2.0)
		var c := xform * Vector3(q.x, q.y, depth / 2.0)
		var d := xform * Vector3(p.x, p.y, depth / 2.0)
		_quad(st, a, b, c, d, xform.basis * Vector3(out2.x, out2.y, 0))


# --- Triangles ---------------------------------------------------------------------

## Emits a triangle facing `out` (Godot's front faces are clockwise seen from outside).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	if (c - a).cross(b - a).dot(out) < 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	_tri(st, a, b, c, out)
	_tri(st, a, c, d, out)


func _cap(st: SurfaceTool, x: float, section: PackedVector2Array, out: Vector3) -> void:
	var c := _centroid(section)
	var center := Vector3(x, c.y, c.x)
	for i in section.size():
		var j := (i + 1) % section.size()
		_tri(st, center, Vector3(x, section[i].y, section[i].x), Vector3(x, section[j].y, section[j].x), out)


func _centroid(points: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in points:
		c += p
	return c / points.size()


func _abs_component(h: Vector3, dir: Vector3) -> float:
	return absf(h.x * dir.x) + absf(h.y * dir.y) + absf(h.z * dir.z)
