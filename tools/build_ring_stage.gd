extends SceneTree
## Builds the boxing ring stage (res://scenes/stages/ring.tscn): ring, arena, crowd,
## lighting truss, and environment. Re-run after changing anything below.
##
## Atmosphere: a restless crowd (Crowd sway/jump), dust in the beams and camera flashes
## in the stands (StageFX), and baked contact shadows on the canvas and floor (StageAO).
##
## Run: godot_console --headless --path . -s res://tools/build_ring_stage.gd
##
## Layout: canvas top at y = 0 (fighters stand on it), canvas 9 m square with corner
## posts at ±4.4 m, ring platform 1 m tall, arena floor at y = -1.

const OUTPUT := "res://scenes/stages/ring.tscn"
const TEX := "res://assets/stages/ring/textures/"
const HDRI := "res://assets/stages/ring/basement_boxing_ring_1k.hdr"
const STAGE_SCRIPT := "res://scripts/stages/stage.gd"
const CROWD_SCRIPT := "res://scripts/stages/crowd.gd"
const AO_DIR := "res://assets/stages/ring/"

const CANVAS_HALF := 4.5
const POST_OFFSET := 4.4
const PLATFORM_HEIGHT := 1.0
const FLOOR_Y := -PLATFORM_HEIGHT
const ROPE_HEIGHTS := [0.45, 0.85, 1.25]
const ROPE_COLORS := [Color(0.1, 0.2, 0.75), Color(0.92, 0.92, 0.92), Color(0.75, 0.08, 0.08)]
const RED_CORNER := Color(0.75, 0.08, 0.08)
const BLUE_CORNER := Color(0.1, 0.2, 0.75)
const NEUTRAL_CORNER := Color(0.85, 0.85, 0.85)
const BRAND_NAVY := Color(0.06, 0.08, 0.2)

var stage: Node3D


func _initialize() -> void:
	stage = Node3D.new()
	stage.name = "Ring"
	stage.set_script(load(STAGE_SCRIPT))

	_build_environment()
	_build_lights()
	_build_ring()
	_build_arena()
	_build_crowd()
	_build_atmosphere()
	_add(stage, StageFX.ambience([["res://assets/audio/ambience/arena_crowd.ogg", -10.0]], "res://assets/audio/ambience/crowd_cheer.ogg", -4.0), "Sound") # ambient loops (StageAmbience)
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


# --- Environment & lighting ------------------------------------------------------

func _build_environment() -> void:
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load(HDRI)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	# The HDRI was shot inside a ring, so it only lights the scene; the visible
	# background is a dark arena void.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.016, 0.025)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.2
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.adjustment_enabled = true # a little punch for the arena lights
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.08
	# SSAO costs ~25% frame time on integrated GPUs for little visible gain here.
	env.ssao_enabled = false
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.009 # enough haze for the beams to read
	env.volumetric_fog_albedo = Color(0.9, 0.9, 1.0)
	env.volumetric_fog_length = 40.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_add(stage, world_env, "WorldEnvironment")


func _build_lights() -> void:
	var lights := _add(stage, Node3D.new(), "Lights")
	# Key light straight down over the ring, with shadows.
	var key := SpotLight3D.new()
	key.position = Vector3(0, 9, 0)
	key.rotation_degrees = Vector3(-90, 0, 0)
	key.light_energy = 14.0
	key.spot_range = 14.0
	key.spot_angle = 38.0
	key.spot_attenuation = 0.6
	key.light_color = Color(1.0, 0.97, 0.9)
	key.shadow_enabled = true
	key.light_volumetric_fog_energy = 1.5
	_add(lights, key, "KeyLight")
	# Four angled truss spots from the corners for modelling and rim light.
	var corner := 0
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			corner += 1
			var spot := SpotLight3D.new()
			var pos := Vector3(x * 6.0, 7.5, z * 6.0)
			spot.transform = Transform3D(Basis.looking_at(Vector3(0, 0.8, 0) - pos), pos)
			_add(lights, spot, "TrussSpot%d" % corner)
			spot.light_energy = 6.0
			spot.spot_range = 16.0
			spot.spot_angle = 24.0
			spot.light_color = Color(0.85, 0.9, 1.0)
			spot.light_volumetric_fog_energy = 2.0
			spot.shadow_enabled = corner == 1
	# Dim cool fill so the crowd and arena don't fall to pure black.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 40, 0)
	fill.light_energy = 0.15
	fill.light_color = Color(0.6, 0.7, 1.0)
	_add(lights, fill, "ArenaFill")

	# Lighting truss (visual only).
	var truss_mat := _material(Color(0.12, 0.12, 0.13), 0.4, 0.8)
	var truss := _add(stage, Node3D.new(), "Truss")
	for i in 4:
		var beam := _box(Vector3(12.4, 0.3, 0.3), truss_mat)
		var along_x := i < 2
		var side := -6.2 if i % 2 == 0 else 6.2
		beam.position = Vector3(0, 7.8, side) if along_x else Vector3(side, 7.8, 0)
		if not along_x:
			beam.rotation_degrees.y = 90.0
		_add(truss, beam, "Beam%d" % i)


