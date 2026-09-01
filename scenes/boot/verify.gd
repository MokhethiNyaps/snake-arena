extends Node3D
## Phases 2+3 verification harness. Runs the REAL arena + player scenes and
## drives them with simulated input (Input.parse_input_event), asserting
## each phase's exit criteria and saving a screenshot.
##
## Run:  xvfb-run -a -s "-screen 0 1280x720x24" \
##         godot --path . --resolution 1280x720 res://scenes/boot/verify.tscn
## Headless assertions only (no screenshot): add --headless.
## Exit code: 0 = PASS, 1 = FAIL (with CC_VERIFY_FAIL reason printed).

var _arena: Node3D = null
var _player: Node3D = null
var _snake: SnakeController = null
var _rig: CameraRig = null
var _phase: int = 0
var _phase_frames: int = 0
var _heading_frames: int = 0
var _boost_frames: int = 0
var _boost_start_power: float = 0.0
var _boost_drain_sum: float = 0.0
var _last_boost_power: float = 0.0
var _start_pos: Vector3 = Vector3.ZERO
var _big_start_pos: Vector3 = Vector3.ZERO
var _path_length: float = 0.0
var _last_head_pos: Vector3 = Vector3.ZERO
var _fail_reason: String = ""
# Phase 3 (economy) scenario state.
var _econ_power_before: float = 0.0
var _econ_score_before: float = 0.0
var _econ_absorb_count: int = 0
var _econ_motes_before: int = 0
var _econ_boost_start: float = 0.0
## Minimum power observed while the boost key was held (drain evidence even
## if incidental collects raise power mid-boost).
var _min_power_during_boost: float = 0.0
var _econ_boost_drain_sum: float = 0.0
var _last_econ_boost_power: float = 0.0
# Phase 4 (ad scaffolding) scenario state.
var _ad_entered: bool = false
var _ad_contract_ok: bool = false
var _ad_rewarded_ok: bool = false
var _ad_timeout_ok: bool = false
var _panel_was_visible: bool = false
# Phase 5 (AI opponents) scenario state.
var _ai_start_pos: Dictionary = {}
var _ai_seen_states: Dictionary = {}
var _ai_path: Dictionary = {}
var _ai_last_pos: Dictionary = {}
var _ai_track_ticks: Dictionary = {}
var _ai_track_start_ms: Dictionary = {}
# Wall-clock phase entry (combat hit-stop can stall physics ticks).
var _phase_wall_start: int = 0


func _phase_waited_s() -> float:
	return float(Time.get_ticks_msec() - _phase_wall_start) / 1000.0


# Phase 6 (conflict) scenario state.
var _kill_power_before: float = 0.0
var _kill_score_before: float = 0.0
var _kill_victim_power: float = 0.0
var _kill_victim_id: int = -1
var _kill_victim: SnakeController = null
var _kill_start_count: int = 0
var _kill_hit_stop_seen: bool = false
var _kill_rim_green_seen: bool = false
var _kill_detected_at_ms: int = -1
var _kill_dying_entry: Dictionary = {}
var _kill_attempts: int = 0
var _kill_verified: bool = false
var _kill_done: bool = false
var _die_seen: bool = false

var _max_frame_ms: float = 0.0
var _frame_samples: int = 0
var _frame_acc_ms: float = 0.0


func _ready() -> void:
	# The ad contract pauses the whole tree; the harness driver must keep
	# ticking regardless (PROCESS_MODE_ALWAYS) or scenario D deadlocks.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_world()
	# Combat is live from Phase 6 on: AI can legitimately kill the player.
	# Phases 0-17 need the player ALIVE, so god-mode until the death
	# scenario (phase 20) — the player can still attack during god-mode.
	_snake.set_meta("invulnerable_until", 1.0e9)


func _build_world() -> void:
	# Replicate the boot sequence: the PlayerController only drives the
	# snake while GameManager is PLAYING.
	GameManager.request_state(GameManager.State.LOADING)
	_arena = (load("res://scenes/arena/arena.tscn") as PackedScene).instantiate()
	add_child(_arena)
	_player = (load("res://scenes/player/player_snake.tscn") as PackedScene).instantiate()
	add_child(_player)
	_snake = _player.get_node("Snake")
	_rig = _player.get_node("CameraRig")
	_rig.set_target(_snake)
	# Phase 3: wire the economy exactly like boot.gd does.
	_arena.setup_world(_player, _snake)
	GameManager.request_state(GameManager.State.PLAYING)
	# Player starts at origin; give the rig a frame to snap.
	print("CC_VERIFY_START")


