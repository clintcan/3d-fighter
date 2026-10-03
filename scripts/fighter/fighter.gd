class_name Fighter
extends Node3D
## A combatant. FightManager calls read_input() and tick() at 60 Hz in a fixed order
## (view → input → tick → pushbox → hits) so the simulation stays deterministic.
## Gameplay runs only in tick(). _process() only updates visuals.

signal health_changed(current: int, maximum: int)
signal combo_changed(hits: int)
signal knocked_out(fighter: Fighter)
## Emitted by the defender who broke a throw.
signal throw_teched(fighter: Fighter)
## Cosmetic hooks for sound/effects (FightFx). Emitted from the tick; never read back.
signal attack_started(move: MoveData)
signal landed_hard(fighter: Fighter)
signal throw_impact(defender: Fighter)

enum State {
	IDLE, WALK_FWD, WALK_BACK, CROUCH,
	JUMP_SQUAT, JUMP, LANDING,
	DASH, BACKDASH, SIDESTEP,
	ATTACK,
	BLOCKSTUN, HITSTUN, AIR_HIT, KNOCKDOWN, GETUP,
	KO,
	THROW, THROWN, TECH,
}

enum HitResult { HIT, BLOCKED, COUNTER }

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
const GETUP_FRAMES := 40
const JUMP_FORWARD_SPEED := 2.5
const JUMP_BACK_SPEED := 2.0
const BLOCK_PUSHBACK_SCALE := 0.7
const JUGGLE_MIN_UP_SPEED := 3.0

## Hitting a fighter during their own attack's startup/active frames.
const COUNTER_DAMAGE_SCALE := 1.25
const COUNTER_HITSTUN_BONUS := 6
## Each hit already in the combo reduces damage by this much, down to the minimum.
const COMBO_SCALING_STEP := 0.1
const MIN_COMBO_SCALE := 0.3
## After this many hits while airborne, a juggled fighter can't be hit until they land.
const MAX_JUGGLE_HITS := 3
const KNOCKDOWN_POP_SPEED := 2.5

## Throw: LP+LK within THROW_INPUT_WINDOW ticks. Grab checks on THROW_STARTUP.
const THROW_INPUT_WINDOW := 3
const THROW_STARTUP := 5
const THROW_WHIFF_RECOVERY := 22
const THROW_RANGE := 0.95
const THROW_HOLD_FRAMES := 30
const THROW_RECOVERY := 14
const THROW_HOLD_DISTANCE := 0.75
## Defender can break a throw with LP+LK during the first ticks of being held.
const THROW_TECH_WINDOW := 10
const TECH_FRAMES := 18
const TECH_PUSH_SPEED := 2.5
const NOT_THROWABLE_STATES := [State.JUMP, State.AIR_HIT, State.KNOCKDOWN, State.GETUP, State.KO,
	State.HITSTUN, State.BLOCKSTUN, State.THROW, State.THROWN, State.TECH]

## Extra distance beyond an attack's reach at which holding back stops walking.
const PROXIMITY_GUARD_MARGIN := 0.5

const BUFFER_WINDOW := 6 # ticks an attack press stays buffered
const DOUBLE_TAP_WINDOW := 14
## Checked heaviest first so a mash of several buttons picks the stronger move.
const ATTACK_BUTTONS := [InputBuffer.HK, InputBuffer.HP, InputBuffer.LK, InputBuffer.LP]
const NEUTRAL_STATES := [State.IDLE, State.WALK_FWD, State.WALK_BACK, State.CROUCH]
const BLOCKING_STATES := [State.IDLE, State.WALK_FWD, State.WALK_BACK, State.CROUCH, State.BLOCKSTUN]
const INVULNERABLE_STATES := [State.KNOCKDOWN, State.GETUP, State.KO, State.THROWN]

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
var juggle_hits := 0 # hits taken while airborne in the current combo
var air_attack_used := false
## Throw bookkeeping: tick (state_frame) the grab connected, or -1 while reaching/whiffing.
var throw_grab_frame := -1
var current_move: MoveData
var move_has_hit := false
var sidestep_dir := Vector3.ZERO
var debug_draw := false
## Set by FightManager on the round/match winner: shows the victory pose when idle.
var victory := false
## Match-win animation (played once, final pose held); empty = round-win folded arms.
var victory_clip: StringName
var _victory_time := 0.0
var last_hit_level: MoveData.HitLevel = MoveData.HitLevel.MID
## Skinned character model, or null for a graybox capsule.
var model: FighterModel
## Alternate costume (mirror match P2).
var alt := false
## Training mode: health never drops below 1, so there are no K.O.s.
var immortal := false

