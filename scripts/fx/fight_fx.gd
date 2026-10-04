class_name FightFx
extends Node3D
## Hit sparks, impact flashes, model hit-flash, knockdown dust and fight sounds, driven
## by FightManager / Fighter signals. Purely cosmetic: reads gameplay, never writes it.
## Special moves add: fighter shouts (special / super / K.O.), motion trails while a
## travelling move is active, sparks along rising and flurry attacks, a ground-pound
## shockwave, projectile launch and impact bursts, and a big burst on super finishers.

const HEAVY_HITSTOP := 8 # moves with at least this much hitstop count as heavy
const SPARK_POOL := 8
const DUST_POOL := 3

const HIT_COLOR := Color(1.0, 0.75, 0.35)
const COUNTER_COLOR := Color(1.0, 0.35, 0.15)
const BLOCK_COLOR := Color(0.45, 0.75, 1.0)
const SUPER_COLOR := Color(1.0, 0.82, 0.3)
const TRAIL_COLOR := Color(0.8, 0.9, 1.0)
const DEBRIS_COLOR := Color(0.55, 0.45, 0.35)

var manager: Node
## Total effects spawned (lets tests confirm hits produce effects).
var spawned := 0

var _sparks: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _next_spark := 0
var _next_dust := 0
var _flash_texture: Texture2D
## Per fighter: continuous emitters toggled each frame while a special is active.
var _trails := {} # Fighter -> GPUParticles3D (streaks behind travelling moves)
var _strike_sparks := {} # Fighter -> GPUParticles3D (sparks along rising/flurry hits)


func setup(fight_manager: Node) -> void:
	manager = fight_manager
	_flash_texture = _make_radial_texture()
	for i in SPARK_POOL:
		_sparks.append(_make_sparks())
	for i in DUST_POOL:
		_dust.append(_make_dust())
	# All effects are cosmetic: manager.cosmetic() skips them during rollback re-simulation.
	manager.hit_landed.connect(manager.cosmetic(_on_hit_landed))
	manager.super_flash.connect(manager.cosmetic(_on_super_flash))
	manager.projectile_clashed.connect(manager.cosmetic(func(point: Vector3) -> void:
		spark(point, SUPER_COLOR, 1.4)
		Audio.sfx(&"hit_heavy", 0.0, 1.2)))
	manager.throw_landed.connect(manager.cosmetic(func(_a: Fighter, _d: Fighter) -> void: Audio.sfx(&"block", -4.0, 0.8)))
	for fighter: Fighter in manager.fighters:
		fighter.attack_started.connect(manager.cosmetic(_on_attack_started.bind(fighter)))
		fighter.move_active.connect(manager.cosmetic(_on_move_active))
		fighter.knocked_out.connect(manager.cosmetic(func(f: Fighter) -> void: Audio.shout(f.data.id, "ko")))
		fighter.combo_changed.connect(manager.cosmetic(func(hits: int) -> void:
			if hits == 5:
				Audio.voice("combo")))
		_trails[fighter] = _make_trail()
		_strike_sparks[fighter] = _make_strike_sparks()
		fighter.landed_hard.connect(manager.cosmetic(_on_landed_hard))
		fighter.throw_impact.connect(manager.cosmetic(_on_throw_impact))


func _on_hit_landed(attacker: Fighter, defender: Fighter, move: MoveData, result: Fighter.HitResult) -> void:
	var point: Vector3 = manager.last_hit_point
	var heavy := move.hitstop >= HEAVY_HITSTOP
	if result != Fighter.HitResult.BLOCKED:
		if move.projectile_speed > 0.0:
			spark(point, move.projectile_color, 2.0) # energy burst
			_ring(point, move.projectile_color, 1.6, false)
		elif move.input.begins_with("~"): # super finisher
			spark(point, SUPER_COLOR, 2.4)
			_ring(point, SUPER_COLOR, 2.2, false)
			manager.camera.shake(0.45)
	match result:
		Fighter.HitResult.BLOCKED:
			spark(point, BLOCK_COLOR, 0.6)
			Audio.sfx(&"block", -2.0)
			if defender.model:
				defender.model.flash(BLOCK_COLOR, 0.12)
		Fighter.HitResult.COUNTER:
			spark(point, COUNTER_COLOR, 1.6)
			Audio.sfx(&"hit_heavy", 2.0, 0.9)
			if defender.model:
				defender.model.flash(COUNTER_COLOR, 0.2)
		_:
			spark(point, HIT_COLOR, 1.3 if heavy else 0.85)
			Audio.sfx(&"hit_heavy" if heavy else &"hit_light", 0.0 if heavy else -2.0)
			if defender.model:
				defender.model.flash(Color.WHITE, 0.16 if heavy else 0.1)


