extends Node
## AUTOLOAD #2 — SaveManager (§22 + §16 save file). Loads BEFORE anything reads.
##
## Owns: user:// persistence — settings.cfg (live settings) AND save.json
##        (versioned, checksummed meta progress: wallet, XP, skins, daily
##        missions, high scores, lifetime stats, FTUE flag).
## Corruption policy (§16 exit criterion): settings.cfg → defaults (Phase 1);
##        save.json → checksum + parse validation, on failure the file is
##        QUARANTINED as save.json.corrupt and defaults load — never a crash.
##        Writes are atomic (tmp file + rename) so a mid-write kill cannot
##        corrupt the previous save.
## Does NOT own: what the data means. Managers interpret; this stores.
## Talks to: MissionManager, SkinManager, LeaderboardManager, boot, EventBus
##           (coins_changed, level_up), Analytics.

const SETTINGS_PATH: String = "user://settings.cfg"
const SAVE_PATH: String = "user://save.json"
const SAVE_TMP_PATH: String = "user://save.json.tmp"
const SAVE_CORRUPT_PATH: String = "user://save.json.corrupt"
const SAVE_VERSION: int = 1

signal save_loaded(source: String)

var _settings: ConfigFile = ConfigFile.new()
var _dirty_settings: bool = false
var _save: Dictionary = {}
var _dirty_save: bool = false
var _meta: MetaConfig = null


func _ready() -> void:
	_meta = load("res://resources/config/meta.tres") as MetaConfig
	if _meta == null:
		push_error("[SaveManager] meta.tres missing — using script defaults.")
		_meta = MetaConfig.new()
	var err: Error = _settings.load(SETTINGS_PATH)
	if err != OK:
		_settings = ConfigFile.new()
		print("[SaveManager] No valid settings file (%s) — using defaults." % error_string(err))
	_load_save()


func meta_config() -> MetaConfig:
	return _meta


# --- settings.cfg (live settings, unchanged Phase 1 API) ------------------------

func get_setting(section: String, key: String, default: Variant = null) -> Variant:
	return _settings.get_value(section, key, default)


func set_setting(section: String, key: String, value: Variant) -> void:
	_settings.set_value(section, key, value)
	_dirty_settings = true
	_settings.save(SETTINGS_PATH)
	_dirty_settings = false


func has_setting(section: String, key: String) -> bool:
	return _settings.has_section_key(section, key)


# --- save.json: load / validate / migrate ---------------------------------------

func _defaults() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"ftue_done": false,
		"wallet": {"coins": 0, "lifetime_earned": 0, "xp": 0},
		"skins": {"owned": ["classic"], "equipped": "classic"},
		"missions": {"date": "", "rerolled": false, "entries": []},
		"high_scores": [],
		"stats": {"runs": 0, "best_score": 0.0, "kills": 0, "total_score": 0.0},
	}


## Reads save.json with validation. Test hook: `force_default` skips disk.
func _load_save(force_default: bool = false) -> void:
	_save = _defaults()
	if force_default:
		return
	if not FileAccess.file_exists(SAVE_PATH):
		_migrate_from_settings()
		save_save()
		return
	var raw: String = FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null or not (parsed is Dictionary):
		_quarantine("save.json is not valid JSON")
		return
	var data: Dictionary = parsed
	var stored: int = int(data.get("checksum", 0))
	data.erase("checksum")
	if stored != _checksum(data):
		_quarantine("checksum mismatch (stored=%d computed=%d)" % [stored, _checksum(data)])
		return
	if int(data.get("save_version", 0)) > SAVE_VERSION:
		_quarantine("save from a NEWER version — refusing to guess")
		return
	_save = _apply_migrations(data)
	_fill_missing(_save)
	save_loaded.emit("disk")


