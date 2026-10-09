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
signal meter_changed(current: int, maximum: int)
signal focus_changed(level: int)
## A super started: FightManager freezes the fight for the super flash.
signal super_started(fighter: Fighter, move: MoveData)
## Cosmetic: the current move's first active frame (impact effects).
signal move_active(fighter: Fighter, move: MoveData)

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
const GRAB_SNAP_FRAMES := 8.0 # the grabbed fighter's model eases into the hold this long
## Defender can break a throw with LP+LK during the first ticks of being held.
const THROW_TECH_WINDOW := 10
const TECH_FRAMES := 18
const TECH_PUSH_SPEED := 2.5
const NOT_THROWABLE_STATES := [State.JUMP, State.AIR_HIT, State.KNOCKDOWN, State.GETUP, State.KO,
	State.HITSTUN, State.BLOCKSTUN, State.THROW, State.THROWN, State.TECH]

## Extra distance beyond an attack's reach at which holding back stops walking.
const PROXIMITY_GUARD_MARGIN := 0.5

## Super meter. A super costs the full bar. Hits build meter for both sides.
const MAX_METER := 1000
const METER_PER_DAMAGE_HIT := 1.0 # attacker, per point of the move's damage
const METER_PER_DAMAGE_BLOCKED := 0.5 # attacker, when blocked
const METER_PER_DAMAGE_TAKEN := 0.6 # defender
const METER_PER_SPECIAL := 20 # starting a special
## Focus (Mira's stance): levels powering up moves with focus_* data. Lost on knockdown.
const MAX_FOCUS := 3
## Motion input windows (ticks) and how recently the final direction must have been held.
const MOTION_WINDOW := 14
const SUPER_MOTION_WINDOW := 26
const MOTION_FINISH := 8
## Specials checked longest/most specific first, so 236236 beats 236 and 623 beats 236.
const MOTION_PRIORITY := ["236236", "63214", "623", "214", "236"]
## A normal that connected can be cancelled into a special for this long after its
## active frames; a special into a super likewise.
const SPECIAL_CANCEL_WINDOW := 10
## A forward dash can turn into a special during its first frames, so walk-forward,
## release, 623 (whose 6 starts a dash) still comes out as the dragon punch.
const DASH_SPECIAL_CANCEL := 8
## Knockback (m/s) of the non-final hits of a multi-hit move, so the victim stays close.
const MULTI_HIT_KNOCKBACK := 0.6

const BUFFER_WINDOW := 6 # ticks an attack press stays buffered
const DOUBLE_TAP_WINDOW := 14
## Checked heaviest first so a mash of several buttons picks the stronger move.
const ATTACK_BUTTONS := [InputBuffer.HK, InputBuffer.HP, InputBuffer.LK, InputBuffer.LP]
const NEUTRAL_STATES := [State.IDLE, State.WALK_FWD, State.WALK_BACK, State.CROUCH]
const BLOCKING_STATES := [State.IDLE, State.WALK_FWD, State.WALK_BACK, State.CROUCH, State.BLOCKSTUN]
const INVULNERABLE_STATES := [State.KNOCKDOWN, State.GETUP, State.KO, State.THROWN]
## Every field the simulation reads or writes, saved and restored for rollback netcode
## (plus the transform, input buffer and projectile). Add new simulation fields here.
const SIM_FIELDS := [&"input_locked", &"view_right", &"view_depth", &"state", &"state_frame",
	&"crouching", &"health", &"forward", &"velocity", &"hitstop", &"stun", &"combo_hits",
	&"juggle_hits", &"air_attack_used", &"throw_grab_frame", &"grab_move", &"throw_techable",
	&"current_move", &"move_has_hit", &"hits_landed", &"next_hit_frame", &"meter", &"frozen",
	&"_landing_frames", &"sidestep_dir", &"victory", &"last_hit_level", &"immortal", &"focus",
	&"move_focus"]
## (victory_clip is cosmetic: each machine picks its own victory animation.)

