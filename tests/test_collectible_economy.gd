extends RefCounted
## Phase 3 economy tests: §11 pool prewarm, 420-population fill, §9A.5
## spawn validity (1000 attempts), the collect flow, §12.3 combo table,
## survival score, and §3.4 boost mote emission/decay.
##
## NOTE: these tests never touch GameManager state — they drive the arena
## systems directly (arena._physics_process is state-gated, so nothing ticks
## underneath the assertions).

const ArenaScene = preload("res://scenes/arena/arena.tscn")
const SnakeControllerClass = preload("res://scripts/snake/snake_controller.gd")

var _arena: Node3D = null
var _snake: SnakeController = null


func _get_arena() -> Node3D:
	if _arena == null:
		_arena = ArenaScene.instantiate()
		(Engine.get_main_loop() as SceneTree).root.add_child(_arena)
	return _arena


func _get_snake() -> SnakeController:
	if _snake == null:
		_snake = SnakeControllerClass.new()
		_snake.name = "EconomyTestSnake"
		_snake.config = load("res://resources/config/snake_player.tres")
		_snake.alive = false
		(Engine.get_main_loop() as SceneTree).root.add_child(_snake)
	return _snake


func _cleanup() -> void:
	if _arena != null and is_instance_valid(_arena):
		var cm: CollectibleManager = _arena.collectible_manager
		if cm != null:
			cm.clear_all()
		_arena.free()
	_arena = null
	if _snake != null and is_instance_valid(_snake):
		_snake.free()
	_snake = null


func test_pool_prewarm_counts() -> bool:
	_get_arena()
	if not ObjectPoolRegistry.has_pool(&"collectible") or ObjectPoolRegistry.inactive_count(&"collectible") + ObjectPoolRegistry.active_count(&"collectible") < 600:
		printerr("  collectible pool under-prewarmed")
		return false
	if not ObjectPoolRegistry.has_pool(&"collect_burst") or ObjectPoolRegistry.inactive_count(&"collect_burst") + ObjectPoolRegistry.active_count(&"collect_burst") < 40:
		printerr("  burst pool under-prewarmed")
		return false
	if not ObjectPoolRegistry.has_pool(&"score_label") or ObjectPoolRegistry.inactive_count(&"score_label") + ObjectPoolRegistry.active_count(&"score_label") < 30:
		printerr("  label pool under-prewarmed")
		return false
	_cleanup()
	return true


func test_initial_fill_reaches_420() -> bool:
	var arena: Node3D = _get_arena()
	var sm: SpawnManager = arena.spawn_manager
	var cm: CollectibleManager = arena.collectible_manager
	sm.initial_fill()
	if cm.non_mote_count() != cm.balance.target_collectible_count:
		printerr("  non-mote count %d != target %d" % [cm.non_mote_count(), cm.balance.target_collectible_count])
		return false
	if cm.rare_count() > cm.balance.max_rare_alive:
		printerr("  rare shards %d over cap %d" % [cm.rare_count(), cm.balance.max_rare_alive])
		return false
	# Every spawned collectible is inside the arena.
	for id in cm._alive:
		var node: CollectibleNode = cm._alive[id] as CollectibleNode
		if node.global_position.length() > cm.balance.arena_radius - 4.0 + 0.01:
			printerr("  collectible outside arena: %s" % node.global_position)
			return false
	_cleanup()
	return true


func test_spawn_validity_1000_attempts() -> bool:
	var arena: Node3D = _get_arena()
	var sm: SpawnManager = arena.spawn_manager
	var snake: SnakeController = _get_snake()
	snake.global_position = Vector3.ZERO
	sm.player_snake = snake
	var radius_limit: float = sm.balance.arena_radius - 4.0
	var min_dist: float = sm.balance.collectible_min_spawn_distance
	for i in 1000:
		var pos: Vector3 = sm.find_valid_collectible_position()
		if pos.length() > radius_limit:
			printerr("  attempt %d outside arena: %s" % [i, pos])
			return false
		if pos.length() < min_dist:
			printerr("  attempt %d within %f of player: %s" % [i, min_dist, pos])
			return false
	_cleanup()
	return true