var _finished: bool = false


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_phase_frames += 1
	# Frame-time budget sampling (sandbox llvmpipe numbers are NOT target
	# hardware — this is regression detection only).
	var frame_ms: float = delta * 1000.0
	_frame_acc_ms += frame_ms
	_frame_samples += 1
	_max_frame_ms = maxf(_max_frame_ms, frame_ms)
	# Path-length accumulation (head velocity integrated per frame).
	if _phase >= 5 and _snake != null:
		_path_length += _snake.global_position.distance_to(_last_head_pos)
		_last_head_pos = _snake.global_position
	elif _snake != null:
		_last_head_pos = _snake.global_position
	match _phase:
		0:  # settle: 30 ticks (0.5 s)
			if _phase_frames >= 30:
				_enter_phase(1)
		1:  # drive right for 240 ticks (4 s), then release
			Input.parse_input_event(_key(KEY_D, true))
			_heading_frames += 1
			if _heading_frames >= 240:
				Input.parse_input_event(_key(KEY_D, false))
				_enter_phase(2)
		2:  # hold boost 90 ticks (1.5 s) — power must drain, boosting flag on
			# §3.4: boost is disallowed at power <= 4.0; the snake spawns at
			# 2.0, so simulate early growth first (as collectibles would).
			if _boost_frames == 0:
				_snake.add_power(10.0)
				_boost_start_power = _snake.power
				_min_power_during_boost = _snake.power
				_last_boost_power = _snake.power
			Input.parse_input_event(_key(KEY_SPACE, true))
			# Cumulative per-tick decrease: re-collecting shed/foreign motes
			# can spike power UP mid-boost, but the drain ticks still cost.
			_boost_drain_sum += maxf(0.0, _last_boost_power - _snake.power)
			_last_boost_power = _snake.power
			_boost_frames += 1
			_min_power_during_boost = minf(_min_power_during_boost, _snake.power)
			if _snake != null and not _snake.boosting and _boost_frames > 10:
				_fail("boost did not engage (power=%.1f min=%.1f)" % [_snake.power, _snake.config.min_boost_power])
				return
			if _boost_frames >= 90:
				Input.parse_input_event(_key(KEY_SPACE, false))
				_enter_phase(3)
		3:  # settle after boost, then small-snake checks
			if _phase_frames >= 30:
				_checks_small()
		4:  # grow to 60 segments (phase exit criterion): pump power to 190
			# (formula: 6 + floor(190/3.5) = 60), then wait for the +1
			# segment/tick growth plus per-segment ease-in to settle.
			if _phase_frames == 1:
				_snake.add_power(190.0 - _snake.power)
			if _phase_frames >= 90:
				var want: int = _snake._segments_for_power(_snake.power)
				if _snake.get_segment_count() != want:
					_fail("60-segment growth stalled: %d != %d (power=%.1f)" % [
						_snake.get_segment_count(), want, _snake.power])
					return
				print("CC_VERIFY_BIG segs=%d power=%.1f" % [_snake.get_segment_count(), _snake.power])
				_enter_phase(5)
		5:  # weave the 60-segment snake for 180 ticks (3 s): right, then left
			if _phase_frames == 1:
				_big_start_pos = _snake.global_position
				_path_length = 0.0
				_last_head_pos = _snake.global_position
			Input.parse_input_event(_key(KEY_D if _phase_frames <= 90 else KEY_A, true))
			Input.parse_input_event(_key(KEY_A if _phase_frames <= 90 else KEY_D, false))
			if _phase_frames >= 180:
				Input.parse_input_event(_key(KEY_A, false))
				_enter_phase(6)
		6:  # settle, then big-snake checks + economy scenario (Phase 3)
			if _phase_frames >= 30:
				_checks_big()
		7:  # economy settle: wait for the 420 population, then plant a
			# collectible directly ahead of the snake to guarantee a pickup
			if _phase_frames >= 120:
				_fail("collectible population never reached 420 (non-mote=%d)" % _arena.collectible_manager.non_mote_count())
				return
			if _arena.collectible_manager.non_mote_count() >= 420:
				var cm: CollectibleManager = _arena.collectible_manager
				var def: CollectibleDef = cm.table.get_def(CollectibleDef.Type.CELL_LARGE)
				var fwd: Vector3 = Vector3(sin(deg_to_rad(_snake.facing_angle_deg)), 0.0, cos(deg_to_rad(_snake.facing_angle_deg)))
				var plant_pos: Vector3 = _snake.global_position + fwd * 4.0
				cm.spawn_collectible(def, plant_pos)
				_econ_power_before = _snake.power
				_econ_score_before = _arena.score_manager.get_score()
				_enter_phase(8)
		8:  # drive straight over the planted collectible
			if _phase_frames >= 90:
				var cm2: CollectibleManager = _arena.collectible_manager
				if _snake.power < _econ_power_before + 8.0 - 0.01:
					_fail("planted CELL_LARGE not absorbed: power %.1f -> %.1f" % [_econ_power_before, _snake.power])
					return
				if _arena.score_manager.get_score() < _econ_score_before + 100.0 * 1.05 - 0.01:
					_fail("score/combo not applied: %.1f -> %.1f" % [_econ_score_before, _arena.score_manager.get_score()])
					return
				if _arena.score_manager.get_combo() < 1:
					_fail("combo did not register")
					return
				print("CC_VERIFY_PICKUP power=%.1f score=%.1f combo=%d alive=%d" % [
					_snake.power, _arena.score_manager.get_score(),
					_arena.score_manager.get_combo(), cm2.non_mote_count()])
				_enter_phase(9)
		9:  # boost 40 ticks: §3.4 shed motes must appear behind the snake
			if _phase_frames == 1:
				_econ_boost_start = _snake.power
				_min_power_during_boost = _snake.power
				_econ_boost_drain_sum = 0.0
				_last_econ_boost_power = _snake.power
				_econ_motes_before = _arena.collectible_manager.mote_count()
			Input.parse_input_event(_key(KEY_SPACE, true))
			_min_power_during_boost = minf(_min_power_during_boost, _snake.power)
			_econ_boost_drain_sum += maxf(0.0, _last_econ_boost_power - _snake.power)
			_last_econ_boost_power = _snake.power
			if _phase_frames >= 40:
				Input.parse_input_event(_key(KEY_SPACE, false))
				_enter_phase(10)
		10:  # settle, then economy checks, then the ad scenario (Phase 4)
			if _phase_frames >= 15:
				_checks_economy()
		11:  # debug ad panel: F3 toggles it (§20); leave it visible
			if _phase_frames == 1:
				var panel: CanvasLayer = AdManager.get_debug_panel()
				if panel == null:
					_fail("debug ad panel missing (debug build required)")
					return
				Input.parse_input_event(_key(KEY_F3, true))
				Input.parse_input_event(_key(KEY_F3, false))
			if _phase_frames == 5:
				var panel2: CanvasLayer = AdManager.get_debug_panel()
				if not panel2.get_node("Root").visible:
					_fail("F3 did not show the debug ad panel")
					return
				_panel_was_visible = true
				_enter_phase(12)
		12:  # trigger a MOCK REWARDED ad from the panel: contract must
			# pause/duck/suspend/overlay, then restore + reward
			if _phase_frames == 1:
				var panel3: CanvasLayer = AdManager.get_debug_panel()
				panel3._on_fill_changed(100.0)
				panel3._on_latency_changed(0.1)
				panel3._on_auto_close_changed(1.0)
				panel3._on_outcome_changed(AdProviderMock.ForcedOutcome.COMPLETED)
				panel3.trigger_rewarded()
			if not _ad_entered and not AdManager._busy and _phase_frames > 20:
				_fail("rewarded ad never engaged (frames=%d)" % _phase_frames)
				return
			if AdManager._busy and not _ad_entered:
				_ad_entered = true
				# §45.6 contract: paused + ducked + suspended + overlay.
				_ad_contract_ok = get_tree().paused \
					and AudioManager._ducked \
					and InputManager.is_suspended() \
					and AdManager._overlay.visible
				if not _ad_contract_ok:
					_fail("ad contract not fully engaged (paused=%s ducked=%s suspended=%s overlay=%s)" % [
						get_tree().paused, AudioManager._ducked,
						InputManager.is_suspended(), AdManager._overlay.visible])
					return
			if _ad_entered and not AdManager._busy:
				# Resolved: contract must be fully restored.
				var panel4: CanvasLayer = AdManager.get_debug_panel()
				var restored: bool = not get_tree().paused \
					and not AudioManager._ducked \
					and not InputManager.is_suspended() \
					and not AdManager._overlay.visible \
					and GameManager.current_state == GameManager.State.PLAYING
				var rewarded: bool = panel4.last_result_code == AdResult.Code.SHOWN_COMPLETED and panel4.last_rewarded
				_ad_rewarded_ok = restored and rewarded
				if not _ad_rewarded_ok:
					_fail("rewarded ad restore/reward failed (restored=%s result=%d rewarded=%s)" % [
						restored, panel4.last_result_code, panel4.last_rewarded])
					return
				print("CC_VERIFY_AD_REWARDED ok contract=%s" % _ad_contract_ok)
				_enter_phase(13)
			if _phase_frames > 400:
				_fail("rewarded ad phase timed out")
				return
		13:  # FORCED TIMEOUT: the mandatory watchdog must unstick the game
			if _phase_frames == 1:
				_ad_entered = false
				# Combat is live now — clear any hit-stop so the ad phases
				# run at normal speed.
				Engine.time_scale = 1.0
				var panel5: CanvasLayer = AdManager.get_debug_panel()
				panel5._on_outcome_changed(AdProviderMock.ForcedOutcome.TIMEOUT)
				AdManager._config.show_watchdog_seconds = 1.0
				panel5.trigger_interstitial()
			if AdManager._busy and not _ad_entered:
				_ad_entered = true
			if _ad_entered and not AdManager._busy:
				var panel6: CanvasLayer = AdManager.get_debug_panel()
				var restored: bool = not get_tree().paused \
					and not AudioManager._ducked \
					and not InputManager.is_suspended() \
					and not AdManager._overlay.visible \
					and GameManager.current_state == GameManager.State.PLAYING
				_ad_timeout_ok = restored and panel6.last_result_code == AdResult.Code.TIMEOUT
				if not _ad_timeout_ok:
					_fail("timeout path failed (restored=%s result=%d)" % [restored, panel6.last_result_code])
					return
				print("CC_VERIFY_AD_TIMEOUT ok watchdog un-stuck the game")
				AdManager._config.show_watchdog_seconds = 90.0
				_enter_phase(14)
			if _phase_frames > 400:
				_fail("timeout ad phase timed out")
				return
		14:  # settle, then ad-scenario checks, then the AI scenario (Phase 5)
			if _phase_frames >= 20:
				_checks_ads()
		15:  # record the AI population baseline (§11: 8 AI, unique names).
			# Combat is LIVE from Phase 6 on, so an AI may have just died —
			# wait for the population to refill before sampling.
			if _phase_frames == 1:
				_phase_wall_start = Time.get_ticks_msec()
			var director: AIDirector = _arena.ai_director
			if director.get_ai_count() >= director.balance.ai_count:
				var names: Dictionary = {}
				for ai in director.ai_controllers:
					if names.has(ai.display_name):
						_fail("AI name reused in match: %s" % ai.display_name)
						return
					names[ai.display_name] = true
					# Skip corpses mid-dissolve: a dead snake can't move and
					# would fail the movement check with 0 path.
					if ai.snake == null or not ai.snake.alive:
						continue
					var id: int = ai.get_instance_id()
					_ai_start_pos[id] = ai.snake.global_position
					_ai_last_pos[id] = ai.snake.global_position
					_ai_path[id] = 0.0
					_ai_track_ticks[id] = 0
					_ai_track_start_ms[id] = Time.get_ticks_msec()
					_ai_seen_states[str(ai._fsm.current_name())] = true
				print("CC_VERIFY_AI_SPAWNED count=%d names=%s" % [director.get_ai_count(), ", ".join(names.keys())])
				_enter_phase(16)
			elif _phase_waited_s() > 10.0:
				_fail("AI population never reached %d (count=%d)" % [director.balance.ai_count, director.get_ai_count()])
				return
		16:  # watch the AI play for ~6 s of WALL time (combat + hit-stop can
			# slow physics ticks; frame counts would stall the harness)
			for ai in _arena.ai_director.ai_controllers:
				if ai.snake == null or not ai.snake.alive:
					continue
				var id: int = ai.get_instance_id()
				if not _ai_path.has(id):
					# Died + respawned mid-window: start tracking the new one.
					_ai_path[id] = 0.0
					_ai_last_pos[id] = ai.snake.global_position
					_ai_start_pos[id] = ai.snake.global_position
					_ai_track_ticks[id] = 0
					_ai_track_start_ms[id] = Time.get_ticks_msec()
					continue
				_ai_path[id] = float(_ai_path[id]) + ai.snake.global_position.distance_to(_ai_last_pos[id])
				_ai_last_pos[id] = ai.snake.global_position
				_ai_track_ticks[id] = int(_ai_track_ticks[id]) + 1
			if _phase_frames % 60 == 0:
				for ai in _arena.ai_director.ai_controllers:
					_ai_seen_states[str(ai._fsm.current_name())] = true
			if _phase_waited_s() >= 6.0:
				_checks_ai_window()
		17:  # settle, then Phase 5 verdict → straight into the conflict
			# scenario (Phase 6)
			if _phase_frames == 1:
				_phase_wall_start = Time.get_ticks_msec()
			if _phase_waited_s() >= 0.6:
				_checks_ai_final()
		18:  # KILL: teleport the big player head into a small AI's body path
			if _phase_frames == 1:
				_phase_wall_start = Time.get_ticks_msec()
				var director: AIDirector = _arena.ai_director
				_kill_start_count = director.get_ai_count()
				_snake.power = 100.0
				_snake._update_derived_stats()
				_snake._sync_segment_target()
				# Pick a LIVE small AI and sample its rim state (should be
				# GREEN: the player can eat it).
				var victim: SnakeController = null
				for ai in director.ai_controllers:
					if ai.snake != null and ai.snake.alive:
						victim = ai.snake
						break
				if victim == null:
					await get_tree().create_timer(1.0, true).timeout
					for ai in director.ai_controllers:
						if ai.snake != null and ai.snake.alive:
							victim = ai.snake
							break
				if victim == null:
					_fail("no live AI to kill")
					return
				var mat: StandardMaterial3D = victim.body.mmi.material_override
				if mat != null and mat.emission.g > mat.emission.r:
					_kill_rim_green_seen = true
				_kill_victim_power = victim.power
				_kill_victim_id = victim.get_instance_id()
				_kill_power_before = _snake.power
				_kill_score_before = _arena.score_manager.get_score()
				# Teleport the head onto the victim's recent trail →
				# head-into-body contact on the next combat tick.
				var trail: Array = []
				victim.history.trail_samples(trail, 40)
				var hit_point: Vector3 = trail[8]
				_snake.global_position = hit_point
				_kill_victim = victim
				print("CC_VERIFY_KILL victim_power=%.1f player_power=%.1f rim_green=%s count=%d dist=%.2f" % [
					_kill_victim_power, _snake.power, _kill_rim_green_seen, _kill_start_count,
					_snake.global_position.distance_to(victim.global_position)])
			# Sample the hit-stop window.
			if Engine.time_scale < 1.0:
				_kill_hit_stop_seen = true
			# Detect the kill the moment the victim dies (direct reference —
			# the registry only drops it at dissolve end, by which time the
			# dying entry is already gone).
			if _kill_detected_at_ms < 0 and _kill_victim != null \
					and not _kill_victim.alive:
				_kill_detected_at_ms = Time.get_ticks_msec()
				# Capture the victim's dying entry AT the kill instant: the
				# dissolve removes it after 0.55 s, but the dictionary
				# reference keeps its final state (mote spawn count).
				for e in _arena.combat_manager._dying:
					if int((e["snake"] as SnakeController).get_instance_id()) == _kill_victim_id:
						_kill_dying_entry = e
						break
				if _kill_dying_entry.is_empty():
					# A third party died instead — my teleport missed.
					# Re-arm against another live victim (max 3 attempts).
					if _rearm_kill_attempt():
						_kill_detected_at_ms = -1
					else:
						_fail("victim never died to the player (attempts exhausted)")
						return
				else:
					var total: int = int(_kill_dying_entry["total_motes"])
					var cfg: SnakeConfig = _snake.config
					var expected_total: int = clampi(int(floor(_kill_victim_power * cfg.dropped_mass_fraction / cfg.corpse_mote_power_divisor)),
						cfg.corpse_mote_min_count, cfg.corpse_mote_max_count)
					if total != expected_total:
						_fail("corpse mote count %d != expected %d" % [total, expected_total])
						return
					print("CC_VERIFY_KILL_DETECTED motes_total=%d" % total)
			# 2.5 s after detection: staggered spawns must have started.
			# (The kill triggers hit-stop, which dilates game time ~0.6 s;
			# a 0.6 s real-time check could land before the first 0.35 s
			# stagger tick. The captured dict freezes at dissolve removal.)
			if _kill_detected_at_ms >= 0 and not _kill_verified \
					and Time.get_ticks_msec() - _kill_detected_at_ms > 2500:
				_kill_verified = true
				_verify_kill()
			if _phase_waited_s() > 12.0 and not _kill_done:
				_fail("kill scenario never resolved (count=%d start=%d detected=%d)" % [
					_arena.ai_director.get_ai_count(), _kill_start_count, _kill_detected_at_ms])
				return
		19:  # wait for the §11 respawn: AI count returns to 8 within ~6 s
			if _phase_frames == 1:
				_phase_wall_start = Time.get_ticks_msec()
			if _arena.ai_director.get_ai_count() >= _arena.ai_director.balance.ai_count:
				print("CC_VERIFY_RESPAWN ok count=%d" % _arena.ai_director.get_ai_count())
				_enter_phase(20)
			if _phase_waited_s() > 10.0:
				_fail("AI respawn never completed (count=%d)" % _arena.ai_director.get_ai_count())
				return
		20:  # VERBS: power-up pickup, cap, refresh, stat multipliers
			if _phase_frames == 1:
				_phase_wall_start = Time.get_ticks_msec()
				var pm: PowerUpManager = _arena.powerup_manager
				if pm == null or pm.alive_pickup_count() < 1:
					_fail("no power-ups alive (count=%d)" % (pm.alive_pickup_count() if pm else -1))
					return
				# Spawn SURGE exactly under the head: the next pickup tick
				# consumes it (overlap is immediate).
				pm.spawn_at(_snake.global_position, PowerUpDef.Effect.SURGE)
				await get_tree().create_timer(0.6, true).timeout
				var active: int = pm.active_count(_snake)
				var mult: float = _snake.stat_stack.get_multiplier(SnakeController.STAT_SPEED)
				print("CC_VERIFY_POWERUP surge_active=%d speed_mult=%.2f pickups=%d" % [
					active, mult, pm.alive_pickup_count()])
				if active < 1 or absf(mult - 1.35) > 0.01:
					_fail("surge pickup failed (active=%d mult=%.2f)" % [active, mult])
					return
				# Cap-3: three more types → SURGE (oldest) is evicted.
				pm.apply(_snake, pm.table.get_def(PowerUpDef.Effect.MAGNET))
				pm.apply(_snake, pm.table.get_def(PowerUpDef.Effect.AEGIS))
				pm.apply(_snake, pm.table.get_def(PowerUpDef.Effect.CHILL))
				var capped: int = pm.active_count(_snake)
				var capped_ok: bool = capped == pm.table.max_active_powerups
				# Refresh: re-apply SURGE (evicts MAGNET, count stays 3, and
				# SURGE's remaining time is longer than the stale -1).
				var before_refresh: float = pm.effect_remaining(_snake, PowerUpDef.Effect.SURGE)
				pm.apply(_snake, pm.table.get_def(PowerUpDef.Effect.SURGE))
				var after_refresh: float = pm.effect_remaining(_snake, PowerUpDef.Effect.SURGE)
				var refresh_ok: bool = pm.active_count(_snake) == 3 and after_refresh > before_refresh
				# Aegis consult WHILE active: consume once, then gone.
				var aegis_ok: bool = pm.has_aegis(_snake) and not pm.has_aegis(_snake)
				# Doubler last (its apply may evict whatever is oldest).
				pm.apply(_snake, pm.table.get_def(PowerUpDef.Effect.DOUBLER))
				var mult2: float = pm.collect_multiplier(_snake)
				print("CC_VERIFY_POWERUP2 cap=%d/%d capped=%s refresh=%.2f->%.2f doubler=%.1f aegis=%s" % [
					capped, pm.table.max_active_powerups, capped_ok, before_refresh, after_refresh, mult2, aegis_ok])
				if not (capped_ok and refresh_ok and absf(mult2 - 2.0) < 0.01 and aegis_ok):
					_fail("cap/refresh/doubler/aegis checks failed")
					return
				_enter_phase(21)
			if _phase_waited_s() > 8.0:
				_fail("powerup scenario never resolved")
				return
		21:  # settle, then Phase 7 verdict → death scenario
			if _phase_frames == 1:
				_phase_wall_start = Time.get_ticks_msec()
			if _phase_waited_s() >= 0.5:
				print("CC_VERIFY_PHASE7_PASS")
				_enter_phase(22)
		22:  # DIE: shrink the player, grow one AI, drive head into its body
			if _phase_frames == 1:
				_phase_wall_start = Time.get_ticks_msec()
				_snake.remove_meta("invulnerable_until")
				Engine.time_scale = 1.0
				_snake.power = 2.0
				_snake._update_derived_stats()
				_snake._sync_segment_target()
				var big: SnakeController = null
				for ai in _arena.ai_director.ai_controllers:
					if ai.snake != null and ai.snake.alive:
						big = ai.snake
						break
				if big == null:
					_fail("no live AI for the death scenario")
					return
				big.power = 120.0
				big._update_derived_stats()
				big._sync_segment_target()
				await get_tree().create_timer(0.5, true).timeout
				var trail: Array = []
				big.history.trail_samples(trail, 40)
				_snake.global_position = trail[6]
				_die_seen = false
				print("CC_VERIFY_DIE player_power=%.1f big_power=%.1f" % [_snake.power, big.power])
			if not _snake.alive and not _die_seen:
				_die_seen = true
				print("CC_VERIFY_PLAYER_DIED state=%s" % GameManager.state_name())
			if _die_seen and GameManager.is_in(GameManager.State.GAME_OVER):
				_enter_phase(23)
			if _phase_waited_s() > 15.0:
				_fail("death scenario never resolved (state=%s alive=%s)" % [GameManager.state_name(), _snake.alive])
				return
		23:  # settle, then final verdict + screenshot
			if _phase_frames == 1:
				_phase_wall_start = Time.get_ticks_msec()
			if _phase_waited_s() >= 0.8:
				_checks_conflict()


