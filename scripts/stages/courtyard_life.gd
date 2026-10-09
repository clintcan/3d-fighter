class_name CourtyardLife
extends Node
## Everything that moves in the Kowloon Courtyard (built by tools/build_courtyard_stage.gd):
##
## - The sun rises over the match: dawn in round 1 (the sun still below the skyline, the
##   gate lamp and windows lit), low sun on the tenements in round 2, golden light on the
##   courtyard floor in the final round. The sky, haze, lights and the skyline's windows
##   ease between rounds; a restarted match is dawn again.
## - The neighbourhood wakes up: the corner store's shutter rolls up in round 2, and
##   neighbours come out (the cook at the kitchen door, someone at the gate, people on the
##   balconies, a kid on the wall), more of them each round and as the crowd gets excited
##   (StageAmbience.excitement). They raise their arms and bounce when it's wild.
## - Props react: pigeons scatter from the wall and ledges on supers, knockdowns and
##   K.O.s and come back later; the cat on the wall bolts; laundry billows and lanterns
##   swing; the kitchen steam puffs.
## - Now and then a jet comes in low over the skyline (a nod to Kai Tak), its roar rising
##   and fading, rattling the laundry and the camera as it passes.
##
## Cosmetic only: real time, its own random numbers, fight events through
## FightManager.cosmetic() (never during rollback re-simulation), and nothing here is read
## by the simulation. Neighbours and pigeons are MultiMeshes built at run time.

## Day level (0 = dawn, 1 = morning) per round number (index); later rounds use the last.
const DAY_BY_ROUND := [0.0, 0.0, 0.55, 1.0]
## How fast the day moves toward its round's level (per second): a few seconds.
const DAY_RATE := 0.22
## Sun elevation (degrees) at dawn and in the morning. It rises behind the camera, over
## the stage's unseen "SunBlocker" block: low, it lights only the shed roofs, the upper
## floors and the skyline (round 2); higher, it clears the block and floods the floor.
const SUN_ELEVATION := Vector2(-4.0, 38.0)
const SUN_HEADING := Vector2(0.28, 0.96) # toward the sun, on the ground (x, z)
const SKY_TOP := [Color(0.1, 0.13, 0.3), Color(0.3, 0.5, 0.82)]
const SKY_HORIZON := [Color(0.95, 0.56, 0.46), Color(0.86, 0.84, 0.78)]
const GROUND_HORIZON := [Color(0.6, 0.4, 0.38), Color(0.62, 0.6, 0.56)]
const SUN_COLOR := [Color(1.0, 0.52, 0.28), Color(1.0, 0.92, 0.8)]
const HAZE := [Color(0.72, 0.6, 0.66), Color(0.8, 0.82, 0.86)]
## Neighbours out to watch per round, plus up to EXCITED_EXTRA more as the crowd gets going.
const NEIGHBOURS_BY_ROUND := [0, 2, 5, 7]
const EXCITED_EXTRA := 3
const CHEER_EXCITEMENT := 0.5
const APPEAR_SECONDS := 1.1
## Jet: first pass this long after the stage loads, then every so often.
const JET_FIRST := Vector2(22.0, 38.0)
const JET_INTERVAL := Vector2(55.0, 85.0)
const JET_SECONDS := 26.0
const JET_PEAK := 13.5 # when it's closest (the sound's loudest moment)
const JET_SPEED := 78.0
const JET_PATH_Z := -190.0
const PIGEON_RETURN := Vector2(8.0, 15.0)
const CAT_RETURN := Vector2(18.0, 30.0)
const FIGURE_SHADER := "res://assets/stages/courtyard/figure.gdshader"
const JET_SOUND := "res://assets/audio/ambience/jet_flyover.ogg"
const PIGEON_SOUNDS := ["res://assets/audio/ambience/pigeons_takeoff_1.ogg", "res://assets/audio/ambience/pigeons_takeoff_2.ogg"]
const SHUTTER_SOUND := "res://assets/audio/ambience/shutter_roll.ogg"

