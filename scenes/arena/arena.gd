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
var combat_manager: CombatManager = null
var powerup_manager: PowerUpManager = null

var _player_snake: SnakeController = null
var _player_root: Node3D = null
var _vignette: ColorRect = null
var _initial_radius: float = 120.0


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
	combat_manager = CombatManager.new()
	combat_manager.name = "CombatManager"
	add_child(combat_manager)
	combat_manager.collectibles = collectible_manager
	combat_manager.score_manager = score_manager
	combat_manager.ai_director = ai_director
	combat_manager.arena_owner = self
	powerup_manager = PowerUpManager.new()
	powerup_manager.name = "PowerUpManager"
	add_child(powerup_manager)
	powerup_manager.collectibles = collectible_manager
	powerup_manager.spawn_manager = spawn_manager
	powerup_manager.combat_manager = combat_manager
	powerup_manager.arena_owner = self
	combat_manager.aegis_query = Callable(powerup_manager, "has_aegis")
	ai_director.powerup_manager = powerup_manager
	_initial_radius = combat_manager.balance.arena_radius
	_build_vignette()
	EventBus.game_state_changed.connect(_on_state_changed)
	print("ARENA_READY")


## Called by boot.gd / the verify harness once the player exists: wires
## player distance checks, the boost-mote drop, and the economy refs.
func setup_world(player_root: Node3D, snake: SnakeController) -> void:
	_player_snake = snake
	_player_root = player_root
	spawn_manager.player_snake = snake
	ai_director.player_snake = snake
	combat_manager.player_snake = snake
	powerup_manager.player_snake = snake
	# Role marker: the combat/score path keys off this group (§9).
	if not snake.is_in_group("player"):
		snake.add_to_group("player")
	snake.boost_mote_emitted.connect(_on_boost_mote)
	snake.wall_hit.connect(_on_player_wall_hit)
	if player_root is PlayerController:
		(player_root as PlayerController).setup_economy(collectible_manager, score_manager, spawn_manager)
		(player_root as PlayerController).setup_powerups(powerup_manager)
	var rig: Node = player_root.get_node_or_null("CameraRig")
	if rig != null:
		combat_manager.rig = rig


## §3.4: boost-shed motes enter the arena economy (power only — they are a
## refund of your own drained power, not free score; decision #27).
func _on_boost_mote(pos: Vector3, power: float) -> void:
	collectible_manager.drop_mote(pos, power, 0.0)


## §9: wall-hit feedback — camera trauma + red vignette pulse.
func on_wall_hit(_is_player: bool = true) -> void:
	if combat_manager.rig != null:
		combat_manager.rig.add_trauma(combat_manager.balance.wall_hit_trauma)
	_pulse_vignette()


func _on_player_wall_hit(_snake: SnakeController) -> void:
	on_wall_hit(true)


## Minimal red vignette flash (proper HUD treatment in Phase 8).
func _build_vignette() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "VignetteLayer"
	layer.layer = 5
	add_child(layer)
	_vignette = ColorRect.new()
	_vignette.color = Color(1.0, 0.1, 0.1, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_vignette)


func _pulse_vignette() -> void:
	if _vignette == null:
		return
	var tween: Tween = create_tween()
	_vignette.color.a = 0.28
	tween.tween_property(_vignette, "color:a", 0.0, 0.4)


## §3.6 shrink: scale boundary visuals + push the live radius into every
## snake and the spawn validity checks.
func _sync_shrink_visuals() -> void:
	var r: float = combat_manager.current_radius()
	if is_equal_approx(r, _initial_radius):
		return
	var s: float = r / _initial_radius
	var scale_vec: Vector3 = Vector3(s, 1.0, s)
	boundary.scale = scale_vec
	soft_zone_ring.scale = scale_vec
	if spawn_manager.validity_radius != r:
		spawn_manager.validity_radius = r
	if _player_snake != null:
		_player_snake.set_arena_radius(r)
	for ai in ai_director.ai_controllers:
		if ai.snake != null:
			ai.snake.set_arena_radius(r)


func _on_state_changed(_from: int, to: int) -> void:
	if to == GameManager.State.PLAYING:
		# Initial population lands at once (decision #26); the 18/s cap
		# applies to refill respawns only.
		spawn_manager.initial_fill()


func _physics_process(delta: float) -> void:
	# The world keeps dissolving/hit-stopping during DYING; everything else
	# freezes when the run is not live.
	if not GameManager.is_in(GameManager.State.PLAYING) \
			and not GameManager.is_in(GameManager.State.DYING):
		return
	collectible_manager.tick(delta)
	spawn_manager.tick(delta)
	spawn_manager.top_up()
	ai_director.tick(delta)
	combat_manager.tick(delta)
	powerup_manager.tick(delta)
	_sync_shrink_visuals()
	if GameManager.is_in(GameManager.State.PLAYING) \
			and _player_snake != null and _player_snake.alive:
		score_manager.tick(delta)


## Soft-zone band [arena_radius - soft_zone_width, arena_radius] (§3.5).
## Gameplay uses this for the slow/push-in behaviour from Phase 2 on.
func soft_zone_inner_radius(balance: GameBalanceConfig) -> float:
	return balance.arena_radius - balance.soft_zone_width
