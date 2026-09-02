class_name AdProviderAdMob
extends AdProvider
## §45.1/§45.2 — AdMob SCAFFOLD (mobile). Cannot be completed by the AI:
## the Poing Studios plugin (addons/) must be installed and configured by a
## human with real bundle IDs + ad unit IDs (use Google's official TEST ids
## in development, e.g. Android interstitial ca-app-pub-3940256099942544/
## 1033173712 — never invent real IDs, §45.2). No AdMob type may appear
## outside this file — enforced by test_ads.gd scan.
##
## What EXISTS here (the seam, fully wired):
## • plugin detection: Engine.has_singleton() for the Poing Godot AdMob
##   plugin's expected entry points. Without the plugin (always, in this
##   sandbox) every call degrades to DISABLED/no-op — the game is playable.
## • UMP consent flow stub (§45.8): must run BEFORE initialize() on mobile;
##   ConsentManager drives it and the plugin's UMP API is called from here.
## • test ad unit IDs read from ads.tres (admob_* fields the human fills).
## • child-directed / under-age flags from ads.tres are passed through.
##
## What the HUMAN adds (HUMAN_TASKS): install the plugin under addons/,
## enable its GDExtension in project.godot, fill ads.tres ad unit IDs,
## build an Android/iOS export preset. Then fill the four TODO methods.

const PLUGIN_SINGLETONS: Array[String] = ["PoingGodotAdMob", "PoingAdMob", "AdMob"]


## §45.2: "no AdMob type may appear anywhere outside that one file" —
## provider detection included; AdManager asks THIS class.
static func plugin_present() -> bool:
	for singleton in PLUGIN_SINGLETONS:
		if Engine.has_singleton(singleton):
			return true
	return false

var _plugin: Object = null
var _initialized: bool = false
var _test_ids: Dictionary = {}


func initialize(config: AdConfig, _consent_state: int) -> void:
	_initialized = true
	for singleton in PLUGIN_SINGLETONS:
		if Engine.has_singleton(singleton):
			_plugin = Engine.get_singleton(singleton)
			break
	if _plugin == null:
		return  # scaffold mode: everything degrades to DISABLED
	_test_ids = {
		"interstitial": config.interstitial_ad_unit_id,
		"rewarded": config.rewarded_ad_unit_id,
		"banner": config.banner_ad_unit_id,
		"child_directed": config.tag_for_child_directed_treatment,
		"under_age": config.tag_for_under_age_of_consent,
	}
	# TODO(human): initialize the plugin here (UMP consent already resolved
	# by ConsentManager BEFORE AdManager reached this point, §45.8), load
	# each ad unit with the TEST ids while developing, and wire the
	# plugin's load/show signals into _finish_show.


func is_initialized() -> bool:
	return _initialized


func set_ui_container(_node: Node) -> void:
	pass


func is_available(_placement: AdPlacementId.ID) -> bool:
	# TODO(human): report per-placement load state from the plugin.
	return _plugin != null


func preload_ad(_placement: AdPlacementId.ID) -> void:
	if _plugin == null:
		return
	# TODO(human): request_load for the placement's unit id.


func show_interstitial(placement: AdPlacementId.ID) -> AdResult:
	if _plugin == null:
		return AdResult.disabled()
	# TODO(human): show the loaded interstitial and await the plugin's
	# closed/failed signal, then return the mapped AdResult.
	await (Engine.get_main_loop() as SceneTree).process_frame
	return AdResult.from_code(AdResult.Code.ERROR)


func show_rewarded(placement: AdPlacementId.ID) -> AdResult:
	if _plugin == null:
		return AdResult.disabled()
	# TODO(human): show the loaded rewarded ad; reward ONLY on the
	# plugin's "earned reward" callback (§45.5).
	await (Engine.get_main_loop() as SceneTree).process_frame
	return AdResult.from_code(AdResult.Code.ERROR)


func show_banner(_position: int) -> void:
	if _plugin == null:
		return
	# TODO(human): show banner (respect no_ads_purchased — AdManager gates
	# the call already; this is belt-and-braces).


func hide_banner() -> void:
	if _plugin == null:
		return
	# TODO(human): hide + destroy banner view.


func get_banner_height_px() -> int:
	if _plugin == null:
		return 0
	# TODO(human): return the real banner height in screen px.
	return 0
