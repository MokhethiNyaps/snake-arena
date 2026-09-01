class_name PowerUpDef
extends Resource
## §10 — One power-up definition (sub-resource of PowerUpTableConfig).
##
## Owns: effect type + tuning for one verb. No behaviour — the
## PowerUpManager applies effects as stackable-but-capped modifiers on the
## per-snake StatModifierStack (§10: adding a power-up requires ZERO
## changes to SnakeController).
## Talks to: nothing; pure data.

enum Effect { SURGE, MAGNET, AEGIS, BLOOM, DOUBLER, CHILL }

## Which effect this def configures.
@export var effect: Effect = Effect.SURGE
## Display name (HUD chip, debug).
@export var display_name: String = "Surge"
## Active duration in seconds (0 = instant).
@export var duration: float = 6.0
## Rarity weight in the spawn table (§10).
@export var weight: int = 25
## Aura colour — every active effect wears it so other players can read
## your buffs (§10).
@export var aura_color: Color = Color(1.0, 0.8, 0.2)
## SURGE: speed multiplier.
@export var surge_speed_mult: float = 1.35
## SURGE: turn-rate multiplier.
@export var surge_turn_mult: float = 1.15
## MAGNET: pull radius in units.
@export var magnet_radius: float = 9.0
## MAGNET: pull speed in units/second.
@export var magnet_pull_speed: float = 14.0
## BLOOM: instant power granted.
@export var bloom_power: float = 18.0
## DOUBLER: score+power multiplier on collects.
@export var doubler_mult: float = 2.0
## CHILL: radius around the owner.
@export var chill_radius: float = 16.0
## CHILL: opponents inside move at this speed multiplier.
@export var chill_speed_mult: float = 0.7
