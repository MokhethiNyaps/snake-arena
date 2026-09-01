extends RefCounted
## §9A.7 / §45.7 — Ad tests: drive AdProviderMock through EVERY outcome and
## assert the §45.6 contract holds: game unpauses, input restored, audio
## restored, state correct, reward granted only in the right cases, and the
## §45.4 frequency caps hold.
##
## Contract tests run through the REAL AdManager.request_ad coroutine; the
## runner (run_tests.gd) awaits coroutine test methods and resets any
## half-finished ad state between tests.

var _original_provider: AdProvider = null
var _original_show_watchdog: float = 90.0


## RefCounted base — the tree comes from the engine, not get_tree().
func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _mock() -> AdProviderMock:
	return AdManager.provider as AdProviderMock


func _to_playing() -> void:
	if GameManager.current_state == GameManager.State.PLAYING:
		return
	if GameManager.current_state == GameManager.State.BOOT:
		GameManager.request_state(GameManager.State.LOADING)
	if GameManager.current_state == GameManager.State.LOADING:
		GameManager.request_state(GameManager.State.PLAYING)


## Configures the mock for a deterministic single-outcome show.
func _arm(outcome: int, fill: float = 1.0, latency: float = 0.0) -> void:
	var mock: AdProviderMock = _mock()
	mock.forced_outcome = outcome
	mock.fill_rate = fill
	mock.latency_seconds = latency
	mock.auto_close_seconds = 5.0


func _contract_clean() -> bool:
	if _tree().paused:
		printerr("  tree still paused")
		return false
	if InputManager.is_suspended():
		printerr("  input still suspended")
		return false
	if AudioManager._ducked:
		printerr("  audio still ducked")
		return false
	if AdManager._overlay.visible:
		printerr("  ad overlay still visible")
		return false
	if AdManager._busy:
		printerr("  AdManager still busy")
		return false
	return true


# --- provider-level -------------------------------------------------------

func test_mock_availability() -> bool:
	var mock: AdProviderMock = _mock()
	mock.forced_outcome = AdProviderMock.ForcedOutcome.NONE
	mock.fill_rate = 0.0
	if mock.is_available(AdPlacementId.ID.REVIVE):
		printerr("  fill 0 still available")
		return false
	mock.fill_rate = 1.0
	if not mock.is_available(AdPlacementId.ID.REVIVE):
		printerr("  fill 1 unavailable")
		return false
	mock.forced_outcome = AdProviderMock.ForcedOutcome.NO_FILL
	if mock.is_available(AdPlacementId.ID.REVIVE):
		printerr("  forced NO_FILL still available at preload")
		return false
	# Show-time no-fill: available at preload, fails at show.
	mock.forced_outcome = AdProviderMock.ForcedOutcome.FORCE_SHOW_NO_FILL
	if not mock.is_available(AdPlacementId.ID.REVIVE):
		printerr("  FORCE_SHOW_NO_FILL unavailable at preload (must be show-time)")
		return false
	mock.forced_outcome = AdProviderMock.ForcedOutcome.NONE
	mock.fill_rate = 1.0
	return true


func test_mock_banner() -> bool:
	var mock: AdProviderMock = _mock()
	mock.show_banner(0)
	if mock.get_banner_height_px() != 60:
		printerr("  banner height %d != 60" % mock.get_banner_height_px())
		return false
	mock.hide_banner()
	if mock.get_banner_height_px() != 0:
		printerr("  banner height after hide %d != 0" % mock.get_banner_height_px())
		return false
	return true


func test_null_provider_playable() -> bool:
	# §45.1: the game must be fully playable with AdProviderNull. Swap it
	# in and confirm a request resolves DISABLED without touching the game.
	_to_playing()
	_original_provider = AdManager.provider
	AdManager.provider = AdProviderNull.new()
	var result: AdResult = await AdManager.request_ad(AdPlacementId.ID.REVIVE, true)
	var ok: bool = result.code == AdResult.Code.DISABLED
	ok = ok and GameManager.current_state == GameManager.State.PLAYING
	ok = ok and not _tree().paused
	if not ok:
		printerr("  null provider disturbed the game (result=%s state=%s paused=%s)" % [
			result, GameManager.state_name(), _tree().paused])
	AdManager.provider = _original_provider
	return ok


# --- pacer gates (§45.4) --------------------------------------------------

