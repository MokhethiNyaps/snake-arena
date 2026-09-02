class_name StatModifierStack
extends RefCounted
## §10 — Stackable-but-capped timed modifiers on SnakeController stats.
## Adding a power-up requires ZERO changes to SnakeController: it reads the
## final multiplier for a stat from this stack.
##
## Owns: active modifiers and their expiry bookkeeping.
## Does NOT own: what the numbers mean; callers pass stat keys.
## Talks to: SnakeController (reads), PowerUpManager (adds, Phase 7).
##
## Stats are read as multipliers (1.0 = no effect). Identical type refreshes
## duration instead of stacking (§10). Cleanup happens lazily on access so
## the hot path does no per-frame list churn.

## stat_name -> { modifier_id: { multiplier, expiry, stack_id } }
var _mods: Dictionary = {}


## Adds/renews a modifier. `stack_id` groups identical effects (refresh
## instead of stack). `duration` <= 0 = permanent until removed.
func add(stack_id: StringName, stat: StringName, multiplier: float, duration: float) -> void:
	var bucket: Dictionary = _mods.get(stat, {})
	if bucket.has(stack_id):
		var entry: Dictionary = bucket[stack_id]
		entry["multiplier"] = multiplier
		entry["expiry"] = _now() + duration if duration > 0.0 else INF
		return
	bucket[stack_id] = {
		"multiplier": multiplier,
		"expiry": _now() + duration if duration > 0.0 else INF,
	}
	_mods[stat] = bucket


func remove(stack_id: StringName, stat: StringName) -> void:
	var bucket: Dictionary = _mods.get(stat, {})
	if bucket.erase(stack_id):
		if bucket.is_empty():
			_mods.erase(stat)


## Strips every modifier (revive path: the run resumes from a clean slate).
func clear() -> void:
	_mods.clear()


func remove_all(stack_id: StringName) -> void:
	for stat: StringName in _mods.keys():
		var bucket: Dictionary = _mods[stat]
		if bucket.erase(stack_id):
			if bucket.is_empty():
				_mods.erase(stat)


## Final multiplier for a stat (1.0 = baseline). Expired entries are
## dropped lazily here.
func get_multiplier(stat: StringName) -> float:
	var bucket: Dictionary = _mods.get(stat, {})
	if bucket.is_empty():
		return 1.0
	var now: float = _now()
	var mult: float = 1.0
	for stack_id: StringName in bucket.keys():
		var entry: Dictionary = bucket[stack_id]
		if entry["expiry"] < now:
			bucket.erase(stack_id)
			if bucket.is_empty():
				_mods.erase(stat)
			continue
		mult *= entry["multiplier"]
	return mult


func has(stat: StringName) -> bool:
	return _mods.has(stat)


func active_count() -> int:
	var total: int = 0
	for stat: StringName in _mods:
		total += _mods[stat].size()
	return total


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