## Bumps old versions forward. v0 → v1: pre-release saves without a version
## stamp get the full default skeleton (nothing worth preserving existed).
func _apply_migrations(data: Dictionary) -> Dictionary:
	var v: int = int(data.get("save_version", 0))
	while v < SAVE_VERSION:
		match v:
			0:
				var fresh: Dictionary = _defaults()
				# Keep anything recognisable from the pre-version payload.
				for key in ["wallet", "skins", "missions", "high_scores", "stats", "ftue_done"]:
					if data.has(key):
						fresh[key] = data[key]
				data = fresh
				v = 1
			_:
				push_warning("[SaveManager] Unknown save version %d — defaults." % v)
				return _defaults()
	data["save_version"] = SAVE_VERSION
	return data


## Top-up any keys a migration may have missed (defensive, recursive-flat).
func _fill_missing(data: Dictionary) -> void:
	var def: Dictionary = _defaults()
	for key in def:
		if not data.has(key):
			data[key] = def[key]
		elif def[key] is Dictionary and data[key] is Dictionary:
			for sub in def[key]:
				if not (data[key] as Dictionary).has(sub):
					(data[key] as Dictionary)[sub] = def[key][sub]


## Decision #58 made this promise: the Phase 8 interim keys in settings.cfg
## migrate into save.json the first time save.json does not exist.
func _migrate_from_settings() -> void:
	if has_setting("ftue", "completed"):
		_save["ftue_done"] = bool(get_setting("ftue", "completed", false))
	if has_setting("progress", "best_score"):
		var best: float = float(get_setting("progress", "best_score", 0.0))
		_save["stats"]["best_score"] = best
		if best > 0.0:
			(_save["high_scores"] as Array).append(
				{"score": best, "date": Time.get_date_string_from_system(true), "skin": "classic"})


func _quarantine(why: String) -> void:
	# Keep the evidence, load defaults, NEVER crash (§16).
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(SAVE_CORRUPT_PATH):
			dir.remove(SAVE_CORRUPT_PATH)
		dir.rename(SAVE_PATH, SAVE_CORRUPT_PATH)
	push_warning("[SaveManager] save.json corrupt (%s) — quarantined, defaults loaded." % why)
	Analytics.track(&"save_corrupt", {"reason": why})
	_save = _defaults()


## Deterministic checksum: djb2 String.hash() over canonical (sorted-key) JSON.
func _checksum(payload: Dictionary) -> int:
	return JSON.stringify(payload, "", true).hash()


## Atomic write: tmp + rename (a crash mid-write cannot destroy the old save).
## The checksum is computed over the PARSE-NORMALIZED payload: Godot's JSON
## parses every number as float, so an int 77 on the write side must be
## canonicalized (77.0) before hashing — else read-back never matches.
func save_save() -> void:
	var body: String = JSON.stringify(_save.duplicate(true), "", true)
	var normalized: Variant = JSON.parse_string(body)
	if not (normalized is Dictionary):
		push_warning("[SaveManager] save payload failed normalization — keeping previous file.")
		return
	var to_write: Dictionary = (normalized as Dictionary).duplicate(true)
	to_write["checksum"] = JSON.stringify(normalized, "", true).hash()
	var f: FileAccess = FileAccess.open(SAVE_TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[SaveManager] cannot open save tmp: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(to_write, "\t", true))
	f.close()
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	if FileAccess.file_exists(SAVE_PATH):
		dir.remove(SAVE_PATH)
	dir.rename(SAVE_TMP_PATH, SAVE_PATH)


## CC_UI_VERIFY hook: simulate a fresh install (in-memory only; the caller
## deletes the files on disk).
func reset_for_verify() -> void:
	_load_save(true)


# --- wallet (§16) ----------------------------------------------------------------

func get_coins() -> int:
	return int(_save["wallet"]["coins"])


func get_lifetime_coins() -> int:
	return int(_save["wallet"]["lifetime_earned"])


func add_coins(amount: int, reason: StringName) -> void:
	if amount == 0:
		return
	_save["wallet"]["coins"] = get_coins() + amount
	_save["wallet"]["lifetime_earned"] = get_lifetime_coins() + maxi(0, amount)
	save_save()
	EventBus.coins_changed.emit(get_coins())
	Analytics.track(&"coins_earned" if amount > 0 else &"coins_spent",
		{"amount": amount, "reason": String(reason), "balance": get_coins()})


## False (and no change) if the balance is insufficient.
func try_spend(amount: int, reason: StringName) -> bool:
	if amount < 0 or get_coins() < amount:
		return false
	_save["wallet"]["coins"] = get_coins() - amount
	save_save()
	EventBus.coins_changed.emit(get_coins())
	Analytics.track(&"coins_spent", {"amount": amount, "reason": String(reason), "balance": get_coins()})
	return true


# --- XP / level (§16) --------------------------------------------------------------

func get_xp() -> int:
	return int(_save["wallet"]["xp"])


func get_level() -> int:
	return MetaConfig.level_for_xp(_meta, get_xp())


## XP into the current level and the span of that level (progress bar).
func get_level_progress() -> Vector2i:
	var lvl: int = get_level()
	var lo: int = MetaConfig.xp_needed_cumulative(_meta, lvl)
	var hi: int = MetaConfig.xp_needed_cumulative(_meta, lvl + 1)
	return Vector2i(get_xp() - lo, maxi(1, hi - lo))


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	var before: int = get_level()
	_save["wallet"]["xp"] = get_xp() + amount
	var after: int = get_level()
	save_save()
	for l in range(before + 1, after + 1):
		add_coins(_meta.level_up_coin_bonus, &"level_up")
		EventBus.level_up.emit(l)
		Analytics.track(&"level_up", {"level": l})


# --- skins (§16) --------------------------------------------------------------------

func get_owned_skins() -> Array:
	return _save["skins"]["owned"] as Array


func own_skin(skin_id: String) -> void:
	if not get_owned_skins().has(skin_id):
		get_owned_skins().append(skin_id)
		save_save()


func get_equipped_skin() -> String:
	return str(_save["skins"]["equipped"])


func set_equipped_skin(skin_id: String) -> void:
	_save["skins"]["equipped"] = skin_id
	save_save()
	EventBus.skin_changed.emit(StringName(skin_id))


# --- missions (§16) -------------------------------------------------------------------

func get_mission_state() -> Dictionary:
	return _save["missions"] as Dictionary


func set_mission_state(state: Dictionary) -> void:
	_save["missions"] = state
	save_save()


# --- high scores + stats (§16/§17) ------------------------------------------------------

## Returns true if this score is the new all-time best.
func submit_high_score(score: float, skin_id: String) -> bool:
	var entries: Array = _save["high_scores"] as Array
	entries.append({
		"score": score,
		"date": Time.get_date_string_from_system(true),
		"skin": skin_id,
	})
	entries.sort_custom(func(a, b) -> bool: return float(a["score"]) > float(b["score"]))
	if entries.size() > _meta.high_score_cap:
		entries.resize(_meta.high_score_cap)
	var new_best: bool = score > float(_save["stats"]["best_score"]) and score > 0.0
	_save["stats"]["best_score"] = maxf(float(_save["stats"]["best_score"]), score)
	save_save()
	return new_best


func get_high_scores() -> Array:
	return _save["high_scores"] as Array


func get_best_score() -> float:
	return float(_save["stats"]["best_score"])


func record_run_finished(score: float, kills: int) -> void:
	_save["stats"]["runs"] = int(_save["stats"]["runs"]) + 1
	_save["stats"]["kills"] = int(_save["stats"]["kills"]) + kills
	_save["stats"]["total_score"] = float(_save["stats"]["total_score"]) + score
	save_save()


# --- FTUE (§13.4; source of truth moved settings.cfg → save.json, #58) ------------------

func is_ftue_done() -> bool:
	return bool(_save["ftue_done"])


func set_ftue_done() -> void:
	if not is_ftue_done():
		_save["ftue_done"] = true
		save_save()
