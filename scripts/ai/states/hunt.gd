class_name AIStateHunt
extends AIState
## §8.2 — Edible prey within aggro_radius: aim at its PREDICTED position;
## with cutoff_skill, aim to cross ahead of it rather than chase the tail.

const LEAD_TIME: float = 0.35


func _init() -> void:
	state_name = &"HUNT"
	priority = 3


func can_enter(ctx: Dictionary) -> bool:
	var prey: Array = ctx["prey"]
	if prey.is_empty():
		return false
	var me_pos: Vector3 = ctx["me_pos"]
	var aggro: float = ctx["personality"].aggro_radius
	for p in prey:
		if me_pos.distance_to(p["pos"]) <= aggro:
			return true
	return false


func interest_dir(ctx: Dictionary) -> Vector3:
	var me_pos: Vector3 = ctx["me_pos"]
	var target: Dictionary = _pick_prey(ctx)
	var tpos: Vector3 = target["pos"]
	# Predicted position: lead the target by its velocity (facing * speed).
	var vel: Vector3 = Vector3(
		sin(deg_to_rad(float(target["facing"]))), 0.0,
		cos(deg_to_rad(float(target["facing"])))) * float(target["speed"])
	var predicted: Vector3 = tpos + vel * LEAD_TIME
	# Cutoff skill: aim ahead of the prey's path instead of chasing tail.
	var rng: RandomNumberGenerator = ctx["rng"]
	if rng.randf() < ctx["personality"].cutoff_skill:
		var tvel: Vector3 = vel.normalized() if vel.length_squared() > 0.001 else Vector3.FORWARD
		predicted = tpos + tvel * 6.0
	return predicted - me_pos


func dangers(ctx: Dictionary) -> Array:
	var out: Array = []
	# Threats (bigger snakes) remain dangerous while hunting.
	for t in ctx["threats"]:
		out.append({"pos": t["pos"], "radius": ctx["personality"].fear_radius, "weight": 1.0})
	return out


func boost_wanted(ctx: Dictionary) -> bool:
	return AIStateFlee._willing(ctx)


func _pick_prey(ctx: Dictionary) -> Dictionary:
	var me_pos: Vector3 = ctx["me_pos"]
	var best: Dictionary = {}
	var best_dist: float = INF
	for p in ctx["prey"]:
		var d: float = me_pos.distance_to(p["pos"])
		if d < best_dist:
			best_dist = d
			best = p
	return best
