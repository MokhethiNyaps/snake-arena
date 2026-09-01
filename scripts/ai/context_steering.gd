class_name ContextSteering
extends RefCounted
## §8.2 Layer 2 — The shared context map that makes AI steering smooth and
## natural instead of jittery target-snapping. States produce a *desired*
## direction; this class weights it against dangers across a 16-direction
## context map and returns the best heading.
##
## Owns: the scoring math. Nothing else — no state, no memory.
## Does NOT own: which dangers/interest exist (the active AIState decides).
## Talks to: AIController only.

const DIR_COUNT: int = 16
## Heading continuity bonus (fights jitter between decisions).
const CONTINUITY_WEIGHT: float = 0.35
## How strongly a danger repels compared to interest attracting. Dangers
## must dominate interest (survival first): verified by test that a danger
## directly ahead flips the heading even with interest behind it.
const DANGER_WEIGHT: float = 1.8

## danger = { pos: Vector3, radius: float, weight: float }
## Returns a normalized XZ heading.
func pick(interest_dir: Vector3, dangers: Array, facing: Vector3) -> Vector3:
	var interest: Vector3 = _xz_normalized(interest_dir)
	var face: Vector3 = _xz_normalized(facing)
	var best_dir: Vector3 = face
	var best_score: float = -INF
	for i in DIR_COUNT:
		var ang: float = TAU * float(i) / float(DIR_COUNT)
		var dir: Vector3 = Vector3(cos(ang), 0.0, sin(ang))
		var score: float = 0.0
		if interest != Vector3.ZERO:
			score += dir.dot(interest)
		score += CONTINUITY_WEIGHT * dir.dot(face)
		for d in dangers:
			var dpos: Vector3 = d["pos"]
			var radius: float = d["radius"]
			var weight: float = d["weight"]
			if weight <= 0.0:
				continue
			var to_danger: Vector3 = dpos
			var dist: float = to_danger.length()
			if dist < 0.001:
				score -= weight * DANGER_WEIGHT
				continue
			var falloff: float = clampf(1.0 - dist / maxf(radius, 0.001), 0.0, 1.0)
			score -= dir.dot(to_danger / dist) * weight * DANGER_WEIGHT * falloff
		if score > best_score:
			best_score = score
			best_dir = dir
	return best_dir.normalized()


## XZ-normalized direction from any vector (zero stays zero).
func _xz_normalized(v: Vector3) -> Vector3:
	var flat: Vector3 = Vector3(v.x, 0.0, v.z)
	if flat.length_squared() < 0.000001:
		return Vector3.ZERO
	return flat.normalized()
