class_name ActionCamera
extends Camera3D
## The dynamic fight camera (CLAUDE.md §6). Neutral framing is side-on to the fight axis
## (FightManager.view_dir). Hits build `intensity`; as it rises the camera orbits behind
## the attacker's shoulder, dollies in, drops to a low angle, narrows its FOV and aims at
## the fighter being hit, so a combo victim is shown prominently. Both fighters are
## always kept in frame. Purely visual: nothing here feeds back into gameplay.

enum Mode { OFF, SUBTLE, FULL }
const MODE_NAMES := ["Off", "Subtle", "Full"]
const MODE_SCALES := [0.0, 0.5, 1.0]

@export_group("Neutral framing")
@export var height := 2.3
@export var look_height := 1.0
@export var min_distance := 4.5
@export var base_distance := 3.0
@export var distance_per_meter := 0.75
## How much fighters' jump height lifts the framing.
@export var vertical_follow := 0.3
@export var base_fov := 45.0
@export var follow_speed := 6.0

@export_group("Action response (at full intensity)")
@export var max_orbit_degrees := 35.0
## Fraction of the framing distance removed.
@export var dolly_in := 0.2
## Camera height at full intensity (lower = more heroic angle on the victim).
@export var action_height := 1.4
@export var action_fov := 40.0
## How far the aim point moves from the midpoint to the victim's chest.
@export var max_focus_weight := 0.65
@export var chest_height := 1.15
## Fraction of the half-FOV both fighters must stay inside.
@export var frame_margin := 0.9

@export_group("Intensity")
@export var base_hit_gain := 0.15
@export var combo_gain := 0.05
@export var counter_gain := 0.15
@export var launch_gain := 0.25
@export var throw_gain := 0.45
@export var block_gain := 0.03
## Decay per second while the victim is still in hitstun / airborne, and once they're free.
@export var stunned_decay := 0.25
@export var free_decay := 0.9
## Smoothing rates for the visible response: snappy into action, slow back to neutral.
@export var rise_speed := 8.0
@export var fall_speed := 2.0

@export_group("Shake")
@export var max_shake_offset := 0.12
@export var max_shake_roll_degrees := 3.0
@export var trauma_decay := 1.6
@export var shake_frequency := 25.0

## Momentary FOV narrowing on heavy hits (degrees at full punch), decaying quickly.
@export var fov_punch_degrees := 3.0
@export var fov_punch_decay := 6.0

@export_group("KO slow motion")
@export var ko_time_scale := 0.3
@export var ko_slowmo_seconds := 0.6

var manager: Node
var mode: Mode = Mode.FULL
## When > 0, used instead of the viewport's aspect ratio for frame fitting (headless tests).
var aspect_override := 0.0
## 0..1, raised by hits and decaying over time.
var intensity := 0.0
## The fighter the camera is featuring (most recently hit), or null.
var focus: Fighter

var _strength := 0.0 # smoothed, mode-scaled intensity actually applied
var _trauma := 0.0
var _base_position := Vector3.ZERO
var _look_target := Vector3.ZERO
var _noise := FastNoiseLite.new()
var _noise_time := 0.0
var _fov_punch := 0.0
var _base_fov := 45.0


func setup(fight_manager: Node) -> void:
	manager = fight_manager
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	manager.hit_landed.connect(_on_hit_landed)
	manager.throw_landed.connect(_on_throw_landed)
	for fighter: Fighter in manager.fighters:
		fighter.knocked_out.connect(_on_knocked_out)
	snap()


## Jumps to neutral framing and clears all action state (round start / reset).
func snap() -> void:
	intensity = 0.0
	_strength = 0.0
	_trauma = 0.0
	_fov_punch = 0.0
	focus = null
	Engine.time_scale = 1.0
	var targets := _compute_targets(0.0)
	_base_position = targets.position
	_look_target = targets.look
	_base_fov = targets.fov
	fov = targets.fov
	_apply_transform(0.0, 0.0)


func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode


func mode_name() -> String:
	return MODE_NAMES[mode]


func _process(scaled_delta: float) -> void:
	if manager == null:
		return
	# Run on real time so the camera keeps moving smoothly through KO slow motion.
	var delta := scaled_delta / maxf(Engine.time_scale, 0.01)
	_update_intensity(delta)
	var strength := _fit_strength(_strength)
	var targets := _compute_targets(strength)
	var t := 1.0 - exp(-follow_speed * delta)
	_base_position = _base_position.lerp(targets.position, t)
	_look_target = _look_target.lerp(targets.look, t)
	_fov_punch = move_toward(_fov_punch, 0.0, fov_punch_decay * delta)
	_base_fov = lerpf(_base_fov, targets.fov, t)
	fov = _base_fov - fov_punch_degrees * _fov_punch

	_trauma = move_toward(_trauma, 0.0, trauma_decay * delta)
	_noise_time += delta * shake_frequency
	_apply_transform(_trauma, _noise_time)
	if manager.stage:
		manager.stage.update_camera_occlusion(global_position)


# --- Intensity -------------------------------------------------------------------

