extends Node
## AUTOLOAD #2 — SaveManager (§22). Loads BEFORE anything reads settings.
##
## Owns: user:// persistence. Phase 1: settings.cfg only (with defaults and
##        corruption-tolerant load). Phase 9 adds save.json (versioned,
##        checksummed) — that design is anticipated here, not implemented.
## Does NOT own: what the data means; consumers interpret it.
## Talks to: Settings UI, SkinManager, MissionManager, Analytics.

const SETTINGS_PATH: String = "user://settings.cfg"

var _settings: ConfigFile = ConfigFile.new()
var _dirty: bool = false


func _ready() -> void:
	var err: Error = _settings.load(SETTINGS_PATH)
	if err != OK:
		# Missing or corrupt settings file: fall back to defaults gracefully.
		# (Phase 9 extends this with the checksummed save.json path.)
		_settings = ConfigFile.new()
		print("[SaveManager] No valid settings file (%s) — using defaults." % error_string(err))


## Typed read with fallback default.
func get_setting(section: String, key: String, default: Variant = null) -> Variant:
	return _settings.get_value(section, key, default)


## Write-through setting: applies immediately and persists.
func set_setting(section: String, key: String, value: Variant) -> void:
	_settings.set_value(section, key, value)
	_dirty = true
	save_now()


func has_setting(section: String, key: String) -> bool:
	return _settings.has_section_key(section, key)


func save_now() -> void:
	if not _dirty:
		return
	var err: Error = _settings.save(SETTINGS_PATH)
	if err != OK:
		push_warning("[SaveManager] Failed to save settings: %s" % error_string(err))
	else:
		_dirty = false
