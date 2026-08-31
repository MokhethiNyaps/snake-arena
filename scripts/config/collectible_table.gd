class_name CollectibleTable
extends Resource
## §3.3 — The collectible roster + weighted random picker.
##
## Owns: the list of CollectibleDef entries and weight bookkeeping.
## Does NOT own: live collectible instances (CollectibleManager).
## Talks to: nothing; pure data + a pure pick function.

## All collectible archetypes, including CORPSE_MOTE (weight 0, drop-only).
@export var entries: Array[CollectibleDef] = []


## Total weight of all spawnable entries (weight > 0).
func total_weight() -> float:
	var total: float = 0.0
	for def in entries:
		if def.spawn_weight > 0.0:
			total += def.spawn_weight
	return total


## Weighted-random pick among spawnable entries. Returns null if table empty.
func pick_weighted(rng: RandomNumberGenerator) -> CollectibleDef:
	var total: float = total_weight()
	if total <= 0.0:
		return null
	var roll: float = rng.randf() * total
	for def in entries:
		if def.spawn_weight <= 0.0:
			continue
		roll -= def.spawn_weight
		if roll <= 0.0:
			return def
	return entries[entries.size() - 1]


## Convenience: entry for a given Type, or null.
func get_def(type: CollectibleDef.Type) -> CollectibleDef:
	for def in entries:
		if def.type == type:
			return def
	return null
