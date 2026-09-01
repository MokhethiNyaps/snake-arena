class_name CollectibleManager
extends Node
## §3.3/§11 — Owns every live collectible: spawn/absorb, the collectible
## spatial hash, pooled VFX + floating labels, and the 420-alive top-up.
##
## Placement: a scene-level node created by arena.gd (NOT an autoload —
## decision #25: game-scoped economy state dies with the arena).
##
## Owns: the SpatialHash of collectibles, the alive registry, decay timers,
##       refill accumulator, and the pooled collect_burst/score_label pools.
## Does NOT own: where to spawn (SpawnManager decides positions), score and
##               combo math (ScoreManager), power application (the snake).
## Talks to: ObjectPoolRegistry (pools), EventBus (collectible_absorbed),
##           AudioManager (no — SFX is played by the collector so it can use
##           the combo pitch; VFX/labels are fired here).

const COLLECTIBLE_SCENE: PackedScene = preload("res://scenes/collectibles/collectible.tscn")
const BURST_SCENE: PackedScene = preload("res://scenes/vfx/collect_burst.tscn")
const LABEL_SCENE: PackedScene = preload("res://scenes/vfx/score_label.tscn")

const POOL_COLLECTIBLE: StringName = &"collectible"
const POOL_BURST: StringName = &"collect_burst"
const POOL_LABEL: StringName = &"score_label"

## §11 prewarm counts.
const PREWARM_COLLECTIBLES: int = 600
const PREWARM_BURSTS: int = 40
const PREWARM_LABELS: int = 30

## VFX bookkeeping (pool + time-to-release; release is manager-ticked so it
## is deterministic and headless-testable).
const BURST_LIFETIME: float = 0.6
const LABEL_LIFETIME: float = 0.75
const LABEL_RISE_SPEED: float = 1.4

@export var balance: GameBalanceConfig = preload("res://resources/config/game_balance.tres")
@export var table: CollectibleTable = preload("res://resources/config/collectibles.tres")

var _hash: SpatialHash = SpatialHash.new()
var _alive: Dictionary = {}  # instance_id -> CollectibleNode
var _refill_accumulator: float = 0.0
var _t: float = 0.0

# Per-instance VFX timers (parallel arrays, only active entries iterated).
var _burst_nodes: Array[Node] = []
var _burst_timers: Array[float] = []
var _label_nodes: Array[Node] = []
var _label_timers: Array[float] = []


func _ready() -> void:
	ObjectPoolRegistry.register_pool(POOL_COLLECTIBLE, COLLECTIBLE_SCENE, PREWARM_COLLECTIBLES)
	ObjectPoolRegistry.register_pool(POOL_BURST, BURST_SCENE, PREWARM_BURSTS)
	ObjectPoolRegistry.register_pool(POOL_LABEL, LABEL_SCENE, PREWARM_LABELS)


## Spawns one collectible of `def` at `pos` (SpawnManager decides where).
## Returns the live node, or null if the pool refused.
func spawn_collectible(def: CollectibleDef, pos: Vector3, power_override: float = -1.0, score_override: float = -1.0) -> CollectibleNode:
	var node: CollectibleNode = ObjectPoolRegistry.acquire(POOL_COLLECTIBLE) as CollectibleNode
	if node == null:
		return null
	node.activate(def, def.power if power_override < 0.0 else power_override, float(def.score) if score_override < 0.0 else score_override, pos)
	_alive[node.get_instance_id()] = node
	_hash.insert(node.get_instance_id(), pos)
	return node


## Drops a corpse mote (§3.3/§3.4/§9): variable power/score, decays.
func drop_mote(pos: Vector3, power: float, score: float) -> CollectibleNode:
	var mote_def: CollectibleDef = table.get_def(CollectibleDef.Type.CORPSE_MOTE)
	return spawn_collectible(mote_def, pos, power, score)


