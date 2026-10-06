extends SceneTree
## Builds the night market stage (res://scenes/stages/market.tscn): a Manila side street
## at dusk, Mira's home turf. The fight is in the middle of the street; behind it a row
## of food stalls with tarp awnings sits on the sidewalk in front of two- and three-storey
## shophouses (shutters, lit shopfronts, balconies, aircon units, hand-painted signs).
## Wooden electric poles carry a tangle of wires, and banderitas (fiesta bunting) and
## string lights cross overhead. A jeepney is parked at the back right, another down the
## street on the left (modelled by tools/build_jeepney.gd), and locals watch from both ends.
## Re-run after changing anything below.
##
## Run: godot_console --headless --path . -s res://tools/build_market_stage.gd
##
## Layout: street (asphalt) top at y = 0, running along X; the sidewalk behind the fight
## (z -6.4 .. -9.6) is 15 cm up; the shophouse fronts are at z = -9.6. Nothing stands
## between the camera (+Z) and the fight. Repeated geometry is merged into one mesh per
## material.
## Atmosphere: grill smoke and sparks, a flickering "BUKAS 24 ORAS" sign (NeonAmbience),
## wavering grill light (FireFlicker), a lively crowd, and baked contact shadows (StageAO).

const OUTPUT := "res://scenes/stages/market.tscn"
const TEX := "res://assets/stages/market/textures/"
const SKY := "res://assets/stages/market/qwantani_dusk_2_puresky_2k.hdr"
const STAGE_SCRIPT := "res://scripts/stages/stage.gd"
const CROWD_SCRIPT := "res://scripts/stages/crowd.gd"
const AMBIENCE_SCRIPT := "res://scripts/stages/neon_ambience.gd"
const FLICKER_SCRIPT := "res://scripts/stages/fire_flicker.gd"
const AO_PATH := "res://assets/stages/market/street_ao.res"
const JEEPNEY := "res://assets/stages/market/jeepney.res" # tools/build_jeepney.gd

const CURB_Z := -6.4 # street edge (sidewalk starts here)
const FRONT_Z := -9.6 # shophouse fronts
const SIDEWALK_TOP := 0.15
const WARM := Color(1.0, 0.78, 0.5)
const SODIUM := Color(1.0, 0.72, 0.42)
const NEON_RED := Color(1.0, 0.15, 0.2)
const NEON_GREEN := Color(0.25, 1.0, 0.45)

var stage: Node3D
var _batches := {}
var _footprints := [] # everything standing on the street (contact shadows)
var _rng := RandomNumberGenerator.new()
var mat_asphalt: StandardMaterial3D
var mat_sidewalk: StandardMaterial3D
var mat_curb: StandardMaterial3D
var mat_paint_white: StandardMaterial3D
var mat_paint_yellow: StandardMaterial3D
var mat_shutter: StandardMaterial3D
var mat_iron: StandardMaterial3D
var mat_wood: StandardMaterial3D
var mat_dark: StandardMaterial3D
var mat_metal: StandardMaterial3D
var mat_chrome: StandardMaterial3D
var mat_glass: StandardMaterial3D
var mat_tire: StandardMaterial3D
var mat_window_lit: StandardMaterial3D
var mat_window_dark: StandardMaterial3D
var mat_shop_lit: StandardMaterial3D
var mat_bulb: StandardMaterial3D
var mat_coals: StandardMaterial3D
var mat_headlight: StandardMaterial3D
var mat_wire: StandardMaterial3D
var mat_pole: StandardMaterial3D
var _plaster := [] # pastel shophouse walls
var _tarps := [] # stall awnings and fiesta colours
var _food := []


