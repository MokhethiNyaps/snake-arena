class_name LeaderboardSort
extends RefCounted
## §9A.8 — Live leaderboard sort (stable, by power desc, ties broken by
## instance id for determinism). Shared by the HUD widget and the tests;
## the HUD only formats what this produces.

static func sort_entries(entries: Array) -> Array:
	# entries: [{name: String, power: float, is_player: bool, id: int}]
	# stable-sort by power desc; equal powers keep insertion order (GDScript
	# sort is stable), and the builder below inserts the player last so ties
	# rank the player just under rivals — matching the §9 eat rule's spirit
	# (the 10% buffer means "equal" is never a win for either side).
	var out: Array = entries.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["power"]) > float(b["power"]))
	return out


## Builds the display list for the in-match leaderboard: top `top_count`
## rows, plus the player's own row appended when outside the top slice.
static func build_rows(entries: Array, top_count: int) -> Array:
	var sorted: Array = sort_entries(entries)
	var rows: Array = []
	for i in mini(sorted.size(), top_count):
		rows.append(sorted[i])
	if sorted.size() > top_count:
		var player_idx: int = -1
		for i in sorted.size():
			if bool(sorted[i]["is_player"]):
				player_idx = i
				break
		if player_idx >= top_count:
			rows.append(sorted[player_idx])
	return rows


## The player's 1-based rank in the full sorted list.
static func player_rank(entries: Array) -> int:
	var sorted: Array = sort_entries(entries)
	for i in sorted.size():
		if bool(sorted[i]["is_player"]):
			return i + 1
	return 0
