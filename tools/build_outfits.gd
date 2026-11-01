extends SceneTree
## Generates each fighter's clothing from their base body mesh and saves it into the
## character data. Run: godot_console --headless --path . -s res://tools/build_outfits.gd
## (append `-- <id> ...` to rebuild only those fighters)
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
## inset), so nothing pokes through and no gap opens at the hems, and with the facial
## expression blend shapes (tools/face_shapes.gd).
## Outfit references: karate gi (cross-over jacket with a V opening, belt, headband),
## Tae Kwon Do dobok (closed V-neck pullover, black collar for black belts), kickboxing
## gear, pro-wrestling singlet with knee pads and boots, brawler tank top and work pants,
## street gear (sleeveless zip-up, track pants with side stripes, fingerless gloves,
## sneakers), Wing Chun uniform (short-sleeved kung fu jacket with a standing collar and a
## contrast placket, loose pants, cloth shoes with white soles).
## Detailed outfits (`detailed = true`) also carry vertex colours: the cloth darkens a
## little toward every hem and opening, and a stitch line runs along each hem (the
## polygons are cut along it, so it stays a crisp line). Their body gets a second UV set
## for the skin pore detail map (FighterModel).

const OUT_DIR := "res://assets/characters/outfits/"
const CHARACTER_DIR := "res://data/characters/"
const HIDE_INSET := 0.015 # body skin this far inside a garment's edge is removed
const NECK_RADIUS := 0.072 # the neck hole of tops and jackets
const ARM_LIMIT := 0.35 # |x| beyond this (T-pose) is arm, never legs or torso
## Detailed outfits: the stitch line runs between these distances inside a hem, and the
## cloth shades from HEM_SHADE at the edge to full brightness HEM_SHADE_DEPTH inside.
const MIN_TRIANGLE_AREA := 1e-9 # (twice the area, m²) smaller triangles are dropped
const STITCH_NEAR := 0.007
const STITCH_FAR := 0.0095
const STITCH_SHADE := 0.62
const HEM_SHADE := 0.8
const HEM_SHADE_DEPTH := 0.035

const TAIL_JOINTS := 3 # spring bones down each belt or headband tail, so it bends as it swings
const TAIL_ROOT_FADE := 0.12 # share of a tail's length, from the knot, still partly held by the knot's bone
const TAIL_PREFIX := "cloth_tail_"
const HEM_FULL_AT := 0.5 # share of a hem chain's length, from its root, where its bones take over fully

enum Slot { MAIN, TRIM, ACCENT, EXTRA }

var _body_skin: Skin
var _pelvis_bind := 0
var _skeleton: Skeleton3D
var _to_skeleton := Transform3D() # body mesh space -> skeleton rest space
var _tails: Array = [] # this outfit's tail chains (the outfit mesh's "spring_tails" meta)


