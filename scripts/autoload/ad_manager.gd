extends Node
## AUTOLOAD #6 — AdManager (§45). The ONLY ad-facing surface gameplay sees.
##
## Owns: provider selection, the §45.6 ad-safety contract (pause / duck /
##        suspend input / opaque overlay / watchdog / restore), the §45.4
##        AdPacer (implemented inside AdManager per spec), the ad_* signals,
##        the decision log for the debug panel, and the debug ad panel
##        itself (debug builds).
## Gameplay calls exactly ONE entry point:
##     var result: AdResult = await AdManager.request_ad(placement)
##
## Does NOT own: ad SDK internals (each AdProvider), consent (ConsentManager).
## Talks to: AdProviders (down), GameManager/AudioManager/InputManager
##           (contract), Analytics (§45.10), the debug panel (up).

# Signals (§45.1: emitted by AdManager, never by gameplay)
signal ad_started(placement: int)
signal ad_finished(placement: int, result: AdResult)
signal ad_reward_granted(placement: int, reward_id: StringName)
signal ad_failed(placement: int, reason: String)
## §45.4: every pacer decision, allowed or blocked, for the debug panel.
signal decision_logged(entry: String)

const OVERLAY_SCENE: PackedScene = preload("res://scenes/ui/ad_overlay.tscn")
const DEBUG_PANEL_SCENE: PackedScene = preload("res://scenes/ui/debug_panel.tscn")

## Max entries kept in the decision log (debug panel).
const LOG_CAP: int = 100

var provider: AdProvider = null
var _config: AdConfig = null
var _overlay: CanvasLayer = null
var _debug_panel: CanvasLayer = null

## Injectable clocks (boxed in tests for determinism, decision #30).
var clock_sec: Callable = func() -> float: return float(Time.get_ticks_msec()) / 1000.0
var date_key: Callable = func() -> String: return Time.get_date_string_from_system()

# --- pacer state --------------------------------------------------------
var _session_runs: int = 0
var _session_counts: Dictionary = {}   # placement -> shows this session
var _day_counts: Dictionary = {}       # placement -> shows today
var _session_interstitial_total: int = 0
var _last_interstitial_clock: float = -1.0e9
var _last_app_open_clock: float = -1.0e9
var _no_ads_purchased: bool = false

# --- show state ----------------------------------------------------------
var _busy: bool = false
var _prev_state: int = -1
var _decision_log: Array[String] = []


func _ready() -> void:
	_config = load("res://resources/config/ads.tres") as AdConfig
	provider = _select_provider()
	if provider != null:
		provider.set_ui_container(self)
		provider.initialize(_config, ConsentManager.state)
	_no_ads_purchased = bool(SaveManager.get_setting("ads", "no_ads_purchased", false))
	# §45.8: consent must resolve before ads serve. In dev builds with the
	# mock provider there is no UMP UI yet (Phase 11), so resolve to the
	# dev-default GRANTED — real providers will require explicit consent.
	if provider is AdProviderMock and ConsentManager.state == ConsentManager.ConsentState.UNKNOWN:
		ConsentManager.resolve()
	_overlay = OVERLAY_SCENE.instantiate()
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	add_child(_overlay)
	if OS.is_debug_build():
		_debug_panel = DEBUG_PANEL_SCENE.instantiate()
		_debug_panel.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_debug_panel)
	EventBus.run_started.connect(_on_run_started)
	EventBus.game_state_changed.connect(_on_state_changed)
	print("[AdManager] Provider: %s (ads %s)" % [
		provider.get_script().get_global_name() if provider != null and provider.get_script() else "none",
		"ENABLED" if (_config != null and _config.ads_enabled) else "DISABLED",
	])


## §45.1 selection. Sandbox/testing escape hatch: CC_AD_PROVIDER=null|mock.
## Web-portal and AdMob branches land with their providers in Phase 11.
func _select_provider() -> AdProvider:
	var env_override: String = OS.get_environment("CC_AD_PROVIDER")
	if env_override == "null":
		return AdProviderNull.new()
	if env_override == "mock":
		return AdProviderMock.new()
	if _config != null and _config.use_mock_in_editor and (OS.has_feature("editor") or OS.is_debug_build()):
		return AdProviderMock.new()
	return AdProviderNull.new()