func _initialize() -> void:
	_rng.seed = 1571 # the year Manila was founded as a Spanish city
	stage = Node3D.new()
	stage.name = "Market"
	stage.set_script(load(STAGE_SCRIPT))
	stage.set("rope_line", 50.0) # nothing sits between the camera and the fight
	stage.set("music", &"market")

	_make_materials()
	_build_environment()
	_build_lights()
	_build_street()
	_build_shophouses()
	_build_stalls()
	_build_jeepney(Transform3D(Basis(Vector3.UP, PI + 0.1), Vector3(10.6, 0, -4.9)), "QUIAPO • CUBAO", 0)
	_build_jeepney(Transform3D(Basis(Vector3.UP, 0.05), Vector3(-15.5, 0, -3.6)), "DIVISORIA • STA. MESA", 1)
	_build_poles_and_wires()
	_build_banderitas()
	_build_crowd()
	_build_atmosphere()
	_add(stage, StageFX.ambience([["res://assets/audio/ambience/market_chatter.ogg", -12.0], ["res://assets/audio/ambience/city_traffic.ogg", -25.0], ["res://assets/audio/ambience/fire_crackle.ogg", -19.0]], "res://assets/audio/ambience/crowd_cheer.ogg", -6.0), "Sound") # ambient loops (StageAmbience)
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
	mat_asphalt = _textured("asphalt_02", Color(0.55, 0.53, 0.55), 0.3)
	mat_sidewalk = _textured("brick_pavement", Color(0.8, 0.72, 0.66), 0.5)
	mat_curb = _material(Color(0.55, 0.55, 0.53), 0.0, 0.85)
	mat_paint_white = _material(Color(0.82, 0.82, 0.78), 0.0, 0.75)
	mat_paint_yellow = _material(Color(0.92, 0.72, 0.15), 0.0, 0.75)
	mat_shutter = _textured("painted_metal_shutter", Color(0.75, 0.78, 0.8), 0.5)
	mat_iron = _textured("rusty_corrugated_iron", Color(0.9, 0.85, 0.8), 0.5)
	mat_wood = _textured("wood_planks", Color(0.85, 0.7, 0.55), 0.8)
	mat_dark = _material(Color(0.08, 0.07, 0.07), 0.0, 0.8)
	mat_metal = _material(Color(0.5, 0.52, 0.55), 0.6, 0.45)
	mat_chrome = _material(Color(0.85, 0.86, 0.88), 1.0, 0.18)
	mat_glass = _material(Color(0.05, 0.07, 0.09), 0.2, 0.08)
	mat_tire = _material(Color(0.05, 0.05, 0.05), 0.0, 0.9)
	mat_window_lit = _emissive(Color(1.0, 0.8, 0.55), 1.6)
	mat_window_dark = _material(Color(0.08, 0.1, 0.14), 0.3, 0.2)
	mat_shop_lit = _emissive(Color(1.0, 0.92, 0.75), 1.3)
	mat_bulb = _emissive(Color(1.0, 0.8, 0.45), 4.0)
	mat_coals = _emissive(Color(1.0, 0.35, 0.08), 3.0)
	mat_headlight = _emissive(Color(1.0, 0.95, 0.8), 2.5)
	mat_wire = _material(Color(0.03, 0.03, 0.03), 0.0, 0.8)
	mat_pole = _textured("wood_planks", Color(0.45, 0.36, 0.28), 1.5)
	for c in [Color(0.95, 0.82, 0.6), Color(0.7, 0.85, 0.82), Color(0.92, 0.72, 0.72), Color(0.82, 0.86, 0.95),
			Color(0.98, 0.93, 0.78), Color(0.78, 0.9, 0.7)]:
		var m := _textured("painted_plaster_wall", c, 0.5)
		_plaster.append(m)
	for c in [Color(0.85, 0.12, 0.12), Color(0.12, 0.35, 0.8), Color(0.95, 0.75, 0.1), Color(0.15, 0.6, 0.3),
			Color(0.95, 0.45, 0.1), Color(0.9, 0.9, 0.88)]:
		var m := _material(c, 0.0, 0.8)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tarps.append(m)
	for c in [Color(0.55, 0.25, 0.1), Color(0.85, 0.6, 0.25), Color(0.95, 0.85, 0.6), Color(0.6, 0.15, 0.4), Color(0.3, 0.5, 0.2)]:
		_food.append(_material(c, 0.0, 0.6))


# --- Environment & lighting ------------------------------------------------------

func _build_environment() -> void:
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load(SKY)
	sky_material.energy_multiplier = 0.22 # late dusk: the stalls and signs carry the light
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(200.0), 0) # the last of the sunset glow behind the shophouses
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.06
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.06
	env.ssao_enabled = false # too costly on integrated GPUs (see the stage notes)
	env.volumetric_fog_enabled = true # grill smoke and warm haze for the lamp beams
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.95, 0.85, 0.75)
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_add(stage, world_env, "WorldEnvironment")


