extends SceneTree
## Builds the dojo stage (res://scenes/stages/dojo.tscn): a traditional training hall
## with a tatami fighting area, polished hinoki floor, shoji walls lit from outside,
## dark timber frame, the kamiza (shrine alcove with a hanging scroll) at the back,
## weapon racks, name boards, hanging lanterns, and students kneeling along the walls.
## Re-run after changing anything below.
##
## Run: godot_console --headless --path . -s res://tools/build_dojo_stage.gd
##
## Layout: tatami top at y = 0 (fighters stand on it), 9 m square with the outer 0.9 m
## band in red (the fight bounds are ±3.6 m); hall 20 m square, 6 m to the ceiling.
## Repeated geometry (timber, lattice, mats) is merged into one mesh per material.
## Atmosphere: dust in the light shafts, candle flicker in the lanterns and andon
## (FireFlicker), incense smoke at the kamiza, students who breathe, and baked contact
## shadows on the hall floor (StageAO).

const OUTPUT := "res://scenes/stages/dojo.tscn"
const TEX := "res://assets/stages/dojo/textures/"
const STAGE_SCRIPT := "res://scripts/stages/stage.gd"
const CROWD_SCRIPT := "res://scripts/stages/crowd.gd"
const FLICKER_SCRIPT := "res://scripts/stages/fire_flicker.gd"
const AO_PATH := "res://assets/stages/dojo/floor_ao.res"

const HALL := 10.0 # half size
const CEILING := 6.0
const BAY := 2.5 # pillar spacing
const PILLAR := 0.28
const FLOOR_TOP := -0.05 # wooden floor; the tatami sits on it with its top at 0
const MAT_HALF := 4.5
const BOUNDS := 3.6
const MAT := 0.9 # tatami width (length 1.8)
const SHOJI_BOTTOM := 1.0
const SHOJI_TOP := 3.4
const PAPER_GLOW := Color(1.0, 0.86, 0.66)
const LANTERN_RED := Color(0.85, 0.22, 0.1)
const WARM_LIGHT := Color(1.0, 0.84, 0.62)

var stage: Node3D
var _batches := {} # Material -> SurfaceTool
var _footprints := [] # everything standing on the hall floor (contact shadows)
var mat_dark_wood: StandardMaterial3D
var mat_cedar: StandardMaterial3D
var mat_hinoki: StandardMaterial3D
var mat_plaster: StandardMaterial3D
var mat_paper: StandardMaterial3D
var mat_tatami: StandardMaterial3D
var mat_tatami_red: StandardMaterial3D
var mat_seam: StandardMaterial3D
var mat_lacquer: StandardMaterial3D
var mat_lantern: StandardMaterial3D
var mat_black: StandardMaterial3D
var mat_scroll: StandardMaterial3D
var mat_skin: StandardMaterial3D
var mat_drum: StandardMaterial3D
var mat_tag: StandardMaterial3D


func _initialize() -> void:
	stage = Node3D.new()
	stage.name = "Dojo"
	stage.set_script(load(STAGE_SCRIPT))
	stage.set("rope_line", 5.8) # students (on the camera's side) hide when the camera is behind them
	stage.set("music", &"dojo")

	_make_materials()
	_build_environment()
	_build_lights()
	_build_floor()
	_build_walls()
	_build_kamiza()
	_build_props()
	_build_ceiling()
	_build_students()
	_build_atmosphere()
	_add(stage, StageFX.ambience([["res://assets/audio/ambience/wind.ogg", -26.0], ["res://assets/audio/ambience/birds.ogg", -30.0]]), "Sound") # ambient loops (StageAmbience)
	_flush_batches()
	_bake_contact_shadows()
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
	mat_dark_wood = _textured("dark_wood", Color(0.42, 0.3, 0.24), 0.8)
	mat_cedar = _textured("japanese_cedar_planks", Color(0.75, 0.6, 0.5), 0.6)
	mat_hinoki = _textured("hinoki_planks", Color(0.95, 0.85, 0.75), 0.4)
	mat_hinoki.roughness = 0.45 # polished
	mat_plaster = _textured("white_plaster_02", Color(0.93, 0.9, 0.84), 0.5)
	mat_tatami = _textured("tatami_mat", Color(1, 1, 1), 1.0 / 1.8)
	mat_tatami_red = _textured("tatami_mat", Color(0.95, 0.42, 0.36), 1.0 / 1.8)
	mat_seam = _material(Color(0.2, 0.22, 0.12), 0.0, 0.9)
	mat_paper = _emissive(PAPER_GLOW, 0.9)
	mat_paper.albedo_color = Color(0.96, 0.92, 0.84)
	mat_lacquer = _material(Color(0.12, 0.05, 0.04), 0.0, 0.25)
	mat_lantern = _emissive(LANTERN_RED, 2.2)
	mat_black = _material(Color(0.03, 0.03, 0.03), 0.0, 0.6)
	mat_scroll = _material(Color(0.93, 0.89, 0.78), 0.0, 0.9)
	mat_skin = _material(Color(0.86, 0.8, 0.66), 0.0, 0.7)
	mat_drum = _material(Color(0.42, 0.12, 0.06), 0.0, 0.35)
	mat_tag = _material(Color(0.88, 0.82, 0.7), 0.0, 0.8)


