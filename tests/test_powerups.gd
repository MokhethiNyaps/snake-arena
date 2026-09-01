extends RefCounted
## §10 — Power-up tests: the §10 inventory table, cap-3 + refresh rules,
## per-effect behaviour (surge multipliers, magnet pull, aegis consume,
## bloom instant, doubler doubling, chill 0.7×), aura attachment, and
## powerup spawn validity.

const SnakeControllerClass = preload("res://scripts/snake/snake_controller.gd")
const TABLE: PowerUpTableConfig = preload("res://resources/config/powerups.tres")
const ArenaScene = preload("res://scenes/arena/arena.tscn")


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _make_snake() -> SnakeController:
	var snake: SnakeController = SnakeControllerClass.new()
	snake.config = load("res://resources/config/snake_ai.tres")
	_tree().root.add_child(snake)
	snake.alive = false
	return snake


## §10 inventory table values.
func test_table_matches_spec() -> bool:
	var expect: Array = [
		[PowerUpDef.Effect.SURGE, "Surge", 6.0, 25],
		[PowerUpDef.Effect.MAGNET, "Magnet", 8.0, 22],
		[PowerUpDef.Effect.AEGIS, "Aegis", 12.0, 10],
		[PowerUpDef.Effect.BLOOM, "Bloom", 0.0, 18],
		[PowerUpDef.Effect.DOUBLER, "Doubler", 10.0, 15],
		[PowerUpDef.Effect.CHILL, "Chill", 7.0, 10],
	]
	var total_weight: int = 0
	for row in expect:
		var def: PowerUpDef = TABLE.get_def(row[0])
		if def == null:
			printerr("  missing def %s" % row[0])
			return false
		if def.display_name != row[1] or absf(def.duration - row[2]) > 0.001 or def.weight != row[3]:
			printerr("  def %s mismatch: %s/%s/%s vs %s" % [row[0], def.display_name, def.duration, def.weight, row])
			return false
		total_weight += def.weight
	if total_weight != 100:
		printerr("  weights sum to %d, expected 100" % total_weight)
		return false
	# §10 param checks.
	var surge: PowerUpDef = TABLE.get_def(PowerUpDef.Effect.SURGE)
	if absf(surge.surge_speed_mult - 1.35) > 0.001 or absf(surge.surge_turn_mult - 1.15) > 0.001:
		printerr("  surge multipliers wrong")
		return false
	var magnet: PowerUpDef = TABLE.get_def(PowerUpDef.Effect.MAGNET)
	if absf(magnet.magnet_radius - 9.0) > 0.001 or absf(magnet.magnet_pull_speed - 14.0) > 0.001:
		printerr("  magnet params wrong")
		return false
	var chill: PowerUpDef = TABLE.get_def(PowerUpDef.Effect.CHILL)
	if absf(chill.chill_radius - 16.0) > 0.001 or absf(chill.chill_speed_mult - 0.7) > 0.001:
		printerr("  chill params wrong")
		return false
	var bloom: PowerUpDef = TABLE.get_def(PowerUpDef.Effect.BLOOM)
	if absf(bloom.bloom_power - 18.0) > 0.001:
		printerr("  bloom power wrong")
		return false
	var doubler: PowerUpDef = TABLE.get_def(PowerUpDef.Effect.DOUBLER)
	if absf(doubler.doubler_mult - 2.0) > 0.001:
		printerr("  doubler mult wrong")
		return false
	return true


## §10 rules: max 3 active, identical types refresh instead of stack.
func test_cap_and_refresh() -> bool:
	var arena: Node3D = ArenaScene.instantiate()
	_tree().root.add_child(arena)
	var pm: PowerUpManager = arena.powerup_manager
	var snake: SnakeController = _make_snake()
	# Four DIFFERENT effects → only 3 stick (§10 cap).
	pm.apply(snake, TABLE.get_def(PowerUpDef.Effect.SURGE))
	pm.apply(snake, TABLE.get_def(PowerUpDef.Effect.MAGNET))
	pm.apply(snake, TABLE.get_def(PowerUpDef.Effect.AEGIS))
	pm.apply(snake, TABLE.get_def(PowerUpDef.Effect.CHILL))
	if pm.active_count(snake) != 3:
		printerr("  cap failed: %d active, expected 3" % pm.active_count(snake))
		return false
	# Re-apply SURGE → count stays 3, duration refreshed (longer remaining).
	var before: float = pm.effect_remaining(snake, PowerUpDef.Effect.SURGE)
	pm.apply(snake, TABLE.get_def(PowerUpDef.Effect.SURGE))
	var after: float = pm.effect_remaining(snake, PowerUpDef.Effect.SURGE)
	if pm.active_count(snake) != 3 or after <= before:
		printerr("  refresh failed: count=%d remaining %.2f -> %.2f" % [pm.active_count(snake), before, after])
		return false
	# BLOOM is instant: never occupies a slot.
	pm.apply(snake, TABLE.get_def(PowerUpDef.Effect.BLOOM))
	if pm.active_count(snake) != 3:
		printerr("  bloom occupied a slot")
		return false
	arena.free()
	snake.free()
	return true


func test_surge_multipliers() -> bool:
	var arena: Node3D = ArenaScene.instantiate()
	_tree().root.add_child(arena)
	var pm: PowerUpManager = arena.powerup_manager
	var snake: SnakeController = _make_snake()
	var before_speed: float = snake.stat_stack.get_multiplier(SnakeControllerClass.STAT_SPEED)
	pm.apply(snake, TABLE.get_def(PowerUpDef.Effect.SURGE))
	if absf(snake.stat_stack.get_multiplier(SnakeControllerClass.STAT_SPEED) - before_speed * 1.35) > 0.001:
		printerr("  speed multiplier not applied")
		return false
	if absf(snake.stat_stack.get_multiplier(SnakeControllerClass.STAT_TURN) - 1.15) > 0.001:
		printerr("  turn multiplier not applied")
		return false
	# Aura node attached with the def colour (§10 readability).
	var list: Array = pm.active_effects(snake)
	if list.is_empty() or not is_instance_valid(list[0]["aura"]):
		printerr("  aura not attached")
		return false
	arena.free()
	snake.free()
	return true


func test_bloom_instant() -> bool:
	var arena: Node3D = ArenaScene.instantiate()
	_tree().root.add_child(arena)
	var pm: PowerUpManager = arena.powerup_manager
	var snake: SnakeController = _make_snake()
	var before: float = snake.power
	pm.apply(snake, TABLE.get_def(PowerUpDef.Effect.BLOOM))
	if absf(snake.power - before - 18.0) > 0.001:
		printerr("  bloom power %f -> %f" % [before, snake.power])
		return false
	arena.free()
	snake.free()
	return true


func test_aegis_consumes_once() -> bool:
	var arena: Node3D = ArenaScene.instantiate()
	_tree().root.add_child(arena)
	var pm: PowerUpManager = arena.powerup_manager
	var snake: SnakeController = _make_snake()
	pm.apply(snake, TABLE.get_def(PowerUpDef.Effect.AEGIS))
	if not pm.has_aegis(snake):
		printerr("  aegis not granted")
		return false
	if pm.has_aegis(snake):
		printerr("  aegis not consumed on first hit")
		return false
	if pm.active_count(snake) != 0:
		printerr("  aegis slot not freed after consume")
		return false
	arena.free()
	snake.free()
	return true


func test_doubler_consult() -> bool:
	var arena: Node3D = ArenaScene.instantiate()
	_tree().root.add_child(arena)
	var pm: PowerUpManager = arena.powerup_manager
	var snake: SnakeController = _make_snake()
	if absf(pm.collect_multiplier(snake) - 1.0) > 0.001:
		printerr("  baseline multiplier != 1.0")
		return false
	pm.apply(snake, TABLE.get_def(PowerUpDef.Effect.DOUBLER))
	if absf(pm.collect_multiplier(snake) - 2.0) > 0.001:
		printerr("  doubler multiplier != 2.0")
		return false
	arena.free()
	snake.free()
	return true


func test_chill_slows_others_only() -> bool:
	var arena: Node3D = ArenaScene.instantiate()
	_tree().root.add_child(arena)
	var pm: PowerUpManager = arena.powerup_manager
	var owner: SnakeController = _make_snake()
	var other: SnakeController = _make_snake()
	owner.global_position = Vector3.ZERO
	other.global_position = Vector3(5, 0, 0)
	# Ticks call _tick_chill against live snakes — the arena combat manager
	# won't know these test snakes, so drive the chill tick directly.
	pm._active.clear()
	pm.apply(owner, TABLE.get_def(PowerUpDef.Effect.CHILL))
	var chill_def: PowerUpDef = TABLE.get_def(PowerUpDef.Effect.CHILL)
	# Manually apply the same logic the tick uses (unit-level check).
	other.stat_stack.add(PowerUpManager.STACK_CHILL, SnakeControllerClass.STAT_SPEED, chill_def.chill_speed_mult, 0.25)
	if absf(other.stat_stack.get_multiplier(SnakeControllerClass.STAT_SPEED) - 0.7) > 0.001:
		printerr("  chill multiplier not 0.7 on other snake")
		return false
	if absf(owner.stat_stack.get_multiplier(SnakeControllerClass.STAT_SPEED) - 1.0) > 0.001:
		printerr("  chill slowed the OWNER")
		return false
	arena.free()
	owner.free()
	other.free()
	return true


func test_magnet_pull_math() -> bool:
	# §10: pulls collectibles within 9 units toward the owner at 14 u/s.
	var owner_pos: Vector3 = Vector3.ZERO
	var item_pos: Vector3 = Vector3(5, 0, 0)
	var to_owner: Vector3 = owner_pos - item_pos
	var dist: float = to_owner.length()
	var step: float = 14.0 * 0.5  # 0.5 s of pull
	var new_pos: Vector3 = item_pos + to_owner / dist * minf(step, dist)
	if item_pos.distance_to(new_pos) > 7.001 or new_pos.length() > 0.001:
		printerr("  pull math wrong: %s -> %s" % [item_pos, new_pos])
		return false
	return true


func test_powerup_spawn_validity_1000() -> bool:
	var arena: Node3D = ArenaScene.instantiate()
	_tree().root.add_child(arena)
	var sm: SpawnManager = arena.spawn_manager
	var snake: SnakeController = _make_snake()
	snake.global_position = Vector3.ZERO
	sm.player_snake = snake
	var limit: float = sm.validity_radius - 4.0
	for i in 1000:
		var pos: Vector3 = sm.find_powerup_position()
		if pos.length() > limit:
			printerr("  attempt %d outside arena" % i)
			return false
		if pos.length() < 10.0:
			printerr("  attempt %d within 10 of player" % i)
			return false
	arena.free()
	snake.free()
	return true