func _on_run_started() -> void:
	_session_runs += 1


func _on_state_changed(_from: int, _to: int) -> void:
	pass  # hook kept for future state-driven placements (app open)


## §45.9: the future no-ads IAP removes ALL ads; the flag must exist and be
## honoured everywhere in the pacer from day one.
func set_no_ads(purchased: bool) -> void:
	_no_ads_purchased = purchased
	SaveManager.set_setting("ads", "no_ads_purchased", purchased)


func is_no_ads_purchased() -> bool:
	return _no_ads_purchased


## Public accessor for the debug ad panel (debug builds only; null in
## release). The verify harness and tests drive its trigger handlers.
func get_debug_panel() -> CanvasLayer:
	return _debug_panel


## §45.4 — the pacer. Every gate in the spec's formula, in order.
## Returns { allowed: bool, reason: String }.
func can_show(placement: int) -> Dictionary:
	if _config == null or not _config.ads_enabled:
		return {"allowed": false, "reason": "ads-disabled"}
	if _no_ads_purchased:
		return {"allowed": false, "reason": "no-ads-purchased"}
	if not ConsentManager.is_granted():
		return {"allowed": false, "reason": "consent-denied"}
	var def: AdPlacementDef = _config.get_placement(placement)
	if def == null:
		return {"allowed": false, "reason": "unknown-placement"}
	if _session_runs < def.min_run_index:
		return {"allowed": false, "reason": "min-run-index"}
	if def.type == AdPlacementDef.AdType.INTERSTITIAL:
		if _last_interstitial_clock > -1.0e8:
			var gap: float = clock_sec.call() - _last_interstitial_clock
			if gap < def.min_gap_seconds:
				return {"allowed": false, "reason": "min-gap"}
		if _config.session_interstitial_cap >= 0 and _session_interstitial_total >= _config.session_interstitial_cap:
			return {"allowed": false, "reason": "session-interstitial-cap"}
	if def.type == AdPlacementDef.AdType.APP_OPEN:
		if _last_app_open_clock > -1.0e8:
			var gap_h: float = (clock_sec.call() - _last_app_open_clock) / 3600.0
			if gap_h < _config.app_open_cooldown_hours:
				return {"allowed": false, "reason": "app-open-cooldown"}
	if def.session_cap >= 0 and int(_session_counts.get(placement, 0)) >= def.session_cap:
		return {"allowed": false, "reason": "session-cap"}
	if def.daily_cap >= 0 and int(_day_counts.get(_day_key(date_key.call(), placement), 0)) >= def.daily_cap:
		return {"allowed": false, "reason": "daily-cap"}
	if provider == null or not provider.is_available(placement):
		return {"allowed": false, "reason": "no-fill"}
	return {"allowed": true, "reason": "allowed"}


## Daily bucket key: date + placement, so the same date string across
## placements never collides.
func _day_key(day: String, placement: int) -> String:
	return "%s#%d" % [day, placement]


func _record_show(placement: int) -> void:
	_session_counts[placement] = int(_session_counts.get(placement, 0)) + 1
	var key: String = _day_key(date_key.call(), placement)
	_day_counts[key] = int(_day_counts.get(key, 0)) + 1
	var def: AdPlacementDef = _config.get_placement(placement) if _config != null else null
	if def != null and def.type == AdPlacementDef.AdType.INTERSTITIAL:
		_session_interstitial_total += 1
		_last_interstitial_clock = clock_sec.call()
	if def != null and def.type == AdPlacementDef.AdType.APP_OPEN:
		_last_app_open_clock = clock_sec.call()


func _log_decision(text: String) -> void:
	_decision_log.append(text)
	if _decision_log.size() > LOG_CAP:
		_decision_log.pop_front()
	decision_logged.emit(text)


