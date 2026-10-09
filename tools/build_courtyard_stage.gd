extends SceneTree
## Builds the Kowloon Courtyard stage (res://scenes/stages/courtyard.tscn), Lian's home:
## the tiled courtyard of an old Hong Kong tenement at dawn. Tall tenement fronts close
## it in on both sides (window grilles, air-con units, balconies, bamboo laundry poles,
## a tea house kitchen on the left, a corner store behind a roller shutter on the right,
## bamboo scaffolding). The back is low on purpose: a courtyard wall with an open red
## gate, an earth god shrine and Lian's wooden dummy, then a lane and single-storey
## kitchen sheds, so the fight camera (which only sees ~5 m up the back) looks over them
## to a distant Kowloon skyline and a strip of dawn sky. Laundry lines and red lanterns
## cross overhead. Re-run after changing anything below.
##
## Run: godot_console --headless --path . -s res://tools/build_courtyard_stage.gd
##
## Everything that moves is driven at run time by CourtyardLife (the "Life" node; real
## time, cosmetic): the sun rising round by round, the neighbours who come out to watch,
## pigeons, cat, laundry, lanterns, kitchen steam, the store's shutter and a low jet.
## Layout: floor top at y = 0; the fight runs along X at z = 0, the camera is at +Z.
## Nothing stands within the fight bounds (±3.6 m) plus a margin.

const OUTPUT := "res://scenes/stages/courtyard.tscn"
const TEX := "res://assets/stages/courtyard/textures/"
const MARKET_TEX := "res://assets/stages/market/textures/" # plaster, shutter, iron, wood (shared)
const STAGE_SCRIPT := "res://scripts/stages/stage.gd"
const LIFE_SCRIPT := "res://scripts/stages/courtyard_life.gd"
const FLICKER_SCRIPT := "res://scripts/stages/fire_flicker.gd"
const TENEMENTS_SHADER := "res://assets/stages/courtyard/tenements.gdshader"
const LAUNDRY_SHADER := "res://assets/stages/courtyard/laundry.gdshader"
const AO_PATH := "res://assets/stages/courtyard/courtyard_ao.res"

const BACK_Z := -7.0 # inner face of the courtyard's back wall
const SIDE_X := 9.5 # inner faces of the side tenements
const NEAR_Z := 15.0 # the courtyard runs this far toward the camera
const WALL_TOP := 2.4
const GATE_X := 1.4
const GATE_WIDTH := 1.8
const LANE_Z := -9.8 # the sheds' fronts, across the lane
const GROUND_FLOOR := 3.2 # tenement ground floor height; the floors above are FLOOR_HEIGHT
const FLOOR_HEIGHT := 2.9
const WARM := Color(1.0, 0.76, 0.48)
const RED := Color(0.72, 0.08, 0.06)
const GOLD := Color(1.0, 0.8, 0.3)

var stage: Node3D
var _batches := {}
var _footprints := [] # everything standing on the courtyard floor (contact shadows)
var _rng := RandomNumberGenerator.new()
var _skyline := SurfaceTool.new()
var _laundry := SurfaceTool.new()
var mat_tiles: StandardMaterial3D
var mat_concrete: StandardMaterial3D
var mat_shutter: StandardMaterial3D
var mat_iron: StandardMaterial3D
var mat_wood: StandardMaterial3D
var mat_bamboo: StandardMaterial3D
var mat_grille: StandardMaterial3D
var mat_red: StandardMaterial3D
var mat_gold: StandardMaterial3D
var mat_dark: StandardMaterial3D
var mat_metal: StandardMaterial3D
var mat_clay: StandardMaterial3D
var mat_window_lit: StandardMaterial3D
var mat_window_dark: StandardMaterial3D
var mat_shop_lit: StandardMaterial3D
var mat_bulb: StandardMaterial3D
var mat_net: StandardMaterial3D
var mat_leaf: StandardMaterial3D
var mat_styro: StandardMaterial3D
var mat_skyline: ShaderMaterial
var mat_laundry: ShaderMaterial
var _plaster := []
var _plastic := []
## For CourtyardLife: where pigeons perch, and where neighbours come out to watch
## ([position, yaw toward the fight, hidden offset, kind: 0 standing, 1 at a balcony rail,
## 2 sitting]).
var _perches := PackedVector3Array()
var _neighbours := []
var _steam: Array[NodePath] = []
var _lanterns: Array[NodePath] = []


func _initialize() -> void:
	_rng.seed = 1898 # the New Territories lease
	stage = Node3D.new()
	stage.name = "Courtyard"
	stage.set_script(load(STAGE_SCRIPT))
	stage.set("rope_line", 50.0) # nothing sits between the camera and the fight
	stage.set("music", &"courtyard")
	_skyline.begin(Mesh.PRIMITIVE_TRIANGLES)
	_laundry.begin(Mesh.PRIMITIVE_TRIANGLES)

	_make_materials()
	_build_environment()
	_build_lights()
	_build_floor()
	_build_back_wall()
	_build_lane_and_sheds()
	_build_side_tenement(-1.0)
	_build_side_tenement(1.0)
	_build_scaffolding()
	_build_courtyard_props()
	_build_wooden_dummy(Vector3(-5.7, 0, -5.95))
	_build_shrine(Vector3(-2.3, 0, BACK_Z - 0.02))
	_build_overhead()
	_build_skyline()
	_build_cat()
	_build_jet()
	_build_sun_blocker()
	_flush_batches()
	_flush_skyline_and_laundry()
	_bake_contact_shadows()
	_add(stage, StageFX.ambience([["res://assets/audio/ambience/birds.ogg", -15.0], ["res://assets/audio/ambience/city_traffic.ogg", -25.0],
		["res://assets/audio/ambience/market_chatter.ogg", -29.0]], "res://assets/audio/ambience/crowd_cheer.ogg", -15.0), "Sound")
	_build_life()
	_add(stage, _marker(Vector3(-2, 0, 0)), "P1Spawn")
	_add(stage, _marker(Vector3(2, 0, 0)), "P2Spawn")

	var scene := PackedScene.new()
	var err := scene.pack(stage)
	if err == OK:
		err = ResourceSaver.save(scene, OUTPUT)
	print("saved ", OUTPUT, " err=", err)
	stage.free()
	quit()


func _make_materials() -> void:
	mat_tiles = _textured(TEX, "dirty_tiles", Color(1.0, 0.92, 0.88), 0.3)
	mat_concrete = _textured(TEX, "concrete_wall_006", Color(0.78, 0.76, 0.72), 0.35)
	mat_shutter = _textured(MARKET_TEX, "painted_metal_shutter", Color(0.45, 0.7, 0.55), 0.5)
	mat_iron = _textured(MARKET_TEX, "rusty_corrugated_iron", Color(0.85, 0.8, 0.75), 0.5)
	mat_wood = _textured(MARKET_TEX, "wood_planks", Color(0.75, 0.5, 0.32), 1.2)
	mat_bamboo = _material(Color(0.72, 0.6, 0.36), 0.0, 0.7)
	mat_grille = _material(Color(0.16, 0.32, 0.24), 0.4, 0.55)
	mat_red = _material(RED, 0.0, 0.5)
	mat_gold = _material(GOLD, 0.6, 0.4)
	mat_dark = _material(Color(0.05, 0.05, 0.06), 0.0, 0.85)
	mat_metal = _material(Color(0.55, 0.57, 0.6), 0.6, 0.45)
	mat_clay = _material(Color(0.6, 0.25, 0.15), 0.0, 0.8)
	mat_window_lit = _emissive(Color(1.0, 0.8, 0.55), 1.4) # CourtyardLife dims it as the day comes up
	mat_window_dark = _material(Color(0.07, 0.09, 0.12), 0.3, 0.15)
	mat_shop_lit = _emissive(Color(1.0, 0.93, 0.78), 0.0) # behind the shutter; lit when it rolls up
	mat_bulb = _emissive(Color(1.0, 0.82, 0.5), 4.0) # the gate lamp; off by day
	mat_net = _material(Color(0.15, 0.45, 0.3, 0.82), 0.0, 0.9)
	mat_net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_net.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_leaf = _material(Color(0.2, 0.42, 0.18), 0.0, 0.75)
	mat_styro = _material(Color(0.9, 0.9, 0.86), 0.0, 0.9)
	for c in [Color(0.72, 0.86, 0.76), Color(0.96, 0.9, 0.74), Color(0.92, 0.76, 0.74), Color(0.74, 0.84, 0.92), Color(0.88, 0.86, 0.8)]:
		_plaster.append(_textured(MARKET_TEX, "painted_plaster_wall", c, 0.5))
	for c in [Color(0.85, 0.15, 0.12), Color(0.15, 0.35, 0.8), Color(0.95, 0.75, 0.12), Color(0.2, 0.6, 0.35)]:
		_plastic.append(_material(c, 0.0, 0.6))
	mat_skyline = ShaderMaterial.new()
	mat_skyline.shader = load(TENEMENTS_SHADER)
	mat_laundry = ShaderMaterial.new()
	mat_laundry.shader = load(LAUNDRY_SHADER)


