extends SceneTree
## Builds the "fight" AnimationLibrary (res://assets/animations/fight_anims.res) from the
## Quaternius UAL clips: a boxing guard, guarded walk/crouch, blocks, and procedurally
## posed kicks/uppercut (the free UAL packs have no kicks).
##
## Run: godot_console --headless --path . -s res://tools/build_fight_animations.gd
##
## Poses are Dictionaries {bone_index: [position: Vector3, rotation: Quaternion]} in bone
## local space. Model space: +Z = forward (toward opponent), +Y = up, -X = model's right.

const MODEL := "res://assets/characters/base/Superhero_Male_FullBody.gltf"
const UAL1 := "res://assets/animations/UAL1_Standard.glb"
const UAL2 := "res://assets/animations/UAL2_Standard.glb"
const OUTPUT := "res://assets/animations/fight_anims.res"
const TRACK_PREFIX := "Armature/Skeleton3D:"
const SAMPLE_FPS := 30.0

const LOWER_BODY := ["root", "pelvis", "thigh_l", "calf_l", "foot_l", "ball_l", "ball_leaf_l",
	"thigh_r", "calf_r", "foot_r", "ball_r", "ball_leaf_r"]
const SPINE := ["spine_01", "spine_02", "spine_03"]

var skeleton: Skeleton3D
var ual1: AnimationLibrary
var ual2: AnimationLibrary
var guard: Dictionary
var crouch: Dictionary
var rear := "r" # side of the rear (kicking / power-punch) limbs, detected from the guard
var lead := "l"


func _initialize() -> void:
	var model := (load(MODEL) as PackedScene).instantiate()
	skeleton = model.find_child("Skeleton3D") as Skeleton3D
	ual1 = load(UAL1)
	ual2 = load(UAL2)

	guard = sample(ual1.get_animation("Punch_Jab"), 0.0)
	crouch = merge(sample(ual1.get_animation("Crouch_Idle"), 0.0), guard, upper_body_bones())
	rotate_bone(crouch, "spine_01", Vector3.RIGHT, -25.0) # Crouch_Idle hunches; sit up to face the opponent
	var foot_l := global_origin(guard, "foot_l")
	var foot_r := global_origin(guard, "foot_r")
	rear = "l" if foot_l.z < foot_r.z else "r"
	lead = "r" if rear == "l" else "l"
	print("rear side: ", rear)

	var lib := AnimationLibrary.new()
	lib.add_animation("guard", build_guard())
	lib.add_animation("walk_guard", resample_merged(ual1.get_animation("Walk"), LOWER_BODY, true))
	lib.add_animation("crouch_guard", build_crouch_guard())
	lib.add_animation("crouch_jab", build_crouch_jab())
	lib.add_animation("block_stand", build_block(guard))
	lib.add_animation("block_crouch", build_block(crouch))
	lib.add_animation("front_kick", build_front_kick())
	lib.add_animation("high_kick", build_high_kick())
	lib.add_animation("sweep", build_sweep())
	lib.add_animation("uppercut", build_uppercut())
	lib.add_animation("spin_sweep", build_spin_sweep())
	lib.add_animation("jump_punch", build_jump_punch())
	lib.add_animation("jump_kick", build_jump_kick())
	lib.add_animation("throw", build_throw())
	lib.add_animation("thrown", build_thrown())
	var err := ResourceSaver.save(lib, OUTPUT)
	print("saved ", OUTPUT, " (", lib.get_animation_list().size(), " clips) err=", err)
	model.free()
	quit()


# --- Clips -----------------------------------------------------------------------

func build_guard() -> Animation:
	var breathe := duplicate_pose(guard)
	move_bone(breathe, "pelvis", Vector3(0, -0.015, 0))
	rotate_bone(breathe, "spine_02", Vector3.RIGHT, 2.0)
	return make_animation([[0.0, guard], [1.0, breathe], [2.0, guard]], true)


func build_crouch_guard() -> Animation:
	var breathe := duplicate_pose(crouch)
	move_bone(breathe, "pelvis", Vector3(0, -0.01, 0))
	return make_animation([[0.0, crouch], [1.0, breathe], [2.0, crouch]], true)


## Low straight punch from crouch with the lead arm. Impact at 0.12 s.
func build_crouch_jab() -> Animation:
	var punch := duplicate_pose(crouch)
	var inward := -0.3 if lead == "l" else 0.3
	rotate_bone(punch, "spine_01", Vector3.RIGHT, 15.0)
	aim(punch, "upperarm_" + lead, "lowerarm_" + lead, Vector3(inward, -0.05, 1))
	aim(punch, "lowerarm_" + lead, "hand_" + lead, Vector3(inward, 0, 1))
	return make_animation([[0.0, crouch], [0.12, punch], [0.2, punch], [0.4, crouch]], false)


