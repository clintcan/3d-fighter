class_name Stage
extends Node3D
## Base for all fight stages. A stage provides spawn points, play-area bounds,
## and its own lighting/environment.

## Fighters are clamped to +/- this distance from the center on X and Z.
@export var bounds_half_extent: float = 3.6
## Narrower limit across the stage (Z), for long thin stages like the train roof.
## Negative = the same as bounds_half_extent.
@export var bounds_depth: float = -1.0


## The Z limit actually in force.
func depth_limit() -> float:
	return bounds_depth if bounds_depth > 0.0 else bounds_half_extent
## Fight music track (a key of Audio.MUSIC).
@export var music: StringName = &"fight"

@onready var p1_spawn: Marker3D = $P1Spawn
@onready var p2_spawn: Marker3D = $P2Spawn

## Ring sides (rope groups "ring_side_0..3": -Z, +Z, -X, +X) hidden when the camera is
## outside them, so near ropes don't cut across the view.
const SIDE_NORMALS := [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
@export var rope_line := 4.4
@export var occlusion_hysteresis := 0.3

var _side_hidden := [false, false, false, false]


func _ready() -> void:
	Settings.apply_graphics_to_stage(self)


func update_camera_occlusion(camera_position: Vector3) -> void:
	for side in SIDE_NORMALS.size():
		var outside: float = camera_position.dot(SIDE_NORMALS[side]) - rope_line
		var hide: bool = outside > occlusion_hysteresis or (_side_hidden[side] and outside > -occlusion_hysteresis)
		if hide == _side_hidden[side]:
			continue
		_side_hidden[side] = hide
		for node in get_tree().get_nodes_in_group(&"ring_side_%d" % side):
			(node as Node3D).visible = not hide