# --- Environment & lighting ------------------------------------------------------

## Dawn sky (ProceduralSkyMaterial: CourtyardLife eases its colours toward morning) and a
## soft haze that thickens with distance, so the skyline steps back into the light.
func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.1, 0.13, 0.3)
	sky_material.sky_horizon_color = Color(0.95, 0.56, 0.46)
	sky_material.ground_horizon_color = Color(0.6, 0.4, 0.38)
	sky_material.ground_bottom_color = Color(0.12, 0.1, 0.12)
	sky_material.sun_angle_max = 8.0
	sky_material.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL # the colours change between rounds
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.ssao_enabled = false # too costly on integrated GPUs (see the stage notes)
	env.fog_enabled = true # morning haze over the skyline
	env.fog_light_color = Color(0.72, 0.6, 0.66)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = true # sun shafts through the laundry once it's up
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.95, 0.9, 0.85)
	env.volumetric_fog_length = 32.0
	env.volumetric_fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_add(stage, world_env, "WorldEnvironment")


func _build_lights() -> void:
	var lights := _add(stage, Node3D.new(), "Lights")
	# The sun first: the key light keeps its shadow on every graphics preset. It starts
	# below the horizon; CourtyardLife raises it round by round.
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.0
	sun.light_color = Color(1.0, 0.6, 0.35)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.light_volumetric_fog_energy = 1.4
	sun.transform = Transform3D(Basis.looking_at(Vector3(0.42, 0.05, 0.9)), Vector3(0, 20, 0))
	_add(lights, sun, "Sun")
	# The lamp over the gate, still on at dawn.
	_batch(mat_metal, Vector3(0.05, 0.05, 0.4), Transform3D(Basis(), Vector3(GATE_X, 2.75, BACK_Z + 0.15)))
	_batch(mat_bulb, Vector3(0.16, 0.12, 0.16), Transform3D(Basis(), Vector3(GATE_X, 2.68, BACK_Z + 0.35)))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(GATE_X, 2.55, BACK_Z + 0.45)
	lamp.light_color = WARM
	lamp.light_energy = 2.2
	lamp.omni_range = 7.0
	lamp.light_volumetric_fog_energy = 0.8
	_add(lights, lamp, "GateLamp")
	# A cool fill from the front so faces read before the sun is up.
	var fill := SpotLight3D.new()
	var fill_at := Vector3(-2.0, 5.0, 8.0)
	fill.transform = Transform3D(Basis.looking_at(Vector3(0, 1.0, 0) - fill_at), fill_at)
	fill.light_energy = 2.8
	fill.spot_range = 15.0
	fill.spot_angle = 36.0
	fill.light_color = Color(0.72, 0.78, 1.0)
	fill.light_volumetric_fog_energy = 0.0
	_add(lights, fill, "FrontFill")
	# The tea house kitchen's window glow and the corner store (lit when its shutter rolls up).
	var kitchen := OmniLight3D.new()
	kitchen.position = Vector3(-SIDE_X + 0.8, 1.7, -3.6)
	kitchen.light_color = WARM
	kitchen.light_energy = 1.3
	kitchen.omni_range = 5.0
	_add(lights, kitchen, "KitchenLight")
	var shop := OmniLight3D.new()
	shop.position = Vector3(SIDE_X - 0.8, 1.6, -3.4)
	shop.light_color = Color(1.0, 0.92, 0.8)
	shop.light_energy = 0.0
	shop.omni_range = 5.0
	_add(lights, shop, "ShopLight")


# --- Floor and walls -------------------------------------------------------------

func _build_floor() -> void:
	var depth := NEAR_Z - BACK_Z
	_batch(mat_tiles, Vector3(SIDE_X * 2.0, 0.2, depth), Transform3D(Basis(), Vector3(0, -0.1, (NEAR_Z + BACK_Z) / 2.0)))
	# A drain channel along the back wall, with a grate.
	_batch(mat_dark, Vector3(SIDE_X * 2.0, 0.01, 0.18), Transform3D(Basis(), Vector3(0, 0.003, BACK_Z + 0.25)))
	for i in 14:
		_batch(mat_metal, Vector3(0.03, 0.012, 0.2), Transform3D(Basis(), Vector3(5.0 + i * 0.08, 0.006, BACK_Z + 0.25)))


## The courtyard's back wall: plaster over a concrete dado, a clay coping, the open red
## gate with its posts and lunar new year couplets.
func _build_back_wall() -> void:
	var gate_left := GATE_X - GATE_WIDTH / 2.0
	var gate_right := GATE_X + GATE_WIDTH / 2.0
	for span in [[-SIDE_X - 0.5, gate_left - 0.15], [gate_right + 0.15, SIDE_X + 0.5]]:
		var width: float = span[1] - span[0]
		var center: float = (span[0] + span[1]) / 2.0
		_batch(_plaster[1], Vector3(width, WALL_TOP, 0.3), Transform3D(Basis(), Vector3(center, WALL_TOP / 2.0, BACK_Z - 0.15)))
		_batch(mat_concrete, Vector3(width, 0.5, 0.32), Transform3D(Basis(), Vector3(center, 0.25, BACK_Z - 0.15)))
		_batch(mat_clay, Vector3(width, 0.08, 0.42), Transform3D(Basis(), Vector3(center, WALL_TOP + 0.04, BACK_Z - 0.15)))
		for k in int(width / 1.6): # pigeons on the coping, away from the gate
			var x: float = span[0] + 0.5 + k * 1.6 + _rng.randf_range(-0.3, 0.3)
			if absf(x - GATE_X) > 1.6 and absf(x) < SIDE_X - 0.6:
				_perches.append(Vector3(x, WALL_TOP + 0.08, BACK_Z - 0.15 + _rng.randf_range(-0.08, 0.08)))
	# Gate posts (red, a 福 diamond on each) and the iron gate leaves swung open into the lane.
	for side in [-1.0, 1.0]:
		var post_x: float = GATE_X + side * (GATE_WIDTH / 2.0 + 0.075)
		_batch(mat_red, Vector3(0.15, 2.65, 0.36), Transform3D(Basis(), Vector3(post_x, 1.325, BACK_Z - 0.15)))
		var diamond := _label("福", 120, Color(1.0, 0.82, 0.3))
		diamond.position = Vector3(post_x, 1.75, BACK_Z + 0.04)
		diamond.rotation.z = PI # upside down: fortune has "arrived"
		diamond.pixel_size = 0.0018
		_add(stage, diamond, "Fortune%d" % int(side + 1.0))
		var hinge := Vector3(post_x - side * 0.06, 0, BACK_Z - 0.3)
		var leaf := Basis(Vector3.UP, side * deg_to_rad(110.0))
		for b in 7:
			_batch(mat_red, Vector3(0.025, 2.05, 0.025), Transform3D(leaf, hinge + leaf * Vector3(-side * (0.08 + b * 0.12), 1.05, 0)))
		for y in [0.15, 1.0, 2.05]:
			_batch(mat_red, Vector3(0.85, 0.05, 0.04), Transform3D(leaf, hinge + leaf * Vector3(-side * 0.43, y, 0)))
	# Couplets (揮春) either side of the gate: safe comings and goings, good health.
	for couplet in [["出\n入\n平\n安", gate_left - 0.55], ["身\n體\n健\n康", gate_right + 0.55]]:
		_batch(mat_red, Vector3(0.3, 1.3, 0.01), Transform3D(Basis(), Vector3(couplet[1], 1.45, BACK_Z + 0.006)))
		var text := _label(couplet[0], 64, Color(0.12, 0.08, 0.04))
		text.position = Vector3(couplet[1], 1.45, BACK_Z + 0.015)
		text.pixel_size = 0.0045
		text.line_spacing = -6.0
		_add(stage, text, "Couplet%d" % int(couplet[1] > GATE_X))
	# Pipes and a meter box on the wall.
	_batch(mat_metal, Vector3(0.06, WALL_TOP, 0.06), Transform3D(Basis(), Vector3(-7.4, WALL_TOP / 2.0, BACK_Z + 0.05)))
	_batch(mat_metal, Vector3(0.35, 0.45, 0.15), Transform3D(Basis(), Vector3(-7.0, 1.5, BACK_Z + 0.08)))


