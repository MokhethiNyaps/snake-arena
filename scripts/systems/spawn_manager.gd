class_name SpawnManager
extends Node
## §11 — World population: spawn validity checks, the Poisson-disc fallback
## candidate set, initial fill, rate-limited top-up, the §3.6 difficulty
## curve (which defs may spawn when), and Surge events.
##
## Placement: scene-level node created by arena.gd (decision #25).
##
## Owns: spawn positions, the precomputed candidate set, game time, surge
##       scheduling + beam visual.
## Does NOT own: the live collectible set (CollectibleManager) or scoring.
## Talks to: CollectibleManager (spawn/drop), EventBus (surge signals),
##           GameManager (state gating), the player (distance checks).

const SEGMENT_CLEARANCE: float = 2.0  # §11: no spawn within 2.0 of a segment
const POISSON_MIN_DIST: float = 3.4
const POISSON_MAX_CANDIDATES: int = 1600

@export var balance: GameBalanceConfig = preload("res://resources/config/game_balance.tres")
@export var table: CollectibleTable = preload("res://resources/config/collectibles.tres")

var collectibles: CollectibleManager = null
## Live arena radius for spawn validity: the §3.6 shrink updates this as
## the wall closes in.
var validity_radius: float = 0.0
var player_snake: SnakeController = null

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _candidates: Array[Vector3] = []
var _game_time: float = 0.0
var _next_surge_time: float = -1.0
var _surge_active: bool = false
var _surge_pos: Vector3 = Vector3.ZERO
var _surge_claimed: bool = false
var _surge_queue: int = 0
var _surge_rare_queue: int = 0
var _surge_queue_timer: float = 0.0
var _beam: MeshInstance3D = null
var _beam_timer: float = 0.0


func _ready() -> void:
	_rng.randomize()
	validity_radius = balance.arena_radius
	_precompute_candidates()
	_beam = _make_beam()
	add_child(_beam)
	EventBus.game_state_changed.connect(_on_state_changed)


func _on_state_changed(_from: int, to: int) -> void:
	if to == GameManager.State.PLAYING:
		# First surge per §3.6: 60 s in, then every surge_interval.
		_next_surge_time = balance.ramp_end_time
	elif to == GameManager.State.LOADING:
		_game_time = 0.0
		_surge_active = false
		_surge_queue = 0
		_surge_rare_queue = 0


## Called once per physics tick by arena while PLAYING.
func tick(delta: float) -> void:
	_game_time += delta
	_tick_surge(delta)


func is_playing() -> bool:
	return GameManager.current_state == GameManager.State.PLAYING


## Initial population: fill straight to the target (§46 decision #26 — the
## 18/s cap applies to refill respawns, not the arena's opening state).
func initial_fill() -> void:
	var target: int = balance.target_collectible_count
	for i in target - collectibles.non_mote_count():
		_spawn_weighted()


## Refill pass: called each tick; spawns up to the rate-limited allowance.
func top_up() -> void:
	var want: int = collectibles.refill_accumulate(get_physics_process_delta_time())
	for i in want:
		_spawn_weighted()


## Weighted random def respecting the §3.6 curve and the rare cap.
func _spawn_weighted() -> void:
	var def: CollectibleDef = _pick_def_for_time(_game_time)
	if def == null:
		return
	var pos: Vector3 = find_valid_collectible_position()
	collectibles.spawn_collectible(def, pos)


## §3.6 gating: 0-20 s only small/medium; 20-60 s ramps in large, then
## rare (respecting max_rare_alive); 60 s+ everything.
func _pick_def_for_time(t: float) -> CollectibleDef:
	var t_small: CollectibleDef = table.get_def(CollectibleDef.Type.CELL_SMALL)
	var t_medium: CollectibleDef = table.get_def(CollectibleDef.Type.CELL_MEDIUM)
	var t_large: CollectibleDef = table.get_def(CollectibleDef.Type.CELL_LARGE)
	var t_rare: CollectibleDef = table.get_def(CollectibleDef.Type.SHARD_RARE)
	if t < balance.free_growth_window:
		var roll: float = _rng.randf()
		if roll < 0.25:
			return t_medium
		return t_small
	var pick: CollectibleDef = table.pick_weighted(_rng)
	# Ramp large in during 20-60 s; rare only after ramp_end (or via surge).
	if t < balance.ramp_end_time and pick.type == CollectibleDef.Type.CELL_LARGE:
		var ramp_t: float = (t - balance.free_growth_window) / maxf(0.001, balance.ramp_end_time - balance.free_growth_window)
		if _rng.randf() > ramp_t:
			return t_medium
	if pick.type == CollectibleDef.Type.SHARD_RARE:
		if t < balance.ramp_end_time or collectibles.rare_count() >= balance.max_rare_alive:
			return t_large
	return pick


## §11 validity checks. Returns a position that passes all of them.
func find_valid_collectible_position() -> Vector3:
	var radius: float = validity_radius - 4.0
	for attempt in balance.spawn_retry_attempts:
		var pos: Vector3 = _random_ring_pos(radius)
		if _pos_valid(pos, balance.collectible_min_spawn_distance):
			return pos
	# Poisson-disc fallback: scan the precomputed candidate set.
	var start: int = _rng.randi() % _candidates.size()
	for i in _candidates.size():
		var pos: Vector3 = _candidates[(start + i) % _candidates.size()]
		if _pos_valid(pos, balance.collectible_min_spawn_distance):
			return pos
	return _candidates[start]