# --- Environment & lighting ------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.015, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.42, 0.32)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.ssao_enabled = false # too costly on integrated GPUs (see CLAUDE.md)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(1.0, 0.9, 0.8)
	env.volumetric_fog_length = 30.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_add(stage, world_env, "WorldEnvironment")

	# Reflections of the hall itself on the polished floor (captured once at load).
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0, 2.0, 0)
	probe.size = Vector3(HALL * 2.0, CEILING + 0.4, HALL * 2.0)
	probe.origin_offset = Vector3(0, -1.0, 0)
	probe.box_projection = true
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	_add(stage, probe, "ReflectionProbe")


func _build_lights() -> void:
	var lights := _add(stage, Node3D.new(), "Lights")
	# Key light over the tatami, with shadows.
	var key := SpotLight3D.new()
	key.position = Vector3(0, CEILING - 0.3, 0.5)
	key.rotation_degrees = Vector3(-90, 0, 0)
	key.light_energy = 9.0
	key.spot_range = 9.0
	key.spot_angle = 52.0
	key.spot_attenuation = 0.5
	key.light_color = Color(1.0, 0.93, 0.82)
	key.shadow_enabled = true
	key.light_volumetric_fog_energy = 1.2
	_add(lights, key, "KeyLight")
	# Warm modelling lights from the front corners.
	for x in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		var pos := Vector3(x * 6.0, 5.2, 5.0)
		spot.transform = Transform3D(Basis.looking_at(Vector3(0, 0.9, 0) - pos), pos)
		spot.light_energy = 3.5
		spot.spot_range = 14.0
		spot.spot_angle = 30.0
		spot.light_color = WARM_LIGHT
		spot.light_volumetric_fog_energy = 1.5
		_add(lights, spot, "FillSpot%s" % ("L" if x < 0 else "R"))
	# Soft daylight through the shoji walls (no shadows: it lights the whole hall).
	var day := DirectionalLight3D.new()
	day.rotation_degrees = Vector3(-30, -60, 0)
	day.light_energy = 0.35
	day.light_color = Color(1.0, 0.88, 0.7)
	_add(lights, day, "Daylight")


# --- Floor & tatami ------------------------------------------------------------

