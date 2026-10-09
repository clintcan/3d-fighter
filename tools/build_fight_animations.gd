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
	lib.add_animation("victory_bow", build_victory_bow())
	lib.add_animation("victory_fist_pump", build_victory_fist_pump())
	lib.add_animation("victory_flex", build_victory_flex())
	lib.add_animation("victory_point", build_victory_point())
	lib.add_animation("rushing_hook", build_in_place([ual2.get_animation("Melee_Hook"), ual2.get_animation("Melee_Hook_Rec")]))
	# Specials and supers
	lib.add_animation("palm_blast", build_palm_blast())
	lib.add_animation("rising_uppercut", build_rising_uppercut())
	lib.add_animation("punch_flurry", build_punch_flurry())
	lib.add_animation("kick_flurry", build_kick_flurry())
	lib.add_animation("rising_kick", build_rising_kick())
	lib.add_animation("ground_pound", build_ground_pound())
	lib.add_animation("axe_kick", build_axe_kick())
	lib.add_animation("spin_back_kick", build_spin_back_kick())
	lib.add_animation("tornado_kick", build_tornado_kick())
	lib.add_animation("hurricane_kicks", build_hurricane_kicks())
	lib.add_animation("lariat", build_lariat())
	lib.add_animation("knee_lift", build_knee_lift())
	lib.add_animation("backfist", build_backfist())
	lib.add_animation("flip_kick", build_flip_kick())
	lib.add_animation("dive_kick", build_dive_kick())
	lib.add_animation("focus_stance", build_focus_stance())
	lib.add_animation("counter_stance", build_counter_stance())
	lib.add_animation("chain_punch", build_chain_punch(12))
	lib.add_animation("chain_punch_short", build_chain_punch(3))
	lib.add_animation("reversal_throw", build_reversal_throw())
	lib.add_animation("slide_kick",build_in_place_ranges([[ual2.get_animation("Slide_Start"), 0.2, 0.83], [ual2.get_animation("Slide_Exit"), 0.0, 0.3]], crouch, 0.25))
	lib.add_animation("shoulder_charge", build_in_place_ranges([[ual2.get_animation("Shield_Dash"), 0.0, 0.5]], guard, 0.3))
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


## Forearms raised in front of the face.
func build_block(base: Dictionary) -> Animation:
	var pose := duplicate_pose(base)
	for side in ["l", "r"]:
		var x := 0.25 if side == "l" else -0.25
		aim(pose, "upperarm_" + side, "lowerarm_" + side, Vector3(x * 0.6, -0.35, 1.0))
		aim(pose, "lowerarm_" + side, "hand_" + side, Vector3(-x * 0.8, 1.0, 0.35))
	rotate_bone(pose, "spine_01", Vector3.RIGHT, 8.0)
	return make_animation([[0.0, pose], [0.5, pose]], false)


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


## Front (push) kick with the rear leg, mae-geri style: knee chambers high toward the
## chest, the hips thrust forward as the leg snaps out ball-of-foot first, then the leg
## rechambers before stepping down. Support knee flexes; torso leans back. Impact 0.20 s.
func build_front_kick() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)

	var load := duplicate_pose(guard)
	move_bone(load, "pelvis", Vector3(0, -0.02, 0.04))
	plant_foot(load, lead, lead_foot)
	plant_foot(load, rear, rear_foot + Vector3(0, 0.03, 0))
	point_foot(load, rear, Vector3(0, -0.6, 0.8)) # heel lifts as weight leaves the rear leg

	var chamber := duplicate_pose(guard)
	move_bone(chamber, "pelvis", Vector3(0, -0.04, 0.07))
	hip_turn(chamber, 15.0)
	lean(chamber, 8.0, 0.0)
	plant_foot(chamber, lead, lead_foot)
	var hip := global_origin(chamber, "thigh_" + rear)
	solve_ik(chamber, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
		hip + Vector3(s * 0.02, -0.32, 0.28), Vector3(0, 0.4, 1))
	point_foot(chamber, rear, Vector3(0, -0.7, 0.7))
	swing_rear_arm(chamber, 0.3)

	var strike := duplicate_pose(guard)
	move_bone(strike, "pelvis", Vector3(0, -0.03, 0.13)) # hip thrust into the target
	hip_turn(strike, 22.0)
	lean(strike, 16.0, 0.0)
	plant_foot(strike, lead, lead_foot)
	pivot_support_foot(strike, 20.0, false)
	hip = global_origin(strike, "thigh_" + rear)
	solve_ik(strike, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
		Vector3(hip.x * 0.5, 0.95, hip.z + 1.0), Vector3(0, 1, 0.2))
	point_foot(strike, rear, Vector3(0, 0.55, 0.85)) # sole to target, ball of the foot leads
	swing_rear_arm(strike, 0.6)

	var recoil := duplicate_pose(chamber)
	move_bone(recoil, "pelvis", Vector3(0, 0, -0.02))

	return make_animation([[0.0, guard], [0.06, load], [0.12, chamber], [0.20, strike],
		[0.27, strike], [0.37, recoil], [0.50, load], [0.64, guard]], false)


## Roundhouse (mawashi-geri) to the head with the rear leg: weight shifts onto the lead
## foot, the knee chambers out to the side, the hips turn over as the support heel pivots
## toward the target, and the leg whips through with a pointed foot. The torso leans away
## and the rear arm swings down and back to counterbalance. Impact 0.26 s.
func build_high_kick() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)
	var toward_support := Vector3(-s, 0, 0)

	var load := duplicate_pose(guard)
	move_bone(load, "pelvis", Vector3(0, -0.02, 0.05) + toward_support * 0.05)
	hip_turn(load, 20.0)
	plant_foot(load, lead, lead_foot)
	plant_foot(load, rear, rear_foot + Vector3(0, 0.04, 0))
	point_foot(load, rear, Vector3(0, -0.7, 0.7))
	pivot_support_foot(load, 25.0, false)

	var chamber := duplicate_pose(guard)
	move_bone(chamber, "pelvis", Vector3(0, -0.06, 0.08) + toward_support * 0.07)
	hip_turn(chamber, 60.0)
	lean(chamber, 10.0, 8.0)
	plant_foot(chamber, lead, lead_foot + Vector3(0, 0.015, 0))
	pivot_support_foot(chamber, 60.0, true)
	var hip := global_origin(chamber, "thigh_" + rear)
	# Knee up and out to the side, lower leg folded back behind it.
	solve_ik(chamber, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
		hip + Vector3(s * 0.42, 0.02, -0.02), Vector3(-s * 0.2, 0.3, 1))
	point_foot(chamber, rear, Vector3(s * 0.6, -0.2, -0.6))
	swing_rear_arm(chamber, 0.5)

	var strike := duplicate_pose(guard)
	move_bone(strike, "pelvis", Vector3(0, -0.07, 0.1) + toward_support * 0.09)
	hip_turn(strike, 95.0)
	lean(strike, 20.0, 18.0)
	plant_foot(strike, lead, lead_foot + Vector3(0, 0.02, 0))
	pivot_support_foot(strike, 115.0, true)
	hip = global_origin(strike, "thigh_" + rear)
	var target := Vector3(-s * 0.05, 1.5, 0.9)
	solve_ik(strike, "thigh_" + rear, "calf_" + rear, "foot_" + rear, target, Vector3(0, 1, -0.3))
	point_foot(strike, rear, (target - global_origin(strike, "calf_" + rear)).normalized() + Vector3(-s * 0.3, 0, 0))
	swing_rear_arm(strike, 1.0)

	var follow := duplicate_pose(strike)
	hip_turn(follow, 8.0)

	var recoil := duplicate_pose(chamber)
	hip_turn(recoil, -10.0)

	return make_animation([[0.0, guard], [0.07, load], [0.15, chamber], [0.26, strike],
		[0.33, follow], [0.46, recoil], [0.62, load], [0.78, guard]], false)


