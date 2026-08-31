class_name PowerUpTable
extends Resource
## §10 — The power-up roster + weighted random picker.
##
## Owns: the list of PowerUpDef entries and weight bookkeeping.
## Does NOT own: live power-up instances (PowerUpManager, Phase 7).
## Talks to: nothing; pure data + a pure pick function.

## All six power-ups from §10.
@export var entries: Array[PowerUpDef] = []


func total_weight() -> float:
	var total: float = 0.0
	for def in entries:
		if def.rarity_weight > 0.0:
			total += def.rarity_weight
	return total


func pick_weighted(rng: RandomNumberGenerator) -> PowerUpDef:
	var total: float = total_weight()
	if total <= 0.0:
		return null
	var roll: float = rng.randf() * total
	for def in entries:
		if def.rarity_weight <= 0.0:
			continue
		roll -= def.rarity_weight
		if roll <= 0.0:
			return def
	return entries[entries.size() - 1]


func get_def(type: PowerUpDef.Type) -> PowerUpDef:
	for def in entries:
		if def.type == type:
			return def
	return null