func _on_hit_landed(_attacker: Fighter, defender: Fighter, move: MoveData, result: Fighter.HitResult) -> void:
	if result == Fighter.HitResult.BLOCKED:
		intensity = minf(intensity + block_gain, 1.0)
		_add_trauma(clampf((move.hitstop - 6) * 0.03, 0.0, 0.15))
		return
	focus = defender
	var gain := base_hit_gain + move.camera_intensity + combo_gain * maxi(defender.combo_hits - 1, 0)
	if result == Fighter.HitResult.COUNTER:
		gain += counter_gain
	if move.launches or move.knockdown:
		gain += launch_gain
	intensity = minf(intensity + gain, 1.0)
	_add_trauma(clampf((move.hitstop - 4) * 0.06, 0.0, 0.5))
	if move.hitstop >= 8 or result == Fighter.HitResult.COUNTER:
		_fov_punch = MODE_SCALES[mode]


func _on_throw_landed(_attacker: Fighter, defender: Fighter) -> void:
	focus = defender
	intensity = minf(intensity + throw_gain, 1.0)
	_add_trauma(0.2)


func _on_knocked_out(loser: Fighter) -> void:
	focus = loser
	intensity = 1.0
	_add_trauma(0.7)
	_fov_punch = MODE_SCALES[mode]
	if mode != Mode.OFF:
		Engine.time_scale = ko_time_scale
		get_tree().create_timer(ko_slowmo_seconds, true, false, true).timeout.connect(
			func() -> void: Engine.time_scale = 1.0)


func _add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount * MODE_SCALES[mode], 1.0)


func _update_intensity(delta: float) -> void:
	var stunned := focus != null and focus.state in [Fighter.State.HITSTUN, Fighter.State.AIR_HIT,
		Fighter.State.THROWN, Fighter.State.KO]
	intensity = move_toward(intensity, 0.0, (stunned_decay if stunned else free_decay) * delta)
	var target: float = smoothstep(0.1, 1.0, intensity) * MODE_SCALES[mode]
	var rate := rise_speed if target > _strength else fall_speed
	_strength = lerpf(_strength, target, 1.0 - exp(-rate * delta))


# --- Framing ---------------------------------------------------------------------

## Camera position, aim point and FOV for a given action strength (0 = neutral).
func _compute_targets(strength: float) -> Dictionary:
	var a := _fighter_position(0)
	var b := _fighter_position(1)
	var mid := (a + b) * 0.5
	var lift := mid.y * vertical_follow
	mid.y = 0.0
	var separation := Vector2(b.x - a.x, b.z - a.z).length()
	var distance := maxf(min_distance, base_distance + separation * distance_per_meter)
	var dir: Vector3 = manager.view_dir
	var look := mid + Vector3.UP * (look_height + lift)
	var cam_height := height
	var cam_fov := base_fov

	if focus and strength > 0.0:
		# Swing around the midpoint toward the attacker's back, revealing the victim's front.
		var attacker_forward := focus.opponent.forward
		var orbit := deg_to_rad(max_orbit_degrees) * strength
		dir = (dir * cos(orbit) - attacker_forward * sin(orbit)).normalized()
		distance *= 1.0 - dolly_in * strength
		var victim := focus.get_global_transform_interpolated().origin
		look = look.lerp(victim + Vector3.UP * chest_height, max_focus_weight * strength)
		cam_height = lerpf(height, action_height, strength)
		cam_fov = lerpf(base_fov, action_fov, strength)

	return {
		position = mid + dir * distance + Vector3.UP * (cam_height + lift),
		look = look,
		fov = cam_fov,
	}


## Largest strength (<= requested) at which both fighters stay inside the frame margin.
func _fit_strength(requested: float) -> float:
	var strength := requested
	for i in 8:
		if strength <= 0.01 or _both_fighters_visible(_compute_targets(strength)):
			return strength
		strength *= 0.75
	return 0.0


func _both_fighters_visible(targets: Dictionary) -> bool:
	var view_basis := Basis.looking_at(targets.look - targets.position)
	var inverse := view_basis.inverse()
	var tan_v := tan(deg_to_rad(targets.fov) * 0.5) * frame_margin
	var aspect := aspect_override if aspect_override > 0.0 else get_viewport().get_visible_rect().size.aspect()
	var tan_h := tan_v * aspect
	for i in 2:
		var origin := _fighter_position(i)
		for point in [origin + Vector3.UP * 0.1, origin + Vector3.UP * Fighter.STAND_HEIGHT]:
			var local: Vector3 = inverse * (point - targets.position)
			var depth := -local.z
			if depth < near or absf(local.x) > tan_h * depth or absf(local.y) > tan_v * depth:
				return false
	return true


func _fighter_position(index: int) -> Vector3:
	return (manager.fighters[index] as Fighter).get_global_transform_interpolated().origin


func _apply_transform(trauma: float, noise_time: float) -> void:
	look_at_from_position(_base_position, _look_target)
	if trauma <= 0.0:
		return
	var shake := trauma * trauma
	var offset := Vector3(_noise.get_noise_2d(noise_time, 0.0), _noise.get_noise_2d(0.0, noise_time), 0.0)
	global_position += global_basis * (offset * max_shake_offset * shake)
	rotate_object_local(Vector3.FORWARD, deg_to_rad(max_shake_roll_degrees) * shake * _noise.get_noise_2d(noise_time, noise_time))
