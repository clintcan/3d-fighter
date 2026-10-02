class_name Fighter
extends Node3D
## A combatant. FightManager calls read_input() and tick() at 60 Hz in a fixed order
## (view → input → tick → pushbox → hits) so the simulation stays deterministic.
## Gameplay runs only in tick(). _process() only updates visuals.

signal health_changed(current: int, maximum: int)
signal combo_changed(hits: int)
signal knocked_out(fighter: Fighter)

enum State {
	IDLE, WALK_FWD, WALK_BACK, CROUCH,
	JUMP_SQUAT, JUMP, LANDING,
	DASH, BACKDASH, SIDESTEP,
	ATTACK,
	BLOCKSTUN, HITSTUN, AIR_HIT, KNOCKDOWN, GETUP,
	KO,
}

const DT := 1.0 / 60.0
const GRAVITY := 20.0
const GROUND_FRICTION := 10.0
const BODY_RADIUS := 0.35
const PUSHBOX_RADIUS := 0.35
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2

const JUMP_SQUAT_FRAMES := 4
const LANDING_FRAMES := 3
const DASH_FRAMES := 16
const BACKDASH_FRAMES := 18
const SIDESTEP_FRAMES := 14
const KNOCKDOWN_FRAMES := 40
const GETUP_FRAMES := 20
const JUMP_FORWARD_SPEED := 2.5
const JUMP_BACK_SPEED := 2.0
const BLOCK_PUSHBACK_SCALE := 0.7
const JUGGLE_MIN_UP_SPEED := 3.0

const BUFFER_WINDOW := 6 # ticks an attack press stays buffered
const DOUBLE_TAP_WINDOW := 14
## Checked heaviest first so a mash of several buttons picks the stronger move.
const ATTACK_BUTTONS := [InputBuffer.HK, InputBuffer.HP, InputBuffer.LK, InputBuffer.LP]
const NEUTRAL_STATES := [State.IDLE, State.WALK_FWD, State.WALK_BACK, State.CROUCH]
const BLOCKING_STATES := [State.IDLE, State.WALK_FWD, State.WALK_BACK, State.CROUCH, State.BLOCKSTUN]
const INVULNERABLE_STATES := [State.KNOCKDOWN, State.GETUP, State.KO]

var data: CharacterData
var controller: FighterController
var opponent: Fighter
var input := InputBuffer.new()
## When true, read_input() feeds neutral (used after a KO).
var input_locked := false
var bounds_half_extent := 3.6

## Set by FightManager each tick from the camera's logical view direction.
var view_right := Vector3.RIGHT
var view_depth := Vector3.FORWARD

var state: State = State.IDLE
var state_frame := 0 # ticks spent in the current state
var crouching := false
var health := 0
var forward := Vector3.RIGHT # flattened unit vector toward the opponent
var velocity := Vector3.ZERO
var hitstop := 0
var stun := 0
var combo_hits := 0 # hits taken in the current combo
var current_move: MoveData
var move_has_hit := false
var sidestep_dir := Vector3.ZERO
var debug_draw := false

var _flash_color := Color.WHITE
var _material: StandardMaterial3D

@onready var visual: Node3D = $Visual
@onready var body_mesh: MeshInstance3D = $Visual/Body
@onready var limb: MeshInstance3D = $Limb
@onready var hurtbox_debug: MeshInstance3D = $HurtboxDebug


func setup(character: CharacterData, fighter_controller: FighterController) -> void:
	data = character
	controller = fighter_controller
	name = character.display_name
	health = character.max_health


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = data.placeholder_color
	body_mesh.material_override = _material
	$Visual/Nose.material_override = _material
	var limb_material := StandardMaterial3D.new()
	limb_material.albedo_color = data.placeholder_color.lightened(0.3)
	limb.material_override = limb_material
	var debug_material := StandardMaterial3D.new()
	debug_material.albedo_color = Color(0.2, 1.0, 0.3, 0.35)
	debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hurtbox_debug.material_override = debug_material


func reset_to(spawn_position: Vector3) -> void:
	position = spawn_position
	velocity = Vector3.ZERO
	health = data.max_health
	hitstop = 0
	stun = 0
	current_move = null
	input_locked = false
	_set_combo(0)
	_set_state(State.IDLE)
	health_changed.emit(health, data.max_health)
	visual.rotation = Vector3.ZERO
	reset_physics_interpolation()