## Low kick from a crouch: sink onto the lead leg and shoot the rear leg out along the
## canvas, foot flat and pointed, lead hand dropping toward the floor. Impact 0.18 s.
func build_sweep() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(crouch, "foot_" + lead)

	var chamber := duplicate_pose(crouch)
	move_bone(chamber, "pelvis", Vector3(0, -0.05, 0.02))
	hip_turn(chamber, 15.0)
	plant_foot(chamber, lead, lead_foot)
	var hip := global_origin(chamber, "thigh_" + rear)
	solve_ik(chamber, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
		Vector3(hip.x, 0.12, hip.z + 0.25), Vector3(-s * 0.3, 0.4, 1))
	point_foot(chamber, rear, Vector3(0, -0.3, 1))

	var strike := duplicate_pose(crouch)
	move_bone(strike, "pelvis", Vector3(0, -0.1, 0.04))
	hip_turn(strike, 28.0)
	lean(strike, -10.0, 6.0)
	plant_foot(strike, lead, lead_foot)
	pivot_support_foot(strike, 25.0, false)
	solve_ik(strike, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
		Vector3(s * 0.12, 0.1, 0.88), Vector3(0, 1, 0.1))
	point_foot(strike, rear, Vector3(-s * 0.2, -0.05, 1))
	reach_arm(strike, lead, Vector3(-s * 0.45, 0.25, 0.3))

	return make_animation([[0.0, crouch], [0.08, chamber], [0.18, strike], [0.29, strike],
		[0.41, chamber], [0.55, crouch]], false)


## Spinning sweep (Street Fighter crouching-heavy-kick style): drop into a deep squat on
## the lead leg with the lead hand planted, and swing the straight rear leg in a wide arc
## along the floor from behind, through the front, and past it. Impact 0.20 s.
func build_spin_sweep() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(crouch, "foot_" + lead)
	var keys := [[0.0, crouch]]
	# [time, hip turn, sweep angle (deg from straight ahead toward the rear side is negative)]
	var arc := [[0.07, -25.0, -110.0], [0.13, 0.0, -55.0], [0.20, 30.0, 0.0],
		[0.28, 60.0, 45.0], [0.36, 80.0, 75.0]]
	for k in arc:
		var pose := duplicate_pose(crouch)
		move_bone(pose, "pelvis", Vector3(0, -0.17, 0.03))
		hip_turn(pose, k[1])
		lean(pose, -12.0, 10.0)
		plant_foot(pose, lead, lead_foot)
		pivot_support_foot(pose, k[1] * 0.6, false)
		var pelvis := global_origin(pose, "pelvis")
		var phi := deg_to_rad(k[2])
		var dir := Vector3(-s * sin(phi), 0, cos(phi))
		var target := Vector3(pelvis.x, 0.1, pelvis.z) + dir * 1.0
		solve_ik(pose, "thigh_" + rear, "calf_" + rear, "foot_" + rear, target, Vector3(0, 1, 0))
		point_foot(pose, rear, dir + Vector3(0, -0.1, 0))
		reach_arm(pose, lead, Vector3(lead_foot.x - s * 0.15, 0.06, lead_foot.z + 0.35))
		keys.append([k[0], pose])
	keys.append([0.50, keys[2][1]])
	keys.append([0.65, crouch])
	return make_animation(keys, false)


## Flying kick: rear leg drives down-forward like a jump side kick with the foot pointed,
## lead knee tucked high, torso leaning back, arms out for balance. Impact 0.12 s.
func build_jump_kick() -> Animation:
	var s := rear_sign()
	var air := sample(ual1.get_animation("Jump_Start"), 0.5)
	air = merge(air, guard, arm_bones())

	var kick := duplicate_pose(air)
	hip_turn(kick, 35.0)
	lean(kick, 16.0, 6.0)
	var hip := global_origin(kick, "thigh_" + rear)
	solve_ik(kick, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
		hip + Vector3(-s * 0.05, -0.5, 0.85), Vector3(0, 1, 0.3))
	point_foot(kick, rear, Vector3(0, -0.2, 1))
	var lead_hip := global_origin(kick, "thigh_" + lead)
	solve_ik(kick, "thigh_" + lead, "calf_" + lead, "foot_" + lead,
		lead_hip + Vector3(-s * 0.1, -0.28, -0.12), Vector3(0, 0.2, 1))
	swing_rear_arm(kick, 0.8)

	return make_animation([[0.0, air], [0.12, kick], [0.30, kick], [0.45, air]], false)


# --- Kick / body helpers ---------------------------------------------------------

## +1 if the rear (kicking) side is the model's left (+X), -1 if it's the right.
func rear_sign() -> float:
	return 1.0 if rear == "l" else -1.0


