class_name SnakeController
extends CharacterBody3D
## §6 — The snake. Owns head movement (turn-rate limited, XZ plane only),
## the §6.2 body-following pipeline, growth/shrink, power/speed/radius math
## (§3.1/§3.2), and boost drain (§3.4). Both the player AND every AI drive
## this through the SAME interface (§8.1): set_steer_target / set_boost.
##
## Owns: its own movement + body + stat state. NOT world collision (the
##        arena soft zone is handled by the caller's WorldRules — AI and
##        player share those rules, Phase 2 runs them inline here via the
##        ArenaRef; SpatialHash combat lands in Phase 6), NOT camera, NOT
##        input, NOT skins.
## Talks to: PositionHistory/SnakeBody/StatModifierStack (children/refs),
##           InputManager (player only, via PlayerController), EventBus on
##           power change.
##
## Godot type note: this node is MOVED MANUALLY (velocity is set for the
## CharacterBody3D API contract only; move_and_slide is not called —
## §6.4 forbids physics bodies for bodies; the CB3D is chosen so Area3D
## children keep transform sync for free).

const STAT_SPEED: StringName = &"speed"
const STAT_TURN: StringName = &"turn"
const STAT_RADIUS: StringName = &"radius"

signal died(snake: SnakeController)
## §9: emitted when the head first enters the soft boundary zone.
signal wall_hit(snake: SnakeController)
signal power_changed(power: float)
signal boosted_changed(boosting: bool)
## §3.4 — a corpse mote was shed behind the head while boosting.
signal boost_mote_emitted(mote_position: Vector3, mote_power: float)

@export var config: SnakeConfig
@export var snake_name: String = "Snake"

## Owned body pipeline (created in _ready; body segments are pooled).
var body: SnakeBody = null
## Timed stat multipliers (§10). Power-ups add to this without touching us.
var stat_stack: StatModifierStack = StatModifierStack.new()

# --- live state ---------------------------------------------------------
var power: float = 2.0
var score: float = 0.0
var facing_angle_deg: float = 0.0
var current_speed: float = 0.0
var current_turn_rate: float = 0.0
var current_radius: float = 0.55
var boosting: bool = false
var alive: bool = true
var arena_radius: float = 120.0
var soft_zone_inner: float = 112.0
var id: int = -1

# --- steering interface (§8.1: player and AI both use this) ---------------
var _steer_target: Vector3 = Vector3.ZERO
var _has_steer_target: bool = false
var _boost_requested: bool = false
## §3.4 mote shedding: drained power accumulates until it equals one mote's
## worth (drain rate / motes per second), then a mote is emitted.
var _mote_accumulator: float = 0.0

var _can_read_input: bool = false
var _segments_target: int = 6
var _segments_current: int = 0
## §8.5 LOD: body-position updates every Nth physics tick (1 = every tick;
## distant AI use ai_far_body_stride).
var body_tick_stride: int = 1
var _body_tick_counter: int = 0
## The distance-sampled trail. Capacity = max_history_points (§6.2).
var history: PositionHistory = null


func _ready() -> void:
	if config == null:
		config = load("res://resources/config/snake_player.tres")
	_validate_config()
	arena_radius = _balance().arena_radius
	soft_zone_inner = arena_radius - _balance().soft_zone_width
	power = config.start_power
	history = PositionHistory.new(config.max_history_points, config.max_segment_count)
	body = SnakeBody.new()
	body.setup(self)
	_segments_target = _segments_for_power(power)
	_segments_current = _segments_target
	body.spawn_segments(_segments_target)
	_add_head_area()
	_update_derived_stats()


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_tick_movement(delta)
	_tick_boost(delta)
	_update_derived_stats()
	# §8.5 LOD: distant AI update body positions every Nth tick.
	_body_tick_counter += 1
	if _body_tick_counter >= body_tick_stride:
		_body_tick_counter = 0
		body.tick()