var data: CharacterData
var controller: FighterController
var opponent: Fighter
var input := InputBuffer.new()
## When true, read_input() feeds neutral (used after a KO).
var input_locked := false
var bounds_half_extent := 3.6
## Z limit (Stage.depth_limit(); the same as bounds_half_extent on square stages).
var bounds_depth := 3.6

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
## The command grab being performed (its damage replaces throw_damage), or null.
var grab_move: MoveData
## False while held by a command grab (no tech).
var throw_techable := true
## Cosmetic: where the fighter was relative to the hold position when grabbed; the model
## eases across it over GRAB_SNAP_FRAMES (not simulation state).
var _grab_snap := Vector3.ZERO
var current_move: MoveData
var move_has_hit := false
## Multi-hit bookkeeping for the current move.
var hits_landed := 0
var next_hit_frame := 0
var meter := 0
var focus := 0
var move_focus := 0 # focus level the current move started with
## This fighter's projectile in flight (one at a time), ticked by FightManager.
var projectile: Projectile
## Set by FightManager during the super freeze (holds animation).
var frozen := false
var _landing_frames := LANDING_FRAMES
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
## This character's specials in MOTION_PRIORITY order: [move, motion, sequence, buttons, window].
var _specials: Array[Array] = []
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
	_specials.clear()
	for motion: String in MOTION_PRIORITY:
		for move in data.moves:
			if move.motion() == motion:
				var window := SUPER_MOTION_WINDOW if move.super_move or motion.length() >= 5 else MOTION_WINDOW
				_specials.append([move, motion, _motion_sequence(motion), _special_buttons(move.input.substr(motion.length())), window])


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
	hits_landed = 0
	next_hit_frame = 0
	_landing_frames = LANDING_FRAMES
	if projectile:
		projectile.queue_free()
		projectile = null
	frozen = false
	input = InputBuffer.new()
	input_locked = false
	juggle_hits = 0
	air_attack_used = false
	throw_grab_frame = -1
	grab_move = null
	throw_techable = true
	sidestep_dir = Vector3.ZERO
	last_hit_level = MoveData.HitLevel.MID
	victory = false
	victory_clip = &""
	move_focus = 0
	_set_focus(0)
	_set_combo(0)
	_set_state(State.IDLE)
	health_changed.emit(health, data.max_health)
	visual.rotation = Vector3.ZERO
	reset_physics_interpolation()


## Rollback snapshot of this fighter's whole simulation state.
func save_state() -> Dictionary:
	var state := {transform = transform, input = input.save_state(),
		projectile = projectile.save_state() if projectile else []}
	for field in SIM_FIELDS:
		state[field] = get(field)
	return state


## Restores a snapshot from save_state(). The HUD is refreshed through the usual signals.
func load_state(state: Dictionary) -> void:
	var old_health := health
	var old_meter := meter
	var old_focus := focus
	var old_combo := combo_hits
	for field in SIM_FIELDS:
		set(field, state[field])
	transform = state.transform
	input.load_state(state.input)
	var saved_projectile: Array = state.projectile
	if saved_projectile.is_empty():
		if projectile:
			projectile.queue_free()
			projectile = null
	else:
		if not projectile:
			projectile = Projectile.new()
			projectile.owner_fighter = self
			projectile.move = saved_projectile[0]
			projectile.name = "Projectile"
			add_sibling(projectile)
			projectile.load_state(saved_projectile)
			projectile.reset_physics_interpolation()
		else:
			projectile.load_state(saved_projectile)
	if health != old_health:
		health_changed.emit(health, data.max_health)
	if meter != old_meter:
		meter_changed.emit(meter, MAX_METER)
	if focus != old_focus:
		focus_changed.emit(focus)
	if combo_hits != old_combo:
		combo_changed.emit(combo_hits)


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
			if state_frame >= _landing_frames:
				_landing_frames = LANDING_FRAMES
				_return_to_neutral()
		State.DASH:
			if state_frame <= DASH_SPECIAL_CANCEL and _try_special(false):
				_apply_motion()
				return
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
			if throw_techable and state_frame <= THROW_TECH_WINDOW and _throw_pressed():
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
	var move := current_move
	var airborne := position.y > 0.0
	var frame := state_frame
	var active := frame > move.startup and frame <= move.startup + move.active
	if active and move.travel > 0.0 and hits_landed < move_hits():
		velocity = Vector3(0.0, velocity.y, 0.0) + forward * move.travel
	elif not airborne:
		velocity = _with_friction(velocity)
	if frame == move.startup + 1:
		move_active.emit(self, move)
		if move.rise > 0.0:
			velocity.y = move.rise + move.focus_rise * move_focus
		if move.dive != Vector2.ZERO and airborne:
			velocity = forward * move.dive.x + Vector3.DOWN * move.dive.y
		if move.focus_gain > 0:
			_set_focus(mini(MAX_FOCUS, focus + move.focus_gain))
		if move.projectile_speed > 0.0:
			_fire_projectile(move)
	if move_has_hit and frame > move.startup and _try_attack(true):
		return
	# A connected move with a follow-up chains into it right after its active frames;
	# a whiff plays out its full recovery.
	var followup := move.focus_followup if move.focus_followup != "" and move_focus >= MAX_FOCUS else move.followup
	if followup != "" and move_has_hit and frame >= move.startup + move.active:
		var next := _move_for_input(followup)
		if next:
			_start_move(next, false, move_focus)
			return
	if frame >= move.total_frames():
		if airborne:
			if move.rise > 0.0:
				_landing_frames = LANDING_FRAMES + move.landing_recovery
			current_move = null
			air_attack_used = true
			_set_state(State.JUMP) # attack finished in the air; keep falling, no second attack
		else:
			_return_to_neutral()