## The lane behind the wall and the single-storey sheds across it (corrugated roofs, a
## lit doorway, a vent puffing steam), low enough for the skyline to show over them.
func _build_lane_and_sheds() -> void:
	_batch(mat_concrete, Vector3(40, 0.2, LANE_Z - BACK_Z + 0.4 + 6.0), Transform3D(Basis(), Vector3(0, -0.12, (LANE_Z + BACK_Z) / 2.0 - 3.0)))
	var x := -16.0
	var index := 0
	while x < 16.0:
		var width := _rng.randf_range(3.2, 4.6)
		var height := _rng.randf_range(3.3, 3.9)
		var center := x + width / 2.0
		var wall: Material = _plaster[(index + 2) % _plaster.size()] if index % 3 != 1 else mat_concrete
		_batch(wall, Vector3(width - 0.06, height, 4.0), Transform3D(Basis(), Vector3(center, height / 2.0, LANE_Z - 2.0)))
		_batch(mat_iron, Vector3(width + 0.1, 0.06, 4.5), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-6.0)), Vector3(center, height + 0.2, LANE_Z - 2.0)))
		_perches.append(Vector3(center + _rng.randf_range(-0.8, 0.8), height + 0.12, LANE_Z + 0.15))
		# A door and a small grilled window on each.
		var lit := index == 3
		_batch(mat_window_lit if lit else mat_dark, Vector3(0.9, 2.0, 0.04), Transform3D(Basis(), Vector3(center - width * 0.2, 1.0, LANE_Z + 0.02)))
		_batch(mat_window_dark, Vector3(0.8, 0.6, 0.04), Transform3D(Basis(), Vector3(center + width * 0.22, 1.9, LANE_Z + 0.02)))
		for b in 5:
			_batch(mat_grille, Vector3(0.02, 0.62, 0.02), Transform3D(Basis(), Vector3(center + width * 0.22 - 0.32 + b * 0.16, 1.9, LANE_Z + 0.06)))
		if index == 5:
			_batch(mat_metal, Vector3(0.18, 1.0, 0.18), Transform3D(Basis(), Vector3(center, height + 0.55, LANE_Z - 0.8)))
			var steam := StageFX.smoke(36, 4.5)
			steam.position = Vector3(center, height + 1.1, LANE_Z - 0.8)
			steam.scale = Vector3.ONE * 4.0
			_add(stage, steam, "ShedSteam")
			_steam.append(NodePath("../ShedSteam"))
		x += width
		index += 1
	# A neighbour on the gate's threshold (walks in along the lane), and a kid who climbs
	# up to sit on the wall.
	_neighbours.append([Vector3(GATE_X + 0.2, 0, BACK_Z - 0.75), 0.15, Vector3(1.5, 0, -0.6), 0])
	_neighbours.append([Vector3(GATE_X - 2.3, WALL_TOP + 0.08, BACK_Z - 0.15), 0.05, Vector3(0, -1.3, -0.5), 2])


## A tenement front closing the courtyard in on the left (side -1) or right (+1): ground
## floor shops, then floors of windows with green grilles, air-con units, balconies and
## laundry poles, in three blocks of different plaster.
func _build_side_tenement(side: float) -> void:
	var face_x := side * SIDE_X
	var inward := -side # the facade faces the courtyard
	var floors := 6 if side < 0.0 else 7
	var height := GROUND_FLOOR + floors * FLOOR_HEIGHT
	var blocks := [[BACK_Z - 0.4, -0.6], [-0.6, 6.0], [6.0, NEAR_Z + 2.0]]
	for b in blocks.size():
		var z0: float = blocks[b][0]
		var z1: float = blocks[b][1]
		var plaster: Material = _plaster[(b + (0 if side < 0.0 else 2)) % _plaster.size()]
		var block_height := height - b * 1.4 * float(b == 2)
		_batch(plaster, Vector3(10.0, block_height, z1 - z0), Transform3D(Basis(), Vector3(face_x + side * 5.0, block_height / 2.0, (z0 + z1) / 2.0)))
		_batch(mat_concrete, Vector3(0.12, 0.6, z1 - z0), Transform3D(Basis(), Vector3(face_x + inward * 0.06, 0.3, (z0 + z1) / 2.0)))
		_batch(mat_concrete, Vector3(0.3, 0.25, z1 - z0), Transform3D(Basis(), Vector3(face_x + inward * 0.15, GROUND_FLOOR, (z0 + z1) / 2.0))) # ledge over the shops
	if side < 0.0:
		_tea_house(face_x)
	else:
		_corner_store(face_x)
	# Upper floors.
	for f in floors:
		var y := GROUND_FLOOR + f * FLOOR_HEIGHT + 1.35
		var z := BACK_Z + 0.9
		while z < NEAR_Z:
			var balcony := f == 0 and z > -6.2 and z < -1.0
			if balcony:
				_balcony(face_x, inward, z, side)
			else:
				_window(face_x, inward, y, z, f >= 1 and _rng.randf() < 0.35)
			z += 2.0
	# Signs: a bone-setter's hanging sign on the left, a mahjong parlour's neon on the right.
	if side < 0.0:
		_batch(mat_metal, Vector3(0.9, 0.05, 0.05), Transform3D(Basis(), Vector3(face_x + 0.45, 6.0, 1.4)))
		_batch(_material(Color(0.95, 0.94, 0.9), 0.0, 0.6), Vector3(0.06, 2.2, 0.6), Transform3D(Basis(), Vector3(face_x + 0.85, 4.85, 1.4)))
		for k in [-1.0, 1.0]:
			var text := _label("跌\n打\n醫\n館", 60, RED)
			text.rotation.y = PI / 2.0 * k
			text.position = Vector3(face_x + 0.85 + k * 0.035, 4.85, 1.4)
			text.pixel_size = 0.0055
			text.line_spacing = -4.0
			_add(stage, text, "BoneSetter%d" % int(k + 1.0))
	else:
		var neon := _label("麻雀", 200, Color(3.0, 0.6, 1.6))
		neon.shaded = false
		neon.outline_size = 14
		neon.outline_modulate = Color(1.0, 0.2, 0.6, 0.35)
		neon.rotation.y = -PI / 2.0
		neon.position = Vector3(face_x - 0.25, 4.45, 3.4)
		neon.pixel_size = 0.004
		_add(stage, neon, "MahjongNeon")