func _initialize() -> void:
	await process_frame
	var specs := _specs()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var only := OS.get_cmdline_user_args() # e.g. `-- mira`: rebuild just these fighters
	for id: String in specs:
		if not only.is_empty() and id not in only:
			continue
		var spec: Dictionary = specs[id]
		var data := load(CHARACTER_DIR + id + ".tres") as CharacterData
		if data == null:
			push_error("No character data for %s" % id)
			continue
		var result := _build(data.model_scene, spec)
		data.detailed_textures = spec.get("detailed", false)
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
## trim slot), `hide = false` (don't remove skin under it) and `flat_soles`. In detailed
## outfits, `stitches = false` leaves the stitch line off thin bands (belts, headbands),
## where cutting along both edges leaves gaps.
func _specs() -> Dictionary:
	return {
		"kenji": {
			detailed = true,
			pieces = func(L: Dictionary) -> Array:
				var v_bottom: float = L.chest - 0.07
				var belt_lo: float = L.hip + 0.04
				var belt_hi: float = L.hip + 0.085
				var hem: float = L.hip - 0.1
				var sleeve_end: float = L.elbow + (L.wrist - L.elbow) * 0.45
				var jacket := func(p, n): return minf(_top(p, L, hem, sleeve_end), -_v_cut(p, n, L, v_bottom, 0.075))
				var collar := func(p, n): return _gi_collar(p, n, L, v_bottom, 0.075, belt_hi)
				# The belt cinches the jacket and the pants.
				var cinch := func(p: Vector3) -> bool: return p.y > belt_lo - 0.012 and p.y < belt_hi + 0.012 and absf(p.x) < ARM_LIMIT
				# Fine triangles also along the collar, which is about one skin triangle wide.
				var jacket_drape := _top_drape(L, {base = 0.026, sleeve_end = sleeve_end, cuff_flare = 0.028, sag = 0.022,
					skirt_from = belt_lo, skirt_flare = 0.03, blouse_at = belt_hi, fine_below = belt_hi + 0.16, pin = cinch,
					fine = func(p: Vector3) -> bool: return _gi_collar(p, Vector3.BACK, L, v_bottom, 0.075, belt_hi) > -0.035})
				var collar_drape := jacket_drape.duplicate()
				collar_drape.extra = 0.007 # (same folds as the jacket, so it never sinks under them)
				return [
					# Gi jacket: loose, past the hips, wide sleeves to mid-forearm, a deep V
					# at the chest, blousing over the belt and pleating below it.
					{slot = Slot.MAIN, offset = 0.026, drape = jacket_drape,
						hem = {top = belt_lo - 0.012, bottom = hem, chains = 8, joints = 2},
						region = func(p, n): return minf(jacket.call(p, n), -collar.call(p, n))},
					# The collar: a stiff quilted band around the neck and down the left
					# panel's edge, which crosses over to the right hip.
					{slot = Slot.MAIN, offset = 0.026, drape = collar_drape,
						stitch_region = func(p, n): return _gi_collar(p, n, L, v_bottom, 0.075, belt_hi, true),
						stitch_rows = [[0.005, 0.0068], [0.011, 0.0128], [0.017, 0.0188], [0.023, 0.0248], [0.029, 0.0308], [0.035, 0.0368]],
						region = func(p, n): return minf(jacket.call(p, n), collar.call(p, n))},
					# Loose gi pants to just above the ankle, fuller toward the hem.
					{slot = Slot.MAIN, offset = 0.02, region = func(p, n): return _legs(p, L.ankle + 0.07, L.waist - 0.02),
						drape = _pants_drape(L, {base = 0.02, flare = 0.022, hem = L.ankle + 0.07, pin = cinch,
							cover = hem, cover_max = 0.021})},
					# Black belt.
					{slot = Slot.TRIM, offset = 0.036, hide = false, stitches = false, region = func(p, n): return _legs(p, belt_lo, belt_hi)},
					# Red headband: snug on the forehead, standing off over the hair at the sides
					# and back.
					{slot = Slot.ACCENT, offset = func(n: Vector3) -> float: return lerpf(0.02, 0.009, clampf(n.z * 1.6 - 0.4, 0.0, 1.0)),
						hide = false, stitches = false, region = func(p, n):
						return minf(minf(p.y - (L.head_top - 0.078), (L.head_top - 0.05) - p.y), 0.15 - absf(p.x))},
				],
			belt_knot = {slot = Slot.TRIM, y = 0.0625, offset = 0.036, tied = true},
			headband_knot = {slot = Slot.ACCENT, y = 0.064, offset = 0.02},
			colors = [Color(0.8, 0.79, 0.76), Color(0.07, 0.07, 0.08), Color(0.78, 0.07, 0.07)],
			alt_colors = [Color(0.15, 0.16, 0.2), Color(0.42, 0.24, 0.1), Color(0.8, 0.8, 0.78)],
			fabrics = [&"cotton", &"cotton", &"cotton"],
		},
		"jin": {
			detailed = true,
			pieces = func(L: Dictionary) -> Array:
				var v_bottom: float = L.chest
				var belt_lo: float = L.hip + 0.04
				var belt_hi: float = L.hip + 0.085
				var hem: float = L.hip - 0.05
				var cinch := func(p: Vector3) -> bool: return p.y > belt_lo - 0.012 and p.y < belt_hi + 0.012 and absf(p.x) < ARM_LIMIT
				return [
					# Dobok: a loose V-neck pullover to the hips, long sleeves a little wider at
					# the cuff, black V collar, bloused over the belt.
					{slot = Slot.MAIN, offset = 0.022, trim_slot = Slot.TRIM,
						trim = func(p, n): return _v_cut(p, n, L, v_bottom - 0.035, 0.08) + 0.03,
						region = func(p, n): return minf(_top(p, L, hem, L.wrist - 0.05), -_v_cut(p, n, L, v_bottom, 0.08)),
						drape = _top_drape(L, {base = 0.022, sleeve_end = L.wrist - 0.05, cuff_flare = 0.014, sag = 0.016,
							skirt_from = belt_lo, skirt_flare = 0.02, blouse_at = belt_hi, amount = 0.9,
							fine_below = belt_hi + 0.16, pin = cinch,
							fine = func(p: Vector3) -> bool: return _v_cut(p, Vector3.BACK, L, v_bottom - 0.035, 0.08) > -0.06}),
						hem = {top = belt_lo - 0.012, bottom = hem, chains = 8, joints = 1}},
					# Loose pants, fuller toward the ankle.
					{slot = Slot.MAIN, offset = 0.016, region = func(p, n): return _legs(p, L.ankle + 0.05, L.waist - 0.02),
						drape = _pants_drape(L, {base = 0.016, flare = 0.02, hem = L.ankle + 0.05, pin = cinch,
							cover = hem, cover_max = 0.018})},
					{slot = Slot.TRIM, offset = 0.032, hide = false, stitches = false, region = func(p, n): return _legs(p, belt_lo, belt_hi)},
				],
			belt_knot = {slot = Slot.TRIM, y = 0.0625, offset = 0.032, tied = true},
			colors = [Color(0.8, 0.8, 0.8), Color(0.06, 0.06, 0.07), Color(0.0, 0.0, 0.0)],
			alt_colors = [Color(0.1, 0.1, 0.11), Color(0.72, 0.1, 0.1), Color(0.0, 0.0, 0.0)],
			fabrics = [&"cotton", &"cotton", &"cotton"],
		},
		"rhea": {
			detailed = true,
			pieces = func(L: Dictionary) -> Array:
				return [
					# Sports crop top: under the bust to the shoulders, scooped neck, sleeveless.
					{slot = Slot.MAIN, offset = 0.005, region = func(p, n):
						return minf(_sleeveless(p, L, L.chest - 0.11, L.shoulder * 0.95), -_scoop(p, L, 0.10, 0.07))},
					# Fight shorts to mid-thigh, covering the waistband: loose Muay Thai legs,
					# wider at the hem, the waistband snug.
					{slot = Slot.TRIM, offset = 0.006, region = func(p, n): return _legs(p, L.knee + 0.2, L.waist + 0.03),
						drape = _pants_drape(L, {base = 0.006, flare = 0.024, hem = L.knee + 0.2, flare_top = L.hip,
							flare_span = L.hip - (L.knee + 0.2), amount = 0.6, leg_fall = 6, max = 0.06,
							pin = func(p: Vector3) -> bool: return p.y > L.waist - 0.01}),
						hem = {legs = true, top = L.hip - 0.08, bottom = L.knee + 0.2, chains = 6, joints = 2}},
					# Hand wraps over the wrists and palms.
					{slot = Slot.ACCENT, offset = 0.004, region = func(p, n):
						return minf(minf(p.y - (L.arm_y - 0.12), absf(p.x) - (L.wrist - 0.08)), (L.wrist + 0.07) - absf(p.x))},
				],
			colors = [Color(0.8, 0.12, 0.16), Color(0.08, 0.08, 0.1), Color(0.8, 0.79, 0.75)],
			alt_colors = [Color(0.12, 0.32, 0.78), Color(0.8, 0.8, 0.82), Color(0.15, 0.15, 0.18)],
			fabrics = [&"stretch", &"stretch", &"cotton"],
		},
		"valka": {
			detailed = true,
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
			detailed = true,
			pieces = func(L: Dictionary) -> Array:
				return [
					# Tank top, tucked into the pants (held at the skin there) and bloused
					# a little above the waistband.
					{slot = Slot.MAIN, offset = 0.009, region = func(p, n):
						return minf(_sleeveless(p, L, L.waist - 0.1, L.shoulder * 0.85), -_scoop(p, L, 0.09, 0.07)),
						drape = _top_drape(L, {base = 0.009, blouse_at = L.waist + 0.01, amount = 0.7, chest_fall = 10,
							fine_below = L.waist + 0.14, pin = func(p: Vector3) -> bool: return p.y < L.waist + 0.01})},
					# Loose work pants over the boot tops, snug at the waistband.
					{slot = Slot.TRIM, offset = 0.016, region = func(p, n): return _legs(p, L.ankle + 0.17, L.waist),
						drape = _pants_drape(L, {base = 0.016, flare = 0.014, hem = L.ankle + 0.17, amount = 0.85,
							pin = func(p: Vector3) -> bool: return p.y > L.waist - 0.035})},
					{slot = Slot.ACCENT, offset = 0.014, flat_soles = true, region = func(p, n): return _legs(p, -1.0, L.ankle + 0.21)},
				],
			colors = [Color(0.34, 0.37, 0.2), Color(0.15, 0.18, 0.26), Color(0.08, 0.06, 0.05)],
			alt_colors = [Color(0.52, 0.52, 0.54), Color(0.22, 0.32, 0.52), Color(0.27, 0.16, 0.08)],
			fabrics = [&"cotton", &"denim", &"leather"],
		},
		"mira": {
			detailed = true,
			pieces = func(L: Dictionary) -> Array:
				var hem: float = L.waist - 0.07
				return [
					# Sleeveless zip-up to the waist, closed at the neck, with a contrast zip
					# down the front and a contrast band at the hem.
					{slot = Slot.MAIN, offset = 0.014, trim_slot = Slot.TRIM,
						region = func(p, n): return _sleeveless(p, L, hem, L.shoulder * 0.9),
						trim = func(p, n): return maxf(_zip(p, n, 0.007), (hem + 0.022) - p.y),
						drape = _top_drape(L, {base = 0.014, amount = 0.6, chest_fall = 8, fine_below = hem + 0.1})},
					# Track pants with contrast stripes down the outside of each leg, gathered
					# by elastic at the waist and the ankles.
					{slot = Slot.ACCENT, offset = 0.010, trim_slot = Slot.TRIM,
						region = func(p, n): return _legs(p, L.ankle + 0.06, L.waist + 0.005),
						trim = func(p, n): return signf(p.x) * n.x - 0.93,
						drape = _pants_drape(L, {base = 0.010, flare = 0.014, hem = L.ankle + 0.06, amount = 0.8,
							cover = hem, cover_max = 0.012,
							pin = func(p: Vector3) -> bool: return p.y > L.waist - 0.03 or p.y < L.ankle + 0.085})},
					# Fingerless gloves: wrist to knuckles.
					{slot = Slot.ACCENT, offset = 0.004, region = func(p, n):
						return minf(minf(p.y - (L.arm_y - 0.12), absf(p.x) - (L.wrist - 0.06)), (L.wrist + 0.085) - absf(p.x))},
					# Leather sneakers over the ankle with a contrast sole, soles flat on the floor.
					{slot = Slot.EXTRA, offset = 0.018, flat_soles = true, trim_slot = Slot.TRIM,
						region = func(p, n): return _legs(p, -1.0, L.ankle + 0.07),
						trim = func(p, n): return 0.03 - p.y},
				],
			colors = [Color(0.13, 0.13, 0.14), Color(0.86, 0.62, 0.12), Color(0.05, 0.05, 0.06), Color(0.82, 0.81, 0.78)],
			alt_colors = [Color(0.8, 0.8, 0.78), Color(0.75, 0.08, 0.08), Color(0.11, 0.11, 0.12), Color(0.72, 0.08, 0.08)],
			fabrics = [&"cotton", &"stretch", &"stretch", &"leather"],
		},
		"lian": {
			detailed = true,
			pieces = func(L: Dictionary) -> Array:
				var hem: float = L.hip - 0.05
				var sleeve: float = L.shoulder + (L.elbow - L.shoulder) * 0.55
				return [
					# Kung fu jacket: to the hips, short sleeves, the collar standing at the neck;
					# contrast trim on the collar, the front placket, the hem and the cuffs.
					{slot = Slot.MAIN, offset = 0.02, trim_slot = Slot.TRIM,
						region = func(p, n): return _top(p, L, hem, sleeve),
						trim = func(p, n): return maxf(maxf(_placket(p, 0.009), p.y - (L.neck - 0.012)),
							maxf((hem + 0.02) - p.y, absf(p.x) - (sleeve - 0.02))),
						# The standing collar stays at the neck (draped, it bridged out to the
						# shoulders).
						drape = _top_drape(L, {base = 0.02, sleeve_end = sleeve, cuff_flare = 0.02, sag = 0.012,
							amount = 0.7, fine_below = hem + 0.12, pin = func(p: Vector3) -> bool: return p.y > L.neck - 0.03,
							fine = func(p: Vector3) -> bool: return _placket(p, 0.04) > 0.0})},
					# Loose pants to the ankle, gathered there and at the waist.
					{slot = Slot.ACCENT, offset = 0.017, region = func(p, n): return _legs(p, L.ankle + 0.04, L.waist - 0.02),
						drape = _pants_drape(L, {base = 0.017, flare = 0.03, hem = L.ankle + 0.04, cover = hem, cover_max = 0.017,
							pin = func(p: Vector3) -> bool: return p.y > L.waist - 0.04 or p.y < L.ankle + 0.06})},
					# Cloth shoes with white soles, flat on the floor.
					{slot = Slot.EXTRA, offset = 0.01, flat_soles = true, trim_slot = Slot.TRIM,
						region = func(p, n): return _legs(p, -1.0, L.ankle + 0.03),
						trim = func(p, n): return 0.022 - p.y},
				],
			colors = [Color(0.1, 0.36, 0.29), Color(0.84, 0.75, 0.52), Color(0.06, 0.06, 0.07), Color(0.07, 0.07, 0.08)],
			alt_colors = [Color(0.8, 0.79, 0.75), Color(0.08, 0.08, 0.09), Color(0.5, 0.06, 0.06), Color(0.08, 0.08, 0.09)],
			fabrics = [&"cotton", &"cotton", &"cotton", &"cotton"],
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


## A zip down the front centre (positive on it), `half_width` either side.
func _zip(p: Vector3, n: Vector3, half_width: float) -> float:
	if p.z <= 0.0 or n.z < 0.3:
		return -1.0
	return half_width - absf(p.x)


## A front placket (positive on it), `half_width` either side of the middle, all the way
## down the front: unlike `_zip` it doesn't depend on the normal, which turns down under
## the bust and made the edges jagged on draped cloth.
func _placket(p: Vector3, half_width: float) -> float:
	return half_width - absf(p.x) if p.z > 0.02 else -1.0


## A rounded neckline front and back (positive inside it): `depth` below the neck,
## `half_width` wide.
func _scoop(p: Vector3, L: Dictionary, depth: float, half_width: float) -> float:
	return minf(p.y - (L.neck - depth), half_width - absf(p.x))


## Karate gi collar band (positive inside it, the distance to its nearer edge): along
## both edges of the V, and on along the left panel's edge from the bottom of the V
## across to the right hip at the belt (left over right). (Around the back of the neck
## the band followed the neck hole into a sunken point; the neckline there is a plain
## stitched hem.)
## `depth`: the distance from the band's outer edge instead (rises steadily across the
## band, for its stitch rows: the tent shape would fool the clipping, which assumes a
## field changes linearly along an edge).
func _gi_collar(p: Vector3, n: Vector3, L: Dictionary, v_bottom: float, width: float, belt_hi: float, depth := false) -> float:
	const BAND := 0.042
	var tent := func(d: float) -> float: return BAND * 0.5 - absf(d - BAND * 0.5)
	var candidates := [-1.0]
	if p.z > 0.0 and n.z >= 0.15:
		if p.y >= v_bottom:
			var half: float = width * (p.y - v_bottom) / (L.neck - v_bottom)
			candidates.append(absf(p.x) - half)
		elif p.y > belt_hi - 0.02:
			# The wearer's right is -X (the T-pose faces +Z).
			var start := Vector2(0.0, v_bottom)
			var along := (Vector2(-0.1, belt_hi) - start).normalized()
			var across := Vector2(-along.y, along.x)
			if across.x < 0.0:
				across = -across
			candidates.append((Vector2(p.x, p.y) - start).dot(across))
	var best: float = candidates[0]
	for d: float in candidates:
		if tent.call(d) > tent.call(best):
			best = d
	return best if depth else tent.call(best)


## Body parts for loose cloth (ClothDrape `hull`): the arms (along X in the T-pose) are
## sliced across X, smoothed over 7 cm either way; the chest falls `chest_fall` slices
## (1.5 cm each) toward the hips and the legs `leg_fall`; the hips stop the fall (separate
## parts above and below them, where a belt sits), and the neck is its own part.
func _hull_part(p: Vector3, L: Dictionary, chest_fall := 13, leg_fall := 10) -> Array:
	if absf(p.x) > L.shoulder + 0.02 and p.y > L.chest - 0.12:
		return ["arm_l" if p.x > 0.0 else "arm_r", 0, 5, 5]
	if absf(p.x) >= ARM_LIMIT:
		return []
	# The neck on its own: the chest's fall would reach up into the head and push a
	# collar out to the width of the jaw.
	if p.y > L.neck - 0.05:
		return ["neck", 1, 1, 1]
	if p.y > L.hip + 0.06:
		return ["chest", 1, chest_fall, 1]
	if p.y > L.hip - 0.04:
		return ["hips", 1, 6, 1]
	return ["leg_l" if p.x > 0.0 else "leg_r", 1, leg_fall, 1]


## ClothDrape spec for a loose top. `o`: base (thickness), sleeve_end, cuff_flare (more
## toward the cuff from the elbow), sag (below the arm), skirt_from / skirt_flare (a
## skirt flaring below that height), blouse_at (a cinch it blouses over), amount (fold
## depth), chest_fall, fine_below (subdivide below this height, plus the sleeves),
## fine (more places to subdivide), pin, max.
func _top_drape(L: Dictionary, o: Dictionary) -> Dictionary:
	var spec := {group = o.get("group", "top"), max = o.get("max", 0.09), fold_amplitude = 0.01,
		hull = func(p: Vector3) -> Array: return _hull_part(p, L, o.get("chest_fall", 13)),
		subdivide = func(p: Vector3) -> bool:
			var fine: Callable = o.get("fine", func(_p: Vector3) -> bool: return false)
			return absf(p.x) > L.shoulder - 0.02 or p.y < o.get("fine_below", -INF) or fine.call(p),
		min = func(p, n): return _loose_top_min(p, n, L, o),
		folds = func(p, n): return _loose_top_folds(p, L, o)}
	if o.has("pin"):
		spec.pin = o.pin
	return spec


## ClothDrape spec for loose pants (or shorts). `o`: base, flare (more toward the hem
## from `flare_top`, by default just above the knee), hem, cover / cover_max (a top
## over them above that height: no thicker than this there), amount, leg_fall, pin.
func _pants_drape(L: Dictionary, o: Dictionary) -> Dictionary:
	var hem: float = o.hem
	var spec := {group = o.get("group", "pants"), fold_amplitude = 0.01, keep_apart = ["leg_l", "leg_r"],
		hull = func(p: Vector3) -> Array: return _hull_part(p, L, 13, o.get("leg_fall", 10)),
		subdivide = func(p: Vector3) -> bool: return p.y < L.knee + 0.12 and p.y > L.ankle + 0.02,
		min = func(p, n):
			var top: float = o.get("flare_top", L.knee + 0.05)
			var span: float = o.get("flare_span", L.knee - L.ankle)
			return o.base + o.flare * clampf((top - p.y) / span, 0.0, 1.0),
		max = func(p, n): return o.cover_max if p.y > o.get("cover", INF) - 0.03 else o.get("max", 0.08),
		folds = func(p, n): return _loose_pants_folds(p, L, hem, o.get("cover", INF), o.get("amount", 1.0))}
	if o.has("pin"):
		spec.pin = o.pin
	return spec


## Loose top thickness before draping: sleeves wider toward the cuff and sagging below
## the arm, a skirt flaring below `skirt_from`.
func _loose_top_min(p: Vector3, n: Vector3, L: Dictionary, o: Dictionary) -> float:
	var h: float = o.base
	var ax := absf(p.x)
	if ax > L.shoulder and o.has("sleeve_end"):
		var sleeve_end: float = o.sleeve_end
		var along := clampf((ax - L.shoulder) / (sleeve_end - L.shoulder), 0.0, 1.0)
		var flare_from := minf(L.elbow, sleeve_end - 0.05)
		h += o.get("cuff_flare", 0.0) * clampf((ax - flare_from) / (sleeve_end - flare_from), 0.0, 1.0) \
			+ o.get("sag", 0.0) * maxf(-n.y, 0.0) * along
	elif p.y < o.get("skirt_from", -INF):
		h += o.get("skirt_flare", 0.0) * clampf((o.skirt_from - p.y) / 0.16, 0.0, 1.0)
	return h


## Loose top folds: rings at the elbow and cuff, lengthwise folds down the sleeve, soft
## vertical folds on the body that deepen into blousing over a cinch (`blouse_at`) and
## pleats below `skirt_from`; `amount` scales them all.
func _loose_top_folds(p: Vector3, L: Dictionary, o: Dictionary) -> float:
	const F := 13.0
	var amount: float = o.get("amount", 1.0)
	var ax := absf(p.x)
	if ax > L.shoulder + 0.02:
		var sleeve_end: float = o.get("sleeve_end", L.shoulder)
		var elbow := clampf(1.0 - absf(ax - L.elbow) / 0.08, 0.0, 1.0)
		var cuff := clampf(1.0 - (sleeve_end - ax) / 0.07, 0.0, 1.0)
		var bunched := maxf(elbow, cuff * 0.8)
		var arm := Vector2(L.arm_y, 0.0)
		var rings := ClothDrape.fold_around(p, 0, arm, 0.06, F * 0.35, F * 1.4, 0.009 * bunched * amount)
		return rings + ClothDrape.fold_around(p, 0, arm, 0.06, F, F * 0.3, 0.006 * (1.0 - bunched) * amount, 31.0)
	var blouse: float = o.get("blouse_at", -INF)
	var skirt: float = o.get("skirt_from", -INF)
	var above := 0.0
	var below := 0.0
	if p.y > blouse:
		above = clampf(1.0 - (p.y - blouse) / 0.18, 0.0, 1.0) * clampf((p.y - blouse - 0.012) / 0.03, 0.0, 1.0)
	if p.y < skirt:
		below = clampf((skirt - p.y) / 0.12, 0.0, 1.0) * clampf((skirt - 0.012 - p.y) / 0.03, 0.0, 1.0)
	return ClothDrape.fold_around(p, 1, Vector2.ZERO, 0.15, F * 1.2, F * 0.22, (0.003 + 0.008 * above + 0.011 * below) * amount, 57.0)


## Loose pants folds: rings behind and over the knee, stacked folds at the hem, long
## vertical folds between; none under a top (`cover` and up).
func _loose_pants_folds(p: Vector3, L: Dictionary, hem: float, cover: float, amount: float) -> float:
	const F := 13.0
	if p.y > cover - 0.03:
		return 0.0
	var knee := clampf(1.0 - absf(p.y - L.knee) / 0.09, 0.0, 1.0)
	var ankle := clampf(1.0 - (p.y - hem) / 0.14, 0.0, 1.0)
	var fade := clampf((cover - 0.03 - p.y) / 0.05, 0.0, 1.0)
	var leg := Vector2(0.1 if p.x > 0.0 else -0.1, 0.0)
	var rings := ClothDrape.fold_around(p, 1, leg, 0.08, F * 0.35, F * 1.5, (0.005 * knee + 0.01 * ankle) * amount, 11.0)
	var vertical := ClothDrape.fold_around(p, 1, leg, 0.08, F * 1.1, F * 0.2, 0.007 * (1.0 - maxf(knee, ankle)) * amount, 83.0)
	return fade * (rings + vertical)


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
	_skeleton = skeleton
	_to_skeleton = skeleton.get_bone_global_rest(skeleton.find_bone("pelvis")) * _body_skin.get_bind_pose(_pelvis_bind)
	_tails = []
	var L := _landmarks(skeleton, body_instance.mesh)
	var arrays := body_instance.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var pieces: Array = spec.pieces.call(L)

	var detailed: bool = spec.get("detailed", false)
	var tools: Array[SurfaceTool] = []
	var used: Array[bool] = []
	for i in Slot.size():
		used.append(false)
		var st := SurfaceTool.new()
		st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
	var hidden := PackedByteArray()
	hidden.resize(indices.size() / 3)
	var triangles := 0
	# Draped pieces get twice the skin's resolution where they fold (`drape.subdivide`,
	# a func(p) -> bool at a triangle's middle): every edge of such a triangle is split,
	# for every draped piece alike, so pieces and neighbours agree and nothing cracks.
	var split_edges := {}
	for piece: Dictionary in pieces:
		if not piece.has("drape"):
			continue
		var wants: Callable = piece.drape.get("subdivide", func(_p: Vector3) -> bool: return true)
		var region: Callable = piece.region
		var inside := PackedFloat32Array()
		inside.resize(verts.size())
		for v in verts.size():
			inside[v] = region.call(verts[v], normals[v])
		for t in indices.size() / 3:
			var c := [indices[t * 3], indices[t * 3 + 1], indices[t * 3 + 2]]
			if maxf(inside[c[0]], maxf(inside[c[1]], inside[c[2]])) < 0.0:
				continue
			if not wants.call((verts[c[0]] + verts[c[1]] + verts[c[2]]) / 3.0):
				continue
			for k in 3:
				split_edges[_edge_key(verts[c[k]], verts[c[(k + 1) % 3]])] = true
	var draped_faces: Array = [] # draped pieces' triangles, finished by ClothDrape
	var surface := _Surface.new() # the outfit and body, for hanging the knots' tails on
	for piece_index in pieces.size():
		var piece: Dictionary = pieces[piece_index]
		var draped := piece.has("drape")
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
			var polygons := [polygon]
			if draped:
				var marked := []
				for k in 3:
					marked.append(split_edges.has(_edge_key(verts[corners[k]], verts[corners[(k + 1) % 3]])))
				polygons = ClothDrape.subdivide(polygon, marked, _blend)
			for sub: Array in polygons:
				var clipped := _clip(sub, region, d.min() >= 0.0 and not draped)
				if clipped.size() < 3:
					continue
				var parts := [[clipped, piece.slot]]
				if piece.has("trim"):
					var trim: Callable = piece.trim
					parts = [[_clip(clipped, trim, false), piece.trim_slot],
						[_clip(clipped, func(p, n): return -trim.call(p, n), false), piece.slot]]
				for part: Array in parts:
					var slot: int = part[1]
					var bands := [[part[0], false]]
					if detailed and piece.get("stitches", true):
						bands = _stitch_bands(part[0], piece.get("stitch_region", region), piece.get("stitch_rows", [[STITCH_NEAR, STITCH_FAR]]))
					for band: Array in bands:
						var poly: Array = band[0]
						for i in range(1, poly.size() - 1):
							# Cuts through a vertex leave zero-area slivers; their tangents
							# come out invalid and render as holes.
							var area: float = (poly[i].p - poly[0].p).cross(poly[i + 1].p - poly[0].p).length()
							if area < MIN_TRIANGLE_AREA:
								continue
							var shades := []
							for vertex: Dictionary in [poly[0], poly[i], poly[i + 1]]:
								var shade := 1.0
								if detailed:
									shade = STITCH_SHADE if band[1] else _hem_shade(region.call(vertex.p, vertex.n))
								shades.append(shade)
								if not draped:
									_emit(tools[slot], vertex, piece, Color(shade, shade, shade) if detailed else Color.TRANSPARENT)
							if draped:
								draped_faces.append([[poly[0], poly[i], poly[i + 1]], piece_index, slot, shades])
							used[slot] = true
							triangles += 1
	if not draped_faces.is_empty():
		var cloth := ClothDrape.process(draped_faces, pieces, verts)
		triangles += cloth.size() - draped_faces.size()
		_rig_hems(cloth, pieces)
		for tri: Array in cloth:
			for corner: Dictionary in tri[0]:
				_emit_draped(tools[tri[1]], corner, detailed)
				surface.add(corner.pos)
	for v in verts:
		surface.add(v)
	if spec.has("belt_knot") and spec.belt_knot.get("tied", false):
		triangles += _add_tied_belt(tools[spec.belt_knot.slot], spec.belt_knot, L, surface, detailed)
		used[spec.belt_knot.slot] = true
	elif spec.has("belt_knot"):
		triangles += _add_belt_knot(tools[spec.belt_knot.slot], spec.belt_knot, L, verts, detailed)
		used[spec.belt_knot.slot] = true
	if spec.has("headband_knot"):
		var binds := [_bind_index(skeleton, "Head"), _bind_index(skeleton, "neck_01"), _bind_index(skeleton, "spine_03")]
		triangles += _add_headband_knot(tools[spec.headband_knot.slot], spec.headband_knot, L, surface, binds, detailed)
		used[spec.headband_knot.slot] = true

	var outfit := ArrayMesh.new()
	for slot in Slot.size():
		if not used[slot]:
			continue
		tools[slot].index()
		tools[slot].generate_tangents()
		tools[slot].commit(outfit)
		outfit.surface_set_name(outfit.get_surface_count() - 1, Slot.keys()[slot].to_lower())
	if not _tails.is_empty():
		outfit.set_meta(&"spring_tails", _tails)

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
	if detailed:
		body_arrays[Mesh.ARRAY_TEX_UV2] = uvs # the skin pore detail map tiles over this
	var body := ArrayMesh.new()
	body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, body_arrays)
	body.surface_set_material(0, body_instance.mesh.surface_get_material(0).duplicate())
	body.surface_set_name(0, body_instance.mesh.surface_get_name(0))
	# Facial expressions (blend shapes, an opened mouth and its interior).
	var face := FaceShapes.landmarks(scene)
	body = FaceShapes.build(body, face, FaceShapes.eye_openings(verts, face), true)
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


## Detailed outfits: a garment polygon cut along its stitch lines (`rows`: [near, far]
## distances inside the hem, in order): [[polygon, is_stitch], ...].
func _stitch_bands(polygon: Array, region: Callable, rows: Array) -> Array:
	var cuts := [-INF]
	for row: Array in rows:
		cuts.append_array(row)
	cuts.append(INF)
	var out: Array = []
	for i in cuts.size() - 1:
		var lo: float = cuts[i]
		var hi: float = cuts[i + 1]
		var part := polygon
		if lo > -INF:
			part = _clip(part, func(p, n): return region.call(p, n) - lo)
		if hi < INF:
			part = _clip(part, func(p, n): return hi - region.call(p, n))
		out.append([part, i % 2 == 1])
	return out


## Cloth brightness at `distance` inside a hem (detailed outfits).
func _hem_shade(distance: float) -> float:
	return lerpf(HEM_SHADE, 1.0, clampf(distance / HEM_SHADE_DEPTH, 0.0, 1.0))


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


## `shade` (detailed outfits): the vertex colour; transparent = none.
func _emit(st: SurfaceTool, vertex: Dictionary, piece: Dictionary, shade := Color.TRANSPARENT) -> void:
	var offset: float = piece.offset.call(vertex.n) if piece.offset is Callable else piece.offset
	if piece.get("flat_soles", false) and vertex.n.y < -0.6:
		offset = 0.002 # don't push boot soles into the floor
	if shade.a > 0.0:
		st.set_color(shade)
	st.set_normal(vertex.n)
	st.set_uv(vertex.uv)
	st.set_bones(vertex.bones)
	st.set_weights(vertex.weights)
	st.add_vertex(vertex.p + vertex.n * offset)


## The same key for an edge from either end (positions to 0.5 mm: the base bodies'
## halves aren't merged down the middle).
func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := Vector3i((a * 2000.0).round())
	var kb := Vector3i((b * 2000.0).round())
	return "%s%s" % [ka, kb] if [ka.x, ka.y, ka.z] < [kb.x, kb.y, kb.z] else "%s%s" % [kb, ka]


## A finished corner of draped cloth (ClothDrape.process).
func _emit_draped(st: SurfaceTool, corner: Dictionary, detailed: bool) -> void:
	if detailed:
		st.set_color(Color(corner.shade, corner.shade, corner.shade))
	st.set_normal(corner.normal)
	st.set_uv(corner.uv)
	st.set_bones(corner.bones)
	st.set_weights(corner.weights)
	st.add_vertex(corner.pos)


## Belt knot at the front centre plus two hanging tails, all bound to the pelvis.
func _add_belt_knot(st: SurfaceTool, knot: Dictionary, L: Dictionary, verts: PackedVector3Array, detailed: bool) -> int:
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
				if detailed:
					st.set_color(Color.WHITE) # no hem shading on the knot
				st.set_normal(basis * normal)
				st.set_uv(Vector2(0.5, 0.5))
				st.set_bones(PackedInt32Array([_pelvis_bind, 0, 0, 0]))
				st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
				st.add_vertex(center + basis * ((normal + (quad[i] as Vector3)) * half))
			triangles += 2
	return triangles


## A belt tied at the front: a rounded square knot and two tails that hang over the
## jacket's skirt, spreading and twisting a little, all bound to the pelvis.
func _add_tied_belt(st: SurfaceTool, knot: Dictionary, L: Dictionary, surface: _Surface, detailed: bool) -> int:
	var y: float = L.hip + knot.y
	var z: float = surface.front(0.0, y) + 0.004
	var pelvis := func(_t: float) -> Array:
		return [PackedInt32Array([_pelvis_bind, 0, 0, 0]), PackedFloat32Array([1.0, 0.0, 0.0, 0.0])]
	var triangles := _rounded_box(st, Vector3(0.0, y, z + 0.012), Vector3(0.03, 0.021, 0.013), Basis(Vector3.BACK, 0.12),
		pelvis, detailed)
	for side in [-1.0, 1.0]:
		var path: Array[Vector3] = []
		var widths: Array[float] = []
		var length := 0.2 if side < 0.0 else 0.22
		for i in 11:
			var t := i / 10.0
			var x: float = side * (0.01 + 0.032 * t)
			var tail_y := y - 0.012 - length * t
			path.append(Vector3(x, tail_y, maxf(z + 0.006 - 0.004 * t, surface.front(x, tail_y) + 0.007)))
			widths.append(0.019 - 0.002 * t)
		triangles += _strip(st, path, widths, 0.005, side * 0.25, _tail_chain(path, "pelvis", pelvis), detailed)
	return triangles


## A headband tied at the back of the head: a small knot and two tails that hang down
## the back of the neck. They follow the head at the knot and the upper back at their
## ends (`binds`: head, neck, upper spine).
func _add_headband_knot(st: SurfaceTool, knot: Dictionary, L: Dictionary, surface: _Surface, binds: Array, detailed: bool) -> int:
	var y: float = L.head_top - knot.y
	var z: float = surface.back(0.0, y) - knot.offset
	var skin := func(t: float) -> Array:
		var head := clampf(1.0 - t * 1.6, 0.0, 1.0)
		var spine := clampf((t - 0.45) * 1.6, 0.0, 1.0)
		var neck := maxf(1.0 - head - spine, 0.0)
		return [PackedInt32Array([binds[0], binds[1], binds[2], 0]), PackedFloat32Array([head, neck, spine, 0.0])]
	var triangles := _rounded_box(st, Vector3(0.0, y, z - 0.007), Vector3(0.017, 0.014, 0.009), Basis(Vector3.BACK, -0.2),
		skin, detailed)
	for side in [-1.0, 1.0]:
		var path: Array[Vector3] = []
		var widths: Array[float] = []
		var length := 0.24 if side < 0.0 else 0.2
		for i in 13:
			var t := i / 12.0
			var x: float = side * (0.008 + 0.035 * t)
			var tail_y := y - 0.01 - length * t
			# Straight down from the knot, unless the back of the neck or the jacket's
			# collar stands out further.
			path.append(Vector3(x, tail_y, minf(z - 0.01, surface.back(x, tail_y) - 0.006)))
			widths.append(0.013 - 0.002 * t)
		var head := func(_t: float) -> Array:
			return [PackedInt32Array([binds[0], 0, 0, 0]), PackedFloat32Array([1.0, 0.0, 0.0, 0.0])]
		triangles += _strip(st, path, widths, 0.003, side * 0.35, _tail_chain(path, "Head", head), detailed)
	return triangles


## Rigs a tail hanging along `path` (points evenly spaced along it) for spring motion:
## `TAIL_JOINTS` bones from the knot down, under `parent` (`_add_chain`). Returns the
## strip's skin: the bones' weights blend over each joint, and near the knot the knot's own
## skin (`knot_skin`) still holds it.
func _tail_chain(path: Array[Vector3], parent: String, knot_skin: Callable) -> Callable:
	var base := _add_chain(path, parent, TAIL_JOINTS, Vector3.BACK, {})
	return func(t: float) -> Array:
		var held := clampf(1.0 - t / TAIL_ROOT_FADE, 0.0, 1.0)
		var knot: Array = knot_skin.call(t)
		var joint := _chain_joints(t, TAIL_JOINTS)
		return [PackedInt32Array([knot[0][0], base + joint[0], base + joint[1], 0]),
			PackedFloat32Array([held, (1.0 - held) * (1.0 - joint[2]), (1.0 - held) * joint[2], 0.0])]


## Adds a chain of `count` spring bones along `path` (mesh space, from the root) under
## `parent`, each with +Y down the chain and +Z toward `outward`, to `_tails` with their
## rests and skin binds (appended after the body skin's binds, which FighterModel copies
## and extends) plus the `extra` fields. Returns the first joint's bind index.
func _add_chain(path: Array[Vector3], parent: String, count: int, outward: Vector3, extra: Dictionary) -> int:
	var at := func(t: float) -> Vector3:
		var f := t * (path.size() - 1)
		var i := mini(floori(f), path.size() - 2)
		return path[i].lerp(path[i + 1], f - i)
	var base := _body_skin.get_bind_count()
	for chain: Dictionary in _tails:
		base += chain.joints.size()
	var parent_rest := _skeleton.get_bone_global_rest(_skeleton.find_bone(parent))
	var joints: Array = []
	var length := 0.0
	for k in count:
		var from := _to_skeleton * (at.call(float(k) / count) as Vector3)
		var to := _to_skeleton * (at.call(float(k + 1) / count) as Vector3)
		var down := (to - from).normalized()
		var across := down.cross(_to_skeleton.basis * outward).normalized()
		var rest := Transform3D(Basis(across, down, across.cross(down)), from)
		joints.append({name = "%s%d" % [TAIL_PREFIX, base - _body_skin.get_bind_count() + k],
			rest = parent_rest.affine_inverse() * rest, bind = rest.affine_inverse() * _to_skeleton})
		parent_rest = rest
		length = from.distance_to(to)
	var chain := {parent = parent, joints = joints, length = length}
	chain.merge(extra)
	_tails.append(chain)
	return base


## Where `t` (0..1 down a chain of `count` joints) falls: [joint, next joint, blend
## toward the next]; joint k's segment is centred on k.
func _chain_joints(t: float, count: int) -> Array:
	var s := t * count - 0.5
	var k0 := clampi(floori(s), 0, count - 1)
	var k1 := mini(k0 + 1, count - 1)
	return [k0, k1, clampf(s - k0, 0.0, 1.0) if k1 != k0 else 0.0]


## Loose hems (a piece's `hem`: top, bottom, chains, joints, optional `legs` and `share`):
## a ring of spring chains hanging from `top` to `bottom` around the pelvis (a jacket's
## skirt) or around each thigh (`legs`: shorts), each on the cloth's outer surface at its
## angle, and the piece's cloth below `top` reweighted onto the two nearest chains, more
## the further down it is (fully from `HEM_FULL_AT` of the way down, times `share`; the
## rest keeps the cloth's own weights, so the hem still follows the legs).
func _rig_hems(cloth: Array, pieces: Array) -> void:
	var to_mesh := _to_skeleton.affine_inverse()
	var rest := func(bone: String) -> Vector3: return to_mesh * _skeleton.get_bone_global_rest(_skeleton.find_bone(bone)).origin
	for piece_index in pieces.size():
		var hem: Dictionary = (pieces[piece_index] as Dictionary).get("hem", {})
		if hem.is_empty():
			continue
		var top: float = hem.top
		var bottom: float = hem.bottom
		var count: int = hem.chains
		var corners: Array = []
		for tri: Array in cloth:
			if tri[2] == piece_index:
				corners.append_array(tri[0])
		# Rings: [parent bone, axis func(y) -> Vector2 (x, z), side (sign of x, 0 = both)].
		var rings: Array = []
		if hem.get("legs", false):
			for side in ["l", "r"]:
				var hip: Vector3 = rest.call("thigh_" + side)
				var knee: Vector3 = rest.call("calf_" + side)
				var axis := func(y: float) -> Vector2:
					var p := hip.lerp(knee, (hip.y - y) / (hip.y - knee.y))
					return Vector2(p.x, p.z)
				rings.append(["thigh_" + side, axis, signf(hip.x)])
		else:
			var pelvis: Vector3 = rest.call("pelvis")
			rings.append(["pelvis", func(_y: float) -> Vector2: return Vector2(pelvis.x, pelvis.z), 0.0])
		var step := TAU / count
		var bases: Array = []
		for ring: Array in rings:
			var axis: Callable = ring[1]
			var mine := corners.filter(func(c: Dictionary) -> bool: return ring[2] == 0.0 or signf(c.pos.x) == ring[2])
			var ring_bases: Array = []
			for k in count:
				var angle := step * (k + 0.5)
				var out := Vector3(sin(angle), 0.0, cos(angle))
				var path: Array[Vector3] = []
				var radius := 0.0
				for i in 5:
					var y := lerpf(top, bottom, i / 4.0)
					var center: Vector2 = axis.call(y)
					var outer := 0.0
					for c: Dictionary in mine:
						var d := Vector2(c.pos.x, c.pos.z) - center
						if absf(c.pos.y - y) < 0.015 and absf(angle_difference(atan2(d.x, d.y), angle)) < step * 0.5:
							outer = maxf(outer, d.length())
					if outer > 0.0:
						radius = outer
					path.append(Vector3(center.x + out.x * radius, y, center.y + out.z * radius))
				ring_bases.append(_add_chain(path, ring[0], hem.joints, out, {kind = &"hem", plane = ring[0]}))
			bases.append(ring_bases)
		# Every corner's new weights first: corners can be shared between triangles.
		var skins: Array = []
		for c: Dictionary in corners:
			var r := 0
			if rings.size() > 1 and signf(c.pos.x) != rings[0][2]:
				r = 1
			var d := Vector2(c.pos.x, c.pos.z) - ((rings[r][1] as Callable).call(c.pos.y) as Vector2)
			var u := fposmod(atan2(d.x, d.y) / step - 0.5, count)
			var a := floori(u) % count
			var b := (a + 1) % count
			var f := u - floorf(u)
			var t := clampf((top - c.pos.y) / (top - bottom), 0.0, 1.0)
			var share := smoothstep(0.0, HEM_FULL_AT, t) * float(hem.get("share", 1.0))
			var joint := _chain_joints(t, hem.joints)
			var map := {}
			for i in 4:
				if c.weights[i] > 0.0:
					map[c.bones[i]] = map.get(c.bones[i], 0.0) + c.weights[i] * (1.0 - share)
			for chain: Array in [[bases[r][a], 1.0 - f], [bases[r][b], f]]:
				for j in 2:
					var w: float = share * chain[1] * (1.0 - joint[2] if j == 0 else joint[2])
					if w > 0.0:
						map[chain[0] + joint[j]] = map.get(chain[0] + joint[j], 0.0) + w
			var order := map.keys()
			order.sort_custom(func(x: int, y: int) -> bool: return map[x] > map[y])
			var bones := PackedInt32Array()
			var weights := PackedFloat32Array()
			var total := 0.0
			for i in 4:
				bones.append(order[i] if i < order.size() else 0)
				weights.append(map[order[i]] if i < order.size() else 0.0)
				total += weights[i]
			for i in 4:
				weights[i] /= maxf(total, 0.0001)
			skins.append([bones, weights])
		for i in corners.size():
			corners[i].bones = skins[i][0]
			corners[i].weights = skins[i][1]


## A flat strip (a belt or headband tail) along `path`, `widths` half wide, `thickness`
## thick, its width turning by `twist` radians from start to end. `skin` gives
## [bones, weights] along it (0..1).
func _strip(st: SurfaceTool, path: Array[Vector3], widths: Array[float], thickness: float, twist: float,
		skin: Callable, detailed: bool) -> int:
	var rings: Array = [] # per point: four corners, then the facing and across directions
	for i in path.size():
		var tangent := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var facing := (Vector3.BACK - tangent * tangent.dot(Vector3.BACK)).normalized()
		facing = facing.rotated(tangent, twist * i / (path.size() - 1.0))
		var across := tangent.cross(facing).normalized()
		var w := across * widths[i]
		var h := facing * thickness * 0.5
		rings.append([path[i] - w + h, path[i] + w + h, path[i] + w - h, path[i] - w - h, facing, across])
	var triangles := 0
	for i in path.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var ta := float(i) / (path.size() - 1)
		var tb := float(i + 1) / (path.size() - 1)
		for k in 4:
			var normal: Vector3 = [a[4], a[5], -a[4], -a[5]][k]
			triangles += _quad(st, [a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]], normal, [ta, ta, tb, tb], skin, detailed)
	for end in [0, path.size() - 1]:
		var r: Array = rings[end]
		var t := float(end) / (path.size() - 1)
		var outward := (path[end] - path[1 if end == 0 else end - 1]).normalized()
		triangles += _quad(st, [r[0], r[1], r[2], r[3]], outward, [t, t, t, t], skin, detailed)
	return triangles