func _build_floor() -> void:
	# Polished wooden hall floor.
	_batch(mat_hinoki, Vector3(HALL * 2.0, 0.1, HALL * 2.0), Transform3D(Basis(), Vector3(0, FLOOR_TOP - 0.05, 0)))
	# Tatami: inner fighting area plus the red boundary band; the texture's cloth borders
	# line up with a 0.9 m mat grid. Short-edge seams are staggered row by row.
	var thickness := -FLOOR_TOP
	var y := FLOOR_TOP + thickness / 2.0
	_batch(mat_tatami, Vector3(BOUNDS * 2.0, thickness, BOUNDS * 2.0), Transform3D(Basis(), Vector3(0, y, 0)))
	var band := MAT_HALF - BOUNDS
	for side in 4:
		var horizontal := side < 2
		var sign := -1.0 if side % 2 == 0 else 1.0
		var size := Vector3(MAT_HALF * 2.0, thickness, band) if horizontal else Vector3(band, thickness, BOUNDS * 2.0)
		var center := Vector3(0, y, sign * (BOUNDS + band / 2.0)) if horizontal else Vector3(sign * (BOUNDS + band / 2.0), y, 0)
		_batch(mat_tatami_red, size, Transform3D(Basis(), center))
	var rows := int(MAT_HALF * 2.0 / MAT)
	for row in rows:
		var z := -MAT_HALF + (row + 0.5) * MAT
		var x := -MAT_HALF + (MAT if row % 2 == 1 else 0.0)
		while x < MAT_HALF - 0.01:
			if x > -MAT_HALF + 0.01:
				_batch(mat_seam, Vector3(0.025, 0.004, MAT - 0.04), Transform3D(Basis(), Vector3(x, 0.002, z)))
			x += MAT * 2.0
	# Low wooden edging around the tatami.
	for side in 4:
		var horizontal := side < 2
		var sign := -1.0 if side % 2 == 0 else 1.0
		var size := Vector3(MAT_HALF * 2.0 + 0.2, thickness + 0.01, 0.1) if horizontal else Vector3(0.1, thickness + 0.01, MAT_HALF * 2.0)
		var center := Vector3(0, y, sign * (MAT_HALF + 0.05)) if horizontal else Vector3(sign * (MAT_HALF + 0.05), y, 0)
		_batch(mat_dark_wood, size, Transform3D(Basis(), center))


# --- Walls -----------------------------------------------------------------------

## Wall-local frame for side 0..3 (0 = +Z, 1 = +X, 2 = -Z, 3 = -X): x along the wall,
## +z toward the wall (outward), y up; `dist` from the center.
func _wall(side: int, dist: float, along: float, y: float) -> Transform3D:
	var basis := Basis(Vector3.UP, side * PI / 2.0)
	var out := basis * Vector3(0, 0, 1)
	var tangent := basis * Vector3(1, 0, 0)
	return Transform3D(basis, out * dist + tangent * along + Vector3.UP * y)


func _build_walls() -> void:
	var length := HALL * 2.0
	var shoji_height := SHOJI_TOP - SHOJI_BOTTOM
	for side in 4:
		# Wainscot, shoji band and plaster, back to front.
		_batch(mat_cedar, Vector3(length, SHOJI_BOTTOM - FLOOR_TOP, 0.08), _wall(side, HALL - 0.04, 0, (SHOJI_BOTTOM + FLOOR_TOP) / 2.0))
		_batch(mat_plaster, Vector3(length, CEILING - SHOJI_TOP, 0.08), _wall(side, HALL - 0.04, 0, (CEILING + SHOJI_TOP) / 2.0))
		var kamiza := side == 2
		for bay in int(length / BAY):
			var along := -HALL + (bay + 0.5) * BAY
			if kamiza and absf(along) < BAY:
				continue # the alcove takes the middle two bays
			_shoji_bay(side, along)
		# Pillars and horizontal timbers (sill, lintel, top).
		for i in int(length / BAY) + 1:
			if kamiza and i * BAY == HALL:
				continue # keep the alcove (and its scroll) clear
			_batch(mat_dark_wood, Vector3(PILLAR, CEILING - FLOOR_TOP, PILLAR), _wall(side, HALL - PILLAR / 2.0, -HALL + i * BAY, (CEILING + FLOOR_TOP) / 2.0))
		for y in [SHOJI_BOTTOM, SHOJI_TOP, CEILING - 0.1]:
			_batch(mat_dark_wood, Vector3(length, 0.14, 0.16), _wall(side, HALL - 0.1, 0, y))
		_batch(mat_dark_wood, Vector3(length, 0.12, 0.05), _wall(side, HALL - 0.03, 0, FLOOR_TOP + 0.06)) # skirting