func get_decision_log() -> Array[String]:
	return _decision_log


## THE single gameplay entry point (§45.6 steps 1-8). Always resolves.
## bypass_pacing: debug-panel/test escape hatch so a mock ad can be
## triggered "at any time" (§48 Phase 4 exit criterion).
func request_ad(placement: int, bypass_pacing: bool = false) -> AdResult:
	if _busy:
		_log_decision("request %s BLOCKED reason=busy" % AdPlacementId.name_of(placement))
		return AdResult.from_code(AdResult.Code.BLOCKED)
	# Null provider fast path: ads disabled — never touch the game state.
	if provider is AdProviderNull or provider == null:
		_log_decision("request %s BLOCKED reason=provider-disabled" % AdPlacementId.name_of(placement))
		Analytics.track(&"ad_blocked", {"placement": placement, "reason": "provider-disabled"})
		return AdResult.disabled()
	var def: AdPlacementDef = _config.get_placement(placement) if _config != null else null
	if def == null:
		_log_decision("request %s BLOCKED reason=unknown-placement" % AdPlacementId.name_of(placement))
		return AdResult.from_code(AdResult.Code.BLOCKED)
	var pace: Dictionary = can_show(placement)
	if not bypass_pacing and not bool(pace["allowed"]):
		_log_decision("request %s BLOCKED reason=%s" % [AdPlacementId.name_of(placement), pace["reason"]])
		Analytics.track(&"ad_blocked", {"placement": placement, "reason": pace["reason"]})
		return AdResult.from_code(AdResult.Code.BLOCKED)
	if not bool(pace["allowed"]) and bypass_pacing:
		_log_decision("request %s (bypass) would be BLOCKED reason=%s — forcing for debug" % [
			AdPlacementId.name_of(placement), pace["reason"]])
	_log_decision("request %s ALLOWED" % AdPlacementId.name_of(placement))
	Analytics.track(&"ad_requested", {"placement": placement})
	# --- §45.6 contract: enter --------------------------------------------
	_busy = true
	_prev_state = GameManager.current_state
	var entered: bool = GameManager.request_state(GameManager.State.PAUSED_FOR_AD)
	if not entered:
		_busy = false
		_log_decision("request %s ERROR reason=state-transition-refused (%s)" % [
			AdPlacementId.name_of(placement), GameManager.state_name()])
		ad_failed.emit(placement, "state-transition-refused")
		return AdResult.from_code(AdResult.Code.ERROR)
	get_tree().paused = true
	AudioManager.duck_all(AudioManager.DUCK_DB)
	InputManager.set_suspended(true)
	_overlay.visible = true
	ad_started.emit(placement)
	Analytics.track(&"ad_shown", {"placement": placement, "latency_ms": 0})
	# --- show, raced against the watchdog --------------------------------
	var show_start: float = clock_sec.call()
	var result: AdResult = await _show_with_watchdog(placement, def)
	var watch_time: float = clock_sec.call() - show_start
	# --- reward decision (§45.5) -----------------------------------------
	if result.code == AdResult.Code.SHOWN_COMPLETED and def.type == AdPlacementDef.AdType.REWARDED:
		_grant_reward(placement)
	elif def.type == AdPlacementDef.AdType.REWARDED and def.grant_on_no_fill \
			and (result.code == AdResult.Code.NO_FILL or result.code == AdResult.Code.ERROR):
		# Never on user skip, never a revive (revive has grant_on_no_fill
		# false in ads.tres) — only non-competitive rewards (§45.5).
		_grant_reward(placement)
	elif result.code != AdResult.Code.SHOWN_COMPLETED:
		ad_failed.emit(placement, AdResult.Code.keys()[result.code])
	# --- §45.6 contract: exit (any path) ----------------------------------
	_record_show(placement)
	_overlay.visible = false
	InputManager.set_suspended(false)
	AudioManager.restore_audio()
	get_tree().paused = false
	GameManager.request_state(_prev_state)
	_busy = false
	Analytics.track(&"ad_result", {"placement": placement, "result": AdResult.Code.keys()[result.code], "watch_time": watch_time})
	ad_finished.emit(placement, result)
	_log_decision("request %s FINISHED result=%s" % [AdPlacementId.name_of(placement), AdResult.Code.keys()[result.code]])
	return result


