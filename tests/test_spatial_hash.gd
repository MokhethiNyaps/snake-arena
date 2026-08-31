extends RefCounted
## §9A.1 — SpatialHash correctness tests: insert/query, no false negatives,
## cell boundaries, removal, moves, dense cells.

const SpatialHashClass = preload("res://scripts/systems/spatial_hash.gd")

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func test_insert_then_query_finds_item() -> bool:
	var hash: SpatialHash = SpatialHashClass.new()
	hash.insert(1, Vector3(5.0, 0.0, 5.0))
	var found: Array[int] = hash.query_radius(Vector3(5.0, 0.0, 5.0), 2.0)
	return found.has(1) and hash.item_count() == 1


func test_query_radius_respects_distance() -> bool:
	var hash: SpatialHash = SpatialHashClass.new()
	hash.insert(1, Vector3(0.0, 0.0, 0.0))
	hash.insert(2, Vector3(10.0, 0.0, 0.0))
	hash.insert(3, Vector3(100.0, 0.0, 0.0))
	var found: Array[int] = hash.query_radius(Vector3.ZERO, 5.0)
	return found.has(1) and not found.has(2) and not found.has(3)


func test_no_false_negatives_vs_brute_force() -> bool:
	# Randomized: any point the hash misses but brute force finds is a failure.
	var hash: SpatialHash = SpatialHashClass.new()
	var points: Array[Vector3] = []
	for i in 200:
		var p: Vector3 = Vector3(
			_rng.randf_range(-80.0, 80.0), 0.0, _rng.randf_range(-80.0, 80.0))
		points.append(p)
		hash.insert(i, p)
	for q in 20:
		var center: Vector3 = Vector3(
			_rng.randf_range(-60.0, 60.0), 0.0, _rng.randf_range(-60.0, 60.0))
		var radius: float = _rng.randf_range(1.0, 15.0)
		var expected: Array[int] = []
		for i in points.size():
			if points[i].distance_to(center) <= radius:
				expected.append(i)
		var got: Array[int] = hash.query_radius(center, radius)
		for id in expected:
			if not got.has(id):
				printerr("  MISS id=%d p=%s r=%f" % [id, points[id], radius])
				return false
	return true


func test_no_false_positives_vs_brute_force() -> bool:
	var hash: SpatialHash = SpatialHashClass.new()
	var points: Array[Vector3] = []
	for i in 100:
		var p: Vector3 = Vector3(
			_rng.randf_range(-80.0, 80.0), 0.0, _rng.randf_range(-80.0, 80.0))
		points.append(p)
		hash.insert(i, p)
	for q in 10:
		var center: Vector3 = Vector3(
			_rng.randf_range(-60.0, 60.0), 0.0, _rng.randf_range(-60.0, 60.0))
		var radius: float = _rng.randf_range(1.0, 15.0)
		var got: Array[int] = hash.query_radius(center, radius)
		for id in got:
			if points[id].distance_to(center) > radius + 0.0001:
				printerr("  FALSE POSITIVE id=%d dist=%f r=%f" % [
					id, points[id].distance_to(center), radius])
				return false
	return true


func test_cell_boundary_correctness() -> bool:
	# 6.0 cell size: 5.9 and 6.1 land in different cells but are close.
	var hash: SpatialHash = SpatialHashClass.new()
	hash.insert(1, Vector3(5.9, 0.0, 0.0))
	hash.insert(2, Vector3(6.1, 0.0, 0.0))
	if hash.get_cell_key(Vector3(5.9, 0, 0)) == hash.get_cell_key(Vector3(6.1, 0, 0)):
		printerr("  expected different cells for 5.9 vs 6.1")
		return false
	var found: Array[int] = hash.query_radius(Vector3(6.0, 0.0, 0.0), 1.0)
	return found.has(1) and found.has(2)


func test_negative_coordinates_cells() -> bool:
	var hash: SpatialHash = SpatialHashClass.new()
	hash.insert(1, Vector3(-1.0, 0.0, -1.0))
	hash.insert(2, Vector3(-7.0, 0.0, -7.0))
	if hash.get_cell_key(Vector3(-1.0, 0, -1.0)) != Vector2i(-1, -1):
		printerr("  expected cell (-1,-1), got %s" % str(hash.get_cell_key(Vector3(-1, 0, -1))))
		return false
	var found: Array[int] = hash.query_radius(Vector3(-1.0, 0.0, -1.0), 2.0)
	return found.has(1) and not found.has(2)


func test_remove_erases_item() -> bool:
	var hash: SpatialHash = SpatialHashClass.new()
	hash.insert(1, Vector3(0.0, 0.0, 0.0))
	if not hash.remove(1):
		return false
	var found: Array[int] = hash.query_radius(Vector3.ZERO, 10.0)
	return not found.has(1) and hash.item_count() == 0 and hash.cell_count() == 0


func test_update_moves_item_across_cells() -> bool:
	var hash: SpatialHash = SpatialHashClass.new()
	hash.insert(1, Vector3(0.0, 0.0, 0.0))
	hash.insert(1, Vector3(50.0, 0.0, 0.0))  # re-insert = move
	var found_old: Array[int] = hash.query_radius(Vector3.ZERO, 1.0)
	var found_new: Array[int] = hash.query_radius(Vector3(50.0, 0.0, 0.0), 1.0)
	return not found_old.has(1) and found_new.has(1) and hash.item_count() == 1


func test_dense_cell_returns_all() -> bool:
	var hash: SpatialHash = SpatialHashClass.new()
	for i in 50:
		hash.insert(i, Vector3(0.1 * float(i % 10), 0.0, 0.1 * float(i / 10)))
	var found: Array[int] = hash.query_radius(Vector3.ZERO, 5.0)
	return found.size() == 50


func test_empty_query() -> bool:
	var hash: SpatialHash = SpatialHashClass.new()
	return hash.query_radius(Vector3.ZERO, 10.0).is_empty()


func test_clear_drops_everything() -> bool:
	var hash: SpatialHash = SpatialHashClass.new()
	for i in 20:
		hash.insert(i, Vector3(float(i), 0.0, 0.0))
	hash.clear()
	return hash.item_count() == 0 and hash.cell_count() == 0
