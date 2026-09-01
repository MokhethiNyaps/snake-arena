class_name PowerUpTableConfig
extends Resource
## §10 — The power-up table: every def plus the global rules.
##
## Owns: the inventory. No behaviour (PowerUpManager acts on it).
## Talks to: PowerUpManager reads it. Pure data.

## §10: no snake may hold more than this many active effects.
@export var max_active_powerups: int = 3
## §11: power-ups alive at steady state (refilled at 1/2 s).
@export var target_alive_count: int = 5
## §11: one new power-up at most every this many seconds after a pickup.
@export var refill_interval: float = 2.0
## Spawn at least this far from the player.
@export var min_player_distance: float = 10.0

@export_group("Inventory (§10)")
@export var powerups: Array[PowerUpDef] = []


func get_def(effect: PowerUpDef.Effect) -> PowerUpDef:
	for p in powerups:
		if p.effect == effect:
			return p
	return null


func weighted_pick(rng: RandomNumberGenerator) -> PowerUpDef:
	var total: int = 0
	for p in powerups:
		total += p.weight
	if total <= 0:
		return powerups[0] if not powerups.is_empty() else null
	var roll: int = rng.randi_range(1, total)
	var acc: int = 0
	for p in powerups:
		acc += p.weight
		if roll <= acc:
			return p
	return powerups[powerups.size() - 1]
