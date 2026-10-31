class_name MenuShowcase
extends SubViewportContainer
## Behind the main menu: one fighter at a time in a close-up, running their character
## select routine (FighterShowcase), then a fade to the next. Fighters come from a shuffled
## bag (everyone once before anyone repeats, never the same one twice in a row), alternate
## between the left and right of the buttons and face the middle; a rim light in the
## fighter's colour, a slow push-in. Only the fighter on screen is built (the swap happens
## while the screen is black). Purely cosmetic, with its own RNG.

const SHOT_MAX := 15.0 # seconds: a long routine is cut here
const SHOT_MIN := 7.0 # a short routine plays on until here
const FADE := 0.4
const POSE_HOLD := 0.15 # seconds held black after a swap: the new model's first frames are its rest pose
const DISTANCE := Vector2(3.5, 2.9) # camera distance at the start / end of a shot
const HEAD_ABOVE_AIM := 0.4 # the camera aims this far below the fighter's head (rest pose), so every head sits on the same line
const ZOOM := {&"aelia": 0.9} # camera distance factor: she is slimmer than the base bodies (shoulders 0.27 m vs 0.30) and looked further away
const SIDE_OFFSET := 1.0 # Camera3D.h_offset: puts the fighter beside the buttons
const ORBIT := 0.12 # radians the camera drifts round over a shot

var viewport: SubViewport
var camera: Camera3D
var rim: DirectionalLight3D
var showcase: FighterShowcase
var model: FighterModel
var shown: Array[CharacterData] = [] # every fighter shown so far, in order

var _turntable: Node3D
var _effects: Node3D
var _shade: ColorRect
var _bag: Array[CharacterData] = []
var _rng := RandomNumberGenerator.new()
var _side := 1.0
var _aim_height := 1.2
var _zoom := 1.0
var _time := 0.0
var _swapping := false


func _ready() -> void:
	_rng.randomize()
	# Everything in here moves in _process (camera push-in, turntable), so it opts out of
	# physics interpolation; the children inherit the mode.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_side = 1.0 if _rng.randf() < 0.5 else -1.0
	set_anchors_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	add_child(viewport)
	var settings = get_node("/root/Settings") # looked up at run time: class_name scripts compile before autoloads in tests
	settings.apply_graphics(viewport)
	viewport.size_changed.connect(func() -> void: settings.apply_graphics(viewport))
	_build_stage(settings.graphics == settings.Graphics.LOW)
	_shade = ColorRect.new() # the fade between fighters
	_shade.color = Color(0.03, 0.03, 0.05)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_show_next()
	var tween := create_tween()
	tween.tween_interval(POSE_HOLD)
	tween.tween_property(_shade, "modulate:a", 0.0, FADE)


func _process(delta: float) -> void:
	if showcase == null:
		return
	showcase.process(delta)
	_time += delta
	_place_camera()
	if not _swapping and (_time >= SHOT_MAX or (showcase.loops > 0 and _time >= SHOT_MIN)):
		_swapping = true
		var tween := create_tween()
		tween.tween_property(_shade, "modulate:a", 1.0, FADE)
		tween.tween_callback(_show_next)
		tween.tween_interval(POSE_HOLD)
		tween.tween_property(_shade, "modulate:a", 0.0, FADE)
		tween.tween_callback(func() -> void: _swapping = false)


func _show_next() -> void:
	var character := _next_fighter()
	if character == null:
		return
	if model:
		model.queue_free()
	for fx in _effects.get_children():
		fx.queue_free()
	model = FighterModel.new()
	_turntable.add_child(model)
	model.build(character)
	_side = -_side
	_turntable.rotation.y = FighterShowcase.REST_ANGLE * _side
	showcase = FighterShowcase.new(model, character, _turntable, _effects)
	showcase.side = _side
	rim.light_color = character.placeholder_color.lerp(Color.WHITE, 0.25)
	shown.append(character)
	_zoom = ZOOM.get(character.id, 1.0)
	_aim_height = head_height(model) - HEAD_ABOVE_AIM * _zoom # a closer camera aims closer to the head: same line on screen
	_time = 0.0
	_place_camera()


## The next fighter from the bag: refilled with a shuffled roster, never starting with
## the one just shown.
func _next_fighter() -> CharacterData:
	if _bag.is_empty():
		_bag.assign(get_node("/root/GameState").roster)
		for i in range(_bag.size() - 1, 0, -1): # Fisher-Yates with our own RNG
			var j := _rng.randi_range(0, i)
			var swap := _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = swap
		if _bag.size() > 1 and not shown.is_empty() and _bag.back() == shown.back():
			_bag.push_front(_bag.pop_back())
	return _bag.pop_back() if not _bag.is_empty() else null


## Close-up from the front, the fighter beside the buttons (h_offset), pushing in and
## drifting round a little over the shot.
func _place_camera() -> void:
	var t := clampf(_time / SHOT_MAX, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var distance := lerpf(DISTANCE.x, DISTANCE.y, eased) * _zoom
	var angle := (eased - 0.5) * ORBIT * _side
	var aim := Vector3(0, _aim_height, 0)
	camera.position = aim + Vector3(sin(angle), 0.08, -cos(angle)) * distance
	camera.look_at(aim)
	# The fighter on the left (side 1) faces screen right, toward the buttons.
	camera.h_offset = SIDE_OFFSET * _side


## Height of the model's head bone in its rest pose (scaled), above the floor.
static func head_height(fighter: FighterModel) -> float:
	var skeleton := fighter.skeleton
	var head := skeleton.find_bone("Head")
	if head < 0:
		return 1.6
	return (skeleton.global_transform * skeleton.get_bone_global_rest(head)).origin.y - fighter.global_position.y


func _build_stage(low_graphics: bool) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = not low_graphics
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var key := SpotLight3D.new()
	key.light_energy = 16.0
	key.spot_range = 10.0
	key.spot_angle = 32.0
	key.shadow_enabled = true
	viewport.add_child(key)
	key.look_at_from_position(Vector3(1.4, 4.2, -2.6), Vector3(0, 1.0, 0))
	rim = DirectionalLight3D.new()
	rim.light_energy = 2.4
	viewport.add_child(rim)
	rim.look_at_from_position(Vector3(-1.0, 2.0, 2.2), Vector3(0, 1.0, 0))

	_turntable = Node3D.new()
	viewport.add_child(_turntable)
	_effects = Node3D.new()
	viewport.add_child(_effects)
	camera = Camera3D.new()
	camera.fov = 30.0
	viewport.add_child(camera)
	camera.current = true