var _flash_color := Color.WHITE
var _material: StandardMaterial3D

@onready var visual: Node3D = $Visual
@onready var body_mesh: MeshInstance3D = $Visual/Body
@onready var limb: MeshInstance3D = $Limb
@onready var hurtbox_debug: MeshInstance3D = $HurtboxDebug


func setup(character: CharacterData, fighter_controller: FighterController, alt_look: bool = false) -> void:
	data = character
	controller = fighter_controller
	alt = alt_look
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

	if data.model_scene:
		model = FighterModel.new()
		add_child(model)
		model.build(data, alt)
		visual.visible = false


## Restores a fresh round state. Everything that affects the simulation is reset here,
## so a round with the same inputs always plays out the same way.
func reset_to(spawn_position: Vector3) -> void:
	position = spawn_position
	velocity = Vector3.ZERO
	health = data.max_health
	hitstop = 0
	stun = 0
	current_move = null
	move_has_hit = false
	input = InputBuffer.new()
	input_locked = false
	juggle_hits = 0
	air_attack_used = false
	throw_grab_frame = -1
	sidestep_dir = Vector3.ZERO
	last_hit_level = MoveData.HitLevel.MID
	victory = false
	victory_clip = &""
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
		State.JUMP:
			if not air_attack_used:
				_try_attack(false)
		State.AIR_HIT:
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
		State.THROW:
			_tick_throw()
		State.THROWN:
			velocity = Vector3.ZERO
			if state_frame <= THROW_TECH_WINDOW and _throw_pressed():
				_tech_throw()
		State.TECH:
			if state_frame >= TECH_FRAMES:
				_return_to_neutral()
	_apply_motion()


func _tick_neutral() -> void:
	face_opponent()
	if _throw_pressed():
		input.consume(InputBuffer.LP)
		input.consume(InputBuffer.LK)
		velocity = Vector3.ZERO
		throw_grab_frame = -1
		_set_state(State.THROW)
		return
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
			# Proximity guard: holding back against a threatening attack blocks in place
			# instead of walking out of range.
			velocity = Vector3.ZERO if opponent.is_threatening(self) else -forward * data.back_walk_speed
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
	air_attack_used = false
	_set_state(State.JUMP)


func _tick_attack() -> void:
	var airborne := position.y > 0.0
	if not airborne:
		velocity = _with_friction(velocity)
	var frame := state_frame
	if move_has_hit and frame > current_move.startup and not current_move.cancel_into.is_empty():
		if _try_attack(true):
			return
	if frame >= current_move.total_frames():
		if airborne:
			current_move = null
			_set_state(State.JUMP) # air attack finished; keep falling, no second attack
		else:
			_return_to_neutral()


## Starts a buffered attack. With `cancel_only`, only moves listed in the current
## move's cancel_into are allowed.
func _try_attack(cancel_only: bool) -> bool:
	var dir := input.dir()
	var airborne := state == State.JUMP
	for button: int in ATTACK_BUTTONS:
		if not input.pressed_within(button, BUFFER_WINDOW):
			continue
		var move := _find_move(button, dir, airborne)
		if move == null or (cancel_only and move.input not in current_move.cancel_into):
			continue
		input.consume(button)
		current_move = move
		move_has_hit = false
		air_attack_used = air_attack_used or airborne
		_set_state(State.ATTACK, move.input.begins_with("2"))
		if move.lunge > 0.0 and not airborne:
			velocity = forward * move.lunge
		attack_started.emit(move)
		return true
	return false


