extends Node
## AUTOLOAD #1 — EventBus (§22/§35.2). Signals only. Zero logic, zero state.
##
## Owns: the cross-system signal vocabulary. Nothing else. Ever.
## Talks to: everyone; no system talks THROUGH it, only TO it.

# Lifecycle (GameManager owns state transitions; everything else reacts)
signal game_state_changed(from_state: int, to_state: int)
signal run_started
signal run_ended

# Player & snakes
signal player_died
signal player_spawned
signal snake_died(killer_id: int, victim_id: int)
signal snake_spawned(snake_id: int)

# Economy / feedback
signal score_changed(score: float)
signal power_changed(power: float)
signal combo_changed(combo: int)
signal collectible_absorbed(type_id: int, value: float)
signal powerup_collected(type_id: int)
signal coins_changed(coins: int)
signal level_up(level: int)

# World events (§3.6)
signal surge_incoming(position: Vector3)
signal surge_started(position: Vector3)
signal arena_shrinking(current_radius: float)

# Meta (§16/§17)
signal mission_completed(mission_id: StringName)
signal skin_changed(skin_id: StringName)
signal settings_changed(section: String, key: String)
