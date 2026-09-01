extends RefCounted
## §9A.4 — Growth math: power -> speed/turn/radius/segment-count at 20 sample
## values, monotonic and within caps. Uses the REAL SnakeController curves
## (instanced in-tree) so the test can never drift from production code.

const SnakeControllerClass = preload("res://scripts/snake/snake_controller.gd")

var _snake: SnakeController = null
var _root: Node = null


func _get_snake() -> SnakeController:
	if _snake == null:
		_root = (Engine.get_main_loop() as SceneTree).root
		_snake = SnakeControllerClass.new()
		_snake.name = "GrowthTestSnake"
		_snake.config = load("res://resources/config/snake_player.tres")
		# Keep it stationary: no steering, and park it far from the wall.
		_root.add_child(_snake)
		_snake.alive = false
	return _snake


func _cleanup() -> void:
	if _snake != null and is_instance_valid(_snake):
		_snake.free()
	_snake = null


func test_speed_curve_endpoints() -> bool:
	var s: SnakeController = _get_snake()
	# Power 1 => the §3.1 formula value (curve applies at power 1 too):
	# speed = 11 * (1 - 0.28 * (1 - exp(-1/9))) ≈ 10.68
	s.power = 1.0
	s._update_derived_stats()
	var expected_p1: float = 11.0 * (1.0 - 0.28 * (1.0 - exp(-1.0 / 9.0)))
	if absf(s.current_speed - expected_p1) > 0.01:
		printerr("  speed at power 1 = %.2f, expected %.2f" % [s.current_speed, expected_p1])
		return false
	# Huge power => clamped at the floor, never below.
	s.power = 10000.0
	s._update_derived_stats()
	if s.current_speed < s.config.min_move_speed - 0.01:
		printerr("  speed at power 10000 = %.2f below floor" % s.current_speed)
		return false
	_cleanup()
	return true


func test_speed_monotonic_non_increasing() -> bool:
	var s: SnakeController = _get_snake()
	var prev: float = INF
	for i in 20:
		s.power = pow(1.5, i)  # 1 .. ~2200
		s._update_derived_stats()
		if s.current_speed > prev + 0.0001:
			printerr("  speed increased at power %.1f" % s.power)
			return false
		prev = s.current_speed
	_cleanup()
	return true


func test_turn_rate_decreases_and_clamps() -> bool:
	var s: SnakeController = _get_snake()
	s.power = 1.0
	s._update_derived_stats()
	# §3.1 formula at power 1: 280 * (1 - 0.30 * log(2)/log(20)) ≈ 260.6
	var expected_p1: float = 280.0 * (1.0 - 0.30 * (log(2.0) / log(20.0)))
	if absf(s.current_turn_rate - expected_p1) > 0.5:
		printerr("  turn at power 1 = %.1f, expected %.1f" % [s.current_turn_rate, expected_p1])
		return false
	var prev: float = INF
	for i in 20:
		s.power = pow(1.5, i)
		s._update_derived_stats()
		if s.current_turn_rate > prev + 0.001:
			printerr("  turn increased at power %.1f" % s.power)
			return false
		prev = s.current_turn_rate
	# Never below the curve floor (45% of base).
	if prev < 280.0 * 0.45 - 0.5:
		printerr("  turn floor broken: %.1f" % prev)
		return false
	_cleanup()
	return true


func test_radius_curve_values() -> bool:
	var s: SnakeController = _get_snake()
	s.power = 1.0
	s._update_derived_stats()
	if absf(s.current_radius - 0.55) > 0.001:
		printerr("  radius at power 1 = %.3f" % s.current_radius)
		return false
	s.power = 512.0
	s._update_derived_stats()
	var expected: float = 0.55 * pow(512.0, 0.19)
	if absf(s.current_radius - expected) > 0.01:
		printerr("  radius at power 512 = %.3f expected %.3f" % [s.current_radius, expected])
		return false
	var prev: float = 0.0
	for i in 20:
		s.power = pow(1.5, i)
		s._update_derived_stats()
		if s.current_radius <= prev:
			printerr("  radius not monotonic at power %.1f" % s.power)
			return false
		prev = s.current_radius
	_cleanup()
	return true


func test_segment_count_formula_and_caps() -> bool:
	var s: SnakeController = _get_snake()
	var cases: Dictionary = {
		2.0: 6,       # floor(2/3.5) = 0
		10.0: 8,      # floor(10/3.5) = 2
		100.0: 34,    # floor(100/3.5) = 28
		350.0: 106,   # floor(350/3.5) = 100
		1000.0: 240,  # capped
		1e9: 240,     # capped
	}
	for p_val: float in cases:
		var count: int = s._segments_for_power(p_val)
		if count != cases[p_val]:
			printerr("  segments at power %.0f = %d, expected %d" % [p_val, count, cases[p_val]])
			return false
	_cleanup()
	return true


func test_add_power_grows_body_and_emits() -> bool:
	var s: SnakeController = _get_snake()
	s.alive = true  # body pipeline needs the controller alive
	var host: TestSignalHost = TestSignalHost.register(s.get_instance_id())
	var events: Array[float] = []
	host.power_changed.connect(func(v: float) -> void: events.append(v))
	var before: int = s._segments_target
	s.add_power(100.0)
	# The target updates instantly; actual segment count eases toward it
	# over ~0.25 s per segment in SnakeBody.tick (verified in the live
	# verify harness, not here — this runner is synchronous).
	var ok: bool = (
		s._segments_target > before
		and absf(s.power - 102.0) < 0.001
		and events.size() >= 1
		and absf(events[0] - 102.0) < 0.001
	)
	TestSignalHost.unregister(s.get_instance_id())
	_cleanup()
	return ok


func test_turn_radius_clamp_applies() -> bool:
	# §6.3: min turn radius = current_radius * 1.15 caps the turn rate.
	var s: SnakeController = _get_snake()
	s.power = 500.0
	s._update_derived_stats()
	var allowed_max: float = rad_to_deg(s.current_speed / (s.config.min_turn_radius_factor * s.current_radius))
	if s.current_turn_rate > allowed_max + 0.01:
		printerr("  turn rate %.1f exceeds min-radius cap %.1f" % [s.current_turn_rate, allowed_max])
		return false
	_cleanup()
	return true