## Starts a buffered attack. With `cancel_only` (the current move connected), only its
## cancel_into moves, specials (from a normal) or a super (from a special) are allowed.
func _try_attack(cancel_only: bool) -> bool:
	# Every normal and special needs a fresh attack press: skip the lookups without one.
	var any_press := false
	for button: int in ATTACK_BUTTONS:
		if input.pressed_within(button, BUFFER_WINDOW):
			any_press = true
			break
	if not any_press:
		return false
	var airborne := state == State.JUMP
	if not airborne and _try_special(cancel_only):
		return true
	var dir := input.dir()
	for button: int in ATTACK_BUTTONS:
		if not input.pressed_within(button, BUFFER_WINDOW):
			continue
		var move := _find_move(button, dir, airborne)
		if move == null or (cancel_only and move.input not in current_move.cancel_into):
			continue
		input.consume(button)
		_start_move(move, airborne)
		return true
	return false


## Motion-input specials. "P" accepts either punch, "K" either kick.
func _try_special(cancel_only: bool) -> bool:
	if cancel_only:
		var since_active := state_frame - current_move.startup - current_move.active
		if current_move.super_move or since_active > SPECIAL_CANCEL_WINDOW or position.y > 0.0:
			return false
	for special: Array in _specials:
		var move: MoveData = special[0]
		if cancel_only and current_move.is_special() and not move.super_move:
			continue
		if move.super_move and meter < MAX_METER:
			continue
		if move.projectile_speed > 0.0 and projectile != null:
			continue
		var pressed := []
		for b: int in special[3]:
			if input.pressed_within(b, BUFFER_WINDOW):
				pressed.append(b)
		if pressed.is_empty():
			continue
		if not input.motion(special[2], special[4], MOTION_FINISH + BUFFER_WINDOW):
			continue
		for b: int in pressed:
			input.consume(b)
		_start_move(move, false)
		return true
	return false


func _motion_sequence(motion: String) -> Array:
	var sequence := []
	for c in motion:
		sequence.append(int(c))
	return sequence


func _special_buttons(suffix: String) -> Array:
	match suffix:
		"P":
			return [InputBuffer.HP, InputBuffer.LP]
		"K":
			return [InputBuffer.HK, InputBuffer.LK]
	var button = InputBuffer.BUTTON_NAMES.find_key(suffix)
	return [button] if button != null else []


## `carried_focus`: a follow-up keeps the focus level its first move started with.
func _start_move(move: MoveData, airborne: bool, carried_focus := -1) -> void:
	current_move = move
	move_focus = focus if carried_focus < 0 else carried_focus
	if move.focus_consume:
		_set_focus(0)
	move_has_hit = false
	hits_landed = 0
	next_hit_frame = 0
	air_attack_used = air_attack_used or airborne
	# Crouching normals (2LP...) crouch; specials whose motion starts with 2 (236, 214) don't.
	_set_state(State.ATTACK, (move.input.begins_with("2") and not move.is_special()) or move.low_profile)
	if move.lunge > 0.0 and not airborne:
		velocity = forward * move.lunge
	if move.super_move:
		add_meter(-MAX_METER)
		super_started.emit(self, move)
	elif move.is_special():
		add_meter(METER_PER_SPECIAL)
	attack_started.emit(move)


func _fire_projectile(move: MoveData) -> void:
	projectile = Projectile.new()
	projectile.setup(self, move)
	add_sibling(projectile)


func _set_focus(level: int) -> void:
	if level != focus:
		focus = level
		focus_changed.emit(focus)


## Hits of the current move, with its focus bonus.
func move_hits() -> int:
	return current_move.hits + current_move.focus_hits * move_focus


