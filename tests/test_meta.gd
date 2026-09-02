extends RefCounted
## Phase 9 — §16/§17 meta: save.json versioning + checksum + corruption
## fallback (§16 exit criterion), wallet/XP math, high-score cap, skin rules
## + the "SnakeController contains zero skin code" invariant, daily missions,
## and the ILeaderboardBackend local implementation.
##
## NOTE: these tests mutate user://save.json and restore a pristine default
## state at the end (final test runs last by declaration order).

const META := preload("res://scripts/config/meta_config.gd")


func _fresh_save() -> void:
	# Isolated defaults: remove disk state + force in-memory defaults.
	DirAccess.remove_absolute("user://save.json")
	DirAccess.remove_absolute("user://save.json.corrupt")
	SaveManager.reset_for_verify()


func test_xp_level_curve() -> bool:
	var cfg: MetaConfig = META.new()
	if META.xp_needed_cumulative(cfg, 1) != 0:
		printerr("  level 1 must cost 0 XP")
		return false
	if META.xp_needed_cumulative(cfg, 2) != 220:
		printerr("  level 2 must cost 220 XP (220*1^1.35), got %d" % META.xp_needed_cumulative(cfg, 2))
		return false
	if META.level_for_xp(cfg, 0) != 1 or META.level_for_xp(cfg, 219) != 1:
		printerr("  219 XP must still be level 1")
		return false
	if META.level_for_xp(cfg, 220) != 2:
		printerr("  220 XP must be level 2")
		return false
	var last: int = 0
	for xp in [0, 220, 700, 2000, 6000, 20000]:
		var lvl: int = META.level_for_xp(cfg, xp)
		if lvl < last:
			printerr("  level not monotonic at xp=%d" % xp)
			return false
		last = lvl
	return true


func test_save_roundtrip_and_checksum() -> bool:
	_fresh_save()
	SaveManager.add_coins(77, &"test")
	var raw: String = FileAccess.get_file_as_string("user://save.json")
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		printerr("  save.json not valid JSON after write")
		return false
	var data: Dictionary = parsed
	if int(data.get("save_version", 0)) != 1:
		printerr("  save_version missing/wrong: %s" % str(data.get("save_version")))
		return false
	if not data.has("checksum"):
		printerr("  checksum missing")
		return false
	# Reload: values survive.
	SaveManager._load_save()
	if SaveManager.get_coins() != 77:
		printerr("  coins lost across reload: %d" % SaveManager.get_coins())
		return false
	return true


func test_corrupt_save_never_crashes() -> bool:
	# §16 exit criterion: corrupt save → defaults, no crash.
	DirAccess.remove_absolute("user://save.json.corrupt")
	var f: FileAccess = FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string("{this is not json")
	f.close()
	SaveManager._load_save()
	if SaveManager.get_coins() != 0:
		printerr("  invalid JSON did not fall back to defaults")
		return false
	if not FileAccess.file_exists("user://save.json.corrupt"):
		printerr("  corrupt file not quarantined")
		return false
	# Valid JSON, WRONG checksum.
	f = FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"save_version": 1, "checksum": 12345,
		"wallet": {"coins": 99999, "lifetime_earned": 99999, "xp": 0},
	}))
	f.close()
	DirAccess.remove_absolute("user://save.json.corrupt")
	SaveManager._load_save()
	if SaveManager.get_coins() != 0:
		printerr("  checksum mismatch did not fall back to defaults (coins=%d)" % SaveManager.get_coins())
		return false
	# Newer version: refuse to guess.
	f = FileAccess.open("user://save.json", FileAccess.WRITE)
	var payload: Dictionary = {
		"save_version": 99, "wallet": {"coins": 5, "lifetime_earned": 5, "xp": 0}}
	payload["checksum"] = JSON.stringify(payload, "", true).hash()
	f.store_string(JSON.stringify(payload))
	f.close()
	DirAccess.remove_absolute("user://save.json.corrupt")
	SaveManager._load_save()
	if SaveManager.get_coins() != 0:
		printerr("  newer-version save not refused")
		return false
	return true