## One shoji bay: glowing paper behind a dark lattice of thin bars.
func _shoji_bay(side: int, along: float) -> void:
	var width := BAY - PILLAR
	var height := SHOJI_TOP - SHOJI_BOTTOM
	var mid := (SHOJI_TOP + SHOJI_BOTTOM) / 2.0
	_batch(mat_paper, Vector3(width, height, 0.02), _wall(side, HALL - 0.09, along, mid))
	var columns := 5
	for c in range(1, columns):
		_batch(mat_dark_wood, Vector3(0.03, height, 0.03), _wall(side, HALL - 0.11, along - width / 2.0 + c * width / columns, mid))
	var rows := 6
	for r in range(1, rows):
		_batch(mat_dark_wood, Vector3(width, 0.03, 0.03), _wall(side, HALL - 0.11, along, SHOJI_BOTTOM + r * height / rows))
	# The frame between two sliding panels.
	_batch(mat_dark_wood, Vector3(0.06, height, 0.05), _wall(side, HALL - 0.12, along, mid))


## Kamiza: the raised shrine alcove at the back (-Z) with a hanging scroll, a small
## kamidana shelf, and paper floor lamps either side.
func _build_kamiza() -> void:
	var side := 2
	var width := BAY * 2.0 - PILLAR
	var mid := (SHOJI_TOP + SHOJI_BOTTOM) / 2.0
	_batch(mat_lacquer, Vector3(width, SHOJI_TOP - SHOJI_BOTTOM, 0.04), _wall(side, HALL - 0.1, 0, mid))
	_batch(mat_cedar, Vector3(width, 0.3, 0.9), _wall(side, HALL - 0.55, 0, FLOOR_TOP + 0.15))
	_batch(mat_dark_wood, Vector3(width + 0.1, 0.06, 0.95), _wall(side, HALL - 0.55, 0, FLOOR_TOP + 0.31))
	# Hanging scroll with 道 ("the way") and a red seal.
	_batch(mat_scroll, Vector3(0.95, 2.1, 0.012), _wall(side, HALL - 0.14, 0, 2.3))
	for y in [3.37, 1.23]:
		_batch(mat_dark_wood, Vector3(1.1, 0.05, 0.05), _wall(side, HALL - 0.15, 0, y))
	var kanji := _label("道", 600, Color(0.05, 0.04, 0.03))
	kanji.transform = _wall(side, HALL - 0.16, 0, 2.45) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	_add(stage, kanji, "ScrollKanji")
	var seal := _label("武", 110, Color(0.75, 0.1, 0.08))
	seal.transform = _wall(side, HALL - 0.16, -0.25, 1.55) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	_add(stage, seal, "ScrollSeal")
	# Kamidana shelf with a tiny shrine.
	_batch(mat_dark_wood, Vector3(1.8, 0.07, 0.45), _wall(side, HALL - 0.3, 0, 4.1))
	_batch(mat_hinoki, Vector3(0.6, 0.4, 0.3), _wall(side, HALL - 0.28, 0, 4.34))
	_batch(mat_dark_wood, Vector3(0.75, 0.06, 0.4), _wall(side, HALL - 0.28, 0, 4.57))
	for x in [-0.6, 0.6]:
		_batch(mat_scroll, Vector3(0.12, 0.22, 0.12), _wall(side, HALL - 0.3, x, 4.25))
	# Floor lamps (andon) either side of the alcove.
	for x in [-3.2, 3.2]:
		_batch(mat_paper, Vector3(0.34, 0.7, 0.34), _wall(side, HALL - 0.9, x, 0.75))
		for leg in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
			_batch(mat_dark_wood, Vector3(0.04, 1.1, 0.04), _wall(side, HALL - 0.9 + leg.y * 0.18, x + leg.x * 0.18, FLOOR_TOP + 0.55))
		var lamp := OmniLight3D.new()
		lamp.transform = _wall(side, HALL - 0.9, x, 0.8)
		lamp.light_color = PAPER_GLOW
		lamp.light_energy = 1.2
		lamp.omni_range = 3.5
		_add(stage, lamp, "Andon%s" % ("L" if x < 0 else "R"))


# --- Props -----------------------------------------------------------------------