func _build_lights() -> void:
	var lights := _add(stage, Node3D.new(), "Lights")
	# Cool dusk skylight from behind the shophouses (no shadows: the sky is soft).
	var dusk := DirectionalLight3D.new()
	dusk.rotation_degrees = Vector3(-25, 160, 0)
	dusk.light_energy = 0.22
	dusk.light_color = Color(0.7, 0.72, 1.0)
	_add(lights, dusk, "DuskLight")
	# Sodium street lamp on the pole at the back, its arm reaching over the fight.
	var lamp_at := Vector3(0.6, 6.0, -3.6)
	_batch(mat_metal, Vector3(0.08, 0.08, 3.3), Transform3D(Basis(), Vector3(0.6, 6.05, -5.2)))
	_batch(mat_bulb, Vector3(0.5, 0.12, 0.3), Transform3D(Basis(), lamp_at + Vector3(0, -0.05, 0)))
	var street := SpotLight3D.new()
	street.transform = Transform3D(Basis.looking_at(Vector3(0, 0.6, 0.8) - lamp_at), lamp_at)
	street.light_energy = 9.0
	street.spot_range = 13.0
	street.spot_angle = 48.0
	street.spot_attenuation = 0.7
	street.light_color = SODIUM
	street.shadow_enabled = true
	street.light_volumetric_fog_energy = 1.6
	_add(lights, street, "StreetLamp")
	# A cooler fill from the front so faces don't go orange-black.
	var fill := SpotLight3D.new()
	var fill_at := Vector3(-2.5, 5.0, 7.0)
	fill.transform = Transform3D(Basis.looking_at(Vector3(0, 1.0, 0) - fill_at), fill_at)
	fill.light_energy = 2.5
	fill.spot_range = 14.0
	fill.spot_angle = 35.0
	fill.light_color = Color(0.75, 0.8, 1.0)
	fill.light_volumetric_fog_energy = 0.0
	_add(lights, fill, "FrontFill")


# --- Street ----------------------------------------------------------------------

func _build_street() -> void:
	_batch(mat_asphalt, Vector3(70, 0.2, 40), Transform3D(Basis(), Vector3(0, -0.1, CURB_Z + 20.0)))
	# Sidewalk (raised) and curb along the back.
	var depth := CURB_Z - FRONT_Z + 0.6
	_batch(mat_sidewalk, Vector3(70, SIDEWALK_TOP + 0.1, depth), Transform3D(Basis(), Vector3(0, (SIDEWALK_TOP - 0.1) / 2.0, (CURB_Z + FRONT_Z - 0.6) / 2.0)))
	_batch(mat_curb, Vector3(70, SIDEWALK_TOP + 0.02, 0.16), Transform3D(Basis(), Vector3(0, SIDEWALK_TOP / 2.0, CURB_Z + 0.08)))
	# Faded road paint: a double yellow line behind the fight, a zebra crossing off to
	# the left, and a manhole cover.
	for dz in [-0.08, 0.08]:
		for i in range(-16, 16):
			_batch(mat_paint_yellow, Vector3(1.6, 0.006, 0.09), Transform3D(Basis(), Vector3(i * 2.2, 0.003, -4.4 + dz)))
	for i in 8:
		_batch(mat_paint_white, Vector3(2.4, 0.006, 0.4), Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-6.8 + (i % 2) * 0.0, 0.003, -5.6 + i * 0.85)) * Transform3D(Basis(), Vector3.ZERO))
	var manhole := CylinderMesh.new()
	manhole.top_radius = 0.38
	manhole.bottom_radius = 0.38
	manhole.height = 0.01
	manhole.radial_segments = 20
	_append(_material(Color(0.12, 0.12, 0.13), 0.5, 0.6), manhole, Transform3D(Basis(), Vector3(3.3, 0.004, 1.6)))


# --- Shophouses ------------------------------------------------------------------

const SHOP_SIGNS := ["KARINDERYA", "SARI-SARI STORE", "BOTIKA", "PANCITERIA", "VULCANIZING", "BIGASAN", "PAWNSHOP", "BAKERY"]

