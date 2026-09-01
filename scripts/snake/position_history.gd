class_name PositionHistory
extends RefCounted
## §6.2 — Distance-sampled position history ring buffer. THE body-following
## backbone: every physics tick the head pushes a sample when it has moved
## history_sample_distance from the last sample; segments read back at
## arc-length offsets with LERP interpolation between bracketing samples.
##
## Owns: the ring buffer + per-sample cached cumulative arc-length, and the
##        per-segment search cursors (O(history_span) per frame total).
## Does NOT own: snake state; it only records where the head has been.
## Talks to: SnakeController (push) and SnakeBody (read via cursors).
##
## Preallocated PackedVector3Array; NEVER append/pop in the hot loop (§6.2).
## Cursor reads are monotonic (the read offset per segment only moves
## forward as the head advances), so the total cost per frame is O(span).

var _positions: PackedVector3Array
var _cumulative_arc: PackedFloat64Array
var capacity: int
var head_index: int = 0
var count: int = 0
var total_arc: float = 0.0

## Per-reader search state, one cursor per body segment.
## Cursors keep their own `index` + `arc` walking state; the snake owns one
## HistoryCursor array sized max_segment_count and reuses them for growth.
var cursors: Array[HistoryCursor] = []


func _init(capacity: int, segment_count: int) -> void:
	self.capacity = maxi(capacity, 16)
	_positions = PackedVector3Array()
	_positions.resize(self.capacity)
	_cumulative_arc = PackedFloat64Array()
	_cumulative_arc.resize(self.capacity)
	cursors.clear()
	for i in segment_count:
		cursors.append(HistoryCursor.new())


## Appends a sample if the head moved >= sample_distance from the last one.
func push(pos: Vector3, sample_distance: float) -> void:
	if count == 0:
		_write(0, pos, 0.0)
		head_index = 1
		count = 1
		return
	var last_pos: Vector3 = _positions[_wrap(head_index - 1)]
	if pos.distance_to(last_pos) < sample_distance:
		return
	_push_sample(pos)


## Force-writes a sample even if the head hasn't moved (spawn trails).
func push_force(pos: Vector3) -> void:
	_push_sample(pos)


## The most recent sample (head position), or Vector3.INF if empty.
func latest() -> Vector3:
	if count == 0:
		return Vector3.INF
	return _positions[_wrap(head_index - 1)]


## Arc length of the newest sample (the head's trail coordinate).
func newest_arc() -> float:
	if count == 0:
		return 0.0
	return _cumulative_arc[_wrap(head_index - 1)]


## Reads the trail position at absolute arc coordinate `target_arc`, using
## (and advancing) the cached cursor `cursor_idx` — monotonic forward
## search, lerp between bracketing samples (§6.2).
func read_at_arc(target_arc: float, cursor_idx: int) -> Vector3:
	if count == 0:
		return Vector3.INF
	var newest_idx: int = _wrap(head_index - 1)
	if count == 1:
		return _positions[newest_idx]
	var oldest_idx: int = _wrap(head_index - count)
	var oldest_arc: float = _cumulative_arc[oldest_idx]
	var newest: float = _cumulative_arc[newest_idx]
	var t: float = clampf(target_arc, oldest_arc, newest)
	var c: HistoryCursor = cursors[cursor_idx]
	if not c.initialized:
		c.index = oldest_idx
		c.arc = oldest_arc
		c.initialized = true
	# Advance while the NEXT sample is still on the correct side of t and
	# has not wrapped past the newest sample.
	while c.index != newest_idx:
		var next_idx: int = _wrap(c.index + 1)
		var next_arc: float = _cumulative_arc[next_idx]
		if next_arc <= t:
			c.index = next_idx
			c.arc = next_arc
		else:
			break
	if c.index == newest_idx:
		return _positions[newest_idx]
	var next_idx2: int = _wrap(c.index + 1)
	var a0: float = c.arc
	var a1: float = _cumulative_arc[next_idx2]
	if a1 < a0 or a1 <= a0:
		return _positions[c.index]
	var f: float = clampf((t - a0) / (a1 - a0), 0.0, 1.0)
	return _positions[c.index].lerp(_positions[next_idx2], f)


func get_sample(index: int) -> Vector3:
	return _positions[index]


func get_arc(index: int) -> float:
	return _cumulative_arc[index]


func _push_sample(pos: Vector3) -> void:
	var prev_idx: int = _wrap(head_index - 1) if count > 0 else head_index
	var prev_arc: float = _cumulative_arc[prev_idx] if count > 0 else 0.0
	var step_arc: float = pos.distance_to(_positions[prev_idx]) if count > 0 else 0.0
	var arc: float = prev_arc + step_arc
	if count < capacity:
		_write(head_index, pos, arc)
		head_index = (head_index + 1) % capacity
		count += 1
	else:
		# Buffer full: overwrite the oldest sample; the valid window slides
		# forward one slot. Cursors only move forward, so they stay valid.
		_write(head_index, pos, arc)
		head_index = (head_index + 1) % capacity


func _write(index: int, pos: Vector3, arc: float) -> void:
	_positions[index] = pos
	_cumulative_arc[index] = arc


func _wrap(i: int) -> int:
	return (i % capacity + capacity) % capacity


## Validates ring-buffer invariants. Used by tests, not the hot path.
func invariant_ok() -> bool:
	if count == 0:
		return true
	var start: int = _wrap(head_index - count)
	var prev_arc: float = -1.0
	for k in count:
		var idx: int = _wrap(start + k)
		var arc: float = _cumulative_arc[idx]
		if arc < prev_arc:
			return false
		prev_arc = arc
	return true


class HistoryCursor:
	extends RefCounted
	## Search state for one segment's read position: the ring index that
	## brackets the target arc distance and the arc at that sample.
	## Owned 1:1 by a body segment slot; reused across grow/shrink.

	var index: int = 0
	var arc: float = 0.0
	var initialized: bool = false
