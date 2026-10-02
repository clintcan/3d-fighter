class_name FighterModel
extends Node3D
## Skinned character visual for a Fighter. Built from CharacterData (body, skin texture,
## hair pieces) and driven by the fighter's logic each frame: logic picks the clip and,
## for timed clips, the exact playback time. The animation never drives gameplay.

const LIBRARIES := {
	&"ual1": preload("res://assets/animations/UAL1_Standard.glb"),
	&"ual2": preload("res://assets/animations/UAL2_Standard.glb"),
	&"fight": preload("res://assets/animations/fight_anims.res"),
}
const BLEND_TIME := 0.08
## Bones whose lowest point must stay above the floor, with the distance from each bone
## to the sole measured in the rest pose (filled in build()).
const CONTACT_BONES := [&"foot_l", &"foot_r", &"ball_l", &"ball_r"]
const SOLE_BELOW_ORIGIN := 0.01

var skeleton: Skeleton3D
var player: AnimationPlayer
var _body: Node3D
var _clip: StringName
var _contacts := {} # bone index -> rest height above the sole


func build(data: CharacterData) -> void:
	var body := data.model_scene.instantiate() as Node3D
	_body = body
	add_child(body)
	# glTF models face +Z; fighters face -Z.
	body.rotation.y = PI
	scale = Vector3.ONE * data.model_scale

	skeleton = body.find_child("Skeleton3D") as Skeleton3D
	for bone_name: StringName in CONTACT_BONES:
		var bone := skeleton.find_bone(bone_name)
		# The rest-pose sole sits ~1 cm below the origin.
		_contacts[bone] = skeleton.get_bone_global_rest(bone).origin.y + SOLE_BELOW_ORIGIN
	for hair_scene in data.hair_scenes:
		_attach_skinned(hair_scene)
	_customize_materials(data)

	player = AnimationPlayer.new()
	body.add_child(player)
	player.root_node = player.get_path_to(body)
	for library_name: StringName in LIBRARIES:
		player.add_animation_library(library_name, LIBRARIES[library_name])
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func clip_length(clip: StringName) -> float:
	return player.get_animation(clip).length if player.has_animation(clip) else 1.0


## Shows `clip`. With time >= 0 the clip is posed at that exact time (timed clips such as
## attacks); otherwise it free-runs at `speed` (loops such as idle and walk).
func show_clip(clip: StringName, time: float, speed: float, delta: float) -> void:
	if not player.has_animation(clip):
		push_warning("Missing animation clip: %s" % clip)
		return
	if clip != _clip:
		_clip = clip
		player.play(clip, BLEND_TIME)
	if time >= 0.0:
		# Seek just short of the target and advance onto it, so cross-fades still progress.
		var target := minf(time, player.current_animation_length)
		player.speed_scale = 1.0
		player.seek(maxf(target - delta, 0.0), false)
		player.advance(minf(delta, target))
	else:
		player.speed_scale = speed
		player.advance(delta)
	_keep_feet_above_floor()


## The UAL clips were authored for slightly different proportions and sink these bodies'
## feet a few cm into the floor. Lift the body so the lowest sole sits on the floor.
## Only ever lifts, so jumps and other airborne poses are unaffected.
func _keep_feet_above_floor() -> void:
	var lowest := INF
	for bone: int in _contacts:
		lowest = minf(lowest, skeleton.get_bone_global_pose(bone).origin.y - _contacts[bone])
	_body.position.y = maxf(-lowest, 0.0)


func _attach_skinned(scene: PackedScene) -> void:
	# Hair pieces are rigged to the same skeleton (Head bone). Move their meshes onto our
	# skeleton; skins bind by bone name.
	var piece := scene.instantiate()
	for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		mesh.owner = null
		mesh.get_parent().remove_child(mesh)
		skeleton.add_child(mesh)
		mesh.skeleton = mesh.get_path_to(skeleton)
	piece.free()


## Swaps the body's skin texture and tints hair, working on per-instance material copies.
func _customize_materials(data: CharacterData) -> void:
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.get_surface_override_material_count():
			var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null:
				continue
			if material.resource_name.begins_with("MI_Superhero") and data.body_albedo:
				var skin := material.duplicate() as StandardMaterial3D
				skin.albedo_texture = data.body_albedo
				mesh.set_surface_override_material(surface, skin)
			elif material.resource_name.begins_with("MI_Hair"):
				var hair := material.duplicate() as StandardMaterial3D
				hair.albedo_color = data.hair_color
				mesh.set_surface_override_material(surface, hair)
