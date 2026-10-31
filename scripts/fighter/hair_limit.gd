class_name HairLimit
extends SkeletonModifier3D
## Runs after the hair's SpringBoneSimulator3D and keeps each spring bone within
## `max_angle` of its place on the head. A fast head move (a punch, a hit reaction, a clip
## that starts in another pose) would otherwise leave the hair trailing so far that it
## flicks through the skull for a few frames. Cosmetic only.

var bones := PackedInt32Array()
var max_angle := deg_to_rad(45.0)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for bone in bones:
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var pose := skeleton.get_bone_pose_rotation(bone)
		var angle := rest.angle_to(pose)
		if angle > max_angle:
			skeleton.set_bone_pose_rotation(bone, rest.slerp(pose, max_angle / angle))