## Absorbs every collectible within `radius` of `pos`. Each absorbed entry
## is { type: Type, power: float, score: float, position: Vector3 }.
## The CALLER applies power/score (snake, ScoreManager) — this manager only
## removes from the world, fires VFX/label, and emits collectible_absorbed.
func collect_near(pos: Vector3, radius: float) -> Array[Dictionary]:
	var ids: Array[int] = _hash.query_radius(pos, radius)
	if ids.is_empty():
		return []
	var out: Array[Dictionary] = []
	for id in ids:
		var node: CollectibleNode = _alive.get(id) as CollectibleNode
		if node == null or node.consumed:
			continue
		out.append({
			"type": node.def.type,
			"power": node.power_value,
			"score": node.score_value,
			"position": node.global_position,
		})
		_fire_feedback(node.def, node.global_position, node.score_value)
		_absorb(node)
	return out


## Releases a live collectible back to the pool.
func _absorb(node: CollectibleNode) -> void:
	var id: int = node.get_instance_id()
	_hash.remove(id)
	_alive.erase(id)
	node.deactivate()
	ObjectPoolRegistry.release(POOL_COLLECTIBLE, node)


## Visual + label feedback for one absorb. SFX is NOT here: the collector
## plays it so the pitch can track the combo (§15).
func _fire_feedback(def: CollectibleDef, pos: Vector3, score: float) -> void:
	_fire_burst(def, pos)
	_fire_label(def, pos, score)


func _fire_burst(def: CollectibleDef, pos: Vector3) -> void:
	var node: Node = ObjectPoolRegistry.acquire(POOL_BURST)
	if node == null:
		return
	node.global_position = pos
	node.fire(def.color)
	_burst_nodes.append(node)
	_burst_timers.append(BURST_LIFETIME)


func _fire_label(def: CollectibleDef, pos: Vector3, score: float) -> void:
	var node: FloatingLabel = ObjectPoolRegistry.acquire(POOL_LABEL) as FloatingLabel
	if node == null:
		return
	node.global_position = pos + Vector3(0.0, 0.6, 0.0)
	node.show_text("+%d" % roundi(score), def.color)
	_label_nodes.append(node)
	_label_timers.append(LABEL_LIFETIME)


## Per-physics-tick maintenance: spin/pulse visuals, decay motes, release
## finished VFX, and top up toward the target count (§11, 18/s max).
func tick(delta: float) -> void:
	_t += delta
	_tick_visuals(delta)
	_tick_decay(delta)
	_tick_vfx(delta)


func _tick_visuals(delta: float) -> void:
	for id in _alive:
		var node: CollectibleNode = _alive[id] as CollectibleNode
		if node == null or not node.visible:
			continue
		if node.def.type == CollectibleDef.Type.SHARD_RARE:
			node.spin(delta * 1.6)
			node.pulse(_t * 5.0, 1.0)
		else:
			node.pulse(_t * 3.0, 0.4)


func _tick_decay(delta: float) -> void:
	var expired: Array[CollectibleNode] = []
	for id in _alive:
		var node: CollectibleNode = _alive[id] as CollectibleNode
		if node != null and node.decay_remaining > 0.0:
			node.decay_remaining -= delta
			if node.decay_remaining <= 0.0:
				expired.append(node)
	for node in expired:
		if not node.consumed:
			_absorb(node)


func _tick_vfx(delta: float) -> void:
	for i in range(_burst_nodes.size() - 1, -1, -1):
		_burst_timers[i] -= delta
		if _burst_timers[i] <= 0.0:
			ObjectPoolRegistry.release(POOL_BURST, _burst_nodes[i])
			_burst_nodes.remove_at(i)
			_burst_timers.remove_at(i)
	for i in range(_label_nodes.size() - 1, -1, -1):
		_label_timers[i] -= delta
		var label: FloatingLabel = _label_nodes[i] as FloatingLabel
		if label != null:
			label.advance(delta)
		if _label_timers[i] <= 0.0:
			ObjectPoolRegistry.release(POOL_LABEL, _label_nodes[i])
			_label_nodes.remove_at(i)
			_label_timers.remove_at(i)