## Left ground floor: a tea house kitchen (lit window, door where the cook comes out),
## then a closed shutter, gas cylinders and a bicycle.
func _tea_house(face_x: float) -> void:
	var x := face_x + 0.03
	_batch(mat_window_lit, Vector3(0.04, 1.4, 2.6), Transform3D(Basis(), Vector3(x, 1.7, -3.7)))
	for b in 13:
		_batch(mat_grille, Vector3(0.03, 1.45, 0.025), Transform3D(Basis(), Vector3(x + 0.08, 1.7, -4.9 + b * 0.2)))
	_batch(mat_dark, Vector3(0.05, 2.2, 1.0), Transform3D(Basis(), Vector3(x, 1.1, -1.6)))
	_neighbours.append([Vector3(face_x + 0.35, 0, -1.6), PI / 2.0 - 0.5, Vector3(-0.9, 0, 0), 0])
	_batch(mat_red, Vector3(0.08, 0.6, 3.8), Transform3D(Basis(), Vector3(x + 0.05, 2.75, -3.1)))
	var sign := _label("茶樓  TEA HOUSE", 90, GOLD)
	sign.rotation.y = PI / 2.0
	sign.position = Vector3(x + 0.1, 2.75, -3.1)
	sign.pixel_size = 0.0035
	_add(stage, sign, "TeaHouseSign")
	var steam := StageFX.smoke(30, 3.5)
	steam.position = Vector3(face_x + 0.3, 2.5, -4.6)
	steam.scale = Vector3.ONE * 3.0
	_add(stage, steam, "KitchenSteam")
	_steam.append(NodePath("../KitchenSteam"))
	_batch(mat_shutter, Vector3(0.05, 2.6, 2.6), Transform3D(Basis(), Vector3(x, 1.3, 2.4)))
	for i in 3: # LPG cylinders by the kitchen door
		var can := CylinderMesh.new()
		can.top_radius = 0.15
		can.bottom_radius = 0.15
		can.height = 0.75
		can.radial_segments = 12
		_append(_material(Color(0.9, 0.45, 0.1), 0.3, 0.5), can, Transform3D(Basis(), Vector3(face_x + 0.3 + i * 0.32, 0.375, -0.5)))
	_bicycle(Transform3D(Basis(Vector3.UP, PI / 2.0 - 0.08), Vector3(face_x + 0.35, 0, 4.3)))


## Right ground floor: a corner store behind a roller shutter (CourtyardLife rolls it up),
## a doorway and stacked crates.
func _corner_store(face_x: float) -> void:
	var x := face_x - 0.03
	_batch(mat_shop_lit, Vector3(0.04, 2.5, 3.4), Transform3D(Basis(), Vector3(x + 0.25, 1.25, -3.4)))
	for shelf in 3: # shelves of goods behind the shutter
		_batch(mat_wood, Vector3(0.35, 0.04, 3.2), Transform3D(Basis(), Vector3(x + 0.05, 0.6 + shelf * 0.6, -3.4)))
		for g in 9:
			_batch(_plastic[(g + shelf) % _plastic.size()], Vector3(0.18, 0.22, 0.2), Transform3D(Basis(), Vector3(x + 0.05, 0.73 + shelf * 0.6, -4.8 + g * 0.35)))
	var shutter := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 2.6, 3.6)
	var hanging := SurfaceTool.new() # origin at the top edge, so scaling y rolls it up
	hanging.begin(Mesh.PRIMITIVE_TRIANGLES)
	hanging.append_from(box, 0, Transform3D(Basis(), Vector3(0, -1.3, 0)))
	shutter.mesh = hanging.commit()
	shutter.material_override = mat_shutter
	shutter.position = Vector3(x - 0.04, 2.6, -3.4)
	_add(stage, shutter, "Shutter")
	_batch(mat_metal, Vector3(0.3, 0.3, 3.7), Transform3D(Basis(), Vector3(x - 0.12, 2.75, -3.4)))
	_batch(_plastic[2], Vector3(0.08, 0.5, 3.0), Transform3D(Basis(), Vector3(x - 0.05, 2.95 + 0.25, -3.4)))
	var sign := _label("士多  STORE", 80, Color(0.1, 0.15, 0.4))
	sign.rotation.y = -PI / 2.0
	sign.position = Vector3(x - 0.1, 3.2, -3.4)
	sign.pixel_size = 0.0035
	_add(stage, sign, "StoreSign")
	_batch(mat_dark, Vector3(0.05, 2.2, 1.0), Transform3D(Basis(), Vector3(x, 1.1, -0.6)))
	for c in 6: # stacked crates
		var crate: Material = _plastic[c % 2]
		_batch(crate, Vector3(0.5, 0.3, 0.4), Transform3D(Basis(Vector3.UP, c * 0.15), Vector3(face_x - 0.4, 0.15 + (c / 2) * 0.31, 1.0 + (c % 2) * 0.45)))


## A grilled window: dark glass or a lit room, a green cage of bars standing out from the
## wall (Hong Kong style), sometimes an air-con unit below and a bamboo laundry pole.
func _window(face_x: float, inward: float, y: float, z: float, laundry_pole: bool) -> void:
	var lit := _rng.randf() < 0.35
	_batch(mat_window_lit if lit else mat_window_dark, Vector3(0.04, 1.2, 1.1), Transform3D(Basis(), Vector3(face_x + inward * 0.02, y, z)))
	var out := face_x + inward * 0.38
	_batch(mat_grille, Vector3(0.36, 0.04, 1.24), Transform3D(Basis(), Vector3(face_x + inward * 0.18, y - 0.62, z)))
	_batch(mat_grille, Vector3(0.36, 0.04, 1.24), Transform3D(Basis(), Vector3(face_x + inward * 0.18, y + 0.62, z)))
	for b in 7:
		_batch(mat_grille, Vector3(0.025, 1.24, 0.025), Transform3D(Basis(), Vector3(out, y, z - 0.6 + b * 0.2)))
	if _rng.randf() < 0.5:
		_batch(mat_metal, Vector3(0.45, 0.4, 0.65), Transform3D(Basis(), Vector3(face_x + inward * 0.25, y - 0.95, z + 0.2)))
		if y < 6.0:
			_perches.append(Vector3(face_x + inward * 0.25, y - 0.74, z + 0.2))
	if laundry_pole:
		var start := Vector3(face_x + inward * 0.4, y + 0.55, z)
		var end := start + Vector3(inward * 1.6, 0.0, 0.0)
		_batch(mat_bamboo, Vector3(1.6, 0.04, 0.04), Transform3D(Basis(), (start + end) / 2.0))
		for k in 3:
			_cloth(start.lerp(end, 0.2 + k * 0.28) + Vector3.DOWN * 0.02, 0.4, _rng.randf_range(0.45, 0.8), Vector3.FORWARD)


