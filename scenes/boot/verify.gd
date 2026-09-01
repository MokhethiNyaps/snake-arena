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
# Phase 4 (ad scaffolding) scenario state.
var _ad_entered: bool = false
var _ad_contract_ok: bool = false
var _ad_rewarded_ok: bool = false
var _ad_timeout_ok: bool = false
var _panel_was_visible: bool = false

var _max_frame_ms: float = 0.0
var _frame_samples: int = 0
var _frame_acc_ms: float = 0.0


func _ready() -> void:
	# The ad contract pauses the whole tree; the harness driver must keep
	# ticking regardless (PROCESS_MODE_ALWAYS) or scenario D deadlocks.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_world()


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
			Input.parse_input_event(_key(KEY_SPACE, true))
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
				_econ_motes_before = _arena.collectible_manager.mote_count()
			Input.parse_input_event(_key(KEY_SPACE, true))
			_min_power_during_boost = minf(_min_power_during_boost, _snake.power)
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
		14:  # settle, then final verdict + screenshot
			if _phase_frames >= 20:
				_checks_ads()


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
	# 2. Boost drained power (risk loop live). The MINIMUM observed power
	# while boosting must dip below the start value — a net comparison of
	# start vs end can be masked by incidental collects during the boost.
	if _min_power_during_boost >= _boost_start_power:
		_fail("boost did not drain power (min %.1f vs start %.1f)" % [_min_power_during_boost, _boost_start_power])
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
	# 11. Boost still drained power (min-power check — a plain start/end
	# comparison can be masked by incidental collects during the boost).
	if _min_power_during_boost >= _econ_boost_start:
		_fail("economy boost did not drain (min %.2f vs start %.2f)" % [_min_power_during_boost, _econ_boost_start])
		return
	print("CC_VERIFY_PHASE3_PASS collectibles=%d motes=%d score=%.1f combo=%d" % [
		cm.non_mote_count(), cm.mote_count(), _arena.score_manager.get_score(),
		_arena.score_manager.get_combo()])
	_enter_phase(11)


## Phase 4 ad-scaffolding exit criteria (§48: trigger a mock ad from the
## debug panel at any time; the game pauses and resumes perfectly,
## including on forced timeout) + the cross-phase frame-budget/framing
## checks + screenshot.
func _checks_ads() -> void:
	if _finished:
		return
	_finished = true
	if not _panel_was_visible:
		_fail("debug ad panel did not toggle")
		return
	if not _ad_rewarded_ok:
		_fail("rewarded mock-ad flow failed")
		return
	if not _ad_timeout_ok:
		_fail("forced-timeout watchdog flow failed")
		return
	# Frame budget across ALL scenarios (worst case: 420 collectibles +
	# VFX + 60-segment snake + ad overlay). Regression threshold 20 ms
	# (llvmpipe — real 16.7 ms target is human-verified, decision #11).
	if _max_frame_ms > 20.0:
		_fail("frame budget blown: max %.1f ms (avg %.1f)" % [_max_frame_ms, _frame_acc_ms / maxf(1.0, float(_frame_samples))])
		return
	# Framing: the head must project on-screen, near centre.
	var view_cam2: Camera3D = get_viewport().get_camera_3d()
	var head_screen: Vector2 = view_cam2.unproject_position(_snake.head_position())
	var on_screen: bool = (
		head_screen.x > 0.0 and head_screen.x < float(view_cam2.get_viewport().get_visible_rect().size.x)
		and head_screen.y > 0.0 and head_screen.y < float(view_cam2.get_viewport().get_visible_rect().size.y)
		and not view_cam2.is_position_behind(_snake.head_position()))
	print("CC_VERIFY_FRAME head_screen=%s on_screen=%s rig_pos=%s rig_rot=%s cam_fwd=%s head=%s" % [
		head_screen, on_screen, _rig.global_position, _rig.global_rotation_degrees,
		-view_cam2.global_transform.basis.z, _snake.head_position()])
	if not on_screen:
		_fail("snake head is off-screen at %s" % head_screen)
		return
	print("CC_VERIFY_PHASE4_PASS rewarded=%s timeout=%s contract=%s" % [
		_ad_rewarded_ok, _ad_timeout_ok, _ad_contract_ok])
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
