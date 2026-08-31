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
func track(event: StringName, props: Dictionary = {}) -> void:
	if not enabled:
		return
	print("[Analytics] %s %s" % [event, JSON.stringify(props)])
