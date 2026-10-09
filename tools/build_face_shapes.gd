extends SceneTree
## Bakes the facial expression blend shapes (tools/face_shapes.gd) into the pieces that sit
## on a fighter's face: the eyebrow and lash meshes of the base models and the eyebrow
## and beard pieces in CharacterData.hair_scenes, and the gaze shapes into the eyeballs
## (FaceShapes.build_eyes). FighterModel swaps these copies in by path
## (FighterModel.face_piece_path). The bodies get theirs from build_outfits.gd.
## Run: godot_console --headless --path . -s res://tools/build_face_shapes.gd

const CHARACTER_DIR := "res://data/characters/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FighterModel.FACE_DIR))
	var done := {}
	for file in ResourceLoader.list_directory(CHARACTER_DIR):
		if not file.ends_with(".tres"):
			continue
		var data := load(CHARACTER_DIR + file) as CharacterData
		var base_path := data.model_scene.resource_path
		var base := data.model_scene.instantiate()
		var face := FaceShapes.landmarks(base)
		var openings: Array
		for mi: MeshInstance3D in base.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh.surface_get_material(0).resource_name.begins_with("MI_Superhero"):
				openings = FaceShapes.eye_openings(mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], face)
		var sources: Array[PackedScene] = [data.model_scene]
		sources.append_array(data.hair_scenes)
		for source in sources:
			var scene := base if source == data.model_scene else source.instantiate()
			for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
				var path := FighterModel.face_piece_path(base_path, source.resource_path, mi.name)
				var eyes := _is_eyes(mi.mesh)
				if done.has(path) or not (eyes or _on_face(mi.mesh, face)):
					continue
				done[path] = true
				var mesh := FaceShapes.build_eyes(mi.mesh as ArrayMesh) if eyes \
					else FaceShapes.build(mi.mesh as ArrayMesh, face, openings, false)
				ResourceSaver.save(mesh, path)
				print("%-7s %s" % [data.id, path])
			if scene != base:
				scene.free()
		base.free()
	quit()


## The eyeballs get the gaze shapes instead.
static func _is_eyes(mesh: Mesh) -> bool:
	var material := mesh.surface_get_material(0)
	return material != null and material.resource_name.begins_with("MI_Eyes")


## Hair pieces close around the eyes and mouth: eyebrows, lashes, beards. Not the scalp hair.
static func _on_face(mesh: Mesh, face: Dictionary) -> bool:
	var material := mesh.surface_get_material(0)
	if material == null or not material.resource_name.begins_with("MI_Hair"):
		return false
	var box := mesh.get_aabb()
	var eye: Vector3 = face.eye
	return box.size.y < 0.16 and box.get_center().y < eye.y + 0.04 and box.end.z > eye.z