## A row of narrow shophouses: ground floor shutters or lit shopfronts with a painted
## sign, upper floors with windows, a balcony with a railing, aircon units, a parapet.
func _build_shophouses() -> void:
	var x := -22.0
	var index := 0
	while x < 22.0:
		var width := _rng.randf_range(3.6, 5.2)
		var floors := 2 + int(_rng.randf() < 0.55)
		var height := 3.4 + floors * 2.8
		var center := x + width / 2.0
		var wall: Material = _plaster[_rng.randi() % _plaster.size()]
		var at := Vector3(center, 0, FRONT_Z)
		_batch(wall, Vector3(width - 0.05, height, 6.0), Transform3D(Basis(), at + Vector3(0, height / 2.0, -3.0)))
		_batch(mat_curb, Vector3(width + 0.05, 0.3, 0.3), Transform3D(Basis(), at + Vector3(0, height + 0.15, 0)))
		# Ground floor: a shutter, or an open lit shop.
		var shop_width := width - 0.8
		if _rng.randf() < 0.45:
			_batch(mat_shutter, Vector3(shop_width, 2.7, 0.06), Transform3D(Basis(), at + Vector3(0, SIDEWALK_TOP + 1.35, 0.02)))
		else:
			_batch(mat_shop_lit, Vector3(shop_width, 2.6, 0.05), Transform3D(Basis(), at + Vector3(0, SIDEWALK_TOP + 1.3, -0.4)))
			_batch(wall, Vector3(0.3, 2.7, 0.45), Transform3D(Basis(), at + Vector3(-shop_width / 2.0 + 0.1, SIDEWALK_TOP + 1.35, -0.2)))
			_batch(wall, Vector3(0.3, 2.7, 0.45), Transform3D(Basis(), at + Vector3(shop_width / 2.0 - 0.1, SIDEWALK_TOP + 1.35, -0.2)))
		# Sign board over the shopfront.
		var sign_color: Material = _tarps[(index + 2) % _tarps.size()]
		_batch(sign_color, Vector3(shop_width, 0.6, 0.08), Transform3D(Basis(), at + Vector3(0, 3.3, 0.06)))
		var text: String = SHOP_SIGNS[index % SHOP_SIGNS.size()]
		var sign := _label(text, 110, Color(1, 1, 1) if index % 3 != 2 else Color(0.1, 0.08, 0.06))
		sign.position = at + Vector3(0, 3.3, 0.11)
		sign.pixel_size = 0.0028
		_add(stage, sign, "ShopSign%d" % index)
		# Upper floors: windows (some lit), a balcony on the first one, aircon units.
		for f in floors:
			var y := 3.4 + f * 2.8 + 1.3
			var panes := maxi(1, int(width / 1.6))
			for p in panes:
				var px := center - width / 2.0 + (p + 0.5) * width / panes
				var lit := _rng.randf() < 0.45
				_batch(mat_window_lit if lit else mat_window_dark, Vector3(0.9, 1.25, 0.05), Transform3D(Basis(), Vector3(px, y, FRONT_Z + 0.02)))
				_batch(mat_dark, Vector3(1.05, 0.08, 0.12), Transform3D(Basis(), Vector3(px, y - 0.68, FRONT_Z + 0.05)))
				if _rng.randf() < 0.3:
					_batch(mat_metal, Vector3(0.7, 0.45, 0.5), Transform3D(Basis(), Vector3(px, y - 0.95, FRONT_Z + 0.25)))
			if f == 0:
				_batch(mat_curb, Vector3(width - 0.3, 0.12, 1.0), Transform3D(Basis(), at + Vector3(0, 3.55, 0.5)))
				_batch(mat_dark, Vector3(width - 0.3, 0.05, 0.05), Transform3D(Basis(), at + Vector3(0, 4.45, 0.98)))
				for r in int(width / 0.25):
					_batch(mat_dark, Vector3(0.025, 0.85, 0.025), Transform3D(Basis(), at + Vector3(-width / 2.0 + 0.3 + r * 0.25, 4.02, 0.98)))
				if _rng.randf() < 0.5: # laundry on the balcony
					for k in 4:
						var cloth: Material = _tarps[_rng.randi() % _tarps.size()]
						_batch(cloth, Vector3(0.38, 0.5, 0.02), Transform3D(Basis(), at + Vector3(-0.9 + k * 0.6, 4.2, 0.75)))
		# Corrugated iron roof showing over the parapet.
		_batch(mat_iron, Vector3(width, 0.06, 6.2), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8.0)), at + Vector3(0, height + 0.45, -3.0)))
		x += width
		index += 1