# --- Simulation (60 Hz, called by FightManager) ---------------------------------

func read_input() -> void:
	if input_locked:
		input.push(InputBuffer.pack(InputBuffer.NEUTRAL, 0))
	else:
		input.push(controller.read(self))


func tick() -> void:
	if hitstop > 0:
		hitstop -= 1
		return
	state_frame += 1
	match state:
		State.IDLE, State.WALK_FWD, State.WALK_BACK, State.CROUCH:
			_tick_neutral()
		State.JUMP_SQUAT:
			_tick_jump_squat()
		State.JUMP, State.AIR_HIT:
			pass # gravity + landing handled in _apply_motion
		State.LANDING:
			velocity = Vector3.ZERO
			if state_frame >= LANDING_FRAMES:
				_return_to_neutral()
		State.DASH:
			velocity = forward * data.dash_speed * _burst_curve(DASH_FRAMES)
			if state_frame >= DASH_FRAMES:
				_return_to_neutral()
		State.BACKDASH:
			velocity = -forward * data.dash_speed * 0.9 * _burst_curve(BACKDASH_FRAMES)
			if state_frame >= BACKDASH_FRAMES:
				_return_to_neutral()
		State.SIDESTEP:
			face_opponent()
			velocity = sidestep_dir * _sidestep_speed() * _burst_curve(SIDESTEP_FRAMES)
			if state_frame >= SIDESTEP_FRAMES:
				_return_to_neutral()
		State.ATTACK:
			_tick_attack()
		State.BLOCKSTUN, State.HITSTUN:
			stun -= 1
			if stun <= 0:
				_return_to_neutral()
		State.KNOCKDOWN:
			if state_frame >= KNOCKDOWN_FRAMES:
				_set_state(State.GETUP)
		State.GETUP:
			if state_frame >= GETUP_FRAMES:
				_return_to_neutral()
		State.KO:
			pass
	_apply_motion()


func _tick_neutral() -> void:
	face_opponent()
	if _try_attack(false):
		return
	if input.pressed_within(InputBuffer.SIDESTEP, BUFFER_WINDOW):
		input.consume(InputBuffer.SIDESTEP)
		_start_sidestep(input.dir() <= 3)
		return
	if input.double_tapped(6, DOUBLE_TAP_WINDOW):
		_set_state(State.DASH)
		return
	if input.double_tapped(4, DOUBLE_TAP_WINDOW):
		_set_state(State.BACKDASH)
		return

	var dir := input.dir()
	if dir >= 7:
		_set_state(State.JUMP_SQUAT)
		velocity = Vector3.ZERO
		return
	var next_state := State.IDLE
	if dir <= 3:
		next_state = State.CROUCH
	elif dir == 6:
		next_state = State.WALK_FWD
	elif dir == 4:
		next_state = State.WALK_BACK
	if next_state != state:
		_set_state(next_state, next_state == State.CROUCH)

	match state:
		State.WALK_FWD:
			velocity = forward * data.walk_speed
		State.WALK_BACK:
			velocity = -forward * data.back_walk_speed
		_:
			velocity = Vector3.ZERO


func _tick_jump_squat() -> void:
	if state_frame < JUMP_SQUAT_FRAMES:
		return
	# Direction is read at the end of the squat. Once started, the jump is committed.
	var horizontal := 0.0
	match input.dir():
		9:
			horizontal = JUMP_FORWARD_SPEED
		7:
			horizontal = -JUMP_BACK_SPEED
	velocity = forward * horizontal + Vector3.UP * data.jump_velocity
	_set_state(State.JUMP)


func _tick_attack() -> void:
	velocity = _with_friction(velocity)
	var frame := state_frame
	if move_has_hit and frame > current_move.startup and not current_move.cancel_into.is_empty():
		if _try_attack(true):
			return
	if frame >= current_move.total_frames():
		_return_to_neutral()


## Starts a buffered attack. With `cancel_only`, only moves listed in the current
## move's cancel_into are allowed.
func _try_attack(cancel_only: bool) -> bool:
	var crouch := input.dir() <= 3
	for button: int in ATTACK_BUTTONS:
		if not input.pressed_within(button, BUFFER_WINDOW):
			continue
		var move := _find_move(button, crouch)
		if move == null or (cancel_only and move.input not in current_move.cancel_into):
			continue
		input.consume(button)
		current_move = move
		move_has_hit = false
		_set_state(State.ATTACK, move.input.begins_with("2"))
		return true
	return false


