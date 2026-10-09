class_name DemoMode
extends Node
## Demo mode (main menu "Demo", GameState.Mode.DEMO): two CPU fighters fight on a random
## stage with no end. FightManager makes P1 a second AIController, keeps both fighters
## immortal and skips the timer and K.O. (like training); this node refills a fighter
## who's low once the combo on them is over, moves on to a new random matchup every
## SWITCH_SECONDS, shows a caption, and goes back to the main menu on any key, button or
## click.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
## A fighter below this share of their health is refilled...
const REFILL_BELOW := 0.4
## ...once no combo has been landing on them for this many ticks. (Not "actionable" as in
## training: two CPUs on Hard are almost never standing still.)
const REFILL_DELAY_TICKS := 30
## A new random matchup and stage this often (real seconds).
const SWITCH_SECONDS := 90.0

var manager: Node
var _refill_ticks := {}
var _time := 0.0
var _leaving := false
var _caption: Label


func setup(fight_manager: Node) -> void:
	manager = fight_manager
	manager.ticked.connect(_on_ticked)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_caption = Label.new()
	_caption.text = "DEMO  ·  Press any button"
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption.offset_bottom = -90
	layer.add_child(_caption)


func _process(delta: float) -> void:
	_time += delta
	_caption.modulate.a = 0.55 + 0.45 * absf(sin(_time * 1.8))
	if _time >= SWITCH_SECONDS and not _leaving:
		_leaving = true
		_game_state().start_demo(get_tree())


## Any key, button or click ends the demo (before the fight's own pause handling).
func _input(event: InputEvent) -> void:
	var pressed := (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) \
		and event.is_pressed() and not event.is_echo()
	if not pressed or _leaving:
		return
	get_viewport().set_input_as_handled()
	stop()


## Back to the main menu.
func stop() -> void:
	_leaving = true
	var game_state := _game_state()
	game_state.mode = game_state.Mode.VS_CPU
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Looked up at run time: tests compile this class before the autoloads exist.
func _game_state() -> Node:
	return get_tree().root.get_node("GameState")


func _on_ticked() -> void:
	for fighter: Fighter in manager.fighters:
		_refill(fighter)


func _refill(fighter: Fighter) -> void:
	var key := fighter.get_instance_id()
	var low := fighter.health < fighter.data.max_health * REFILL_BELOW
	if low and fighter.combo_hits == 0:
		_refill_ticks[key] = int(_refill_ticks.get(key, 0)) + 1
		if _refill_ticks[key] >= REFILL_DELAY_TICKS:
			fighter.health = fighter.data.max_health
			fighter.health_changed.emit(fighter.health, fighter.data.max_health)
			_refill_ticks[key] = 0
	else:
		_refill_ticks[key] = 0