func _on_attack_started(move: MoveData, fighter: Fighter) -> void:
	if move.projectile_speed > 0.0:
		Audio.sfx(&"energy", -4.0)
	elif not move.super_move: # the super flash has its own sound
		Audio.sfx(&"swing_heavy" if move.hitstop >= HEAVY_HITSTOP else &"swing_light", -8.0)
	if move.is_special() and not move.super_move:
		Audio.shout(fighter.data.id, "special")


## First active frame: launch flash, rising burst, or ground-pound shockwave.
func _on_move_active(fighter: Fighter, move: MoveData) -> void:
	if move.projectile_speed > 0.0:
		spark(fighter.global_transform * Projectile.SPAWN_OFFSET, move.projectile_color, 1.0)
	if move.rise > 0.0:
		spark(fighter.global_transform * move.hitbox_offset, SUPER_COLOR if move.input.begins_with("~") else HIT_COLOR, 1.2)
	if move.impact_fx == &"shockwave":
		var point := fighter.global_position + fighter.forward * absf(move.hitbox_offset.z)
		point.y = 0.02
		_ring(point, Color(0.95, 0.85, 0.7), 3.4, true)
		dust(point)
		_debris(point)
		Audio.sfx(&"fall", 2.0, 0.7)
		manager.camera.shake(0.35)


## Trails and strike sparks follow fighters while a qualifying move is active.
func _process(_delta: float) -> void:
	for fighter: Fighter in _trails:
		var move := fighter.current_move
		var active := fighter.state == Fighter.State.ATTACK and move != null \
				and fighter.state_frame > move.startup and fighter.state_frame <= move.startup + move.active
		var trail: GPUParticles3D = _trails[fighter]
		trail.emitting = active and move.travel > 0.0
		if trail.emitting:
			trail.global_position = fighter.global_position + Vector3.UP * (0.25 if move.low_profile else 1.0)
		var sparks: GPUParticles3D = _strike_sparks[fighter]
		sparks.emitting = active and (move.rise > 0.0 or move.hits > 1)
		if sparks.emitting:
			sparks.global_position = fighter.global_transform * move.hitbox_offset
			(sparks.process_material as ParticleProcessMaterial).color = SUPER_COLOR if move.super_move or move.input.begins_with("~") else HIT_COLOR


## Super start: a burst of golden sparks and a glow on the fighter, plus the flash sound.
func _on_super_flash(fighter: Fighter, _move: MoveData) -> void:
	spark(fighter.global_position + Vector3.UP * 1.1, SUPER_COLOR, 2.2)
	Audio.sfx(&"super", 0.0)
	Audio.shout(fighter.data.id, "super", 2.0)
	if fighter.model:
		fighter.model.flash(SUPER_COLOR, 0.6)


func _on_landed_hard(fighter: Fighter) -> void:
	dust(fighter.global_position)
	Audio.sfx(&"fall", -2.0)


func _on_throw_impact(defender: Fighter) -> void:
	spark(defender.global_position + Vector3.UP * 1.1, HIT_COLOR, 1.4)
	Audio.sfx(&"hit_heavy", 1.0, 0.85)
	# Command grabs slam: dust and a shake; the super grab adds a gold shockwave.
	var grab := defender.opponent.grab_move
	if grab:
		var floor_point := Vector3(defender.global_position.x, 0.02, defender.global_position.z)
		dust(floor_point)
		manager.camera.shake(0.3)
		if grab.impact_fx == &"shockwave":
			_ring(floor_point, SUPER_COLOR, 3.4, true)
			spark(defender.global_position + Vector3.UP * 0.8, SUPER_COLOR, 2.4)
			manager.camera.shake(0.4)
	if defender.model:
		defender.model.flash(Color.WHITE, 0.16)


# --- Effects ---------------------------------------------------------------------

## Burst of sparks plus a brief additive flash at `point`. `size` ~0.5..1.6.
func spark(point: Vector3, color: Color, size: float) -> void:
	spawned += 1
	var p := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	p.global_position = point
	p.amount_ratio = clampf(size / 1.6, 0.3, 1.0)
	var mat := p.process_material as ParticleProcessMaterial
	mat.color = color
	mat.initial_velocity_min = 1.8 * size
	mat.initial_velocity_max = 4.5 * size
	p.restart()
	_impact_flash(point, color, size)