## Two-bone IK in model space: places `end_bone` at `target`, bending `mid_bone` toward
## `pole`. Out-of-reach targets straighten the limb toward them.
func solve_ik(pose: Dictionary, upper: String, mid: String, end_bone: String, target: Vector3, pole: Vector3) -> void:
	var a := global_origin(pose, upper)
	var l1 := a.distance_to(global_origin(pose, mid))
	var l2 := global_origin(pose, mid).distance_to(global_origin(pose, end_bone))
	var to_target := target - a
	var d := clampf(to_target.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := to_target.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 0.0001:
		bend = Vector3.UP.cross(dir)
	bend = bend.normalized()
	var knee := a + dir * (cos_a * l1) + bend * (sqrt(1.0 - cos_a * cos_a) * l1)
	aim(pose, upper, mid, knee - a)
	aim(pose, mid, end_bone, (a + dir * d) - global_origin(pose, mid))


## Keeps a support foot at `planted` (model space), knee bending forward and slightly out.
func plant_foot(pose: Dictionary, side: String, planted: Vector3) -> void:
	var out := 0.25 if side == "l" else -0.25
	solve_ik(pose, "thigh_" + side, "calf_" + side, "foot_" + side, planted, Vector3(out, 0, 1))
	point_foot(pose, side, foot_direction(guard, side))


## Points the foot (ankle → ball) along a model-space direction.
func point_foot(pose: Dictionary, side: String, direction: Vector3) -> void:
	aim(pose, "foot_" + side, "ball_" + side, direction)


func foot_direction(pose: Dictionary, side: String) -> Vector3:
	return global_origin(pose, "ball_" + side) - global_origin(pose, "foot_" + side)


## Pivots the lead (support) foot so the heel turns toward the target; optionally up on
## the ball of the foot.
func pivot_support_foot(pose: Dictionary, degrees: float, on_ball: bool) -> void:
	var base := foot_direction(guard, lead)
	var dir := base.rotated(Vector3.UP, deg_to_rad(degrees * -rear_sign()))
	if on_ball:
		dir.y -= 0.22 * Vector2(dir.x, dir.z).length()
	point_foot(pose, lead, dir)


## Turns the hips by `degrees` (positive brings the rear hip forward). Shoulders follow
## about half way and the head stays on the target.
func hip_turn(pose: Dictionary, degrees: float) -> void:
	var signed := degrees * -rear_sign()
	rotate_bone(pose, "pelvis", Vector3.UP, signed)
	rotate_bone(pose, "spine_02", Vector3.UP, -signed * 0.5)
	rotate_bone(pose, "neck_01", Vector3.UP, -signed * 0.4)


## Leans the torso back (positive) or forward (negative) and sideways toward the
## support side, then rights the head a little.
func lean(pose: Dictionary, back_degrees: float, side_degrees: float) -> void:
	rotate_bone(pose, "spine_01", Vector3.RIGHT, -back_degrees * 0.6)
	rotate_bone(pose, "spine_02", Vector3.RIGHT, -back_degrees * 0.4)
	rotate_bone(pose, "spine_01", Vector3(0, 0, 1), -rear_sign() * side_degrees)
	rotate_bone(pose, "neck_01", Vector3.RIGHT, back_degrees * 0.4)


## Rear arm swings down and back to counterbalance a kick (amount 0..1); lead arm keeps
## the guard.
func swing_rear_arm(pose: Dictionary, amount: float) -> void:
	var s := rear_sign()
	var upper := Vector3(s * 0.35, -0.2, 0.25).lerp(Vector3(s * 0.35, -0.85, -0.45), amount)
	var lower := Vector3(0, 0.4, 0.6).lerp(Vector3(s * 0.1, -0.95, -0.15), amount)
	aim(pose, "upperarm_" + rear, "lowerarm_" + rear, upper)
	aim(pose, "lowerarm_" + rear, "hand_" + rear, lower)


## Places a hand at `target` (model space), elbow bending back and out.
func reach_arm(pose: Dictionary, side: String, target: Vector3) -> void:
	var out := 1.0 if side == "l" else -1.0
	solve_ik(pose, "upperarm_" + side, "lowerarm_" + side, "hand_" + side, target, Vector3(out * 0.6, 0.3, -0.6))


## Crouching jab (lead hand): a quick snap from the crouch. The lead shoulder rolls up
## and forward to cover the chin, the hips turn the lead side in, the rear hand stays at
## the chin, and the fist retracts along the same line. Impact 0.12 s.
func build_crouch_jab() -> Animation:
	var lead_foot := global_origin(crouch, "foot_" + lead)
	var rear_foot := global_origin(crouch, "foot_" + rear)

	var load := duplicate_pose(crouch)
	hip_turn(load, 6.0) # tiny counter-coil before the snap
	plant_both(load, lead_foot, rear_foot)

	var strike := duplicate_pose(crouch)
	move_bone(strike, "pelvis", Vector3(0, -0.01, 0.04))
	hip_turn(strike, -20.0)
	lean(strike, -6.0, 0.0)
	plant_both(strike, lead_foot, rear_foot)
	var shoulder := global_origin(strike, "upperarm_" + lead)
	punch_arm(strike, lead, Vector3(-rear_sign() * 0.05, shoulder.y - 0.08, shoulder.z + 0.62))
	shoulder_roll(strike, lead, 12.0)
	rotate_bone(strike, "neck_01", Vector3.RIGHT, 8.0) # chin tucked behind the shoulder

	var recoil := duplicate_pose(strike)
	punch_arm(recoil, lead, Vector3(-rear_sign() * 0.05, shoulder.y - 0.05, shoulder.z + 0.3))

	return make_animation([[0.0, crouch], [0.05, load], [0.12, strike], [0.17, strike],
		[0.24, recoil], [0.40, crouch]], false)


## Rising uppercut (rear hand): dip by bending the knees with the rear shoulder dropped
## and the fist low, then drive up from the legs, turning the hips and pivoting the rear
## heel, the elbow held near 90° as the fist rises through the body and chin, then
## follows through high before recovering to guard. Impact 0.22 s (fist at chest height).
func build_uppercut() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)

	var dip := duplicate_pose(crouch)
	move_bone(dip, "pelvis", Vector3(0, -0.06, -0.02))
	hip_turn(dip, -22.0) # coil: rear hip pulled back
	lean(dip, -8.0, -10.0) # rear shoulder dips
	plant_both(dip, global_origin(crouch, "foot_" + lead), global_origin(crouch, "foot_" + rear))
	var dip_shoulder := global_origin(dip, "upperarm_" + rear)
	reach_arm(dip, rear, Vector3(dip_shoulder.x * 0.7, dip_shoulder.y - 0.4, dip_shoulder.z + 0.2))

	var strike := duplicate_pose(guard)
	move_bone(strike, "pelvis", Vector3(0, 0.03, 0.06))
	hip_turn(strike, 35.0)
	lean(strike, 2.0, 6.0)
	plant_foot(strike, lead, lead_foot)
	plant_foot(strike, rear, rear_foot + Vector3(0, 0.04, 0.03))
	point_foot(strike, rear, foot_direction(guard, rear).rotated(Vector3.UP, deg_to_rad(-s * 50.0)) + Vector3(0, -0.5, 0))
	var shoulder := global_origin(strike, "upperarm_" + rear)
	uppercut_arm(strike, Vector3(-s * 0.02, 1.32, shoulder.z + 0.45))

	var follow := duplicate_pose(guard)
	move_bone(follow, "pelvis", Vector3(0, 0.07, 0.07))
	hip_turn(follow, 45.0)
	lean(follow, 8.0, 8.0)
	plant_foot(follow, lead, lead_foot + Vector3(0, 0.02, 0))
	plant_foot(follow, rear, rear_foot + Vector3(0, 0.07, 0.05))
	point_foot(follow, rear, foot_direction(guard, rear).rotated(Vector3.UP, deg_to_rad(-s * 60.0)) + Vector3(0, -0.8, 0))
	shoulder = global_origin(follow, "upperarm_" + rear)
	uppercut_arm(follow, Vector3(-s * 0.04, shoulder.y + 0.16, shoulder.z + 0.4)) # finish at head height, elbow still bent

	return make_animation([[0.0, crouch], [0.09, dip], [0.22, strike], [0.32, follow],
		[0.46, follow], [0.70, guard]], false)


## Jump punch: from the air tuck, the body pitches forward over a downward diagonal punch
## with the lead hand while the rear arm pulls back for counter-rotation. Impact 0.10 s.
func build_jump_punch() -> Animation:
	var air := sample(ual1.get_animation("Jump_Start"), 0.5)
	air = merge(air, guard, arm_bones())

	var punch := duplicate_pose(air)
	hip_turn(punch, -25.0)
	lean(punch, -18.0, 0.0)
	var shoulder := global_origin(punch, "upperarm_" + lead)
	punch_arm(punch, lead, shoulder + Vector3(-rear_sign() * 0.08, -0.38, 0.55))
	shoulder_roll(punch, lead, 10.0)
	swing_rear_arm(punch, 0.55)

	return make_animation([[0.0, air], [0.10, punch], [0.25, punch], [0.40, air]], false)


## Straight punch: hand to `target` with the elbow tucked down and slightly out.
func punch_arm(pose: Dictionary, side: String, target: Vector3) -> void:
	var out := 1.0 if side == "l" else -1.0
	solve_ik(pose, "upperarm_" + side, "lowerarm_" + side, "hand_" + side, target, Vector3(out * 0.4, -1.0, -0.2))


## Uppercut arm: rear hand to `target` with the elbow held low and in front, so the forearm
## stays near vertical with the arm bent ~90°.
func uppercut_arm(pose: Dictionary, target: Vector3) -> void:
	var out := 1.0 if rear == "l" else -1.0
	solve_ik(pose, "upperarm_" + rear, "lowerarm_" + rear, "hand_" + rear, target, Vector3(out * 0.3, -1.0, 0.6))


## Raises a shoulder (clavicle) by `degrees`: the jab's chin-covering shoulder roll.
func shoulder_roll(pose: Dictionary, side: String, degrees: float) -> void:
	rotate_bone(pose, "clavicle_" + side, Vector3(0, 0, 1), degrees * (1.0 if side == "l" else -1.0))


func plant_both(pose: Dictionary, lead_foot: Vector3, rear_foot: Vector3) -> void:
	plant_foot(pose, lead, lead_foot)
	plant_foot(pose, rear, rear_foot)


## Victory: martial-arts salute and bow. Feet come together, right fist meets left palm
## in front of the chest, a measured bow, then upright to hold the salute. ~3.4 s.
func build_victory_bow() -> Animation:
	var stand := _victory_stance(0.11, 0.05)
	var salute := duplicate_pose(stand)
	_salute_hands(salute)
	var bow := duplicate_pose(stand)
	lean(bow, -32.0, 0.0)
	rotate_bone(bow, "neck_01", Vector3.RIGHT, 12.0)
	_salute_hands(bow)
	var settle := duplicate_pose(salute)
	move_bone(settle, "pelvis", Vector3(0, -0.01, 0))
	return make_animation([[0.0, guard], [0.4, stand], [0.75, salute], [1.25, salute],
		[1.75, bow], [2.25, bow], [2.75, salute], [3.4, settle]], false)


