class_name AIState
extends RefCounted
## §8.2 Layer 1 — Base class for the eight FSM states. Each state owns:
##   can_enter(ctx)   — its trigger condition
##   interest_dir(ctx)— where it wants to go (context steering input)
##   dangers(ctx)     — [{pos, radius, weight}] to avoid on the way
##   boost_wanted(ctx)— whether it wants boost this decision (roll happens
##                      in the controller against personality willingness)
##
## Context `ctx` is a Dictionary built fresh by AIController each decision:
##   me_pos, me_facing, me_speed, me_power, me_radius, peak_power
##   snakes:   [{pos, power, facing, speed, radius}] (all sensed snakes)
##   threats:  [{pos, power, ...}]  (power > mine * eat_power_ratio)
##   prey:     [{pos, power, ...}]  (power < mine / eat_power_ratio)
##   clusters: [{pos, power, score, count}]
##   motes:    [{pos, power}]
##   wall:     { center_dist, soft_inner, radius, predicted_out: bool }
##   body_hit: [{pos, radius, weight}] (probe results)
##   rng:      RandomNumberGenerator (shared, per-AI)
##   personality: AIPersonalityConfig
##   balance:  GameBalanceConfig
##
## Owns: its trigger + steering for one behaviour.
## Does NOT own: memory (waypoints/timers live in AIController), the
##               priority chain (AIStateMachine owns that).
## Talks to: nobody — pure functions of the context.

var state_name: StringName = &"AIState"
## Priority: LOWER number = higher priority (§8.2 chain).
var priority: int = 100


func can_enter(_ctx: Dictionary) -> bool:
	return false


func on_enter(_ctx: Dictionary) -> void:
	pass


func interest_dir(ctx: Dictionary) -> Vector3:
	return ctx["me_pos"] as Vector3


func dangers(_ctx: Dictionary) -> Array:
	return []


func boost_wanted(_ctx: Dictionary) -> bool:
	return false