# --- Ring ------------------------------------------------------------------------

func _build_ring() -> void:
	var ring := _add(stage, Node3D.new(), "BoxingRing")

	var canvas_mat := _textured("terlenka", Color(0.82, 0.85, 0.9), 6.0)
	var canvas := _box(Vector3(CANVAS_HALF * 2, 0.12, CANVAS_HALF * 2), canvas_mat)
	canvas.position.y = -0.06
	_add(ring, canvas, "Canvas")

	# Center logo: a disc and the game's name printed on the canvas.
	var disc_mat := _material(Color(BRAND_NAVY, 0.85), 0.0, 0.7)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 1.7
	disc_mesh.bottom_radius = 1.7
	disc_mesh.height = 0.004
	disc_mesh.radial_segments = 64
	disc_mesh.material = disc_mat
	disc.mesh = disc_mesh
	disc.position.y = 0.002
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(ring, disc, "LogoDisc")
	var logo := _label("3D FIGHTER", 150, Color(0.95, 0.75, 0.2))
	logo.position.y = 0.006
	logo.rotation_degrees.x = -90.0
	_add(ring, logo, "LogoText")

	# Apron skirt with branding on all four sides.
	var apron_mat := _textured("fabric_leather_02", BRAND_NAVY, 3.0)
	var apron := _box(Vector3(CANVAS_HALF * 2 + 0.3, PLATFORM_HEIGHT - 0.12, CANVAS_HALF * 2 + 0.3), apron_mat)
	apron.position.y = FLOOR_Y + (PLATFORM_HEIGHT - 0.12) / 2.0
	_add(ring, apron, "Apron")
	for i in 4:
		var banner := _label("3D FIGHTER", 110, Color(0.95, 0.75, 0.2))
		var angle := i * PI / 2.0
		var out := Vector3(sin(angle), 0, cos(angle))
		banner.position = out * (CANVAS_HALF + 0.16) + Vector3.UP * (FLOOR_Y + 0.5)
		banner.rotation.y = angle
		_add(ring, banner, "ApronBanner%d" % i)

	var collision := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CANVAS_HALF * 2, PLATFORM_HEIGHT, CANVAS_HALF * 2)
	shape.shape = box
	collision.position.y = FLOOR_Y / 2.0
	_add(ring, collision, "Collision")
	_add(collision, shape, "Shape")

	# Corner posts with padded turnbuckle covers.
	var post_mat := _material(Color(0.55, 0.56, 0.6), 0.9, 0.3)
	var corner_colors := {Vector2(-1, -1): RED_CORNER, Vector2(1, 1): BLUE_CORNER}
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var corner := Node3D.new()
			corner.position = Vector3(x * POST_OFFSET, 0, z * POST_OFFSET)
			_add(ring, corner, "Corner_%s%s" % ["E" if x > 0 else "W", "S" if z > 0 else "N"])
			var post := _cylinder(0.07, 1.65, post_mat)
			post.position.y = 0.78
			_add(corner, post, "Post")
			var pad_color: Color = corner_colors.get(Vector2(x, z), NEUTRAL_CORNER)
			var pad := _box(Vector3(0.26, 1.05, 0.26), _textured("fabric_leather_02", pad_color, 1.0))
			pad.position.y = 0.85
			_add(corner, pad, "Pad")

	# Ropes: three levels, round, slightly glossy.
	var span := POST_OFFSET * 2.0
	for level in ROPE_HEIGHTS.size():
		var rope_mat := _material(ROPE_COLORS[level], 0.0, 0.35)
		for side in 4:
			var rope := _cylinder(0.028, span, rope_mat)
			var along_x := side < 2
			var offset := -POST_OFFSET if side % 2 == 0 else POST_OFFSET
			rope.position = Vector3(0, ROPE_HEIGHTS[level], offset) if along_x else Vector3(offset, ROPE_HEIGHTS[level], 0)
			rope.rotation_degrees = Vector3(0, 0, 90) if along_x else Vector3(90, 0, 0)
			_add(ring, rope, "Rope_%d_%d" % [level, side])
			rope.add_to_group(&"ring_side_%d" % side, true)

	# Steps at the red and blue corners.
	var step_mat := _material(Color(0.1, 0.1, 0.12), 0.2, 0.6)
	for corner_sign in [-1.0, 1.0]:
		for i in 3:
			var h := PLATFORM_HEIGHT * (i + 1) / 4.0
			var step := _box(Vector3(1.2, h, 0.35), step_mat)
			step.position = Vector3(corner_sign * (CANVAS_HALF + 0.35 + (2 - i) * 0.35), FLOOR_Y + h / 2.0, corner_sign * (CANVAS_HALF - 0.7))
			step.rotation_degrees.y = 90.0
			_add(ring, step, "Step_%s_%d" % ["red" if corner_sign < 0 else "blue", i])