func test_pacer_gates() -> bool:
	_to_playing()
	# Deterministic baseline: consent granted (mock dev-default).
	var saved_consent: int = ConsentManager.state
	ConsentManager.state = ConsentManager.ConsentState.GRANTED
	var checks: Array = []
	# ads disabled
	var saved_enabled: bool = AdManager._config.ads_enabled
	AdManager._config.ads_enabled = false
	checks.append(AdManager.can_show(AdPlacementId.ID.REVIVE)["reason"] == "ads-disabled")
	AdManager._config.ads_enabled = saved_enabled
	# no-ads purchased
	var saved_no_ads: bool = AdManager._no_ads_purchased
	AdManager._no_ads_purchased = true
	checks.append(AdManager.can_show(AdPlacementId.ID.REVIVE)["reason"] == "no-ads-purchased")
	AdManager._no_ads_purchased = saved_no_ads
	# consent denied
	ConsentManager.state = ConsentManager.ConsentState.DENIED
	checks.append(AdManager.can_show(AdPlacementId.ID.REVIVE)["reason"] == "consent-denied")
	ConsentManager.state = ConsentManager.ConsentState.GRANTED
	# min-run-index (INTER_RUN needs run #3 of the session)
	var saved_runs: int = AdManager._session_runs
	AdManager._session_runs = 0
	checks.append(AdManager.can_show(AdPlacementId.ID.INTER_RUN)["reason"] == "min-run-index")
	AdManager._session_runs = 5
	checks.append(AdManager.can_show(AdPlacementId.ID.INTER_RUN)["allowed"])
	# min gap: record a show, then ask again within the gap
	var saved_gap: float = AdManager._last_interstitial_clock
	AdManager._last_interstitial_clock = -1.0e9
	AdManager._session_interstitial_total = 0
	checks.append(AdManager.can_show(AdPlacementId.ID.INTER_RUN)["allowed"])
	AdManager._record_show(AdPlacementId.ID.INTER_RUN)
	checks.append(AdManager.can_show(AdPlacementId.ID.INTER_RUN)["reason"] == "min-gap")
	# session interstitial cap (6)
	AdManager._session_interstitial_total = 6
	var box: Array = [1000.0]
	AdManager.clock_sec = func() -> float: return box[0]
	box[0] = 1000.0 + 200.0  # beyond the 120 s gap
	checks.append(AdManager.can_show(AdPlacementId.ID.INTER_RUN)["reason"] == "session-interstitial-cap")
	AdManager.clock_sec = func() -> float: return float(Time.get_ticks_msec()) / 1000.0
	AdManager._session_interstitial_total = 0
	AdManager._last_interstitial_clock = saved_gap
	# session cap on a rewarded placement (REVIVE: 4/session)
	var saved_counts: Dictionary = AdManager._session_counts.duplicate()
	AdManager._session_counts[AdPlacementId.ID.REVIVE] = 4
	checks.append(AdManager.can_show(AdPlacementId.ID.REVIVE)["reason"] == "session-cap")
	AdManager._session_counts = saved_counts
	# daily cap on a rewarded placement (REVIVE: 8/day)
	var saved_days: Dictionary = AdManager._day_counts.duplicate()
	var day_key: String = AdManager._day_key(AdManager.date_key.call(), AdPlacementId.ID.REVIVE)
	AdManager._day_counts[day_key] = 8
	checks.append(AdManager.can_show(AdPlacementId.ID.REVIVE)["reason"] == "daily-cap")
	AdManager._day_counts = saved_days
	AdManager._session_runs = saved_runs
	ConsentManager.state = saved_consent
	for i in checks.size():
		if not checks[i]:
			printerr("  pacer gate %d failed" % i)
			return false
	return true


func test_run_started_increments_session_runs() -> bool:
	var before: int = AdManager._session_runs
	EventBus.run_started.emit()
	if AdManager._session_runs != before + 1:
		printerr("  session_runs %d -> %d" % [before, AdManager._session_runs])
		return false
	return true


# --- contract outcomes (§45.7) --------------------------------------------

func test_rewarded_completed_contract() -> bool:
	_to_playing()
	_arm(AdProviderMock.ForcedOutcome.COMPLETED)
	var rewards: Array = [0]
	AdManager.ad_reward_granted.connect(func(_p: int, _r: StringName) -> void: rewards[0] += 1, CONNECT_ONE_SHOT)
	var result: AdResult = await AdManager.request_ad(AdPlacementId.ID.REVIVE, true)
	if result.code != AdResult.Code.SHOWN_COMPLETED or not result.rewarded:
		printerr("  result %s" % result)
		return false
	if rewards[0] != 1:
		printerr("  reward granted %d times, expected 1" % rewards[0])
		return false
	if GameManager.current_state != GameManager.State.PLAYING:
		printerr("  state after ad: %s" % GameManager.state_name())
		return false
	return _contract_clean()


func test_rewarded_skipped_no_reward() -> bool:
	_to_playing()
	_arm(AdProviderMock.ForcedOutcome.SKIPPED)
	var rewards: Array = [0]
	AdManager.ad_reward_granted.connect(func(_p: int, _r: StringName) -> void: rewards[0] += 1, CONNECT_ONE_SHOT)
	var result: AdResult = await AdManager.request_ad(AdPlacementId.ID.REVIVE, true)
	if result.code != AdResult.Code.SHOWN_SKIPPED or result.rewarded:
		printerr("  result %s" % result)
		return false
	if rewards[0] != 0:
		printerr("  reward granted on skip!")
		return false
	if GameManager.current_state != GameManager.State.PLAYING:
		return false
	return _contract_clean()


