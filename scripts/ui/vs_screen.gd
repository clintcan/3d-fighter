extends Control
## "P1 VS P2" splash between character select and the fight. Portraits slide in from
## the sides, "VS" punches in, then the fight loads. Confirm skips it.

const FIGHT_SCENE := "res://scenes/fight.tscn"
const HOLD_SECONDS := 2.2

@onready var left_portrait: TextureRect = %LeftPortrait
@onready var right_portrait: TextureRect = %RightPortrait
@onready var left_name: Label = %LeftName
@onready var right_name: Label = %RightName
@onready var vs_label: Label = %VsLabel
@onready var left_side: Control = %LeftSide
@onready var right_side: Control = %RightSide

var _leaving := false


func _ready() -> void:
	GameState.ensure_selections()
	left_portrait.texture = GameState.player_character.portrait
	right_portrait.texture = GameState.p2_character.portrait
	var versus := GameState.mode == GameState.Mode.VERSUS
	left_name.text = ("P1  " if versus else "") + GameState.player_character.display_name.to_upper()
	right_name.text = "%s (%s)" % [GameState.p2_character.display_name.to_upper(), "P2" if versus else "CPU"]
	# Wait a frame so containers have laid out, then animate from off-screen.
	await get_tree().process_frame
	var width := get_viewport_rect().size.x
	var left_home := left_side.position
	var right_home := right_side.position
	left_side.position.x -= width * 0.6
	right_side.position.x += width * 0.6
	vs_label.pivot_offset = vs_label.size / 2.0
	vs_label.scale = Vector2(3, 3)
	vs_label.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(left_side, "position", left_home, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(right_side, "position", right_home, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(vs_label, "scale", Vector2.ONE, 0.3).set_delay(0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(vs_label, "modulate:a", 1.0, 0.15).set_delay(0.35)
	get_tree().create_timer(HOLD_SECONDS).timeout.connect(_go)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_go()


func _go() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(FIGHT_SCENE)
