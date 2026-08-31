class_name PowerUpDef
extends Resource
## §10 — One power-up archetype (sub-resource of PowerUpTable).
##
## Owns: effect parameters for one power-up type. Effects themselves are
##        applied by PowerUpManager through StatModifierStack (Phase 7).
## Does NOT own: spawn/pool logic.
## Talks to: nothing; pure data.

enum Type { SURGE, MAGNET, AEGIS, BLOOM, DOUBLER, CHILL }

## Which power-up this defines.
@export var type: Type = Type.SURGE
## Human-readable name shown on the HUD chip.
@export var display_name: String = "Surge"
## Effect duration in seconds (0 = instant, e.g. BLOOM).
@export var duration: float = 6.0
## Relative spawn rarity weight.
@export var rarity_weight: float = 25.0
## Aura particle colour (readable by other players).
@export var color: Color = Color(1.0, 0.85, 0.2)

@export_group("Surge")
@export var speed_multiplier: float = 1.35
@export var turn_multiplier: float = 1.15

@export_group("Magnet")
## Pulls collectibles within this many units toward the snake.
@export var pull_radius: float = 9.0
## Pull speed in units/s.
@export var pull_speed: float = 14.0

@export_group("Aegis")
## One free death while active (consumed on lethal hit).
@export var grants_invuln: bool = true

@export_group("Bloom")
## Instant power granted on pickup.
@export var bonus_power: float = 18.0

@export_group("Doubler")
## Multiplier on score AND power gained from collectibles.
@export var collectible_multiplier: float = 2.0

@export_group("Chill")
## Opponents within this radius are slowed.
@export var slow_radius: float = 16.0
## Their movement speed multiplier while chilled.
@export_range(0.0, 1.0) var slow_multiplier: float = 0.7
