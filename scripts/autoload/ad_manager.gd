extends Node
## AUTOLOAD #6 — AdManager (§45). The ONLY ad-facing surface gameplay sees.
##
## Owns: provider selection, the ad-safety contract (pause/duck/suspend/
##        overlay/watchdog), pacing, and the ad_* signals. Gameplay calls
##        exactly ONE entry point: `await AdManager.request_ad(placement)`.
## Phase 1: provider selection + null-provider fast path only. Phase 4 lands
##          the full contract, AdPacer, mock provider and the debug panel.
## Does NOT own: ad SDK internals (they live in each AdProvider).
## Talks to: AdProviders (down), gameplay systems (up, via signals/awaits).

# Signals (§45.1: emitted by AdManager, never by gameplay)
signal ad_started(placement: int)
signal ad_finished(placement: int, result: AdResult)
signal ad_reward_granted(placement: int, reward_id: StringName)
signal ad_failed(placement: int, reason: String)

var provider: AdProvider = null
var _config: AdConfig = null


func _ready() -> void:
	_config = load("res://resources/config/ads.tres") as AdConfig
	provider = _select_provider()
	print("[AdManager] Provider: %s (ads %s)" % [
		provider.get_script().get_global_name() if provider.get_script() else "unknown",
		"ENABLED" if (_config != null and _config.ads_enabled) else "DISABLED",
	])


## §45.1 selection logic. Phase 4 adds mock-in-editor + portal detection;
## null is the correct, safe default everywhere until then.
func _select_provider() -> AdProvider:
	return AdProviderNull.new()


## The single gameplay entry point. Always resolves — never throws, never
## hangs (watchdog lands in Phase 4; null provider resolves instantly).
## Callers MUST await it.
func request_ad(placement: int) -> AdResult:
	# Phase 4 replaces this body with the full §45.6 contract (pause, duck
	# audio, suspend input, overlay, watchdog, restore). Keeping it a
	# coroutine from day one so call sites never change shape.
	await get_tree().process_frame
	if provider == null:
		return AdResult.disabled()
	if provider.is_available(placement):
		var placement_def: AdPlacementDef = _config.get_placement(placement) if _config else null
		var is_rewarded: bool = placement_def != null and placement_def.type == AdPlacementDef.AdType.REWARDED
		return provider.show_rewarded(placement) if is_rewarded else provider.show_interstitial(placement)
	return AdResult.disabled()


func is_available(placement: int) -> bool:
	return provider != null and provider.is_available(placement)


func preload_ad(placement: int) -> void:
	if provider != null:
		provider.preload_ad(placement)


# Banners (menu screens only, §45.3)
func show_banner(position: int) -> void:
	if provider != null:
		provider.show_banner(position)


func hide_banner() -> void:
	if provider != null:
		provider.hide_banner()


func get_banner_height_px() -> int:
	return provider.get_banner_height_px() if provider != null else 0