func _enter_phase(p: int) -> void:
	_phase = p
	_phase_frames = 0


func _key(key: int, pressed: bool) -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = pressed
	return ev


## Small-snake exit criteria (movement, boost drain, body trail, camera,
## §3.2 segment formula). Passes → continue to the 60-segment scenario.
func _checks_small() -> void:
	# 1. Snake moved meaningfully while steering right.
	var moved: float = _snake.global_position.distance_to(Vector3.ZERO)
	if moved < 20.0:
		_fail("snake moved only %.1f units in ~6s (speed=%.2f)" % [moved, _snake.current_speed])
		return
	# 2. Boost drained power (risk loop live). The CUMULATIVE per-tick
	# decrease must exceed a full second of drain — re-collecting shed or
	# foreign corpse motes can spike power up mid-boost (a circling snake
	# recycles its own shed motes), but the drain ticks always cost.
	if _boost_drain_sum < 1.8:
		_fail("boost did not drain power (sum %.2f, start %.1f)" % [_boost_drain_sum, _boost_start_power])
		return
	# 3. Body follows: segment 0 trails the head by roughly one spacing.
	var head: Vector3 = _snake.global_position
	var seg0: Vector3 = _snake.get_history().read_at_arc(
		_snake.get_history().newest_arc() - _snake.config.segment_spacing_radius_factor * _snake.current_radius, 0)
	var head_to_seg: float = head.distance_to(seg0)
	if head_to_seg < 0.1 or head_to_seg > 3.0:
		_fail("segment 0 not trailing head correctly (dist=%.2f)" % head_to_seg)
		return
	# 4. Camera: damped follow, distance in bounds, camera is current.
	var view_cam: Camera3D = get_viewport().get_camera_3d()
	if view_cam == null or view_cam != _rig.cam:
		_fail("camera rig camera is not current")
		return
	var cam_dist: float = _rig.global_position.distance_to(head)
	if cam_dist < 10.0 or cam_dist > 100.0:
		_fail("camera distance out of bounds: %.1f" % cam_dist)
		return
	# 5. Segment count follows the §3.2 formula (after boost drain, the
	# snake must have SHRUNK back toward the target for its current power).
	var expected_segs: int = _snake._segments_for_power(_snake.power)
	if _snake.get_segment_count() != expected_segs:
		_fail("segment count %d != expected %d at power %.1f" % [
			_snake.get_segment_count(), expected_segs, _snake.power])
		return
	_enter_phase(4)