## A first-floor balcony with a solid parapet: a neighbour comes out here to watch.
func _balcony(face_x: float, inward: float, z: float, side: float) -> void:
	var floor_y := GROUND_FLOOR + 0.05
	_batch(mat_concrete, Vector3(0.9, 0.12, 1.8), Transform3D(Basis(), Vector3(face_x + inward * 0.45, floor_y, z)))
	_batch(_plaster[4], Vector3(0.08, 1.0, 1.8), Transform3D(Basis(), Vector3(face_x + inward * 0.86, floor_y + 0.55, z)))
	for e in [-0.86, 0.86]:
		_batch(_plaster[4], Vector3(0.9, 1.0, 0.08), Transform3D(Basis(), Vector3(face_x + inward * 0.45, floor_y + 0.55, z + e)))
	_batch(mat_grille, Vector3(0.05, 0.05, 1.8), Transform3D(Basis(), Vector3(face_x + inward * 0.86, floor_y + 1.12, z)))
	_batch(mat_dark, Vector3(0.04, 2.1, 0.9), Transform3D(Basis(), Vector3(face_x + inward * 0.02, floor_y + 1.05, z)))
	var yaw := atan2(-face_x, -z) # toward the fight
	# Waits indoors and steps out through the balcony door.
	_neighbours.append([Vector3(face_x + inward * 0.5, floor_y + 0.06, z), yaw, Vector3(-inward * 1.2, 0, 0), 1])
	_cloth(Vector3(face_x + inward * 0.86, floor_y + 1.1, z - 0.4), 0.5, 0.55, Vector3.RIGHT) # towels over the parapet
	_cloth(Vector3(face_x + inward * 0.86, floor_y + 1.1, z + 0.3), 0.45, 0.5, Vector3.RIGHT)


## Bamboo scaffolding with green netting over part of the right tenement (repairs).
func _build_scaffolding() -> void:
	var x := SIDE_X - 0.55
	var z0 := 1.2
	var z1 := 9.0
	var top := GROUND_FLOOR + 6.0 * FLOOR_HEIGHT
	var z := z0
	while z <= z1 + 0.01:
		for dx in [0.0, -0.45]:
			_batch(mat_bamboo, Vector3(0.05, top - GROUND_FLOOR, 0.05), Transform3D(Basis(), Vector3(x + dx, (top + GROUND_FLOOR) / 2.0, z)))
		z += 1.3
	var y := GROUND_FLOOR + 0.2
	while y < top:
		for dx in [0.0, -0.45]:
			_batch(mat_bamboo, Vector3(0.04, 0.04, z1 - z0), Transform3D(Basis(), Vector3(x + dx, y, (z0 + z1) / 2.0)))
		y += 1.4
	_batch(mat_net, Vector3(0.01, top - GROUND_FLOOR - 2.4, z1 - z0 - 1.5), Transform3D(Basis(), Vector3(x - 0.5, (top + GROUND_FLOOR + 2.4) / 2.0, (z0 + z1 + 1.5) / 2.0)))


# --- Props -----------------------------------------------------------------------

func _build_courtyard_props() -> void:
	# A folding table with a tea set and two plastic stools, at the right.
	var table := Vector3(6.9, 0, -3.6)
	_batch(_material(Color(0.6, 0.35, 0.2), 0.0, 0.6), Vector3(0.8, 0.04, 0.8), Transform3D(Basis(), table + Vector3(0, 0.72, 0)))
	for lx in [-0.35, 0.35]:
		for lz in [-0.35, 0.35]:
			_batch(mat_metal, Vector3(0.03, 0.72, 0.03), Transform3D(Basis(), table + Vector3(lx, 0.36, lz)))
	var pot := SphereMesh.new()
	pot.radius = 0.08
	pot.height = 0.13
	pot.radial_segments = 10
	pot.rings = 5
	_append(_material(Color(0.85, 0.85, 0.82), 0.1, 0.3), pot, Transform3D(Basis(), table + Vector3(-0.1, 0.8, 0.05)))
	for c in 3:
		_batch(_material(Color(0.95, 0.95, 0.92), 0.0, 0.3), Vector3(0.06, 0.05, 0.06), Transform3D(Basis(), table + Vector3(0.12 + c * 0.1, 0.765, -0.15 + c * 0.1)))
	for s in 2:
		var seat := CylinderMesh.new()
		seat.top_radius = 0.16
		seat.bottom_radius = 0.15
		seat.height = 0.04
		seat.radial_segments = 12
		var spot := table + Vector3(-0.75 + s * 1.45, 0, 0.2 - s * 0.5)
		_append(_plastic[s * 3 % _plastic.size()], seat, Transform3D(Basis(), spot + Vector3(0, 0.42, 0)))
		for leg in 4:
			var a := leg * PI / 2.0 + 0.4
			_batch(_plastic[s * 3 % _plastic.size()], Vector3(0.035, 0.42, 0.035), Transform3D(Basis(), spot + Vector3(cos(a) * 0.12, 0.21, sin(a) * 0.12)))
	# Styrofoam planters and pots along the back wall, right of the gate; a big potted
	# palm by the shrine.
	for p in 6:
		var at := Vector3(3.6 + p * 0.9, 0, BACK_Z + 0.4)
		_batch(mat_styro, Vector3(0.6, 0.3, 0.4), Transform3D(Basis(), at + Vector3(0, 0.15, 0)))
		for l in 5:
			_batch(mat_leaf, Vector3(0.1, _rng.randf_range(0.25, 0.5), 0.1), Transform3D(Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.1, 0.5)), at + Vector3(-0.2 + l * 0.1, 0.45, 0)))
	_plant(Vector3(-3.3, 0, BACK_Z + 0.45), 1.2)
	_plant(Vector3(-8.6, 0, BACK_Z + 0.5), 1.6)
	# Bird cages hanging from a bracket on the left tenement.
	for c in 2:
		var at := Vector3(-SIDE_X + 0.6, 2.25, 5.5 + c * 0.7)
		_batch(mat_metal, Vector3(0.6, 0.03, 0.03), Transform3D(Basis(), at + Vector3(-0.3, 0.45, 0)))
		_batch(mat_bamboo, Vector3(0.36, 0.03, 0.36), Transform3D(Basis(), at))
		for b in 8:
			var a := b * TAU / 8.0
			_batch(mat_bamboo, Vector3(0.012, 0.42, 0.012), Transform3D(Basis(), at + Vector3(cos(a) * 0.16, 0.21, sin(a) * 0.16)))
		_batch(_material(Color(0.95, 0.85, 0.2), 0.0, 0.6), Vector3(0.06, 0.06, 0.1), Transform3D(Basis(), at + Vector3(0, 0.12, 0)))


func _plant(at: Vector3, size: float) -> void:
	var pot := CylinderMesh.new()
	pot.top_radius = 0.24 * size
	pot.bottom_radius = 0.17 * size
	pot.height = 0.4 * size
	pot.radial_segments = 12
	_append(mat_clay, pot, Transform3D(Basis(), at + Vector3(0, 0.2 * size, 0)))
	for l in 9:
		var a := l * TAU / 9.0 + _rng.randf() * 0.3
		var tilt := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), _rng.randf_range(0.25, 0.7))
		_batch(mat_leaf, Vector3(0.12, 0.8 * size, 0.03), Transform3D(tilt, at + Vector3(0, 0.4 * size, 0) + tilt * Vector3(0, 0.4 * size, 0)))


func _bicycle(xform: Transform3D) -> void:
	for wx in [-0.52, 0.52]:
		var wheel := TorusMesh.new()
		wheel.inner_radius = 0.3
		wheel.outer_radius = 0.33
		wheel.rings = 20
		wheel.ring_segments = 6
		_append(mat_dark, wheel, xform * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(wx, 0.33, 0)))
	for bar in [[Vector3(-0.52, 0.33, 0), Vector3(0.0, 0.75, 0)], [Vector3(0.0, 0.75, 0), Vector3(0.52, 0.33, 0)],
			[Vector3(-0.1, 0.33, 0), Vector3(0.0, 0.75, 0)], [Vector3(-0.1, 0.33, 0), Vector3(-0.52, 0.33, 0)],
			[Vector3(0.0, 0.75, 0), Vector3(0.45, 0.95, 0)], [Vector3(0.42, 0.95, -0.25), Vector3(0.42, 0.95, 0.25)]]:
		var a: Vector3 = xform * bar[0]
		var b: Vector3 = xform * bar[1]
		var dir := b - a
		_batch(_material(Color(0.12, 0.3, 0.5), 0.5, 0.4), Vector3(0.03, 0.03, dir.length()), Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT), (a + b) / 2.0))


