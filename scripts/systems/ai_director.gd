class_name AIDirector
extends Node
## §11/§8 — Owns the AI population: spawns the 8 AI snakes (§11), assigns
## personalities (§8.3/§8.4: difficulty via the MIX + starting power —
## rubber-banding is FORBIDDEN), hands out unique match names (§8.4), and
## measures the §8.5 budget (< 2.5 ms/frame for all AI combined).
##
## Placement: scene-level node created by arena.gd (decision #25).
##
## Owns: the AI registry, personality/name assignment, respawn scheduling
##       (§11: 2.5 s after death — deaths arrive in Phase 6), the rolling
##       AI-cost telemetry, and the world-query helpers the AIs call
##       (sense-limited; no omniscience, §8.4).
## Does NOT own: individual decisions (AIController), combat (Phase 6).
## Talks to: AIControllers (spawn/query), SpawnManager (positions),
##           CollectibleManager (clusters/motes), EventBus (deaths).

const AI_SCENE: PackedScene = preload("res://scenes/ai/ai_snake.tscn")
const NAMES_PATH: String = "res://resources/data/ai_names.txt"

const AI_PERSONALITY_SCENES: Dictionary = {
	"Collector": "res://resources/ai/ai_collector.tres",
	"Aggressive": "res://resources/ai/ai_aggressive.tres",
	"Defensive": "res://resources/ai/ai_defensive.tres",
	"Explorer": "res://resources/ai/ai_explorer.tres",
	"Opportunist": "res://resources/ai/ai_opportunist.tres",
}

@export var balance: GameBalanceConfig = preload("res://resources/config/game_balance.tres")

var collectibles: CollectibleManager = null
var spawn_manager: SpawnManager = null
var player_snake: SnakeController = null
var arena_owner: Node3D = null

var ai_controllers: Array[AIController] = []
var _used_names: Dictionary = {}  # match-scoped; names never reused
var _all_names: Array[String] = []
var _game_time: float = 0.0
var _pending_respawns: Array[float] = []

# §8.5 budget telemetry: per-frame sum of decision cost (rolling 60 frames).
var ai_ms_frame_history: Array[float] = []
var ai_ms_max: float = 0.0
var _frame_decide_us: int = 0


func _ready() -> void:
	_load_names()
	EventBus.game_state_changed.connect(_on_state_changed)


func _on_state_changed(_from: int, to: int) -> void:
	if to == GameManager.State.PLAYING:
		if ai_controllers.is_empty():
			_spawn_initial()


func tick(delta: float) -> void:
	_game_time += delta
	# Roll the decision-cost sample into the per-frame history.
	ai_ms_frame_history.append(float(_frame_decide_us) / 1000.0)
	_frame_decide_us = 0
	if ai_ms_frame_history.size() > 60:
		ai_ms_frame_history.pop_front()
		var m: float = 0.0
		for v in ai_ms_frame_history:
			m = maxf(m, v)
		ai_ms_max = m
	# §11: respawn 2.5 s after a death (deaths land in Phase 6; the path is
	# live and unit-tested now).
	for i in range(_pending_respawns.size() - 1, -1, -1):
		_pending_respawns[i] -= delta
		if _pending_respawns[i] <= 0.0:
			_pending_respawns.remove_at(i)
			_spawn_ai(false)


func _spawn_initial() -> void:
	var target: int = balance.ai_count
	for i in target:
		_spawn_ai(true)


## Spawns one AI. initial=true → free-growth-window distance (35); false →
## respawn distance (45, §11). Personality from the §8.4 mix; power from
## the configured spread; a unique match name.
func _spawn_ai(initial: bool) -> void:
	var spawn_min: float = balance.ai_initial_spawn_distance if initial else balance.ai_min_spawn_distance
	var pos: Vector3 = spawn_manager.find_ai_spawn_position(spawn_min)
	var ai: AIController = AI_SCENE.instantiate()
	ai.name = "AI_%d" % ai_controllers.size()
	# Wire BEFORE add_child: _ready runs on tree entry and needs these.
	ai.director = self
	var idx: int = ai_controllers.size() % maxi(1, balance.ai_personality_mix.size())
	var personality_name: String = balance.ai_personality_mix[idx]
	ai.personality = load(AI_PERSONALITY_SCENES[personality_name]) as AIPersonalityConfig
	ai.display_name = _take_name(ai._rng)
	arena_owner.add_child(ai)
	var snake: SnakeController = ai.get_node("Snake")
	snake.global_position = pos
	# §8.4: difficulty through the mix and starting power — never scaled to
	# the player (rubber-banding forbidden).
	snake.power = _rng_range(ai._rng, balance.ai_start_power_min, balance.ai_start_power_max)
	snake._update_derived_stats()
	snake._sync_segment_target()
	snake.boost_mote_emitted.connect(_on_ai_boost_mote)
	snake.died.connect(_on_ai_died)
	ai_controllers.append(ai)


