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

## Economy refs, wired by arena.setup_world (Phase 3).
var collectibles: CollectibleManager = null
var score_mgr: ScoreManager = null
var spawn_mgr: SpawnManager = null
var powerup_mgr: PowerUpManager = null


func setup_economy(cm: CollectibleManager, sm: ScoreManager, spm: SpawnManager) -> void:
	collectibles = cm
	score_mgr = sm
	spawn_mgr = spm


## §10 DOUBLER consult lives in the manager; the collect site just asks.
func setup_powerups(pm: PowerUpManager) -> void:
	powerup_mgr = pm


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
		if collectibles != null:
			_try_collect()
			_try_surge_claim()
	else:
		snake.set_steer_target(Vector3.ZERO)
		snake.set_boost(false)


## §9 "Head → collectible: Absorb." Queries the collectible spatial hash
## around the head; applies power to the snake and score/combo to the
## ScoreManager; SFX pitch tracks the combo (§15).
func _try_collect() -> void:
	var radius: float = snake.current_radius + collectibles.balance.collect_radius_margin
	var pickups: Array[Dictionary] = collectibles.collect_near(snake.global_position, radius)
	if pickups.is_empty():
		return
	# §10 DOUBLER: 2× score+power from collectibles while active.
	var mult: float = 1.0
	if powerup_mgr != null:
		mult = powerup_mgr.collect_multiplier(snake)
	for p in pickups:
		snake.add_power(float(p["power"]) * mult)
		var steps: int = 0
		if score_mgr != null:
			score_mgr.on_collectible(float(p["score"]) * mult)
			steps = score_mgr.get_combo() - 1
		AudioManager.play_pickup(int(p["type"]), steps, snake.global_position)


## §12.3: first snake to the Surge cluster claims +300.
func _try_surge_claim() -> void:
	if spawn_mgr == null or score_mgr == null:
		return
	if spawn_mgr.try_claim_surge(snake.global_position):
		score_mgr.add_score(float(spawn_mgr.balance.surge_claim_score))


## Spawns the snake at `pos` facing `angle_deg` (used by boot / later by
## SpawnManager + revive).
func place_snake(pos: Vector3, angle_deg: float) -> void:
	snake.global_position = Vector3(pos.x, 0.0, pos.z)
	snake.facing_angle_deg = angle_deg
	snake.body_push_direct(snake.global_position)