func test_collect_flow_and_refill() -> bool:
	var arena: Node3D = _get_arena()
	var cm: CollectibleManager = arena.collectible_manager
	# Isolated flow: no fill spawns nearby to interfere with the query.
	var small: CollectibleDef = cm.table.get_def(CollectibleDef.Type.CELL_SMALL)
	var pos: Vector3 = Vector3(10.0, 0.0, 0.0)
	cm.spawn_collectible(small, pos)
	var pickups: Array[Dictionary] = cm.collect_near(pos + Vector3(0.4, 0.0, 0.0), 1.2)
	if pickups.size() != 1:
		printerr("  expected 1 pickup, got %d" % pickups.size())
		return false
	var p: Dictionary = pickups[0]
	if p["type"] != CollectibleDef.Type.CELL_SMALL or absf(float(p["power"]) - 1.0) > 0.001 or absf(float(p["score"]) - 10.0) > 0.001:
		printerr("  wrong pickup payload: %s" % str(p))
		return false
	# Second query finds nothing (absorbed).
	if cm.collect_near(pos, 1.2).size() != 0:
		printerr("  absorbed collectible still queryable")
		return false
	# Refill allowance: with a 1-population deficit, 1s accumulates 1 spawn.
	if cm.refill_accumulate(1.0) != 1:
		printerr("  refill allowance not granted")
		return false
	_cleanup()
	return true


func test_combo_table() -> bool:
	var sm: ScoreManager = ScoreManager.new()
	# Boxed clock: GDScript lambdas capture locals BY VALUE, so the
	# injectable clock must read through a mutable container.
	var clock_box: Array = [0]
	sm.clock_ms = func() -> int: return clock_box[0]
	# Collect 1: combo 1, mult 1.05 (§12.3 literal formula).
	var gain1: float = sm.on_collectible(10.0)
	if absf(gain1 - 10.5) > 0.001 or sm.combo != 1:
		printerr("  first collect: gain %.3f combo %d" % [gain1, sm.combo])
		return false
	# Collect 2 within window: combo 2, mult 1.10.
	clock_box[0] = 500
	var gain2: float = sm.on_collectible(10.0)
	if absf(gain2 - 11.0) > 0.001 or sm.combo != 2:
		printerr("  second collect: gain %.3f combo %d" % [gain2, sm.combo])
		return false
	# Window (1.4 s) expired: combo resets to 1.
	clock_box[0] = 2100
	var gain3: float = sm.on_collectible(10.0)
	if absf(gain3 - 10.5) > 0.001 or sm.combo != 1:
		printerr("  after-window collect: gain %.3f combo %d" % [gain3, sm.combo])
		return false
	# Climb to combo 21 within the window: multiplier caps at 2.0.
	clock_box[0] = 3000
	var last_gain: float = 0.0
	for i in 20:
		clock_box[0] += 100
		last_gain = sm.on_collectible(10.0)
	if sm.combo != 21 or absf(last_gain - 20.0) > 0.001:
		printerr("  cap: combo %d last gain %.3f" % [sm.combo, last_gain])
		return false
	if absf(sm.combo_multiplier() - 2.0) > 0.001:
		printerr("  multiplier at combo 21 = %.3f" % sm.combo_multiplier())
		return false
	sm.free()
	return true


func test_survival_score() -> bool:
	var sm: ScoreManager = ScoreManager.new()
	sm.tick(2.0)
	if absf(sm.get_score() - 12.0) > 0.001:
		printerr("  2 s survival score = %.3f, expected 12.0" % sm.get_score())
		return false
	sm.free()
	return true


