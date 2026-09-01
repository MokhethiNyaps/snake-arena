class_name AIStateCollect
extends AIState
## §8.2 — Collectibles within the sense radius: pathless steer to the
## best-scoring cluster (highest total power + score nearby).

const CLUSTER_RADIUS: float = 5.0


func _init() -> void:
	state_name = &"COLLECT"
	priority = 5


func can_enter(ctx: Dictionary) -> bool:
	return not (ctx["clusters"] as Array).is_empty()


func interest_dir(ctx: Dictionary) -> Vector3:
	var me_pos: Vector3 = ctx["me_pos"]
	var best: Dictionary = _best_cluster(ctx)
	return (best["pos"] as Vector3) - me_pos


func dangers(ctx: Dictionary) -> Array:
	var out: Array = []
	for t in ctx["threats"]:
		out.append({"pos": t["pos"], "radius": ctx["personality"].fear_radius, "weight": 0.8})
	return out


func boost_wanted(_ctx: Dictionary) -> bool:
	return false


func _best_cluster(ctx: Dictionary) -> Dictionary:
	var clusters: Array = ctx["clusters"]
	var best: Dictionary = clusters[0]
	var best_value: float = -1.0
	for c in clusters:
		var value: float = float(c["power"]) * 2.0 + float(c["score"]) * 0.05
		if value > best_value:
			best_value = value
			best = c
	return best