func _rng_range(rng: RandomNumberGenerator, lo: float, hi: float) -> float:
	return lo + rng.randf() * (hi - lo)


## §3.4: AI-shed motes feed the same arena economy as the player's.
func _on_ai_boost_mote(pos: Vector3, power: float) -> void:
	collectibles.drop_mote(pos, power, 0.0)


func _on_ai_died(_snake: SnakeController) -> void:
	# §11: respawn 2.5 s after death. The controller is freed by the death
	# sequence (Phase 6); the registry entry is pruned there via snake_died.
	_pending_respawns.append(balance.ai_respawn_delay)


func _take_name(_rng: RandomNumberGenerator) -> String:
	var pool: Array[String] = _all_names.filter(func(n: String) -> bool: return not _used_names.has(n))
	if pool.is_empty():
		# Fallback: numeric suffix; the match never reuses a name.
		return "AI-%d" % ai_controllers.size()
	# Own seeded RNG: the AI's RNG may not be randomized yet (pre-_ready).
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var name: String = pool[rng.randi() % pool.size()]
	_used_names[name] = true
	return name


func _load_names() -> void:
	var file: FileAccess = FileAccess.open(NAMES_PATH, FileAccess.READ)
	if file == null:
		push_warning("[AIDirector] missing %s" % NAMES_PATH)
		return
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line != "" and not line.begins_with("#"):
			_all_names.append(line)


## Stamps a decision cost sample from one AI (called right after decide()).
func stamp_decide(us: int) -> void:
	_frame_decide_us += us


## §8.5 budget scheduler: an AI asks before deciding. When this frame's
## accumulated AI cost already consumed 60% of the budget, the decision is
## deferred to a later frame (the AI retries next tick). This bounds the
## worst-case frame regardless of phase clustering — random stagger alone
## can still land several 10 Hz decisions on one frame (caught live:
## 3.78 ms spike when all 8 AIs decided together).
func can_afford_decide(us_hint: int) -> bool:
	var projected: float = float(_frame_decide_us + maxi(0, us_hint)) / 1000.0
	return projected < balance.ai_frame_budget_ms * 0.6


func now() -> float:
	return _game_time


# --- world-query helpers (sense-limited, §8.4) -----------------------------

## All live snakes (excluding `self_ai`) within `radius` of `origin`, as
## [{pos, power, facing, speed, radius}]. Includes the player.
func snakes_near(origin_snake: SnakeController, radius: float, self_ai: AIController) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if player_snake != null and player_snake != origin_snake and player_snake.alive:
		_push_snake(out, origin_snake, player_snake, radius)
	for ai in ai_controllers:
		if ai == self_ai or ai.snake == null or ai.snake == origin_snake or not ai.snake.alive:
			continue
		_push_snake(out, origin_snake, ai.snake, radius)
	return out


func _push_snake(out: Array[Dictionary], origin: SnakeController, other: SnakeController, radius: float) -> void:
	if origin.global_position.distance_to(other.global_position) > radius:
		return
	out.append({
		"pos": other.global_position,
		"power": other.power,
		"facing": other.facing_angle_deg,
		"speed": other.current_speed,
		"radius": other.current_radius,
	})


## Collectible clusters within `radius` of `pos`:
## [{pos, power, score, count}] — the TOP 5 by value, grouped by proximity
## among themselves only. PERF (§8.5): the full O(n²) merge over every
## in-range collectible measured ~160 µs per call; top-5 selection is a
## single pass + 25 pairwise checks and is behaviourally equivalent for
## steering (the AI heads for the best pickups, not a census).
func clusters_near(pos: Vector3, radius: float) -> Array[Dictionary]:
	if collectibles == null:
		return []
	var hash: SpatialHash = collectibles._hash
	var ids: Array[int] = hash.query_radius(pos, radius)
	if ids.is_empty():
		return []
	# Untyped: holds [value, entry] pairs.
	var top: Array = []
	for id in ids:
		var node: CollectibleNode = collectibles._alive.get(id) as CollectibleNode
		if node == null or node.consumed:
			continue
		var value: float = node.power_value * 2.0 + node.score_value * 0.05
		var entry: Dictionary = {
			"pos": node.global_position,
			"power": node.power_value,
			"score": node.score_value,
			"count": 1,
		}
		_insert_top(top, entry, value, 5)
	# Merge the top entries by proximity (≤ 25 pairwise checks).
	var clusters: Array[Dictionary] = []
	for pair in top:
		var e: Dictionary = pair[1]
		var merged: bool = false
		for c in clusters:
			if (c["pos"] as Vector3).distance_to(e["pos"]) <= AIStateCollect.CLUSTER_RADIUS:
				var n: int = int(c["count"])
				c["pos"] = ((c["pos"] as Vector3) * n + (e["pos"] as Vector3)) / float(n + 1)
				c["power"] = float(c["power"]) + float(e["power"])
				c["score"] = float(c["score"]) + float(e["score"])
				c["count"] = n + 1
				merged = true
				break
		if not merged:
			clusters.append(e)
	return clusters



