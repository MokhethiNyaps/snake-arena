class_name SkinDef
extends Resource
## §16 skin definition — PURELY COSMETIC. A skin may never touch gameplay
## stats (SnakeController contains zero skin code by design; SkinManager
## talks to SnakeBody's visual layer only).

@export var id: String = "classic"
@export var display_name: String = "Classic"
## Base body tint — lerped onto the §6 tier band colours (threat tiers stay
## readable through any skin).
@export var body_colour: Color = Color(0.62, 0.94, 1.0)
@export var emission_colour: Color = Color(0.35, 0.9, 1.0)
@export var emission_energy: float = 0.55
@export var head_colour: Color = Color(0.75, 0.98, 1.0)
## Trail particle colour (boost motes / Phase 10 trail FX read this).
@export var trail_colour: Color = Color(0.4, 0.95, 1.0)
## Optional head mesh override ("" = default sphere; Phase 10 may use it).
@export var head_mesh_override: String = ""
## Optional death-effect override id ("" = default dissolve; Phase 10).
@export var death_effect: String = ""
## Player level that unlocks the RIGHT to purchase (§16 levels unlock skins).
@export var unlock_level: int = 1
## Coin price (0 = free with the level unlock).
@export var price: int = 0
