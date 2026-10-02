class_name ActionCamera
extends Camera3D
## Milestone 2: neutral framing only. Views the fight from the side (FightManager.view_dir)
## and zooms with fighter distance. Intensity-driven orbit/dolly/shake is milestone 6
## (CLAUDE.md §6).

@export var height := 2.3
@export var look_height := 1.0
@export var min_distance := 4.5
@export var base_distance := 3.0
@export var distance_per_meter := 0.75
## How much fighters' jump height lifts the framing.
@export var vertical_follow := 0.3
@export var follow_speed := 6.0

var manager: Node
var _look_target := Vector3.ZERO


func setup(fight_manager: Node) -> void:
	manager = fight_manager
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	snap()


func snap() -> void:
	var targets := _compute_targets()
	position = targets[0]
	_look_target = targets[1]
	look_at(_look_target)


func _process(delta: float) -> void:
	if manager == null:
		return
	var targets := _compute_targets()
	var t := 1.0 - exp(-follow_speed * delta)
	position = position.lerp(targets[0], t)
	_look_target = _look_target.lerp(targets[1], t)
	look_at(_look_target)


## Returns [camera_position, look_target].
func _compute_targets() -> Array[Vector3]:
	var a: Vector3 = manager.fighters[0].get_global_transform_interpolated().origin
	var b: Vector3 = manager.fighters[1].get_global_transform_interpolated().origin
	var mid := (a + b) * 0.5
	var lift := mid.y * vertical_follow
	mid.y = 0.0
	var separation := Vector2(b.x - a.x, b.z - a.z).length()
	var distance := maxf(min_distance, base_distance + separation * distance_per_meter)
	var view_dir: Vector3 = manager.view_dir
	return [
		mid + view_dir * distance + Vector3.UP * (height + lift),
		mid + Vector3.UP * (look_height + lift),
	]