## Victory: crouch, then explode upward with the rear fist thrown overhead and the lead
## fist pumped at the chest, chest out, head back. ~3.0 s.
func build_victory_fist_pump() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)

	var gather := duplicate_pose(guard)
	move_bone(gather, "pelvis", Vector3(0, -0.1, 0))
	lean(gather, -10.0, 0.0)
	plant_both(gather, lead_foot, rear_foot)
	var shoulder := global_origin(gather, "upperarm_" + rear)
	reach_arm(gather, rear, Vector3(shoulder.x, 0.95, shoulder.z + 0.15))

	var pump := duplicate_pose(guard)
	move_bone(pump, "pelvis", Vector3(0, 0.04, 0))
	hip_turn(pump, 15.0)
	lean(pump, 12.0, 0.0)
	rotate_bone(pump, "neck_01", Vector3.RIGHT, -18.0) # head back
	plant_both(pump, lead_foot, rear_foot + Vector3(0, 0.03, 0))
	shoulder = global_origin(pump, "upperarm_" + rear)
	punch_arm(pump, rear, Vector3(shoulder.x + s * 0.08, shoulder.y + 0.62, shoulder.z + 0.05))
	var lead_shoulder := global_origin(pump, "upperarm_" + lead)
	reach_arm(pump, lead, Vector3(lead_shoulder.x * 0.4, lead_shoulder.y - 0.12, lead_shoulder.z + 0.25))

	var breathe := duplicate_pose(pump)
	move_bone(breathe, "pelvis", Vector3(0, -0.02, 0))
	return make_animation([[0.0, guard], [0.18, gather], [0.42, pump], [0.55, pump],
		[1.6, breathe], [3.0, pump]], false)


## Victory: wide stance, double-biceps flex with a roar. ~3.2 s.
func build_victory_flex() -> Animation:
	var stand := _victory_stance(0.3, -0.02)
	var flex := duplicate_pose(stand)
	lean(flex, 8.0, 0.0)
	rotate_bone(flex, "neck_01", Vector3.RIGHT, -12.0)
	_double_biceps(flex, 0.0)
	var squeeze := duplicate_pose(flex)
	move_bone(squeeze, "pelvis", Vector3(0, -0.02, 0))
	_double_biceps(squeeze, 0.12)
	return make_animation([[0.0, guard], [0.35, stand], [0.7, flex], [1.1, squeeze],
		[1.5, flex], [1.9, squeeze], [2.4, flex], [3.2, flex]], false)


## Victory: weight on one hip, lead hand on the hip, rear arm pointing straight at the
## camera (out front). ~3.0 s.
func build_victory_point() -> Animation:
	var s := rear_sign()
	var stand := _victory_stance(0.14, 0.03)
	var pose := duplicate_pose(stand)
	move_bone(pose, "pelvis", Vector3(s * -0.07, -0.01, 0)) # hip pops to the lead side
	rotate_bone(pose, "pelvis", Vector3(0, 0, 1), s * 6.0)
	lean(pose, 4.0, -6.0)
	plant_both(pose, Vector3(-s * 0.14, 0.04, 0.03), Vector3(s * 0.14, 0.04, -0.03))
	var hip := global_origin(pose, "thigh_" + lead)
	reach_arm(pose, lead, hip + Vector3(-s * 0.18, 0.02, -0.02))
	var shoulder := global_origin(pose, "upperarm_" + rear)
	punch_arm(pose, rear, shoulder + Vector3(-s * 0.15, 0.08, 0.62))
	var sway := duplicate_pose(pose)
	move_bone(sway, "pelvis", Vector3(s * -0.02, 0, 0))
	return make_animation([[0.0, guard], [0.35, stand], [0.7, pose], [1.8, sway], [3.0, pose]], false)


## Upright stance with feet `half_width` apart and the pelvis raised `rise`.
func _victory_stance(half_width: float, rise: float) -> Dictionary:
	var s := rear_sign()
	var pose := duplicate_pose(guard)
	move_bone(pose, "pelvis", Vector3(0, rise, 0.1))
	hip_turn(pose, 20.0) # square up toward the opponent/camera
	plant_both(pose, Vector3(-s * half_width, 0.04, 0.06), Vector3(s * half_width, 0.04, 0.0))
	return pose


## Fist-in-palm salute held in front of the upper chest (anchored to the neck so it
## follows the torso through the bow).
func _salute_hands(pose: Dictionary) -> void:
	var target := global_origin(pose, "neck_01") + Vector3(0, -0.26, 0.26)
	reach_arm(pose, "l", target + Vector3(0.03, 0, 0))
	reach_arm(pose, "r", target + Vector3(-0.03, 0, 0))


func _double_biceps(pose: Dictionary, lift: float) -> void:
	for side in ["l", "r"]:
		var out := 1.0 if side == "l" else -1.0
		aim(pose, "upperarm_" + side, "lowerarm_" + side, Vector3(out, 0.08 + lift, 0.12))
		aim(pose, "lowerarm_" + side, "hand_" + side, Vector3(-out * 0.25, 1.0, 0.05))


## Chains clips and pins the pelvis horizontally, so travel baked into the animation
## can be done by gameplay (MoveData.lunge) instead. Prints the removed travel.
func build_in_place(clips: Array) -> Animation:
	var keys := []
	var offset := 0.0
	var anchor := Vector3.INF
	var max_travel := 0.0
	for clip: Animation in clips:
		var t := 0.0
		while t <= clip.length + 0.001:
			var pose := sample(clip, t)
			var pelvis := global_origin(pose, "pelvis")
			if anchor == Vector3.INF:
				anchor = pelvis
			max_travel = maxf(max_travel, pelvis.z - anchor.z)
			move_bone(pose, "pelvis", Vector3(anchor.x - pelvis.x, 0.0, anchor.z - pelvis.z))
			keys.append([offset + t, pose])
			t += 1.0 / SAMPLE_FPS
		offset += clip.length + 1.0 / SAMPLE_FPS
	print("in-place clip: removed up to %.2f m of forward travel" % max_travel)
	return make_animation(keys, false)


## Like build_in_place, for parts of clips: [[clip, from, to], ...], then blends into
## `settle` over `settle_time` seconds.
func build_in_place_ranges(ranges: Array, settle: Dictionary, settle_time: float) -> Animation:
	var keys := []
	var offset := 0.0
	var anchor := Vector3.INF
	for r: Array in ranges:
		var clip: Animation = r[0]
		var t: float = r[1]
		while t <= r[2] + 0.001:
			var pose := sample(clip, t)
			var pelvis := global_origin(pose, "pelvis")
			if anchor == Vector3.INF:
				anchor = pelvis
			move_bone(pose, "pelvis", Vector3(anchor.x - pelvis.x, 0.0, anchor.z - pelvis.z))
			keys.append([offset + t - r[1], pose])
			t += 1.0 / SAMPLE_FPS
		offset += r[2] - r[1] + 1.0 / SAMPLE_FPS
	keys.append([offset + settle_time, settle])
	return make_animation(keys, false)


# --- Specials ----------------------------------------------------------------------

## Two-handed palm blast (Kenji's Ki Blast): sink and coil with both hands cupped at the
## rear hip, then drive the weight forward and thrust both palms out at chest height,
## heels of the hands together, holding as the energy leaves. Impact 0.20 s.
func build_palm_blast() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)

	var coil := duplicate_pose(guard)
	move_bone(coil, "pelvis", Vector3(0, -0.09, -0.05))
	hip_turn(coil, -30.0)
	lean(coil, 4.0, 0.0)
	plant_both(coil, lead_foot, rear_foot)
	var hip := global_origin(coil, "thigh_" + rear)
	var cup := Vector3(hip.x + s * 0.12, hip.y + 0.15, hip.z + 0.08)
	reach_arm(coil, rear, cup)
	reach_arm(coil, lead, cup + Vector3(-s * 0.05, 0.1, 0.06))

	var thrust := duplicate_pose(guard)
	move_bone(thrust, "pelvis", Vector3(0, -0.07, 0.1))
	hip_turn(thrust, 12.0)
	lean(thrust, -8.0, 0.0)
	plant_both(thrust, lead_foot, rear_foot)
	var chest := global_origin(thrust, "spine_03")
	var palm := Vector3(0, chest.y - 0.02, chest.z + 0.6)
	for side in [lead, rear]:
		var x := 0.045 if side == "l" else -0.045
		punch_arm(thrust, side, palm + Vector3(x, 0, 0))
		rotate_bone(thrust, "hand_" + side, Vector3.RIGHT, -55.0) # wrist back: palm forward

	var hold := duplicate_pose(thrust)
	move_bone(hold, "pelvis", Vector3(0, -0.01, 0.01))

	return make_animation([[0.0, guard], [0.11, coil], [0.20, thrust], [0.42, hold], [0.65, guard]], false)


