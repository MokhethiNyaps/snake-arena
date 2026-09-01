class_name AIStateFlee
extends AIState
## §8.2 — A bigger snake is within fear_radius: steer away from the
## strongest threat, blended toward open space (arena centre when cornered).

func _init() -> void:
	state_name = &"FLEE"
	priority = 2


func can_enter(ctx: Dictionary) -> bool:
	var threats: Array = ctx["threats"]
	if threats.is_empty():
		return false
	var me_pos: Vector3 = ctx["me_pos"]
	var fear: float = ctx["personality"].fear_radius
	for t in threats:
		if me_pos.distance_to(t["pos"]) <= fear:
			return true
	return false


func interest_dir(ctx: Dictionary) -> Vector3:
	var me_pos: Vector3 = ctx["me_pos"]
	var threats: Array = ctx["threats"]
	var strongest: Dictionary = threats[0]
	for t in threats:
		if float(t["power"]) > float(strongest["power"]):
			strongest = t
	var away: Vector3 = me_pos - (strongest["pos"] as Vector3)
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = ctx["me_facing"] as Vector3
	# Blend toward open space: the centre, weighted by how cornered we are.
	var centre: Vector3 = Vector3.ZERO - me_pos
	var centre_dist: float = centre.length()
	var max_r: float = ctx["balance"].arena_radius
	var cornered: float = clampf(1.0 - centre_dist / max_r, 0.0, 0.6)
	return away.normalized() * (1.0 - cornered) + centre.normalized() * cornered


func dangers(ctx: Dictionary) -> Array:
	var out: Array = []
	for t in ctx["threats"]:
		out.append({"pos": t["pos"], "radius": ctx["personality"].fear_radius, "weight": 1.5})
	return out


func boost_wanted(ctx: Dictionary) -> bool:
	return _willing(ctx)


static func _willing(ctx: Dictionary) -> bool:
	return (ctx["rng"] as RandomNumberGenerator).randf() < ctx["personality"].boost_willingness
