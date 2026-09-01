class_name SnakeBody
extends RefCounted
## §6.2 — The body-following pipeline: reads the head's PositionHistory at
## arc-length offsets and drives ONE MultiMeshInstance3D per snake (the
## single biggest perf win, §6.2/§36.2). Segments are conceptual slots over
## MultiMesh instances — no per-segment nodes, no physics bodies.
##
## Owns: the MultiMeshInstance3D + transform/colour buffers + grow/shrink
##        tween state, and the per-slot HistoryCursor reuse.
## Does NOT own: the history itself (PositionHistory does), the head
##               movement (SnakeController).
## Talks to: SnakeController only.

const SEGMENT_GROW_TIME: float = 0.25  # §6.2 ease-in for new segments
const SEGMENT_SHRINK_TIME: float = 0.2  # §6.2 scale-down before pooling

var controller: SnakeController = null
var mmi: MultiMeshInstance3D = null
## Head visual (the controller node itself has no mesh).
var head_mesh: MeshInstance3D = null

var _target_count: int = 6
var _count: int = 0
## MultiMesh TRANSFORM_3D buffer: 16 floats per instance in Godot 4.7
## (decision #17 — a 12-float buffer is rejected by the engine).
var _transforms: PackedFloat32Array = PackedFloat32Array()
var _colours: PackedColorArray = PackedColorArray()
var _growing: Array[float] = []   # per-slot grow timer (-1 = settled)
var _shrinking: Array[float] = []  # per-slot shrink timer (-1 = settled)
var _base_scale: float = 1.0


## Attaches to `owner` (a SnakeController in the tree).
func setup(owner: SnakeController) -> void:
	controller = owner
	mmi = MultiMeshInstance3D.new()
	mmi.name = "BodyMultiMesh"
	owner.add_child(mmi)
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _make_segment_mesh()
	# §19: buffers sized to the hard cap ONCE — instance_count stays at the
	# cap forever; visibility is driven by visible_instance_count. Never
	# resizing buffers means zero allocations and zero GPU upload churn.
	var cap: int = controller.config.max_segment_count
	multimesh.instance_count = cap
	mmi.multimesh = multimesh
	mmi.material_override = _make_body_material()
	_transforms.resize(cap * 16)
	_colours.resize(cap)
	# Initial invisible instances (all at origin until written).
	for i in cap:
		_colours[i] = Color(1, 1, 1)
	mmi.multimesh.buffer = _transforms
	mmi.multimesh.color_array = _colours
	mmi.multimesh.visible_instance_count = 0
	# Head visual: a slightly larger sphere riding the controller node.
	head_mesh = MeshInstance3D.new()
	head_mesh.name = "HeadMesh"
	var head_sphere: SphereMesh = SphereMesh.new()
	head_sphere.radius = 1.0
	head_sphere.height = 2.0
	head_sphere.radial_segments = 12
	head_sphere.rings = 6
	head_mesh.mesh = head_sphere
	head_mesh.material_override = _make_head_material()
	controller.add_child(head_mesh)


## All segments spawn at the current last segment (or head) position and
## ease into place — never pop at the origin (§6.2).
func spawn_segments(count: int) -> void:
	var spawn_pos: Vector3 = controller.global_position
	# Extend history so the first body has a real trail to read from.
	for i in count * 2:
		controller.body_push_direct(spawn_pos)
	_count = count
	_target_count = count
	_growing.clear()
	_shrinking.clear()
	for i in count:
		_growing.append(-1.0)
		_shrinking.append(-1.0)
		_write_instance(i, spawn_pos, controller.current_radius)
	mmi.multimesh.visible_instance_count = count
	_upload_buffers()


## Per-physics-tick body update: every segment reads its arc-length slot
## from the history with lerp interpolation (§6.2 — never snap to nearest).
## Segments sit BEHIND the head: target arc = newest_arc - (i+1)*spacing.
func tick() -> void:
	var cfg: SnakeConfig = controller.config
	var history: PositionHistory = controller.get_history()
	if history == null or history.count == 0:
		return
	var radius: float = controller.current_radius
	var spacing: float = cfg.segment_spacing_radius_factor * radius
	var elapsed: float = controller.get_physics_process_delta_time()
	# Grow first: ease new segments in over SEGMENT_GROW_TIME. Buffers are
	# fixed at the cap; growing = one more visible instance per tick.
	if _count < _target_count:
		_count += 1
		var last_pos: Vector3 = _last_segment_pos()
		_growing.append(SEGMENT_GROW_TIME)
		_shrinking.append(-1.0)
		_write_instance(_count - 1, last_pos, radius)
		mmi.multimesh.visible_instance_count = _count
	var newest_arc: float = history.newest_arc()
	for i in _count:
		var target_arc: float = segment_target_arc(newest_arc, i, spacing)
		var pos: Vector3 = history.read_at_arc(target_arc, i)
		# New segments ease outward from the spawn position over 0.25 s.
		if _growing[i] > 0.0:
			_growing[i] = maxf(0.0, _growing[i] - elapsed)
			var t: float = 1.0 - _growing[i] / SEGMENT_GROW_TIME
			pos = pos.lerp(_last_segment_pos(), 1.0 - MathUtil.ease_out_cubic(t))
		_write_transform(i, pos, radius)
	# Shrink: pending slots scale down over SEGMENT_SHRINK_TIME then vanish.
	if _count > _target_count:
		_shrink_step(radius, elapsed)
	# One upload per tick, no matter how many segments changed.
	_upload_buffers()
	# Head visual rides the controller at 1.15x body radius, tinted by the
	# power-tier band colour.
	if head_mesh != null:
		head_mesh.scale = Vector3.ONE * radius * 1.15
		var mat: StandardMaterial3D = head_mesh.material_override
		mat.albedo_color = _band_colour(controller.power_tier(), 0, 2)
		mat.emission = _band_colour(controller.power_tier(), 0, 2)


