class_name AIPersonalityConfig
extends Resource
## §8.3 — One AI personality archetype, one .tres per personality.
##
## Owns: behaviour weights for a single AI temperament.
## Does NOT own: AI decision logic (AIController/AIStateMachine, Phase 5).
## Talks to: nothing; pure data.

## Personality label ("Collector", "Aggressive", ...).
@export var display_name: String = "Collector"
## Chase range for edible targets.
@export var aggro_radius: float = 14.0
## Flee range for dangerous targets.
@export var fear_radius: float = 34.0
## How single-mindedly it farms collectibles (0..1).
@export_range(0.0, 1.0) var greed: float = 1.0
## Probability of aiming to cross ahead of prey instead of chasing tail.
@export_range(0.0, 1.0) var cutoff_skill: float = 0.10
## Probability of using boost when hunting/fleeing.
@export_range(0.0, 1.0) var boost_willingness: float = 0.15
## World-snapshot staleness the AI perceives through (humanizes it).
@export var reaction_delay: float = 0.30
## Degrees of aiming error added to chosen headings (smoothed noise).
@export var aim_error_deg: float = 6.0
## Max range at which other snakes are sensed (§8.4).
@export var sense_radius: float = 55.0
## Max range at which collectibles are sensed.
@export var collectible_sense_radius: float = 28.0
## Chance, per 2 s, of deliberately holding a bad heading for 0.5 s.
@export_range(0.0, 1.0) var blunder_chance: float = 0.04
## WANDER waypoint re-pick interval range (seconds).
@export var wander_min_interval: float = 3.0
@export var wander_max_interval: float = 6.0
