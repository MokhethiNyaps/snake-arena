class_name LocalLeaderboardBackend
extends ILeaderboardBackend
## §17 local implementation — top-20 persisted in save.json (§16) via
## SaveManager. One-file swap for a remote backend later.


func submit_score(score: float, meta: Dictionary) -> void:
	SaveManager.submit_high_score(score, str(meta.get("skin", "classic")))


func fetch_top(count: int) -> Array:
	var all: Array = SaveManager.get_high_scores()
	if all.size() <= count:
		return all.duplicate()
	return all.slice(0, count)
