class_name AdProvider
extends RefCounted
## §45.1 — THE ad abstraction interface. Every concrete provider (Null, Mock,
## WebPortal, AdMob) implements this; no SDK type may ever appear outside its
## own provider file.
##
## Owns: the contract. Does NOT own: pacing, pausing, audio ducking — those
##        belong to AdManager and are identical for every provider (§45.6).
## Talks to: only AdManager.

# Lifecycle
func initialize(config: AdConfig, consent_state: int) -> void:
	pass


func is_initialized() -> bool:
	return false


func shutdown() -> void:
	pass


# Availability
func is_available(placement: AdPlacementId.ID) -> bool:
	return false


func preload_ad(placement: AdPlacementId.ID) -> void:
	pass


# Showing. Async in real providers; must ALWAYS resolve (AdManager enforces
# the watchdog timeout regardless of provider behaviour).
func show_interstitial(placement: AdPlacementId.ID) -> AdResult:
	return AdResult.disabled()


func show_rewarded(placement: AdPlacementId.ID) -> AdResult:
	return AdResult.disabled()


# Banners
func show_banner(position: int) -> void:
	pass


func hide_banner() -> void:
	pass


func get_banner_height_px() -> int:
	return 0