func _build_props() -> void:
	# Taiko drum on its stand beside the kamiza.
	var drum_at := _wall(2, HALL - 1.4, 5.2, 1.0)
	var drum := _cylinder(0.45, 0.62, mat_drum)
	drum.transform = drum_at * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
	_add(stage, drum, "TaikoDrum")
	for z in [-0.32, 0.32]:
		var skin := _cylinder(0.46, 0.03, mat_skin)
		skin.transform = drum_at * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, z))
		_add(stage, skin, "TaikoSkin%d" % (1 if z < 0 else 2))
	for x in [-0.4, 0.4]:
		_batch(mat_dark_wood, Vector3(0.08, 1.0, 0.08), drum_at * Transform3D(Basis(Vector3(0, 0, 1), x * 0.5), Vector3(x, -0.5, 0)))
	_batch(mat_dark_wood, Vector3(0.9, 0.06, 0.5), drum_at * Transform3D(Basis(), Vector3(0, -1.0, 0)))

	# Weapon racks with bokken and staffs on the side walls.
	for side in [1, 3]:
		for along in [-5.0, 5.0]:
			_weapon_rack(side, along)
		_name_board(side, 0.0)
	_name_board(0, 0.0)


func _weapon_rack(side: int, along: float) -> void:
	var base := _wall(side, HALL - 0.45, along, 0)
	_batch(mat_dark_wood, Vector3(1.9, 0.08, 0.35), base * Transform3D(Basis(), Vector3(0, 0.08, 0)))
	_batch(mat_dark_wood, Vector3(1.9, 0.08, 0.12), base * Transform3D(Basis(), Vector3(0, 1.3, 0.08)))
	for x in [-0.9, 0.9]:
		_batch(mat_dark_wood, Vector3(0.08, 1.45, 0.12), base * Transform3D(Basis(), Vector3(x, 0.72, 0.08)))
	for i in 8:
		var x := -0.75 + i * 0.21
		var staff := i % 3 == 2
		var length := 1.85 if staff else 1.0
		var material := mat_dark_wood if staff else mat_hinoki
		var lean := Basis(Vector3.RIGHT, -0.12)
		_batch(material, Vector3(0.035, length, 0.035), base * Transform3D(lean, Vector3(x, 0.12 + length / 2.0, 0.02)))


## Nafudakake: a board of members' name tags on the plaster above the shoji.
func _name_board(side: int, along: float) -> void:
	var board := _wall(side, HALL - 0.1, along, 4.6)
	_batch(mat_dark_wood, Vector3(3.4, 1.0, 0.05), board)
	for row in 3:
		for i in 22:
			_batch(mat_tag, Vector3(0.09, 0.26, 0.015), board * Transform3D(Basis(), Vector3(-1.53 + i * 0.146, 0.3 - row * 0.3, -0.035)))


# --- Ceiling & lanterns ----------------------------------------------------------

func _build_ceiling() -> void:
	_batch(mat_cedar, Vector3(HALL * 2.0, 0.08, HALL * 2.0), Transform3D(Basis(), Vector3(0, CEILING + 0.04, 0)))
	var count := int(HALL * 2.0 / BAY) + 1
	for i in count:
		var p := -HALL + i * BAY
		_batch(mat_dark_wood, Vector3(HALL * 2.0, 0.32, 0.26), Transform3D(Basis(), Vector3(0, CEILING - 0.16, p)))
	for x in [-HALL + BAY, HALL - BAY]:
		_batch(mat_dark_wood, Vector3(0.3, 0.36, HALL * 2.0), Transform3D(Basis(), Vector3(x, CEILING - 0.5, 0)))
	# Paper lanterns (chochin) hanging over the corners of the tatami.
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var pos := Vector3(x * 4.6, 4.5, z * 4.6)
			var body := _cylinder(0.26, 0.62, mat_lantern)
			body.position = pos
			_add(stage, body, "Lantern%d%d" % [int(x > 0), int(z > 0)])
			for cap_y in [0.33, -0.33]:
				_batch(mat_black, Vector3(0.36, 0.06, 0.36), Transform3D(Basis(), pos + Vector3(0, cap_y, 0)))
			_batch(mat_black, Vector3(0.015, CEILING - pos.y - 0.35, 0.015), Transform3D(Basis(), pos + Vector3(0, (CEILING - pos.y) / 2.0 + 0.17, 0)))
			var glow := OmniLight3D.new()
			glow.position = pos
			glow.light_color = Color(1.0, 0.55, 0.3)
			glow.light_energy = 1.4
			glow.omni_range = 5.0
			_add(stage, glow, "LanternLight%d%d" % [int(x > 0), int(z > 0)])


# --- Students -----------------------------------------------------------------------