## Rising uppercut (dragon punch): a quick dip, then the rear fist drives straight up past
## the face as the body extends off the ground, lead knee lifting; the fighter itself rises
## (MoveData.rise). At the peak the arm is fully overhead, then the body tucks to fall.
## Impact 0.09 s.
func build_rising_uppercut() -> Animation:
	var s := rear_sign()
	var dip := duplicate_pose(crouch)
	move_bone(dip, "pelvis", Vector3(0, -0.05, 0.0))
	hip_turn(dip, -20.0)
	lean(dip, -8.0, -8.0)
	plant_both(dip, global_origin(crouch, "foot_" + lead), global_origin(crouch, "foot_" + rear))
	var dip_shoulder := global_origin(dip, "upperarm_" + rear)
	reach_arm(dip, rear, Vector3(dip_shoulder.x * 0.6, dip_shoulder.y - 0.35, dip_shoulder.z + 0.25))

	var rise := duplicate_pose(guard)
	move_bone(rise, "pelvis", Vector3(0, 0.04, 0.05))
	hip_turn(rise, 40.0)
	lean(rise, 4.0, 10.0)
	var shoulder := global_origin(rise, "upperarm_" + rear)
	solve_ik(rise, "upperarm_" + rear, "lowerarm_" + rear, "hand_" + rear,
		shoulder + Vector3(-s * 0.12, 0.6, 0.2), Vector3(s * 0.3, 0.0, 1.0))
	var lead_hip := global_origin(rise, "thigh_" + lead)
	solve_ik(rise, "thigh_" + lead, "calf_" + lead, "foot_" + lead,
		lead_hip + Vector3(0, -0.38, 0.3), Vector3(0, 0.3, 1))
	point_foot(rise, lead, Vector3(0, -0.8, 0.4))
	var rear_hip := global_origin(rise, "thigh_" + rear)
	solve_ik(rise, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
		rear_hip + Vector3(0, -0.84, -0.12), Vector3(0, 0, 1))
	point_foot(rise, rear, Vector3(0, -1, 0.25))

	var peak := duplicate_pose(rise)
	lean(peak, 6.0, 0.0)
	shoulder = global_origin(peak, "upperarm_" + rear)
	solve_ik(peak, "upperarm_" + rear, "lowerarm_" + rear, "hand_" + rear,
		shoulder + Vector3(-s * 0.05, 0.66, 0.05), Vector3(s * 0.3, 0.0, 1.0))

	var fall := merge(sample(ual1.get_animation("Jump_Start"), 0.5), guard, arm_bones())

	return make_animation([[0.0, guard], [0.04, dip], [0.09, rise], [0.30, peak],
		[0.48, peak], [0.70, fall]], false)


## Rapid alternating straight punches to the body (Kenji's super): a low, forward stance
## with the hips snapping side to side, a strike roughly every 0.085 s, the fists landing
## at slightly different heights. First impact 0.10 s; ends in a ready pose for the
## follow-up.
func build_punch_flurry() -> Animation:
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)
	var base := duplicate_pose(guard)
	move_bone(base, "pelvis", Vector3(0, -0.05, 0.06))
	lean(base, -6.0, 0.0)
	plant_both(base, lead_foot, rear_foot)
	var keys := [[0.0, guard], [0.05, base]]
	var t := 0.10
	for i in 7:
		var side := lead if i % 2 == 0 else rear
		var strike := duplicate_pose(base)
		hip_turn(strike, -14.0 if side == lead else 18.0)
		plant_both(strike, lead_foot, rear_foot)
		var shoulder := global_origin(strike, "upperarm_" + side)
		var x := -rear_sign() * 0.03 if side == lead else rear_sign() * 0.03
		punch_arm(strike, side, Vector3(x, shoulder.y - 0.12 + 0.05 * (i % 3), shoulder.z + 0.6))
		shoulder_roll(strike, side, 8.0)
		keys.append([t, strike])
		t += 0.085
	keys.append([t + 0.06, base])
	return make_animation(keys, false)


## Machine-gun kicks (Rhea's super): balanced on the lead leg, leaning back, the rear
## knee stays chambered high and the foot snaps out again and again at head, body and
## head-again heights. First impact 0.10 s.
func build_kick_flurry() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var chamber := duplicate_pose(guard)
	move_bone(chamber, "pelvis", Vector3(0, -0.05, 0.06))
	hip_turn(chamber, 25.0)
	lean(chamber, 14.0, 6.0)
	plant_foot(chamber, lead, lead_foot)
	pivot_support_foot(chamber, 30.0, false)
	var hip := global_origin(chamber, "thigh_" + rear)
	solve_ik(chamber, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
		hip + Vector3(s * 0.05, -0.15, 0.35), Vector3(0, 0.6, 1))
	point_foot(chamber, rear, Vector3(0, -0.5, 0.8))
	swing_rear_arm(chamber, 0.5)

	var keys := [[0.0, guard], [0.06, chamber]]
	var heights := [1.35, 1.0, 1.5, 1.15, 1.4, 1.05, 1.45]
	var t := 0.10
	for h: float in heights:
		var strike := duplicate_pose(chamber)
		hip = global_origin(strike, "thigh_" + rear)
		var target := Vector3(hip.x * 0.4, h, hip.z + 0.95)
		solve_ik(strike, "thigh_" + rear, "calf_" + rear, "foot_" + rear, target, Vector3(0, 1, 0.2))
		point_foot(strike, rear, (target - global_origin(strike, "calf_" + rear)).normalized() + Vector3(0, 0.3, 0))
		keys.append([t, strike])
		keys.append([t + 0.04, chamber])
		t += 0.085
	keys.append([t + 0.08, chamber])
	return make_animation(keys, false)


## Rising crescent kick (Rhea's anti-air): springs off the lead leg as the rear leg swings
## straight up in front of the body to above the head, arms flung back. Impact 0.09 s.
func build_rising_kick() -> Animation:
	var s := rear_sign()
	var dip := duplicate_pose(crouch)
	move_bone(dip, "pelvis", Vector3(0, -0.04, 0))
	hip_turn(dip, 15.0)
	plant_both(dip, global_origin(crouch, "foot_" + lead), global_origin(crouch, "foot_" + rear))

	var kick := duplicate_pose(guard)
	move_bone(kick, "pelvis", Vector3(0, 0.03, 0.04))
	hip_turn(kick, 30.0)
	lean(kick, 26.0, 6.0)
	var hip := global_origin(kick, "thigh_" + rear)
	var target := Vector3(hip.x * 0.3, 1.85, hip.z + 0.55)
	solve_ik(kick, "thigh_" + rear, "calf_" + rear, "foot_" + rear, target, Vector3(0, 0.2, 1))
	point_foot(kick, rear, Vector3(0, 1, 0.3))
	var lead_hip := global_origin(kick, "thigh_" + lead)
	solve_ik(kick, "thigh_" + lead, "calf_" + lead, "foot_" + lead,
		lead_hip + Vector3(-s * 0.05, -0.85, -0.1), Vector3(0, 0, 1))
	point_foot(kick, lead, Vector3(0, -1, 0.3))
	swing_rear_arm(kick, 0.9)
	reach_arm(kick, lead, global_origin(kick, "upperarm_" + lead) + Vector3(-s * 0.35, -0.3, -0.2))

	var peak := duplicate_pose(kick)
	lean(peak, 8.0, 0.0)
	var fall := merge(sample(ual1.get_animation("Jump_Start"), 0.5), guard, arm_bones())

	return make_animation([[0.0, guard], [0.04, dip], [0.09, kick], [0.28, peak],
		[0.45, peak], [0.70, fall]], false)


