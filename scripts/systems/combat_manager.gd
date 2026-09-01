class_name CombatManager
extends Node
## §9/§12 — Conflict resolution. Owns the eat rules, head-vs-body detection,
## the death sequence (dissolve + staggered corpse motes), absorb rewards,
## hit-stop, camera trauma, the threat rim-light pass, and the arena shrink
## (§3.6). Scene-level node created by arena.gd (decision #25).
##
## Combat model (decision #44): per-pair recent-trail walk with head-
## distance prefilter, instead of re-inserting every body segment into the
## SpatialHash each tick. Same semantics as §6.4's hash broadphase (custom,
## no physics bodies) at a fraction of the rebuild cost — bodies are dense
## trails, so near-head windows are the only segments that can collide.
##
## Owns: the §9 matrix, death bookkeeping, shrink state.
## Does NOT own: input (suspension via InputManager), the game-over panel
##               (Phase 8), power-up interactions (PowerUpManager, Phase 7 —
##               aegis consult arrives via an injectable Callable).
## Talks to: snakes (read/write), CollectibleManager (motes),
##            ScoreManager (kill score), AIDirector (deaths), arena (trauma).

enum HitOutcome { NONE, SELF_DIES, OTHER_DIES, BOTH_DIE }

const PLAYER_GROUP: StringName = &"player"

@export var balance: GameBalanceConfig = preload("res://resources/config/game_balance.tres")

var collectibles: CollectibleManager = null
var score_manager: ScoreManager = null
var ai_director: AIDirector = null
var rig: Node = null  # CameraRig — trauma target
var arena_owner: Node = null
## Cached player reference (set by arena.setup_world) — no group scans in
## the hot path (§19).
var player_snake: SnakeController = null

## Injectable aegis consult (Phase 7): func(snake) -> bool. Null until
## PowerUpManager wires itself; must never be called when null.
var aegis_query: Callable = Callable()

var _dying: Array[Dictionary] = []  # {snake, t, total_motes, spawned, path: Array[Vector3], killer}
var _hit_stop_deadline_ms: int = -1
var _tick_counter: int = 0
## Arena shrink state (§3.6).
var _shrink_active: bool = false
var _current_radius: float = 0.0
var _elapsed: float = 0.0
## Combat telemetry (§19 budget).
var combat_us_max: float = 0.0
var _combat_us_history: Array[float] = []


func _ready() -> void:
	_current_radius = balance.arena_radius


## The §9 matrix as a pure function — table-tested.
## is_head_to_head: both heads collide; otherwise my head hit their body.
## Scaled-integer comparison (×10 vs ×11) avoids float-boundary wobble at
## exactly 1.10× (caught by the table test: 110.0 vs 100×1.10 flips on
## float error).
static func resolve_hit(my_power: float, other_power: float, is_head_to_head: bool) -> HitOutcome:
	if my_power <= 0.0 or other_power <= 0.0:
		return HitOutcome.NONE
	var mine10: float = my_power * 10.0
	var theirs11: float = other_power * 11.0
	var theirs10: float = other_power * 10.0
	var mine11: float = my_power * 11.0
	if is_head_to_head:
		if mine10 > theirs11:
			return HitOutcome.OTHER_DIES
		if theirs10 > mine11:
			return HitOutcome.SELF_DIES
		return HitOutcome.BOTH_DIE
	# My head into their body: I only survive if I'm big enough.
	if mine10 >= theirs11:
		return HitOutcome.OTHER_DIES
	return HitOutcome.SELF_DIES


