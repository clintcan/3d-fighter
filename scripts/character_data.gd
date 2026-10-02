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
## Rigged glTF body (Quaternius UAL skeleton). Null = graybox capsule.
@export var model_scene: PackedScene
## Extra skinned pieces (hair, beard) rigged to the same skeleton.
@export var hair_scenes: Array[PackedScene] = []
## Optional skin texture variant replacing the body's base color.
@export var body_albedo: Texture2D
@export var model_scale: float = 1.0
## Tint for hair/eyebrow materials (the free Quaternius hair textures are greyscale).
@export var hair_color: Color = Color.WHITE
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
@export var throw_damage: int = 120
## 0..1 ratings shown as bars on the character select screen.
@export_range(0.0, 1.0) var power_rating := 0.5
@export_range(0.0, 1.0) var speed_rating := 0.5

@export_group("Moves")
@export var moves: Array[MoveData] = []
