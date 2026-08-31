class_name Smoothing
extends Object
## Frame-rate-independent exponential damping, as mandated by §5.
##
## Owns: the damp() math used by the camera rig (and anywhere else that must
##        not use `lerp(x, y, delta)`).
## Does NOT own: any node state; these are pure static functions.
## Talks to: camera code and other systems that import Smoothing.

## Steps `current` toward `target` with a critically-damped spring.
## `half_life` is the time in seconds to cover half the remaining distance.
## Result depends only on elapsed time, not on frame rate.
static func damp(current: float, target: float, half_life: float, delta: float) -> float:
	if half_life <= 0.0:
		return target
	return target + (current - target) * exp(-delta * (log(2.0) / half_life))


## Vector3 variant of [method damp].
static func damp_vector(current: Vector3, target: Vector3, half_life: float, delta: float) -> Vector3:
	if half_life <= 0.0:
		return target
	return target + (current - target) * exp(-delta * (log(2.0) / half_life))


## Angle (degrees) variant of [method damp], wrapping through the shortest arc.
static func damp_angle_deg(current: float, target: float, half_life: float, delta: float) -> float:
	if half_life <= 0.0:
		return target
	var delta_angle: float = MathUtil.angle_delta_deg(current, target)
	return MathUtil.normalize_angle_deg(current + delta_angle * (1.0 - exp(-delta * (log(2.0) / half_life))))
