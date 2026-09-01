class_name PlayerController
extends Node3D
## §7 — The player's driver for a SnakeController. Converts InputManager
## output (steering vector + boost) into set_steer_target/set_boost calls.
##
## Owns: the PLAYER-specific input translation. Nothing else.
## Does NOT own: the snake's movement (SnakeController), the input itself
##               (InputManager), the camera (CameraRig).
## Talks to: InputManager (read), its SnakeController child (write).
##
## Phase 2 scope: keyboard steering + boost hold; mouse steering wired via
## InputManager's raycast path (Phase 3) with this same interface.

@onready var snake: SnakeController = $Snake
@onready var camera_rig: CameraRig = $CameraRig


func _physics_process(_delta: float) -> void:
	if snake == null or not snake.alive:
		return
	if GameManager.is_in(GameManager.State.PLAYING) and not InputManager.is_suspended():
		var steer: Vector3 = InputManager.get_steer_direction()
		if steer != Vector3.ZERO:
			snake.set_steer_target(snake.global_position + steer * 30.0)
		else:
			snake.set_steer_target(Vector3.ZERO)
		snake.set_boost(InputManager.is_boosting())
	else:
		snake.set_steer_target(Vector3.ZERO)
		snake.set_boost(false)


## Spawns the snake at `pos` facing `angle_deg` (used by boot / later by
## SpawnManager + revive).
func place_snake(pos: Vector3, angle_deg: float) -> void:
	snake.global_position = Vector3(pos.x, 0.0, pos.z)
	snake.facing_angle_deg = angle_deg
	snake.body_push_direct(snake.global_position)