@export var window_material: StandardMaterial3D
@export var lamp_material: StandardMaterial3D
@export var shop_material: StandardMaterial3D
@export var skyline_material: ShaderMaterial
@export var laundry_material: ShaderMaterial
@export var perches := PackedVector3Array()
@export var neighbour_spots := PackedVector3Array()
@export var neighbour_yaws := PackedFloat32Array()
@export var neighbour_hidden := PackedVector3Array()
@export var neighbour_kinds := PackedInt32Array() # 0 standing, 1 on a balcony, 2 a kid
@export var steam: Array[NodePath] = []
@export var lanterns: Array[NodePath] = []
@export var cat_escape := Vector3.ZERO
## Day level when there's no fight (stage previews, thumbnails).
@export var idle_day := 0.0

var day := 0.0
var day_target := 0.0
var shutter_open := 0.0 # 0 closed .. 1 rolled up
var gust := 0.0
var manager: Node
var _applied_day := -1.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _last_round := 0
var _ready_done := false
var _sun: DirectionalLight3D
var _world: WorldEnvironment
var _lamp: Light3D
var _lamp_energy := 0.0
var _lamp_emission := 0.0
var _window_emission := 0.0
var _fill: Light3D
var _fill_energy := 0.0
var _shop_light: Light3D
var _shutter: Node3D
var _neon: Label3D
var _neon_color := Color.WHITE
var _sound: Node # StageAmbience (excitement)
var _player: AudioStreamPlayer
var _jet_player: AudioStreamPlayer
# Neighbours: per spot [order, progress 0..1, appearing, phase, arm raise].
var _people: MultiMeshInstance3D
var _arms: MultiMeshInstance3D
var _neighbour_state := []
var _visible_target := 0
# Pigeons: per perch [state, timer, position, velocity, return-from, heading].
enum Pigeon { PERCHED, FLEEING, AWAY, RETURNING }
var _pigeons: MultiMeshInstance3D
var _wings: Array[MultiMeshInstance3D] = []
var _pigeon_state := []
# Cat: [state, timer]; jet: time into the current pass (< 0 = waiting).
enum Cat { SITTING, RUNNING, AWAY, RETURNING }
var _cat: Node3D
var _cat_home := Vector3.ZERO
var _cat_state := Cat.SITTING
var _cat_timer := 0.0
var _jet: Node3D
var _jet_time := -1.0
var _next_jet := 0.0
var _jet_peaked := false
var _lantern_nodes: Array[Node3D] = []
var _lantern_swing := [] # per lantern [angle, velocity]
var _steam_nodes: Array[GPUParticles3D] = []
var _steam_base := []
var _next_puff := 3.0
var _puff_until := 0.0


func _ready() -> void:
	_rng.seed = hash(get_path()) ^ Time.get_ticks_usec()
	var stage := get_parent()
	_sun = stage.get_node_or_null("Lights/Sun")
	_world = stage.get_node_or_null("WorldEnvironment")
	_lamp = stage.get_node_or_null("Lights/GateLamp")
	_fill = stage.get_node_or_null("Lights/FrontFill")
	_shop_light = stage.get_node_or_null("Lights/ShopLight")
	_shutter = stage.get_node_or_null("Shutter")
	_neon = stage.get_node_or_null("MahjongNeon")
	_cat = stage.get_node_or_null("Cat")
	_jet = stage.get_node_or_null("Jet")
	_sound = stage.get_node_or_null("Sound")
	if _lamp:
		_lamp_energy = _lamp.light_energy
	if _fill:
		_fill_energy = _fill.light_energy
	if _neon:
		_neon_color = _neon.modulate
	if lamp_material:
		_lamp_emission = lamp_material.emission_energy_multiplier
	if window_material:
		_window_emission = window_material.emission_energy_multiplier
	if _cat:
		_cat_home = _cat.position
	for path in lanterns:
		var lantern := get_node_or_null(path) as Node3D
		if lantern:
			_lantern_nodes.append(lantern)
			_lantern_swing.append([_rng.randf_range(-0.05, 0.05), 0.0])
	_player = _audio_player(-9.0)
	_jet_player = _audio_player(-5.0)
	_jet_player.stream = load(JET_SOUND)
	_next_jet = _rng.randf_range(JET_FIRST.x, JET_FIRST.y)
	_build_neighbours()
	_build_pigeons()
	day = idle_day
	day_target = idle_day
	_connect_fight.call_deferred()


