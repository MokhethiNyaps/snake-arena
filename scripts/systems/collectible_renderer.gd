class_name CollectibleRenderer
extends Node3D
## §19 Phase 10 — ONE MultiMeshInstance3D per collectible TYPE replaces
## 420+ individual MeshInstance3D nodes (measured: collectibles alone cost
## ~840 draw calls; §19 ceiling for the whole frame is 150). The pooled
## CollectibleNodes stay as pure data/logic (hash, values, decay).
##
## Colour design note (decision #71): per-TYPE materials carry the colour.
## MultiMesh per-instance color_array rendering proved UNRELIABLE on the
## sandbox stack (llvmpipe + Compatibility renders instances white — the
## same reason per-segment snake banding cannot be verified here), so this
## renderer deliberately uses zero per-instance colour data. Draw calls: 5.
##
## Zero per-frame allocations: the transform arrays are persistent and only
## ever grow. Pulse lives in the shader; spin is one shared angle.

const TYPES: Array = [
	CollectibleDef.Type.CELL_SMALL,
	CollectibleDef.Type.CELL_MEDIUM,
	CollectibleDef.Type.CELL_LARGE,
	CollectibleDef.Type.SHARD_RARE,
	CollectibleDef.Type.CORPSE_MOTE,
]
## Worst-case live counts + headroom (cells 420 target, motes burst-heavy).
const CAPS: Dictionary = {
	CollectibleDef.Type.CELL_SMALL: 500,
	CollectibleDef.Type.CELL_MEDIUM: 300,
	CollectibleDef.Type.CELL_LARGE: 64,
	CollectibleDef.Type.SHARD_RARE: 32,
	CollectibleDef.Type.CORPSE_MOTE: 300,
}
## The rare shard spins; the rest sit still (readability: spin = "special").
const SPIN_TYPES: Array = [CollectibleDef.Type.SHARD_RARE]
const PULSE_BY_TYPE: Dictionary = {
	CollectibleDef.Type.SHARD_RARE: [5.0, 1.2],   # hz, amount — hard pulse
	CollectibleDef.Type.CELL_LARGE: [3.0, 0.7],
	CollectibleDef.Type.CELL_MEDIUM: [3.0, 0.5],
	CollectibleDef.Type.CELL_SMALL: [3.0, 0.4],
	CollectibleDef.Type.CORPSE_MOTE: [4.0, 0.6],
}

var _table: CollectibleTable = null
var _mmi: Dictionary = {}          # type -> MultiMeshInstance3D
var _mats: Dictionary = {}         # type -> StandardMaterial3D (pulse energy)
var _transforms: Dictionary = {}   # type -> PackedFloat32Array (16/instance)
var _counts: Dictionary = {}
var _warned: Dictionary = {}


var _pulse_t: float = 0.0


func _ready() -> void:
	_table = load("res://resources/config/collectibles.tres")
	for type in TYPES:
		var def: CollectibleDef = _table.get_def(type)
		var cap: int = int(CAPS[type])
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.name = "Collectibles_" + str(CollectibleDef.Type.keys()[type])
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _mesh_for_shape(def.mesh_shape)
		multimesh.instance_count = cap
		multimesh.visible_instance_count = 0
		mmi.multimesh = multimesh
		# §19: collectibles do not cast shadows (the shadow pass over 400
		# casters doubled the draw-call count).
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# NOTE: a ShaderMaterial whose uniforms are set at runtime rendered
		# WHITE on the sandbox stack (llvmpipe + Compatibility) in every
		# variation tried (the boundary .tscn ShaderMaterial works — the
		# difference is runtime set_shader_parameter). StandardMaterial
		# emissive is bulletproof on both; the per-type pulse runs through
		# emission energy in sync().
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = def.color
		mat.emission_enabled = true
		mat.emission = def.color
		mat.emission_energy_multiplier = 1.4
		mmi.material_override = mat
		_mats[type] = mat
		add_child(mmi)
		_mmi[type] = mmi
		var t: PackedFloat32Array = PackedFloat32Array()
		# use_colors=false → the engine expects the NON-PADDED 12-float
		# Transform3D per instance (probe-verified: 16 rejected, 12 accepted;
		# the padded 4x4 16-float layout is only valid with use_colors=true).
		t.resize(cap * 12)
		_transforms[type] = t
		_counts[type] = 0
		_warned[type] = false