# --- Arena -----------------------------------------------------------------------

func _build_arena() -> void:
	var arena := _add(stage, Node3D.new(), "Arena")
	var floor_mat := _textured("concrete_floor_worn_001", Color(0.35, 0.35, 0.38), 18.0)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(80, 80)
	floor_mesh.material = floor_mat
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	floor_mi.position.y = FLOOR_Y
	_add(arena, floor_mi, "Floor")

	# Barricade around the ringside area.
	var barrier_mat := _material(Color(0.05, 0.05, 0.06), 0.1, 0.5)
	var barrier_dist := 8.0
	for i in 4:
		var along_x := i < 2
		var side := -barrier_dist if i % 2 == 0 else barrier_dist
		var wall := _box(Vector3(barrier_dist * 2, 1.1, 0.15), barrier_mat)
		wall.position = Vector3(0, FLOOR_Y + 0.55, side) if along_x else Vector3(side, FLOOR_Y + 0.55, 0)
		if not along_x:
			wall.rotation_degrees.y = 90.0
		_add(arena, wall, "Barricade%d" % i)
		var strip := _box(Vector3(barrier_dist * 2, 0.06, 0.02), _emissive(Color(0.95, 0.6, 0.15), 2.0))
		strip.position = wall.position + Vector3.UP * 0.45 + (Vector3(0, 0, -0.085 * signf(side)) if along_x else Vector3(-0.085 * signf(side), 0, 0))
		strip.rotation_degrees = wall.rotation_degrees
		_add(arena, strip, "LedStrip%d" % i)

	# Tiered seating on all four sides.
	var tier_mat := _material(Color(0.08, 0.08, 0.1), 0.0, 0.9)
	for side in 4:
		for row in CROWD_ROWS:
			var tier := _box(Vector3(TIER_WIDTH, TIER_RISE * (row + 1), TIER_DEPTH), tier_mat)
			var dist := TIER_START + row * TIER_DEPTH
			tier.position = _side_point(side, dist, 0.0) + Vector3.UP * (FLOOR_Y + TIER_RISE * (row + 1) / 2.0)
			tier.rotation.y = side * PI / 2.0
			_add(arena, tier, "Tier_%d_%d" % [side, row])