func tick(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	_elapsed += delta
	_tick_counter += 1
	_tick_collisions()
	_tick_dying(delta)
	if _tick_counter % balance.rim_update_ticks == 0:
		_tick_rim_lights()
	_tick_shrink(delta)
	_tick_hit_stop()
	var us: int = Time.get_ticks_usec() - t0
	_combat_us_history.append(float(us) / 1000.0)
	if _combat_us_history.size() > 60:
		_combat_us_history.pop_front()
		combat_us_max = 0.0
		for v in _combat_us_history:
			combat_us_max = maxf(combat_us_max, v)


# --- collision -------------------------------------------------------------

func _tick_collisions() -> void:
	var snakes: Array[SnakeController] = _live_snakes()
	for i in snakes.size():
		var a: SnakeController = snakes[i]
		for j in range(i + 1, snakes.size()):
			var b: SnakeController = snakes[j]
			_resolve_pair(a, b)


func _resolve_pair(a: SnakeController, b: SnakeController) -> void:
	var head_dist: float = a.global_position.distance_to(b.global_position)
	var head_radius_sum: float = a.current_radius + b.current_radius
	# Head-to-head (§9).
	if head_dist <= head_radius_sum:
		var outcome: HitOutcome = resolve_hit(a.power, b.power, true)
		_apply_outcome(outcome, a, b)
		return
	# Head-to-body (§9): only possible if b's body spans near a's head.
	var b_body_span: float = b.segment_count() * b.current_radius * 1.4 + 4.0
	if head_dist > b_body_span:
		return
	if _head_hits_trail(a, b):
		var outcome2: HitOutcome = resolve_hit(a.power, b.power, false)
		_apply_outcome(outcome2, a, b)
		if outcome2 == HitOutcome.SELF_DIES:
			# a died on b's body; still check b's head on a's body.
			if not a.alive and _head_hits_trail(b, a) \
					and b.power >= a.power * 1.10:
				_apply_outcome(HitOutcome.OTHER_DIES, b, a)


## a's head against b's recent trail (newest-first samples).
func _head_hits_trail(a: SnakeController, b: SnakeController) -> bool:
	if not a.alive or not b.alive:
		return false
	var trail: Array = []
	b.history.trail_samples(trail, 1200)
	var hit_r: float = a.current_radius + b.current_radius
	var head: Vector3 = a.global_position
	for k in range(0, trail.size(), 4):
		if (trail[k] as Vector3).distance_to(head) <= hit_r:
			return true
	return false


func _apply_outcome(outcome: HitOutcome, a: SnakeController, b: SnakeController) -> void:
	match outcome:
		HitOutcome.OTHER_DIES:
			_kill(b, a)
		HitOutcome.SELF_DIES:
			_kill(a, b)
		HitOutcome.BOTH_DIE:
			_kill(a, b, true)
			_kill(b, a, true)
		_:
			pass


# --- death -----------------------------------------------------------------

func _kill(victim: SnakeController, killer: SnakeController, mutual: bool = false) -> void:
	if not victim.alive:
		return
	# Invulnerability protects the VICTIM only — an invulnerable snake can
	# still attack freely (revive grace, harness god-mode).
	if _is_invulnerable(victim):
		return
	# Phase 7 hook: aegis consumes the death instead.
	if aegis_query.is_valid() and aegis_query.call(victim):
		return
	victim.alive = false
	var victim_power: float = victim.power
	# §9: dropped mass as corpse motes along the body's last path,
	# staggered 0.35 s so it looks like a dissolving trail.
	var dropped: float = victim_power * victim.config.dropped_mass_fraction
	var mote_count: int = clampi(int(floor(dropped / victim.config.corpse_mote_power_divisor)),
		victim.config.corpse_mote_min_count, victim.config.corpse_mote_max_count)
	var path: Array[Vector3] = []
	victim.history.trail_samples(path, mote_count)
	var entry: Dictionary = {
		"snake": victim, "t": 0.0, "total_motes": mote_count, "spawned": 0,
		"path": path, "per_mote": dropped / float(mote_count),
		"killer": killer, "mutual": mutual,
	}
	_dying.append(entry)
	# Absorb rewards (§9/§12.3). No reward in a mutual kill.
	if killer != null and killer.alive and not mutual:
		var absorbed: float = victim_power * victim.config.absorbed_power_fraction
		killer.add_power(absorbed)
		if killer.is_in_group(PLAYER_GROUP) and score_manager != null:
			var reward: float = balance.kill_score_base + floor(victim_power * balance.kill_score_power_factor)
			score_manager.add_score(reward)
			EventBus.collectible_absorbed.emit(99, reward)
			Analytics.track(&"absorb", {"victim_power": victim_power, "reward": reward})
	# Signals + analytics.
	victim.died.emit(victim)
	EventBus.snake_died.emit(killer.get_instance_id() if killer != null else -1, victim.get_instance_id())
	Analytics.track(&"snake_died", {"killer": killer != null, "victim_power": victim_power, "mutual": mutual})
	# Feel: hit-stop + camera trauma (§12.1).
	_trigger_hit_stop()
	if rig != null:
		rig.add_trauma(balance.die_trauma if victim.is_in_group(PLAYER_GROUP) else balance.eat_trauma)
	# Player death: freeze input, mark DYING.
	if victim.is_in_group(PLAYER_GROUP):
		InputManager.set_suspended(true)
		EventBus.player_died.emit()
		GameManager.request_state(GameManager.State.DYING)


## Per-tick: dissolve victims (scale-down + emissive flash), stagger motes.
func _tick_dying(delta: float) -> void:
	for i in range(_dying.size() - 1, -1, -1):
		var e: Dictionary = _dying[i]
		e["t"] = float(e["t"]) + delta
		var snake: SnakeController = e["snake"]
		var progress: float = clampf(float(e["t"]) / 0.55, 0.0, 1.0)
		# Staggered mote spawns along the stored path (§9: 0.35 s apart).
		var due: int = mini(e["total_motes"], int(floor(float(e["t"]) / snake.config.corpse_mote_stagger)))
		while int(e["spawned"]) < due:
			var idx: int = int(e["spawned"])
			var pos: Vector3 = e["path"][idx] if idx < (e["path"] as Array).size() else snake.global_position
			collectibles.drop_mote(pos, float(e["per_mote"]), 0.0)
			e["spawned"] = idx + 1
		# Dissolve visuals: scale the body down, flash emissive.
		var mmi: MultiMeshInstance3D = snake.body.mmi
		var scale: float = lerpf(1.0, 0.05, progress)
		mmi.scale = Vector3(scale, scale, scale)
		if progress >= 1.0:
			mmi.visible = false
			if snake.body.head_mesh != null:
				snake.body.head_mesh.visible = false
			_dying.remove_at(i)
			_finalize_death(snake)
			continue


func _finalize_death(snake: SnakeController) -> void:
	# Player: DYING → GAME_OVER after the dissolve (panel arrives Phase 8).
	if snake.is_in_group(PLAYER_GROUP):
		if GameManager.current_state == GameManager.State.DYING:
			GameManager.request_state(GameManager.State.GAME_OVER)
		return
	# AI: director schedules the §11 respawn (2.5 s) and the node is freed.
	if ai_director != null:
		ai_director.on_ai_combat_death(snake)
	if snake.get_parent() != null:
		snake.get_parent().queue_free()


func _is_invulnerable(snake: SnakeController) -> bool:
	# Revive grace (Phase 8) lives in the player controller.
	return snake.has_meta("invulnerable_until") and float(snake.get_meta("invulnerable_until")) > _elapsed


## Harness/test aid: make the player invulnerable (god mode).
func set_player_invulnerable(until_elapsed: float) -> void:
	for s in _live_snakes():
		if s.is_in_group(PLAYER_GROUP):
			s.set_meta("invulnerable_until", until_elapsed)


# --- rim lights (§9 readability) -------------------------------------------

## Player-relative threat rim lights, refreshed every 4 physics ticks:
## can eat ME → red-tinted emission; I can eat IT → green. Applied to the
## body MultiMesh material (emission colour) + head mesh. This is the
## single most important UX feature in the game (§9).
func _tick_rim_lights() -> void:
	var player: SnakeController = _player()
	if player == null or not player.alive:
		return
	for s in _live_snakes():
		if s == player:
			continue
		var tint: Color = Color(0.08, 0.08, 0.12)
		# >= (not >) matches the §9 body-eat rule at exactly 1.10×; threat
		# wins ties — the player should always err on the side of caution.
		if s.power * 10.0 >= player.power * 11.0:
			tint = Color(0.85, 0.10, 0.10)   # threat: red
		elif player.power * 10.0 >= s.power * 11.0:
			tint = Color(0.15, 0.85, 0.25)   # prey: green
		_apply_tint(s, tint)


func _apply_tint(s: SnakeController, tint: Color) -> void:
	var mat: StandardMaterial3D = s.body.mmi.material_override
	if mat == null:
		return
	mat.emission = tint
	if s.body.head_mesh != null:
		var head_mat: StandardMaterial3D = s.body.head_mesh.material_override as StandardMaterial3D
		if head_mat == null:
			head_mat = StandardMaterial3D.new()
			head_mat.vertex_color_use_as_albedo = true
			head_mat.emission_enabled = true
			head_mat.emission_energy_multiplier = 1.2
			s.body.head_mesh.material_override = head_mat
		head_mat.emission = tint


# --- arena shrink (§3.6) ----------------------------------------------------

func set_elapsed(total: float) -> void:
	# Test/harness aid: jumps the session clock (shrink timing).
	_elapsed = total


func _tick_shrink(delta: float) -> void:
	if _elapsed < balance.shrink_start_time or _current_radius <= balance.shrink_floor_radius:
		return
	if not _shrink_active:
		_shrink_active = true
		EventBus.arena_shrinking.emit(_current_radius)
		print("CC_ARENA_COLLAPSING radius=%.1f" % _current_radius)
	_current_radius = maxf(balance.shrink_floor_radius, _current_radius - balance.shrink_rate * delta)
	# Progress ping at ~1 Hz for the HUD ring, not every frame.
	if _tick_counter % 60 == 0:
		EventBus.arena_shrinking.emit(_current_radius)


func current_radius() -> float:
	return _current_radius


func is_shrinking() -> bool:
	return _shrink_active


# --- hit-stop (§12.1) -------------------------------------------------------

var _hit_stop_recovering: bool = false


func _trigger_hit_stop() -> void:
	_hit_stop_deadline_ms = Time.get_ticks_msec() + int(balance.hit_stop_duration * 1000.0)
	_hit_stop_recovering = false
	Engine.time_scale = balance.hit_stop_scale


func _tick_hit_stop() -> void:
	if _hit_stop_deadline_ms < 0:
		return
	var now_ms: int = Time.get_ticks_msec()
	if not _hit_stop_recovering:
		if now_ms >= _hit_stop_deadline_ms:
			_hit_stop_recovering = true
			_hit_stop_deadline_ms = now_ms + int(balance.hit_stop_recover * 1000.0)
		return
	var span: float = balance.hit_stop_recover * 1000.0
	var t: float = clampf(1.0 - float(_hit_stop_deadline_ms - now_ms) / maxf(span, 1.0), 0.0, 1.0)
	Engine.time_scale = lerpf(balance.hit_stop_scale, 1.0, t)
	if now_ms >= _hit_stop_deadline_ms:
		Engine.time_scale = 1.0
		_hit_stop_deadline_ms = -1


func hit_stop_active() -> bool:
	return _hit_stop_deadline_ms >= 0


# --- helpers ----------------------------------------------------------------

func _live_snakes() -> Array[SnakeController]:
	var out: Array[SnakeController] = []
	if player_snake != null and player_snake.alive:
		out.append(player_snake)
	if ai_director != null:
		for ai in ai_director.ai_controllers:
			if ai.snake != null and ai.snake.alive:
				out.append(ai.snake)
	return out


func _player() -> SnakeController:
	return player_snake


func alive_count() -> int:
	return _live_snakes().size()


func player_alive() -> bool:
	var p: SnakeController = _player()
	return p != null and p.alive
