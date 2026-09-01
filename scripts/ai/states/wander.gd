class_name AIStateWander
extends AIState
## §8.2 — Nothing interesting nearby: drift toward a centre-biased random
## waypoint, re-picked every 3-6 s (the waypoint memory lives in
## AIController; this state just steers to it).

func _init() -> void:
	state_name = &"WANDER"
	priority = 7


func can_enter(_ctx: Dictionary) -> bool:
	return true


func interest_dir(ctx: Dictionary) -> Vector3:
	var me_pos: Vector3 = ctx["me_pos"]
	var waypoint: Vector3 = ctx["waypoint"]
	return waypoint - me_pos


func dangers(ctx: Dictionary) -> Array:
	var out: Array = []
	for t in ctx["threats"]:
		out.append({"pos": t["pos"], "radius": ctx["personality"].fear_radius, "weight": 0.6})
	return out


func boost_wanted(_ctx: Dictionary) -> bool:
	return false
