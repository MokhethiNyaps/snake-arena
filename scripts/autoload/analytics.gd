extends Node
## AUTOLOAD #5 — Analytics (§45.10). track() events with a backend seam.
##
## Owns: the event funnel. Phase 1: console backend prints events to stdout
##        (headless-visible); a Null backend is trivially achievable by
##        setting `enabled = false`.
## Does NOT own: gameplay logic; systems only report through track().
## Talks to: every system that emits events. Phase 11: GameAnalytics/Firebase
##           seam (human supplies keys — docs/HUMAN_TASKS.md Part B #22).

var enabled: bool = true
var backend_id: String = "console"


## Event funnel entry point. props must be JSON-serializable primitives.
var _session_start: int = 0
var _session_runs: int = 0
var _session_ads: int = 0


func _ready() -> void:
	_session_start = Time.get_ticks_msec()
	track(&"app_open", {"version": ProjectSettings.get_setting("application/config/version", "dev")})
	EventBus.run_started.connect(func() -> void: _session_runs += 1)
	EventBus.settings_changed.connect(func(section: String, key: String) -> void:
		track(&"settings_changed", {"section": section, "key": key}))


func ftue_step(index: int) -> void:
	track(&"ftue_step", {"step": index})


func _exit_tree() -> void:
	track(&"session_end", {
		"duration_s": float(Time.get_ticks_msec() - _session_start) / 1000.0,
		"runs": _session_runs,
		"ads_shown": _session_ads,
	})


func track(event: StringName, props: Dictionary = {}) -> void:
	if event == &"ad_shown":
		_session_ads += 1
	if not enabled:
		return
	print("[Analytics] %s %s" % [event, JSON.stringify(props)])
