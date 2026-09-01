class_name AIStateRecover
extends AIState
## §8.2 — Just dropped below 40% of peak power (or a near-miss): play safe
## for `ai_recover_duration` seconds — collect only in quiet areas, no boost.

func _init() -> void:
	state_name = &"RECOVER"
	priority = 6


func can_enter(ctx: Dictionary) -> bool:
	# Triggered only while the recover timer is active (AIController sets it
	# when power < fraction * peak and peak > ai_recover_peak_min).
	return bool(ctx["recover_active"])


func interest_dir(ctx: Dictionary) -> Vector3:
	var me_pos: Vector3 = ctx["me_pos"]
	# Quiet area: the cluster with the fewest nearby snakes; else a
	# mid-radius ring point away from the strongest threat.
	var clusters: Array = ctx["clusters"]
	if not clusters.is_empty():
		var quiet: Dictionary = _quietest_cluster(ctx, clusters)
		return (quiet["pos"] as Vector3) - me_pos
	if not (ctx["threats"] as Array).is_empty():
		var strongest: Dictionary = ctx["threats"][0]
		for t in ctx["threats"]:
			if float(t["power"]) > float(strongest["power"]):
				strongest = t
		var away: Vector3 = me_pos - (strongest["pos"] as Vector3)
		away.y = 0.0
		if away.length_squared() > 0.001:
			return away.normalized() * 20.0
	# Edge-ish quiet ring, opposite the centre traffic.
	var ring: Vector3 = me_pos.normalized()
	return ring * ctx["balance"].arena_radius * 0.7 - me_pos


func dangers(ctx: Dictionary) -> Array:
	var out: Array = []
	for t in ctx["threats"]:
		out.append({"pos": t["pos"], "radius": ctx["personality"].fear_radius, "weight": 1.5})
	return out


func boost_wanted(_ctx: Dictionary) -> bool:
	return false


func _quietest_cluster(ctx: Dictionary, clusters: Array) -> Dictionary:
	var snakes: Array = ctx["snakes"]
	var best: Dictionary = clusters[0]
	var best_neighbors: int = 999
	for c in clusters:
		var neighbors: int = 0
		for s in snakes:
			if (s["pos"] as Vector3).distance_to(c["pos"]) < 15.0:
				neighbors += 1
		if neighbors < best_neighbors:
			best_neighbors = neighbors
			best = c
	return best
