class_name SkinDef
extends Resource
## §16 — One cosmetic skin. Purely visual; MUST never affect gameplay stats.
##
## Owns: mesh/material/colour data for a skin.
## Does NOT own: application logic (SkinManager, Phase 9) — SnakeController
##              must contain zero skin-specific code (§16).
## Talks to: nothing; pure data.

enum HeadMesh { DEFAULT_SPHERE, CRYSTAL, DIAMOND }
enum DeathEffect { DEFAULT, SPARKLE, VOID }

@export var display_name: String = "Classic"
## Head mesh override for this skin.
@export var head_mesh: HeadMesh = HeadMesh.DEFAULT_SPHERE
## Body material base colour.
@export var body_color: Color = Color(0.2, 0.85, 0.45)
## Accent (rim/emission) colour.
@export var accent_color: Color = Color(0.7, 1.0, 0.8)
## Trail particle colour.
@export var trail_color: Color = Color(0.2, 0.85, 0.45)
## Emission strength multiplier on body material.
@export_range(0.0, 4.0) var emissive_strength: float = 1.0
## Optional death-effect override.
@export var death_effect: DeathEffect = DeathEffect.DEFAULT
## Coin cost to unlock (0 = free).
@export var cost_coins: int = 0