## AI spawn point (§11: 22 from player general rule; respawns use 45 —
## "at least 45 units from the player"; initial spawns use 35 for the
## §3.6 free-growth window). Caller passes the required minimum distance.
func find_ai_spawn_position(min_player_dist: float = -1.0) -> Vector3:
	if min_player_dist < 0.0:
		min_player_dist = balance.ai_min_spawn_distance
	var radius: float = validity_radius - 4.0
	for attempt in balance.spawn_retry_attempts:
		var pos: Vector3 = _random_ring_pos(radius)
		if _pos_valid(pos, min_player_dist):
			return pos
	return _candidates[_rng.randi() % _candidates.size()]


func _pos_valid(pos: Vector3, min_player_dist: float) -> bool:
	if pos.length() > validity_radius - 4.0:
		return false
	if player_snake != null and pos.distance_to(player_snake.global_position) < min_player_dist:
		return false
	if _near_trail(pos, SEGMENT_CLEARANCE):
		return false
	return true


## Segment clearance: sample the player trail (history + head). O(trail);
## startup cost is one-time, steady-state spawns are single retries.
func _near_trail(pos: Vector3, clearance: float) -> bool:
	if player_snake == null:
		return false
	var history: PositionHistory = player_snake.get_history()
	if history == null or history.count == 0:
		return pos.distance_to(player_snake.global_position) < clearance
	var arc: float = history.newest_arc()
	var step: float = maxf(0.3, arc / 80.0)
	var a: float = 0.0
	while a <= arc:
		if pos.distance_to(history.read_at_arc(a, 0)) < clearance:
			return true
		a += step
	return false


func _random_ring_pos(radius: float) -> Vector3:
	var ang: float = _rng.randf() * TAU
	var r: float = radius * sqrt(_rng.randf())
	return Vector3(cos(ang) * r, 0.0, sin(ang) * r)


## §3.6 Surge: 40 collectibles + 1 rare at a random point, announced by a
## light beam. Spawns stagger over ~1.2 s so the cluster forms organically.
func _tick_surge(delta: float) -> void:
	if _surge_active:
		_surge_queue_timer -= delta
		if _surge_queue_timer <= 0.0:
			_surge_queue_timer = balance.surge_spawn_stagger
			if _surge_queue > 0:
				_surge_queue -= 1
				var def: CollectibleDef = table.pick_weighted(_rng)
				var offset: Vector3 = Vector3(_rng.randf_range(-3.0, 3.0), 0.0, _rng.randf_range(-3.0, 3.0))
				collectibles.spawn_collectible(def, _surge_pos + offset)
			elif _surge_rare_queue > 0:
				_surge_rare_queue -= 1
				var rare: CollectibleDef = table.get_def(CollectibleDef.Type.SHARD_RARE)
				collectibles.spawn_collectible(rare, _surge_pos)
			else:
				_surge_active = false
	_beam_timer -= delta
	if _beam_timer <= 0.0:
		_beam.visible = false
	if not _surge_active and _next_surge_time > 0.0 and _game_time >= _next_surge_time:
		_start_surge()
		_next_surge_time = _game_time + balance.surge_interval


func _start_surge() -> void:
	_surge_pos = find_valid_collectible_position()
	_surge_queue = balance.surge_collectible_count
	_surge_rare_queue = balance.surge_rare_count
	_surge_queue_timer = 0.0
	_surge_active = true
	_surge_claimed = false
	_beam.global_position = _surge_pos + Vector3(0.0, 12.0, 0.0)
	_beam.visible = true
	_beam_timer = balance.surge_beam_time
	EventBus.surge_started.emit(_surge_pos)


## §12.3: first snake to the surge cluster claims the bonus.
func try_claim_surge(pos: Vector3) -> bool:
	if not _surge_active or _surge_claimed:
		return false
	if pos.distance_to(_surge_pos) < balance.surge_claim_radius:
		_surge_claimed = true
		return true
	return false


## Precomputed Poisson-disc-ish candidate set for fallback spawns (§11).
func _precompute_candidates() -> void:
	var radius: float = validity_radius - 4.0
	var attempt: int = 0
	while _candidates.size() < POISSON_MAX_CANDIDATES and attempt < POISSON_MAX_CANDIDATES * 30:
		attempt += 1
		var pos: Vector3 = _random_ring_pos(radius)
		var ok: bool = true
		for c in _candidates:
			if pos.distance_to(c) < POISSON_MIN_DIST:
				ok = false
				break
		if ok:
			_candidates.append(pos)


func _make_beam() -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "SurgeBeam"
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.6
	cyl.height = 24.0
	mi.mesh = cyl
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.9, 0.95, 1.0, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.85, 1.0)
	mat.emission_energy_multiplier = 1.5
	mi.material_override = mat
	mi.visible = false
	return mi