## Ticks between the current move's hits: focus bonus hits are fitted into the same
## active frames.
func _hit_interval() -> int:
	var hits := move_hits()
	if hits == current_move.hits:
		return current_move.hit_interval
	return maxi(2, (current_move.active - 1) / (hits - 1))


## Damage multiplier of `move` from this fighter's focus when the move started.
func focus_damage_scale(move: MoveData) -> float:
	return 1.0 + move.focus_damage * move_focus


func add_meter(amount: int) -> void:
	var value := clampi(meter + amount, 0, MAX_METER)
	if value != meter:
		meter = value
		meter_changed.emit(meter, MAX_METER)


## Picks the move for a button given the held direction (numpad, facing-relative).
## Air moves use "j." inputs only. On the ground: down/down-diagonals → "2", forward →
## "6", back → "4"; each falls back to the plain standing move.
func _find_move(button: int, dir: int, airborne: bool) -> MoveData:
	var button_name: String = InputBuffer.BUTTON_NAMES[button]
	if airborne:
		# Down + button in the air: "j.2LK", or "j.2K" for either kick (dive kicks).
		var dive_move: MoveData = null
		if dir <= 3:
			dive_move = _move_for_input("j.2" + button_name)
			if dive_move == null:
				dive_move = _move_for_input("j.2" + button_name.right(1))
		return dive_move if dive_move else _move_for_input("j." + button_name)
	var prefix := ""
	if dir <= 3:
		prefix = "2"
	elif dir == 6:
		prefix = "6"
	elif dir == 4:
		prefix = "4"
	var move := _move_for_input(prefix + button_name) if prefix != "" else null
	return move if move else _move_for_input(button_name)


## Exact input lookup (also finds "~" follow-ups).
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
			# Rising moves keep their landing lag; a dive kick only when it missed.
			if current_move and (current_move.rise > 0.0 or (current_move.dive != Vector2.ZERO and not move_has_hit)):
				_landing_frames = LANDING_FRAMES + current_move.landing_recovery
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
	if new_state != State.JUMP and new_state != State.LANDING:
		_landing_frames = LANDING_FRAMES # only a rising move's own fall keeps the extra lag
	state = new_state
	state_frame = 0
	crouching = crouch
	if new_state == State.KNOCKDOWN or new_state == State.KO:
		_set_focus(0)


# --- Combat ----------------------------------------------------------------------

## Active hitbox this tick as {center: Vector3, radius: float}, or {} if none.
func get_active_hitbox() -> Dictionary:
	if state != State.ATTACK or current_move.projectile_speed > 0.0 or current_move.command_grab 			or current_move.hitbox_radius <= 0.0:
		return {}
	if hits_landed >= move_hits() or state_frame < next_hit_frame:
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
	if is_invulnerable():
		return false
	var top := (CROUCH_HEIGHT if crouching else STAND_HEIGHT) - BODY_RADIUS
	var a := position + Vector3.UP * BODY_RADIUS
	var b := position + Vector3.UP * top
	var closest := Geometry3D.get_closest_point_to_segment(center, a, b)
	return closest.distance_to(center) <= radius + BODY_RADIUS


## Startup invincibility of the current move (reversals, supers).
func is_invulnerable() -> bool:
	return state == State.ATTACK and current_move != null and state_frame <= current_move.invuln_frames


