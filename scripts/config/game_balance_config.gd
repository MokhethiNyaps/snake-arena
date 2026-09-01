class_name GameBalanceConfig
extends Resource
## §3.5/§3.6 — Arena shape, session flow, surge/shrink events, population.
##
## Owns: the starting tuning values for world-level rules.
## Does NOT own: per-snake numbers (SnakeConfig), per-collectible numbers
##               (CollectibleTable), ad pacing (AdConfig).
## Talks to: nothing; it is pure data. Systems READ it via RemoteConfig.

@export_group("Arena")
## Circular arena radius in world units (§3.5). 0,0 is the centre; Y=0 is the floor.
@export var arena_radius: float = 120.0
## Outer band width where snakes are slowed and pushed inward (§3.5).
@export var soft_zone_width: float = 8.0
## Movement speed multiplier while inside the soft zone.
@export_range(0.0, 1.0) var soft_zone_slow_multiplier: float = 0.85

@export_group("Session / difficulty curve (§3.6)")
## Seconds at run start with no AI near spawn; free growth window.
@export var free_growth_window: float = 20.0
## Seconds until AI density has fully ramped and rare shards appear.
@export var ramp_end_time: float = 60.0
## Seconds after run start when the arena begins shrinking.
@export var shrink_start_time: float = 180.0
## Arena radius lost per second once shrinking begins.
@export var shrink_rate: float = 0.6
## Hard floor for the shrinking radius.
@export var shrink_floor_radius: float = 70.0

@export_group("Surge events (§3.6)")
## Seconds between Surge events.
@export var surge_interval: float = 45.0
## Collectibles dropped by one Surge.
@export var surge_collectible_count: int = 40
## Rare shards dropped by one Surge.
@export var surge_rare_count: int = 1
## Seconds the announcement beam stays visible.
@export var surge_beam_time: float = 3.0
## Seconds between staggered surge spawns (cluster forms organically).
@export var surge_spawn_stagger: float = 0.03
## Distance within which the first snake claims the surge bonus (§12.3).
@export var surge_claim_radius: float = 12.0

@export_group("World population (§11)")
## Collectibles the arena maintains at steady state.
@export var target_collectible_count: int = 420
## Max collectibles respawned per second (organic refill, not pop-in).
@export var refill_rate_per_second: float = 18.0
## Maximum rare shards alive at once (§3.3).
@export var max_rare_alive: int = 6
## AI snakes alive at steady state.
@export var ai_count: int = 8
## Seconds before a dead AI respawns.
@export var ai_respawn_delay: float = 2.5
## AI spawn points must be at least this far from the player.
@export var ai_min_spawn_distance: float = 45.0
## Any AI spawn must be at least this far from the player (§11).
@export var min_spawn_distance_from_player: float = 22.0
## Collectible spawns must be at least this far from the player.
@export var collectible_min_spawn_distance: float = 6.0
## Spawn validity retries before falling back to the Poisson-disc candidate set.
@export var spawn_retry_attempts: int = 12
## Power-ups alive at steady state.
@export var powerup_target_count: int = 5

@export_group("Scoring & combo (§12.3)")
## Combo window: a collect within this many seconds of the previous one
## increments the combo.
@export var combo_window: float = 1.4
## Score multiplier added per combo step: 1 + min(combo, combo_max_bonus_steps) * combo_multiplier_step.
@export var combo_multiplier_step: float = 0.05
## Combo steps beyond which the multiplier stops growing (max 2x at step 20).
@export var combo_max_bonus_steps: int = 20
## Survival score granted per second alive (§12.3).
@export var survival_score_per_second: float = 6.0
## Score for being first to a Surge cluster (§12.3).
@export var surge_claim_score: int = 300

@export_group("Collection (§3.3)")
## Extra collection radius added to the snake's current head radius.
@export var collect_radius_margin: float = 0.6
