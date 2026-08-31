class_name AdPlacementDef
extends Resource
## §45.3 — One row of the placement inventory table (sub-resource of AdConfig).
##
## Owns: caps, gaps and type for one placement. The human retunes these in
##        resources/config/ads.tres (or via RemoteConfig) without code changes.
## Talks to: AdPacer (Phase 4) reads these to decide can_show().

enum AdType { INTERSTITIAL, REWARDED, BANNER, APP_OPEN }

## Which placement from §45.3 this row configures.
@export var id: AdPlacementId.ID = AdPlacementId.ID.INTER_RUN
## Ad format for this placement.
@export var type: AdType = AdType.INTERSTITIAL
## Earliest session run index at which this may fire (FTUE protection).
@export var min_run_index: int = 3
## Minimum seconds since the last interstitial (interstitials only).
@export var min_gap_seconds: float = 120.0
## Max shows per session (-1 = unlimited).
@export var session_cap: int = -1
## Max shows per calendar day (-1 = unlimited).
@export var daily_cap: int = -1
## On NO_FILL/ERROR (never on user skip): grant the reward anyway.
## For non-competitive rewards only (coins, rerolls). Revive must stay false.
@export var grant_on_no_fill: bool = false