## Applies a hit from `attacker` and reports whether it hit, was blocked, or counter-hit.
## `push_dir` overrides the knockback direction (projectiles). On a multi-hit move only
## the `final` hit launches or knocks down; the others keep the victim close.
func receive_hit(attacker: Fighter, move: MoveData, push_dir := Vector3.ZERO, final := true) -> HitResult:
	if push_dir == Vector3.ZERO:
		push_dir = attacker.forward
	var knockback := move.knockback if final else Vector2(MULTI_HIT_KNOCKBACK, 0.0)
	hitstop = move.hitstop
	if _can_block(move.hit_level):
		var crouch_block := input.dir() == 1
		_set_state(State.BLOCKSTUN, crouch_block)
		stun = move.blockstun
		velocity = push_dir * knockback.x * BLOCK_PUSHBACK_SCALE / data.weight
		_flash_color = Color(0.4, 0.7, 1.0)
		if move.chip_damage > 0:
			_take_damage(move.chip_damage)
			if health == 0:
				_knock_out(push_dir)
		return HitResult.BLOCKED

	var counter := state == State.ATTACK and current_move != null \
			and state_frame <= current_move.startup + current_move.active
	var airborne := position.y > 0.0 or state in [State.JUMP, State.AIR_HIT]
	if airborne and final:
		juggle_hits += 1
	var scale := maxf(MIN_COMBO_SCALE, 1.0 - COMBO_SCALING_STEP * combo_hits)
	if counter:
		scale *= COUNTER_DAMAGE_SCALE
	_take_damage(roundi(move.damage * scale * attacker.focus_damage_scale(move)))
	_set_combo(combo_hits + 1)
	_flash_color = Color(1.0, 0.85, 0.3) if counter else Color.WHITE
	last_hit_level = move.hit_level
	current_move = null
	velocity = push_dir * knockback.x / data.weight + Vector3.UP * knockback.y

	if health == 0:
		_knock_out(push_dir)
	elif airborne or (move.launches and final):
		velocity.y = maxf(velocity.y, JUGGLE_MIN_UP_SPEED if final else 1.5)
		_set_state(State.AIR_HIT)
	elif move.knockdown and final:
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
	hits_landed += 1
	next_hit_frame = state_frame + _hit_interval()
	hitstop = current_move.hitstop


## True if the next hit of the current move is its last (multi-hit moves).
func is_final_hit() -> bool:
	return current_move == null or hits_landed + 1 >= move_hits()


## Match win: play `clip` from the start (cosmetic; the fighter stays in its idle state).
func start_victory(clip: StringName) -> void:
	victory = true
	victory_clip = clip
	_victory_time = 0.0


## True while this fighter's attack (or projectile) could connect with `target` soon.
func is_threatening(target: Fighter) -> bool:
	return threat_move(target) != null


## The attack about to reach `target`: the current move in startup/active within reach,
## or an approaching projectile. Null if none.
func threat_move(target: Fighter) -> MoveData:
	if projectile and projectile.is_threatening(target):
		return projectile.move
	if state != State.ATTACK or current_move == null or current_move.projectile_speed > 0.0 			or current_move.hitbox_radius <= 0.0:
		return null
	if state_frame > current_move.startup + current_move.active:
		return null
	var reach := absf(current_move.hitbox_offset.z) + current_move.hitbox_radius + BODY_RADIUS
	reach += current_move.travel * current_move.active * DT
	return current_move if _flat_distance_to(target) <= reach + PROXIMITY_GUARD_MARGIN else null


func _flat_distance_to(other: Fighter) -> float:
	return Vector2(other.position.x - position.x, other.position.z - position.z).length()


## True on the tick a throw's grab checks for a target (FightManager resolves it).
func is_throw_grab_frame() -> bool:
	return state == State.THROW and throw_grab_frame < 0 and state_frame == THROW_STARTUP


## True on a command grab's first active frame (FightManager resolves the grab).
func is_command_grab_frame() -> bool:
	return state == State.ATTACK and current_move != null and current_move.command_grab \
			and state_frame == current_move.startup + 1


## True if this fighter's reversal stance catches `move` (a body strike) right now.
func reverses(move: MoveData) -> bool:
	return state == State.ATTACK and current_move != null and current_move.reversal 			and state_frame > current_move.startup and state_frame <= current_move.startup + current_move.active 			and move.hit_level != MoveData.HitLevel.LOW


func is_projectile_immune() -> bool:
	return state == State.ATTACK and current_move != null and current_move.projectile_immune \
			and state_frame <= current_move.startup + current_move.active


func is_throwable() -> bool:
	return position.y <= 0.0 and state not in NOT_THROWABLE_STATES and not is_invulnerable()


## Called on the attacker when its grab connects.
func on_throw_grabbed() -> void:
	throw_grab_frame = state_frame


## Called on the attacker when its command grab connects: becomes a held throw that
## deals the move's damage.
func on_command_grab() -> void:
	grab_move = current_move
	current_move = null
	velocity = Vector3.ZERO
	_set_state(State.THROW)
	throw_grab_frame = 0


## Called on the defender when grabbed: held in front of the attacker.
func on_grabbed_by(attacker: Fighter, techable: bool = true) -> void:
	throw_techable = techable
	current_move = null
	velocity = Vector3.ZERO
	var before := position
	position = attacker.position + attacker.forward * THROW_HOLD_DISTANCE
	clamp_to_bounds()
	face_opponent()
	_set_state(State.THROWN)
	# Cosmetic: the model eases into the hold instead of jumping (a reversed jump-in is
	# pulled down from the air).
	_grab_snap = before - position
	reset_physics_interpolation()


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
		grab_move = null
		_return_to_neutral()


