class_name FighterShowcase
extends RefCounted
## Character select preview routine: the focused fighter shows off moves in a loop that
## matches their CPU personality, instead of just turning on the turntable. Moves play
## with the same frame data and clip timing as in a fight (startup maps to the clip up to
## the impact, active + recovery to the rest); rising moves lift off, travelling moves
## slide forward and glide back, Ki Blast fires a glowing orb and Earthquake sends a
## shockwave across the disc. The turntable rests at a 3/4 angle and turns side-on for
## attacks so they read clearly.
##
## Routine steps: ["move", input] (from the character's MoveData), ["clip", animation,
## seconds] (played once, e.g. a victory pose), ["idle", seconds, optional clip, speed].

const ROUTINES := {
	# Zoner: measured, keeps distance: fireball, anti-air, a clean string, a bow.
	&"kenji": [["idle", 1.0], ["move", "236P"], ["idle", 1.1], ["move", "623P"], ["idle", 1.0],
		["move", "LP"], ["move", "HP"], ["idle", 1.0], ["clip", &"fight/victory_bow", 3.0], ["idle", 1.2]],
	# Rushdown: barely stops: kick flurry, slide, rushing hook, rising kick.
	&"rhea": [["idle", 0.5, &"fight/guard", 1.8], ["move", "236236K"], ["idle", 0.4, &"fight/guard", 1.8],
		["move", "236K"], ["idle", 0.4, &"fight/guard", 1.8], ["move", "6HP"], ["move", "623K"],
		["idle", 0.6, &"fight/guard", 1.8], ["clip", &"fight/victory_point", 2.4], ["idle", 0.4, &"fight/guard", 1.8]],
	# Grappler: walks you down, spins, reaches for the grab, knees, flexes.
	&"valka": [["idle", 1.3, &"fight/walk_guard", 0.6], ["move", "623P"], ["idle", 0.8],
		["move", "63214P"], ["idle", 0.8], ["move", "6LK"], ["move", "6HP"], ["idle", 0.8],
		["clip", &"fight/victory_flex", 2.6], ["idle", 1.0, &"fight/walk_guard", 0.6]],
	# Punisher: waits with folded arms, then slams, charges, smashes, flexes.
	&"brutus": [["idle", 2.2, &"ual2/Idle_FoldArms", 1.0], ["move", "214P"], ["idle", 1.6],
		["move", "236P"], ["idle", 1.4], ["move", "6HP"], ["idle", 1.0],
		["clip", &"fight/victory_flex", 2.6], ["idle", 1.6, &"ual2/Idle_FoldArms", 1.0]],
}
const REST_ANGLE := 0.75 # radians: 3/4 view while idle
const ATTACK_ANGLE := 1.35 # side-on while attacking
const TURN_SPEED := 5.0
const GRAVITY := 20.0
const TRAVEL_SCALE := 0.25 # travelling moves cover a fraction of their real distance here
const RISE_SCALE := 0.45 # rising moves lift off only a little, staying in frame
const RETURN_SPEED := 2.5 # m/s gliding back to the center

var model: FighterModel
var data: CharacterData
var pivot: Node3D
var fx_parent: Node3D

var _steps: Array = []
var _moves := {}
var _index := 0
var _time := 0.0
var _frame := 0.0
var _impact_done := false
var _offset := Vector3.ZERO # model offset in the pivot's space (rise, travel)
var _y_velocity := 0.0


func _init(fighter_model: FighterModel, character: CharacterData, turntable: Node3D, effects_parent: Node3D) -> void:
	model = fighter_model
	data = character
	pivot = turntable
	fx_parent = effects_parent
	for move in character.moves:
		_moves[move.input] = move
	restart()


func restart() -> void:
	_steps = (ROUTINES.get(data.id, [["idle", 999.0]]) as Array).duplicate(true)
	_index = 0
	_begin_step()
	_offset = Vector3.ZERO
	_y_velocity = 0.0
	model.position = Vector3.ZERO


