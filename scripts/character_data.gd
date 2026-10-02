class_name CharacterData
extends Resource
## Static definition of a playable character. One .tres per character in res://data/characters/.

@export var id: StringName
@export var display_name: String
@export var archetype: String
@export_multiline var description: String
## Position on the character select screen (lowest first).
@export var select_order: int = 0

@export_group("Visuals")
@export var portrait: Texture2D
## Imported .glb model (with skeleton + animations). Null until models are imported.
@export var model_scene: PackedScene
## Tint used for graybox stand-ins and UI until real models/portraits exist.
@export var placeholder_color: Color = Color.WHITE

@export_group("Stats")
@export var max_health: int = 1000
## Meters per second.
@export var walk_speed: float = 2.0
@export var back_walk_speed: float = 1.6
@export var dash_speed: float = 6.0
@export var sidestep_distance: float = 0.8
@export var jump_velocity: float = 6.0
## Scales knockback received. Heavier characters get pushed less.
@export var weight: float = 1.0

@export_group("Moves")
@export var moves: Array[MoveData] = []