## Player/AI steering API: a world-space XZ point to head toward. ZERO
## clears the target (coast straight).
func set_steer_target(target: Vector3) -> void:
	if target == Vector3.ZERO:
		_has_steer_target = false
		return
	_steer_target = Vector3(target.x, 0.0, target.z)
	_has_steer_target = true


func set_boost(active: bool) -> void:
	_boost_requested = active


func head_position() -> Vector3:
	return global_position


## Live segment count (growth eases in; the target lags the curve).
func segment_count() -> int:
	return _segments_current


## Unit XZ vector of the current facing angle (0 = +Z, positive toward +X).
func facing_vector() -> Vector3:
	return Vector3(sin(deg_to_rad(facing_angle_deg)), 0.0, cos(deg_to_rad(facing_angle_deg)))


func head_forward() -> Vector3:
	return MathUtil.angle_deg_to_xz_direction(facing_angle_deg)


func _balance() -> GameBalanceConfig:
	# Cache not needed (autoload lookup is cheap and out of hot loop).
	return load("res://resources/config/game_balance.tres")


func _validate_config() -> void:
	# Guard the §6.3 invariant early: sample spacing must be smaller than
	# the smallest segment spacing we can produce, or body reads can stall.
	var worst_radius: float = config.head_radius * pow(maxf(1.0, config.start_power), config.radius_power_exponent)
	var spacing: float = config.segment_spacing_radius_factor * worst_radius
	if config.history_sample_distance >= spacing * 0.5:
		push_error("[SnakeController] history_sample_distance (%.3f) too large vs segment spacing (%.3f) — increase history_sample_distance headroom in config." % [config.history_sample_distance, spacing])


func _tick_movement(delta: float) -> void:
	var steer: Vector3 = _resolve_steer_input()
	if steer != Vector3.ZERO:
		var desired_angle: float = MathUtil.xz_direction_to_angle_deg(steer)
		var max_turn: float = current_turn_rate * delta
		facing_angle_deg = MathUtil.move_toward_angle_deg(facing_angle_deg, desired_angle, max_turn)
	# Speed with boost + stat multipliers + soft-zone slow.
	var speed: float = current_speed * (config.boost_multiplier if boosting else 1.0)
	speed *= stat_stack.get_multiplier(STAT_SPEED)
	speed *= _soft_zone_factor()
	var move: Vector3 = MathUtil.angle_deg_to_xz_direction(facing_angle_deg) * speed * delta
	# §3.5: the soft zone pushes the head inward, scaled by depth (full
	# strength at the wall). Gentle by design — it steers drifters back,
	# it never traps anyone against the boundary.
	var radial: float = global_position.length()
	if radial > soft_zone_inner and radial > 0.0001:
		var push: float = _balance().soft_zone_push_strength * _soft_zone_depth(radial) * delta
		move -= global_position / radial * push
	global_position = _clamp_to_arena(global_position + move)
	history.push(global_position, config.history_sample_distance)


## Trail accessors for the body pipeline (and tests).
func get_history() -> PositionHistory:
	return history


## Force-writes a trail sample (spawn trails, before any movement exists).
func body_push_direct(pos: Vector3) -> void:
	history.push_force(pos)


## Steering comes from the driver (player/AI) via set_steer_target; the
## controller never reads Input directly.
func _resolve_steer_input() -> Vector3:
	if not _has_steer_target:
		return Vector3.ZERO
	return (_steer_target - global_position) * Vector3(1, 0, 1)


## §3.5 soft zone: slow 0.85x toward the wall, push inward; hard wall
## clamps the outward velocity component away while tangential movement
## keeps sliding. Applied as a position clamp + speed factor (AI treats
## the zone as hazard in Phase 5).
var _was_in_soft_zone: bool = false


func _soft_zone_edge(r: float) -> void:
	var in_zone: bool = r >= soft_zone_inner
	if in_zone and not _was_in_soft_zone:
		wall_hit.emit(self)
	_was_in_soft_zone = in_zone


## §3.6 shrink: the arena owns the live radius; snakes follow it.
func set_arena_radius(r: float) -> void:
	arena_radius = r
	soft_zone_inner = r - _balance().soft_zone_width