## One call per frame from the CollectibleManager. `alive` maps
## instance_id -> CollectibleNode; `spin_angle` is the shared accumulated
## angle for SPIN_TYPES (per-instance offset derives from position).
func sync(alive: Dictionary, spin_angle: float) -> void:
	_pulse_t += get_process_delta_time()
	for type in TYPES:
		_counts[type] = 0
	# Per-type emissive pulse (cheap: one uniform per material, per frame).
	for type in _mats:
		var pulse: Array = PULSE_BY_TYPE.get(type, [3.0, 0.45])
		(_mats[type] as StandardMaterial3D).emission_energy_multiplier = \
			1.4 + float(pulse[1]) * (0.5 + 0.5 * sin(_pulse_t * float(pulse[0]) * TAU))
	for id in alive:
		var node: CollectibleNode = alive[id] as CollectibleNode
		if node == null or node.def == null or not node.visible:
			continue
		var type: int = node.def.type
		var idx: int = int(_counts[type])
		if idx >= int(CAPS[type]):
			if not _warned[type]:
				_warned[type] = true
				push_warning("[CollectibleRenderer] type %d at cap — extras not drawn." % type)
			continue
		_counts[type] = idx + 1
		var s: float = node.def.scale
		var pos: Vector3 = node.global_position
		var ang: float = spin_angle + pos.x * 0.7 + pos.z * 1.3 if SPIN_TYPES.has(type) else 0.0
		var ca: float = cos(ang) * s
		var sa: float = sin(ang) * s
		var base: int = idx * 12
		var t: PackedFloat32Array = _transforms[type]
		# 12-float Transform3D: basis COLUMNS x/y/z then origin. Y-rotation.
		t[base] = ca;       t[base + 1] = 0.0;  t[base + 2] = -sa
		t[base + 3] = 0.0;  t[base + 4] = s;    t[base + 5] = 0.0
		t[base + 6] = sa;   t[base + 7] = 0.0;  t[base + 8] = ca
		t[base + 9] = pos.x; t[base + 10] = pos.y; t[base + 11] = pos.z
	for type in TYPES:
		var count: int = int(_counts[type])
		var mmi: MultiMeshInstance3D = _mmi[type]
		if count == 0:
			if mmi.multimesh.visible_instance_count != 0:
				mmi.multimesh.visible_instance_count = 0
			continue
		mmi.multimesh.buffer = _transforms[type]
		mmi.multimesh.visible_instance_count = count


func _mesh_for_shape(shape: int) -> Mesh:
	match shape:
		CollectibleDef.MeshShape.SPHERE:
			var m: SphereMesh = SphereMesh.new()
			m.radius = 0.5
			m.height = 1.0
			m.radial_segments = 8
			m.rings = 4
			return m
		CollectibleDef.MeshShape.OCTAHEDRON:
			var p: PrismMesh = PrismMesh.new()
			p.size = Vector3(0.9, 1.0, 0.9)
			return p
		CollectibleDef.MeshShape.CUBE:
			var b: BoxMesh = BoxMesh.new()
			b.size = Vector3.ONE * 0.8
			return b
		CollectibleDef.MeshShape.DODECAHEDRON:
			var d: SphereMesh = SphereMesh.new()
			d.radius = 0.5
			d.height = 1.0
			d.radial_segments = 5
			d.rings = 3
			return d
		_:
			var f: SphereMesh = SphereMesh.new()
			f.radius = 0.5
			f.height = 1.0
			return f