func test_boost_mote_emission() -> bool:
	var snake: SnakeController = _get_snake()
	snake.power = 12.0
	snake.facing_angle_deg = 0.0  # facing +Z
	snake.set_boost(true)
	var emissions: Array[Dictionary] = []
	snake.boost_mote_emitted.connect(func(pos: Vector3, p: float) -> void:
		emissions.append({"pos": pos, "power": p}))
	# 1.3 s of boost: drain 2.86 -> 5 whole motes at 0.55 each (2.75 shed,
	# 0.11 stays in the accumulator). Avoided exact multiples of 0.55 —
	# float drain (power - floor(power - drain)) never lands exactly.
	snake._tick_boost(1.3)
	if emissions.size() != 5:
		printerr("  expected 5 motes, got %d" % emissions.size())
		return false
	var facing: Vector3 = Vector3(0.0, 0.0, 1.0)
	var total: float = 0.0
	for e in emissions:
		total += float(e["power"])
		if absf(float(e["power"]) - 0.55) > 0.001:
			printerr("  mote power %.3f != 0.55" % float(e["power"]))
			return false
		# Motes land BEHIND the head (opposite the facing direction).
		var rel: Vector3 = (e["pos"] as Vector3) - snake.global_position
		if rel.dot(facing) > 0.0:
			printerr("  mote in front of head: %s" % str(rel))
			return false
	if total > 2.2 * 1.3 + 0.001:
		printerr("  shed total %.3f exceeds drained %.3f" % [total, 2.2 * 1.3])
		return false
	# Another 0.3 s: drain 0.66 + 0.11 carried -> 1 mote, 0.22 remains.
	emissions.clear()
	snake._tick_boost(0.3)
	if emissions.size() != 1:
		printerr("  second burst: expected 1 mote, got %d" % emissions.size())
		return false
	_cleanup()
	return true


func test_mote_decay() -> bool:
	var arena: Node3D = _get_arena()
	var cm: CollectibleManager = arena.collectible_manager
	cm.drop_mote(Vector3(5.0, 0.0, 5.0), 5.0, 0.0)
	if cm.mote_count() != 1:
		printerr("  mote did not spawn")
		return false
	# §3.3: corpse motes decay after 14 s.
	cm.tick(15.0)
	if cm.mote_count() != 0:
		printerr("  mote did not decay after 15 s")
		return false
	_cleanup()
	return true


func test_surge_event_and_claim() -> bool:
	var arena: Node3D = _get_arena()
	var sm: SpawnManager = arena.spawn_manager
	var cm: CollectibleManager = arena.collectible_manager
	# Drive game time across the §3.6 surge threshold (60 s).
	sm._next_surge_time = sm.balance.ramp_end_time
	sm._game_time = sm.balance.ramp_end_time - 0.1
	sm.tick(0.2)
	if not sm._surge_active:
		printerr("  surge did not start at threshold")
		return false
	if not sm._beam.visible:
		printerr("  surge beam not visible")
		return false
	# Stagger spawns (~1.23 s for 40 + 1 rare at 0.03 s spacing).
	for i in 60:
		sm.tick(0.05)
	if sm._surge_active:
		printerr("  surge never finished")
		return false
	if cm.non_mote_count() != sm.balance.surge_collectible_count + sm.balance.surge_rare_count:
		printerr("  surge spawned %d, expected %d" % [
			cm.non_mote_count(), sm.balance.surge_collectible_count + sm.balance.surge_rare_count])
		return false
	# §12.3: first claim wins; a second claim gets nothing.
	# Re-arm a surge to test claiming (state was consumed above).
	sm._start_surge()
	var claim_pos: Vector3 = sm._surge_pos + Vector3(5.0, 0.0, 0.0)
	if not sm.try_claim_surge(claim_pos):
		printerr("  first surge claim refused")
		return false
	if sm.try_claim_surge(claim_pos):
		printerr("  second surge claim granted")
		return false
	_cleanup()
	return true
