class_name SnakeConfig
extends Resource
## §3.1/§3.2/§3.4 — every tuning value for a snake (player or AI instance).
##
## Owns: movement, growth, boost and combat numbers for one snake archetype.
## Does NOT own: world rules (GameBalanceConfig) or AI personality weights
##               (AIPersonalityConfig).
## Talks to: nothing; pure data read by SnakeController (Phase 2+).

enum BoostMode { DRAIN, COOLDOWN }

@export_group("Movement (§3.1)")
## Speed in units/s at Power 1.
@export var base_move_speed: float = 11.0
## speed = base * (1 - strength * (1 - exp(-power / scale))) — bigger is slower.
@export var speed_curve_strength: float = 0.28
## Speed curve scale divisor (the "9.0" in the spec formula).
@export var speed_curve_scale: float = 9.0
## Absolute speed floor so the late game never feels sluggish.
@export var min_move_speed: float = 7.6
## Base turning rate in degrees/s at Power 1.
@export var base_turn_rate: float = 280.0
## turn = base * clamp(1 - strength * log(power+1)/log(scale_log), min_mult, 1).
@export var turn_curve_strength: float = 0.30
## Turn curve log divisor (the "20.0" in the spec formula).
@export var turn_curve_scale_log: float = 20.0
## Lowest multiplier the turn curve may apply.
@export_range(0.0, 1.0) var turn_curve_min_multiplier: float = 0.45

@export_group("Boost (§3.4)")
## DRAIN = boosting costs power and emits motes; COOLDOWN = bar-based variant.
@export var boost_mode: BoostMode = BoostMode.DRAIN
## Speed multiplier while boosting.
@export var boost_multiplier: float = 1.85
## Turn-rate multiplier while boosting (the core boost risk).
@export_range(0.0, 1.0) var boost_turn_penalty: float = 0.72
## Power drained per second while boosting (DRAIN mode).
@export var boost_power_drain: float = 2.2
## Cannot boost below this power (DRAIN mode).
@export var min_boost_power: float = 4.0
## Corpse motes emitted per second while boosting.
@export var boost_mote_emission_rate: float = 4.0

@export_group("Size & growth (§3.1/§3.2)")
## Head sphere radius in units at Power 1.
@export var head_radius: float = 0.55
## radius = head_radius * pow(power, exponent) — sublinear growth.
@export var radius_power_exponent: float = 0.19
## Segment spacing as a fraction of the current radius.
@export var segment_spacing_radius_factor: float = 0.62
## Body segments at spawn.
@export var start_segment_count: int = 6
## Hard cap on segments; beyond this growth converts to score/radius only.
@export var max_segment_count: int = 240
## Power value at spawn (§3.2).
@export var start_power: float = 2.0
## Length in segments = start + floor(power / segments_per_power).
@export var segments_per_power: float = 3.5
## Minimum turn radius as a multiple of the current body radius (§6.3).
@export var min_turn_radius_factor: float = 1.15
## Head vs own body collision (off by default; Hardcore mode future toggle).
@export var self_collision_enabled: bool = false

@export_group("Position history (§6.2)")
## Minimum world distance between consecutive history samples.
@export var history_sample_distance: float = 0.10
## Preallocated ring buffer size (never appended to in the hot loop).
@export var max_history_points: int = 4096

@export_group("Combat (§3.2/§9/§12)")
## my_power must be >= their_power * eat_power_ratio to eat them.
@export var eat_power_ratio: float = 1.10
## Fraction of a victim's power granted immediately on absorption.
@export var absorbed_power_fraction: float = 0.62
## Fraction of a victim's power dropped as corpse motes on death.
@export var dropped_mass_fraction: float = 0.72
## Corpse motes despawn after this many seconds.
@export var corpse_mote_decay_time: float = 14.0
## Stagger between corpse mote spawns during the death dissolve (§9).
@export var corpse_mote_stagger: float = 0.35