## Top-up loop: refill toward the target at most `refill_rate_per_second`
## spawns per second. The caller (SpawnManager) supplies positions, because
## validity checks are its job. The accumulator is capped at 1.0 so a long
## full-arena stretch can never pop-in a burst of respawns in one tick.
## Motes (boost/death drops) are ADDITIVE — they don't count against the
## population target.
func refill_accumulate(delta: float) -> int:
	_refill_accumulator = minf(1.0, _refill_accumulator + balance.refill_rate_per_second * delta)
	var want: int = mini(int(_refill_accumulator), maxi(0, balance.target_collectible_count - non_mote_count()))
	_refill_accumulator -= float(want)
	_refill_accumulator = maxf(0.0, _refill_accumulator)
	return want


func alive_count() -> int:
	return _alive.size()


## Non-mote collectibles only — the §11 "420 collectibles" population.
func non_mote_count() -> int:
	return alive_count() - mote_count()


func rare_count() -> int:
	var count: int = 0
	for id in _alive:
		var node: CollectibleNode = _alive[id] as CollectibleNode
		if node != null and node.def.type == CollectibleDef.Type.SHARD_RARE:
			count += 1
	return count


func mote_count() -> int:
	var count: int = 0
	for id in _alive:
		var node: CollectibleNode = _alive[id] as CollectibleNode
		if node != null and node.def.type == CollectibleDef.Type.CORPSE_MOTE:
			count += 1
	return count


## §8 SCAVENGE: the TOP-3 corpse motes within `radius` of `pos` (by power),
## as [{pos: Vector3, power: float}]. PERF (§8.5): avoids a sort_custom
## lambda allocation per call; scavenging only ever targets the best few.
func get_motes_near(pos: Vector3, radius: float) -> Array[Dictionary]:
	var ids: Array[int] = _hash.query_radius(pos, radius)
	var top: Array[Dictionary] = []
	for id in ids:
		var node: CollectibleNode = _alive.get(id) as CollectibleNode
		if node == null or node.consumed or node.def.type != CollectibleDef.Type.CORPSE_MOTE:
			continue
		var entry: Dictionary = {"pos": node.global_position, "power": node.power_value}
		var inserted: bool = false
		for i in range(top.size() - 1, -1, -1):
			if node.power_value <= float(top[i]["power"]):
				if top.size() < 3:
					top.insert(i + 1, entry)
				inserted = true
				break
		if not inserted and top.size() < 3:
			top.insert(0, entry)
	return top


## §10 MAGNET: moves a live collectible; the hash insert handles the
## cross-cell move (SpatialHash.insert re-keys on cell change).
func move_collectible(id: int, new_pos: Vector3) -> void:
	var node: CollectibleNode = _alive.get(id) as CollectibleNode
	if node == null or node.consumed:
		return
	_hash.insert(id, new_pos)
	node.global_position = new_pos


## Debug/test aid: removes every live collectible and active VFX instantly.
func clear_all() -> void:
	for id in _alive.keys():
		var node: CollectibleNode = _alive[id] as CollectibleNode
		if node != null:
			node.deactivate()
			ObjectPoolRegistry.release(POOL_COLLECTIBLE, node)
	_alive.clear()
	_hash.clear()
	_refill_accumulator = 0.0
	for i in range(_burst_nodes.size() - 1, -1, -1):
		ObjectPoolRegistry.release(POOL_BURST, _burst_nodes[i])
	for i in range(_label_nodes.size() - 1, -1, -1):
		ObjectPoolRegistry.release(POOL_LABEL, _label_nodes[i])
	_burst_nodes.clear()
	_burst_timers.clear()
	_label_nodes.clear()
	_label_timers.clear()