func test_wallet_and_spend() -> bool:
	_fresh_save()
	SaveManager.add_coins(100, &"test")
	if SaveManager.get_coins() != 100 or SaveManager.get_lifetime_coins() != 100:
		printerr("  add_coins broke the wallet")
		return false
	if not SaveManager.try_spend(40, &"test"):
		printerr("  spend of 40 from 100 must succeed")
		return false
	if SaveManager.get_coins() != 60:
		printerr("  balance wrong after spend: %d" % SaveManager.get_coins())
		return false
	if SaveManager.try_spend(9999, &"test"):
		printerr("  overspend must be refused")
		return false
	if SaveManager.get_coins() != 60:
		printerr("  refused spend changed the balance")
		return false
	if SaveManager.get_lifetime_coins() != 100:
		printerr("  lifetime must track EARNED only")
		return false
	return true


func test_high_score_cap_and_best() -> bool:
	_fresh_save()
	for i in 25:
		# Monotonically increasing scores beat the all-time best EVERY time
		# by definition (new_best = score > previous all-time best).
		var is_best: bool = SaveManager.submit_high_score(float(100 + i), "classic")
		if not is_best:
			printerr("  increasing score %d must flag new_best" % i)
			return false
	var entries: Array = SaveManager.get_high_scores()
	if entries.size() != 20:
		printerr("  cap not enforced: %d entries" % entries.size())
		return false
	if float(entries[0]["score"]) != 124.0:
		printerr("  entries not sorted desc: top=%s" % str(entries[0]["score"]))
		return false
	if SaveManager.get_best_score() != 124.0:
		printerr("  best score wrong: %s" % str(SaveManager.get_best_score()))
		return false
	return true


func test_skins_rules_and_invariant() -> bool:
	_fresh_save()
	var sm: SkinManager = SkinManager.new()  # not in tree; load catalogue directly
	sm._load_catalogue()
	if sm.get_all().size() != 8:
		printerr("  catalogue must ship 8 skins, found %d" % sm.get_all().size())
		return false
	if not sm.is_owned("classic") or sm.get_equipped_id() != "classic":
		printerr("  classic must be owned + equipped by default")
		return false
	var neon: SkinDef = sm.get_def("neon")
	if neon == null or sm.can_buy(neon):
		printerr("  neon must be level-gated at level 1")
		return false
	if sm.equip("void"):
		printerr("  equipping an unowned skin must fail")
		return false
	# Level 2 + coins → buy + equip works. NOTE: add_xp(220) ALSO pays the
	# level-up coin bonus (+50) — assert the SPEND DELTA, not the balance.
	SaveManager.add_xp(220)
	SaveManager.add_coins(neon.price, &"test")
	var coins_before_buy: int = SaveManager.get_coins()
	if not sm.buy(neon) or not sm.is_owned("neon"):
		printerr("  buy at level 2 with coins must succeed")
		return false
	if SaveManager.get_coins() != coins_before_buy - neon.price:
		printerr("  buy must spend exactly the price: %d != %d - %d" % [
			SaveManager.get_coins(), coins_before_buy, neon.price])
		return false
	if not sm.equip("neon") or sm.get_equipped_id() != "neon":
		printerr("  equip of owned skin failed")
		return false
	# §16 invariant: SnakeController contains zero skin CODE (comments only).
	var src: String = FileAccess.get_file_as_string("res://scripts/snake/snake_controller.gd")
	for line in src.split("\n"):
		var code: String = line.split("#")[0].strip_edges()
		if code.is_empty():
			continue
		if "skin" in code.to_lower():
			printerr("  SnakeController references skins in code: %s" % line)
			return false
	return true