func process(delta: float) -> void:
	var step: Array = _steps[_index]
	_time += delta
	var target_angle := REST_ANGLE
	match step[0]:
		"idle":
			var clip: StringName = step[2] if step.size() > 2 else &"fight/guard"
			model.show_clip(clip, -1.0, step[3] if step.size() > 3 else 1.0, delta)
			if _time >= step[1]:
				_next()
		"clip":
			model.show_clip(step[1], minf(_time, model.clip_length(step[1])), 1.0, delta)
			if _time >= step[2]:
				_next()
		"move":
			target_angle = ATTACK_ANGLE
			_process_move(_moves.get(step[1]), delta)
	pivot.rotation.y = lerp_angle(pivot.rotation.y, target_angle, 1.0 - exp(-TURN_SPEED * delta))
	# Gravity for rising moves; glide back to the center once a travelling move is over.
	if _offset.y > 0.0 or _y_velocity > 0.0:
		_y_velocity -= GRAVITY * delta
		_offset.y = maxf(_offset.y + _y_velocity * delta, 0.0)
		if _offset.y == 0.0:
			_y_velocity = 0.0
	if step[0] != "move":
		_offset.z = move_toward(_offset.z, 0.0, RETURN_SPEED * delta)
	model.position = _offset


func _process_move(move: MoveData, delta: float) -> void:
	if move == null:
		_next()
		return
	_frame += delta * 60.0
	model.show_clip(move.animation, _clip_time(move, _frame), 1.0, delta)
	var active := _frame > move.startup and _frame <= move.startup + move.active
	if active and move.travel > 0.0:
		_offset.z -= move.travel * TRAVEL_SCALE * delta # the model faces -Z
	if not _impact_done and _frame > move.startup:
		_impact_done = true
		if move.rise > 0.0:
			_y_velocity = move.rise * RISE_SCALE
		if move.projectile_speed > 0.0:
			_fire_orb(move)
		if move.impact_fx == &"shockwave":
			_shockwave()
	if _frame >= move.total_frames() and _offset.y <= 0.0:
		var follow := _moves.get(move.followup) as MoveData if move.followup != "" else null
		if follow:
			_steps[_index] = ["move", move.followup] # supers chain into their finisher
			_begin_step()
		else:
			_next()


## Same mapping as Fighter._attack_clip_time: the strike lands on the first active frame.
func _clip_time(move: MoveData, f: float) -> float:
	var impact_frame := float(move.startup + 1)
	if f <= impact_frame:
		return move.animation_impact * f / impact_frame
	var end_time: float = move.animation_end if move.animation_end > 0.0 else model.clip_length(move.animation)
	return lerpf(move.animation_impact, end_time, clampf((f - impact_frame) / maxf(move.total_frames() - impact_frame, 1.0), 0.0, 1.0))


func _next() -> void:
	var step: Array = _steps[_index]
	# A super step rewritten to its finisher goes back to the super for the next loop.
	if step[0] == "move" and String(step[1]).begins_with("~"):
		_steps[_index] = ROUTINES[data.id][_index].duplicate()
	_index = (_index + 1) % _steps.size()
	_begin_step()


func _begin_step() -> void:
	_time = 0.0
	_frame = 0.0
	_impact_done = false


# --- Effects (inside the preview's own 3D world) ----------------------------------

func _fire_orb(move: MoveData) -> void:
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = move.projectile_color.lightened(0.6)
	mat.emission_enabled = true
	mat.emission = move.projectile_color
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = mat
	orb.mesh = sphere
	var light := OmniLight3D.new()
	light.light_color = move.projectile_color
	light.light_energy = 2.0
	light.omni_range = 2.0
	orb.add_child(light)
	fx_parent.add_child(orb)
	var forward := pivot.global_basis * Vector3(0, 0, -1)
	var start := model.global_transform * Projectile.SPAWN_OFFSET
	orb.global_position = start
	var tween := orb.create_tween().set_parallel()
	tween.tween_property(orb, "global_position", start + forward * 2.6, 0.7)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25).set_delay(0.45)
	tween.tween_property(light, "light_energy", 0.0, 0.25).set_delay(0.45)
	tween.chain().tween_callback(orb.queue_free)


func _shockwave() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.9, 0.7, 0.9)
	torus.material = mat
	ring.mesh = torus
	fx_parent.add_child(ring)
	var forward := pivot.global_basis * Vector3(0, 0, -1)
	ring.global_position = model.global_position + forward * 0.6 + Vector3.UP * 0.04
	ring.scale = Vector3(0.2, 0.05, 0.2)
	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3(4.0, 0.2, 4.0), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)
