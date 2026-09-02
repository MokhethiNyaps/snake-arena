extends RefCounted
## §3.5/§9A — Boundary wall rules: touching the wall never kills; it
## hard-stops the OUTWARD velocity component while tangential movement
## keeps sliding, and the soft zone slows (0.85×) + pushes inward.
## Regression guard for the wall-freeze bug (an alive snake pinned at
## r == arena_radius with speed 0 forever — caught by the Phase 5 verify
## flake; see decision #51).

const SnakeControllerClass = preload("res://scripts/snake/snake_controller.gd")
const BALANCE: GameBalanceConfig = preload("res://resources/config/game_balance.tres")


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _make_snake() -> SnakeController:
	var snake: SnakeController = SnakeControllerClass.new()
	snake.config = load("res://resources/config/snake_ai.tres")
	_tree().root.add_child(snake)
	return snake


func _free_snake(snake: SnakeController) -> void:
	snake.alive = false
	snake.queue_free()
	await _tree().physics_frame


## The slow curve: 1.0 inside the zone, linear to 0.85 at the wall, and
## — critically — FLOORED at 0.85 beyond it (mid-shrink), never 0.0.
func test_soft_zone_factor_curve() -> bool:
	var snake: SnakeController = _make_snake()
	snake.alive = false
	var r_arena: float = BALANCE.arena_radius
	var soft_in: float = r_arena - BALANCE.soft_zone_width
	# Inside the zone: full speed.
	snake.global_position = Vector3(soft_in - 1.0, 0.0, 0.0)
	if absf(snake._soft_zone_factor() - 1.0) > 0.0001:
		printerr("  factor inside zone != 1.0")
		return false
	# Mid-zone: linear interpolation (halfway → 1 - 0.15*0.5).
	snake.global_position = Vector3((soft_in + r_arena) * 0.5, 0.0, 0.0)
	var want_mid: float = 1.0 - (1.0 - BALANCE.soft_zone_slow_multiplier) * 0.5
	if absf(snake._soft_zone_factor() - want_mid) > 0.0001:
		printerr("  mid-zone factor %.4f != %.4f" % [snake._soft_zone_factor(), want_mid])
		return false
	# Exactly at the wall: the soft-zone minimum.
	snake.global_position = Vector3(r_arena, 0.0, 0.0)
	if absf(snake._soft_zone_factor() - BALANCE.soft_zone_slow_multiplier) > 0.0001:
		printerr("  wall factor %.4f != %.4f (frozen?)" % [snake._soft_zone_factor(), BALANCE.soft_zone_slow_multiplier])
		return false
	# Beyond the wall (shrink clamped a snake outside): FLOOR, not zero.
	snake.global_position = Vector3(r_arena + 5.0, 0.0, 0.0)
	if absf(snake._soft_zone_factor() - BALANCE.soft_zone_slow_multiplier) > 0.0001:
		printerr("  beyond-wall factor %.4f != floor %.4f" % [snake._soft_zone_factor(), BALANCE.soft_zone_slow_multiplier])
		return false
	await _free_snake(snake)
	return true


## §3.5 slide, not freeze: a head pinned exactly ON the wall must keep
## moving when steered along it (the bug froze it at speed 0 forever).
func test_wall_slide_no_freeze() -> bool:
	var snake: SnakeController = _make_snake()
	var r_arena: float = BALANCE.arena_radius
	# Pin exactly at the wall — the state _clamp_to_arena produces.
	snake.global_position = Vector3(r_arena, 0.0, 0.0)
	snake.facing_angle_deg = 0.0  # +Z: tangent to the wall at this point.
	snake.set_steer_target(Vector3(r_arena, 0.0, 1000.0))
	var travelled: float = 0.0
	var last: Vector3 = snake.global_position
	for i in 60:
		await _tree().physics_frame
		travelled += snake.global_position.distance_to(last)
		last = snake.global_position
		if snake.global_position.length() > r_arena + 0.001:
			printerr("  escaped the wall outward at tick %d (r=%.4f)" % [i, snake.global_position.length()])
			return false
	# ~0.85 × min_move_speed × 1 s ≈ 6.5 units expected; the bug gave 0.0.
	if travelled < 3.0:
		printerr("  wall-pinned snake froze: travelled %.3f units in 60 ticks" % travelled)
		return false
	await _free_snake(snake)
	return true


## Driving head-on into the wall: hard stop (never crosses), then the
## snake steers along it and keeps sliding.
func test_wall_hard_stop_and_slide() -> bool:
	var snake: SnakeController = _make_snake()
	var r_arena: float = BALANCE.arena_radius
	snake.global_position = Vector3(r_arena - 3.0, 0.0, 0.0)
	snake.facing_angle_deg = 90.0  # +X: straight at the wall.
	snake.set_steer_target(Vector3(1000.0, 0.0, 0.0))
	var hit_wall: bool = false
	for i in 90:
		await _tree().physics_frame
		var r: float = snake.global_position.length()
		if r > r_arena + 0.001:
			printerr("  crossed the wall at tick %d (r=%.4f)" % [i, r])
			return false
		if r >= r_arena - 0.01:
			hit_wall = true
	if not hit_wall:
		printerr("  never reached the wall (r=%.3f)" % snake.global_position.length())
		return false
	# Now steer along the wall: must slide, not freeze.
	snake.set_steer_target(Vector3(r_arena, 0.0, 1000.0))
	var travelled: float = 0.0
	var last: Vector3 = snake.global_position
	for i in 60:
		await _tree().physics_frame
		travelled += snake.global_position.distance_to(last)
		last = snake.global_position
	if travelled < 3.0:
		printerr("  post-impact slide froze: travelled %.3f units" % travelled)
		return false
	await _free_snake(snake)
	return true


## Steering inward from the wall recovers into the arena.
func test_wall_recovery() -> bool:
	var snake: SnakeController = _make_snake()
	var r_arena: float = BALANCE.arena_radius
	snake.global_position = Vector3(r_arena, 0.0, 0.0)
	snake.facing_angle_deg = 0.0
	# NOTE: steer at a NEAR-centre point — set_steer_target treats the
	# exact zero vector as "clear target" (sentinel), so Vector3.ZERO
	# would coast instead of steering.
	snake.set_steer_target(Vector3(1.0, 0.0, 0.0))
	for i in 60:
		await _tree().physics_frame
	var r: float = snake.global_position.length()
	if r > r_arena - 4.0:
		printerr("  never recovered inward from the wall (r=%.3f)" % r)
		return false
	await _free_snake(snake)
	return true


## §3.5 "push you inward": coasting tangentially in the soft zone with no
## steering, the inward push must reduce the radial distance.
func test_soft_zone_push_inward() -> bool:
	var snake: SnakeController = _make_snake()
	var r_arena: float = BALANCE.arena_radius
	snake.global_position = Vector3(r_arena - 0.2, 0.0, 0.0)
	snake.facing_angle_deg = 0.0  # tangent; no steer target → coast straight.
	snake.set_steer_target(Vector3.ZERO)
	var r_start: float = snake.global_position.length()
	for i in 60:
		await _tree().physics_frame
	var r_end: float = snake.global_position.length()
	# Push ≈ 2.0 u/s at full depth ≈ 2.0 units over 1 s; require > 0.5.
	if r_end >= r_start - 0.5:
		printerr("  soft-zone push did not act (r %.3f -> %.3f)" % [r_start, r_end])
		return false
	await _free_snake(snake)
	return true
