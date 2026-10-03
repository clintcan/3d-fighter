class_name MoveData
extends Resource
## Frame data for a single attack. All timings are in 60 Hz physics ticks.

enum HitLevel { HIGH, MID, LOW, OVERHEAD }

@export var name: String
## Input notation: "LP", "HP", "LK", "HK", "2LP" (crouching), "6HP" / "4HP" (forward /
## back + button), "j.LP" (airborne). Specials use a motion plus P (either punch) or K
## (either kick): "236P" (quarter-circle forward), "623P", "214K", "236236P" (super).
## Inputs starting with "~" are follow-ups, reachable only through `followup`.
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
## Chip damage dealt through a block (specials and supers).
@export var chip_damage: int = 0

@export_group("Special")
## Hits per move instance (multi-hit moves); a new hit can land every `hit_interval`
## ticks during the active frames. Launch/knockdown apply on the final hit only.
@export var hits: int = 1
@export var hit_interval: int = 4
## Forward speed (m/s) held during the active frames until the move connects.
@export var travel: float = 0.0
## Upward speed (m/s) applied on the first active frame (rising anti-airs).
@export var rise: float = 0.0
## Extra landing frames after a rising move comes back down.
@export var landing_recovery: int = 0
## The move has no hurtbox (and can't be thrown) through this frame.
@export var invuln_frames: int = 0
## Hurtbox lowered to crouch height for the whole move (slides).
@export var low_profile: bool = false
## Spends a full super meter and starts with the super freeze.
@export var super_move: bool = false
## Move started automatically when this one ends after connecting (hit or block).
@export var followup: String = ""
## Projectile fired on the first active frame instead of a body hitbox.
@export var projectile_speed: float = 0.0
@export var projectile_lifetime: int = 90
@export var projectile_color: Color = Color(0.4, 0.75, 1.0)
## Cosmetic effect when the move becomes active ("shockwave" = ground-pound ring and
## dust). Trails, rising sparks and projectile flashes come from the move's own data.
@export var impact_fx: StringName = &""
## Command grab: on its first active frame it grabs an opponent within `grab_range`
## (unblockable, can't be teched; damage = this move's damage). A whiff plays out the
## move's recovery.
@export var command_grab: bool = false
@export var grab_range: float = 1.0
## Projectiles pass through the fighter during this move's startup and active frames.
@export var projectile_immune: bool = false

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


## Motion part of a special input ("236" of "236P"), or "" for normals.
func motion() -> String:
	var digits := ""
	for c in input:
		if not c.is_valid_int():
			break
		digits += c
	return digits if digits.length() >= 3 else ""


func is_special() -> bool:
	return motion() != ""