## 60-segment exit criteria (§48 Phase 2: "drive a 60-segment snake around
## at 60 FPS"). Frame budget uses a 20 ms regression threshold — the
## sandbox runs llvmpipe software rendering (decision #11), so the real
## 16.7 ms target is human-verified on hardware (docs/HUMAN_TASKS.md).
## Passes → the run continues into the Phase 3 economy scenario.
func _checks_big() -> void:
	if _finished:
		return
	# 6. The big snake keeps moving (path length, not displacement — a
	# high-turn-rate snake legitimately coils into tight circles).
	if _path_length < 15.0:
		_fail("60-segment snake travelled only %.1f units in 3s (expected ~%.1f at speed %.2f)" % [
			_path_length, 3.0 * _snake.current_speed, _snake.current_speed])
		return
	# 7. Segment count still follows the formula at 60 segments.
	var expected_big: int = _snake._segments_for_power(_snake.power)
	if _snake.get_segment_count() != expected_big:
		_fail("big segment count %d != expected %d" % [_snake.get_segment_count(), expected_big])
		return
	print("CC_VERIFY_PHASE2_PASS moved=%.1f power=%.1f speed=%.2f segs=%d path_3s=%.1f" % [
		_snake.global_position.distance_to(Vector3.ZERO), _snake.power,
		_snake.current_speed, _snake.get_segment_count(), _path_length])
	_enter_phase(7)


