class_name BoostTrail
extends Node3D
## §7/§16 Phase 10 — boost trail particles at the snake head, coloured by
## the equipped skin's trail_colour. Attached as a CHILD of the SnakeController
## node so it rides the head for free; world-space particles stay behind as
## the snake moves (that IS the trail).

var _particles: GPUParticles3D = null


func setup(colour: Color) -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "BoostTrail"
	_particles.amount = 48
	_particles.lifetime = 0.55
	_particles.explosiveness = 0.0
	_particles.local_coords = false
	_particles.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.28
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.5
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	mat.color = colour
	_particles.process_material = mat
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	quad.material = _glow_material(colour)
	_particles.draw_pass_1 = quad
	_particles.emitting = false
	add_child(_particles)


func _glow_material(colour: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = colour
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = 2.2
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m


func set_boosting(on: bool) -> void:
	if _particles != null:
		_particles.emitting = on