func _find_move(button: int, crouch: bool) -> MoveData:
	var button_name: String = InputBuffer.BUTTON_NAMES[button]
	var fallback: MoveData = null
	for move in data.moves:
		if crouch and move.input == "2" + button_name:
			return move
		if move.input == button_name:
			fallback = move
	return fallback


func _start_sidestep(toward_camera: bool) -> void:
	sidestep_dir = Vector3.UP.cross(forward).normalized()
	if sidestep_dir.dot(view_depth) < 0.0:
		sidestep_dir = -sidestep_dir
	if toward_camera:
		sidestep_dir = -sidestep_dir
	_set_state(State.SIDESTEP)


func _apply_motion() -> void:
	var airborne := state in [State.JUMP, State.AIR_HIT] or position.y > 0.0
	if airborne:
		velocity.y -= GRAVITY * DT
	elif state in [State.HITSTUN, State.BLOCKSTUN, State.KNOCKDOWN, State.GETUP, State.KO]:
		velocity = _with_friction(velocity)
	position += velocity * DT
	if position.y <= 0.0 and velocity.y <= 0.0:
		position.y = 0.0
		velocity.y = 0.0
		if airborne:
			_on_landed()
	clamp_to_bounds()


func _on_landed() -> void:
	match state:
		State.JUMP:
			velocity = Vector3.ZERO
			_set_state(State.LANDING)
		State.AIR_HIT:
			_set_state(State.KNOCKDOWN)


func _return_to_neutral() -> void:
	current_move = null
	_set_combo(0)
	_set_state(State.IDLE)


func _set_state(new_state: State, crouch: bool = false) -> void:
	state = new_state
	state_frame = 0
	crouching = crouch


# --- Combat ----------------------------------------------------------------------

## Active hitbox this tick as {center: Vector3, radius: float}, or {} if none.
func get_active_hitbox() -> Dictionary:
	if state != State.ATTACK or move_has_hit:
		return {}
	var frame := state_frame
	if frame <= current_move.startup or frame > current_move.startup + current_move.active:
		return {}
	return {
		center = global_transform * current_move.hitbox_offset,
		radius = current_move.hitbox_radius,
	}


func overlaps_hurtbox(center: Vector3, radius: float) -> bool:
	if state in INVULNERABLE_STATES:
		return false
	var top := (CROUCH_HEIGHT if crouching else STAND_HEIGHT) - BODY_RADIUS
	var a := position + Vector3.UP * BODY_RADIUS
	var b := position + Vector3.UP * top
	var closest := Geometry3D.get_closest_point_to_segment(center, a, b)
	return closest.distance_to(center) <= radius + BODY_RADIUS


## Applies a hit from `attacker`. Returns true if it was blocked.
func receive_hit(attacker: Fighter, move: MoveData) -> bool:
	var push_dir := attacker.forward
	hitstop = move.hitstop
	if _can_block(move.hit_level):
		var crouch_block := input.dir() == 1
		_set_state(State.BLOCKSTUN, crouch_block)
		stun = move.blockstun
		velocity = push_dir * move.knockback.x * BLOCK_PUSHBACK_SCALE / data.weight
		_flash_color = Color(0.4, 0.7, 1.0)
		return true

	var airborne := position.y > 0.0 or state in [State.JUMP, State.AIR_HIT]
	health = maxi(health - move.damage, 0)
	health_changed.emit(health, data.max_health)
	_set_combo(combo_hits + 1)
	_flash_color = Color.WHITE
	current_move = null
	velocity = push_dir * move.knockback.x / data.weight + Vector3.UP * move.knockback.y

	if health == 0:
		velocity += push_dir * 1.5 + Vector3.UP * 4.0
		_set_state(State.KO)
		knocked_out.emit(self)
	elif airborne or move.launches:
		velocity.y = maxf(velocity.y, JUGGLE_MIN_UP_SPEED)
		_set_state(State.AIR_HIT)
	else:
		var was_crouching := crouching
		_set_state(State.HITSTUN, was_crouching)
		stun = move.hitstun
	return false


## Called on the attacker after its hitbox connected (hit or block).
func on_hit_confirmed() -> void:
	if current_move == null: # traded and got hit on the same tick
		return
	move_has_hit = true
	hitstop = current_move.hitstop


