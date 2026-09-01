class_name AIController
extends Node3D
## §8.1/§8.5 — One AI opponent. Owns decision-making and drives the SAME
## SnakeController the player uses through the SAME interface
## (set_steer_target / set_boost) — if the AI can do something the player
## physically cannot, that is a bug (§8.1).
##
## Humanizing features (§8.4):
##   reaction_delay — decisions read a STALE world snapshot (ring buffer)
##   aim_error_deg  — smoothed heading noise, resampled every 0.4 s
##   blunder_chance — every 2 s, may hold a bad heading for 0.5 s
##   sense limits   — snakes within 55, collectibles within 28. No omniscience.
##   rubber-banding — FORBIDDEN (§8.4). None exists here.
##
## LOD (§8.5): > ai_lod_distance from the player → 3 Hz decisions, body
## positions every 3rd tick, MultiMesh culled.
##
## Owns: the FSM + ContextSteering instances, the snapshot ring, waypoint
##       and timer memory, the personality, LOD state, decision cadence.
## Does NOT own: spawning (AIDirector), combat (Phase 6), the snake itself
##               (child scene — driven, not owned).
## Talks to: AIDirector (world data), its SnakeController (write only).

const SNAPSHOT_RING: int = 16

var director: AIDirector = null
var personality: AIPersonalityConfig = null
var snake: SnakeController = null
var display_name: String = "AI"

var _fsm: AIStateMachine = AIStateMachine.new()
var _steering: ContextSteering = ContextSteering.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Staggered decision cadence (§8.5).
var _decide_elapsed: float = 0.0
var _decide_interval: float = 0.1
# Stale-world snapshot ring (§8.4).
var _snapshots: Array[Dictionary] = []
var _snapshot_head: int = 0
# Memory: waypoint, recover, aim noise, blunder.
var _waypoint: Vector3 = Vector3.ZERO
var _waypoint_timer: float = 0.0
var _recover_until: float = 0.0
var _peak_power: float = 0.0
var _aim_error: float = 0.0
var _aim_error_target: float = 0.0
var _aim_error_timer: float = 0.0
var _blunder_timer: float = 0.0
var _blundering: bool = false
var _blunder_until: float = 0.0
var _blunder_heading: Vector3 = Vector3.FORWARD
# LOD state.
var _lod_far: bool = false
var _frame_counter: int = 0
# Telemetry (visited states + decision cost for the §8.5 budget).
var visited_states: Dictionary = {}
var last_decide_us: int = 0
# 5 Hz probe/mote refresh cache (see _sample_world).
var _probe_tick: int = 0
var _cached_probe: Array = []
var _cached_motes: Array = []


func _ready() -> void:
	_rng.randomize()
	snake = get_node_or_null("Snake") as SnakeController
	_decide_interval = 1.0 / maxf(0.1, director.balance.ai_decide_rate_hz)
	# §8.5 stagger: a random phase offset so AIs never all think at once.
	_decide_elapsed = _rng.randf() * _decide_interval
	_peak_power = snake.power if snake != null else 2.0
	# First waypoint: centre-biased random point (§8.2 WANDER).
	_pick_waypoint()
	# Immediately seed the snapshot ring so the first decision has data.
	_sample_world()
	# Distinct colour per AI so behaviour reads across the arena (§8.4).
	if snake != null:
		snake.body.mmi.material_override = _ai_body_material()


func _physics_process(delta: float) -> void:
	_frame_counter += 1
	if snake == null or not snake.alive:
		return
	# Mirror the player's state gate: AI only act while PLAYING.
	if not GameManager.is_in(GameManager.State.PLAYING):
		snake.set_steer_target(Vector3.ZERO)
		snake.set_boost(false)
		return
	_update_lod()
	# §8.5: distant AI decide at 3 Hz instead of 10 Hz.
	var interval: float = _decide_interval if not _lod_far else 1.0 / maxf(0.1, director.balance.ai_far_decide_rate_hz)
	_decide_elapsed += delta
	if _decide_elapsed >= interval:
		# §8.5 budget scheduler: defer when this frame's allowance is spent.
		if director.can_afford_decide(last_decide_us):
			_decide_elapsed = 0.0
			var t0: int = Time.get_ticks_usec()
			_decide()
			last_decide_us = Time.get_ticks_usec() - t0
			if director != null:
				director.stamp_decide(last_decide_us)
	# Collection is the same physics-tick query the player uses (§9:
	# head -> collectible = absorb; no AI-only shortcuts).
	_collect_nearby()


