extends SceneTree
## Rigs the hanging part of the hair pieces for spring motion (FighterModel._add_hair_springs).
## Run: godot_console --headless --path . -s res://tools/build_hair_motion.gd
##
## The Quaternius hair is bound to the Head bone only. This adds a ring of `CHAINS` spring
## bones round the head at `top` (temple height), each hanging down to where the hair ends
## in its sector, and moves the weight of every vertex below `top` from the Head onto the
## two nearest chains: none at `top`, all of it by halfway down, so the crown stays put and
## the ends swing. Fringes shorter than `MIN_LENGTH` keep their Head weight.
## Writes assets/characters/hair/motion/<piece>.scn: the piece with the new weights and a
## skin with the extra binds; its MeshInstance3D carries the chains in its "spring_chains"
## meta ([{name, rest (relative to the Head bone), length}]). FighterModel uses it in place
## of the original piece and adds the bones.

const BODY := "res://assets/characters/base/Superhero_Female_FullBody.gltf"
const HAIR_DIR := "res://assets/characters/hair/"
const OUT_DIR := "res://assets/characters/hair/motion/"
const STYLES := {
	"Hair_Long.gltf": {top = 1.66}, # Valka: hangs to the jaw at the sides and back
	"Hair_Bob.tscn": {top = 1.64}, # Mira
	"Hair_Buns.gltf": {top = 1.64}, # Rhea: the strands framing her face
}
const CHAINS := 8
const AXIS := Vector2(0.0, -0.01) # x, z of the head's vertical axis (T-pose)
const MIN_LENGTH := 0.04
const FULL_AT := 0.5 # share of the chain's length where a vertex follows it completely
const ROOT_INSET := 0.85 # the chain's root sits this share of the way out to the hair's surface
const BONE_PREFIX := "hair_spring_"


func _initialize() -> void:
	var body := (load(BODY) as PackedScene).instantiate()
	var skeleton := body.find_child("Skeleton3D") as Skeleton3D
	var head_rest := skeleton.get_bone_global_rest(skeleton.find_bone("Head"))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for file: String in STYLES:
		_build(file, STYLES[file], head_rest)
	body.free()
	quit()


func _build(file: String, style: Dictionary, head_rest: Transform3D) -> void:
	var source := (load(HAIR_DIR + file) as PackedScene).instantiate()
	var mi := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var head_bind := -1
	for i in mi.skin.get_bind_count():
		if mi.skin.get_bind_name(i) == &"Head":
			head_bind = i
	var to_skeleton := head_rest * mi.skin.get_bind_pose(head_bind) # mesh space -> skeleton rest
	var top: float = style.top

	# Where the hair ends, and how far out it reaches at `top`, in each sector.
	var bottom := PackedFloat32Array()
	var reach := PackedFloat32Array()
	bottom.resize(CHAINS)
	bottom.fill(top)
	reach.resize(CHAINS)
	for surface in mi.mesh.get_surface_count():
		for v: Vector3 in mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var s := to_skeleton * v
			var k := posmod(roundi(_angle(s) / TAU * CHAINS), CHAINS)
			bottom[k] = minf(bottom[k], s.y)
			if absf(s.y - top) < 0.015:
				reach[k] = maxf(reach[k], Vector2(s.x - AXIS.x, s.z - AXIS.y).length())

	var chains: Array[Dictionary] = []
	var lengths := PackedFloat32Array()
	var skin := mi.skin.duplicate() as Skin
	var binds := PackedInt32Array() # per sector: its skin bind, or -1 for no chain
	for k in CHAINS:
		var length := top - bottom[k]
		lengths.append(length)
		if length < MIN_LENGTH:
			binds.append(-1)
			continue
		var angle := TAU * k / CHAINS
		var root := Vector3(AXIS.x + sin(angle) * reach[k] * ROOT_INSET, top, AXIS.y + cos(angle) * reach[k] * ROOT_INSET)
		# The bone's +Y points down the hair (the simulator's chain direction).
		var rest := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)), root)
		var bone_name := "%s%d" % [BONE_PREFIX, k]
		chains.append({name = bone_name, rest = head_rest.affine_inverse() * rest, length = length})
		binds.append(skin.get_bind_count())
		skin.add_named_bind(bone_name, rest.affine_inverse() * to_skeleton)

	var mesh := ArrayMesh.new()
	for surface in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(verts.size() * 4)
		weights.resize(verts.size() * 4)
		for i in verts.size():
			var s := to_skeleton * verts[i]
			var sector := _angle(s) / TAU * CHAINS
			var k0 := posmod(floori(sector), CHAINS)
			var k1 := (k0 + 1) % CHAINS
			var t := sector - floorf(sector)
			var share := [1.0 - t, t]
			var moving := 0.0
			var slot := 1
			bones[i * 4] = head_bind
			for j in 2:
				var k: int = [k0, k1][j]
				if binds[k] < 0:
					continue
				var w := clampf((top - s.y) / lengths[k] / FULL_AT, 0.0, 1.0)
				w = w * w * (3.0 - 2.0 * w) * share[j]
				bones[i * 4 + slot] = binds[k]
				weights[i * 4 + slot] = w
				moving += w
				slot += 1
			weights[i * 4] = 1.0 - moving
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surface, mi.mesh.surface_get_material(surface))
		mesh.surface_set_name(surface, mi.mesh.surface_get_name(surface))

	var root_node := Node3D.new()
	root_node.name = file.get_basename()
	var piece := MeshInstance3D.new()
	piece.name = mi.name
	piece.mesh = mesh
	piece.skin = skin
	piece.set_meta(&"spring_chains", chains)
	root_node.add_child(piece)
	piece.owner = root_node
	var scene := PackedScene.new()
	scene.pack(root_node)
	var out := OUT_DIR + file.get_basename() + ".scn"
	var err := ResourceSaver.save(scene, out)
	print("%s: %d chains, lengths %s, err=%d" % [out, chains.size(), Array(lengths).map(func(x: float) -> float: return snappedf(x, 0.001)), err])
	root_node.free()
	source.free()


## Angle round the head's axis, 0 at the face (+Z), growing toward +X.
static func _angle(s: Vector3) -> float:
	return fposmod(atan2(s.x - AXIS.x, s.z - AXIS.y), TAU)
