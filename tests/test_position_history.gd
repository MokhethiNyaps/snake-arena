extends RefCounted
## §9A.2 — Body-following correctness: given synthetic head paths, segment N
## must sit within 0.02 units of the correct arc-length position (straight
## path) / 0.05 (curved path). Uses the SAME production formula
## (SnakeBody.segment_target_arc) and the production PositionHistory.

const PositionHistoryClass = preload("res://scripts/snake/position_history.gd")
const SnakeBodyClass = preload("res://scripts/snake/snake_body.gd")

const SAMPLE_DISTANCE: float = 0.10
const SPACING: float = 0.682  # 0.62 * radius(1.1) — representative spacing


func test_arc_accumulates_on_straight_line() -> bool:
	var h: PositionHistory = PositionHistoryClass.new(1024, 8)
	h.push(Vector3.ZERO, SAMPLE_DISTANCE)
	var x: float = 0.0
	while x < 50.0:
		x += 0.5
		h.push(Vector3(x, 0, 0), SAMPLE_DISTANCE)
	return absf(h.newest_arc() - 50.0) < 0.01


func test_distance_sampling_skips_close_points() -> bool:
	var h: PositionHistory = PositionHistoryClass.new(1024, 8)
	h.push(Vector3.ZERO, 0.5)
	# Oscillate within ±0.3: cumulative drift never reaches the 0.5 sample
	# distance, so NO new samples may be created.
	for i in 100:
		var x: float = 0.3 * sin(float(i) * 0.7)
		h.push(Vector3(x, 0, 0), 0.5)
	return h.count == 1


func test_read_at_arc_lerps_exactly() -> bool:
	var h: PositionHistory = PositionHistoryClass.new(1024, 8)
	h.push(Vector3.ZERO, 0.05)
	for i in 400:
		h.push(Vector3(0.05 * float(i + 1), 0, 0), 0.05)
	var p: Vector3 = h.read_at_arc(2.5, 0)
	return absf(p.x - 2.5) < 0.02


func test_read_beyond_range_returns_newest() -> bool:
	var h: PositionHistory = PositionHistoryClass.new(1024, 8)
	h.push(Vector3.ZERO, 0.1)
	for i in 50:
		h.push(Vector3(float(i + 1), 0, 0), 0.1)
	var p: Vector3 = h.read_at_arc(1e9, 0)
	return absf(p.x - 50.0) < 0.01


func test_cursor_reads_are_monotonic() -> bool:
	var h: PositionHistory = PositionHistoryClass.new(1024, 8)
	h.push(Vector3.ZERO, 0.1)
	for i in 300:
		h.push(Vector3(float(i + 1), 0, 0), 0.1)
	var prev_x: float = -1.0
	for arc in [10.0, 20.0, 30.0, 40.0, 50.0]:
		var p: Vector3 = h.read_at_arc(arc, 0)
		if p.x <= prev_x:
			return false
		prev_x = p.x
	return true


func test_ring_buffer_wraps_cleanly() -> bool:
	var h: PositionHistory = PositionHistoryClass.new(64, 8)
	var angle: float = 0.0
	h.push(Vector3(30, 0, 0), SAMPLE_DISTANCE)
	for i in 2000:
		angle += 0.02
		h.push(Vector3(cos(angle) * 30.0, 0, sin(angle) * 30.0), SAMPLE_DISTANCE)
	if not h.invariant_ok():
		printerr("  invariant broken after wrap")
		return false
	# A read near the newest sample must be close to the circle's edge.
	var newest: Vector3 = h.latest()
	var p: Vector3 = h.read_at_arc(h.newest_arc() - 0.5, 0)
	if absf(p.length() - 30.0) > 0.1:
		printerr("  read drifted off the circle: len=%.2f" % p.length())
		return false
	return newest.length() > 29.9


func test_segment_follows_straight_path_within_tolerance() -> bool:
	# §9A.2 core test. Head moves along +X at 5 u/s for 10 s. The correct
	# arc-length position is measured along the RECORDED trail (the newest
	# sample), not the true head — distance sampling lags the head by up to
	# one sample gap, by design.
	var h: PositionHistory = PositionHistoryClass.new(4096, 64)
	var dt: float = 1.0 / 60.0
	var x: float = 0.0
	h.push(Vector3.ZERO, SAMPLE_DISTANCE)
	for frame in 600:
		x += 5.0 * dt
		h.push(Vector3(x, 0, 0), SAMPLE_DISTANCE)
		if frame < 120:
			continue  # let the trail build
		var latest_x: float = h.latest().x
		for seg in [0, 5, 19, 39]:
			var target: float = SnakeBodyClass.segment_target_arc(h.newest_arc(), seg, SPACING)
			var got: Vector3 = h.read_at_arc(target, seg)
			var expected_x: float = maxf(0.0, latest_x - (seg + 1) * SPACING)
			if absf(got.x - expected_x) > 0.02:
				printerr("  seg %d: got x=%.4f expected %.4f (frame %d)" % [seg, got.x, expected_x, frame])
				return false
	return true


func test_segment_follows_curved_path_within_tolerance() -> bool:
	# Circle of radius 30; expected = point at (seg+1)*spacing arc behind
	# the recorded head sample, clamped to the trail start.
	var h: PositionHistory = PositionHistoryClass.new(4096, 64)
	var radius: float = 30.0
	var angle: float = 0.0
	var dt: float = 1.0 / 60.0
	var speed: float = 7.0
	h.push(Vector3(radius, 0, 0), SAMPLE_DISTANCE)
	for frame in 600:
		angle += speed * dt / radius
		var head_pos: Vector3 = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		h.push(head_pos, SAMPLE_DISTANCE)
		if frame < 120:
			continue
		var latest: Vector3 = h.latest()
		var latest_angle: float = atan2(latest.z, latest.x)
		for seg in [0, 5, 19, 39]:
			var target: float = SnakeBodyClass.segment_target_arc(h.newest_arc(), seg, SPACING)
			var got: Vector3 = h.read_at_arc(target, seg)
			var expected_arc: float = maxf(0.0, h.newest_arc() - (seg + 1) * SPACING)
			# Trail angle decreases going backward from the newest sample.
			var expected_angle: float = latest_angle - (h.newest_arc() - expected_arc) / radius
			var expected: Vector3 = Vector3(cos(expected_angle) * radius, 0, sin(expected_angle) * radius)
			if got.distance_to(expected) > 0.05:
				printerr("  seg %d: dist %.4f > 0.05 (frame %d)" % [seg, got.distance_to(expected), frame])
				return false
	return true