## One decision: sample the world, store the snapshot, then decide from
## the stale snapshot delayed by reaction_delay (§8.4).
func _decide() -> void:
	_sample_world()
	var ctx: Dictionary = _stale_context()
	if ctx.is_empty():
		return
	_update_timers(ctx)
	ctx["waypoint"] = _waypoint
	ctx["recover_active"] = _recover_until > ctx["now"]
	var state: AIState = _fsm.pick(ctx)
	visited_states[state.state_name] = int(visited_states.get(state.state_name, 0)) + 1
	var heading: Vector3 = _steering.pick(state.interest_dir(ctx), state.dangers(ctx), ctx["me_facing"])
	heading = _apply_humanizing(ctx, heading)
	if heading.length_squared() < 0.001:
		heading = ctx["me_facing"]
	snake.set_steer_target(snake.global_position + heading * 30.0)
	var want_boost: bool = state.boost_wanted(ctx)
	snake.set_boost(want_boost)


## §8.4 aim error + blunder, applied AFTER context steering.
func _apply_humanizing(ctx: Dictionary, heading: Vector3) -> Vector3:
	var now: float = ctx["now"]
	# Smoothed aim noise, resampled every ai_aim_error_resample seconds.
	_aim_error_timer += ctx["dt"]
	if _aim_error_timer >= director.balance.ai_aim_error_resample:
		_aim_error_timer = 0.0
		_aim_error_target = _rng.randf_range(-personality.aim_error_deg, personality.aim_error_deg)
	_aim_error = lerpf(_aim_error, _aim_error_target, 0.3)
	# Blunder: hold a deliberately bad heading for ai_blunder_hold seconds.
	_blunder_timer += ctx["dt"]
	if _blunder_timer >= director.balance.ai_blunder_interval:
		_blunder_timer = 0.0
		if _rng.randf() < personality.blunder_chance:
			_blundering = true
			_blunder_until = now + director.balance.ai_blunder_hold
			_blunder_heading = heading.rotated(Vector3.UP, deg_to_rad(_rng.randf_range(60.0, 120.0)))
	if _blundering:
		if now < _blunder_until:
			return _blunder_heading.normalized()
		_blundering = false
	return heading.rotated(Vector3.UP, deg_to_rad(_aim_error))


## Samples the CURRENT world into a timestamped snapshot and pushes it into
## the ring. Decisions read the entry delayed by reaction_delay.
## PERF (§8.5): the body probe and mote scan refresh at 5 Hz (every other
## decision) and reuse the previous result between refreshes — 0.2 s of
## staleness is below the reaction_delay the AI already perceives through.
func _sample_world() -> void:
	_probe_tick += 1
	var refresh_probe: bool = _probe_tick % 2 == 1
	if refresh_probe:
		_cached_probe = director.body_probe(snake, director.balance.ai_probe_lookahead)
		_cached_motes = director.motes_near(snake.global_position, director.balance.ai_scavenge_radius)
	var snapshot: Dictionary = {
		"t": director.now(),
		"me_pos": snake.global_position,
		"me_facing": snake.facing_vector(),
		"me_speed": snake.current_speed,
		"me_power": snake.power,
		"me_radius": snake.current_radius,
		"snakes": director.snakes_near(snake, personality.sense_radius, self),
		"clusters": director.clusters_near(snake.global_position, personality.collectible_sense_radius),
		"motes": _cached_motes,
		"wall": director.wall_info(snake),
		"body_hit": _cached_probe,
	}
	_snapshot_push(snapshot)


func _snapshot_push(entry: Dictionary) -> void:
	if _snapshots.size() < SNAPSHOT_RING:
		_snapshots.append(entry)
	else:
		_snapshots[_snapshot_head] = entry
	_snapshot_head = (_snapshot_head + 1) % SNAPSHOT_RING


