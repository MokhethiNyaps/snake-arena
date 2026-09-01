class_name CollectibleNode
extends Node3D
## §3.3 — One pooled, live collectible (cells, rare shard, corpse mote).
## Dumb data + visuals: the CollectibleManager owns spawning, ticking,
## the spatial hash, and absorption. No per-node _process (420+ nodes would
## violate the §19 budget); the manager ticks all alive nodes in one loop.
##
## Owns: its mesh/material, the CollectibleDef it was spawned as, and its
##       power/score values (corpse motes override the def's).
## Does NOT own: the pool, the hash, or collection logic.
## Talks to: nobody — the manager reads its fields.

var def: CollectibleDef = null
## Power granted when absorbed (corpse motes override the def value).
var power_value: float = 0.0
## Score granted when absorbed (corpse motes override the def value).
var score_value: float = 0.0
## Seconds until this mote decays; 0 = lives until collected.
var decay_remaining: float = 0.0
## True once absorb/release has been requested this tick (manager bookkeeping).
var consumed: bool = false

@onready var mesh_instance: MeshInstance3D = $Mesh


## Configures the pooled node for a new life. Reuses the instance material
## (created on first activate) rather than allocating a new one per spawn.
func activate(p_def: CollectibleDef, p_power: float, p_score: float, pos: Vector3) -> void:
	def = p_def
	power_value = p_power
	score_value = p_score
	decay_remaining = p_def.decay_time
	consumed = false
	global_position = pos
	visible = true
	_apply_visual()


func _apply_visual() -> void:
	if def == null:
		return
	# Primitive stand-ins (§46 decision #28): sphere, prism ~ octahedron,
	# box, low-poly sphere ~ dodecahedron. Phase 10 art pass replaces these.
	match def.mesh_shape:
		CollectibleDef.MeshShape.SPHERE:
			mesh_instance.mesh = _sphere_mesh(8, 4)
		CollectibleDef.MeshShape.OCTAHEDRON:
			mesh_instance.mesh = _prism_mesh()
		CollectibleDef.MeshShape.CUBE:
			mesh_instance.mesh = _box_mesh()
		CollectibleDef.MeshShape.DODECAHEDRON:
			mesh_instance.mesh = _sphere_mesh(5, 3)
	mesh_instance.scale = Vector3.ONE * def.scale
	var mat: StandardMaterial3D = mesh_instance.material_override
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.roughness = 0.4
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 1.4
		mesh_instance.material_override = mat
	mat.albedo_color = def.color
	mat.emission = def.color


## Pulse the emissive glow (rare shards pulse hard; cells pulse softly).
func pulse(phase: float, boost: float) -> void:
	var mat: StandardMaterial3D = mesh_instance.material_override
	if mat != null:
		mat.emission_energy_multiplier = 1.4 + boost * (0.5 + 0.5 * sin(phase))


## Spin for the rare shard (called by the manager each tick).
func spin(angle_delta: float) -> void:
	rotate_y(angle_delta)


## Release back to the pool, unregistered from the hash by the manager.
func deactivate() -> void:
	consumed = true
	def = null
	visible = false


func _sphere_mesh(segments: int, rings: int) -> SphereMesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = segments
	m.rings = rings
	return m


func _prism_mesh() -> PrismMesh:
	var m: PrismMesh = PrismMesh.new()
	m.size = Vector3(0.9, 1.0, 0.9)
	return m


func _box_mesh() -> BoxMesh:
	var m: BoxMesh = BoxMesh.new()
	m.size = Vector3.ONE * 0.8
	return m
