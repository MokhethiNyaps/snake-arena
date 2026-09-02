class_name ILeaderboardBackend
extends RefCounted
## §17 leaderboard backend INTERFACE (§1 dependency inversion).
##
## A future RemoteLeaderboardBackend (Silent Wolf / PlayFab / Nakama / custom)
## must be a DROP-IN replacement: same two methods, same payload shapes.
## Do NOT build the online one now (§17). Submits are fire-and-forget —
## backends may be async internally; fetch_top returns what is available
## locally (remote cache or local file).


## score: float; meta: { "date": String, "skin": String } (extend carefully —
## remote backends will persist whatever you send).
func submit_score(score: float, meta: Dictionary) -> void:
	pass  # virtual


## Returns up to `count` entries, best first:
##   [ { "score": float, "date": String, "skin": String }, ... ]
func fetch_top(count: int) -> Array:
	return []  # virtual


func is_online() -> bool:
	return false