## The stale context (§8.4): the newest snapshot at least reaction_delay
## seconds old, annotated with threat/prey classification + time state.
func _stale_context() -> Dictionary:
	if _snapshots.is_empty():
		return {}
	var now: float = director.now()
	var want_t: float = now - personality.reaction_delay
	var best: Dictionary = {}
	for s in _snapshots:
		if float(s["t"]) <= want_t:
			if best.is_empty() or float(s["t"]) > float(best["t"]):
				best = s
	if best.is_empty():
		best = _snapshots[_snapshots.size() - 1]
	var ctx: Dictionary = best.duplicate()
	ctx["now"] = now
	ctx["dt"] = get_physics_process_delta_time()
	ctx["rng"] = _rng
	ctx["personality"] = personality
	ctx["balance"] = director.balance
	# Classify sensed snakes into threats vs prey (§9 eat rule thresholds).
	var eat_ratio: float = snake.config.eat_power_ratio
	var threats: Array = []
	var prey: Array = []
	for s in ctx["snakes"]:
		var p: float = float(s["power"])
		if p > ctx["me_power"] * eat_ratio:
			threats.append(s)
		elif ctx["me_power"] >= p * eat_ratio:
			prey.append(s)
	ctx["threats"] = threats
	ctx["prey"] = prey
	return ctx


func _update_timers(ctx: Dictionary) -> void:
	# RECOVER trigger (§8.2): below 40% of peak (peak must be meaningful).
	_peak_power = maxf(_peak_power, snake.power)
	if _peak_power >= director.balance.ai_recover_peak_min \
			and snake.power < director.balance.ai_recover_power_fraction * _peak_power \
			and _recover_until <= ctx["now"]:
		_recover_until = ctx["now"] + director.balance.ai_recover_duration
	# WANDER waypoint re-pick (§8.2: every 3-6 s, personality-tuned).
	_waypoint_timer -= ctx["dt"]
	if _waypoint_timer <= 0.0:
		_pick_waypoint()


func _pick_waypoint() -> void:
	_waypoint_timer = _rng.randf_range(personality.wander_min_interval, personality.wander_max_interval)
	# Centre-biased random waypoint (§8.2): radius shrunk toward the middle.
	var ang: float = _rng.randf() * TAU
	var r: float = director.balance.arena_radius * 0.6 * sqrt(_rng.randf())
	_waypoint = Vector3(cos(ang) * r, 0.0, sin(ang) * r)


func _update_lod() -> void:
	if director == null or director.player_snake == null:
		return
	var dist: float = snake.global_position.distance_to(director.player_snake.global_position)
	var lod_dist: float = director.balance.ai_lod_distance
	# Hysteresis band of ±5 so AIs on the boundary don't flap between modes.
	var far_now: bool = _lod_far
	if not far_now and dist > lod_dist + 5.0:
		far_now = true
	elif far_now and dist < lod_dist - 5.0:
		far_now = false
	if far_now != _lod_far:
		_lod_far = far_now
		snake.body_tick_stride = director.balance.ai_far_body_stride if _lod_far else 1
		# §8.5: cull the MultiMesh of distant (off-screen) AI.
		snake.body.mmi.visible = not _lod_far
		if snake.body.head_mesh != null:
			snake.body.head_mesh.visible = not _lod_far


## Same collect query the player uses. Power goes to the snake; score to
## the AI's own score var (never the player's ScoreManager).
func _collect_nearby() -> void:
	if director == null or director.collectibles == null:
		return
	var radius: float = snake.current_radius + director.collectibles.balance.collect_radius_margin
	var pickups: Array[Dictionary] = director.collectibles.collect_near(snake.global_position, radius)
	# §10 DOUBLER applies to AI collects too (same rules as the player).
	var mult: float = 1.0
	if director.powerup_manager != null:
		mult = director.powerup_manager.collect_multiplier(snake)
	for p in pickups:
		snake.add_power(float(p["power"]) * mult)
		snake.score += float(p["score"]) * mult


func is_lod_far() -> bool:
	return _lod_far


## Per-AI body material: same power-tier bands, distinct hue so each snake
## reads as an individual (§8.4 personality visibility comes later via rim
## lights, Phase 6).
func _ai_body_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 0.4
	return mat