## A box with rounded edges (a knot): a subdivided cube pushed toward a sphere.
func _rounded_box(st: SurfaceTool, center: Vector3, half: Vector3, basis: Basis, skin: Callable, detailed: bool) -> int:
	const STEPS := 4
	var triangles := 0
	for face in 6:
		var axis := face / 2
		var sign := 1.0 if face % 2 == 0 else -1.0
		var u := Vector3.ZERO
		u[(axis + 1) % 3] = 1.0
		var v := Vector3.ZERO
		v[(axis + 2) % 3] = 1.0
		var normal_axis := Vector3.ZERO
		normal_axis[axis] = sign
		for i in STEPS:
			for j in STEPS:
				var corners := []
				for c: Array in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
					var q: Vector3 = normal_axis + u * (c[0] * 2.0 / STEPS - 1.0) + v * (c[1] * 2.0 / STEPS - 1.0)
					var rounded := q.lerp(q.normalized() * 1.25, 0.55).clamp(-Vector3.ONE, Vector3.ONE)
					corners.append(center + basis * (rounded * half))
				var mid: Vector3 = normal_axis + u * ((i + 0.5) * 2.0 / STEPS - 1.0) + v * ((j + 0.5) * 2.0 / STEPS - 1.0)
				triangles += _quad(st, corners, basis * (mid / half).normalized(), [0.0, 0.0, 0.0, 0.0], skin, detailed)
	return triangles