## Ground pound (Brutus's Earthquake): both fists raised overhead with the back arched,
## then a deep squat as the double fist hammers into the canvas in front, sending a
## shockwave along the floor. Impact 0.33 s.
func build_ground_pound() -> Animation:
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)

	var raise := duplicate_pose(guard)
	move_bone(raise, "pelvis", Vector3(0, 0.02, -0.04))
	lean(raise, 14.0, 0.0)
	plant_both(raise, lead_foot, rear_foot)
	var shoulders := (global_origin(raise, "upperarm_l") + global_origin(raise, "upperarm_r")) * 0.5
	var top := shoulders + Vector3(0, 0.5, -0.02)
	for side in ["l", "r"]:
		var x := 0.06 if side == "l" else -0.06
		solve_ik(raise, "upperarm_" + side, "lowerarm_" + side, "hand_" + side, top + Vector3(x, 0, 0), Vector3(x * 4.0, 0.2, -1.0))

	var slam := duplicate_pose(crouch)
	move_bone(slam, "pelvis", Vector3(0, -0.14, 0.08))
	lean(slam, -32.0, 0.0)
	plant_both(slam, lead_foot, rear_foot)
	var floor := Vector3(0, 0.12, 0.62)
	for side in ["l", "r"]:
		var x := 0.06 if side == "l" else -0.06
		solve_ik(slam, "upperarm_" + side, "lowerarm_" + side, "hand_" + side, floor + Vector3(x, 0, 0), Vector3(x * 4.0, 0.3, 0.2))

	var hold := duplicate_pose(slam)
	move_bone(hold, "pelvis", Vector3(0, 0.02, 0))

	return make_animation([[0.0, guard], [0.18, raise], [0.27, raise], [0.33, slam],
		[0.55, hold], [0.85, guard]], false)


## Axe kick (Jin): the straight rear leg swings up past the head, then chops down onto
## the opponent's head/shoulder with the heel; the torso leans back as it rises and
## forward as it drops. Impact 0.30 s (heel at chest height on the way down).
func build_axe_kick() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var raise := duplicate_pose(guard)
	move_bone(raise, "pelvis", Vector3(0, 0.02, 0.06))
	hip_turn(raise, 12.0)
	lean(raise, 18.0, 4.0)
	plant_foot(raise, lead, lead_foot)
	pivot_support_foot(raise, 15.0, true)
	var hip := global_origin(raise, "thigh_" + rear)
	solve_ik(raise, "thigh_" + rear, "calf_" + rear, "foot_" + rear, Vector3(hip.x * 0.4, 2.05, hip.z + 0.45), Vector3(0, 0.3, 1))
	point_foot(raise, rear, Vector3(0, 0.6, 0.8))
	swing_rear_arm(raise, 0.7)

	var chop := duplicate_pose(guard)
	move_bone(chop, "pelvis", Vector3(0, -0.04, 0.12))
	hip_turn(chop, 15.0)
	lean(chop, -12.0, 2.0)
	plant_foot(chop, lead, lead_foot)
	pivot_support_foot(chop, 15.0, false)
	hip = global_origin(chop, "thigh_" + rear)
	solve_ik(chop, "thigh_" + rear, "calf_" + rear, "foot_" + rear, Vector3(hip.x * 0.4, 1.15, hip.z + 0.9), Vector3(0, 1, 0.2))
	point_foot(chop, rear, Vector3(0, -0.3, 1))
	swing_rear_arm(chop, 0.4)

	var land := duplicate_pose(guard)
	move_bone(land, "pelvis", Vector3(0, -0.06, 0.1))
	lean(land, -8.0, 0.0)
	plant_both(land, lead_foot, global_origin(guard, "foot_" + rear) + Vector3(0, 0, 0.55))

	return make_animation([[0.0, guard], [0.18, raise], [0.30, chop], [0.38, chop], [0.52, land], [0.75, guard]], false)


## Spinning back kick (Jin): turns the back to the opponent on the lead foot, looks over
## the shoulder, and drives the rear heel straight back into them (a side-on thrust),
## then completes the turn. Impact 0.22 s.
func build_spin_back_kick() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var turn := duplicate_pose(guard)
	move_bone(turn, "pelvis", Vector3(0, -0.03, 0.04))
	rotate_bone(turn, "pelvis", Vector3.UP, s * 120.0)
	rotate_bone(turn, "neck_01", Vector3.UP, -s * 70.0) # eyes stay on the target
	plant_foot(turn, lead, lead_foot)
	var kick := duplicate_pose(guard)
	move_bone(kick, "pelvis", Vector3(0, -0.02, 0.06))
	rotate_bone(kick, "pelvis", Vector3.UP, s * 175.0)
	rotate_bone(kick, "neck_01", Vector3.UP, -s * 90.0)
	lean(kick, -18.0, 0.0)
	plant_foot(kick, lead, lead_foot)
	var hip := global_origin(kick, "thigh_" + rear)
	solve_ik(kick, "thigh_" + rear, "calf_" + rear, "foot_" + rear, Vector3(hip.x * 0.3, 1.1, hip.z + 1.0), Vector3(0, 1, 0))
	point_foot(kick, rear, Vector3(0, -1.0, 0.1)) # heel leads
	var through := duplicate_pose(guard)
	rotate_bone(through, "pelvis", Vector3.UP, s * 300.0)
	plant_foot(through, lead, lead_foot)
	return make_animation([[0.0, guard], [0.12, turn], [0.22, kick], [0.32, kick], [0.48, through], [0.66, guard]], false)


## Tornado kick (Jin): springs up spinning a full turn, the rear leg swinging round in a
## high crescent as the body rotates; lands back in guard. The fighter rises (MoveData.rise).
## First impact 0.10 s.
func build_tornado_kick() -> Animation:
	var s := rear_sign()
	var keys := [[0.0, guard]]
	var air := merge(sample(ual1.get_animation("Jump_Start"), 0.5), guard, arm_bones())
	var t := 0.06
	for q in range(5):
		var pose := duplicate_pose(air)
		lean(pose, 14.0, 6.0)
		var hip := global_origin(pose, "thigh_" + rear)
		solve_ik(pose, "thigh_" + rear, "calf_" + rear, "foot_" + rear, Vector3(hip.x * 0.3, 1.55, hip.z + 0.85), Vector3(0, 1, 0.2))
		point_foot(pose, rear, Vector3(0, 0.2, 1))
		swing_rear_arm(pose, 0.8)
		rotate_bone(pose, "pelvis", Vector3.UP, -s * (q * 90.0 - 60.0))
		keys.append([t, pose])
		t += 0.07
	keys.append([t + 0.12, air])
	keys.append([t + 0.3, guard])
	return make_animation(keys, false)


## Hurricane kicks (Jin's super): planted on alternate legs, rapid high kicks left, right,
## left... each snapping out to head height, then ends chambered for the axe-kick finisher.
## First impact 0.10 s.
func build_hurricane_kicks() -> Animation:
	var keys := [[0.0, guard]]
	var t := 0.1
	for i in 7:
		var side := rear if i % 2 == 0 else lead
		var other := lead if side == rear else rear
		var pose := duplicate_pose(guard)
		move_bone(pose, "pelvis", Vector3(0, -0.02, 0.05))
		hip_turn(pose, 30.0 if side == rear else -30.0)
		lean(pose, 14.0, 0.0)
		plant_foot(pose, other, global_origin(guard, "foot_" + other))
		var hip := global_origin(pose, "thigh_" + side)
		var target := Vector3(hip.x * 0.4, 1.25 + 0.15 * (i % 3), hip.z + 0.95)
		solve_ik(pose, "thigh_" + side, "calf_" + side, "foot_" + side, target, Vector3(0, 1, 0.2))
		point_foot(pose, side, Vector3(0, 0.3, 1))
		keys.append([t, pose])
		keys.append([t + 0.04, guard])
		t += 0.085
	keys.append([t + 0.08, guard])
	return make_animation(keys, false)