## Picks the move for a button given the held direction (numpad, facing-relative).
## Air moves use "j." inputs only. On the ground: down/down-diagonals → "2", forward →
## "6", back → "4"; each falls back to the plain standing move.
func _find_move(button: int, dir: int, airborne: bool) -> MoveData:
	var button_name: String = InputBuffer.BUTTON_NAMES[button]
	if airborne:
		return _move_for_input("j." + button_name)
	var prefix := ""
	if dir <= 3:
		prefix = "2"
	elif dir == 6:
		prefix = "6"
	elif dir == 4:
		prefix = "4"
	var move := _move_for_input(prefix + button_name) if prefix != "" else null
	return move if move else _move_for_input(button_name)


func _move_for_input(input_name: String) -> MoveData:
	for move in data.moves:
		if move.input == input_name:
			return move
	return null


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
	elif state in [State.HITSTUN, State.BLOCKSTUN, State.KNOCKDOWN, State.GETUP, State.KO, State.TECH, State.THROW]:
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
		State.JUMP, State.ATTACK:
			velocity = Vector3.ZERO
			current_move = null
			_set_state(State.LANDING)
		State.AIR_HIT:
			_set_state(State.KNOCKDOWN)
			landed_hard.emit(self)
		State.KO:
			landed_hard.emit(self)


func _return_to_neutral() -> void:
	current_move = null
	juggle_hits = 0
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
	if state == State.AIR_HIT and juggle_hits >= MAX_JUGGLE_HITS:
		return false
	var top := (CROUCH_HEIGHT if crouching else STAND_HEIGHT) - BODY_RADIUS
	var a := position + Vector3.UP * BODY_RADIUS
	var b := position + Vector3.UP * top
	var closest := Geometry3D.get_closest_point_to_segment(center, a, b)
	return closest.distance_to(center) <= radius + BODY_RADIUS


## Applies a hit from `attacker` and reports whether it hit, was blocked, or counter-hit.
func receive_hit(attacker: Fighter, move: MoveData) -> HitResult:
	var push_dir := attacker.forward
	hitstop = move.hitstop
	if _can_block(move.hit_level):
		var crouch_block := input.dir() == 1
		_set_state(State.BLOCKSTUN, crouch_block)
		stun = move.blockstun
		velocity = push_dir * move.knockback.x * BLOCK_PUSHBACK_SCALE / data.weight
		_flash_color = Color(0.4, 0.7, 1.0)
		return HitResult.BLOCKED

	var counter := state == State.ATTACK and current_move != null \
			and state_frame <= current_move.startup + current_move.active
	var airborne := position.y > 0.0 or state in [State.JUMP, State.AIR_HIT]
	if airborne:
		juggle_hits += 1
	var scale := maxf(MIN_COMBO_SCALE, 1.0 - COMBO_SCALING_STEP * combo_hits)
	if counter:
		scale *= COUNTER_DAMAGE_SCALE
	_take_damage(roundi(move.damage * scale))
	_set_combo(combo_hits + 1)
	_flash_color = Color(1.0, 0.85, 0.3) if counter else Color.WHITE
	last_hit_level = move.hit_level
	current_move = null
	velocity = push_dir * move.knockback.x / data.weight + Vector3.UP * move.knockback.y

	if health == 0:
		_knock_out(push_dir)
	elif airborne or move.launches:
		velocity.y = maxf(velocity.y, JUGGLE_MIN_UP_SPEED)
		_set_state(State.AIR_HIT)
	elif move.knockdown:
		# Tripped: a small pop, then falls into a knockdown.
		velocity.y = KNOCKDOWN_POP_SPEED
		_set_state(State.AIR_HIT)
	else:
		var was_crouching := crouching
		_set_state(State.HITSTUN, was_crouching)
		stun = move.hitstun + (COUNTER_HITSTUN_BONUS if counter else 0)
	return HitResult.COUNTER if counter else HitResult.HIT


func _take_damage(amount: int) -> void:
	health = maxi(health - amount, 1 if immortal else 0)
	health_changed.emit(health, data.max_health)


func _knock_out(push_dir: Vector3) -> void:
	velocity += push_dir * 1.5 + Vector3.UP * 4.0
	_set_state(State.KO)
	knocked_out.emit(self)


## Called on the attacker after its hitbox connected (hit or block).
func on_hit_confirmed() -> void:
	if current_move == null: # traded and got hit on the same tick
		return
	move_has_hit = true
	hitstop = current_move.hitstop