## Lian's wooden dummy (mook jong): a trunk on two slats between posts, two upper arms
## angled up and in, a middle arm and a bent leg.
func _build_wooden_dummy(at: Vector3) -> void:
	for px in [-0.55, 0.55]:
		_batch(mat_wood, Vector3(0.1, 1.9, 0.1), Transform3D(Basis(), at + Vector3(px, 0.95, -0.25)))
	for y in [0.45, 1.6]:
		_batch(mat_wood, Vector3(1.2, 0.08, 0.06), Transform3D(Basis(), at + Vector3(0, y, -0.25)))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.14
	trunk.height = 1.5
	trunk.radial_segments = 14
	_append(mat_wood, trunk, Transform3D(Basis(), at + Vector3(0, 1.05, -0.12)))
	var arm := CylinderMesh.new()
	arm.top_radius = 0.025
	arm.bottom_radius = 0.032
	arm.height = 0.5
	arm.radial_segments = 8
	for side in [-1.0, 1.0]:
		var basis := Basis(Vector3.UP, side * 0.35) * Basis(Vector3.RIGHT, PI / 2.0 - 0.15)
		_append(mat_wood, arm, Transform3D(basis, at + Vector3(side * 0.06, 1.45, 0.12)))
	_append(mat_wood, arm, Transform3D(Basis(Vector3.RIGHT, PI / 2.0 + 0.1), at + Vector3(0, 1.15, 0.15)))
	var leg := CylinderMesh.new()
	leg.top_radius = 0.035
	leg.bottom_radius = 0.035
	leg.height = 0.45
	leg.radial_segments = 8
	_append(mat_wood, leg, Transform3D(Basis(Vector3.RIGHT, PI / 2.0 - 0.3), at + Vector3(0.02, 0.62, 0.12)))
	_append(mat_wood, leg, Transform3D(Basis(Vector3.RIGHT, 0.15), at + Vector3(0.02, 0.33, 0.34)))


## The earth god (土地) shrine at the foot of the wall: a red niche with candles, incense
## smoke and an offering of oranges.
func _build_shrine(at: Vector3) -> void:
	_batch(mat_red, Vector3(0.62, 0.62, 0.32), Transform3D(Basis(), at + Vector3(0, 0.31, 0.16)))
	_batch(mat_dark, Vector3(0.44, 0.38, 0.02), Transform3D(Basis(), at + Vector3(0, 0.33, 0.325)))
	_batch(mat_gold, Vector3(0.5, 0.05, 0.05), Transform3D(Basis(), at + Vector3(0, 0.6, 0.33)))
	var title := _label("土地", 70, GOLD)
	title.position = at + Vector3(0, 0.47, 0.34)
	title.pixel_size = 0.0022
	_add(stage, title, "ShrineTitle")
	_batch(mat_red, Vector3(0.66, 0.08, 0.36), Transform3D(Basis(), at + Vector3(0, 0.04, 0.4)))
	for k in 3: # oranges
		var orange := SphereMesh.new()
		orange.radius = 0.04
		orange.height = 0.08
		orange.radial_segments = 8
		orange.rings = 4
		_append(_material(Color(1.0, 0.5, 0.05), 0.0, 0.5), orange, Transform3D(Basis(), at + Vector3(-0.08 + k * 0.08, 0.12, 0.45)))
	for c in [-0.2, 0.2]:
		_batch(mat_red, Vector3(0.04, 0.12, 0.04), Transform3D(Basis(), at + Vector3(c, 0.14, 0.48)))
		_batch(mat_bulb, Vector3(0.02, 0.03, 0.02), Transform3D(Basis(), at + Vector3(c, 0.215, 0.48)))
	for s in 3:
		_batch(_material(Color(0.6, 0.2, 0.1), 0.0, 0.8), Vector3(0.008, 0.25, 0.008), Transform3D(Basis(Vector3.FORWARD, (s - 1) * 0.12), at + Vector3((s - 1) * 0.02, 0.2, 0.42)))
	var smoke := StageFX.smoke(24, 5.0)
	smoke.position = at + Vector3(0, 0.34, 0.42)
	_add(stage, smoke, "IncenseSmoke")
	var candle := OmniLight3D.new()
	candle.position = at + Vector3(0, 0.35, 0.6)
	candle.light_color = Color(1.0, 0.45, 0.2)
	candle.light_energy = 0.9
	candle.omni_range = 2.2
	_add(stage, candle, "ShrineCandle")
	var flicker := Node.new()
	flicker.set_script(load(FLICKER_SCRIPT))
	_add(stage, flicker, "CandleFlicker")
	var lights: Array[NodePath] = [NodePath("../ShrineCandle")]
	flicker.set("lights", lights)
	flicker.set("amount", 0.3)


## Laundry lines across the back of the courtyard and red lanterns over the gate.
func _build_overhead() -> void:
	for line in [[BACK_Z + 1.0, 4.3, 0.5], [BACK_Z + 2.4, 4.9, 0.6]]:
		var a := Vector3(-SIDE_X, line[1], line[0])
		var b := Vector3(SIDE_X, line[1] + 0.2, line[0] + 0.6)
		_wire(a, b, line[2])
		var count := 14
		for i in count:
			var t := (i + 0.5 + _rng.randf_range(-0.2, 0.2)) / count
			if _rng.randf() < 0.25:
				continue
			var p := a.lerp(b, t) + Vector3.DOWN * sin(t * PI) * float(line[2])
			_cloth(p, _rng.randf_range(0.35, 0.7), _rng.randf_range(0.45, 1.0), (b - a).normalized())
	var lantern_line := [Vector3(GATE_X - 2.4, 3.6, BACK_Z + 0.25), Vector3(GATE_X + 2.4, 3.6, BACK_Z + 0.25)]
	_wire(lantern_line[0], lantern_line[1], 0.25)
	for post in lantern_line: # the line runs between two poles off the wall
		_batch(mat_metal, Vector3(0.05, 3.6, 0.05), Transform3D(Basis(), Vector3(post.x, 1.8, post.z)))
	for i in 3:
		var t := 0.25 + i * 0.25
		var pivot := Node3D.new()
		pivot.position = (lantern_line[0] as Vector3).lerp(lantern_line[1], t) + Vector3.DOWN * sin(t * PI) * 0.25
		_add(stage, pivot, "Lantern%d" % i)
		var body := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.2
		ball.height = 0.34
		ball.radial_segments = 14
		ball.rings = 8
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(ball, 0, Transform3D(Basis(), Vector3(0, -0.4, 0)))
		var cap := CylinderMesh.new()
		cap.top_radius = 0.07
		cap.bottom_radius = 0.07
		cap.height = 0.05
		st.append_from(cap, 0, Transform3D(Basis(), Vector3(0, -0.22, 0)))
		st.append_from(cap, 0, Transform3D(Basis(), Vector3(0, -0.58, 0)))
		var cord := BoxMesh.new()
		cord.size = Vector3(0.01, 0.2, 0.01)
		st.append_from(cord, 0, Transform3D(Basis(), Vector3(0, -0.1, 0)))
		body.mesh = st.commit()
		body.material_override = _emissive(Color(0.95, 0.12, 0.08), 0.6)
		_add(pivot, body, "Body")
		_lanterns.append(NodePath("../Lantern%d" % i))