## Phase 3 economy exit criteria (§48: 420 collectibles alive, collecting
## is satisfying, 60 FPS held). Passes → the run continues into the Phase 4
## ad scenario.
func _checks_economy() -> void:
	if _finished:
		return
	# 10. Boost shed motes (§3.4): mote count grew while boosting.
	var cm: CollectibleManager = _arena.collectible_manager
	if cm.mote_count() <= _econ_motes_before:
		_fail("boost shed no motes (before=%d after=%d)" % [_econ_motes_before, cm.mote_count()])
		return
	# 11. Boost still drained power (cumulative decrease — mote
	# re-collection can spike power up mid-boost; drain ticks always cost;
	# hit-stop can dilate the window, so any clear drain passes).
	if _econ_boost_drain_sum < 0.3:
		_fail("economy boost did not drain (sum %.2f vs start %.2f)" % [_econ_boost_drain_sum, _econ_boost_start])
		return
	print("CC_VERIFY_PHASE3_PASS collectibles=%d motes=%d score=%.1f combo=%d" % [
		cm.non_mote_count(), cm.mote_count(), _arena.score_manager.get_score(),
		_arena.score_manager.get_combo()])
	_enter_phase(11)


## Phase 4 ad-scaffolding exit criteria (§48: trigger a mock ad from the
## debug panel at any time; the game pauses and resumes perfectly,
## including on forced timeout). Passes → the run continues into the
## Phase 5 AI scenario.
func _checks_ads() -> void:
	if _finished:
		return
	if not _panel_was_visible:
		_fail("debug ad panel did not toggle")
		return
	if not _ad_rewarded_ok:
		_fail("rewarded mock-ad flow failed")
		return
	if not _ad_timeout_ok:
		_fail("forced-timeout watchdog flow failed")
		return
	print("CC_VERIFY_PHASE4_PASS rewarded=%s timeout=%s contract=%s" % [
		_ad_rewarded_ok, _ad_timeout_ok, _ad_contract_ok])
	_enter_phase(15)