func test_missions_day_progress_reroll() -> bool:
	_fresh_save()
	var mm: MissionManager = MissionManager.new()
	Engine.get_main_loop().root.add_child(mm)
	if mm.get_missions().size() != 3:
		printerr("  must generate 3 daily missions, got %d" % mm.get_missions().size())
		return false
	# Per-run MAX semantics: advance below goal then above.
	var m0: Dictionary = mm.get_missions()[0]
	var coins_before: int = SaveManager.get_coins()
	mm._advance(str(m0["metric"]), float(m0["goal"]) * 0.5)
	if mm.get_progress(str(m0["id"])) != float(m0["goal"]) * 0.5:
		printerr("  progress below goal not recorded")
		mm.queue_free()
		return false
	mm._advance(str(m0["metric"]), float(m0["goal"]))
	var m0_after: Dictionary = mm.get_missions()[0]
	if not bool(m0_after["done"]):
		printerr("  reaching the goal must complete")
		mm.queue_free()
		return false
	if SaveManager.get_coins() != coins_before + int(m0["reward"]):
		printerr("  completion must pay the reward")
		mm.queue_free()
		return false
	# Same metric at LOWER value must not regress max progress.
	mm._advance(str(m0["metric"]), 1.0)
	if mm.get_progress(str(m0["id"])) != float(m0["goal"]):
		printerr("  max-per-run semantics violated (progress regressed)")
		mm.queue_free()
		return false
	# Reroll: once per day only.
	if not mm.can_reroll() or not mm.reroll_all():
		printerr("  first reroll must be allowed")
		mm.queue_free()
		return false
	if mm.can_reroll() or mm.reroll_all():
		printerr("  second reroll same day must be refused")
		mm.queue_free()
		return false
	# Cumulative top3 metric.
	var before_top3: float = 0.0
	for m in mm.get_missions():
		if m["metric"] == "top3":
			before_top3 = float(m["progress"])
			mm._advance_cumulative("top3")
			if float(mm.get_missions()[mm.get_missions().find(m)]["progress"]) != before_top3 + 1.0:
				printerr("  top3 must be cumulative")
				mm.queue_free()
				return false
	mm.queue_free()
	return true


func test_leaderboard_backend_swap() -> bool:
	_fresh_save()
	var lb: LeaderboardManager = LeaderboardManager.new()
	Engine.get_main_loop().root.add_child(lb)  # _ready sets the default backend
	if lb.backend == null or lb.backend.is_online():
		printerr("  default backend must be the local one")
		return false
	var was_best: bool = lb.submit_run(500.0, {"skin": "neon"})
	if not was_best:
		printerr("  500 on an empty board must be the best")
		return false
	if lb.submit_run(100.0, {"skin": "neon"}):
		printerr("  100 after 500 must not be best")
		return false
	var top: Array = lb.fetch_top(5)
	if top.size() != 2 or float(top[0]["score"]) != 500.0:
		printerr("  fetch_top order wrong: %s" % str(top))
		return false
	if str(top[0].get("skin", "")) != "neon":
		printerr("  meta (skin) not persisted with the entry")
		lb.queue_free()
		return false
	lb.queue_free()
	return true


func test_settings_migration_then_restore() -> bool:
	# Decision #58 promise: Phase 8 interim settings.cfg keys migrate.
	DirAccess.remove_absolute("user://save.json")
	SaveManager._settings.set_value("ftue", "completed", true)
	SaveManager._settings.set_value("progress", "best_score", 1234.0)
	SaveManager._load_save()
	if not SaveManager.is_ftue_done():
		printerr("  ftue.completed did not migrate")
		return false
	if SaveManager.get_best_score() != 1234.0:
		printerr("  progress.best_score did not migrate: %s" % str(SaveManager.get_best_score()))
		return false
	if SaveManager.get_high_scores().size() != 1:
		printerr("  migrated best must seed one high-score entry")
		return false
	# Leave a pristine default state for any later consumer.
	_fresh_save()
	return true
