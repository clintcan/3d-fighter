class_name TrainMotion
extends Node3D
## Makes the train stage move: the train stays put and the world streams past it. Every
## scenery material (assets/stages/train/scenery.gdshader, ground.gdshader) gets the
## distance travelled as `scroll`; trees and telegraph poles are MultiMesh instances laid
## out here at runtime (headless tools lose MultiMesh instance data) over one loop
## `period`, which the shader wraps. Also runs the occasional train passing the other
## way on the second line. Cosmetic only: real time (slowed by the K.O. slow motion,
## stopped by the pause menu), never the simulation, its own RNG.

## Train speed in m/s (about 95 km/h).
@export var speed := 26.0
## Every material with a `scroll` parameter.
@export var materials: Array[ShaderMaterial] = []
## Trees: low-poly meshes (vertex coloured), drawn with `tree_material`.
@export var tree_meshes: Array[Mesh] = []
@export var tree_material: ShaderMaterial
@export var tree_count := 420
## Telegraph poles (one span of wire each) along the far side of the other line.
@export var pole_mesh: Mesh
@export var pole_material: ShaderMaterial
@export var pole_spacing := 40.0
@export var pole_z := -7.6
## Where the scenery stands: the ground under the track.
@export var ground_y := -4.35
## The train that passes the other way on the second line (hidden between passes).
@export var passing_train: Node3D
@export var passing_interval := Vector2(18.0, 32.0)
@export var passing_speed := 30.0 # its own speed (the closing speed is the sum)
@export var passing_length := 130.0
@export var passing_sound: AudioStreamPlayer3D

## Scroll wraps here: every tiling and loop period in the shaders divides it.
const WRAP := 2400.0
const SCENERY_PERIOD := 480.0

var travelled := 0.0
var _rng := RandomNumberGenerator.new()
var _passing_x := INF
var _next_pass := 0.0
var _time := 0.0


func _ready() -> void:
	_rng.seed = 7071 # the same countryside every time
	_build_trees()
	_build_poles()
	_rng.randomize() # passing trains: different every match
	_next_pass = _rng.randf_range(6.0, 12.0)
	if passing_train:
		passing_train.visible = false


func _process(delta: float) -> void:
	_time += delta
	travelled = fmod(travelled + speed * delta, WRAP)
	for material in materials:
		material.set_shader_parameter("scroll", travelled)
	_update_passing(delta)


func _build_trees() -> void:
	if tree_meshes.is_empty() or tree_material == null:
		return
	var per_mesh: Array[Array] = []
	for i in tree_meshes.size():
		per_mesh.append([])
	# Copses on the far side (thick near the line, thinning out), a few behind the camera.
	var placed := 0
	while placed < tree_count:
		var far := _rng.randf() < 0.85
		var center := Vector3(_rng.randf_range(-SCENERY_PERIOD, SCENERY_PERIOD) * 0.5, ground_y,
			-_rng.randf_range(18.0, 160.0) * (1.0 if far else -1.0))
		if not far:
			center.z = _rng.randf_range(16.0, 90.0)
		var cluster := _rng.randi_range(2, 9)
		for i in cluster:
			if placed == tree_count:
				break
			var p := center + Vector3(_rng.randf_range(-9.0, 9.0), 0.0, _rng.randf_range(-6.0, 6.0))
			if p.z > -16.0 and p.z < 16.0:
				continue # keep the line and the camera side clear
			var s := _rng.randf_range(0.75, 1.45)
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.85, 1.2), s))
			per_mesh[_rng.randi() % tree_meshes.size()].append(Transform3D(basis, p))
			placed += 1
	for i in tree_meshes.size():
		_multimesh(tree_meshes[i], tree_material, per_mesh[i], "Trees%d" % i)


func _build_poles() -> void:
	if pole_mesh == null or pole_material == null:
		return
	var xforms: Array = []
	var count := int(SCENERY_PERIOD / pole_spacing)
	for i in count:
		xforms.append(Transform3D(Basis(), Vector3(-SCENERY_PERIOD * 0.5 + i * pole_spacing, ground_y, pole_z)))
	_multimesh(pole_mesh, pole_material, xforms, "Poles", GeometryInstance3D.SHADOW_CASTING_SETTING_ON) # poles and wires flick shadows over the line


func _multimesh(mesh: Mesh, material: Material, xforms: Array, node_name: String, cast_shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = mm
	instance.material_override = material
	# The shader moves every instance, so culling by the laid-out bounds would be wrong.
	instance.custom_aabb = AABB(Vector3(-SCENERY_PERIOD, -20.0, -200.0), Vector3(SCENERY_PERIOD * 2.0, 80.0, 400.0))
	instance.cast_shadow = cast_shadows
	add_child(instance)


## Every so often a train roars past the other way, behind the fight.
func _update_passing(delta: float) -> void:
	if passing_train == null:
		return
	if _passing_x == INF:
		if _time >= _next_pass:
			_passing_x = 140.0 # its nose (the node origin; the cars trail toward +X) starts well ahead
			passing_train.visible = true
			if passing_sound:
				passing_sound.play()
		return
	_passing_x -= (speed + passing_speed) * delta
	passing_train.position.x = _passing_x
	if _passing_x < -140.0 - passing_length: # its last car is well behind us
		passing_train.visible = false
		_passing_x = INF
		_next_pass = _time + _rng.randf_range(passing_interval.x, passing_interval.y)