## Phase 5 window checks (§48: AI play competently, visibly differ in
## behaviour, and cost < 2.5 ms/frame).
func _checks_ai_window() -> void:
	var director: AIDirector = _arena.ai_director
	# Every AI kept moving (path length, not displacement — a high-turn-rate
	# snake legitimately coils; the Phase 2 player check hit the same trap).
	# AIs that respawned mid-window get a proportional allowance.
	for ai in director.ai_controllers:
		if ai.snake == null or not ai.snake.alive:
			continue
		var id: int = ai.get_instance_id()
		var ticks: int = int(_ai_track_ticks.get(id, 0))
		# Wall-time allowance (hit-stop dilutes per-tick distance): 2 u/s
		# tracked, floor 20 — a healthy snake does 7.6+ u/s.
		var wall_s: float = float(Time.get_ticks_msec() - int(_ai_track_start_ms.get(id, Time.get_ticks_msec()))) / 1000.0
		# Fresh spawns (< 1 s tracked) are exempt: they may land mid
		# hit-stop or still be settling from the spawn stagger.
		if wall_s < 1.0:
			continue
		var needed: float = minf(20.0, wall_s * 2.0)
		if float(_ai_path.get(id, 0.0)) < needed:
			_fail("AI %s travelled only %.1f units (%.1fs tracked, needed %.1f)" % [
				ai.display_name, float(_ai_path.get(id, 0.0)), wall_s, needed])
			return
	# At least two AI have grown past the starting-power spread (they
	# collected from the economy).
	var grown: int = 0
	var powers: Array[float] = []
	for ai in director.ai_controllers:
		powers.append(ai.snake.power)
		if ai.snake.power > director.balance.ai_start_power_max:
			grown += 1
	if grown < 2:
		_fail("only %d AI grew past start-power spread (powers=%s)" % [grown, str(powers)])
		return
	# Visibly different behaviour: multiple FSM states across the window.
	if _ai_seen_states.size() < 3:
		_fail("state diversity too low: %s" % str(_ai_seen_states.keys()))
		return
	print("CC_VERIFY_AI_WINDOW states=%s powers=%s ai_ms_max=%.2f" % [
		str(_ai_seen_states.keys()), str(powers), director.ai_ms_max])
	_enter_phase(17)