## Students in white gi (a few in dark hakama) kneeling along the side walls and the
## front. One Crowd node per side so a side can hide when the camera is behind it
## (Stage occlusion groups: 0 = -Z, 1 = +Z, 2 = -X, 3 = +X).
func _build_students() -> void:
	var groups := {0: 1, 1: 3, 3: 2} # crowd side -> Stage occlusion group
	for side: int in groups:
		var students := MultiMeshInstance3D.new()
		students.set_script(load(CROWD_SCRIPT))
		students.set("rows", 2)
		students.set("tier_start", 6.6)
		students.set("tier_depth", 0.85)
		students.set("tier_rise", 0.0)
		students.set("row_width", 12.0)
		students.set("seat_spacing", 0.8)
		students.set("floor_y", FLOOR_TOP)
		students.set("empty_seat_chance", 0.3)
		students.set("crowd_seed", 77 + side)
		students.set("sides", PackedInt32Array([side]))
		students.set("kneeling", true)
		students.set("sway", 0.004) # breathing
		students.set("palette", PackedColorArray([Color(1, 1, 1), Color(0.95, 0.95, 1.0), Color(1.0, 0.97, 0.93)]))
		_add(stage, students, "Students%d" % side)
		students.add_to_group(&"ring_side_%d" % groups[side], true)


# --- Atmosphere -----------------------------------------------------------------

## Dust drifting through the light over the tatami, candle flicker in the hanging
## lanterns and the andon, and a thread of incense smoke rising at the kamiza.
func _build_atmosphere() -> void:
	var dust := StageFX.motes(Vector3(4.5, 2.4, 4.5), 220)
	dust.position = Vector3(0, 3.0, 0)
	_add(stage, dust, "Dust")
	var flicker := Node.new()
	flicker.set_script(load(FLICKER_SCRIPT))
	_add(stage, flicker, "CandleFlicker")
	var lights: Array[NodePath] = [NodePath("../AndonL"), NodePath("../AndonR")]
	for x in [0, 1]:
		for z in [0, 1]:
			lights.append(NodePath("../LanternLight%d%d" % [x, z]))
	flicker.set("lights", lights)
	flicker.set("amount", 0.12)
	# Incense: a small holder on the alcove dais, smoke curling up toward the scroll.
	var holder := _wall(2, HALL - 0.5, 0.75, FLOOR_TOP + 0.4)
	_batch(mat_dark_wood, Vector3(0.12, 0.08, 0.12), holder)
	var smoke := StageFX.smoke()
	smoke.transform = holder * Transform3D(Basis(), Vector3(0, 0.12, 0))
	_add(stage, smoke, "IncenseSmoke")


## Baked contact shadows on the hall floor (StageAO): the merged geometry is recorded as
## it's batched, separate meshes (drum, lanterns) are collected here.
func _bake_contact_shadows() -> void:
	StageAO.collect(_footprints, stage, FLOOR_TOP, ["Geometry"])
	var image := StageAO.bake(_footprints, Vector2.ZERO, Vector2(HALL, HALL), 256)
	_add(stage, StageAO.overlay(StageAO.save(image, AO_PATH), Vector2.ZERO, Vector2(HALL, HALL), FLOOR_TOP), "FloorShadows")
	print("baked contact shadows from %d footprints" % _footprints.size())


# --- Helpers ---------------------------------------------------------------------

## Adds a box to the merged mesh for `material`.
func _batch(material: Material, size: Vector3, xform: Transform3D) -> void:
	StageAO.add_box(_footprints, xform, size, FLOOR_TOP)
	var st: SurfaceTool = _batches.get(material)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[material] = st
	var box := BoxMesh.new()
	box.size = size
	st.append_from(box, 0, xform)


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


func _cylinder(radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


## Poly Haven PBR set (diff / nor_gl / rough), tinted, triplanar-tiled `tiling` per meter.
func _textured(texture_name: String, tint: Color, tiling: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = load(TEX + texture_name + "_diff_1k.jpg")
	m.normal_enabled = true
	m.normal_texture = load(TEX + texture_name + "_nor_gl_1k.jpg")
	m.roughness_texture = load(TEX + texture_name + "_rough_1k.jpg")
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


func _label(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.0018
	label.modulate = color
	label.outline_size = 0
	label.shaded = true
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label
