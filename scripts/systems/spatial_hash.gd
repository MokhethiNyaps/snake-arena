class_name SpatialHash
extends RefCounted
## Custom spatial hash broadphase — the performance backbone (§6.4).
##
## Owns: a Dictionary keyed by Vector2i(cell_x, cell_z) mapping item ids to
##        their current positions, plus an id -> cell reverse map.
## Does NOT own: game objects; ids and positions are supplied by callers.
## Talks to: snake bodies and CollectibleManager (head-vs-body tests,
##            collection radius queries). Never uses physics bodies.
##
## Cell size 6.0 per §6.4. Queries check the home cell + the 8 neighbours
## (or a wider window when the query radius exceeds the cell size).

const DEFAULT_CELL_SIZE: float = 6.0

var cell_size: float = DEFAULT_CELL_SIZE

## cell_key -> { item_id: Vector3 position }
var _cells: Dictionary = {}
## item_id -> cell_key
var _id_cells: Dictionary = {}


## Inserts or overwrites the item at `pos`, moving it across cells if needed.
func insert(id: int, pos: Vector3) -> void:
	var key: Vector2i = get_cell_key(pos)
	var old_key: Variant = _id_cells.get(id, null)
	if old_key != null:
		if old_key == key:
			# Same cell: update position in place.
			_cells[key][id] = pos
			return
		remove(id)
	var bucket: Variant = _cells.get(key)
	if bucket == null:
		bucket = {}
		_cells[key] = bucket
	bucket[id] = pos
	_id_cells[id] = key


## Removes the item entirely.
func remove(id: int) -> bool:
	var key: Variant = _id_cells.get(id, null)
	if key == null:
		return false
	var bucket: Dictionary = _cells[key]
	bucket.erase(id)
	if bucket.is_empty():
		_cells.erase(key)
	_id_cells.erase(id)
	return true


## Removes all items (call once per physics tick before rebuilding).
func clear() -> void:
	_cells.clear()
	_id_cells.clear()


## Returns items whose position is within `radius` of `pos`.
## Result includes exact-distance filtering — never rely on cells alone.
func query_radius(pos: Vector3, radius: float) -> Array[int]:
	var result: Array[int] = []
	var radius_sq: float = radius * radius
	var span: int = maxi(1, ceili(radius / cell_size))
	var center: Vector2i = get_cell_key(pos)
	for x in range(center.x - span, center.x + span + 1):
		for z in range(center.y - span, center.y + span + 1):
			var bucket: Variant = _cells.get(Vector2i(x, z))
			if bucket == null:
				continue
			for id: int in bucket:
				var item_pos: Vector3 = bucket[id]
				if pos.distance_squared_to(item_pos) <= radius_sq:
					result.append(id)
	return result


## Returns ALL items in the cell containing `pos` and its 8 neighbours.
## Use when the caller wants "everything nearby" without a radius filter.
func query_cell_neighbors(pos: Vector3) -> Array[int]:
	var result: Array[int] = []
	var center: Vector2i = get_cell_key(pos)
	for x in range(center.x - 1, center.x + 2):
		for z in range(center.y - 1, center.y + 2):
			var bucket: Variant = _cells.get(Vector2i(x, z))
			if bucket == null:
				continue
			for id: int in bucket:
				result.append(id)
	return result


## Cell key for a world position. Negative coords handled by floor().
func get_cell_key(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.z / cell_size))


## Item's current cell, or Vector2i(-2147483648, -2147483648) if absent.
func get_item_cell(id: int) -> Vector2i:
	var key: Variant = _id_cells.get(id, null)
	if key == null:
		return Vector2i(-2147483648, -2147483648)
	return key


func item_count() -> int:
	return _id_cells.size()


func cell_count() -> int:
	return _cells.size()
