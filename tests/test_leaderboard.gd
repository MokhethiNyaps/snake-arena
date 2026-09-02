extends RefCounted
## §9A.8 — Score/leaderboard sort stability + row building + player rank,
## and the settings.cfg persistence round-trip (Phase 8 additions).

const SORT = preload("res://scripts/ui/leaderboard_sort.gd")


func test_sort_descending_and_stable() -> bool:
	var entries: Array = []
	for i in 5:
		entries.append({"name": "A%d" % i, "power": 100.0 - float(i) * 10.0, "is_player": false, "id": i})
	var sorted: Array = SORT.sort_entries(entries)
	var last: float = INF
	for e in sorted:
		if float(e["power"]) > last:
			printerr("  sort not descending")
			return false
		last = float(e["power"])
	# Stability: equal powers keep insertion order.
	var tied: Array = [
		{"name": "first", "power": 50.0, "is_player": false, "id": 1},
		{"name": "second", "power": 50.0, "is_player": false, "id": 2},
		{"name": "big", "power": 90.0, "is_player": false, "id": 3},
	]
	var tied_sorted: Array = SORT.sort_entries(tied)
	if str(tied_sorted[0]["name"]) != "big" or str(tied_sorted[1]["name"]) != "first" or str(tied_sorted[2]["name"]) != "second":
		printerr("  tie order changed: %s" % str(tied_sorted.map(func(e): return e["name"])))
		return false
	# Input array must not be mutated.
	if entries.size() != 5 or float(entries[0]["power"]) != 100.0:
		printerr("  input array mutated by sort")
		return false
	return true


func test_build_rows_top5_plus_player() -> bool:
	var entries: Array = []
	for i in 8:
		entries.append({"name": "AI%d" % i, "power": 20.0 + float(i) * 5.0, "is_player": false, "id": i})
	entries.append({"name": "YOU", "power": 1.0, "is_player": true, "id": 99})
	var rows: Array = SORT.build_rows(entries, 5)
	if rows.size() != 6:
		printerr("  expected 5 top rows + player row, got %d" % rows.size())
		return false
	if not bool(rows.back()["is_player"]):
		printerr("  player row missing when outside top 5")
		return false
	if SORT.player_rank(entries) != 9:
		printerr("  player rank %d != 9" % SORT.player_rank(entries))
		return false
	# Player inside top 5: no duplicate extra row.
	entries.append({"name": "BIG-YOU", "power": 1.0, "is_player": true, "id": 100})
	entries[-1]["power"] = 999.0
	var rows2: Array = SORT.build_rows(entries, 5)
	if rows2.size() != 5:
		printerr("  expected exactly 5 rows when player is inside top, got %d" % rows2.size())
		return false
	if not bool(rows2[0]["is_player"]):
		printerr("  top row should be the player (999 power)")
		return false
	return true


func test_settings_roundtrip() -> bool:
	# §14/§9A.6 (settings.cfg slice): write → read → deep-compare.
	var section: String = "test_section_%d" % (Time.get_ticks_msec() % 100000)
	var want: Dictionary = {
		"float": 12.5, "int": 42, "bool": true, "string": "skin_neon",
	}
	for key in want:
		SaveManager.set_setting(section, key, want[key])
	for key in want:
		var got: Variant = SaveManager.get_setting(section, key, null)
		if str(got) != str(want[key]) and got != want[key]:
			printerr("  roundtrip mismatch %s: %s != %s" % [key, str(got), str(want[key])])
			return false
	# File reload from disk (deep compare through a fresh ConfigFile).
	var fresh: ConfigFile = ConfigFile.new()
	if fresh.load("user://settings.cfg") == OK:
		var from_disk: Variant = fresh.get_value(section, "float", -1.0)
		if absf(float(from_disk) - 12.5) > 0.0001:
			printerr("  disk value for float is %s" % str(from_disk))
			return false
	else:
		printerr("  settings.cfg failed to reload")
		return false
	# Cleanup the test section values.
	for key in want:
		SaveManager.set_setting(section, key, null)
	return true
