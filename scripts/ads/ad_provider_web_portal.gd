class_name AdProviderWebPortal
extends AdProvider
## §45.1/§45.2 — Web portal provider (Poki / CrazyGames / GameDistribution).
## ALL portal API knowledge lives in the custom HTML shell's `window.CCPortal`
## bridge (web/portal_shell.html): one small JS adapter object per portal
## (spirit of "PortalAdapter sub-strategy, ~60 lines each"), plus an
## instant-resolve MOCK adapter when the page has no real SDK — that is how
## "mock portal ads fire at every placement" is verifiable in a browser.
##
## Contract notes:
## • Every JS touch is guarded; without JavaScriptBridge (desktop/headless/
##   tests) the provider initializes fine, reports unavailable, and resolves
##   shows as DISABLED immediately — a provider must NEVER hang a caller.
## • Mute + input suspension for the break duration is the AdManager
##   contract (§45.6); the portal owns the ad surface itself.
## • Portals have no banner inventory: banners no-op, height 0.
##
## Talks to: AdManager only. No portal type leaks anywhere else.

const WATCHDOG_S: float = 45.0

var portal_name: String = ""
var _cc: JavaScriptObject = null
var _initialized: bool = false
var _pending: AdResult = null


func initialize(_config: AdConfig, _consent_state: int) -> void:
	_initialized = true
	if not _js_ready():
		return
	var detected: Variant = JavaScriptBridge.eval(
		"(typeof window.CCPortal !== 'undefined' && window.CCPortal.detect()) || null")
	if detected is String and str(detected) != "":
		portal_name = str(detected)
		_cc = JavaScriptBridge.get_interface("CCPortal")
		if _cc != null:
			_cc.gameLoadingFinished()


func is_initialized() -> bool:
	return _initialized


func set_ui_container(_node: Node) -> void:
	pass


func is_available(_placement: AdPlacementId.ID) -> bool:
	return _cc != null


func preload_ad(_placement: AdPlacementId.ID) -> void:
	pass  # portals preload internally


func show_interstitial(_placement: AdPlacementId.ID) -> AdResult:
	var r: AdResult = await _break("commercialBreak", false)
	show_completed.emit(r)
	return r


func show_rewarded(_placement: AdPlacementId.ID) -> AdResult:
	var r: AdResult = await _break("rewardedBreak", true)
	show_completed.emit(r)
	return r


func show_banner(_position: int) -> void:
	pass


func hide_banner() -> void:
	pass


func get_banner_height_px() -> int:
	return 0


## §45.2 lifecycle calls (Poki model; every adapter maps them).
func notify_gameplay_start() -> void:
	if _cc != null:
		_cc.gameplayStart()


func notify_gameplay_stop() -> void:
	if _cc != null:
		_cc.gameplayStop()


static func portal_detected() -> bool:
	if not _js_ready():
		return false
	var v: Variant = JavaScriptBridge.eval(
		"(typeof window.CCPortal !== 'undefined' && window.CCPortal.detect()) || null")
	return v is String and str(v) != ""


static func _js_ready() -> bool:
	return OS.has_feature("web")


## Runs one break through the shell bridge: `method(ok_cb, err_cb)` where
## ok_cb may carry a boolean (rewarded actually earned, §45.2 Poki).
func _break(method: String, rewarded: bool) -> AdResult:
	if _cc == null:
		return AdResult.disabled()
	_pending = null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var ok_cb := JavaScriptBridge.create_callback(
		func(args: Array) -> void:
			var earned: bool = rewarded and args.size() > 0 and bool(args[0])
			_pending = AdResult.from_code(AdResult.Code.SHOWN_COMPLETED, earned)
	)
	var err_cb := JavaScriptBridge.create_callback(
		func(_args: Array) -> void:
			_pending = AdResult.from_code(AdResult.Code.NO_FILL)
	)
	_cc.call(method, ok_cb, err_cb)
	# §45.6 backup watchdog: never wait forever for the portal.
	var waited: float = 0.0
	while _pending == null and waited < WATCHDOG_S:
		await tree.create_timer(0.1, true, false, true).timeout
		waited += 0.1
	if _pending == null:
		return AdResult.from_code(AdResult.Code.TIMEOUT)
	return _pending
