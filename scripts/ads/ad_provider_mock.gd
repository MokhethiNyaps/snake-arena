class_name AdProviderMock
extends AdProvider
## §45.7 — The fake ad provider: simulates the full ad flow with a visible
## overlay, configurable fill rate, load latency, and forced outcomes.
## "This is how you test ads without an SDK."
##
## Knobs (tuned live from the debug ad panel, §45.7):
##   fill_rate (0..1)          — availability roll at preload time
##   latency_seconds (0..8)    — simulated load latency before the ad shows
##   auto_close_seconds        — fake-ad countdown before auto-complete
##   forced_outcome            — NONE (natural) | COMPLETED | SKIPPED |
##                               NO_FILL | ERROR | TIMEOUT | CRASH
##
## Outcome semantics:
##   NO_FILL  — availability rolls FALSE (preload-time no fill). The pacer
##              blocks with reason "no-fill" (same as a real provider).
##              To exercise the SHOW-time no-fill path (grant_on_no_fill),
##              see FORCE_SHOW_NO_FILL below.
##   TIMEOUT  — the show coroutine never resolves (provider hang). The
##              AdManager watchdog must force TIMEOUT and restore.
##   CRASH    — resolves with ERROR after the latency (contract-safe crash).
##   SKIPPED  — rewarded closed early (or the close button pressed).
##   COMPLETED— watched to the end of the countdown (rewarded = true).
##
## Owns: the fake overlay UI + banner, the outcome simulation.
## Does NOT own: the real ad contract (§45.6 — AdManager's job).
## Talks to: AdManager only.

enum ForcedOutcome { NONE, COMPLETED, SKIPPED, NO_FILL, FORCE_SHOW_NO_FILL, ERROR, TIMEOUT, CRASH }
## Show-time no-fill variant: available at preload, but the show itself
## reports NO_FILL (exercises §45.5 grant_on_no_fill).

## Probability an ad is available when preloaded.
var fill_rate: float = 1.0
## Simulated load latency in seconds before the fake ad appears.
var latency_seconds: float = 0.3
## Countdown length on the fake ad; at 0 the ad auto-completes.
var auto_close_seconds: float = 5.0
## Forced outcome for the next show (debug panel / tests).
var forced_outcome: ForcedOutcome = ForcedOutcome.NONE

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _initialized: bool = false
var _ui_root: Node = null
var _overlay: CanvasLayer = null
var _panel: ColorRect = null
var _title_label: Label = null
var _countdown_label: Label = null
var _close_button: Button = null
var _banner: ColorRect = null
var _countdown: float = 0.0
var _countdown_total: float = 0.0
var _auto_close: bool = false
var _show_placement: int = -1
var _show_rewarded: bool = false
## Internal signal the TIMEOUT outcome awaits — never emitted.
signal _never


func initialize(_config: AdConfig, _consent_state: int) -> void:
	_rng.randomize()
	_initialized = true


func is_initialized() -> bool:
	return _initialized


func set_ui_container(node: Node) -> void:
	_ui_root = node
	_build_overlay()


func is_available(_placement: AdPlacementId.ID) -> bool:
	if forced_outcome == ForcedOutcome.NO_FILL:
		return false
	return _rng.randf() <= fill_rate


func preload_ad(_placement: AdPlacementId.ID) -> void:
	# Latency is simulated at show time (one knob, §45.7).
	pass


func show_interstitial(placement: AdPlacementId.ID) -> AdResult:
	return await _run_show(placement, false)


func show_rewarded(placement: AdPlacementId.ID) -> AdResult:
	return await _run_show(placement, true)


