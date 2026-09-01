class_name AdProvider
extends RefCounted
## §45.1 — THE ad abstraction interface. Every concrete provider (Null, Mock,
## WebPortal, AdMob) implements this; no SDK type may ever appear outside its
## own provider file.
##
## Owns: the contract. Does NOT own: pacing, pausing, audio ducking — those
##        belong to AdManager and are identical for every provider (§45.6).
## Talks to: only AdManager.
##
## Completion model (decision #33): show_* start an async show, emit
## `show_completed(result)` when it resolves, and also RETURN the final
## AdResult (so a caller could await it with its own timeout). AdManager
## listens to the signal and races it against its watchdog — a provider
## that never resolves (crash/hang) can therefore never freeze the game.

## Emitted when a show resolves, on EVERY path (success/skip/fail/timeout).
## AdManager listens with CONNECT_ONE_SHOT and races against its watchdog.
signal show_completed(result: AdResult)

# Lifecycle
func initialize(config: AdConfig, consent_state: int) -> void:
	pass


func is_initialized() -> bool:
	return false


func shutdown() -> void:
	pass


## Optional: a UI container under which the provider may build its own
## visual elements (the mock's fake ad overlay / banner). No-op elsewhere.
func set_ui_container(node: Node) -> void:
	pass


# Availability
func is_available(placement: AdPlacementId.ID) -> bool:
	return false


func preload_ad(placement: AdPlacementId.ID) -> void:
	pass


# Showing. Async; must ALWAYS resolve (via show_completed + the returned
# result). The watchdog in AdManager is the backstop regardless of provider
# behaviour.
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
