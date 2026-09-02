extends Node
## AUTOLOAD #4 — RemoteConfig (§22/§45.10 seam). Config defaults come from
## .tres files; a fetched JSON may override individual keys at runtime.
##
## Owns: the override dictionary and typed accessors.
## Phase 1: overrides from JSON string only (no network fetch yet — Phase 11
##          adds the HTTP endpoint + cache).
## Does NOT own: the config .tres files themselves.
## Talks to: every system that reads tuning values (through the getters).

var _overrides: Dictionary = {}
const CACHE_PATH: String = "user://remote_cache.json"


func _ready() -> void:
	_apply_cache()
	var cfg: AdConfig = load("res://resources/config/ads.tres") as AdConfig
	if cfg != null and cfg.remote_config_url != "":
		fetch(cfg.remote_config_url)


## Cached overrides apply instantly at boot (offline-first); a successful
## network fetch refreshes the cache. Failures are SILENT by design —
## .tres defaults are always playable.
func fetch(url: String, timeout_s: float = 4.0) -> void:
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = timeout_s
	add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return
	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() < 3 or result[0] != HTTPRequest.RESULT_SUCCESS:
		return
	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	if apply_json(text):
		var f: FileAccess = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()


func _apply_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var text: String = FileAccess.get_file_as_string(CACHE_PATH)
	if not apply_json(text):
		DirAccess.remove_absolute(CACHE_PATH)  # poisoned cache — drop it



## Applies a JSON object of "section/key": value overrides.
## Returns false and keeps previous state on parse failure.
func apply_json(json_text: String) -> bool:
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[RemoteConfig] Ignoring invalid JSON override payload.")
		return false
	for key: String in parsed:
		_overrides[key] = parsed[key]
	print("[RemoteConfig] Applied %d overrides." % parsed.size())
	return true


func has_override(key: String) -> bool:
	return _overrides.has(key)


## Drops all overrides (back to .tres defaults).
func clear_overrides() -> void:
	_overrides.clear()


func get_float(key: String, default: float) -> float:
	return _overrides.get(key, default)


func get_int(key: String, default: int) -> int:
	return _overrides.get(key, default)


func get_bool(key: String, default: bool) -> bool:
	return _overrides.get(key, default)


func get_string(key: String, default: String) -> String:
	return _overrides.get(key, default)