func _grant_reward(placement: int) -> void:
	var reward_id: StringName = StringName(AdPlacementId.name_of(placement))
	ad_reward_granted.emit(placement, reward_id)
	Analytics.track(&"ad_reward_granted", {"placement": placement, "reward_id": reward_id})


## Starts the provider show, then waits for the FIRST of:
##   provider.show_completed  (normal resolution, any code)
##   watchdog timeout         (forced TIMEOUT — game must never stick)
## The wait loop ticks on process_always SceneTreeTimers so it keeps
## running while the tree is paused mid-ad.
func _show_with_watchdog(placement: int, def: AdPlacementDef) -> AdResult:
	var slot: Array = [null]  # boxed — lambdas capture by value (decision #30)
	var on_done := func(r: AdResult) -> void:
		if slot[0] == null:
			slot[0] = r
	provider.show_completed.connect(on_done, CONNECT_ONE_SHOT)
	var on_watchdog := func() -> void:
		if slot[0] == null:
			slot[0] = AdResult.from_code(AdResult.Code.TIMEOUT)
	# The watchdog and the polling loop are REAL-TIME (ignore_time_scale):
	# combat hit-stop scales Engine.time_scale, and a time-scaled watchdog
	# would let the game stick behind an ad for 6+ real seconds (caught
	# live: 1.0 s watchdog took 6.6 s at 0.15× time_scale).
	var watchdog: SceneTreeTimer = get_tree().create_timer(
		_config.show_watchdog_seconds if _config != null else 90.0, true, false, true)
	watchdog.timeout.connect(on_watchdog)
	# Fire-and-forget the provider coroutine: even un-awaited, a GDScript
	# coroutine completes on its own and emits show_completed.
	var is_rewarded: bool = def.type == AdPlacementDef.AdType.REWARDED
	if is_rewarded:
		provider.show_rewarded(placement)
	else:
		provider.show_interstitial(placement)
	while slot[0] == null:
		await get_tree().create_timer(0.05, true, false, true).timeout
	if watchdog.timeout.is_connected(on_watchdog):
		watchdog.timeout.disconnect(on_watchdog)
	return slot[0] as AdResult


## §45.6.8: backgrounding mid-ad resolves cleanly. The mock treats it as
## a user skip; real providers will route through the same path.
func simulate_focus_out() -> void:
	if not _busy:
		return
	_log_decision("focus lost mid-ad — resolving as SKIPPED")
	_focus_resolve()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _busy:
		_log_decision("NOTIFICATION_APPLICATION_FOCUS_OUT mid-ad — resolving as SKIPPED")
		_focus_resolve()


## Focus-loss path: resolve the CURRENT show as SHOWN_SKIPPED immediately.
## The active request_ad coroutine picks it up from the same slot.
func _focus_resolve() -> void:
	# The slot lives inside _show_with_watchdog; routing through the
	# provider keeps one source of truth: a synthetic skip completion.
	if provider != null and provider.has_signal("show_completed"):
		provider.show_completed.emit(AdResult.from_code(AdResult.Code.SHOWN_SKIPPED))


# --- passthroughs ---------------------------------------------------------

func is_available(placement: int) -> bool:
	var pace: Dictionary = can_show(placement)
	return bool(pace["allowed"])


func preload_ad(placement: int) -> void:
	if provider != null:
		provider.preload_ad(placement)


# Banners (menu screens only, §45.3)
func show_banner(position: int) -> void:
	if provider != null and can_show(AdPlacementId.ID.BANNER_MENU)["allowed"]:
		provider.show_banner(position)


func hide_banner() -> void:
	if provider != null:
		provider.hide_banner()


func get_banner_height_px() -> int:
	return provider.get_banner_height_px() if provider != null else 0
