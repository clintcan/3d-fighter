## Builds Aelia's fighter model (assets/characters/aelia/aelia.scn) from the export of
## tools/aelia_blender.py (assets/characters/aelia/source/aelia.gltf).
##
##   godot_console --headless --path . -s res://tools/build_aelia.gd -- --dump-rest <file.json>
##       writes the game skeleton's rest joints (input for aelia_blender.py)
##   godot_console --headless --path . -s res://tools/build_aelia.gd
##       builds the scene
##
## The animations set every bone's rotation (and the pelvis position), not bone lengths, so a
## skeleton with the game skeleton's rest orientations works with any proportions. The scene
## gets a copy of the game skeleton whose joints are moved to hers (from the export) without
## changing a single rest rotation, and new skin binds so her mesh stays where it is at rest.
extends SceneTree

const BASE := "res://assets/characters/base/Superhero_Female_FullBody.gltf"
const SOURCE := "res://assets/characters/aelia/source/aelia.gltf"
const OUTPUT := "res://assets/characters/aelia/aelia.scn"
## Surface looks by material name: the export's plain glossy colours read as plastic, so
## the armour becomes satin painted metal. [albedo or null, metallic, roughness, specular]
const LOOKS := {
	"Aelia_Armour": [Color(0.17, 0.38, 0.16), 0.75, 0.5, 0.5],
	"Aelia_Gold": [Color(0.78, 0.58, 0.2), 0.9, 0.38, 0.5],
	"Aelia_Rivets": [Color(0.42, 0.42, 0.4), 0.85, 0.42, 0.5],
	"Aelia_Chainmail": [null, 0.8, 0.45, 0.5],
	"Aelia_Leather": [null, 0.0, 0.72, 0.25],
	"Aelia_Bandage": [Color(0.82, 0.8, 0.76), 0.0, 0.9, 0.2],
	"MI_Hair_Aelia": [null, 0.0, 0.6, 0.4],
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--dump-rest":
		_dump_rest(args[1])
	else:
		_build()
	quit()


func _base_skeleton() -> Array:
	var base: Node = load(BASE).instantiate()
	return [base, base.find_child("Skeleton3D") as Skeleton3D]


func _dump_rest(path: String) -> void:
	var pair := _base_skeleton()
	var sk: Skeleton3D = pair[1]
	var out := {}
	for b in sk.get_bone_count():
		var o := sk.get_bone_global_rest(b).origin
		out[sk.get_bone_name(b)] = [o.x, o.y, o.z, sk.get_bone_parent(b), b]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
	pair[0].free()
	print("wrote ", path)


func _build() -> void:
	var pair := _base_skeleton()
	var base_sk: Skeleton3D = pair[1]
	var source: Node = load(SOURCE).instantiate()
	var src_sk := source.find_child("Skeleton3D") as Skeleton3D

	# Same bones, names, parents and rest rotations as the game skeleton; her joint positions.
	var root := Node3D.new()
	root.name = "Aelia"
	var armature := Node3D.new()
	armature.name = "Armature" # the clips' tracks address Armature/Skeleton3D:<bone>
	root.add_child(armature)
	armature.owner = root
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	armature.add_child(sk)
	sk.owner = root
	var globals: Array[Transform3D] = []
	for b in base_sk.get_bone_count():
		var bone_name := base_sk.get_bone_name(b)
		var src_bone := src_sk.find_bone(bone_name)
		assert(src_bone >= 0, "missing bone in the export: %s" % bone_name)
		var global := Transform3D(base_sk.get_bone_global_rest(b).basis, src_sk.get_bone_global_rest(src_bone).origin)
		globals.append(global)
		sk.add_bone(bone_name)
		var parent := base_sk.get_bone_parent(b)
		sk.set_bone_parent(b, parent)
		var local := global if parent < 0 else globals[parent].affine_inverse() * global
		sk.set_bone_rest(b, local)
	sk.reset_bone_poses()
	for b in sk.get_bone_count():
		assert(sk.get_bone_rest(b).basis.is_equal_approx(base_sk.get_bone_rest(b).basis),
			"rest rotation changed: %s" % sk.get_bone_name(b))

	var triangles := 0
	for src_mesh: MeshInstance3D in src_sk.find_children("*", "MeshInstance3D", true, false):
		var mesh := src_mesh.mesh.duplicate() as ArrayMesh
		for s in mesh.get_surface_count():
			var material := mesh.surface_get_material(s) as StandardMaterial3D
			if material:
				material = material.duplicate()
				var look: Array = LOOKS.get(material.resource_name, [])
				if not look.is_empty():
					if look[0] != null:
						material.albedo_color = look[0]
					material.metallic = look[1]
					material.roughness = look[2]
					material.metallic_specular = look[3]
				mesh.surface_set_material(s, material)
			triangles += mesh.surface_get_array_index_len(s) / 3
		# Vertex space -> skeleton space at rest, from the export's own skin.
		var src_skin := src_mesh.skin
		var skin := Skin.new()
		for i in src_skin.get_bind_count():
			var bone_name := src_skin.get_bind_name(i)
			if bone_name == &"":
				bone_name = src_sk.get_bone_name(src_skin.get_bind_bone(i))
			var to_skeleton := src_sk.get_bone_global_rest(src_sk.find_bone(bone_name)) * src_skin.get_bind_pose(i)
			skin.add_named_bind(bone_name, globals[sk.find_bone(bone_name)].affine_inverse() * to_skeleton)
		var mi := MeshInstance3D.new()
		mi.name = src_mesh.name
		mi.mesh = mesh
		mi.skin = skin
		sk.add_child(mi)
		mi.owner = root
		mi.skeleton = mi.get_path_to(sk)
		print("mesh %s: %d surfaces, %d binds" % [mi.name, mesh.get_surface_count(), skin.get_bind_count()])

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	print("saved %s (%d triangles), error %d" % [OUTPUT, triangles, err])
	root.free()
	source.free()
	pair[0].free()