func _run_show(placement: AdPlacementId.ID, rewarded: bool) -> AdResult:
	_show_placement = placement
	_show_rewarded = rewarded
	# Simulated load latency.
	if latency_seconds > 0.0:
		await _delay(latency_seconds)
	# Forced outcomes that resolve before any overlay appears.
	match forced_outcome:
		ForcedOutcome.FORCE_SHOW_NO_FILL:
			var r_no_fill: AdResult = AdResult.from_code(AdResult.Code.NO_FILL)
			show_completed.emit(r_no_fill)
			return r_no_fill
		ForcedOutcome.ERROR:
			var r_err: AdResult = AdResult.from_code(AdResult.Code.ERROR)
			show_completed.emit(r_err)
			return r_err
		ForcedOutcome.CRASH:
			print("[AdProviderMock] Simulated provider crash (mid-ad)")
			var r_crash: AdResult = AdResult.from_code(AdResult.Code.ERROR)
			show_completed.emit(r_crash)
			return r_crash
		ForcedOutcome.TIMEOUT:
			# Provider hang: never resolve. The AdManager watchdog is the
			# only thing standing between the game and a stuck ad.
			await _never
			var r_hang: AdResult = AdResult.from_code(AdResult.Code.TIMEOUT)
			show_completed.emit(r_hang)
			return r_hang
		ForcedOutcome.SKIPPED:
			var r_skip: AdResult = AdResult.from_code(AdResult.Code.SHOWN_SKIPPED)
			show_completed.emit(r_skip)
			return r_skip
		ForcedOutcome.COMPLETED:
			var r_done: AdResult = AdResult.from_code(AdResult.Code.SHOWN_COMPLETED, rewarded)
			show_completed.emit(r_done)
			return r_done
	# Natural flow: visible fake ad with countdown + close button.
	_show_overlay(rewarded)
	var result: AdResult = await _user_resolution
	_hide_overlay()
	show_completed.emit(result)
	return result


## Never-emitted signal the natural flow awaits while the fake ad is up.
signal _user_resolution


func _on_close_pressed() -> void:
	# Interstitial close = watched (no reward concept). Rewarded close
	# early = skipped, no reward (§45.5: reward only on SHOWN_COMPLETED).
	var code: AdResult.Code = AdResult.Code.SHOWN_COMPLETED if not _show_rewarded else AdResult.Code.SHOWN_SKIPPED
	var r: AdResult = AdResult.from_code(code, false)
	_user_resolution.emit(r)


func _on_auto_complete() -> void:
	var r: AdResult = AdResult.from_code(AdResult.Code.SHOWN_COMPLETED, _show_rewarded)
	_user_resolution.emit(r)


func _show_overlay(rewarded: bool) -> void:
	if _overlay == null:
		return
	_overlay.visible = true
	_countdown_total = auto_close_seconds
	_countdown = auto_close_seconds
	_auto_close = auto_close_seconds > 0.0
	var kind: String = "REWARDED" if rewarded else "INTERSTITIAL"
	_title_label.text = "MOCK %s AD — %s" % [kind, AdPlacementId.name_of(_show_placement)]
	_close_button.text = "✕ Skip" if rewarded else "✕ Close"
	_close_button.visible = true


func _hide_overlay() -> void:
	if _overlay != null:
		_overlay.visible = false
	_close_button.visible = false


## ALWAYS-process so the countdown ticks while the tree is paused (§45.6).
func _process(delta: float) -> void:
	if _overlay == null or not _overlay.visible or not _auto_close:
		return
	_countdown -= delta
	_countdown_label.text = "Closes in %.1f s" % maxf(0.0, _countdown)
	if _countdown <= 0.0:
		_auto_close = false
		_on_auto_complete()


func show_banner(_position: int) -> void:
	if _banner != null:
		_banner.visible = true


func hide_banner() -> void:
	if _banner != null:
		_banner.visible = false


func get_banner_height_px() -> int:
	return 60 if (_banner != null and _banner.visible) else 0


## SceneTreeTimer helper: process_always so it fires while the tree is
## paused mid-ad.
func _delay(seconds: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(seconds, true).timeout


## Builds the fake-ad overlay (dark panel + countdown + close) and the
## fake banner strip under the container AdManager provides.
func _build_overlay() -> void:
	if _ui_root == null:
		return
	_overlay = CanvasLayer.new()
	_overlay.name = "MockAdOverlay"
	_overlay.layer = 95
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	_ui_root.add_child(_overlay)
	_panel = ColorRect.new()
	_panel.color = Color(0.10, 0.06, 0.16, 0.97)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_panel)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_child(vbox)
	_title_label = Label.new()
	_title_label.text = "MOCK AD"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)
	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_countdown_label)
	_close_button = Button.new()
	_close_button.text = "✕ Close"
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_button.pressed.connect(_on_close_pressed)
	vbox.add_child(_close_button)
	_banner = ColorRect.new()
	_banner.color = Color(0.95, 0.75, 0.2, 0.95)
	_banner.anchor_top = 1.0
	_banner.anchor_bottom = 1.0
	_banner.offset_top = -60.0
	_banner.visible = false
	_overlay.add_child(_banner)
