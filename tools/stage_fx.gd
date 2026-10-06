class_name StageFX
## Ambient particle effects for the stage builders: dust motes, camera flashes, embers,
## flames and sea spray. Each returns a ready GPUParticles3D for the builder to place.
## All of it is cosmetic: GPU particles never touch the simulation.


## Dust drifting in the air. Shaded, so it only shows where it crosses a light beam.
static func motes(extents: Vector3, amount: int, color := Color(1.0, 0.95, 0.85, 0.5)) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3(0.3, 0.2, 0.1)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.08
	process.gravity = Vector3(0, -0.01, 0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.4
	process.turbulence_noise_speed_random = 0.3
	process.turbulence_influence_min = 0.02
	process.turbulence_influence_max = 0.06
	process.scale_min = 0.5
	process.scale_max = 1.2
	process.color_ramp = _fade(color, 0.2, 0.8)
	var material := _billboard(false)
	material.disable_ambient_light = true # visible only where a light actually hits it
	return _particles(_quad(0.018, material), process, amount, 9.0, extents)


## Camera flashes in the stands: brief white pops spread around a ring of seating.
static func flashes(inner: float, outer: float, height: float, amount: int, lifetime := 2.0) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = outer
	process.emission_ring_inner_radius = inner
	process.emission_ring_height = height
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	var ramp := Gradient.new() # bright for the first few percent of the life, then nothing
	ramp.offsets = PackedFloat32Array([0.0, 0.03, 0.06, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0), Color(1, 1, 1, 0)])
	var texture := GradientTexture1D.new()
	texture.gradient = ramp
	process.color_ramp = texture
	var material := _billboard(true)
	material.albedo_color = Color(2.5, 2.5, 2.8)
	var p := _particles(_quad(0.22, material), process, amount, lifetime, Vector3(outer, height, outer))
	p.randomness = 1.0
	return p


## Embers rising from a fire and fading: orange sparks on a lazy, turbulent climb.
static func embers(extents: Vector3, amount: int, lifetime := 3.0) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 0.8
	process.gravity = Vector3(0, 0.15, 0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.2
	process.turbulence_influence_min = 0.05
	process.turbulence_influence_max = 0.15
	process.scale_min = 0.5
	process.scale_max = 1.0
	process.color_ramp = _fade(Color(1.0, 0.55, 0.15, 1.0), 0.05, 0.7)
	var material := _billboard(true)
	material.albedo_color = Color(3.0, 1.6, 0.6)
	return _particles(_quad(0.03, material), process, amount, lifetime, extents + Vector3(1, 3, 1))


## A small flame (torch, lantern): bright yellow-orange tongues licking upward.
static func flame(size := 0.2, amount := 24) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = size * 0.25
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = size * 2.0
	process.initial_velocity_max = size * 3.5
	process.gravity = Vector3(0, size * 2.0, 0)
	process.scale_min = 0.7
	process.scale_max = 1.2
	var curve := Curve.new() # tongues shrink as they rise
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var scale := CurveTexture.new()
	scale.curve = curve
	process.scale_curve = scale
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.95, 0.6, 1), Color(1.0, 0.65, 0.2, 0.9), Color(0.9, 0.25, 0.05, 0.5), Color(0.3, 0.05, 0.0, 0)])
	var texture := GradientTexture1D.new()
	texture.gradient = ramp
	process.color_ramp = texture
	var material := _billboard(true)
	material.albedo_color = Color(2.2, 1.6, 1.0)
	var p := _particles(_quad(size * 0.6, material, true), process, amount, 0.45, Vector3.ONE * size * 3.0)
	return p


## A thin wisp of smoke (incense): grey puffs rising slowly, swelling and fading.
static func smoke(amount := 40, lifetime := 4.0) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.01
	process.direction = Vector3.UP
	process.spread = 6.0
	process.initial_velocity_min = 0.12
	process.initial_velocity_max = 0.2
	process.gravity = Vector3(0, 0.02, 0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.turbulence_noise_scale = 3.0
	process.turbulence_influence_min = 0.02
	process.turbulence_influence_max = 0.05
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(1.0, 1.0))
	var scale := CurveTexture.new()
	scale.curve = curve
	process.scale_curve = scale
	process.color_ramp = _fade(Color(0.85, 0.85, 0.88, 0.3), 0.1, 0.5)
	return _particles(_quad(0.14, _billboard(false)), process, amount, lifetime, Vector3(0.6, 1.2, 0.6))


## Sea spray: soft white mist drifting along the shore on the wind.
static func spray(extents: Vector3, amount: int, wind := Vector3(0.6, 0.15, 0.0)) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = wind.normalized()
	process.spread = 30.0
	process.initial_velocity_min = wind.length() * 0.6
	process.initial_velocity_max = wind.length() * 1.4
	process.gravity = Vector3(0, -0.05, 0)
	process.scale_min = 0.6
	process.scale_max = 1.6
	process.color_ramp = _fade(Color(1, 1, 1, 0.22), 0.25, 0.6)
	var material := _billboard(false)
	material.disable_receive_shadows = true
	return _particles(_quad(0.6, material, true), process, amount, 5.0, extents + Vector3(4, 2, 2))


# --- Helpers ------------------------------------------------------------------------

static func _particles(mesh: Mesh, process: ParticleProcessMaterial, amount: int, lifetime: float, reach: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime # already going when the stage appears
	p.process_material = process
	p.draw_pass_1 = mesh
	p.visibility_aabb = AABB(-reach * 1.5, reach * 3.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Billboarded particle material: additive and unshaded (glows), or shaded alpha (lit
## only where light reaches it). Colours come from the particle colour ramp.
static func _billboard(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	if additive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


## A quad with a soft round falloff (a radial gradient texture), so particles aren't squares.
static func _quad(size: float, material: StandardMaterial3D, soft := true) -> QuadMesh:
	if soft:
		var falloff := Gradient.new()
		falloff.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
		var texture := GradientTexture2D.new()
		texture.gradient = falloff
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 32
		texture.height = 32
		material.albedo_texture = texture
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	return quad


## Colour ramp: fades in over `fade_in` of the life, holds, fades out from `fade_out`.
static func _fade(color: Color, fade_in: float, fade_out: float) -> GradientTexture1D:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, fade_in, fade_out, 1.0])
	ramp.colors = PackedColorArray([Color(color, 0.0), color, color, Color(color, 0.0)])
	var texture := GradientTexture1D.new()
	texture.gradient = ramp
	return texture


## A stage's ambient sound (StageAmbience): `loops` as [[path, volume dB], ...], an
## optional crowd reaction, and optional one-shots (`sprinkles` paths) every few seconds.
static func ambience(loops: Array, reaction := "", reaction_volume := -6.0, sprinkles: Array = [], sprinkle_volume := -14.0) -> Node:
	var node := Node.new()
	node.set_script(load("res://scripts/stages/stage_ambience.gd"))
	var streams: Array[AudioStream] = []
	var volumes := PackedFloat32Array()
	for loop: Array in loops:
		streams.append(load(loop[0]))
		volumes.append(loop[1])
	node.set("loops", streams)
	node.set("loop_volumes", volumes)
	if reaction != "":
		node.set("reaction", load(reaction))
		node.set("reaction_volume", reaction_volume)
	var shots: Array[AudioStream] = []
	for path: String in sprinkles:
		shots.append(load(path))
	node.set("sprinkles", shots)
	node.set("sprinkle_volume", sprinkle_volume)
	return node