func _soft_zone_factor() -> float:
	var r: float = global_position.length()
	_soft_zone_edge(r)

	var soft_start: float = soft_zone_inner
	if r < soft_start:
		return 1.0
	# §3.5: at (or beyond, mid-shrink) the wall the factor floors at the
	# soft-zone minimum — NEVER zero. The clamp kills the outward velocity
	# component; tangential movement must keep sliding ("slide along it").
	# A zero factor froze wall-pinned snakes alive forever (caught by the
	# Phase 5 verify flake: an AI travelled 0.0 units for 6+ s).
	var depth: float = clampf(
		(r - soft_start) / maxf(0.0001, arena_radius - soft_start), 0.0, 1.0)
	return 1.0 - (1.0 - _balance().soft_zone_slow_multiplier) * depth


## §3.5: soft-zone depth in [0, 1] (0 = inner edge, 1 = wall). Shared by
## the slow curve and the inward push.
func _soft_zone_depth(r: float) -> float:
	if r <= soft_zone_inner:
		return 0.0
	return clampf(
		(r - soft_zone_inner) / maxf(0.0001, arena_radius - soft_zone_inner), 0.0, 1.0)



func _clamp_to_arena(pos: Vector3) -> Vector3:
	var horiz: Vector3 = Vector3(pos.x, 0.0, pos.z)
	var r: float = horiz.length()
	if r > arena_radius and r > 0.0001:
		var clamped: Vector3 = horiz / r * arena_radius
		# Sliding preserves lateral speed; the head hugs the wall.
		return Vector3(clamped.x, 0.0, clamped.z)
	return Vector3(pos.x, 0.0, pos.z)


func _tick_boost(delta: float) -> void:
	# Boost active = driver wants it AND power allows (§3.4).
	var want: bool = _boost_requested
	if want and config.boost_mode == SnakeConfig.BoostMode.DRAIN:
		want = power > config.min_boost_power
	if want != boosting:
		boosting = want
		boosted_changed.emit(boosting)
		TestSignalHost.relay(get_instance_id(), &"boosted_changed", boosting)
	if not boosting:
		return
	if config.boost_mode == SnakeConfig.BoostMode.DRAIN:
		var drain: float = config.boost_power_drain * delta
		var new_power: float = maxf(config.min_boost_power, power - drain)
		if new_power != power:
			var drained: float = power - new_power
			power = new_power
			power_changed.emit(power)
			TestSignalHost.relay(get_instance_id(), &"power_changed", power)
			_update_derived_stats()
			# §3.4: drained power is lost mass — the body shrinks (this is
			# the risk half of the boost loop).
			_sync_segment_target()
			# §3.4: ...and is shed behind the snake as corpse motes, one
			# mote per (drain / motes_per_second) power, so the arena
			# economy stays fed. Arena wires this to CollectibleManager.
			_mote_accumulator += drained
			_emit_boost_motes()


## Emits whole motes from the accumulator. Each mote carries exactly
## boost_power_drain / boost_motes_per_second power (conservation: shed
## power always equals drained power, modulo one partial mote).
func _emit_boost_motes() -> void:
	var per_mote: float = config.boost_power_drain / maxf(0.1, config.boost_mote_emission_rate)
	while _mote_accumulator >= per_mote:
		_mote_accumulator -= per_mote
		var back: Vector3 = Vector3(-sin(deg_to_rad(facing_angle_deg)), 0.0, -cos(deg_to_rad(facing_angle_deg)))
		var lateral: Vector3 = Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
		# Drop past the collect radius (radius + margin): boost_mote_drop_distance
		# guarantees the snake can't instantly re-collect its own shed power.
		var drop_dist: float = current_radius * 1.4 + config.boost_mote_drop_distance
		var pos: Vector3 = global_position + back * drop_dist + lateral
		boost_mote_emitted.emit(pos, per_mote)