## §6.2 target-arc formula, shared by the tick and the unit tests.
static func segment_target_arc(newest_arc: float, index: int, spacing: float) -> float:
	return maxf(0.0, newest_arc - (index + 1) * spacing)


## Requests a segment-count change; handled smoothly over subsequent ticks.
func set_target_segment_count(target: int) -> void:
	_target_count = clampi(target, 0, controller.config.max_segment_count)
	if _target_count < _count:
		for i in range(_target_count, _count):
			_shrinking[i] = SEGMENT_SHRINK_TIME


func get_segment_count() -> int:
	return _count


func _shrink_step(radius: float, elapsed: float) -> void:
	var removed: int = 0
	for i in range(_count - 1, -1, -1):
		if _shrinking[i] >= 0.0:
			_shrinking[i] -= elapsed
			var t: float = 1.0 - maxf(0.0, _shrinking[i]) / SEGMENT_SHRINK_TIME
			var scale: float = (1.0 - t) * radius
			_write_transform(i, _last_segment_pos(), maxf(scale, 0.001))
			if _shrinking[i] <= 0.0:
				removed += 1
	if removed > 0:
		_count = maxi(0, _count - removed)
		mmi.multimesh.visible_instance_count = _count
		for i in _count:
			_shrinking[i] = -1.0
			_growing[i] = -1.0


func _last_segment_pos() -> Vector3:
	if _count > 0:
		return controller.get_history().read_at_arc(_count * controller.config.segment_spacing_radius_factor * controller.current_radius, _count - 1)
	return controller.global_position


func _write_instance(index: int, pos: Vector3, radius: float) -> void:
	_write_transform(index, pos, radius)
	var tier: int = controller.power_tier()
	_colours[index] = _band_colour(tier, index, _count)


## MultiMesh buffer: Godot 4.7 validates 16 floats per instance for
## TRANSFORM_3D (verified empirically — a 12-float buffer is REJECTED).
## Layout: basis x row + 0, basis y row + 0, basis z row + 0, origin + 1.
func _write_transform(index: int, pos: Vector3, radius: float) -> void:
	var base: int = index * 16
	_transforms[base] = radius
	_transforms[base + 1] = 0.0
	_transforms[base + 2] = 0.0
	_transforms[base + 3] = 0.0
	_transforms[base + 4] = 0.0
	_transforms[base + 5] = radius
	_transforms[base + 6] = 0.0
	_transforms[base + 7] = 0.0
	_transforms[base + 8] = 0.0
	_transforms[base + 9] = 0.0
	_transforms[base + 10] = radius
	_transforms[base + 11] = 0.0
	_transforms[base + 12] = pos.x
	_transforms[base + 13] = 0.0
	_transforms[base + 14] = pos.z
	_transforms[base + 15] = 1.0


## Uploads the accumulated transform buffer once per tick (called by tick()
## and spawn_segments()) — per-write uploads would re-send the whole
## 240-instance buffer for every segment, every tick (§19 upload churn).
func _upload_buffers() -> void:
	mmi.multimesh.buffer = _transforms
	mmi.multimesh.color_array = _colours


## Power-tier colour bands (§3.2) — readably distinct, with a slight
## per-segment luminance ramp so the body reads as a moving coil.
func _band_colour(tier: int, index: int, count: int) -> Color:
	var bands: Array[Color] = [
		Color(0.2, 0.85, 0.45),
		Color(0.25, 0.9, 0.55),
		Color(0.35, 0.95, 0.6),
		Color(1.0, 0.85, 0.3),
		Color(1.0, 0.6, 0.25),
		Color(1.0, 0.35, 0.3),
	]
	var base: Color = bands[mini(tier, bands.size() - 1)]
	var ramp: float = 0.85 + 0.15 * (float(index) / float(maxi(1, count - 1)))
	return Color(base.r * ramp, base.g * ramp, base.b * ramp)


func _make_segment_mesh() -> SphereMesh:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh


func _make_body_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 0.4
	return mat


func _make_head_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 0.45)
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.85, 0.45)
	mat.emission_energy_multiplier = 0.55
	return mat
