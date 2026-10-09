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

@export_group("Victory cinematic")
## Shot 1: wide low-angle orbit around the winner. Shot 2 (after a hard cut): 3/4 front
## push-in to a close-up, then a slow drift. Angles are measured from the winner's facing.
@export var victory_shot1_seconds := 1.5
@export var victory_shot2_seconds := 2.0
@export var victory_drift_degrees_per_second := 4.0

@export_group("Super flash")
## Close-up on the fighter starting a super, held through the super freeze (real time).
@export var super_seconds := 0.75
@export var super_distance := 2.7
@export var super_fov := 36.0
## How far the shot swings from the side view toward the fighter's front (0..1). Kept
## small so the opponent, standing in front, doesn't block the shot.
@export var super_front := 0.25

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
## Match-winner being filmed by the victory cinematic, or null during the fight.
var victory_target: Fighter
var _victory_time := 0.0
var _victory_side := 1.0
var _victory_cut := false
var _super_fighter: Fighter
var _super_time := 0.0
## Fighter featured by the pre-fight intro (FightIntro), or null.
var intro_target: Fighter
var _intro_time := 0.0


func setup(fight_manager: Node) -> void:
	manager = fight_manager
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	manager.hit_landed.connect(manager.cosmetic(_on_hit_landed))
	manager.throw_landed.connect(manager.cosmetic(_on_throw_landed))
	for fighter: Fighter in manager.fighters:
		fighter.knocked_out.connect(manager.cosmetic(_on_knocked_out))
	snap()


## Jumps to neutral framing and clears all action state (round start / reset).
func snap() -> void:
	intensity = 0.0
	_strength = 0.0
	_trauma = 0.0
	_fov_punch = 0.0
	focus = null
	victory_target = null
	intro_target = null
	_super_time = 0.0
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
	if victory_target:
		_process_victory(delta)
		return
	if intro_target:
		_process_intro(delta)
		return
	_update_intensity(delta)
	var strength := _fit_strength(_strength)
	var targets := _compute_targets(strength)
	var speed := follow_speed
	if _super_time > 0.0:
		_super_time -= delta
		targets = _super_targets()
		speed = 9.0
	var t := 1.0 - exp(-speed * delta)
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


# --- Super flash -------------------------------------------------------------------

## Swings in to a low close-up of `fighter` for the super freeze, then eases back.
func start_super(fighter: Fighter) -> void:
	if mode == Mode.OFF:
		return
	_super_fighter = fighter
	_super_time = super_seconds
	_add_trauma(0.25)


func _super_targets() -> Dictionary:
	var chest := _super_fighter.get_global_transform_interpolated().origin + Vector3.UP * 1.2
	var side: Vector3 = manager.view_dir
	var dir := (side * (1.0 - super_front) + _super_fighter.forward * super_front).normalized()
	return {
		position = chest + dir * super_distance + Vector3.UP * 0.15,
		look = chest + _super_fighter.forward * 0.35,
		fov = super_fov,
	}


# --- Pre-fight intro ----------------------------------------------------------------

## Cuts to a 3/4 front shot of `fighter` that pushes in toward a close-up (FightIntro).
## snap() ends it.
func start_intro(fighter: Fighter) -> void:
	intro_target = fighter
	_intro_time = 0.0
	var shot := _intro_shot(0.0)
	_base_position = shot.position
	_look_target = shot.look
	_base_fov = shot.fov


func _process_intro(delta: float) -> void:
	_intro_time += delta
	var shot := _intro_shot(_intro_time)
	var t := 1.0 - exp(-6.0 * delta)
	_base_position = _base_position.lerp(shot.position, t)
	_look_target = _look_target.lerp(shot.look, t)
	_base_fov = lerpf(_base_fov, shot.fov, t)
	fov = _base_fov
	_apply_transform(0.0, 0.0)
	if manager.stage:
		manager.stage.update_camera_occlusion(global_position)