## Thrown: damage, then tossed into a knockdown (no juggles after a throw).
func _release_from_throw(attacker: Fighter) -> void:
	var push_dir := attacker.forward
	var grab := attacker.grab_move
	_take_damage(grab.damage if grab else attacker.data.throw_damage)
	throw_impact.emit(self)
	_set_combo(1)
	_flash_color = Color.WHITE
	hitstop = grab.hitstop if grab else 8
	attacker.hitstop = hitstop
	juggle_hits = MAX_JUGGLE_HITS
	throw_techable = true
	# Command grabs slam harder: a higher toss.
	velocity = push_dir * 2.5 + Vector3.UP * (6.0 if grab else 4.5)
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
	var depth := bounds_depth - 0.01
	return (direction.x > 0.1 and position.x >= limit) or (direction.x < -0.1 and position.x <= -limit) \
			or (direction.z > 0.1 and position.z >= depth) or (direction.z < -0.1 and position.z <= -depth)


func clamp_to_bounds() -> void:
	position.x = clampf(position.x, -bounds_half_extent, bounds_half_extent)
	position.z = clampf(position.z, -bounds_depth, bounds_depth)


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
	var frozen := hitstop > 0 or self.frozen
	var request := _animation_request(frozen)
	# Hitstop freezes the pose outright; the super freeze holds the clip time but lets a
	# cross-fade finish, so nobody is stuck mid-blend in the close-up.
	model.show_clip(request[0], request[1], request[2], 0.0 if hitstop > 0 else delta)
	# The face keeps moving through hitstop, so the reaction lands with the impact.
	model.set_face(face_expression(), delta)
	model.set_gaze(gaze_target(), delta)
	var shake := Vector3.ZERO
	if frozen and state in [State.HITSTUN, State.BLOCKSTUN, State.AIR_HIT, State.KO]:
		shake.x = randf_range(-0.03, 0.03)
	if state == State.THROWN and state_frame < GRAB_SNAP_FRAMES:
		var f := (float(state_frame) + Engine.get_physics_interpolation_fraction()) / GRAB_SNAP_FRAMES
		shake += global_transform.basis.inverse() * (_grab_snap * (1.0 - smoothstep(0.0, 1.0, f)))
	model.position = shake


## Logic → facial expression (a FighterModel.EXPRESSIONS key). Cosmetic.
func face_expression() -> StringName:
	match state:
		State.ATTACK:
			var move := current_move
			var through_active := state_frame <= move.startup + move.active + 6
			if move.super_move or move.name.begins_with("~"):
				return &"roar"
			if through_active and (move.is_special() or move.damage >= 80):
				return &"shout" if state_frame > move.startup / 2 else &"effort"
			return &"effort" if through_active else &"neutral"
		State.THROW:
			return &"shout" if throw_grab_frame >= 0 else &"effort"
		State.HITSTUN, State.AIR_HIT, State.THROWN:
			return &"pain"
		State.BLOCKSTUN:
			return &"guard"
		State.KNOCKDOWN:
			return &"dazed"
		State.GETUP, State.JUMP_SQUAT, State.JUMP, State.DASH:
			return &"effort"
		State.KO:
			return &"out"
		State.TECH:
			return &"surprise"
	if victory:
		return &"grin" if victory_clip != &"" else &"smirk"
	return &"neutral"


## Where the eyes look (world space, Vector3.INF = straight ahead). Cosmetic: the
## opponent's upper chest (fighters watch the shoulders, not the eyes), the camera in a
## win, nowhere in particular when down.
const GAZE_DROP := 0.3 # metres below the opponent's eyes


func gaze_target() -> Vector3:
	if state in [State.KNOCKDOWN, State.KO]:
		return Vector3.INF
	if victory:
		var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
		return camera.global_position if camera else Vector3.INF
	if opponent and opponent.model:
		return opponent.model.eye_position() + Vector3.DOWN * GAZE_DROP
	return Vector3.INF


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
			if grab_move and grab_move.reversal:
				return [&"fight/reversal_throw", t, 1.0]
			return [&"fight/throw", t if throw_grab_frame >= 0 else minf(t, 0.25), 1.0]
		State.THROWN:
			if opponent and opponent.grab_move and opponent.grab_move.reversal:
				return [&"fight/reversed", t, 1.0]
			return [&"fight/thrown", t, 1.0]
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
