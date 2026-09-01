class_name AIStateAvoidBody
extends AIState
## Second-priority state (§8.2): the probe ahead hits another snake's body
## within 1.0 s of travel — steer to the side with more open space.

func _init() -> void:
	state_name = &"AVOID_BODY"
	priority = 1


func can_enter(ctx: Dictionary) -> bool:
	return not (ctx["body_hit"] as Array).is_empty()


func interest_dir(ctx: Dictionary) -> Vector3:
	# Probe left and right of the current heading; pick the side whose
	# probes found fewer hits (more open space).
	var me_pos: Vector3 = ctx["me_pos"]
	var facing: Vector3 = ctx["me_facing"]
	var probe_dist: float = ctx["balance"].ai_probe_lookahead * float(ctx["me_speed"])
	var left: Vector3 = _side(facing, 1.0)
	var right: Vector3 = _side(facing, -1.0)
	var left_clear: float = _side_clearance(ctx, me_pos, left, probe_dist)
	var right_clear: float = _side_clearance(ctx, me_pos, right, probe_dist)
	var side: Vector3 = left if left_clear >= right_clear else right
	return facing + side * 1.5


func dangers(ctx: Dictionary) -> Array:
	return ctx["body_hit"]


func boost_wanted(_ctx: Dictionary) -> bool:
	return false


func _side(forward: Vector3, sign: float) -> Vector3:
	return Vector3(forward.z * sign, 0.0, -forward.x * sign).normalized()


## Rough clearance: distance to the nearest body_hit probe along `dir`.
func _side_clearance(ctx: Dictionary, me_pos: Vector3, dir: Vector3, probe_dist: float) -> float:
	var best: float = probe_dist
	for hit in ctx["body_hit"]:
		var to_hit: Vector3 = (hit["pos"] as Vector3) - me_pos
		var along: float = to_hit.dot(dir)
		if along > 0.0:
			best = minf(best, along)
	return best
