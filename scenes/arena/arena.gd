extends Node3D
## Arena root (§3.5): circular ground, translucent boundary wall, soft-zone
## ring, lighting, and the Phase-1 placeholder camera.
##
## Owns: static world visuals and their node references.
## Does NOT own: snake movement/collision (soft-zone PUSH logic arrives with
##               SnakeController, Phase 2); the real CameraRig replaces the
##               placeholder camera in Phase 2 (§5).
## Talks to: nobody yet. Systems will read $Ground etc. by export reference.

@onready var ground: MeshInstance3D = $Ground
@onready var boundary: MeshInstance3D = $Boundary
@onready var soft_zone_ring: MeshInstance3D = $SoftZoneRing


func _ready() -> void:
	# The CameraRig (player scene) owns the camera from Phase 2 on.
	print("ARENA_READY")


## Soft-zone band [arena_radius - soft_zone_width, arena_radius] (§3.5).
## Gameplay uses this for the slow/push-in behaviour from Phase 2 on.
func soft_zone_inner_radius(balance: GameBalanceConfig) -> float:
	return balance.arena_radius - balance.soft_zone_width
