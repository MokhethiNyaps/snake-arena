class_name AIStateScavenge
extends AIState
## §8.2 — Corpse motes within 40 units: rush the best cluster. (Death-event
## motes arrive in Phase 6; boost-shed motes already feed this state.)

func _init() -> void:
	state_name = &"SCAVENGE"
	priority = 4


func can_enter(ctx: Dictionary) -> bool:
	return not (ctx["motes"] as Array).is_empty()


func interest_dir(ctx: Dictionary) -> Vector3:
	var me_pos: Vector3 = ctx["me_pos"]
	var motes: Array = ctx["motes"]
	# Centroid of the top-3 motes near the strongest one.
	var best: Dictionary = motes[0]
	var centroid: Vector3 = best["pos"]
	var count: int = 1
	for i in range(1, mini(3, motes.size())):
		var m: Dictionary = motes[i]
		if (m["pos"] as Vector3).distance_to(best["pos"]) < 6.0:
			centroid += m["pos"]
			count += 1
	return centroid / float(count) - me_pos


func dangers(ctx: Dictionary) -> Array:
	var out: Array = []
	for t in ctx["threats"]:
		out.append({"pos": t["pos"], "radius": ctx["personality"].fear_radius, "weight": 1.0})
	return out


func boost_wanted(ctx: Dictionary) -> bool:
	return AIStateFlee._willing(ctx)