## Spinning lariat (Valka): both arms flung out straight at shoulder height, fists
## clenched, then the whole body spins like a top two full turns on planted feet, leaning
## slightly into the spin. First swing at 0.12 s.
func build_lariat() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)
	var wind := duplicate_pose(guard)
	move_bone(wind, "pelvis", Vector3(0, -0.06, 0))
	hip_turn(wind, -25.0)
	plant_both(wind, lead_foot, rear_foot)
	var keys := [[0.0, guard], [0.08, wind]]
	var t := 0.12
	var turns := 8 # quarter turns: two full spins
	for q in range(turns + 1):
		var pose := duplicate_pose(guard)
		move_bone(pose, "pelvis", Vector3(0, -0.04, 0))
		lean(pose, -6.0, 4.0)
		for side in ["l", "r"]:
			var out := 1.0 if side == "l" else -1.0
			aim(pose, "upperarm_" + side, "lowerarm_" + side, Vector3(out, 0.08, 0.1))
			aim(pose, "lowerarm_" + side, "hand_" + side, Vector3(out, 0.05, 0.12))
		rotate_bone(pose, "pelvis", Vector3.UP, -s * q * 90.0) # the whole body spins
		keys.append([t, pose])
		t += 0.07
	keys.append([t + 0.18, guard])
	return make_animation(keys, false)


## Knee lift (Valka): grab the opponent's head with both hands and drive the rear knee
## up to chest height, pulling down as the hips thrust forward. Impact 0.16 s.
func build_knee_lift() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var clinch := duplicate_pose(guard)
	move_bone(clinch, "pelvis", Vector3(0, -0.02, 0.05))
	lean(clinch, -6.0, 0.0)
	var chest := global_origin(clinch, "spine_03")
	for side in ["l", "r"]:
		var x := 0.12 if side == "l" else -0.12
		reach_arm(clinch, side, Vector3(x, chest.y + 0.1, chest.z + 0.5))

	var strike := duplicate_pose(clinch)
	move_bone(strike, "pelvis", Vector3(0, 0.02, 0.12))
	hip_turn(strike, 15.0)
	lean(strike, -14.0, 0.0)
	plant_foot(strike, lead, lead_foot)
	pivot_support_foot(strike, 15.0, true)
	var hip := global_origin(strike, "thigh_" + rear)
	solve_ik(strike, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
		hip + Vector3(s * 0.02, 0.05, 0.3), Vector3(0, 0.3, 1))
	point_foot(strike, rear, Vector3(0, -1.0, -0.3))
	for side in ["l", "r"]:
		var x := 0.1 if side == "l" else -0.1
		reach_arm(strike, side, Vector3(x, chest.y - 0.05, chest.z + 0.45)) # pulling the head down

	# Knee comes straight back down under the hip (no swing through a kick).
	var recoil := duplicate_pose(clinch)
	plant_foot(recoil, lead, lead_foot)
	hip = global_origin(recoil, "thigh_" + rear)
	solve_ik(recoil, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
		hip + Vector3(0, -0.55, 0.05), Vector3(0, 0.2, 1))
	point_foot(recoil, rear, Vector3(0, -0.6, 0.8))

	return make_animation([[0.0, guard], [0.08, clinch], [0.16, strike], [0.26, strike],
		[0.36, recoil], [0.46, clinch], [0.62, guard]], false)


## Backfist (Mira's Tapik): the lead elbow lifts across the chest with the fist by the
## rear shoulder, then the forearm whips out so the back of the fist snaps into the
## opponent's temple as the lead hip drives in; it comes back along the same arc.
## Impact 0.12 s.
func build_backfist() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)
	var chamber := duplicate_pose(guard)
	hip_turn(chamber, 15.0)
	plant_both(chamber, lead_foot, rear_foot)
	var rear_shoulder := global_origin(chamber, "upperarm_" + rear)
	reach_arm(chamber, lead, rear_shoulder + Vector3(-s * 0.05, -0.08, 0.2))
	shoulder_roll(chamber, lead, 8.0)

	var strike := duplicate_pose(guard)
	move_bone(strike, "pelvis", Vector3(0, -0.02, 0.06))
	hip_turn(strike, -25.0)
	lean(strike, -4.0, 0.0)
	plant_both(strike, lead_foot, rear_foot)
	var lead_shoulder := global_origin(strike, "upperarm_" + lead)
	var fist := Vector3(lead_shoulder.x * 0.6, lead_shoulder.y + 0.05, lead_shoulder.z + 0.62)
	# Elbow up and out to the side: the forearm swings horizontally into the target.
	solve_ik(strike, "upperarm_" + lead, "lowerarm_" + lead, "hand_" + lead, fist, Vector3(-s, 0.4, 0.0))
	shoulder_roll(strike, lead, 12.0)

	return make_animation([[0.0, guard], [0.06, chamber], [0.12, strike], [0.17, strike], [0.32, guard]], false)


## Somersault flip kick (Mira's Sipa Flip and Lawin Rise): a quick dip, then the rear leg
## whips straight up past the opponent's chin as the body throws itself into a backflip,
## knees tucked through the turn, landing in a crouch. Impact 0.12 s (foot in front of
## the face). The flip turns in steps under 180 degrees so the keys interpolate the right
## way round.
func build_flip_kick() -> Animation:
	var s := rear_sign()
	var dip := duplicate_pose(crouch)
	move_bone(dip, "pelvis", Vector3(0, -0.05, 0))
	plant_both(dip, global_origin(crouch, "foot_" + lead), global_origin(crouch, "foot_" + rear))

	var kicks := []
	for k in [[-40.0, 0.12], [-75.0, 0.22]]:
		var kick := duplicate_pose(guard)
		move_bone(kick, "pelvis", Vector3(0, k[1], 0))
		rotate_bone(kick, "pelvis", Vector3.RIGHT, k[0])
		var hip := global_origin(kick, "thigh_" + rear)
		solve_ik(kick, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
			Vector3(hip.x * 0.3, hip.y + 0.72, hip.z + 0.5), Vector3(0, 0, 1))
		point_foot(kick, rear, Vector3(0, 1, 0.4))
		rotate_bone(kick, "thigh_" + lead, Vector3.RIGHT, -45.0)
		rotate_bone(kick, "calf_" + lead, Vector3.RIGHT, 80.0)
		swing_rear_arm(kick, 0.9)
		kicks.append(kick)

	var tucks := []
	for t in [[-150.0, 0.38], [-240.0, 0.40], [-310.0, 0.24]]:
		var tuck := duplicate_pose(guard)
		move_bone(tuck, "pelvis", Vector3(0, t[1], 0))
		rotate_bone(tuck, "pelvis", Vector3.RIGHT, t[0])
		for side in ["l", "r"]:
			rotate_bone(tuck, "thigh_" + side, Vector3.RIGHT, -95.0 if t[0] > -300.0 else -40.0)
			rotate_bone(tuck, "calf_" + side, Vector3.RIGHT, 115.0 if t[0] > -300.0 else 60.0)
		tucks.append(tuck)

	var land := duplicate_pose(crouch)
	move_bone(land, "pelvis", Vector3(0, -0.04, 0))

	return make_animation([[0.0, guard], [0.05, dip], [0.12, kicks[0]], [0.18, kicks[1]],
		[0.26, tucks[0]], [0.34, tucks[1]], [0.42, tucks[2]], [0.50, land], [0.66, guard]], false)


