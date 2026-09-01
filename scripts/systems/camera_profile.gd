class_name CameraProfile
extends Resource
## §5 — Swappable camera styles (close/arcade, far/tactical, cinematic).
## The default profile lives in resources/config/camera_default.tres.
##
## Owns: the numbers that define one camera style. No behaviour.
## Talks to: nothing; CameraRig reads it.

@export_group("Framing")
## Pitch in degrees at start, easing toward pitch_max as the player grows.
@export var pitch_start_deg: float = -58.0
@export var pitch_max_deg: float = -68.0
## dist = dist_base + dist_power * pow(power, dist_exponent), clamped.
@export var dist_base: float = 17.0
@export var dist_power: float = 11.0
@export var dist_exponent: float = 0.30
@export var dist_min: float = 17.0
@export var dist_max: float = 62.0
## lookahead = lookahead_base + speed * lookahead_speed_factor
@export var lookahead_base: float = 3.5
@export var lookahead_speed_factor: float = 0.22
## Look-ahead is scaled to this while boosting (§5).
@export_range(0.0, 1.0) var lookahead_boost_scale: float = 0.4
## Critically-damped spring half-life (seconds) — NOT lerp (§5).
@export var smoothing_half_life: float = 0.12
@export_group("FOV & feel")
@export var fov_base: float = 55.0
@export var fov_max: float = 72.0
## Boost FOV kick for a sense of speed.
@export var fov_boost_add: float = 6.0
## Mobile multiplier on distance + FOV (smaller screens held closer).
@export var mobile_multiplier: float = 1.12
@export_group("Shake (trauma-based)")
## shake = trauma^2; trauma decays at this rate per second (§5).
@export var trauma_decay: float = 1.4
## Peak rotation (deg) and offset (units) at trauma = 1.
@export var shake_max_angle_deg: float = 2.5
@export var shake_max_offset: float = 0.5
## Global shake strength multiplier (Settings: 0..1; 0 = off).
@export var shake_intensity: float = 1.0