## Settings and particles are adjusted by Stage._ready, which runs after ours: read the
## steam's base amounts on the first frame.
func _late_ready() -> void:
	_ready_done = true
	for path in steam:
		var particles := get_node_or_null(path) as GPUParticles3D
		if particles:
			_steam_nodes.append(particles)
			_steam_base.append(particles.amount_ratio)


func _connect_fight() -> void:
	var node := get_parent()
	while node:
		if node.has_method("cosmetic") and "fighters" in node:
			manager = node
			break
		node = node.get_parent()
	if manager == null:
		return
	for fighter: Fighter in manager.fighters:
		fighter.landed_hard.connect(manager.cosmetic(func(_f: Fighter) -> void: react(0.35)))
		fighter.knocked_out.connect(manager.cosmetic(func(_f: Fighter) -> void:
			react(0.8)
			_puff_until = _time + 1.5))
	manager.super_flash.connect(manager.cosmetic(func(_f: Fighter, _m: MoveData) -> void: react(0.6)))
	manager.throw_landed.connect(manager.cosmetic(func(_a: Fighter, _d: Fighter) -> void: react(0.25)))


func _process(delta: float) -> void:
	if not _ready_done:
		_late_ready()
	_time += delta
	_follow_rounds()
	day = move_toward(day, day_target, DAY_RATE * delta)
	if absf(day - _applied_day) > 0.0005:
		_apply_day()
	_update_shutter(delta)
	_update_neighbours(delta)
	_update_pigeons(delta)
	_update_cat(delta)
	_update_jet(delta)
	_update_swing(delta)
	_update_steam()