## One quad facing `normal`; `at` is each corner's position along the piece, for `skin`.
func _quad(st: SurfaceTool, corners: Array, normal: Vector3, at: Array, skin: Callable, detailed: bool) -> int:
	var order := [0, 1, 2, 0, 2, 3]
	var a: Vector3 = corners[0]
	# Wound like the body's triangles (Godot's front faces are clockwise: the cross
	# product points into the surface).
	if (corners[1] - a).cross(corners[2] - a).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k: int in order:
		var influence: Array = skin.call(at[k])
		if detailed:
			st.set_color(Color.WHITE)
		st.set_normal(normal.normalized())
		st.set_uv(Vector2(0.5, 0.5))
		st.set_bones(influence[0])
		st.set_weights(influence[1])
		st.add_vertex(corners[k])
	return 2


## The outfit and body surfaces, for hanging things on: the furthest-out point near a
## spot, at the front (+Z) or the back.
class _Surface:
	const CELL := 0.012
	var front_z := {}
	var back_z := {}


	func add(p: Vector3) -> void:
		var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
		front_z[key] = maxf(front_z.get(key, -INF), p.z)
		back_z[key] = minf(back_z.get(key, INF), p.z)


	func front(x: float, y: float) -> float:
		var best := -INF
		for key: Vector2i in _around(x, y):
			best = maxf(best, front_z.get(key, -INF))
		return best


	func back(x: float, y: float) -> float:
		var best := INF
		for key: Vector2i in _around(x, y):
			best = minf(best, back_z.get(key, INF))
		return best


	func _around(x: float, y: float) -> Array:
		var center := Vector2i(floori(x / CELL), floori(y / CELL))
		var keys := []
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				keys.append(center + Vector2i(dx, dy))
		return keys


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
