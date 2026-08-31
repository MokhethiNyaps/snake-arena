extends Node
## AUTOLOAD #9 — ObjectPoolRegistry (§11). Owns one ObjectPool per pooled
## scene type and prewarms them at load.
##
## Owns: the pool Dictionary and the container node all pooled objects live
##        under. Phase 1: the mechanism + prewarm orchestration. Phase 3
##        registers the real pooled scenes (600 collectibles, 400 segments,
##        40 particle bursts, 30 labels per §11).
## Does NOT own: object behaviour.
## Talks to: systems that acquire/release pooled nodes.

const POOL_LAYER: int = -5

var _container: Node = null
var _pools: Dictionary = {}  # StringName -> ObjectPool


func _ready() -> void:
	_container = Node.new()
	_container.name = "PooledObjects"
	add_child(_container)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Registers (or returns an existing) pool for `scene`.
func register_pool(key: StringName, scene: PackedScene, prewarm_count: int = 0) -> ObjectPool:
	if _pools.has(key):
		return _pools[key]
	var pool: ObjectPool = ObjectPool.new(scene, _container)
	pool.prewarm(prewarm_count)
	_pools[key] = pool
	return pool


func acquire(key: StringName) -> Node:
	var pool: ObjectPool = _pools.get(key)
	if pool == null:
		push_error("[ObjectPoolRegistry] Unknown pool: %s" % key)
		return null
	return pool.acquire()


func release(key: StringName, node: Node) -> void:
	var pool: ObjectPool = _pools.get(key)
	if pool == null:
		push_error("[ObjectPoolRegistry] Unknown pool: %s" % key)
		return
	pool.release(node)


func has_pool(key: StringName) -> bool:
	return _pools.has(key)


func active_count(key: StringName) -> int:
	var pool: ObjectPool = _pools.get(key)
	return pool.active_count() if pool != null else 0


func inactive_count(key: StringName) -> int:
	var pool: ObjectPool = _pools.get(key)
	return pool.inactive_count() if pool != null else 0


func total_pooled_nodes() -> int:
	var total: int = 0
	for key in _pools:
		var pool: ObjectPool = _pools[key]
		total += pool.total_created
	return total