## A shock in the courtyard: `strength` 0..1 billows the laundry, swings the lanterns,
## scatters some of the pigeons and, if hard enough, sends the cat running.
func react(strength: float) -> void:
	gust = minf(gust + strength, 1.0)
	for swing: Array in _lantern_swing:
		swing[1] += strength * _rng.randf_range(0.8, 1.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
	scatter_pigeons(strength)
	if strength >= 0.5 and _cat_state == Cat.SITTING:
		_cat_state = Cat.RUNNING


# --- The day -------------------------------------------------------------------------

func _follow_rounds() -> void:
	if manager == null:
		return
	var round_number: int = manager.round_number
	if round_number < _last_round or (_last_round == 0 and round_number <= 1):
		_restart_morning() # a new or restarted match starts at dawn
	_last_round = round_number
	day_target = DAY_BY_ROUND[clampi(round_number, 0, DAY_BY_ROUND.size() - 1)]


func _restart_morning() -> void:
	day = 0.0
	day_target = 0.0
	shutter_open = 0.0
	_visible_target = 0
	for state: Array in _neighbour_state:
		state[1] = 0.0
		state[2] = false


## Sets everything the time of day touches: sun, sky, haze, lamps and windows.
func _apply_day() -> void:
	_applied_day = day
	var e := smoothstep(0.0, 1.0, day)
	var elevation := deg_to_rad(lerpf(SUN_ELEVATION.x, SUN_ELEVATION.y, e))
	if _sun:
		var to_sun := Vector3(SUN_HEADING.x * cos(elevation), sin(elevation), SUN_HEADING.y * cos(elevation)).normalized()
		_sun.global_basis = Basis.looking_at(-to_sun)
		_sun.light_energy = smoothstep(deg_to_rad(-1.0), deg_to_rad(6.0), elevation) * lerpf(1.2, 2.3, e)
		_sun.light_color = SUN_COLOR[0].lerp(SUN_COLOR[1], smoothstep(0.0, deg_to_rad(28.0), elevation))
	var env := _world.environment if _world else null
	if env:
		var sky := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
		if sky:
			sky.sky_top_color = SKY_TOP[0].lerp(SKY_TOP[1], e)
			sky.sky_horizon_color = SKY_HORIZON[0].lerp(SKY_HORIZON[1], e)
			sky.ground_horizon_color = GROUND_HORIZON[0].lerp(GROUND_HORIZON[1], e)
			sky.sky_energy_multiplier = lerpf(0.75, 1.0, e)
		env.ambient_light_energy = lerpf(0.8, 0.85, e)
		env.fog_light_color = HAZE[0].lerp(HAZE[1], e)
		env.fog_density = lerpf(0.0045, 0.0028, e)
		env.tonemap_exposure = lerpf(1.25, 0.95, e)
	var lights_out := smoothstep(0.0, 0.45, day)
	if _lamp:
		_lamp.light_energy = _lamp_energy * (1.0 - lights_out)
	if lamp_material:
		lamp_material.emission_energy_multiplier = lerpf(_lamp_emission, 0.2, lights_out)
	if window_material:
		window_material.emission_energy_multiplier = lerpf(_window_emission, 0.15, smoothstep(0.0, 0.8, day))
	if skyline_material:
		skyline_material.set_shader_parameter("day", day)
	if _fill:
		_fill.light_energy = _fill_energy * lerpf(1.0, 0.55, e)
	if _neon:
		_neon.modulate = Color(_neon_color * lerpf(1.0, 0.3, e), 1.0)


# --- The neighbourhood ----------------------------------------------------------------

## The store's shutter rolls up once the morning comes (round 2), lighting the shop.
func _update_shutter(delta: float) -> void:
	if day_target >= 0.3:
		if shutter_open == 0.0:
			_play(load(SHUTTER_SOUND), -6.0)
		shutter_open = move_toward(shutter_open, 1.0, delta / 2.6)
	if _shutter:
		_shutter.scale.y = lerpf(1.0, 0.1, shutter_open)
	if shop_material:
		shop_material.emission_energy_multiplier = 1.3 * shutter_open
	if _shop_light:
		_shop_light.light_energy = 1.2 * shutter_open


func _build_neighbours() -> void:
	var count := neighbour_spots.size()
	if count == 0:
		return
	var material := ShaderMaterial.new()
	material.shader = load(FIGURE_SHADER)
	_people = _multimesh(_figure_mesh(), count, material, "Neighbours")
	_arms = _multimesh(_arms_mesh(), count, material, "NeighbourArms")
	var shirts := [Color(0.9, 0.9, 0.88), Color(0.2, 0.35, 0.65), Color(0.8, 0.25, 0.2), Color(0.95, 0.85, 0.5),
		Color(0.3, 0.55, 0.4), Color(0.55, 0.45, 0.7), Color(0.85, 0.6, 0.65)]
	# Who comes out first: people at ground level, then the balconies, the kid last.
	var order := range(count)
	var rank := func(i: int) -> int: return (5 if neighbour_kinds[i] == 2 else neighbour_kinds[i]) * 100 + i
	order.sort_custom(func(a: int, b: int) -> bool: return rank.call(a) < rank.call(b))
	for i in count:
		var shirt: Color = shirts[i % shirts.size()]
		_people.multimesh.set_instance_custom_data(i, shirt)
		_arms.multimesh.set_instance_custom_data(i, shirt)
		_neighbour_state.append([order.find(i), 0.0, false, _rng.randf() * TAU, 0.0])
		_place_neighbour(i)


## How many neighbours are out: by round, plus a few more when the crowd gets going.
func visible_neighbours() -> int:
	var count := 0
	for state: Array in _neighbour_state:
		if state[2]:
			count += 1
	return count


func _update_neighbours(delta: float) -> void:
	if _people == null:
		return
	var excitement: float = _sound.excitement if _sound and "excitement" in _sound else 0.0
	var round_number: int = manager.round_number if manager else 1
	var wanted: int = NEIGHBOURS_BY_ROUND[clampi(round_number, 0, NEIGHBOURS_BY_ROUND.size() - 1)] + roundi(excitement * EXCITED_EXTRA)
	if manager == null:
		wanted = roundi(lerpf(2.0, 6.0, idle_day))
	_visible_target = maxi(_visible_target, mini(wanted, _neighbour_state.size())) # once out, they stay
	var cheering := excitement >= CHEER_EXCITEMENT
	for i in _neighbour_state.size():
		var state: Array = _neighbour_state[i]
		if state[0] < _visible_target and not state[2]:
			state[2] = true
		if state[2]:
			state[1] = minf(state[1] + delta / APPEAR_SECONDS, 1.0)
		var raise_target := 2.4 + 0.3 * sin(_time * 7.0 + state[3]) if cheering and state[1] >= 1.0 else 0.12
		state[4] = move_toward(state[4], raise_target, delta * 6.0)
		_place_neighbour(i, 0.06 * absf(sin(_time * 6.5 + state[3])) if cheering else 0.0)


func _place_neighbour(i: int, bounce := 0.0) -> void:
	var state: Array = _neighbour_state[i]
	var shown := smoothstep(0.0, 1.0, state[1])
	var scale := 0.8 if neighbour_kinds[i] == 2 else 1.0
	if state[1] <= 0.0:
		scale = 0.0 # indoors
	var basis := Basis(Vector3.UP, neighbour_yaws[i]).scaled(Vector3.ONE * maxf(scale, 0.0001))
	var at := neighbour_spots[i] + neighbour_hidden[i] * (1.0 - shown) + Vector3.UP * bounce
	_people.multimesh.set_instance_transform(i, Transform3D(basis, at))
	var shoulder := Transform3D(basis, at) * Transform3D(Basis(Vector3.RIGHT, -state[4]), Vector3(0, 1.38, 0))
	_arms.multimesh.set_instance_transform(i, shoulder)


# --- Pigeons ---------------------------------------------------------------------------

func _build_pigeons() -> void:
	if perches.is_empty():
		return
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.8
	_pigeons = _multimesh(_pigeon_mesh(), perches.size(), material, "Pigeons")
	for side in [-1.0, 1.0]:
		_wings.append(_multimesh(_wing_mesh(side), perches.size(), material, "PigeonWings%d" % int(side + 1.0)))
	for i in perches.size():
		_pigeon_state.append([Pigeon.PERCHED, _rng.randf() * 3.0, perches[i], Vector3.ZERO, Vector3.ZERO, _rng.randf() * TAU])
		_place_pigeon(i, 0.0)


## Each perched pigeon takes off with probability `chance` (a burst of wings).
func scatter_pigeons(chance: float) -> int:
	var flushed := 0
	for i in _pigeon_state.size():
		var state: Array = _pigeon_state[i]
		if state[0] == Pigeon.PERCHED and _rng.randf() < chance:
			var away := Vector3(state[2].x * 0.15 + _rng.randf_range(-1.0, 1.0), 0.0, -1.0).normalized()
			state[0] = Pigeon.FLEEING
			state[1] = -_rng.randf_range(0.0, 0.25) # a ragged take-off
			state[3] = away * _rng.randf_range(3.0, 5.0) + Vector3.UP * _rng.randf_range(2.5, 4.0)
			state[5] = atan2(away.x, away.z)
			flushed += 1
	if flushed > 0:
		_play(load(PIGEON_SOUNDS[_rng.randi() % PIGEON_SOUNDS.size()]), -8.0 + minf(flushed, 6) * 0.6)
	return flushed


func perched_pigeons() -> int:
	return _pigeon_state.filter(func(s: Array) -> bool: return s[0] == Pigeon.PERCHED).size()


func _update_pigeons(delta: float) -> void:
	for i in _pigeon_state.size():
		var state: Array = _pigeon_state[i]
		state[1] += delta
		match state[0]:
			Pigeon.PERCHED:
				if state[1] > 2.5: # a look around now and then
					state[1] = -_rng.randf_range(0.0, 3.0)
					state[5] += _rng.randf_range(-1.2, 1.2)
			Pigeon.FLEEING:
				if state[1] > 0.0:
					state[3] += Vector3.UP * 3.0 * delta
					state[2] += state[3] * delta
				if state[1] > 3.0:
					state[0] = Pigeon.AWAY
					state[1] = -_rng.randf_range(PIGEON_RETURN.x, PIGEON_RETURN.y)
					state[4] = state[2]
			Pigeon.AWAY:
				if state[1] >= 0.0:
					state[0] = Pigeon.RETURNING
					state[1] = 0.0
			Pigeon.RETURNING:
				var t := minf(state[1] / 2.4, 1.0)
				var home: Vector3 = perches[i]
				var from: Vector3 = state[4]
				var arc := from.lerp(home, smoothstep(0.0, 1.0, t)) + Vector3.UP * sin(t * PI) * 1.2
				var heading := home - from
				state[5] = atan2(heading.x, heading.z)
				state[2] = arc
				if t >= 1.0:
					state[0] = Pigeon.PERCHED
					state[1] = 0.0
					state[2] = home
		_place_pigeon(i, delta)


func _place_pigeon(i: int, _delta: float) -> void:
	var state: Array = _pigeon_state[i]
	var flying: bool = state[0] in [Pigeon.FLEEING, Pigeon.RETURNING] and state[1] >= 0.0
	var hidden: bool = state[0] == Pigeon.AWAY
	var basis := Basis(Vector3.UP, state[5]).scaled(Vector3.ONE * (0.0001 if hidden else 1.0))
	if state[0] == Pigeon.PERCHED and state[1] < -0.2 and state[1] > -0.5: # head-bob peck
		basis = basis * Basis(Vector3.RIGHT, 0.25)
	var xform := Transform3D(basis, state[2])
	_pigeons.multimesh.set_instance_transform(i, xform)
	var flap := sin(_time * 22.0 + i) * 1.0 if flying else 0.0
	for w in 2:
		var side := -1.0 if w == 0 else 1.0
		var wing_basis := Basis(Vector3.FORWARD, side * flap).scaled(Vector3.ONE * (1.0 if flying else 0.0001))
		_wings[w].multimesh.set_instance_transform(i, xform * Transform3D(wing_basis, Vector3(0, 0.1, 0)))


# --- Cat, jet, swinging things, steam ----------------------------------------------------

func _update_cat(delta: float) -> void:
	if _cat == null:
		return
	match _cat_state:
		Cat.RUNNING:
			_move_cat(cat_escape, 4.5, delta, true)
			if _cat.position.distance_to(cat_escape) < 0.05:
				_cat_state = Cat.AWAY
				_cat_timer = _rng.randf_range(CAT_RETURN.x, CAT_RETURN.y)
				_cat.visible = false
		Cat.AWAY:
			_cat_timer -= delta
			if _cat_timer <= 0.0:
				_cat_state = Cat.RETURNING
				_cat.visible = true
		Cat.RETURNING:
			_move_cat(_cat_home, 0.8, delta, false)
			if _cat.position.distance_to(_cat_home) < 0.02:
				_cat_state = Cat.SITTING
				_cat.rotation = Vector3(0, PI, 0)


func _move_cat(target: Vector3, speed: float, delta: float, bounding: bool) -> void:
	var flat := Vector3(target.x, _cat_home.y, target.z)
	var at := Vector3(_cat.position.x, _cat_home.y, _cat.position.z).move_toward(flat, speed * delta)
	var heading := flat - at
	if heading.length() > 0.001:
		_cat.rotation.y = atan2(-heading.z, heading.x)
	_cat.position = at + Vector3.UP * (absf(sin(_time * 14.0)) * 0.07 if bounding else 0.0)


## Starts a jet's pass now (normally on a timer).
func start_flyover() -> void:
	if _jet == null:
		return
	_jet_time = 0.0
	_jet_peaked = false
	_jet.visible = true
	_jet_player.play()


func _update_jet(delta: float) -> void:
	if _jet == null:
		return
	if _jet_time < 0.0:
		if _time >= _next_jet:
			start_flyover()
		return
	_jet_time += delta
	var x := (_jet_time - JET_PEAK) * JET_SPEED
	var descent := clampf(_jet_time / JET_SECONDS, 0.0, 1.0)
	_jet.position = Vector3(x, lerpf(52.0, 34.0, descent), JET_PATH_Z)
	_jet.rotation = Vector3(0.0, 0.0, -0.05)
	# The roar shakes things as it passes over.
	var near := 1.0 - clampf(absf(_jet_time - JET_PEAK) / 4.0, 0.0, 1.0)
	gust = maxf(gust, near * 0.7)
	if not _jet_peaked and _jet_time >= JET_PEAK:
		_jet_peaked = true
		react(0.5)
		if manager and manager.get("camera"):
			manager.camera.shake(0.15)
	if _jet_time >= JET_SECONDS:
		_jet_time = -1.0
		_jet.visible = false
		_next_jet = _time + _rng.randf_range(JET_INTERVAL.x, JET_INTERVAL.y)


func jet_flying() -> bool:
	return _jet_time >= 0.0


func _update_swing(delta: float) -> void:
	gust = move_toward(gust, 0.0, delta * 0.45)
	if laundry_material:
		laundry_material.set_shader_parameter("gust", gust)
	for i in _lantern_nodes.size():
		var swing: Array = _lantern_swing[i]
		var breeze := sin(_time * 0.9 + i * 1.7) * 0.02
		swing[1] += (-9.0 * (swing[0] - breeze) - 1.2 * swing[1]) * delta
		swing[0] += swing[1] * delta
		_lantern_nodes[i].rotation = Vector3(swing[0], 0.0, swing[0] * 0.35)


## The kitchens puff out more steam every few seconds (and after a K.O.).
func _update_steam() -> void:
	if _time >= _next_puff:
		_puff_until = _time + _rng.randf_range(0.8, 1.6)
		_next_puff = _time + _rng.randf_range(5.0, 10.0)
	var puffing := _time < _puff_until
	for i in _steam_nodes.size():
		var base: float = _steam_base[i]
		_steam_nodes[i].amount_ratio = minf(base * 2.0, 1.0) if puffing else base


# --- Meshes and helpers ----------------------------------------------------------------

func _multimesh(mesh: Mesh, count: int, material: Material, node_name: String) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF # moved every frame, cosmetically
	instance.multimesh = multimesh
	instance.material_override = material
	add_child(instance)
	return instance


func _audio_player(volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = &"Ambience"
	player.volume_db = volume
	add_child(player)
	return player


func _play(stream: AudioStream, volume: float) -> void:
	if _player == null or stream == null:
		return
	_player.stream = stream
	_player.volume_db = volume
	_player.pitch_scale = _rng.randf_range(0.95, 1.05)
	_player.play()


## A neighbour (faces +Z, feet at the origin): trousers, a shirt (vertex alpha 1: tinted
## per person), neck, head and hair. Arms are a separate mesh so they can be raised.
func _figure_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := Color(0.78, 0.6, 0.46, 0.0)
	var trousers := Color(0.18, 0.18, 0.22, 0.0)
	var hair := Color(0.06, 0.05, 0.05, 0.0)
	for part in [[Vector3(0, 0.42, 0), Vector3(0.34, 0.84, 0.2), trousers], [Vector3(0, 1.1, 0), Vector3(0.4, 0.58, 0.24), Color(1, 1, 1, 1)],
			[Vector3(0, 1.43, 0), Vector3(0.1, 0.08, 0.1), skin], [Vector3(0, 1.56, 0.01), Vector3(0.19, 0.22, 0.21), skin],
			[Vector3(0, 1.66, -0.01), Vector3(0.2, 0.07, 0.22), hair]]:
		_colored_box(st, part[0], part[1], part[2])
	return st.commit()


## Both arms hanging from the shoulder line (origin): sleeves tinted, hands skin.
func _arms_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-0.25, 0.25]:
		_colored_box(st, Vector3(x, -0.17, 0), Vector3(0.1, 0.34, 0.11), Color(1, 1, 1, 1))
		_colored_box(st, Vector3(x, -0.47, 0), Vector3(0.08, 0.3, 0.09), Color(0.78, 0.6, 0.46, 0.0))
	return st.commit()


## A pigeon (faces +Z): grey body, darker head with a green-purple neck, tail.
func _pigeon_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_colored_box(st, Vector3(0, 0.1, 0), Vector3(0.12, 0.11, 0.22), Color(0.55, 0.57, 0.62))
	_colored_box(st, Vector3(0, 0.17, 0.1), Vector3(0.08, 0.08, 0.08), Color(0.32, 0.4, 0.38))
	_colored_box(st, Vector3(0, 0.2, 0.14), Vector3(0.06, 0.06, 0.07), Color(0.4, 0.42, 0.48))
	_colored_box(st, Vector3(0, 0.08, -0.15), Vector3(0.09, 0.03, 0.1), Color(0.3, 0.3, 0.34))
	_colored_box(st, Vector3(0, 0.02, 0.02), Vector3(0.04, 0.04, 0.03), Color(0.75, 0.3, 0.3))
	return st.commit()


func _wing_mesh(side: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_colored_box(st, Vector3(side * 0.15, 0.0, 0.0), Vector3(0.26, 0.015, 0.13), Color(0.5, 0.52, 0.58))
	return st.commit()


func _colored_box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index: int in arrays[Mesh.ARRAY_INDEX]:
		st.set_color(color)
		st.set_normal(normals[index])
		st.add_vertex(verts[index] + center)
