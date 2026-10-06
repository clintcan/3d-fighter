class_name FireFlicker
extends Node
## Cosmetic flicker for lights from flames and candles (torches, lanterns): each light's
## energy wavers on a few out-of-step sine waves around its base value. Real time and
## its own phases, so it never touches the simulation.

@export var lights: Array[NodePath] = []
## How far the energy swings (fraction of the base).
@export var amount := 0.18

var _time := 0.0
var _lights := {} # Light3D -> [base energy, phase]


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(get_path())
	for path in lights:
		var light := get_node_or_null(path) as Light3D
		if light:
			_lights[light] = [light.light_energy, rng.randf() * TAU]


func _process(delta: float) -> void:
	_time += delta
	for light: Light3D in _lights:
		var base: float = _lights[light][0]
		var phase: float = _lights[light][1]
		var wave := sin(_time * 7.3 + phase) * 0.5 + sin(_time * 13.1 + phase * 1.7) * 0.3 + sin(_time * 23.0 + phase * 2.3) * 0.2
		light.light_energy = base * (1.0 + amount * wave)