## Phase 5 exit criteria + the cross-phase frame-budget/framing checks +
## screenshot.
func _checks_ai_final() -> void:
	if _finished:
		return
	var director: AIDirector = _arena.ai_director
	# §8.5 hard budget: all AI combined < 2.5 ms/frame (CPU decision cost —
	# measured on the sandbox CPU, not GPU-bound like frame time).
	if director.ai_ms_max >= director.balance.ai_frame_budget_ms:
		_fail("AI budget blown: max %.2f ms/frame (budget %.2f)" % [director.ai_ms_max, director.balance.ai_frame_budget_ms])
		return
	print("CC_VERIFY_PHASE5_PASS ai=%d states=%s ai_ms_max=%.2f budget=%.2f" % [
		director.get_ai_count(), str(_ai_seen_states.keys()),
		director.ai_ms_max, director.balance.ai_frame_budget_ms])
	_enter_phase(18)


## True when the chosen victim is no longer a live AI registry member.
func _victim_gone() -> bool:
	for ai in _arena.ai_director.ai_controllers:
		if ai.snake != null and int(ai.snake.get_instance_id()) == _kill_victim_id:
			return false
	return true


## Re-arms the kill scenario against another live small AI. Returns false
## when no live AI remains (attempts exhausted).
func _rearm_kill_attempt() -> bool:
	_kill_attempts += 1
	if _kill_attempts > 3:
		return false
	_snake.power = 100.0
	_snake._update_derived_stats()
	_snake._sync_segment_target()
	for ai in _arena.ai_director.ai_controllers:
		if ai.snake != null and ai.snake.alive and ai.snake.power < 50.0:
			_kill_victim = ai.snake
			_kill_victim_id = ai.snake.get_instance_id()
			_kill_victim_power = ai.snake.power
			_kill_power_before = _snake.power
			_kill_score_before = _arena.score_manager.get_score()
			_kill_start_count = _arena.ai_director.get_ai_count()
			var trail: Array = []
			ai.snake.history.trail_samples(trail, 40)
			if trail.size() > 10:
				_snake.global_position = trail[8]
				print("CC_VERIFY_KILL_REARM attempt=%d victim_power=%.1f dist=%.2f" % [
					_kill_attempts, _kill_victim_power,
					_snake.global_position.distance_to(ai.snake.global_position)])
				return true
	_fail("no rearm target")
	return false


