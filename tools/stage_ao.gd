class_name StageAO
## Baked contact shadows for the stage builders (tools/build_*_stage.gd).
##
## A builder records everything that stands on a floor (add_box for merged geometry,
## collect for separate meshes); bake() rasterises their footprints into a height map and
## computes horizon-based ambient occlusion: for each texel, the highest horizon in
## DIRECTIONS directions out to the last of STEPS. Four rotated direction sets are picked
## per texel and the result is blurred, so thin poles leave soft blobs instead of spokes.
## overlay() turns the result into a flat quad just above the floor that multiplies the
## floor's colour, so a stage's own floor materials stay untouched. All of it is baked when
## the stage is built: nothing runs while playing.

const DIRECTIONS := 16
const STEPS := [0.08, 0.16, 0.28, 0.45, 0.7, 1.0, 1.4, 1.9, 2.5] # metres
const STRENGTH := 1.35
const BLUR_PASSES := 4
const MIN_HEIGHT := 0.06 # shorter things (paint, seams, mats) cast no shadow
const MAX_BASE := 0.3 # things whose bottom is higher than this above the floor don't touch it


## Records a box (merged geometry: size and transform as given to the batch) if it
## stands on the floor at `floor_y`. Footprints are [x0, z0, x1, z1, height above floor].
static func add_box(footprints: Array, xform: Transform3D, size: Vector3, floor_y: float) -> void:
	add_aabb(footprints, xform * AABB(-size * 0.5, size), floor_y)


static func add_aabb(footprints: Array, bounds: AABB, floor_y: float) -> void:
	if bounds.position.y - floor_y < MAX_BASE and bounds.end.y - floor_y > MIN_HEIGHT:
		footprints.append([bounds.position.x, bounds.position.z, bounds.end.x, bounds.end.z, bounds.end.y - floor_y])


## Records every separate MeshInstance3D under `root` (built nodes aren't in the scene
## tree yet, so transforms are chained by hand). Skips nodes named in `skip`.
static func collect(footprints: Array, root: Node3D, floor_y: float, skip: Array = []) -> void:
	_collect(footprints, root, Transform3D(), floor_y, skip)


static func _collect(footprints: Array, node: Node, parent: Transform3D, floor_y: float, skip: Array) -> void:
	if String(node.name) in skip:
		return
	var xform := parent
	if node is Node3D:
		xform = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		add_aabb(footprints, xform * (node as MeshInstance3D).mesh.get_aabb(), floor_y)
	for child in node.get_children():
		_collect(footprints, child, xform, floor_y, skip)


## Ambient occlusion over the rectangle `center` ± `half` (X/Z), `size` texels on its
## longer side. Returns an L8 image: 255 = open, darker = occluded.
static func bake(footprints: Array, center: Vector2, half: Vector2, size: int) -> Image:
	var cell := maxf(half.x, half.y) * 2.0 / size
	var width := maxi(2, roundi(half.x * 2.0 / cell))
	var depth := maxi(2, roundi(half.y * 2.0 / cell))
	var origin := center - half
	var heights := PackedFloat32Array()
	heights.resize(width * depth)
	for f: Array in footprints:
		var x0 := clampi(int((f[0] - origin.x) / cell), 0, width - 1)
		var x1 := clampi(int((f[2] - origin.x) / cell), 0, width - 1)
		var z0 := clampi(int((f[1] - origin.y) / cell), 0, depth - 1)
		var z1 := clampi(int((f[3] - origin.y) / cell), 0, depth - 1)
		if f[2] < origin.x or f[0] > origin.x + half.x * 2.0 or f[3] < origin.y or f[1] > origin.y + half.y * 2.0:
			continue # outside the baked area
		if f[0] <= origin.x and f[2] >= origin.x + half.x * 2.0 and f[1] <= origin.y and f[3] >= origin.y + half.y * 2.0:
			continue # encloses the whole area (a distant ring of mountains): its box isn't solid
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				heights[z * width + x] = maxf(heights[z * width + x], f[4])
	var rotations := []
	for r in 4:
		var offsets := [] # per direction: [dx, dz, distance], per step
		for d in DIRECTIONS:
			var a := TAU * (d + r * 0.25) / DIRECTIONS
			var steps := []
			for dist: float in STEPS:
				steps.append([roundi(cos(a) * dist / cell), roundi(sin(a) * dist / cell), dist])
			offsets.append(steps)
		rotations.append(offsets)
	var ao := PackedFloat32Array()
	ao.resize(width * depth)
	for z in depth:
		for x in width:
			var h0 := heights[z * width + x]
			var occlusion := 0.0
			for steps: Array in rotations[(x * 3 + z * 5) % 4]:
				var horizon := 0.0
				for step: Array in steps:
					var xi: int = x + step[0]
					var zi: int = z + step[1]
					if xi < 0 or zi < 0 or xi >= width or zi >= depth:
						continue
					var rise := heights[zi * width + xi] - h0
					if rise > 0.0:
						horizon = maxf(horizon, rise / sqrt(rise * rise + step[2] * step[2]))
				occlusion += horizon
			ao[z * width + x] = clampf(1.0 - occlusion / DIRECTIONS * STRENGTH, 0.2, 1.0)
	for pass_index in BLUR_PASSES:
		var blurred := ao.duplicate()
		for z in range(1, depth - 1):
			for x in range(1, width - 1):
				var sum := 0.0
				for dz in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						sum += ao[(z + dz) * width + x + dx]
				blurred[z * width + x] = sum / 9.0
		ao = blurred
	var bytes := PackedByteArray()
	bytes.resize(width * depth)
	for i in ao.size():
		bytes[i] = int(ao[i] * 255.0)
	return Image.create_from_data(width, depth, false, Image.FORMAT_L8, bytes)


## Saves `image` to `path` (a .res texture) and returns it loaded.
static func save(image: Image, path: String) -> Texture2D:
	ResourceSaver.save(ImageTexture.create_from_image(image), path)
	return load(path)


## A quad just above the floor that multiplies the floor's colour by the baked AO.
static func overlay(texture: Texture2D, center: Vector2, half: Vector2, floor_y: float) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = half * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	material.albedo_texture = texture
	material.texture_repeat = false
	material.disable_fog = true
	material.disable_receive_shadows = true
	plane.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	mesh.position = Vector3(center.x, floor_y + 0.003, center.y)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh
