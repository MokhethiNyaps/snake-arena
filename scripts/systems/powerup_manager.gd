class_name PowerUpManager
extends Node
## §10 — Power-ups. Applies timed effects as stackable-but-capped modifiers
## on each snake's StatModifierStack; adding a power-up requires ZERO
## changes to SnakeController. Scene-level node created by arena.gd
## (decision #25).
##
## Effects (§10):
##   SURGE   +35% speed / +15% turn (stat stack)
##   MAGNET  pulls collectibles within 9 u at 14 u/s (manager moves them)
##   AEGIS   one free death, consumed on lethal hit (CombatManager consults)
##   BLOOM   instant +18 power
##   DOUBLER 2× score+power from collectibles (collect call sites consult)
##   CHILL   opponents within 16 u move at 0.7× (stat stack on OTHERS)
## Rules: max 3 active per snake; identical types refresh duration; every
## active effect wears a distinct aura colour (§10 readability).
##
## Owns: effect state, aura visuals, powerup spawn/refill (§11: 5 alive).
## Does NOT own: spawn validity (SpawnManager), combat (consults aegis).
## Talks to: snakes (stat stacks), CollectibleManager (magnet), arena.

const PICKUP_SCENE: PackedScene = preload("res://scenes/powerups/powerup_pickup.tscn")
const POOL_POWERUP: StringName = &"powerup_pickup"

const STACK_SURGE: StringName = &"pu_surge"
const STACK_CHILL: StringName = &"pu_chill"

@export var table: PowerUpTableConfig = preload("res://resources/config/powerups.tres")

var collectibles: CollectibleManager = null
var spawn_manager: SpawnManager = null
var combat_manager: CombatManager = null
var arena_owner: Node = null
var player_snake: SnakeController = null

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pickups: Array[Dictionary] = []   # {node, def}
var _refill_accumulator: float = 0.0
# Per-snake active effects: snake_id -> [{def, until, aura}]
var _active: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	ObjectPoolRegistry.register_pool(POOL_POWERUP, PICKUP_SCENE, 12)
	EventBus.game_state_changed.connect(_on_state_changed)


func _on_state_changed(_from: int, to: int) -> void:
	if to == GameManager.State.PLAYING:
		# §11: initial 5 power-ups immediately.
		for i in table.target_alive_count:
			_spawn_pickup()


func tick(delta: float) -> void:
	_tick_effects(delta)
	_tick_magnet(delta)
	_tick_chill(delta)
	_tick_pickups()
	# §11 refill: 5 alive, one per refill_interval.
	if _pickups.size() < table.target_alive_count:
		_refill_accumulator += delta
		if _refill_accumulator >= table.refill_interval:
			_refill_accumulator = 0.0
			_spawn_pickup()


# --- spawning ---------------------------------------------------------------

func _spawn_pickup() -> void:
	var pos: Vector3 = spawn_manager.find_powerup_position()
	var def: PowerUpDef = table.weighted_pick(_rng)
	var node: Node3D = ObjectPoolRegistry.acquire(POOL_POWERUP)
	node.set_meta("def", def)
	arena_owner.add_child(node)
	node.global_position = pos
	node.set_meta("active", true)
	_pickups.append({"node": node, "def": def})


## Harness/test aid: spawn a specific effect at a position.
func spawn_at(pos: Vector3, effect: PowerUpDef.Effect) -> Node3D:
	var def: PowerUpDef = table.get_def(effect)
	var node: Node3D = ObjectPoolRegistry.acquire(POOL_POWERUP)
	node.set_meta("def", def)
	arena_owner.add_child(node)
	node.global_position = pos
	node.set_meta("active", true)
	_pickups.append({"node": node, "def": def})
	return node


## Pickup detection: any live snake head overlapping a pickup consumes it.
func _tick_pickups() -> void:
	var snakes: Array[SnakeController] = _live_snakes()
	for i in range(_pickups.size() - 1, -1, -1):
		var entry: Dictionary = _pickups[i]
		var node: Node3D = entry["node"]
		var def: PowerUpDef = entry["def"]
		for s in snakes:
			if s.global_position.distance_to(node.global_position) <= s.current_radius + 1.2:
				apply(s, def)
				EventBus.powerup_collected.emit(def.effect)
				_pickups.remove_at(i)
				node.set_meta("active", false)
				ObjectPoolRegistry.release(POOL_POWERUP, node)
				break


# --- effects ----------------------------------------------------------------

## The single apply entry: identical types refresh (§10), cap enforced.
func apply(snake: SnakeController, def: PowerUpDef) -> void:
	var id: int = snake.get_instance_id()
	var list: Array = _active.get(id, [])
	if list.is_empty():
		_active[id] = list
	# Instant effect: never occupies a slot.
	if def.duration <= 0.0:
		if def.effect == PowerUpDef.Effect.BLOOM:
			snake.add_power(def.bloom_power)
		EventBus.powerup_collected.emit(def.effect)
		return
	# Refresh identical type.
	for e in list:
		if int(e["def"].effect) == def.effect:
			e["until"] = now() + def.duration
			EventBus.powerup_collected.emit(def.effect)
			return
	# Cap: drop the oldest when at max (§10).
	if list.size() >= table.max_active_powerups:
		_remove_effect(list[0])
		list.remove_at(0)
	var entry: Dictionary = {"def": def, "until": now() + def.duration, "aura": null}
	list.append(entry)
	_apply_start(snake, def)
	_attach_aura(snake, def, entry)
	EventBus.powerup_collected.emit(def.effect)


