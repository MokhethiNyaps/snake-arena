class_name LeaderboardManager
extends Node
## §17 façade: owns the current ILeaderboardBackend and routes submits.
## The HUD's LIVE in-match leaderboard (sorted by power, 4 Hz) is separate —
## see scripts/ui/leaderboard_sort.gd; this is the persistent high-score side.


var backend: ILeaderboardBackend = null


func _ready() -> void:
	set_backend(LocalLeaderboardBackend.new())


## One-file swap point for a remote backend (§17).
func set_backend(b: ILeaderboardBackend) -> void:
	backend = b


## meta: { "skin": String }. Returns true when this was the new all-time best.
func submit_run(score: float, meta: Dictionary) -> bool:
	if backend == null:
		return false
	var was_best: float = SaveManager.get_best_score()
	backend.submit_score(score, meta)
	return score > was_best and score > 0.0


func fetch_top(count: int) -> Array:
	return backend.fetch_top(count) if backend != null else []
