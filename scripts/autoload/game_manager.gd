extends Node
## AUTOLOAD #10 — GameManager (§22). Owns the run lifecycle state machine:
## BOOT → MENU → LOADING → COUNTDOWN → PLAYING → PAUSED → DYING → GAME_OVER
## (+ PAUSED_FOR_AD, §45.6). Every other system REACTS via
## EventBus.game_state_changed; no system may change state except through
## request_state().
##
## Owns: the current state and transition validation. NOT the scene switching
##        itself (UIManager owns screens; Boot owns initial flow).
## Talks to: EventBus (emits game_state_changed).

enum State { BOOT, MENU, LOADING, COUNTDOWN, PLAYING, PAUSED, PAUSED_FOR_AD, DYING, GAME_OVER }

var current_state: State = State.BOOT

## Previous non-ad state, so PAUSED_FOR_AD can return to it (§45.6 step 7).
var _pre_ad_state: State = State.BOOT

## Valid transition table. Phase 1: matches the §22 flow; later phases keep
## this table authoritative.
const _VALID_TRANSITIONS: Dictionary = {
	State.BOOT: [State.MENU, State.LOADING],
	State.MENU: [State.LOADING, State.COUNTDOWN, State.PAUSED_FOR_AD],
	State.LOADING: [State.MENU, State.COUNTDOWN, State.PLAYING],
	State.COUNTDOWN: [State.PLAYING],
	State.PLAYING: [State.PAUSED, State.PAUSED_FOR_AD, State.DYING, State.GAME_OVER],
	State.PAUSED: [State.PLAYING, State.MENU, State.GAME_OVER],
	State.PAUSED_FOR_AD: [State.PLAYING, State.PAUSED, State.MENU, State.GAME_OVER],
	State.DYING: [State.GAME_OVER],
	State.GAME_OVER: [State.MENU, State.LOADING, State.PAUSED_FOR_AD, State.PLAYING],
}


func _ready() -> void:
	# Initial state; no transition event for the very first assignment.
	current_state = State.BOOT
	print("[GameManager] Initial state: %s" % State.keys()[current_state])


## The ONLY way to change game state. Returns false (and logs) on an
## invalid transition — callers must handle a refusal.
func request_state(new_state: State) -> bool:
	if new_state == current_state:
		return true
	var allowed: Array = _VALID_TRANSITIONS.get(current_state, [])
	if not allowed.has(new_state):
		push_warning("[GameManager] Refused transition %s -> %s" % [
			State.keys()[current_state], State.keys()[new_state]])
		return false
	var from_state: State = current_state
	current_state = new_state
	if new_state == State.PAUSED_FOR_AD:
		_pre_ad_state = from_state
	print("[GameManager] %s -> %s" % [State.keys()[from_state], State.keys()[new_state]])
	EventBus.game_state_changed.emit(from_state, new_state)
	return true


func is_in(asked: State) -> bool:
	return current_state == asked


func state_name() -> String:
	return State.keys()[current_state]
