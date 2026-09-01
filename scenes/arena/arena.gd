extends Node3D
## Arena root (§3.5): circular ground, translucent boundary wall, soft-zone
## ring, lighting, and the Phase-3 economy systems (CollectibleManager,
## SpawnManager, ScoreManager — scene-level, decision #25).
##
## Owns: static world visuals + the economy managers it creates and ticks.
## Does NOT own: the player (boot wires it via setup_world), snake movement,
##               the camera (CameraRig).
## Talks to: the managers; boot.gd / verify harness via setup_world().

@onready var ground: MeshInstance3D = $Ground
@onready var boundary: MeshInstance3D = $Boundary
@onready var soft_zone_ring: MeshInstance3D = $SoftZoneRing

var collectible_manager: CollectibleManager = null
var spawn_manager: SpawnManager = null
var score_manager: ScoreManager = null
var ai_director: AIDirector = null

var _player_snake: SnakeController = null


func _ready() -> void:
	# The CameraRig (player scene) owns the camera from Phase 2 on.
	collectible_manager = CollectibleManager.new()
	collectible_manager.name = "CollectibleManager"
	add_child(collectible_manager)
	spawn_manager = SpawnManager.new()
	spawn_manager.name = "SpawnManager"
	add_child(spawn_manager)
	spawn_manager.collectibles = collectible_manager
	score_manager = ScoreManager.new()
	score_manager.name = "ScoreManager"
	add_child(score_manager)
	ai_director = AIDirector.new()
	ai_director.name = "AIDirector"
	add_child(ai_director)
	ai_director.collectibles = collectible_manager
	ai_director.spawn_manager = spawn_manager
	ai_director.arena_owner = self
	EventBus.game_state_changed.connect(_on_state_changed)
	print("ARENA_READY")


## Called by boot.gd / the verify harness once the player exists: wires
## player distance checks, the boost-mote drop, and the economy refs.
func setup_world(player_root: Node3D, snake: SnakeController) -> void:
	_player_snake = snake
	spawn_manager.player_snake = snake
	ai_director.player_snake = snake
	snake.boost_mote_emitted.connect(_on_boost_mote)
	if player_root is PlayerController:
		(player_root as PlayerController).setup_economy(collectible_manager, score_manager, spawn_manager)


## §3.4: boost-shed motes enter the arena economy (power only — they are a
## refund of your own drained power, not free score; decision #27).
func _on_boost_mote(pos: Vector3, power: float) -> void:
	collectible_manager.drop_mote(pos, power, 0.0)


func _on_state_changed(_from: int, to: int) -> void:
	if to == GameManager.State.PLAYING:
		# Initial population lands at once (decision #26); the 18/s cap
		# applies to refill respawns only.
		spawn_manager.initial_fill()


func _physics_process(delta: float) -> void:
	if not GameManager.is_in(GameManager.State.PLAYING):
		return
	collectible_manager.tick(delta)
	spawn_manager.tick(delta)
	spawn_manager.top_up()
	ai_director.tick(delta)
	if _player_snake != null and _player_snake.alive:
		score_manager.tick(delta)


## Soft-zone band [arena_radius - soft_zone_width, arena_radius] (§3.5).
## Gameplay uses this for the slow/push-in behaviour from Phase 2 on.
func soft_zone_inner_radius(balance: GameBalanceConfig) -> float:
	return balance.arena_radius - balance.soft_zone_width
