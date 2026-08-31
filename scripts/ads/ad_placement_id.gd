class_name AdPlacementId
extends RefCounted
## §45.3 — Enum of every ad placement in the inventory.
##
## Owns: the placement identity constants. No logic.
## Talks to: AdManager, AdPacer, and gameplay call sites (via ints).

enum ID {
	INTER_RUN,      ## Interstitial between runs (PLAY AGAIN)
	MENU_RETURN,    ## Interstitial on return to main menu
	REVIVE,         ## Rewarded: game-over revive
	DOUBLE_COINS,   ## Rewarded: x2 coins at game over
	MISSION_REROLL, ## Rewarded: missions screen reroll
	SKIN_TRIAL,     ## Rewarded: 24h skin unlock
	STARTER_BOOST,  ## Rewarded: pre-run Power 24 + Aegis
	BANNER_MENU,    ## Banner: menu screens only, never gameplay
	APP_OPEN,       ## App Open: cold start, run #2+, mobile only
}


## Human-readable id for logs and the debug ad panel.
static func name_of(placement: ID) -> String:
	return ID.keys()[placement]
