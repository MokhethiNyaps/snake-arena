class_name ObjectPool
extends RefCounted
## Generic object pool for Node instances (§11: pooling is mandatory for
## collectibles, corpse motes, body segments, particle bursts, score labels).
##
## Owns: the inactive/active bookkeeping for ONE pooled scene type.
## Pooled nodes stay parented to the container; callers use global
## transforms instead of re-parenting acquired nodes.
## Does NOT own: what the pooled nodes do — it only stores and recycles them.
## Talks to: ObjectPoolRegistry (which owns the container node in the tree).

var _scene: PackedScene
var _container: Node
var _inactive: Array[Node] = []
var _active: Dictionary = {}  # instance_id -> Node, for O(1) release
var total_created: int = 0

## Creates a pool for `scene`; instances live under `container`.
func _init(scene: PackedScene, container: Node) -> void:
	_scene = scene
	_container = container


## Instantiates `count` nodes up front and parks them inactive.
func prewarm(count: int) -> void:
	for i in count:
		var node: Node = _instantiate()
		_set_visible(node, false)
		_inactive.append(node)
		total_created += 1


## Returns an inactive node, or instantiates a new one if the pool is empty.
func acquire() -> Node:
	var node: Node
	if _inactive.is_empty():
		node = _instantiate()
		total_created += 1
	else:
		node = _inactive.pop_back()
	_active[node.get_instance_id()] = node
	return node


## Returns a node to the pool. Safe to call with a node not from this pool
## (it will be refused rather than corrupting state).
## Pooled nodes stay parented to the container at ALL times; callers use
## global transforms/state instead of re-parenting.
func release(node: Node) -> bool:
	var id: int = node.get_instance_id()
	if not _active.has(id):
		return false
	_active.erase(id)
	var parent: Node = node.get_parent()
	if parent != _container:
		if parent != null:
			parent.remove_child(node)
		_container.add_child(node)
	_set_visible(node, false)
	_inactive.append(node)
	return true


func active_count() -> int:
	return _active.size()


func inactive_count() -> int:
	return _inactive.size()


func _instantiate() -> Node:
	var node: Node = _scene.instantiate()
	_container.add_child(node)
	return node


## `visible` lives on CanvasItem/Node3D, not on plain Node — the pool must
## accept any pooled scene type.
static func _set_visible(node: Node, v: bool) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = v
	elif node is Node3D:
		(node as Node3D).visible = v