## Dive kick (Mira's Lawin Drop): from the jump the rear leg spears down and forward at
## 45 degrees, foot pointed, the lead knee tucked and the torso leaning back, arms out for
## balance; held all the way down. Impact 0.08 s.
func build_dive_kick() -> Animation:
	var s := rear_sign()
	var air := merge(sample(ual1.get_animation("Jump_Start"), 0.5), guard, arm_bones())
	var kick := duplicate_pose(air)
	hip_turn(kick, 30.0)
	lean(kick, 24.0, 4.0)
	var hip := global_origin(kick, "thigh_" + rear)
	solve_ik(kick, "thigh_" + rear, "calf_" + rear, "foot_" + rear,
		hip + Vector3(-s * 0.05, -0.68, 0.58), Vector3(0, 1, 0.3))
	point_foot(kick, rear, Vector3(0, -0.6, 1))
	var lead_hip := global_origin(kick, "thigh_" + lead)
	solve_ik(kick, "thigh_" + lead, "calf_" + lead, "foot_" + lead,
		lead_hip + Vector3(-s * 0.1, -0.22, -0.06), Vector3(0, 0.2, 1))
	swing_rear_arm(kick, 0.6)
	# The extra key keeps the cubic curve from bulging away from the held pose.
	return make_animation([[0.0, air], [0.08, kick], [0.11, kick], [0.6, kick]], false)


## Focus stance (Mira's Lakas Stance): the feet slide wide into a low horse stance, the
## fists cross in front of the chest, then pull back to the hips with the chest out and
## the chin up as she draws in power; holds, then back to guard. Power peaks at 0.25 s.
func build_focus_stance() -> Animation:
	var s := rear_sign()
	var wide_lead := global_origin(guard, "foot_" + lead) + Vector3(-s * 0.12, 0, 0.04)
	var wide_rear := global_origin(guard, "foot_" + rear) + Vector3(s * 0.12, 0, -0.04)
	var cross := duplicate_pose(guard)
	move_bone(cross, "pelvis", Vector3(0, -0.1, 0))
	plant_both(cross, wide_lead, wide_rear)
	var chest := global_origin(cross, "spine_03")
	reach_arm(cross, "l", chest + Vector3(-0.06, 0.02, 0.32))
	reach_arm(cross, "r", chest + Vector3(0.06, 0.06, 0.30)) # crossed at the wrists

	var power := duplicate_pose(guard)
	move_bone(power, "pelvis", Vector3(0, -0.16, 0))
	lean(power, 10.0, 0.0)
	plant_both(power, wide_lead, wide_rear)
	for side in ["l", "r"]:
		var hip := global_origin(power, "thigh_" + side)
		var x := 0.12 if side == "l" else -0.12
		reach_arm(power, side, hip + Vector3(x, 0.12, -0.08)) # fists at the hips, elbows back
	rotate_bone(power, "neck_01", Vector3.RIGHT, -12.0) # chin up

	return make_animation([[0.0, guard], [0.10, cross], [0.25, power], [0.45, power], [0.60, guard]], false)


## Reversal stance (Lian's Still Water): the weight sinks onto the rear leg, the lead arm
## floats forward at chest height with the palm turned out to meet a strike (tan sau), the
## rear palm guards beside the lead elbow (wu sau). In place by 0.05 s, held, then back
## to the guard.
func build_counter_stance() -> Animation:
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)
	var stance := _counter_pose(lead_foot, rear_foot)
	var settle := duplicate_pose(stance)
	move_bone(settle, "pelvis", Vector3(0, -0.01, -0.01))
	return make_animation([[0.0, guard], [0.05, stance], [0.38, settle], [0.62, guard]], false)


func _counter_pose(lead_foot: Vector3, rear_foot: Vector3) -> Dictionary:
	var s := rear_sign()
	var pose := duplicate_pose(guard)
	move_bone(pose, "pelvis", Vector3(0, -0.07, -0.06)) # sit back
	hip_turn(pose, -12.0)
	lean(pose, 3.0, 0.0)
	plant_both(pose, lead_foot, rear_foot)
	var chest := global_origin(pose, "spine_03")
	punch_arm(pose, lead, Vector3(-s * 0.04, chest.y + 0.12, chest.z + 0.38)) # elbow down, forearm rising
	rotate_bone(pose, "hand_" + lead, Vector3(0, 0, 1), s * 60.0) # palm turned out
	punch_arm(pose, rear, Vector3(-s * 0.01, chest.y + 0.06, chest.z + 0.2))
	rotate_bone(pose, "hand_" + rear, Vector3.RIGHT, -40.0) # palm forward
	return pose


## Chain punches (Wing Chun): upright, square to the opponent, fists thrown straight down
## the centre line one after another, knuckles vertical, each arm retracting under the
## next. A punch every 0.06 s from 0.08 s (`count` of them: 12 for the super, 3 for
## the normal); ends back in the guard.
func build_chain_punch(count: int) -> Animation:
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)
	var base := duplicate_pose(guard)
	move_bone(base, "pelvis", Vector3(0, -0.04, 0.03))
	hip_turn(base, 20.0) # square up
	plant_both(base, lead_foot, rear_foot)
	var chest := global_origin(base, "spine_03")
	var keys := [[0.0, guard], [0.04, base]]
	var t := 0.08
	for i in count:
		var side := lead if i % 2 == 0 else rear
		var other := rear if side == lead else lead
		var strike := duplicate_pose(base)
		move_bone(strike, "pelvis", Vector3(0, 0, 0.015))
		plant_both(strike, lead_foot, rear_foot)
		punch_arm(strike, side, Vector3(0, chest.y - 0.04 + 0.02 * (i % 2), chest.z + 0.55))
		rotate_bone(strike, "hand_" + side, Vector3(0, 0, 1), 80.0 if side == "l" else -80.0) # vertical fist
		punch_arm(strike, other, Vector3(0, chest.y - 0.1, chest.z + 0.2)) # retracting, under the punch
		keys.append([t, strike])
		t += 0.06
	keys.append([t + 0.08, base])
	keys.append([t + 0.2, guard])
	return make_animation(keys, false)


## Reversal throw: the lead hand traps the caught limb and draws it past (0-0.2 s) as the
## hips turn away, then the rear palm drives into the chest (0.42 s, when the opponent is
## released) and the stance recovers.
func build_reversal_throw() -> Animation:
	var s := rear_sign()
	var lead_foot := global_origin(guard, "foot_" + lead)
	var rear_foot := global_origin(guard, "foot_" + rear)
	var catch := _counter_pose(lead_foot, rear_foot)
	var chest := global_origin(catch, "spine_03")
	punch_arm(catch, lead, Vector3(-s * 0.05, chest.y + 0.12, chest.z + 0.45))

	var draw := duplicate_pose(guard)
	move_bone(draw, "pelvis", Vector3(0, -0.09, -0.04))
	hip_turn(draw, -35.0)
	plant_both(draw, lead_foot, rear_foot)
	chest = global_origin(draw, "spine_03")
	reach_arm(draw, lead, Vector3(-s * 0.35, chest.y - 0.15, chest.z + 0.2)) # drawn past the hip
	reach_arm(draw, rear, Vector3(s * 0.05, chest.y - 0.05, chest.z + 0.15)) # chambered palm

	var strike := duplicate_pose(guard)
	move_bone(strike, "pelvis", Vector3(0, -0.08, 0.1))
	hip_turn(strike, 25.0)
	lean(strike, -6.0, 0.0)
	plant_both(strike, lead_foot, rear_foot)
	chest = global_origin(strike, "spine_03")
	punch_arm(strike, rear, Vector3(0, chest.y - 0.04, chest.z + 0.6))
	rotate_bone(strike, "hand_" + rear, Vector3.RIGHT, -55.0) # palm forward
	reach_arm(strike, lead, Vector3(-s * 0.25, chest.y - 0.18, chest.z + 0.12))

	return make_animation([[0.0, catch], [0.2, draw], [0.32, draw], [0.42, strike], [0.62, strike],
		[0.85, guard]], false)


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