func _apply_start(snake: SnakeController, def: PowerUpDef) -> void:
	match def.effect:
		PowerUpDef.Effect.SURGE:
			snake.stat_stack.add(STACK_SURGE, SnakeController.STAT_SPEED, def.surge_speed_mult, def.duration)
			snake.stat_stack.add(STACK_SURGE, SnakeController.STAT_TURN, def.surge_turn_mult, def.duration)
		_:
			pass


func _remove_effect(entry: Dictionary) -> void:
	var def: PowerUpDef = entry["def"]
	var snake: SnakeController = entry.get("snake")
	if snake != null and def.effect == PowerUpDef.Effect.SURGE:
		snake.stat_stack.remove_all(STACK_SURGE)
	var aura: Node3D = entry.get("aura")
	if aura != null and is_instance_valid(aura):
		aura.queue_free()


func _attach_aura(snake: SnakeController, def: PowerUpDef, entry: Dictionary) -> void:
	entry["snake"] = snake
	var aura: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.2
	sphere.radial_segments = 10
	sphere.rings = 4
	aura.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(def.aura_color.r, def.aura_color.g, def.aura_color.b, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = def.aura_color
	mat.emission_energy_multiplier = 0.8
	aura.material_override = mat
	snake.add_child(aura)
	entry["aura"] = aura


func _tick_effects(delta: float) -> void:
	for id in _active.keys():
		var list: Array = _active[id]
		for i in range(list.size() - 1, -1, -1):
			var e: Dictionary = list[i]
			if float(e["until"]) <= now():
				_remove_effect(e)
				list.remove_at(i)
		# Aura follows the snake (scale with radius).
		for e in list:
			var aura: Node3D = e.get("aura")
			var snake: SnakeController = e.get("snake")
			if aura != null and is_instance_valid(aura) and snake != null:
				var r: float = maxf(snake.current_radius, 0.55) * 2.4
				aura.scale = Vector3(r, r, r)
		if list.is_empty():
			_active.erase(id)


## MAGNET: pull in-range collectibles toward the owner.
func _tick_magnet(delta: float) -> void:
	for id in _active.keys():
		for e in _active[id]:
			if int(e["def"].effect) != PowerUpDef.Effect.MAGNET:
				continue
			var owner: SnakeController = e.get("snake")
			if owner == null or not owner.alive:
				continue
			var def: PowerUpDef = e["def"]
			var ids: Array[int] = collectibles._hash.query_radius(owner.global_position, def.magnet_radius)
			for cid in ids:
				var node: CollectibleNode = collectibles._alive.get(cid) as CollectibleNode
				if node == null or node.consumed:
					continue
				var to_owner: Vector3 = owner.global_position - node.global_position
				var dist: float = to_owner.length()
				if dist < 0.01:
					continue
				var step: float = def.magnet_pull_speed * delta
				var new_pos: Vector3 = node.global_position + to_owner / dist * minf(step, dist)
				collectibles.move_collectible(cid, new_pos)


## CHILL: opponents within radius move at 0.7× (refreshed each tick).
func _tick_chill(delta: float) -> void:
	for id in _active.keys():
		for e in _active[id]:
			if int(e["def"].effect) != PowerUpDef.Effect.CHILL:
				continue
			var owner: SnakeController = e.get("snake")
			if owner == null or not owner.alive:
				continue
			var def: PowerUpDef = e["def"]
			for other in _live_snakes():
				if other == owner:
					continue
				if owner.global_position.distance_to(other.global_position) <= def.chill_radius:
					other.stat_stack.add(STACK_CHILL, SnakeController.STAT_SPEED, def.chill_speed_mult, 0.25)


# --- consults (combat + collect paths) ---------------------------------------

## CombatManager consult: aegis consumes one lethal hit (§10).
func has_aegis(snake: SnakeController) -> bool:
	var list: Array = _active.get(snake.get_instance_id(), [])
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		if int(e["def"].effect) == PowerUpDef.Effect.AEGIS:
			_remove_effect(e)
			list.remove_at(i)
			EventBus.powerup_collected.emit(PowerUpDef.Effect.AEGIS)
			return true
	return false


## Collect-site consult: DOUBLER multiplies collect payloads (§10).
func collect_multiplier(snake: SnakeController) -> float:
	var list: Array = _active.get(snake.get_instance_id(), [])
	for e in list:
		if int(e["def"].effect) == PowerUpDef.Effect.DOUBLER:
			return float(e["def"].doubler_mult)
	return 1.0


func active_effects(snake: SnakeController) -> Array:
	return _active.get(snake.get_instance_id(), [])


func active_count(snake: SnakeController) -> int:
	return (_active.get(snake.get_instance_id(), []) as Array).size()


## Test aid: remaining time of a specific effect on a snake, or -1.
func effect_remaining(snake: SnakeController, effect: PowerUpDef.Effect) -> float:
	var list: Array = _active.get(snake.get_instance_id(), [])
	for e in list:
		if int(e["def"].effect) == effect:
			return float(e["until"]) - now()
	return -1.0


func alive_pickup_count() -> int:
	return _pickups.size()


func now() -> float:
	# Injectable-free: arena-scoped clock via combat manager elapsed.
	if combat_manager != null:
		return combat_manager._elapsed
	return float(Time.get_ticks_msec()) / 1000.0


func _live_snakes() -> Array[SnakeController]:
	var out: Array[SnakeController] = []
	if combat_manager != null:
		out = combat_manager._live_snakes()
	return out