# --- Food stalls -----------------------------------------------------------------

const STALLS := [
	[-7.0, "IHAW-IHAW", "grill"], [-3.6, "ISAW • BBQ • BETAMAX", "grill"], [0.2, "TURON • BANANA CUE", "fruit"],
	[3.6, "HALO-HALO", "dessert"], [11.5, "BALUT • PENOY", "eggs"], [-11.0, "KWEK-KWEK", "fry"],
]

## Stalls on the sidewalk: a wooden counter on legs, a tarp awning on poles, a bulb,
## food on the counter and a hand-lettered sign; grill stalls have glowing coals.
func _build_stalls() -> void:
	var grill_lights: Array[NodePath] = []
	for i in STALLS.size():
		var spec: Array = STALLS[i]
		var at := Vector3(spec[0], SIDEWALK_TOP, CURB_Z - 1.1)
		var tarp: Material = _tarps[i % _tarps.size()]
		_batch(mat_wood, Vector3(2.2, 0.08, 0.8), Transform3D(Basis(), at + Vector3(0, 0.95, 0)))
		_batch(mat_wood, Vector3(2.2, 0.85, 0.05), Transform3D(Basis(), at + Vector3(0, 0.5, 0.38)))
		for lx in [-1.0, 1.0]:
			for lz in [-0.35, 0.35]:
				_batch(mat_wood, Vector3(0.06, 0.95, 0.06), Transform3D(Basis(), at + Vector3(lx, 0.47, lz)))
			_batch(mat_metal, Vector3(0.05, 2.3, 0.05), Transform3D(Basis(), at + Vector3(lx * 1.15, 1.15, 0.6)))
			_batch(mat_metal, Vector3(0.05, 2.6, 0.05), Transform3D(Basis(), at + Vector3(lx * 1.15, 1.3, -0.55)))
		# Awning: sloping down toward the street.
		_batch(tarp, Vector3(2.6, 0.03, 1.6), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), at + Vector3(0, 2.45, 0.05)))
		_batch(tarp, Vector3(2.6, 0.25, 0.02), Transform3D(Basis(), at + Vector3(0, 2.18, 0.84)))
		# Sign hanging from the awning.
		var sign := _label(spec[1], 90, Color(1.0, 0.95, 0.85))
		sign.position = at + Vector3(0, 2.18, 0.86)
		sign.pixel_size = 0.0024
		sign.outline_size = 10
		sign.outline_modulate = Color(0.1, 0.05, 0.02)
		_add(stage, sign, "StallSign%d" % i)
		# Bulb and its light.
		_batch(mat_bulb, Vector3(0.09, 0.12, 0.09), Transform3D(Basis(), at + Vector3(0, 2.1, 0.1)))
		var bulb := OmniLight3D.new()
		bulb.position = at + Vector3(0, 1.95, 0.25)
		bulb.light_color = WARM
		bulb.light_energy = 1.4
		bulb.omni_range = 4.5
		bulb.light_volumetric_fog_energy = 0.6
		_add(stage, bulb, "StallLight%d" % i)
		# Food on the counter.
		match spec[2]:
			"grill":
				_batch(mat_dark, Vector3(1.3, 0.12, 0.5), Transform3D(Basis(), at + Vector3(0, 1.05, 0)))
				_batch(mat_coals, Vector3(1.2, 0.03, 0.42), Transform3D(Basis(), at + Vector3(0, 1.1, 0)))
				for s in 9: # skewers on the grill
					_batch(_food[s % 2], Vector3(0.05, 0.05, 0.4), Transform3D(Basis(), at + Vector3(-0.55 + s * 0.14, 1.16, 0)))
				grill_lights.append(NodePath("../StallLight%d" % i))
				var smoke := StageFX.smoke(30, 3.5)
				smoke.position = at + Vector3(0, 1.2, 0)
				smoke.scale = Vector3.ONE * 2.5
				_add(stage, smoke, "GrillSmoke%d" % i)
				var sparks := StageFX.embers(Vector3(0.5, 0.02, 0.15), 10, 1.4)
				sparks.position = at + Vector3(0, 1.15, 0)
				_add(stage, sparks, "GrillSparks%d" % i)
			_:
				for f in 7:
					var item: Material = _food[(f + i) % _food.size()]
					var size := Vector3(0.18, 0.12, 0.18) if spec[2] != "eggs" else Vector3(0.1, 0.12, 0.1)
					_batch(item, size, Transform3D(Basis(Vector3.UP, f * 0.6), at + Vector3(-0.8 + f * 0.27, 1.05, -0.05 + (f % 2) * 0.12)))
				_batch(mat_metal, Vector3(0.35, 0.25, 0.35), Transform3D(Basis(), at + Vector3(0.75, 1.12, -0.2)))
		# A plastic stool or two out front: a round seat on four splayed legs.
		for k in 2:
			var stool: Material = _tarps[(i + k + 3) % _tarps.size()]
			var spot := at + Vector3(-0.6 + k * 1.1, 0.0, 0.75)
			var seat := CylinderMesh.new()
			seat.top_radius = 0.16
			seat.bottom_radius = 0.15
			seat.height = 0.04
			seat.radial_segments = 12
			_append(stool, seat, Transform3D(Basis(), spot + Vector3(0, 0.42, 0)))
			for leg in 4:
				var a := leg * PI / 2.0 + k * 0.4
				_batch(stool, Vector3(0.035, 0.42, 0.035), Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.12), spot + Vector3(cos(a) * 0.12, 0.21, sin(a) * 0.12)))
	var flicker := Node.new()
	flicker.set_script(load(FLICKER_SCRIPT))
	_add(stage, flicker, "GrillFlicker")
	flicker.set("lights", grill_lights)
	flicker.set("amount", 0.2)