## A piece of laundry hanging from `top` (its top edge centre), `width` along `along`,
## `drop` down: two subdivided quads in the laundry shader's mesh (UV.y 0 at the line).
func _cloth(top: Vector3, width: float, drop: float, along: Vector3) -> void:
	var colors := [Color(0.95, 0.95, 0.92), Color(0.85, 0.2, 0.2), Color(0.25, 0.4, 0.75), Color(0.95, 0.8, 0.3),
		Color(0.35, 0.6, 0.4), Color(0.9, 0.6, 0.7), Color(0.3, 0.3, 0.35), Color(0.6, 0.75, 0.9)]
	var color: Color = colors[_rng.randi() % colors.size()]
	var right := along.normalized() * width / 2.0
	var rows := 3
	for r in rows:
		var v0 := float(r) / rows
		var v1 := float(r + 1) / rows
		var quad := [[top - right + Vector3.DOWN * drop * v0, Vector2(0, v0)], [top + right + Vector3.DOWN * drop * v0, Vector2(1, v0)],
			[top + right + Vector3.DOWN * drop * v1, Vector2(1, v1)], [top - right + Vector3.DOWN * drop * v1, Vector2(0, v1)]]
		var normal := along.cross(Vector3.UP).normalized()
		for i in [0, 1, 2, 0, 2, 3]:
			_laundry.set_color(color)
			_laundry.set_normal(normal)
			_laundry.set_uv(quad[i][1])
			_laundry.add_vertex(quad[i][0])


# --- Skyline ------------------------------------------------------------------------

## Kowloon beyond the sheds: rows of tenements growing taller with distance, every row
## low enough to stay under the fight camera's view line (about 8° up), so a strip of
## dawn sky shows above them; rooftop water tanks and antennas; the hills behind.
func _build_skyline() -> void:
	var rows := [[-30.0, 4.5, 6.5, 70.0], [-55.0, 8.0, 10.5, 110.0], [-90.0, 12.0, 15.0, 160.0], [-140.0, 17.0, 21.5, 230.0], [-210.0, 24.0, 30.0, 330.0]]
	var walls := [Color(0.62, 0.6, 0.58), Color(0.7, 0.66, 0.6), Color(0.55, 0.6, 0.62), Color(0.68, 0.62, 0.64), Color(0.6, 0.64, 0.58)]
	for row: Array in rows:
		var x: float = -row[3]
		while x < row[3]:
			var width := _rng.randf_range(8.0, 18.0)
			var height := _rng.randf_range(row[1], row[2])
			var depth := _rng.randf_range(10.0, 16.0)
			var z: float = row[0] - _rng.randf_range(0.0, 6.0)
			_skyline_box(Vector3(x + width / 2.0, height / 2.0, z - depth / 2.0), Vector3(width - 0.6, height, depth), walls[_rng.randi() % walls.size()])
			if _rng.randf() < 0.45: # water tank or a stair hut on the roof
				_skyline_box(Vector3(x + width * _rng.randf_range(0.3, 0.7), height + 0.9, z - depth * 0.4), Vector3(2.0, 1.8, 2.0), Color(0.45, 0.45, 0.48))
			if _rng.randf() < 0.3:
				_skyline_box(Vector3(x + width * 0.5, height + 2.5, z - depth * 0.5), Vector3(0.15, 5.0, 0.15), Color(0.3, 0.3, 0.32))
			x += width + _rng.randf_range(0.5, 4.0)
	# The hills behind Kowloon, a hazy ridge (unshaded, the fog fades it into the sky).
	var ridge := SurfaceTool.new()
	ridge.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := []
	for i in 41:
		var x := -1600.0 + i * 80.0
		var peak := 70.0 + 50.0 * sin(i * 0.45) + 30.0 * sin(i * 1.3 + 1.0) + (60.0 if i in [17, 18] else 0.0)
		points.append(Vector3(x, peak, -900.0))
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		for v in [a, b, Vector3(b.x, 0, b.z), a, Vector3(b.x, 0, b.z), Vector3(a.x, 0, a.z)]:
			ridge.set_color(Color(0.42, 0.42, 0.55))
			ridge.set_normal(Vector3.BACK)
			ridge.add_vertex(v)
	var hills := MeshInstance3D.new()
	hills.mesh = ridge.commit()
	var hill_material := _material(Color.WHITE, 0.0, 1.0)
	hill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hill_material.vertex_color_use_as_albedo = true
	hills.material_override = hill_material
	hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(stage, hills, "Hills")


