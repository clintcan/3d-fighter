class_name MoveData
extends Resource
## Frame data for a single attack. All timings are in 60 Hz physics ticks.

enum HitLevel { HIGH, MID, LOW, OVERHEAD }

@export var name: String
## Input notation, e.g. "LP", "HP", "LK", "HK", "2LP" (crouching), later "236P".
@export var input: String
@export var animation: StringName

@export_group("Timing")
@export var startup: int = 5
@export var active: int = 3
@export var recovery: int = 10

@export_group("On Hit")
@export var damage: int = 50
@export var hit_level: HitLevel = HitLevel.MID
@export var hitstun: int = 15
@export var blockstun: int = 10
@export var hitstop: int = 6
## (along fight axis, vertical) in meters per second.
@export var knockback: Vector2 = Vector2(1.5, 0.0)
@export var launches: bool = false

@export_group("Hitbox")
@export var hitbox_bone: StringName
@export var hitbox_size: Vector3 = Vector3(0.25, 0.25, 0.25)
@export var hitbox_offset: Vector3 = Vector3.ZERO

@export_group("Flow")
## Move inputs this move can be cancelled into during its active/recovery frames.
@export var cancel_into: Array[String] = []
## Extra intensity added to the action camera when this move lands.
@export var camera_intensity: float = 0.0


func total_frames() -> int:
	return startup + active + recovery
