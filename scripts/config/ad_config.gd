class_name AdConfig
extends Resource
## §45 — All monetization tuning: enables, caps, consent URLs, ad unit IDs and
## the placement inventory table. The human fills real IDs here (or in
## RemoteConfig) before shipping; Google's official DEMO ids ship as defaults.
##
## Owns: ad-layer configuration data. No behaviour.
## Talks to: AdManager/AdPacer/ConsentManager read it. Pure data.

@export_group("Master switches")
## Master switch. When false, every placement is denied immediately.
@export var ads_enabled: bool = true
## In the editor, prefer the Mock provider for manual testing (§45.7).
@export var use_mock_in_editor: bool = true

@export_group("Pacing (§45.4)")
## Hard cap on interstitials per session.
@export var session_interstitial_cap: int = 6
## App Open ad at most once per this many hours.
@export var app_open_cooldown_hours: float = 4.0

@export_group("Watchdogs (§45.6 — mandatory)")
## Force-resolve a stuck preload after this many seconds.
@export var load_watchdog_seconds: float = 12.0
## Force-resolve a stuck show after this many seconds (TIMEOUT). The game
## must never be able to get stuck behind an ad.
@export var show_watchdog_seconds: float = 90.0

@export_group("Consent & compliance (§45.8)")
## Filled in by the HUMAN (see docs/HUMAN_TASKS.md Part B) — not by the AI.
@export_multiline var privacy_policy_url: String = ""
@export_multiline var terms_url: String = ""

@export_group("Ad unit IDs — Google OFFICIAL demo IDs (test ads only)")
## Replace with real IDs from the AdMob console before shipping. Never ship demo IDs.
@export var app_id: String = "ca-app-pub-3940256099942544~3347511713"
@export var app_open_ad_unit_id: String = "ca-app-pub-3940256099942544/5575463023"
@export var banner_ad_unit_id: String = "ca-app-pub-3940256099942544/2934735716"
@export var interstitial_ad_unit_id: String = "ca-app-pub-3940256099942544/4411468910"
@export var rewarded_ad_unit_id: String = "ca-app-pub-3940256099942544/1712485313"
@export var rewarded_interstitial_ad_unit_id: String = "ca-app-pub-3940256099942544/6978759866"

@export_group("Placement inventory (§45.3)")
## One row per placement; caps/gaps live here, not in code.
@export var placements: Array[AdPlacementDef] = []


## Row for a placement id, or null.
func get_placement(id: AdPlacementId.ID) -> AdPlacementDef:
	for p in placements:
		if p.id == id:
			return p
	return null
