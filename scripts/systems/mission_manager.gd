class_name MissionManager
extends Node
## §16 daily missions — 3 per day, rerollable once via rewarded ad.
##
## Owns: mission generation (deterministic per UTC day), live progress
##        tracking, rewards, persistence.
## Does NOT own: coins (SaveManager grants), ads (the screen requests
##        MISSION_REROLL and calls reroll_all on completion).
## Talks to: EventBus (collectible_absorbed, power_changed, run_started),
##           SaveManager, Analytics, boot (run stats).
##
## Progress semantics: PER-RUN MAX for run-scoped metrics (absorbs, power,
## cells, score, time — "best single run counts"), CUMULATIVE for top-3
## finishes. Deterministic selection: seeded by the UTC date string, so a
## day always rolls the same set (test-friendly, no save churn).

const POOL: Array[Dictionary] = [
	{"id": "absorb_5", "desc": "Absorb 5 rivals in one run", "metric": "absorbs", "goal": 5, "reward": 80},
	{"id": "power_512", "desc": "Reach Power 512", "metric": "power", "goal": 512.0, "reward": 70},
	{"id": "cells_300", "desc": "Collect 300 cells in one run", "metric": "cells", "goal": 300, "reward": 60},
	{"id": "top3_twice", "desc": "Finish top 3 twice", "metric": "top3", "goal": 2, "reward": 75},
	{"id": "score_2000", "desc": "Score 2,000 in one run", "metric": "score", "goal": 2000.0, "reward": 65},
	{"id": "survive_180", "desc": "Survive 3 minutes", "metric": "time", "goal": 180.0, "reward": 70},
]

## Live per-run cells counter (fed by EventBus.collectible_absorbed).
var _run_cells: int = 0
var _missions: Array[Dictionary] = []
var _today: String = ""


func _ready() -> void:
	_roll_day_if_needed()
	EventBus.run_started.connect(func() -> void: _run_cells = 0)
	# Player-scoped by construction: only player_controller emits with a real
	# collectible type (combat absorb rewards use type_id 99 — skipped).
	EventBus.collectible_absorbed.connect(_on_collected)
	EventBus.power_changed.connect(_on_power_changed)


# --- day / generation ------------------------------------------------------------

func today() -> String:
	return Time.get_date_string_from_system(true)


func _roll_day_if_needed() -> void:
	var state: Dictionary = SaveManager.get_mission_state()
	var date: String = str(state.get("date", ""))
	_today = today()
	if date == _today and not (state.get("entries", []) as Array).is_empty():
		_load_entries(state.get("entries", []))
		return
	_generate(date != "" and state.get("rerolled", false))


## Deterministic 3-of-pool pick seeded by the date.
func _generate(keep_rerolled: bool) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(_today)
	var pool: Array = POOL.duplicate()
	_missions.clear()
	for i in SaveManager.meta_config().daily_mission_count:
		if pool.is_empty():
			break
		var idx: int = rng.randi_range(0, pool.size() - 1)
		var def: Dictionary = pool[idx]
		pool.remove_at(idx)
		_missions.append({
			"id": def["id"], "desc": def["desc"], "metric": def["metric"],
			"goal": def["goal"], "reward": int(def["reward"]),
			"progress": 0.0, "done": false,
		})
	_persist(keep_rerolled)


func _load_entries(entries: Array) -> void:
	_missions.clear()
	for e in entries:
		var def: Dictionary = _def_by_id(str(e.get("id", "")))
		if def.is_empty():
			continue
		_missions.append({
			"id": def["id"], "desc": def["desc"], "metric": def["metric"],
			"goal": def["goal"], "reward": int(def["reward"]),
			"progress": float(e.get("progress", 0.0)), "done": bool(e.get("done", false)),
		})


func _def_by_id(id: String) -> Dictionary:
	for d in POOL:
		if str(d["id"]) == id:
			return d
	return {}


func _persist(rerolled: bool) -> void:
	var entries: Array = []
	for m in _missions:
		entries.append({"id": m["id"], "progress": m["progress"], "done": m["done"]})
	SaveManager.set_mission_state({"date": _today, "rerolled": rerolled, "entries": entries})


# --- progress ----------------------------------------------------------------------

func _on_collected(type_id: int, _value: float) -> void:
	if type_id == 99:
		return  # absorb reward, not a cell
	_run_cells += 1
	_advance("cells", float(_run_cells))


func _on_power_changed(power: float) -> void:
	_advance("power", power)


## Called by the run director at game over with the final stats dict.
func on_run_ended(stats: Dictionary) -> void:
	_advance("absorbs", float(stats.get("absorbed", 0)))
	_advance("score", float(stats.get("score", 0.0)))
	_advance("time", float(stats.get("time_s", 0.0)))
	if int(stats.get("field_size", 0)) > 0 and int(stats.get("rank", 99)) <= 3:
		_advance_cumulative("top3")
	_persist(_rerolled_flag())


func _advance(metric: String, value: float) -> void:
	var changed: bool = false
	for m in _missions:
		if m["metric"] != metric or m["done"]:
			continue
		if value > float(m["progress"]):
			m["progress"] = value
			changed = true
		if float(m["progress"]) >= float(m["goal"]):
			m["done"] = true
			_complete(m)
			changed = true
	if changed:
		_persist(_rerolled_flag())


func _advance_cumulative(metric: String) -> void:
	for m in _missions:
		if m["metric"] != metric or m["done"]:
			continue
		m["progress"] = float(m["progress"]) + 1.0
		if float(m["progress"]) >= float(m["goal"]):
			m["done"] = true
			_complete(m)
	_persist(_rerolled_flag())


func _complete(m: Dictionary) -> void:
	SaveManager.add_coins(int(m["reward"]), &"mission")
	EventBus.mission_completed.emit(StringName(m["id"]))
	Analytics.track(&"mission_completed", {"id": m["id"], "reward": m["reward"]})


func _rerolled_flag() -> bool:
	return bool(SaveManager.get_mission_state().get("rerolled", false))


# --- reroll (rewarded-ad gated, once per day) ----------------------------------------

func can_reroll() -> bool:
	return not bool(SaveManager.get_mission_state().get("rerolled", false))


## Called by the missions screen ONLY after MISSION_REROLL completed.
func reroll_all() -> bool:
	if not can_reroll():
		return false
	_generate(true)
	Analytics.track(&"mission_rerolled", {})
	return true


# --- read API ------------------------------------------------------------------------

func get_missions() -> Array[Dictionary]:
	return _missions


func get_progress(id: String) -> float:
	for m in _missions:
		if m["id"] == id:
			return float(m["progress"])
	return 0.0