## From the camera's side of the fight, in front of the fighter: a medium shot easing in
## to head and shoulders over 2 s.
func _intro_shot(time: float) -> Dictionary:
	var origin := intro_target.get_global_transform_interpolated().origin
	var side: Vector3 = manager.view_dir
	var e: float = smoothstep(0.0, 1.0, minf(time / 2.0, 1.0))
	var rad := deg_to_rad(lerpf(58.0, 46.0, e))
	var dir := (intro_target.forward * cos(rad) + side * sin(rad)).normalized()
	return {
		position = origin + dir * lerpf(3.0, 2.1, e) + Vector3.UP * lerpf(1.25, 1.5, e),
		look = origin + Vector3.UP * lerpf(1.25, 1.45, e),
		fov = lerpf(40.0, 33.0, e),
	}


# --- Victory cinematic -------------------------------------------------------------

## Starts the match-win camera sequence on `winner`.
func start_victory(winner: Fighter) -> void:
	victory_target = winner
	_victory_time = 0.0
	_victory_cut = false
	intensity = 0.0
	_trauma = 0.0
	_fov_punch = 0.0
	Engine.time_scale = 1.0
	# Film from the side the camera is already on, so shot 1 continues the fight view.
	var to_camera := global_position - winner.global_position
	_victory_side = 1.0 if to_camera.dot(_victory_right(winner)) >= 0.0 else -1.0


func _process_victory(delta: float) -> void:
	_victory_time += delta
	var shot := _victory_shot(_victory_time)
	var cut_now := _victory_time >= victory_shot1_seconds and not _victory_cut
	if cut_now:
		_victory_cut = true
	if cut_now or _victory_time <= delta:
		# Hard cut (and the very first frame) jumps straight to the shot.
		_base_position = shot.position
		_look_target = shot.look
		_base_fov = shot.fov
	else:
		var t := 1.0 - exp(-(10.0 if _victory_cut else 3.0) * delta)
		_base_position = _base_position.lerp(shot.position, t)
		_look_target = _look_target.lerp(shot.look, t)
		_base_fov = lerpf(_base_fov, shot.fov, t)
	fov = _base_fov
	_apply_transform(0.0, 0.0)
	if manager.stage:
		manager.stage.update_camera_occlusion(global_position)


## Camera position/aim/FOV for the victory sequence at `time` seconds.
func _victory_shot(time: float) -> Dictionary:
	var winner := victory_target.get_global_transform_interpolated().origin
	var facing := victory_target.forward
	var right := _victory_right(victory_target) * _victory_side
	var angle: float
	var radius: float
	var height: float
	var look_height: float
	var shot_fov: float
	if time < victory_shot1_seconds:
		# Wide, low hero angle from the side, orbiting toward the front.
		var e: float = smoothstep(0.0, 1.0, time / victory_shot1_seconds)
		angle = lerpf(100.0, 70.0, e)
		radius = lerpf(4.2, 3.6, e)
		height = lerpf(0.55, 0.7, e)
		look_height = 1.15
		shot_fov = 46.0
	else:
		# 3/4 front push-in to a medium close-up, then a slow drift.
		var t2 := time - victory_shot1_seconds
		var e: float = smoothstep(0.0, 1.0, minf(t2 / victory_shot2_seconds, 1.0))
		angle = lerpf(48.0, 38.0, e) + maxf(t2 - victory_shot2_seconds, 0.0) * victory_drift_degrees_per_second
		radius = lerpf(2.6, 1.9, e)
		height = lerpf(1.4, 1.55, e)
		look_height = lerpf(1.45, 1.55, e)
		shot_fov = lerpf(38.0, 32.0, e)
	var rad := deg_to_rad(angle)
	var dir := (facing * cos(rad) + right * sin(rad)).normalized()
	return {
		position = winner + dir * radius + Vector3.UP * height,
		look = winner + Vector3.UP * look_height,
		fov = shot_fov,
	}


func _victory_right(fighter: Fighter) -> Vector3:
	return fighter.forward.cross(Vector3.UP).normalized()


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


## Extra shake from effects (ground pounds, super finishers), scaled by the camera mode.
func shake(amount: float) -> void:
	_add_trauma(amount)


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