## Keeps the top `max_count` [value, entry] pairs in a sorted-by-value
## array. Single insertion pass; no full sort.
## NOTE: `out` MUST be an untyped Array (holds [value, entry] pairs) —
## inserting pairs into an Array[Dictionary] triggers a runtime type
## conversion error per insert (~50 µs each, caught by profiling).
func _insert_top(out: Array, entry: Dictionary, value: float, max_count: int) -> void:
	var pos: int = 0
	while pos < out.size() and float(out[pos][0]) >= value:
		pos += 1
	if pos >= max_count:
		return
	out.insert(pos, [value, entry])
	if out.size() > max_count:
		out.pop_back()


func motes_near(pos: Vector3, radius: float) -> Array[Dictionary]:
	return collectibles.get_motes_near(pos, radius) if collectibles != null else []


## AVOID_WALL context: inside the soft zone now, or predicted to enter it
## within 1.2 s.
func wall_info(snake: SnakeController) -> Dictionary:
	var centre_dist: float = snake.global_position.length()
	var soft_inner: float = balance.arena_radius - balance.soft_zone_width
	var inside_soft: bool = centre_dist >= soft_inner
	var predicted: Vector3 = snake.global_position + snake.facing_vector() * snake.current_speed * 1.2
	var predicted_out: bool = predicted.length() >= soft_inner
	return {
		"center_dist": centre_dist,
		"soft_inner": soft_inner,
		"radius": balance.arena_radius,
		"inside_soft": inside_soft,
		"predicted_out": predicted_out,
	}


## AVOID_BODY probe: samples the probe path (lookahead seconds of travel)
## against nearby snakes' trails; returns [{pos, radius, weight}] hits.
##
## PERF (§8.5): cursor-based read_at_arc sampling measured ~0.9 ms/decision
## (thousands of cursor ops across 9 snakes × 10 Hz). This version walks
## raw trail samples (no cursors, no side effects) with a head-distance
## prefilter and a recent-trail window, earlying out on the first hit.
func body_probe(snake: SnakeController, lookahead: float) -> Array[Dictionary]:
	var probe_len: float = snake.current_speed * lookahead
	if probe_len <= 0.0:
		return []
	var fwd: Vector3 = snake.facing_vector()
	var my_r: float = snake.current_radius
	var head: Vector3 = snake.global_position
	var probe_points: Array[Vector3] = []
	for step in range(1, 5):
		probe_points.append(head + fwd * (probe_len * float(step) / 4.0))
	for other in _all_live_snakes():
		if other == snake:
			continue
		var other_r: float = other.current_radius + my_r + 0.35
		# Prefilter: only snakes whose HEAD is near the probe path can have
		# recent trail segments crossing it (recent = last ~30 units of
		# trail; older segments are handled by FLEE/threat logic).
		if other.global_position.distance_to(head) > probe_len + 15.0:
			continue
		if _hit_any(probe_points, other.global_position, other_r):
			return [{"pos": probe_points[0], "radius": 4.0, "weight": 1.0}]
		var history: PositionHistory = other.history
		if history == null or history.count < 2:
			continue
		var trail: Array = []
		history.trail_samples(trail, 300)
		# Stride 3 (0.3 units between checks) still catches every body
		# wider than ~0.6 units — bodies are 0.55+ radius.
		for i in range(0, trail.size(), 3):
			if _hit_any(probe_points, trail[i], other_r):
				return [{"pos": probe_points[0], "radius": 4.0, "weight": 1.0}]
	return []


func _hit_any(points: Array, pos: Vector3, radius: float) -> bool:
	for p in points:
		if (p as Vector3).distance_to(pos) < radius:
			return true
	return false


func _all_live_snakes() -> Array[SnakeController]:
	var out: Array[SnakeController] = []
	if player_snake != null and player_snake.alive:
		out.append(player_snake)
	for ai in ai_controllers:
		if ai.snake != null and ai.snake.alive:
			out.append(ai.snake)
	return out


# --- harness/test accessors -------------------------------------------------

func get_ai_count() -> int:
	return ai_controllers.size()


func near_ai_count() -> int:
	var count: int = 0
	for ai in ai_controllers:
		if not ai.is_lod_far():
			count += 1
	return count


func distinct_current_states() -> int:
	var names: Dictionary = {}
	for ai in ai_controllers:
		names[ai._fsm.current_name()] = true
	return names.size()
