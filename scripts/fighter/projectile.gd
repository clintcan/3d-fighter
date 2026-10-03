class_name Projectile
extends Node3D
## A fireball-style projectile. Simulation state is plain fields ticked by FightManager
## at 60 Hz (move → hit check), so it stays deterministic; the glowing orb, light and
## trail are cosmetic. Flies straight along the owner's facing at launch, so a sidestep
## can dodge it. One per fighter at a time (Fighter.projectile).

const SPAWN_OFFSET := Vector3(0.0, 1.25, -0.75) # fighter-local, -Z = toward the opponent
## How close (m, along its path) it must be to count as a threat for blocking.
const THREAT_DISTANCE := 1.6

var owner_fighter: Fighter
var move: MoveData
var direction := Vector3.FORWARD
var speed := 0.0
var ticks_left := 0
var radius := 0.3

var _mesh: MeshInstance3D
var _light: OmniLight3D
var _trail: GPUParticles3D
var _age := 0.0


func setup(fighter: Fighter, projectile_move: MoveData) -> void:
	owner_fighter = fighter
	move = projectile_move
	direction = fighter.forward
	speed = projectile_move.projectile_speed
	ticks_left = projectile_move.projectile_lifetime
	radius = projectile_move.hitbox_radius
	position = fighter.global_transform * SPAWN_OFFSET
	name = "Projectile"


func _ready() -> void:
	var color := move.projectile_color
	# White-hot core inside two additive glow shells.
	_mesh = _sphere(radius * 0.45, Color(1.0, 1.0, 1.0), false)
	_mesh.add_child(_sphere(radius * 0.75, Color(color.lightened(0.3), 0.55), true))
	_mesh.add_child(_sphere(radius * 1.15, Color(color, 0.25), true))
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 2.5
	_light.omni_range = 2.5
	add_child(_light)

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.ZERO
	process.spread = 180.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.4
	process.gravity = Vector3.ZERO
	process.scale_min = 0.5
	process.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(color.lightened(0.4), 0.9))
	fade.set_color(1, Color(color, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 1.2
	var quad_material := StandardMaterial3D.new()
	quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad_material.vertex_color_use_as_albedo = true
	quad.material = quad_material
	_trail = GPUParticles3D.new()
	_trail.process_material = process
	_trail.draw_pass_1 = quad
	_trail.amount = 40
	_trail.lifetime = 0.35
	_trail.local_coords = false
	add_child(_trail)
	reset_physics_interpolation()


func _sphere(r: float, color: Color, additive: bool) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if additive:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


## One simulation tick. Returns false when it has expired (FightManager removes it).
func tick(bounds_half_extent: float) -> bool:
	position += direction * speed * Fighter.DT
	ticks_left -= 1
	var limit := bounds_half_extent + 0.5
	return ticks_left > 0 and absf(position.x) <= limit and absf(position.z) <= limit


## Approaching `target` and close enough that they should be blocking.
func is_threatening(target: Fighter) -> bool:
	var to_target := target.position - position
	to_target.y = 0.0
	return to_target.dot(direction) > -0.2 and to_target.length() <= THREAT_DISTANCE + radius


func _process(delta: float) -> void:
	_age += delta
	if _mesh:
		var pulse := 1.0 + 0.12 * sin(_age * 30.0)
		# Slightly stretched along its flight.
		_mesh.basis = Basis.looking_at(direction) * Basis.from_scale(Vector3(1.0, 1.0, 1.3) * pulse)
		_light.light_energy = 2.5 * pulse
