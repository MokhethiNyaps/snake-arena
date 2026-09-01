class_name AIStateMachine
extends RefCounted
## §8.2 Layer 1 — The FSM. States are separate scripts (scripts/ai/states/);
## each decision tick the machine evaluates the strict override chain
## top-down and picks the highest-priority state whose trigger holds.
##
## Priority order (§8.2): AVOID_WALL > AVOID_BODY > FLEE > HUNT >
## SCAVENGE > COLLECT > RECOVER > WANDER.
##
## Owns: the state list and the pick logic. No memory beyond that.
## Does NOT own: waypoints/timers (AIController), steering (ContextSteering).
## Talks to: AIController only.

var states: Array[AIState] = []
var current: AIState = null


func _init() -> void:
	states = [
		AIStateAvoidWall.new(),
		AIStateAvoidBody.new(),
		AIStateFlee.new(),
		AIStateHunt.new(),
		AIStateScavenge.new(),
		AIStateCollect.new(),
		AIStateRecover.new(),
		AIStateWander.new(),
	]
	states.sort_custom(func(a: AIState, b: AIState) -> bool: return a.priority < b.priority)
	current = states[states.size() - 1]  # WANDER default


## Evaluates the priority chain against `ctx`; returns the winning state
## (WANDER always accepts, so this never returns null).
func pick(ctx: Dictionary) -> AIState:
	var next_state: AIState = null
	for s in states:
		if s.can_enter(ctx):
			next_state = s
			break
	if next_state == null:
		next_state = states[states.size() - 1]
	if next_state != current:
		current = next_state
		current.on_enter(ctx)
	return current


func current_name() -> StringName:
	return current.state_name if current != null else &"NONE"