func _skyline_box(center: Vector3, size: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var shade := color * _rng.randf_range(0.85, 1.1)
	for index in indices:
		_skyline.set_color(Color(shade, 1.0))
		_skyline.set_normal(normals[index])
		_skyline.add_vertex(verts[index] + center)


func _flush_skyline_and_laundry() -> void:
	var skyline := MeshInstance3D.new()
	skyline.mesh = _skyline.commit()
	skyline.material_override = mat_skyline
	skyline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(stage, skyline, "Skyline")
	var laundry := MeshInstance3D.new()
	laundry.mesh = _laundry.commit()
	laundry.material_override = mat_laundry
	_add(stage, laundry, "Laundry")


# --- Cat and jet --------------------------------------------------------------------

## A tabby cat sitting on the wall's coping (CourtyardLife makes it bolt and come back).
## Faces local +X.
func _build_cat() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fur := Color(0.62, 0.45, 0.28)
	var dark := Color(0.25, 0.18, 0.12)
	for part in [[Vector3(0.0, 0.14, 0), Vector3(0.34, 0.16, 0.15), fur], [Vector3(0.2, 0.27, 0), Vector3(0.14, 0.13, 0.13), fur],
			[Vector3(0.23, 0.36, 0.04), Vector3(0.03, 0.06, 0.03), dark], [Vector3(0.23, 0.36, -0.04), Vector3(0.03, 0.06, 0.03), dark],
			[Vector3(0.12, 0.04, 0.05), Vector3(0.05, 0.1, 0.05), fur], [Vector3(0.12, 0.04, -0.05), Vector3(0.05, 0.1, 0.05), fur],
			[Vector3(-0.12, 0.04, 0.05), Vector3(0.05, 0.1, 0.05), fur], [Vector3(-0.12, 0.04, -0.05), Vector3(0.05, 0.1, 0.05), fur],
			[Vector3(-0.27, 0.22, 0), Vector3(0.04, 0.24, 0.04), dark]]:
		var box := BoxMesh.new()
		box.size = part[1]
		var arrays := box.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			st.set_color(part[2])
			st.set_normal(normals[index])
			st.add_vertex(verts[index] + part[0])
	var cat := MeshInstance3D.new()
	cat.mesh = st.commit()
	var material := _material(Color.WHITE, 0.0, 0.9)
	material.vertex_color_use_as_albedo = true
	cat.material_override = material
	cat.position = Vector3(6.2, WALL_TOP + 0.08, BACK_Z - 0.15)
	cat.rotation.y = PI
	_add(stage, cat, "Cat")


## An airliner on approach (CourtyardLife flies it low over the courtyard now and then):
## white fuselage, swept wings with engines, a tall fin, navigation lights and a landing
## light that sweeps the courtyard before sunrise. It casts a shadow (the fight camera sees
## that, not the plane). Nose toward local +X, about 38 m long.
func _build_jet() -> void:
	var white := _material(Color(0.92, 0.93, 0.95), 0.2, 0.4)
	var grey := _material(Color(0.6, 0.62, 0.66), 0.4, 0.4)
	var fin := _material(Color(0.12, 0.35, 0.45), 0.2, 0.4)
	var parts := {white: SurfaceTool.new(), grey: SurfaceTool.new(), fin: SurfaceTool.new()}
	for st: SurfaceTool in parts.values():
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fuselage := CylinderMesh.new()
	fuselage.top_radius = 2.0
	fuselage.bottom_radius = 2.0
	fuselage.height = 30.0
	fuselage.radial_segments = 16
	(parts[white] as SurfaceTool).append_from(fuselage, 0, Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3.ZERO))
	var nose := SphereMesh.new()
	nose.radius = 2.0
	nose.height = 6.0
	nose.radial_segments = 16
	nose.rings = 8
	(parts[white] as SurfaceTool).append_from(nose, 0, Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(15.0, 0, 0)))
	var tail := CylinderMesh.new()
	tail.top_radius = 0.5
	tail.bottom_radius = 2.0
	tail.height = 8.0
	tail.radial_segments = 16
	(parts[white] as SurfaceTool).append_from(tail, 0, Transform3D(Basis(Vector3.FORWARD, -PI / 2.0), Vector3(-19.0, 0.6, 0)))
	for side in [-1.0, 1.0]:
		var wing := BoxMesh.new()
		wing.size = Vector3(5.0, 0.4, 16.0)
		(parts[grey] as SurfaceTool).append_from(wing, 0, Transform3D(Basis(Vector3.UP, side * 0.45), Vector3(-1.5, -0.8, side * 9.0)))
		var engine := CylinderMesh.new()
		engine.top_radius = 1.1
		engine.bottom_radius = 1.1
		engine.height = 4.0
		engine.radial_segments = 12
		(parts[grey] as SurfaceTool).append_from(engine, 0, Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(1.0, -2.0, side * 6.0)))
		var stabiliser := BoxMesh.new()
		stabiliser.size = Vector3(2.5, 0.25, 6.0)
		(parts[grey] as SurfaceTool).append_from(stabiliser, 0, Transform3D(Basis(Vector3.UP, side * 0.5), Vector3(-20.0, 1.0, side * 3.0)))
	var tail_fin := BoxMesh.new()
	tail_fin.size = Vector3(4.5, 7.0, 0.3)
	(parts[fin] as SurfaceTool).append_from(tail_fin, 0, Transform3D(Basis(Vector3.FORWARD, -0.45), Vector3(-19.5, 4.5, 0)))
	var mesh := ArrayMesh.new()
	for material: Material in parts:
		(parts[material] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	var jet := Node3D.new()
	jet.visible = false
	jet.position = Vector3(-2000, 60, -260)
	_add(stage, jet, "Jet")
	var hull := MeshInstance3D.new()
	hull.mesh = mesh
	_add(jet, hull, "Hull")
	var landing := SpotLight3D.new()
	landing.position = Vector3(14.0, -1.8, 0)
	landing.basis = Basis.looking_at(Vector3(1.0, -0.6, 0.0).normalized())
	landing.light_color = Color(1.0, 0.96, 0.88)
	landing.light_energy = 60.0
	landing.spot_range = 160.0
	landing.spot_angle = 18.0
	landing.spot_attenuation = 0.4
	landing.light_volumetric_fog_energy = 0.6
	_add(jet, landing, "LandingLight")
	for light in [[Vector3(12.0, -1.5, 0), Color(1.0, 0.97, 0.88), 0.9, 12.0], [Vector3(-1.0, -0.8, -16.5), Color(1.0, 0.1, 0.05), 0.45, 8.0], [Vector3(-1.0, -0.8, 16.5), Color(0.1, 1.0, 0.3), 0.45, 8.0]]:
		var bulb := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = light[2]
		ball.height = light[2] * 2.0
		ball.radial_segments = 8
		ball.rings = 4
		bulb.mesh = ball
		bulb.material_override = _emissive(light[1], light[3])
		bulb.position = light[0]
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(jet, bulb, "Light%d" % jet.get_child_count())


## An unseen block of tenements behind the camera that only casts shadows: the rising
## sun (CourtyardLife) clears it gradually, so round 2 lights the tops and the final round
## the courtyard floor.
func _build_sun_blocker() -> void:
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(60.0, 12.0, 8.0)
	block.mesh = box
	block.position = Vector3(0, 6.0, 26.0)
	block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_add(stage, block, "SunBlocker")


# --- Life, shadows ------------------------------------------------------------------

func _build_life() -> void:
	var life := Node.new()
	life.set_script(load(LIFE_SCRIPT))
	_add(stage, life, "Life")
	life.set("window_material", mat_window_lit)
	life.set("lamp_material", mat_bulb)
	life.set("shop_material", mat_shop_lit)
	life.set("skyline_material", mat_skyline)
	life.set("laundry_material", mat_laundry)
	life.set("perches", _perches)
	var spots := PackedVector3Array()
	var yaws := PackedFloat32Array()
	var hides := PackedVector3Array()
	var kinds := PackedInt32Array()
	for n: Array in _neighbours:
		spots.append(n[0])
		yaws.append(n[1])
		hides.append(n[2])
		kinds.append(n[3])
	life.set("neighbour_spots", spots)
	life.set("neighbour_yaws", yaws)
	life.set("neighbour_hidden", hides)
	life.set("neighbour_kinds", kinds)
	life.set("steam", _steam)
	life.set("lanterns", _lanterns)
	life.set("cat_escape", Vector3(SIDE_X + 1.5, WALL_TOP + 0.08, BACK_Z - 0.15))
	print("life: %d perches, %d neighbour spots" % [_perches.size(), _neighbours.size()])


## Baked contact shadows on the courtyard floor (StageAO).
func _bake_contact_shadows() -> void:
	StageAO.collect(_footprints, stage, 0.0, ["Geometry", "Skyline", "Hills", "Jet", "Laundry", "SunBlocker"])
	var half := Vector2(10.0, 11.0)
	var center := Vector2(0.0, 3.0)
	var image := StageAO.bake(_footprints, center, half, 256)
	_add(stage, StageAO.overlay(StageAO.save(image, AO_PATH), center, half, 0.0), "FloorShadows")
	print("baked contact shadows from %d footprints" % _footprints.size())


# --- Helpers ---------------------------------------------------------------------

func _wire(a: Vector3, b: Vector3, sag: float, thickness := 0.015) -> void:
	var pieces := 12
	var previous := a
	for i in range(1, pieces + 1):
		var t := float(i) / pieces
		var p := a.lerp(b, t) + Vector3.DOWN * sin(t * PI) * sag
		var dir := p - previous
		if dir.length() > 0.001:
			var basis := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
			_batch(mat_dark, Vector3(thickness, thickness, dir.length()), Transform3D(basis, (previous + p) / 2.0))
		previous = p


func _batch(material: Material, size: Vector3, xform: Transform3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	_append(material, box, xform)


func _append(material: Material, mesh: PrimitiveMesh, xform: Transform3D) -> void:
	StageAO.add_aabb(_footprints, xform * mesh.get_aabb(), 0.0)
	var st: SurfaceTool = _batches.get(material)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[material] = st
	st.append_from(mesh, 0, xform)


func _flush_batches() -> void:
	var group := _add(stage, Node3D.new(), "Geometry")
	var i := 0
	for material: Material in _batches:
		var mesh := (_batches[material] as SurfaceTool).commit()
		mesh.surface_set_material(0, material)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		_add(group, mi, "Batch%d" % i)
		i += 1


func _add(parent: Node, node: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = stage
	return node


func _marker(pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.position = pos
	return m


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _textured(folder: String, texture_name: String, tint: Color, tiling: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = load(folder + texture_name + "_diff_1k.jpg")
	m.normal_enabled = true
	m.normal_texture = load(folder + texture_name + "_nor_gl_1k.jpg")
	m.roughness_texture = load(folder + texture_name + "_rough_1k.jpg")
	m.uv1_scale = Vector3(tiling, tiling, tiling)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Painted lettering facing +Z (signs).
func _label(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label