## Phase 6 kill verification: absorb power/score landed, the victim's own
## corpse-mote drop ran (captured dying entry with staggered spawns —
## late-run mote decay makes global mote counts meaningless), hit-stop
## engaged, and the rim light was readable BEFORE the kill.
func _verify_kill() -> void:
	var cm: CombatManager = _arena.combat_manager
	var power_gain: float = _snake.power - _kill_power_before
	var expected: float = _kill_victim_power * 0.62
	if power_gain < expected * 0.5:
		_fail("absorb power missing: gain %.2f expected ~%.2f" % [power_gain, expected])
		return
	var score_gain: float = _arena.score_manager.get_score() - _kill_score_before
	var expected_score: float = cm.balance.kill_score_base + floor(_kill_victim_power * cm.balance.kill_score_power_factor)
	if score_gain < expected_score * 0.5:
		_fail("kill score missing: gain %.1f expected ~%.1f" % [score_gain, expected_score])
		return
	if _kill_dying_entry.is_empty():
		_fail("no dying entry captured for the victim")
		return
	if int(_kill_dying_entry["spawned"]) < 1:
		_fail("corpse motes not spawning (spawned=%d of %d)" % [
			int(_kill_dying_entry["spawned"]), int(_kill_dying_entry["total_motes"])])
		return
	if not _kill_hit_stop_seen:
		_fail("hit-stop never engaged (time_scale never dipped)")
		return
	_kill_done = true
	print("CC_VERIFY_PHASE6_KILL ok power+%.2f score+%.1f motes=%d/%d hit_stop=%s rim_green=%s" % [
		power_gain, score_gain, int(_kill_dying_entry["spawned"]), int(_kill_dying_entry["total_motes"]),
		_kill_hit_stop_seen, _kill_rim_green_seen])
	_enter_phase(19)


## Phase 6 exit criteria: you can kill AND be killed, and always
## understand why (the rim-light + matrix checks cover the why).
func _checks_conflict() -> void:
	if _finished:
		return
	_finished = true
	if not _kill_done:
		_fail("kill scenario failed")
		return
	if not _die_seen or not GameManager.is_in(GameManager.State.GAME_OVER):
		_fail("death scenario failed (state=%s alive=%s)" % [GameManager.state_name(), _snake.alive])
		return
	if not InputManager.is_suspended():
		_fail("input not suspended after player death")
		return
	# Frame budget across ALL scenarios. 20 ms llvmpipe regression
	# threshold (decision #11).
	if _max_frame_ms > 20.0:
		_fail("frame budget blown: max %.1f ms (avg %.1f)" % [_max_frame_ms, _frame_acc_ms / maxf(1.0, float(_frame_samples))])
		return
	print("CC_VERIFY_PHASE6_PASS killed=%s died=%s input_suspended=%s hit_stop=%s" % [
		_kill_done, _die_seen, InputManager.is_suspended(), _kill_hit_stop_seen])
	# Screenshot (skipped in headless mode — no renderer).
	if not DisplayServer.get_name() == "headless":
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(OS.get_environment("CC_SCREENSHOT") if OS.get_environment("CC_SCREENSHOT") != "" else "/tmp/cc_verify.png")
	_win()


func _win() -> void:
	print("CC_VERIFY_PASS moved=%.1f power=%.1f speed=%.2f segs=%d path_3s=%.1f max_frame_ms=%.1f avg_frame_ms=%.1f" % [
		_snake.global_position.distance_to(Vector3.ZERO), _snake.power,
		_snake.current_speed, _snake.get_segment_count(), _path_length, _max_frame_ms,
		_frame_acc_ms / maxf(1.0, float(_frame_samples))])
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("CC_VERIFY_FAIL " + reason)
	get_tree().quit(1)