const CROWD_ROWS := 9
const TIER_START := 9.5
const TIER_DEPTH := 0.9
const TIER_RISE := 0.45
const TIER_WIDTH := 24.0
const SEAT_SPACING := 0.62


## Point on side `side` (0..3 around the ring) at distance `dist`, offset `along` it.
func _side_point(side: int, dist: float, along: float) -> Vector3:
	var angle := side * PI / 2.0
	var out := Vector3(sin(angle), 0, cos(angle))
	var tangent := Vector3(cos(angle), 0, -sin(angle))
	return out * dist + tangent * along


func _build_crowd() -> void:
	# Spectators are generated at runtime by crowd.gd (MultiMesh instance data isn't kept
	# when built headless); these settings must match the tiers above.
	var crowd := MultiMeshInstance3D.new()
	crowd.set_script(load(CROWD_SCRIPT))
	crowd.set("rows", CROWD_ROWS)
	crowd.set("tier_start", TIER_START)
	crowd.set("tier_depth", TIER_DEPTH)
	crowd.set("tier_rise", TIER_RISE)
	crowd.set("row_width", TIER_WIDTH)
	crowd.set("seat_spacing", SEAT_SPACING)
	crowd.set("floor_y", FLOOR_Y)
	crowd.set("sway", 0.02) # restless, and now and then someone jumps up
	crowd.set("jump", 0.16)
	_add(stage, crowd, "Crowd")


## Dust drifting through the spotlight beams over the ring, and camera flashes popping
## around the stands (StageFX).
func _build_atmosphere() -> void:
	var dust := StageFX.motes(Vector3(5.5, 3.0, 5.5), 260)
	dust.position = Vector3(0, 3.5, 0)
	_add(stage, dust, "Dust")
	var flashes := StageFX.flashes(TIER_START + 0.5, TIER_START + CROWD_ROWS * TIER_DEPTH, CROWD_ROWS * TIER_RISE, 8)
	flashes.position = Vector3(0, FLOOR_Y + CROWD_ROWS * TIER_RISE * 0.5 + 0.6, 0)
	_add(stage, flashes, "CameraFlashes")


## Baked contact shadows (StageAO): on the canvas around the posts, and on the arena
## floor around the ring platform, its steps, the barricades and the first tiers.
func _bake_contact_shadows() -> void:
	var on_canvas := []
	StageAO.collect(on_canvas, stage, 0.0)
	var canvas_ao := StageAO.save(StageAO.bake(on_canvas, Vector2.ZERO, Vector2(CANVAS_HALF, CANVAS_HALF), 128), AO_DIR + "canvas_ao.res")
	_add(stage, StageAO.overlay(canvas_ao, Vector2.ZERO, Vector2(CANVAS_HALF, CANVAS_HALF), 0.0), "CanvasShadows")
	var on_floor := []
	StageAO.collect(on_floor, stage, FLOOR_Y, ["Floor"])
	var floor_ao := StageAO.save(StageAO.bake(on_floor, Vector2.ZERO, Vector2(12.5, 12.5), 256), AO_DIR + "arena_ao.res")
	_add(stage, StageAO.overlay(floor_ao, Vector2.ZERO, Vector2(12.5, 12.5), FLOOR_Y), "ArenaShadows")
	print("baked contact shadows: %d on the canvas, %d on the floor" % [on_canvas.size(), on_floor.size()])


# --- Helpers ---------------------------------------------------------------------

func _add(parent: Node, node: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = stage
	return node


func _marker(pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.position = pos
	return m


func _box(size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _cylinder(radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
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


## Poly Haven PBR set (diff / nor_gl / rough), tinted and tiled.
func _textured(texture_name: String, tint: Color, tiling: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = load(TEX + texture_name + "_diff_1k.jpg")
	m.normal_enabled = true
	m.normal_texture = load(TEX + texture_name + "_nor_gl_1k.jpg")
	m.roughness_texture = load(TEX + texture_name + "_rough_1k.jpg")
	m.uv1_scale = Vector3(tiling, tiling, tiling)
	m.uv1_triplanar = true
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
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 0
	label.shaded = true
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label