func test_no_fill_grant_rules() -> bool:
	_to_playing()
	# REVIVE: grant_on_no_fill = false → no reward on NO_FILL (§45.5).
	_arm(AdProviderMock.ForcedOutcome.FORCE_SHOW_NO_FILL)
	var rewards: Array = [0]
	AdManager.ad_reward_granted.connect(func(_p: int, _r: StringName) -> void: rewards[0] += 1, CONNECT_ONE_SHOT)
	var r1: AdResult = await AdManager.request_ad(AdPlacementId.ID.REVIVE, true)
	if r1.code != AdResult.Code.NO_FILL or rewards[0] != 0:
		printerr("  revive no-fill: %s rewards=%d" % [r1, rewards[0]])
		return false
	# DOUBLE_COINS: grant_on_no_fill = true → granted (§45.5).
	_arm(AdProviderMock.ForcedOutcome.FORCE_SHOW_NO_FILL)
	var r2: AdResult = await AdManager.request_ad(AdPlacementId.ID.DOUBLE_COINS, true)
	if r2.code != AdResult.Code.NO_FILL or rewards[0] != 1:
		printerr("  double-coins no-fill: %s rewards=%d" % [r2, rewards[0]])
		return false
	if GameManager.current_state != GameManager.State.PLAYING:
		return false
	return _contract_clean()


func test_error_path() -> bool:
	_to_playing()
	_arm(AdProviderMock.ForcedOutcome.ERROR)
	var result: AdResult = await AdManager.request_ad(AdPlacementId.ID.INTER_RUN, true)
	if result.code != AdResult.Code.ERROR:
		printerr("  result %s" % result)
		return false
	if GameManager.current_state != GameManager.State.PLAYING:
		return false
	return _contract_clean()


func test_crash_path() -> bool:
	_to_playing()
	_arm(AdProviderMock.ForcedOutcome.CRASH)
	var result: AdResult = await AdManager.request_ad(AdPlacementId.ID.INTER_RUN, true)
	if result.code != AdResult.Code.ERROR:
		printerr("  crash resolved as %s" % result)
		return false
	return _contract_clean()


func test_watchdog_timeout() -> bool:
	# THE mandatory §45.6 test: a hung provider must never wedge the game.
	_to_playing()
	_original_show_watchdog = AdManager._config.show_watchdog_seconds
	AdManager._config.show_watchdog_seconds = 0.4
	_arm(AdProviderMock.ForcedOutcome.TIMEOUT)
	var result: AdResult = await AdManager.request_ad(AdPlacementId.ID.INTER_RUN, true)
	AdManager._config.show_watchdog_seconds = _original_show_watchdog
	if result.code != AdResult.Code.TIMEOUT:
		printerr("  hung show resolved as %s, expected TIMEOUT" % result)
		return false
	if GameManager.current_state != GameManager.State.PLAYING:
		printerr("  state after timeout: %s" % GameManager.state_name())
		return false
	return _contract_clean()


func test_busy_guard() -> bool:
	_to_playing()
	_arm(AdProviderMock.ForcedOutcome.COMPLETED, 1.0, 0.8)
	# Fire the first request without awaiting it; the second must be
	# refused while the first is in flight.
	AdManager.request_ad(AdPlacementId.ID.INTER_RUN, true)
	var second: AdResult = await AdManager.request_ad(AdPlacementId.ID.INTER_RUN, true)
	if second.code != AdResult.Code.BLOCKED:
		printerr("  concurrent request not blocked: %s" % second)
		return false
	# Wait for the first to finish and the contract to restore.
	await _tree().create_timer(1.4, true).timeout
	if GameManager.current_state != GameManager.State.PLAYING:
		return false
	return _contract_clean()


func test_focus_out_resolves() -> bool:
	_to_playing()
	_arm(AdProviderMock.ForcedOutcome.NONE, 1.0, 0.2)
	var finished: Array = [null]
	AdManager.ad_finished.connect(func(p: int, r: AdResult) -> void: finished[0] = r, CONNECT_ONE_SHOT)
	AdManager.request_ad(AdPlacementId.ID.REVIVE, true)
	await _tree().create_timer(0.4, true).timeout
	# Mid-ad: tab loses focus → clean resolve (§45.6.8).
	AdManager.simulate_focus_out()
	await _tree().create_timer(0.4, true).timeout
	if finished[0] == null or (finished[0] as AdResult).code != AdResult.Code.SHOWN_SKIPPED:
		printerr("  focus-out did not resolve cleanly: %s" % str(finished[0]))
		return false
	if GameManager.current_state != GameManager.State.PLAYING:
		return false
	return _contract_clean()
