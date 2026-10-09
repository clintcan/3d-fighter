class_name LimbTrail
extends MeshInstance3D
## A short fading ribbon along the path of the striking hand or foot of a heavy attack,
## special or super, so fast strikes read at fight distance. Cosmetic: FightFx calls
## update() every frame; it reads the fighter and its skeleton, never writes them.
##
## The limb is whichever fist or foot is nearest the move's hitbox. The ribbon faces the
## camera (a straight punch, moving along its own arm, still shows) and tapers as it ages.
## It stops ageing during hitstop and the super freeze, so the swoosh hangs in the air
## through the impact. A flurry that switches limbs starts a new strip.

const LIFE := 0.16 # seconds a sample stays visible (not counting hitstop)
const LEAD_FRAMES := 8 # starts this many frames before the active frames (the wind-up)...
const TAIL_FRAMES := 3 # ...and ends this many after
const ALPHA := 0.75
const HEAVY_HITSTOP := 8 # normals with at least this much hitstop get a trail
const SUPER_COLOR := Color(1.0, 0.82, 0.3) # supers and their finishers (FightFx's gold)
## [bone, ribbon width (m)]: fists, then the balls of the feet.
const LIMBS := [["hand_l", 0.1], ["hand_r", 0.1], ["ball_l", 0.13], ["ball_r", 0.13]]
const MIN_STEP := 0.004 # a sample closer than this to the last one isn't added

var fighter: Fighter
var color := Color.WHITE
var _skeleton: Skeleton3D
var _bones: Array[int] = []
var _samples: Array = [] # [position, age, strip, colour, width]
var _strip := 0
var _limb := -1
var _mesh := ImmediateMesh.new()


func _init(owner_fighter: Fighter, trail_color: Color) -> void:
	fighter = owner_fighter
	color = trail_color
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # additive washed out on bright skies
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material
	_skeleton = fighter.model.skeleton if fighter.model else null
	if _skeleton:
		for limb: Array in LIMBS:
			_bones.append(_skeleton.find_bone(limb[0]))


## True if `move` gets a trail: a strike (not a projectile, grab or stance) that's heavy,
## special or a super.
static func wants(move: MoveData) -> bool:
	if move == null or move.hitbox_radius <= 0.0 or move.projectile_speed > 0.0 or move.command_grab:
		return false
	return move.hitstop >= HEAVY_HITSTOP or move.is_special() or move.input.begins_with("~")


func update(delta: float) -> void:
	var held := fighter.hitstop > 0 or fighter.frozen
	if not held:
		for sample: Array in _samples:
			sample[1] += delta
		while not _samples.is_empty() and _samples[0][1] > LIFE:
			_samples.pop_front()
	if _skeleton and not held and _sampling():
		var skeleton_xform := _skeleton.get_global_transform_interpolated()
		var move := fighter.current_move
		var hitbox: Vector3 = fighter.get_global_transform_interpolated() * move.hitbox_offset
		var nearest := 0
		var best := INF
		for i in _bones.size():
			var d := (skeleton_xform * _skeleton.get_bone_global_pose(_bones[i]).origin).distance_to(hitbox)
			if d < best:
				best = d
				nearest = i
		if nearest != _limb:
			_limb = nearest
			_strip += 1
		var tip := skeleton_xform * _skeleton.get_bone_global_pose(_bones[nearest]).origin
		var last: Array = _samples[-1] if not _samples.is_empty() else []
		if last.is_empty() or last[2] != _strip or (last[0] as Vector3).distance_to(tip) > MIN_STEP:
			var tint := SUPER_COLOR if move.super_move or move.input.begins_with("~") else color
			_samples.append([tip, 0.0, _strip, tint, LIMBS[nearest][1]])
	elif not held:
		_limb = -1
	_draw()


func _sampling() -> bool:
	if fighter.state != Fighter.State.ATTACK or not wants(fighter.current_move):
		return false
	var move := fighter.current_move
	return fighter.state_frame >= move.startup - LEAD_FRAMES and fighter.state_frame <= move.startup + move.active + TAIL_FRAMES


func _draw() -> void:
	_mesh.clear_surfaces()
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or _samples.size() < 2:
		return
	var eye := camera.global_position
	var vertices: Array = [] # [position, colour]
	for i in range(1, _samples.size()):
		var a: Array = _samples[i - 1]
		var b: Array = _samples[i]
		if a[2] != b[2]:
			continue # a new strip: don't bridge two limbs
		var pa: Vector3 = a[0]
		var pb: Vector3 = b[0]
		var side := (pb - pa).cross(eye - pb).normalized()
		if not side.is_finite() or side == Vector3.ZERO:
			continue
		var life_a: float = 1.0 - a[1] / LIFE
		var life_b: float = 1.0 - b[1] / LIFE
		var wa: float = a[4] * 0.5 * life_a
		var wb: float = b[4] * 0.5 * life_b
		var ca := Color(a[3], pow(life_a, 1.5) * ALPHA)
		var cb := Color(b[3], pow(life_b, 1.5) * ALPHA)
		vertices.append_array([[pa + side * wa, ca], [pa - side * wa, ca], [pb - side * wb, cb],
			[pa + side * wa, ca], [pb - side * wb, cb], [pb + side * wb, cb]])
	if vertices.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Array in vertices:
		_mesh.surface_set_color(v[1])
		_mesh.surface_add_vertex(v[0])
	_mesh.surface_end()