## Highs and mids are blocked standing (hold back), lows and mids crouching (hold down-back).
func _can_block(level: MoveData.HitLevel) -> bool:
	if state not in BLOCKING_STATES:
		return false
	match input.dir():
		4:
			return level != MoveData.HitLevel.LOW
		1:
			return level != MoveData.HitLevel.OVERHEAD
	return false


# --- Helpers ---------------------------------------------------------------------

func faces_screen_right() -> bool:
	return forward.dot(view_right) >= 0.0


func is_actionable() -> bool:
	return state in NEUTRAL_STATES


func clamp_to_bounds() -> void:
	position.x = clampf(position.x, -bounds_half_extent, bounds_half_extent)
	position.z = clampf(position.z, -bounds_half_extent, bounds_half_extent)


func face_opponent() -> void:
	var to_opponent := opponent.position - position
	to_opponent.y = 0.0
	if to_opponent.length_squared() > 0.0001:
		forward = to_opponent.normalized()
	basis = Basis.looking_at(forward)


func _with_friction(v: Vector3) -> Vector3:
	var horizontal := Vector3(v.x, 0.0, v.z)
	horizontal = horizontal.move_toward(Vector3.ZERO, GROUND_FRICTION * DT)
	return Vector3(horizontal.x, v.y, horizontal.z)


## Fast start, eased stop. Integrates to 2/3 of (top speed × duration).
func _burst_curve(frames: int) -> float:
	var t := float(state_frame) / frames
	return 1.0 - t * t


func _sidestep_speed() -> float:
	return data.sidestep_distance / (SIDESTEP_FRAMES * DT * 2.0 / 3.0)


func _set_combo(hits: int) -> void:
	if hits == combo_hits:
		return
	combo_hits = hits
	combo_changed.emit(hits)


# --- Visuals (render rate, cosmetic only) --------------------------------------

func _process(delta: float) -> void:
	var smoothing := 1.0 - exp(-18.0 * delta)

	var target_scale_y := CROUCH_HEIGHT / STAND_HEIGHT if crouching else 1.0
	visual.scale.y = lerpf(visual.scale.y, target_scale_y, smoothing)

	var lying := state in [State.KNOCKDOWN, State.KO] and position.y <= 0.0
	var target_tilt := 0.0
	if lying:
		target_tilt = PI / 2.0
	elif state in [State.AIR_HIT, State.KO]:
		target_tilt = PI / 4.0
	visual.rotation.x = lerp_angle(visual.rotation.x, target_tilt, 1.0 - exp(-10.0 * delta))
	var shake := Vector3.ZERO
	if hitstop > 0 and state in [State.HITSTUN, State.BLOCKSTUN, State.AIR_HIT, State.KO]:
		shake.x = randf_range(-0.04, 0.04)
	visual.position = shake + Vector3.UP * (BODY_RADIUS * sin(visual.rotation.x))

	var flashing := hitstop > 0 and state in [State.HITSTUN, State.BLOCKSTUN, State.AIR_HIT, State.KO]
	_material.emission_enabled = flashing
	_material.emission = _flash_color
	_material.emission_energy_multiplier = 0.8

	_update_limb()
	hurtbox_debug.visible = debug_draw and state not in INVULNERABLE_STATES
	if hurtbox_debug.visible:
		var height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
		(hurtbox_debug.mesh as CapsuleMesh).height = height
		hurtbox_debug.position = Vector3.UP * height * 0.5


## Placeholder attack animation: a sphere extends from the body to the hitbox during
## startup, stays out (red) while active, and retracts during recovery.
func _update_limb() -> void:
	if state != State.ATTACK or current_move == null:
		limb.visible = false
		return
	var move := current_move
	var frame := float(state_frame)
	var progress := 1.0
	var active := frame > move.startup and frame <= move.startup + move.active
	if frame <= move.startup:
		progress = frame / maxf(move.startup, 1.0)
	elif not active:
		progress = 1.0 - (frame - move.startup - move.active) / maxf(move.recovery, 1.0)
	var shoulder := Vector3(0.0, move.hitbox_offset.y, 0.0)
	limb.visible = true
	limb.position = shoulder.lerp(move.hitbox_offset, progress)
	limb.scale = Vector3.ONE * move.hitbox_radius * 2.0
	(limb.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.2, 0.15) if active and not move_has_hit else data.placeholder_color.lightened(0.3)