# --- Jeepneys --------------------------------------------------------------------

## A jeepney (the mesh from tools/build_jeepney.gd), painted through its named surfaces,
## with its route lit on the roof board and a name painted on each side. Front toward
## local +X.
func _build_jeepney(xform: Transform3D, route: String, index: int) -> void:
	var schemes := [
		{body = _material(Color(0.82, 0.84, 0.87), 0.85, 0.22), paint = _material(Color(0.1, 0.25, 0.7), 0.1, 0.35),
			accent = _material(Color(0.9, 0.15, 0.12), 0.0, 0.5), accent2 = _material(Color(0.95, 0.75, 0.1), 0.0, 0.5), name = "MIRA'S PRIDE"},
		{body = _material(Color(0.85, 0.16, 0.13), 0.2, 0.3), paint = _material(Color(0.95, 0.82, 0.18), 0.1, 0.35),
			accent = _material(Color(0.12, 0.3, 0.75), 0.0, 0.5), accent2 = _material(Color(0.95, 0.95, 0.92), 0.0, 0.5), name = "GOD BLESS OUR TRIP"},
	]
	var scheme: Dictionary = schemes[index]
	var shared := {chrome = mat_chrome, glass = mat_glass, interior = mat_dark, seat = _material(Color(0.6, 0.08, 0.08), 0.0, 0.4),
		tire = mat_tire, light = mat_headlight, taillight = _emissive(Color(1.0, 0.1, 0.05), 2.0)}
	var jeep := MeshInstance3D.new()
	jeep.mesh = load(JEEPNEY)
	jeep.transform = xform
	_add(stage, jeep, "Jeepney%d" % index)
	for s in jeep.mesh.get_surface_count():
		var surface: String = jeep.mesh.surface_get_name(s)
		jeep.set_surface_override_material(s, scheme.get(surface, shared.get(surface)))
	var label := _label(route, 80, Color(1.0, 0.92, 0.5))
	label.transform = xform * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(1.09, 2.43, 0))
	label.pixel_size = 0.0022
	label.modulate = Color(2.2, 2.0, 1.0)
	label.shaded = false
	_add(stage, label, "JeepneyRoute%d" % index)
	for side in [-1.0, 1.0]: # its name in looping script along the stainless side
		var name_label := _label(scheme.name, 96, Color(0.95, 0.2, 0.15) if index == 0 else Color(1.0, 0.95, 0.4))
		name_label.transform = xform * Transform3D(Basis(Vector3.UP, 0.0 if side > 0 else PI), Vector3(-0.8, 1.28, side * 0.945))
		name_label.pixel_size = 0.0026
		name_label.outline_size = 10
		name_label.outline_modulate = Color(0.05, 0.05, 0.1)
		_add(stage, name_label, "JeepneyName%d%s" % [index, "R" if side > 0 else "L"])


