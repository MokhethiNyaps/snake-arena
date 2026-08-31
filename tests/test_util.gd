extends RefCounted
## §5/§11 — Smoothing correctness (frame-rate independence) and ObjectPool
## bookkeeping.

const ObjectPoolClass = preload("res://scripts/util/object_pool.gd")


func test_smoothing_converges_to_target() -> bool:
	var v: float = 0.0
	var target: float = 10.0
	var half_life: float = 0.12
	var steps: int = 240  # 4 simulated seconds at 60 Hz
	for i in steps:
		v = Smoothing.damp(v, target, half_life, 1.0 / 60.0)
	return absf(v - target) < 0.001


func test_smoothing_frame_rate_independent() -> bool:
	# Same wall-clock duration, different tick rates, must land in the same
	# place (within tolerance) — the whole point of half-life damping.
	var v60: float = 0.0
	var v30: float = 0.0
	var v5: float = 0.0
	var target: float = 100.0
	var half_life: float = 0.12
	for i in 60:   # 1 s at 60 Hz
		v60 = Smoothing.damp(v60, target, half_life, 1.0 / 60.0)
	for i in 30:   # 1 s at 30 Hz
		v30 = Smoothing.damp(v30, target, half_life, 1.0 / 30.0)
	for i in 5:    # 1 s at 5 Hz (hostile frame pacing)
		v5 = Smoothing.damp(v5, target, half_life, 1.0 / 5.0)
	var ok: bool = absf(v60 - v30) < 0.5 and absf(v60 - v5) < 2.5
	if not ok:
		printerr("  v60=%f v30=%f v5=%f" % [v60, v30, v5])
	return ok


func test_smoothing_half_life_covers_half_distance() -> bool:
	# After exactly one half-life, exactly half the distance is covered.
	var v: float = Smoothing.damp(0.0, 100.0, 0.5, 0.5)
	return is_equal_approx(v, 50.0)


func test_damp_vector_works() -> bool:
	var v: Vector3 = Vector3.ZERO
	for i in 120:
		v = Smoothing.damp_vector(v, Vector3(5.0, 3.0, -2.0), 0.1, 1.0 / 60.0)
	return v.distance_to(Vector3(5.0, 3.0, -2.0)) < 0.01


func test_object_pool_prewarm_and_reuse() -> bool:
	var container: Node = Node.new()
	var scene: PackedScene = _make_poolable_scene()
	var pool: ObjectPool = ObjectPoolClass.new(scene, container)
	pool.prewarm(5)
	if pool.inactive_count() != 5 or pool.total_created != 5:
		container.free()
		return false
	var nodes: Array[Node] = []
	for i in 7:  # acquire 7: 5 from prewarm + 2 new
		nodes.append(pool.acquire())
	if pool.total_created != 7 or pool.inactive_count() != 0 or pool.active_count() != 7:
		container.free()
		return false
	for n in nodes:
		if not pool.release(n):
			container.free()
			return false
	var ok: bool = pool.inactive_count() == 7 and pool.active_count() == 0
	container.free()
	return ok


func test_object_pool_refuses_foreign_node() -> bool:
	var container: Node = Node.new()
	var pool: ObjectPool = ObjectPoolClass.new(_make_poolable_scene(), container)
	pool.prewarm(1)
	var stranger: Node = Node.new()
	var refused: bool = not pool.release(stranger)
	stranger.free()
	var count_ok: bool = pool.active_count() == 0
	container.free()
	return refused and count_ok


func _make_poolable_scene() -> PackedScene:
	# A scene that is legal to instantiate headlessly.
	var root: Node = Node.new()
	var scene: PackedScene = PackedScene.new()
	scene.pack(root)
	root.free()
	return scene