## Forearms raised in front of the face.
func build_block(base: Dictionary) -> Animation:
	var pose := duplicate_pose(base)
	for side in ["l", "r"]:
		var x := 0.25 if side == "l" else -0.25
		aim(pose, "upperarm_" + side, "lowerarm_" + side, Vector3(x * 0.6, -0.35, 1.0))
		aim(pose, "lowerarm_" + side, "hand_" + side, Vector3(-x * 0.8, 1.0, 0.35))
	rotate_bone(pose, "spine_01", Vector3.RIGHT, 8.0)
	return make_animation([[0.0, pose], [0.5, pose]], false)


## Mid front kick with the rear leg. Impact at 0.20 s.
func build_front_kick() -> Animation:
	var thigh := "thigh_" + rear
	var calf := "calf_" + rear
	var foot := "foot_" + rear
	var chamber := duplicate_pose(guard)
	aim(chamber, thigh, calf, Vector3(0, 0.15, 1))
	aim(chamber, calf, foot, Vector3(0, -1, 0.1))
	rotate_bone(chamber, "spine_01", Vector3.RIGHT, -6.0)
	var extend := duplicate_pose(chamber)
	aim(extend, thigh, calf, Vector3(0, 0.1, 1))
	aim(extend, calf, foot, Vector3(0, 0.05, 1))
	rotate_bone(extend, "spine_01", Vector3.RIGHT, -6.0)
	return make_animation([[0.0, guard], [0.10, chamber], [0.20, extend], [0.30, extend],
		[0.45, chamber], [0.62, guard]], false)


## High roundhouse-style kick with hip turn and lean back. Impact at 0.26 s.
func build_high_kick() -> Animation:
	var thigh := "thigh_" + rear
	var calf := "calf_" + rear
	var foot := "foot_" + rear
	var side_x := 0.35 if rear == "l" else -0.35
	var chamber := duplicate_pose(guard)
	rotate_bone(chamber, "pelvis", Vector3.UP, 25.0 if rear == "r" else -25.0)
	aim(chamber, thigh, calf, Vector3(side_x, 0.6, 0.8))
	aim(chamber, calf, foot, Vector3(-side_x, -0.6, 0.2))
	rotate_bone(chamber, "spine_01", Vector3.RIGHT, -12.0)
	var extend := duplicate_pose(chamber)
	aim(extend, thigh, calf, Vector3(side_x * 0.6, 0.85, 0.8))
	aim(extend, calf, foot, Vector3(-side_x * 0.3, 0.6, 1))
	rotate_bone(extend, "spine_01", Vector3.RIGHT, -10.0)
	return make_animation([[0.0, guard], [0.13, chamber], [0.26, extend], [0.38, extend],
		[0.56, chamber], [0.78, guard]], false)


## Low sweep from crouch with the rear leg extended along the ground. Impact at 0.18 s.
func build_sweep() -> Animation:
	var thigh := "thigh_" + rear
	var calf := "calf_" + rear
	var foot := "foot_" + rear
	var side_x := 0.3 if rear == "l" else -0.3
	var extend := duplicate_pose(crouch)
	move_bone(extend, "pelvis", Vector3(0, -0.08, 0))
	rotate_bone(extend, "pelvis", Vector3.UP, 20.0 if rear == "r" else -20.0)
	aim(extend, thigh, calf, Vector3(side_x, -0.45, 1))
	aim(extend, calf, foot, Vector3(side_x * 0.5, -0.3, 1))
	return make_animation([[0.0, crouch], [0.18, extend], [0.32, extend], [0.55, crouch]], false)


## Rising uppercut with the rear arm, from crouch up to standing. Impact at 0.22 s.
func build_uppercut() -> Animation:
	var upper := "upperarm_" + rear
	var lower := "lowerarm_" + rear
	var hand := "hand_" + rear
	var side_x := 0.1 if rear == "l" else -0.1
	var wind := duplicate_pose(crouch)
	aim(wind, upper, lower, Vector3(side_x, -0.9, 0.2))
	aim(wind, lower, hand, Vector3(0, 0.2, 1))
	var hit := duplicate_pose(guard)
	move_bone(hit, "pelvis", Vector3(0, 0.05, 0.08))
	rotate_bone(hit, "spine_01", Vector3.RIGHT, -5.0)
	aim(hit, upper, lower, Vector3(side_x, 0.35, 1))
	aim(hit, lower, hand, Vector3(0, 1, 0.45))
	return make_animation([[0.0, crouch], [0.10, wind], [0.22, hit], [0.38, hit], [0.70, guard]], false)