# --- Poles, wires, banderitas ------------------------------------------------------

const POLES := [Vector3(-9.5, 0, -6.9), Vector3(-2.2, 0, -6.9), Vector3(5.5, 0, -6.9), Vector3(14.0, 0, -6.9)]

## Wooden electric poles with crossarms and transformers, joined by sagging wires and
## a tangle of drop lines into the shophouses.
func _build_poles_and_wires() -> void:
	for pole: Vector3 in POLES:
		_batch(mat_pole, Vector3(0.22, 8.0, 0.22), Transform3D(Basis(), pole + Vector3(0, 4.0, 0)))
		_batch(mat_pole, Vector3(1.6, 0.12, 0.12), Transform3D(Basis(), pole + Vector3(0, 7.4, 0)))
		if int(pole.x) % 2 == 0:
			var can := CylinderMesh.new()
			can.top_radius = 0.24
			can.bottom_radius = 0.24
			can.height = 0.7
			can.radial_segments = 12
			_append(mat_metal, can, Transform3D(Basis(), pole + Vector3(0.3, 6.6, 0.15)))
	for i in POLES.size() - 1:
		for k in 3:
			var a: Vector3 = POLES[i] + Vector3(-0.7 + k * 0.7, 7.45, 0)
			var b: Vector3 = POLES[i + 1] + Vector3(-0.7 + k * 0.7, 7.45, 0)
			_wire(a, b, 0.55 + k * 0.1)
	for pole: Vector3 in POLES: # drop lines into the buildings
		for k in 3:
			var a := pole + Vector3(-0.5 + k * 0.5, 7.4, 0)
			var b := Vector3(pole.x + _rng.randf_range(-2.0, 2.0), _rng.randf_range(5.0, 6.5), FRONT_Z + 0.05)
			_wire(a, b, 0.35)


## Banderitas: strings of small triangular flags in fiesta colours zig-zagging over the
## street, with string lights between them.
func _build_banderitas() -> void:
	var strands := [[Vector3(-10.0, 5.6, FRONT_Z + 0.1), Vector3(-5.0, 4.8, -1.5)], [Vector3(-5.0, 4.8, -1.5), Vector3(1.0, 5.6, FRONT_Z + 0.1)],
		[Vector3(1.0, 5.6, FRONT_Z + 0.1), Vector3(6.0, 4.8, -1.5)], [Vector3(6.0, 4.8, -1.5), Vector3(11.0, 5.6, FRONT_Z + 0.1)],
		[Vector3(-5.0, 4.8, -1.5), Vector3(6.0, 4.8, -1.5)]]
	for side_pole in [Vector3(-5.0, 0, -1.5), Vector3(6.0, 0, -1.5)]: # the strands' far ends hang off thin poles
		_batch(mat_metal, Vector3(0.06, 4.9, 0.06), Transform3D(Basis(), side_pole + Vector3(0, 2.45, 0)))
	var flag := PrismMesh.new()
	flag.size = Vector3(0.26, 0.3, 0.004)
	for s in strands.size():
		var a: Vector3 = strands[s][0]
		var b: Vector3 = strands[s][1]
		_wire(a, b, 0.6, mat_wire, 0.008)
		var count := int(a.distance_to(b) / 0.32)
		for i in range(1, count):
			var t := float(i) / count
			var p := a.lerp(b, t) + Vector3.DOWN * sin(t * PI) * 0.6
			var along := (b - a).normalized()
			var basis := Basis.looking_at(Vector3.UP.cross(along).normalized(), Vector3.UP) * Basis(Vector3.BACK, PI)
			if s == strands.size() - 1 and i % 2 == 0:
				_batch(mat_bulb, Vector3(0.07, 0.09, 0.07), Transform3D(Basis(), p + Vector3.DOWN * 0.06))
			else:
				var cloth: Material = _tarps[i % _tarps.size()]
				_append(cloth, flag, Transform3D(basis, p + Vector3.DOWN * 0.16))


