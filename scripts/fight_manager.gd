extends Node3D
## Fight scene root. Owns the fixed-order 60 Hz simulation:
##   view → input → fighter tick → pushbox → hits
## Milestone 2: P1 vs. a training dummy, endless rounds (KO → reset). Rounds, timer
## and the real AI come in later milestones (see CLAUDE.md §9).

signal hit_landed(attacker: Fighter, defender: Fighter, move: MoveData, result: Fighter.HitResult)
signal throw_landed(attacker: Fighter, defender: Fighter)

const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const FIGHTER_SCENE := preload("res://scenes/fighter/fighter.tscn")
const KO_RESET_TICKS := 180
## Share of a hit's knockback transferred to the attacker when the defender is pinned.
const CORNER_PUSHBACK := 0.8
## Per-tick slerp factor for the logical view direction following the fight axis.
const VIEW_FOLLOW := 0.08

var stage: Stage
var fighters: Array[Fighter] = []
## Unit vector (flattened) from the fighters' midpoint toward the camera. Part of the
## simulation state because it decides which way "left/right" map for each player.
var view_dir := Vector3.BACK
var dummy: DummyController
var ko_timer := -1
var debug_draw := false

@onready var camera: ActionCamera = $ActionCamera
@onready var hud: FightHud = $HUD


func _ready() -> void:
	GameState.ensure_selections()
	stage = (load(GameState.stage_path) as PackedScene).instantiate() as Stage
	add_child(stage)

	dummy = DummyController.new()
	var p1 := _spawn_fighter(GameState.player_character, PlayerController.new("p1_"))
	var p2 := _spawn_fighter(GameState.cpu_character, dummy)
	p1.opponent = p2
	p2.opponent = p1
	for fighter in fighters:
		fighter.knocked_out.connect(_on_knocked_out)
		fighter.throw_teched.connect(_on_throw_teched)

	hud.setup(p1, p2)
	_reset_round()
	camera.setup(self)
	_update_debug_text()


func _spawn_fighter(character: CharacterData, controller: FighterController) -> Fighter:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	fighter.setup(character, controller)
	fighter.bounds_half_extent = stage.bounds_half_extent
	add_child(fighter)
	fighters.append(fighter)
	return fighter


func _reset_round() -> void:
	ko_timer = -1
	fighters[0].reset_to(stage.p1_spawn.global_position)
	fighters[1].reset_to(stage.p2_spawn.global_position)
	view_dir = Vector3.BACK
	_update_view()
	# Facing depends on the opponent's position, so face once both are placed.
	for fighter in fighters:
		fighter.face_opponent()
	hud.announce("")
	if camera.manager:
		camera.snap()


# --- Simulation ------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	_update_view()
	for fighter in fighters:
		fighter.read_input()
	for fighter in fighters:
		fighter.tick()
	_resolve_pushboxes()
	_resolve_throws()
	_resolve_hits()
	if ko_timer > 0:
		ko_timer -= 1
		if ko_timer == 0:
			_reset_round()


## Keeps the camera side-on to the fight axis, turning toward whichever perpendicular is
## closer so the view never flips.
func _update_view() -> void:
	var axis := fighters[1].position - fighters[0].position
	axis.y = 0.0
	if axis.length_squared() > 0.0001:
		var desired := Vector3.UP.cross(axis).normalized()
		if desired.dot(view_dir) < 0.0:
			desired = -desired
		view_dir = view_dir.slerp(desired, VIEW_FOLLOW).normalized()
	var view_right := (-view_dir).cross(Vector3.UP)
	for fighter in fighters:
		fighter.view_right = view_right
		fighter.view_depth = -view_dir


func _resolve_pushboxes() -> void:
	var a := fighters[0]
	var b := fighters[1]
	var min_distance := Fighter.PUSHBOX_RADIUS * 2.0
	var delta := _flat(b.position - a.position)
	var distance := delta.length()
	if distance >= min_distance:
		return
	var push_dir := delta / distance if distance > 0.0001 else a.forward
	var overlap := min_distance - distance
	a.position -= push_dir * overlap * 0.5
	b.position += push_dir * overlap * 0.5
	a.clamp_to_bounds()
	b.clamp_to_bounds()
	# If one fighter is pinned at the edge, the other takes the remaining push.
	var remaining := min_distance - _flat(b.position - a.position).length()
	if remaining > 0.001:
		b.position += push_dir * remaining
		b.clamp_to_bounds()
		remaining = min_distance - _flat(b.position - a.position).length()
		if remaining > 0.001:
			a.position -= push_dir * remaining
			a.clamp_to_bounds()


## Grabs connect on the throw's startup tick if the opponent is close and throwable.
## Simultaneous throws break each other.
func _resolve_throws() -> void:
	var a := fighters[0]
	var b := fighters[1]
	if a.is_throw_grab_frame() and b.is_throw_grab_frame():
		a.tech_apart()
		b.tech_apart()
		hud.note(0, "TECH")
		hud.note(1, "TECH")
		return
	for attacker in fighters:
		if not attacker.is_throw_grab_frame():
			continue
		var defender := attacker.opponent
		if defender.is_throwable() and _flat(defender.position - attacker.position).length() <= Fighter.THROW_RANGE:
			attacker.on_throw_grabbed()
			defender.on_grabbed_by(attacker)
			throw_landed.emit(attacker, defender)


## Collects all connecting hitboxes first, then applies them, so simultaneous hits trade.
func _resolve_hits() -> void:
	var connecting: Array[Fighter] = []
	for attacker in fighters:
		var hitbox := attacker.get_active_hitbox()
		if not hitbox.is_empty() and attacker.opponent.overlaps_hurtbox(hitbox.center, hitbox.radius):
			connecting.append(attacker)
	for attacker in connecting:
		var move := attacker.current_move
		var defender := attacker.opponent
		var result := defender.receive_hit(attacker, move)
		attacker.on_hit_confirmed()
		if defender.is_pinned_against_bounds(attacker.forward) and attacker.position.y <= 0.0:
			attacker.velocity -= attacker.forward * move.knockback.x * CORNER_PUSHBACK
		if result == Fighter.HitResult.COUNTER:
			hud.note(fighters.find(attacker), "COUNTER")
		hit_landed.emit(attacker, defender, move, result)


func _on_knocked_out(_loser: Fighter) -> void:
	hud.announce("K.O.")
	ko_timer = KO_RESET_TICKS
	for fighter in fighters:
		fighter.input_locked = true


func _on_throw_teched(defender: Fighter) -> void:
	hud.note(fighters.find(defender), "TECH")


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Debug / scene input ------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F1:
				dummy.cycle_mode()
			KEY_F3:
				camera.cycle_mode()
			KEY_F2:
				debug_draw = not debug_draw
				for fighter in fighters:
					fighter.debug_draw = debug_draw
			KEY_F5:
				_reset_round()
			_:
				return
		_update_debug_text()


func _update_debug_text() -> void:
	hud.set_debug_text("F1 Dummy: %s  ·  F2 Hurtboxes: %s  ·  F3 Action Cam: %s  ·  F5 Reset  ·  Esc Back" % [
		dummy.mode_name(), "On" if debug_draw else "Off", camera.mode_name()])