## Heavy sweep: low, long leg swinging through an arc with the hips. Impact at 0.20 s.
func build_spin_sweep() -> Animation:
	var thigh := "thigh_" + rear
	var calf := "calf_" + rear
	var foot := "foot_" + rear
	var turn := 1.0 if rear == "r" else -1.0
	var keys := [[0.0, crouch]]
	# The leg sweeps from the rear side, through the front, and past it.
	var arc := [[0.10, -50.0, -0.6], [0.20, 15.0, 0.0], [0.30, 50.0, 0.5], [0.40, 60.0, 0.6]]
	for k in arc:
		var pose := duplicate_pose(crouch)
		move_bone(pose, "pelvis", Vector3(0, -0.15, 0))
		rotate_bone(pose, "pelvis", Vector3.UP, turn * k[1])
		rotate_bone(pose, "spine_01", Vector3.RIGHT, 20.0)
		var dir := Vector3(-turn * k[2], -0.35, 1.0 - absf(k[2]) * 0.5)
		aim(pose, thigh, calf, dir)
		aim(pose, calf, foot, Vector3(dir.x, -0.25, dir.z))
		keys.append([k[0], pose])
	keys.append([0.65, crouch])
	return make_animation(keys, false)


## Mid-air tuck with the lead fist driving down-forward. Impact at 0.10 s.
func build_jump_punch() -> Animation:
	var air := sample(ual1.get_animation("Jump_Start"), 0.5)
	air = merge(air, guard, arm_bones())
	var punch := duplicate_pose(air)
	rotate_bone(punch, "spine_01", Vector3.RIGHT, 15.0)
	aim(punch, "upperarm_" + lead, "lowerarm_" + lead, Vector3(0, -0.45, 1))
	aim(punch, "lowerarm_" + lead, "hand_" + lead, Vector3(0, -0.5, 1))
	return make_animation([[0.0, air], [0.10, punch], [0.25, punch], [0.4, air]], false)


## Flying kick: rear leg extended down-forward, the other tucked. Impact at 0.12 s.
func build_jump_kick() -> Animation:
	var air := sample(ual1.get_animation("Jump_Start"), 0.5)
	air = merge(air, guard, arm_bones())
	var kick := duplicate_pose(air)
	rotate_bone(kick, "spine_01", Vector3.RIGHT, -10.0)
	aim(kick, "thigh_" + rear, "calf_" + rear, Vector3(0, -0.45, 1))
	aim(kick, "calf_" + rear, "foot_" + rear, Vector3(0, -0.5, 1))
	return make_animation([[0.0, air], [0.12, kick], [0.30, kick], [0.45, air]], false)


## Grab with both arms (0.08 s), then twist and heave (0.25-0.45 s).
func build_throw() -> Animation:
	var reach := duplicate_pose(guard)
	for side in ["l", "r"]:
		var x := 0.15 if side == "l" else -0.15
		aim(reach, "upperarm_" + side, "lowerarm_" + side, Vector3(x * 0.5, -0.1, 1))
		aim(reach, "lowerarm_" + side, "hand_" + side, Vector3(-x, 0.05, 1))
	rotate_bone(reach, "spine_01", Vector3.RIGHT, 12.0)
	var heave := duplicate_pose(reach)
	var turn := 1.0 if rear == "r" else -1.0
	rotate_bone(heave, "pelvis", Vector3.UP, turn * 35.0)
	rotate_bone(heave, "spine_02", Vector3.UP, turn * 25.0)
	rotate_bone(heave, "spine_01", Vector3.RIGHT, -20.0)
	return make_animation([[0.0, guard], [0.08, reach], [0.25, reach], [0.45, heave],
		[0.6, heave], [0.85, guard]], false)


## Held in a grab: doubled over, arms limp.
func build_thrown() -> Animation:
	var held := sample(ual1.get_animation("Hit_Chest"), 0.12)
	rotate_bone(held, "spine_01", Vector3.RIGHT, 20.0)
	return make_animation([[0.0, held], [0.5, held]], false)


