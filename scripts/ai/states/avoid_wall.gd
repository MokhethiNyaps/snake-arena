class_name AIStateAvoidWall
extends AIState
## Highest-priority state (§8.2): inside the soft zone or predicted to be
## within 1.2 s — steer hard toward the arena centre.

func _init() -> void:
	state_name = &"AVOID_WALL"
	priority = 0


func can_enter(ctx: Dictionary) -> bool:
	var wall: Dictionary = ctx["wall"]
	if bool(wall["inside_soft"]):
		return true
	return bool(wall["predicted_out"])


func interest_dir(ctx: Dictionary) -> Vector3:
	var me_pos: Vector3 = ctx["me_pos"]
	return Vector3.ZERO - me_pos


func dangers(ctx: Dictionary) -> Array:
	# The wall itself repels: a danger at the point where the snake would
	# leave the safe zone, weighted by how imminent the exit is.
	var wall: Dictionary = ctx["wall"]
	var me_pos: Vector3 = ctx["me_pos"]
	var radius: float = ctx["balance"].arena_radius
	var outward: Vector3 = me_pos.normalized()
	if outward.length_squared() < 0.001:
		outward = Vector3.FORWARD
	var danger_pos: Vector3 = outward * radius
	var weight: float = 2.0 if bool(wall["inside_soft"]) else 1.2
	return [{"pos": danger_pos, "radius": radius, "weight": weight}]


func boost_wanted(_ctx: Dictionary) -> bool:
	return false