## §3.1/§3.2 power curves — recomputed after any power change.
func _update_derived_stats() -> void:
	var p: float = maxf(1.0, power)
	var p_curve: float = 1.0 - config.speed_curve_strength * (1.0 - exp(-p / config.speed_curve_scale))
	current_speed = maxf(config.min_move_speed, config.base_move_speed * p_curve)
	var turn_curve: float = clampf(
		1.0 - config.turn_curve_strength * (log(p + 1.0) / log(config.turn_curve_scale_log)),
		config.turn_curve_min_multiplier, 1.0)
	current_turn_rate = config.base_turn_rate * turn_curve
	current_turn_rate *= config.boost_turn_penalty if boosting else 1.0
	current_turn_rate *= stat_stack.get_multiplier(STAT_TURN)
	# §6.3: min turn radius = current_radius * 1.15 -> cap turn rate.
	current_radius = config.head_radius * pow(p, config.radius_power_exponent) * stat_stack.get_multiplier(STAT_RADIUS)
	var min_turn_radius: float = config.min_turn_radius_factor * current_radius
	if min_turn_radius > 0.0:
		current_turn_rate = minf(current_turn_rate, rad_to_deg(current_speed / min_turn_radius))


## §3.2 growth math: segments from power, capped.
func _segments_for_power(p: float) -> int:
	return clampi(config.start_segment_count + int(floor(p / config.segments_per_power)), config.start_segment_count, config.max_segment_count)


## Applies a power delta (collectibles, absorption). Positive grows the
## body smoothly (segments ease in, §6.2); negative shrinks (scale-down
## + pool return, Phase 6 uses this for boost? No — boost drains power but
## power floor keeps us above shrink here; absorb-shrink arrives Phase 6).
func add_power(delta: float) -> void:
	power = maxf(0.0, power + delta)
	power_changed.emit(power)
	TestSignalHost.relay(get_instance_id(), &"power_changed", power)
	_update_derived_stats()
	_sync_segment_target()


## Recomputes the segment target from power and hands any change to the
## body (grows smoothly, shrinks with a scale-down).
func _sync_segment_target() -> void:
	var target: int = _segments_for_power(power)
	if target == _segments_target:
		return
	_segments_target = target
	body.set_target_segment_count(target)


func get_segment_count() -> int:
	return body.get_segment_count() if body != null else 0


func display_power() -> int:
	return int(round(power))


## Power Tier = floor(log2(power)) (§3.2), for colour banding and AI
## matchmaking-style behaviour.
func power_tier() -> int:
	if power <= 0.0:
		return 0
	return int(floor(log(power) / log(2.0)))


## Called by the driver every physics tick before the controller's own
## tick would read input (player path). AI path is the same interface.
func can_read_input(flag: bool) -> void:
	_can_read_input = flag


func _add_head_area() -> void:
	var area: Area3D = Area3D.new()
	area.name = "HeadArea"
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "HeadSphere"
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = current_radius
	col.shape = sphere
	area.add_child(col)
	add_child(area)


## §45.5 revive path: restore at `new_power` at a safe point, body
## rebuilt from scratch (the corpse trail must not follow us), alive again.
func revive_at(pos: Vector3, new_power: float) -> void:
	if body != null:
		body.set_target_segment_count(0)
	power = maxf(config.start_power, new_power)
	alive = true
	boosting = false
	_boost_requested = false
	_has_steer_target = false
	_mote_accumulator = 0.0
	global_position = Vector3(pos.x, 0.0, pos.z)
	stat_stack.clear()
	if history != null:
		history.reset(global_position)
	_update_derived_stats()
	_segments_target = _segments_for_power(power)
	if body != null:
		body.spawn_segments(_segments_target)
	_sync_segment_target()
	power_changed.emit(power)
	TestSignalHost.relay(get_instance_id(), &"power_changed", power)


## Human/debug-friendly state dump (10 Hz use, not hot path).
func debug_line() -> String:
	return "%s pwr=%.1f tier=%d len=%d speed=%.2f turn=%.0f r=%.2f boost=%s pos=(%.1f, %.1f)" % [
		snake_name, power, power_tier(), get_segment_count(), current_speed,
		current_turn_rate, current_radius, "Y" if boosting else "n",
		global_position.x, global_position.z]