## Resamples `source` keeping its `keep_bones`, with the rest of the body from the guard.
func resample_merged(source: Animation, keep_bones: Array, loop: bool) -> Animation:
	var keys := []
	var t := 0.0
	while t <= source.length + 0.001:
		keys.append([t, merge(guard, sample(source, t), bone_indices(keep_bones))])
		t += 1.0 / SAMPLE_FPS
	return make_animation(keys, loop)


# --- Pose helpers ----------------------------------------------------------------

func sample(anim: Animation, time: float) -> Dictionary:
	var pose := {}
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(i)
		var path := NodePath(TRACK_PREFIX + skeleton.get_bone_name(i))
		var pos := rest.origin
		var rot := rest.basis.get_rotation_quaternion()
		var pt := anim.find_track(path, Animation.TYPE_POSITION_3D)
		if pt >= 0:
			pos = anim.position_track_interpolate(pt, time)
		var rt := anim.find_track(path, Animation.TYPE_ROTATION_3D)
		if rt >= 0:
			rot = anim.rotation_track_interpolate(rt, time)
		pose[i] = [pos, rot]
	return pose


func merge(base: Dictionary, overlay: Dictionary, overlay_bones: Array) -> Dictionary:
	var out := duplicate_pose(base)
	for i: int in overlay_bones:
		out[i] = overlay[i].duplicate()
	return out


func duplicate_pose(pose: Dictionary) -> Dictionary:
	var out := {}
	for i in pose:
		out[i] = pose[i].duplicate()
	return out


func global_transform(pose: Dictionary, bone: int) -> Transform3D:
	var local := Transform3D(Basis(pose[bone][1] as Quaternion), pose[bone][0] as Vector3)
	var parent := skeleton.get_bone_parent(bone)
	return local if parent < 0 else global_transform(pose, parent) * local


func global_origin(pose: Dictionary, bone_name: String) -> Vector3:
	return global_transform(pose, skeleton.find_bone(bone_name)).origin


## Rotates `bone` (and its subtree) by `degrees` around a model-space axis.
func rotate_bone(pose: Dictionary, bone_name: String, axis: Vector3, degrees: float) -> void:
	_apply_global_rotation(pose, skeleton.find_bone(bone_name), Quaternion(axis.normalized(), deg_to_rad(degrees)))


## Rotates `bone` so the direction toward `child` points along a model-space direction.
func aim(pose: Dictionary, bone_name: String, child_name: String, direction: Vector3) -> void:
	var bone := skeleton.find_bone(bone_name)
	var from := global_origin(pose, bone_name)
	var to := global_origin(pose, child_name)
	_apply_global_rotation(pose, bone, Quaternion((to - from).normalized(), direction.normalized()))


## Moves `bone` by a model-space offset.
func move_bone(pose: Dictionary, bone_name: String, offset: Vector3) -> void:
	var bone := skeleton.find_bone(bone_name)
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := Basis() if parent < 0 else global_transform(pose, parent).basis
	pose[bone][0] = (pose[bone][0] as Vector3) + parent_basis.inverse() * offset


func _apply_global_rotation(pose: Dictionary, bone: int, rotation: Quaternion) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := Basis() if parent < 0 else global_transform(pose, parent).basis
	var global_basis := global_transform(pose, bone).basis
	var new_local := parent_basis.inverse() * Basis(rotation) * global_basis
	pose[bone][1] = new_local.get_rotation_quaternion()


func bone_indices(names: Array) -> Array:
	var out := []
	for n: String in names:
		out.append(skeleton.find_bone(n))
	return out


func upper_body_bones() -> Array:
	var lower := bone_indices(LOWER_BODY + SPINE)
	var out := []
	for i in skeleton.get_bone_count():
		if i not in lower:
			out.append(i)
	return out


func arm_bones() -> Array:
	var out := []
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i)
		if n.ends_with("_l") or n.ends_with("_r"):
			if not (n.begins_with("thigh") or n.begins_with("calf") or n.begins_with("foot") or n.begins_with("ball")):
				out.append(i)
	return out


## keys: Array of [time, pose]. Position track for the pelvis, rotation tracks for all bones.
func make_animation(keys: Array, loop: bool) -> Animation:
	var anim := Animation.new()
	anim.length = keys[-1][0]
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var pelvis := skeleton.find_bone("pelvis")
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath(TRACK_PREFIX + "pelvis"))
	for key in keys:
		anim.position_track_insert_key(pos_track, key[0], key[1][pelvis][0])
	for i in skeleton.get_bone_count():
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath(TRACK_PREFIX + skeleton.get_bone_name(i)))
		anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		for key in keys:
			anim.rotation_track_insert_key(track, key[0], key[1][i][1])
	return anim
