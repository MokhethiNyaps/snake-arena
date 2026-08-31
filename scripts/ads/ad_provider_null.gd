class_name AdProviderNull
extends AdProvider
## §45.1 — The "ads completely disabled" provider. Used on desktop dev builds,
## in headless tests, and as the guaranteed-safe fallback.
##
## Owns: the nothing-happens implementation. The game MUST be fully playable
##        and shippable with this provider (§45.1 exit requirement).
## Talks to: nobody but AdManager.

func is_initialized() -> bool:
	return true


func is_available(_placement: AdPlacementId.ID) -> bool:
	return false


func show_interstitial(_placement: AdPlacementId.ID) -> AdResult:
	return AdResult.disabled()


func show_rewarded(_placement: AdPlacementId.ID) -> AdResult:
	return AdResult.disabled()


func get_banner_height_px() -> int:
	return 0