## Expanding ring: flat on the floor (ground pound) or facing the camera (impacts).
func _ring(point: Vector3, color: Color, size: float, flat: bool) -> void:
	spawned += 1
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 32
	torus.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color, 0.9)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	torus.material = mat
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = point
	if flat:
		ring.scale = Vector3(1.0, 0.15, 1.0)
	else:
		var camera := get_viewport().get_camera_3d()
		if camera:
			ring.look_at(camera.global_position, Vector3.UP)
			ring.rotate_object_local(Vector3.RIGHT, PI / 2.0) # torus axis toward the camera
	var start := ring.scale * 0.2
	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, "scale", start * 5.0 * size, 0.35).from(start).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


## Chunks of debris thrown up by a ground pound.
func _debris(point: Vector3) -> void:
	var p := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	p.global_position = point
	p.amount_ratio = 1.0
	var mat := p.process_material as ParticleProcessMaterial
	mat.color = DEBRIS_COLOR
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 6.0
	p.restart()


func dust(point: Vector3) -> void:
	spawned += 1
	var p := _dust[_next_dust]
	_next_dust = (_next_dust + 1) % _dust.size()
	p.global_position = point + Vector3.UP * 0.05
	p.restart()


func _impact_flash(point: Vector3, color: Color, size: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.7 * size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.albedo_texture = _flash_texture
	mat.albedo_color = Color(color, 1.0)
	quad.material = mat
	var flash := MeshInstance3D.new()
	flash.mesh = quad
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	flash.global_position = point
	var tween := flash.create_tween().set_parallel()
	tween.tween_property(flash, "scale", Vector3.ONE * 2.2, 0.12).from(Vector3.ONE * 0.6)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.14)
	tween.chain().tween_callback(flash.queue_free)


func _make_sparks() -> GPUParticles3D:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 7.0
	mat.gravity = Vector3(0, -12, 0)
	mat.damping_min = 8.0
	mat.damping_max = 14.0
	mat.scale_min = 0.7
	mat.scale_max = 1.6
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	mat.color_ramp = ramp
	return _make_emitter(mat, 40, 0.3, Vector2(0.09, 0.09))


## Speed streaks left behind a travelling move (charges, slides).
func _make_trail() -> GPUParticles3D:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.35
	mat.direction = Vector3.ZERO
	mat.spread = 180.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.3
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.8
	mat.scale_max = 1.6
	mat.color = Color(TRAIL_COLOR, 0.55)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.7))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	mat.color_ramp = ramp
	return _make_continuous(mat, 60, 0.35, Vector2(0.3, 0.3))


## Sparks streaming off the striking limb during rising attacks and flurries.
func _make_strike_sparks() -> GPUParticles3D:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 60.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -4, 0)
	mat.scale_min = 0.6
	mat.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	mat.color_ramp = ramp
	return _make_continuous(mat, 50, 0.3, Vector2(0.08, 0.08))


func _make_continuous(mat: ParticleProcessMaterial, amount: int, lifetime: float, quad_size: Vector2) -> GPUParticles3D:
	var p := _make_emitter(mat, amount, lifetime, quad_size)
	p.one_shot = false
	p.explosiveness = 0.0
	p.emitting = false
	return p


func _make_dust() -> GPUParticles3D:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3.UP
	mat.emission_ring_radius = 0.5
	mat.emission_ring_inner_radius = 0.2
	mat.emission_ring_height = 0.05
	mat.direction = Vector3.UP
	mat.spread = 70.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 1.4
	mat.gravity = Vector3(0, 0.3, 0)
	mat.damping_min = 1.0
	mat.damping_max = 2.0
	mat.scale_min = 1.5
	mat.scale_max = 3.0
	mat.color = Color(0.75, 0.72, 0.68, 0.5)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.6))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	mat.color_ramp = ramp
	var p := _make_emitter(mat, 24, 0.9, Vector2(0.25, 0.25))
	(p.draw_pass_1.surface_get_material(0) as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	return p


func _make_emitter(mat: ParticleProcessMaterial, amount: int, lifetime: float, quad_size: Vector2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.process_material = mat
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = quad_size
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.albedo_texture = _flash_texture
	quad.material = draw_mat
	p.draw_pass_1 = quad
	add_child(p)
	return p


func _make_radial_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.3, Color(1, 1, 1, 0.8))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex
