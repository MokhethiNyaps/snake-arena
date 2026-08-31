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