## Match win: play `clip` from the start (cosmetic; the fighter stays in its idle state).
func start_victory(clip: StringName) -> void:
	victory = true
	victory_clip = clip
	_victory_time = 0.0


## True while this fighter's attack is in startup/active and close enough to `target`
## that it could connect.
func is_threatening(target: Fighter) -> bool:
	if state != State.ATTACK or current_move == null:
		return false
	if state_frame > current_move.startup + current_move.active:
		return false
	var reach := absf(current_move.hitbox_offset.z) + current_move.hitbox_radius + BODY_RADIUS
	return _flat_distance_to(target) <= reach + PROXIMITY_GUARD_MARGIN


func _flat_distance_to(other: Fighter) -> float:
	return Vector2(other.position.x - position.x, other.position.z - position.z).length()


## True on the tick a throw's grab checks for a target (FightManager resolves it).
func is_throw_grab_frame() -> bool:
	return state == State.THROW and throw_grab_frame < 0 and state_frame == THROW_STARTUP


func is_throwable() -> bool:
	return position.y <= 0.0 and state not in NOT_THROWABLE_STATES


## Called on the attacker when its grab connects.
func on_throw_grabbed() -> void:
	throw_grab_frame = state_frame


## Called on the defender when grabbed: held in front of the attacker.
func on_grabbed_by(attacker: Fighter) -> void:
	current_move = null
	velocity = Vector3.ZERO
	position = attacker.position + attacker.forward * THROW_HOLD_DISTANCE
	clamp_to_bounds()
	face_opponent()
	_set_state(State.THROWN)


## Both fighters break apart. Used for a defender tech and for simultaneous throws.
func tech_apart() -> void:
	current_move = null
	throw_grab_frame = -1
	velocity = -forward * TECH_PUSH_SPEED
	_flash_color = Color(0.4, 0.7, 1.0)
	_set_state(State.TECH)


func _tech_throw() -> void:
	tech_apart()
	opponent.tech_apart()
	throw_teched.emit(self)


func _tick_throw() -> void:
	if throw_grab_frame < 0:
		if state_frame >= THROW_STARTUP + THROW_WHIFF_RECOVERY:
			_return_to_neutral()
		return
	var held_for := state_frame - throw_grab_frame
	if held_for == THROW_HOLD_FRAMES and opponent.state == State.THROWN:
		opponent._release_from_throw(self)
	elif held_for >= THROW_HOLD_FRAMES + THROW_RECOVERY:
		throw_grab_frame = -1
		_return_to_neutral()


## Thrown: damage, then tossed into a knockdown (no juggles after a throw).
func _release_from_throw(attacker: Fighter) -> void:
	var push_dir := attacker.forward
	_take_damage(attacker.data.throw_damage)
	throw_impact.emit(self)
	_set_combo(1)
	_flash_color = Color.WHITE
	hitstop = 8
	attacker.hitstop = 8
	juggle_hits = MAX_JUGGLE_HITS
	velocity = push_dir * 2.5 + Vector3.UP * 4.5
	if health == 0:
		_knock_out(push_dir)
	else:
		_set_state(State.AIR_HIT)


func _throw_pressed() -> bool:
	return input.pressed_within(InputBuffer.LP, THROW_INPUT_WINDOW) \
			and input.pressed_within(InputBuffer.LK, THROW_INPUT_WINDOW)


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


## True if being pushed along `direction` would be stopped by the ring edge.
func is_pinned_against_bounds(direction: Vector3) -> bool:
	var limit := bounds_half_extent - 0.01
	return (direction.x > 0.1 and position.x >= limit) or (direction.x < -0.1 and position.x <= -limit) 			or (direction.z > 0.1 and position.z >= limit) or (direction.z < -0.1 and position.z <= -limit)


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
	if model:
		_update_model(delta)
		_update_limb()
		_update_hurtbox_debug()
		return
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
	_update_hurtbox_debug()


func _update_hurtbox_debug() -> void:
	hurtbox_debug.visible = debug_draw and state not in INVULNERABLE_STATES
	if hurtbox_debug.visible:
		var height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
		(hurtbox_debug.mesh as CapsuleMesh).height = height
		hurtbox_debug.position = Vector3.UP * height * 0.5


