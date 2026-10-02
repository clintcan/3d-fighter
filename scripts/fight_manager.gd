extends Node3D
## Fight scene root. Loads the selected stage and spawns both fighters.
## Milestone 1: fighters are colored capsule stand-ins. Real fighters, rounds,
## HUD and the action camera arrive in later milestones (see CLAUDE.md §9).

const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"

@onready var camera: Camera3D = $Camera3D
@onready var matchup_label: Label = %MatchupLabel

var stage: Stage


func _ready() -> void:
	GameState.ensure_selections()
	stage = (load(GameState.stage_path) as PackedScene).instantiate() as Stage
	add_child(stage)

	_spawn_placeholder(GameState.player_character, stage.p1_spawn)
	_spawn_placeholder(GameState.cpu_character, stage.p2_spawn)
	camera.look_at(Vector3(0, 1.0, 0))
	matchup_label.text = "%s  vs  %s (CPU)" % [GameState.player_character.display_name, GameState.cpu_character.display_name]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _spawn_placeholder(character: CharacterData, spawn: Marker3D) -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var material := StandardMaterial3D.new()
	material.albedo_color = character.placeholder_color
	capsule.material = material

	var body := MeshInstance3D.new()
	body.name = "%sPlaceholder" % character.display_name
	body.mesh = capsule
	body.position = spawn.global_position + Vector3.UP * capsule.height * 0.5
	add_child(body)
