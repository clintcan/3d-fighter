class_name MoveData
extends Resource
## Frame data for a single attack. All timings are in 60 Hz physics ticks.

enum HitLevel { HIGH, MID, LOW, OVERHEAD }

@export var name: String
## Input notation: "LP", "HP", "LK", "HK", "2LP" (crouching), "6HP" / "4HP" (forward /
## back + button), "j.LP" (airborne). Later: motion inputs like "236P".
@export var input: String
## Clip as "library/name", e.g. "ual1/Punch_Jab" or "fight/front_kick".
@export var animation: StringName
## Time (s) in the clip where the strike lands. Mapped onto the first active frame.
@export var animation_impact: float = 0.2
## Clip time (s) reached at the end of recovery. 0 = clip length.
@export var animation_end: float = 0.0

@export_group("Timing")
## Ticks after the press before the hitbox appears.
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
## Grounded hit trips the defender into a knockdown (sweeps).
@export var knockdown: bool = false
## Forward speed (m/s) given to the attacker when the move starts; friction slows it.
@export var lunge: float = 0.0

@export_group("Hitbox")
## Sphere hitbox. Offset is in the fighter's local space (-Z = toward opponent), or
## relative to `hitbox_bone` once skeletal models are in.
@export var hitbox_bone: StringName
@export var hitbox_radius: float = 0.15
@export var hitbox_offset: Vector3 = Vector3(0, 1.4, -0.8)

@export_group("Flow")
## Move inputs this move can be cancelled into during its active/recovery frames.
@export var cancel_into: Array[String] = []
## Extra intensity added to the action camera when this move lands.
@export var camera_intensity: float = 0.0


func total_frames() -> int:
	return startup + active + recovery