## Placeholder attack animation: a sphere extends from the body to the hitbox during
## startup, stays out (red) while active, and retracts during recovery.
func _update_limb() -> void:
	if state != State.ATTACK or current_move == null or (model and not debug_draw):
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


func _update_model(delta: float) -> void:
	if victory_clip != &"":
		_victory_time += delta
	var frozen := hitstop > 0
	var request := _animation_request(frozen)
	model.show_clip(request[0], request[1], request[2], 0.0 if frozen else delta)
	var shake := Vector3.ZERO
	if frozen and state in [State.HITSTUN, State.BLOCKSTUN, State.AIR_HIT, State.KO]:
		shake.x = randf_range(-0.03, 0.03)
	model.position = shake


## Logic → animation: [clip, time (s, or -1 to free-run), speed].
func _animation_request(frozen: bool) -> Array:
	# Interpolate between ticks so timed clips stay smooth at high refresh rates.
	var f := float(state_frame) + (0.0 if frozen else Engine.get_physics_interpolation_fraction())
	var t := f * DT
	match state:
		State.WALK_FWD:
			return [&"fight/walk_guard", -1.0, data.walk_speed / 1.5]
		State.WALK_BACK:
			return [&"fight/walk_guard", -1.0, -data.back_walk_speed / 1.5]
		State.CROUCH:
			return [&"fight/crouch_guard", -1.0, 1.0]
		State.JUMP_SQUAT:
			return [&"ual1/Jump_Start", 0.15 * f / JUMP_SQUAT_FRAMES, 1.0]
		State.JUMP:
			return [&"ual1/Jump_Start", 0.15 + t, 1.0]
		State.LANDING:
			return [&"ual1/Jump_Land", 0.05 + t, 1.0]
		State.DASH, State.SIDESTEP:
			return [&"fight/walk_guard", -1.0, 2.5]
		State.BACKDASH:
			return [&"fight/walk_guard", -1.0, -2.5]
		State.ATTACK:
			return [current_move.animation, _attack_clip_time(f), 1.0]
		State.BLOCKSTUN:
			return [&"fight/block_crouch" if crouching else &"fight/block_stand", 0.0, 1.0]
		State.HITSTUN:
			if crouching:
				return [&"fight/crouch_guard", 0.0, 1.0]
			return [&"ual1/Hit_Head" if last_hit_level == MoveData.HitLevel.HIGH else &"ual1/Hit_Chest", t, 1.0]
		State.AIR_HIT, State.KO:
			return [&"ual2/Hit_Knockback", t, 1.0]
		State.KNOCKDOWN:
			return [&"ual2/Hit_Knockback", model.clip_length(&"ual2/Hit_Knockback"), 1.0]
		State.GETUP:
			return [&"ual2/LayToIdle", lerpf(0.35, model.clip_length(&"ual2/LayToIdle"), f / GETUP_FRAMES), 1.0]
		State.THROW:
			# Grab connected: play through the heave. Whiffed: hold the reach.
			return [&"fight/throw", t if throw_grab_frame >= 0 else minf(t, 0.25), 1.0]
		State.THROWN:
			return [&"fight/thrown", 0.0, 1.0]
		State.TECH:
			return [&"fight/block_stand", 0.0, 1.0]
	if victory and victory_clip != &"":
		return [victory_clip, _victory_time, 1.0]
	if victory:
		return [&"ual2/Idle_FoldArms", -1.0, 1.0]
	return [&"fight/guard", -1.0, 1.0]


## Maps the move's frame onto clip time: startup covers [0, impact], so the strike lands
## on the first active frame, and active + recovery cover [impact, end].
func _attack_clip_time(f: float) -> float:
	var move := current_move
	var impact_frame := float(move.startup + 1)
	if f <= impact_frame:
		return move.animation_impact * f / impact_frame
	var end_time: float = move.animation_end if move.animation_end > 0.0 else model.clip_length(move.animation)
	return lerpf(move.animation_impact, end_time, (f - impact_frame) / maxf(move.total_frames() - impact_frame, 1.0))
