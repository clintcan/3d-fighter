class_name Stage
extends Node3D
## Base for all fight stages. A stage provides spawn points, play-area bounds,
## and its own lighting/environment.

## Fighters are clamped to +/- this distance from the center on X and Z.
@export var bounds_half_extent: float = 3.6

@onready var p1_spawn: Marker3D = $P1Spawn
@onready var p2_spawn: Marker3D = $P2Spawn
