class_name NeonAmbience
extends Node
## Cosmetic light animation for a stage: neon signs that hum and now and then flicker,
## and aircraft warning lights that blink. Runs on real time with its own random numbers,
## so it never touches the simulation (rollback, replays and spectating are unaffected).
## The first flicker waits a few seconds, so stills rendered right after loading are clean.

## Neon that flickers in short bursts: Label3D nodes plus the lights they cast.
@export var flicker_labels: Array[NodePath] = []
@export var flicker_lights: Array[NodePath] = []
## Neon that only hums (a faint, slow brightness wave).
@export var hum_labels: Array[NodePath] = []
## Blinking warning lights and the emissive material of their bulbs.
@export var blink_lights: Array[NodePath] = []
@export var blink_material: StandardMaterial3D
@export var blink_period := 1.4
@export var blink_on := 0.35

var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _next_burst := 0.0
var _burst_end := -1.0
var _labels := {} # Label3D -> base modulate
var _lights := {} # Light3D -> base energy
var _hums := {}
var _blinks := {}
var _blink_energy := 0.0


func _ready() -> void:
	_rng.seed = hash(get_path())
	_next_burst = _rng.randf_range(5.0, 9.0)
	for path in flicker_labels:
		var label := get_node_or_null(path) as Label3D
		if label:
			_labels[label] = label.modulate
	for path in flicker_lights:
		var light := get_node_or_null(path) as Light3D
		if light:
			_lights[light] = light.light_energy
	for path in hum_labels:
		var label := get_node_or_null(path) as Label3D
		if label:
			_hums[label] = label.modulate
	for path in blink_lights:
		var light := get_node_or_null(path) as Light3D
		if light:
			_blinks[light] = light.light_energy
	if blink_material:
		_blink_energy = blink_material.emission_energy_multiplier


func _process(delta: float) -> void:
	_time += delta
	# Flicker: a burst of quick on/off cuts every 5-10 s.
	var level := 1.0
	if _time >= _next_burst:
		_burst_end = _time + _rng.randf_range(0.25, 0.6)
		_next_burst = _time + _rng.randf_range(5.0, 10.0)
	if _time < _burst_end:
		level = 0.15 if _rng.randf() < 0.45 else 1.0
	for label: Label3D in _labels:
		label.modulate = Color(_labels[label] * level, 1.0)
	for light: Light3D in _lights:
		light.light_energy = _lights[light] * (0.25 + 0.75 * level)
	var hum := 0.93 + 0.07 * sin(_time * 2.1)
	for label: Label3D in _hums:
		label.modulate = Color(_hums[label] * hum, 1.0)
	# Blink: on for blink_on seconds every blink_period.
	var lit := fmod(_time, blink_period) < blink_on
	for light: Light3D in _blinks:
		light.light_energy = _blinks[light] if lit else 0.0
	if blink_material:
		blink_material.emission_energy_multiplier = _blink_energy if lit else _blink_energy * 0.08