## A sagging wire from a to b made of short straight pieces.
func _wire(a: Vector3, b: Vector3, sag: float, material: Material = null, thickness := 0.018) -> void:
	material = material if material else mat_wire
	var pieces := 10
	var previous := a
	for i in range(1, pieces + 1):
		var t := float(i) / pieces
		var p := a.lerp(b, t) + Vector3.DOWN * sin(t * PI) * sag
		var mid := (previous + p) / 2.0
		var dir := p - previous
		if dir.length() > 0.001:
			var basis := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
			_batch(material, Vector3(thickness, thickness, dir.length()), Transform3D(basis, mid))
		previous = p


# --- Crowd, atmosphere, shadows ----------------------------------------------------

## Locals watching from both ends of the street.
func _build_crowd() -> void:
	var crowd := MultiMeshInstance3D.new()
	crowd.set_script(load(CROWD_SCRIPT))
	crowd.set("rows", 3)
	crowd.set("tier_start", 7.4)
	crowd.set("tier_depth", 0.8)
	crowd.set("tier_rise", 0.0)
	crowd.set("row_width", 10.0)
	crowd.set("seat_spacing", 0.7)
	crowd.set("floor_y", -0.15)
	crowd.set("empty_seat_chance", 0.35)
	crowd.set("crowd_seed", 1898) # Philippine independence
	crowd.set("sides", PackedInt32Array([1, 3]))
	crowd.set("palette", PackedColorArray([Color(0.9, 0.9, 0.88), Color(0.85, 0.2, 0.2), Color(0.15, 0.3, 0.7),
		Color(0.95, 0.75, 0.15), Color(0.2, 0.2, 0.22), Color(0.3, 0.6, 0.35), Color(0.6, 0.4, 0.7)]))
	crowd.set("sway", 0.025)
	crowd.set("jump", 0.18)
	_add(stage, crowd, "Crowd")


## A "BUKAS 24 ORAS" (open 24 hours) neon over the sari-sari store that flickers, and a
## green pharmacy cross that hums (NeonAmbience).
func _build_atmosphere() -> void:
	var open_sign := _neon("BUKAS 24 ORAS", 120, NEON_RED)
	open_sign.position = Vector3(-6.1, 4.85, FRONT_Z + 1.1) # in front of the balconies
	_add(stage, open_sign, "NeonOpen")
	var cross := _neon("✚", 260, NEON_GREEN)
	cross.position = Vector3(2.9, 5.0, FRONT_Z + 1.1)
	_add(stage, cross, "NeonCross")
	var glow := OmniLight3D.new()
	glow.position = Vector3(-6.1, 4.8, FRONT_Z + 1.8)
	glow.light_color = NEON_RED
	glow.light_energy = 1.2
	glow.omni_range = 5.0
	_add(stage, glow, "NeonGlow")
	var ambience := Node.new()
	ambience.set_script(load(AMBIENCE_SCRIPT))
	_add(stage, ambience, "Ambience")
	var flicker_labels: Array[NodePath] = [NodePath("../NeonOpen")]
	var flicker_lights: Array[NodePath] = [NodePath("../NeonGlow")]
	var hum_labels: Array[NodePath] = [NodePath("../NeonCross")]
	ambience.set("flicker_labels", flicker_labels)
	ambience.set("flicker_lights", flicker_lights)
	ambience.set("hum_labels", hum_labels)


## Baked contact shadows on the street (StageAO): the curb, stalls, jeepneys and poles.
func _bake_contact_shadows() -> void:
	StageAO.collect(_footprints, stage, 0.0, ["Geometry"])
	var half := Vector2(16.0, 10.0)
	var center := Vector2(0.0, -2.0)
	var image := StageAO.bake(_footprints, center, half, 256)
	_add(stage, StageAO.overlay(StageAO.save(image, AO_PATH), center, half, 0.0), "StreetShadows")
	print("baked contact shadows from %d footprints" % _footprints.size())


# --- Helpers ---------------------------------------------------------------------

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


## Glowing neon lettering facing +Z. HDR modulate drives the glow.
func _neon(text: String, font_size: int, color: Color) -> Label3D:
	var label := _label(text, font_size, Color(color.r * 3.0, color.g * 3.0, color.b * 3.0))
	label.pixel_size = 0.004
	label.outline_size = 16
	label.outline_modulate = Color(color.r, color.g, color.b, 0.35)
	label.shaded = false
	return label
