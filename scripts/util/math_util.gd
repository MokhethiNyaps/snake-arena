class_name MathUtil
extends Object
## Small shared math helpers for angles on the XZ plane.
##
## Owns: angle wrapping / shortest-arc math used by movement and steering.
## Does NOT own: game state.
## Talks to: anyone who imports MathUtil (no dependencies).

## Wraps an angle in degrees to [-180, 180).
static func normalize_angle_deg(angle_deg: float) -> float:
	var a: float = fmod(angle_deg, 360.0)
	if a >= 180.0:
		a -= 360.0
	elif a < -180.0:
		a += 360.0
	return a


## Signed shortest-arc distance in degrees from `from_deg` to `to_deg`
## (positive = turn counter-clockwise... in Godot's Y-up, positive = left).
static func angle_delta_deg(from_deg: float, to_deg: float) -> float:
	return normalize_angle_deg(to_deg - from_deg)


## Moves `current_deg` toward `target_deg` by at most `max_delta_deg` degrees,
## taking the shortest arc.
static func move_toward_angle_deg(current_deg: float, target_deg: float, max_delta_deg: float) -> float:
	var delta: float = angle_delta_deg(current_deg, target_deg)
	if absf(delta) <= max_delta_deg:
		return target_deg
	return current_deg + signf(delta) * max_delta_deg


## A vector direction (degrees) on the XZ plane from an XZ direction vector.
## 0 deg = +Z (toward -Z camera default "up-screen"), positive = toward +X.
static func xz_direction_to_angle_deg(dir: Vector3) -> float:
	if dir.length_squared() < 0.000001:
		return 0.0
	return rad_to_deg(atan2(dir.x, dir.z))


## XZ direction vector from an angle in degrees (see xz_direction_to_angle_deg).
static func angle_deg_to_xz_direction(angle_deg: float) -> Vector3:
	var rad: float = deg_to_rad(angle_deg)
	return Vector3(sin(rad), 0.0, cos(rad)).normalized()
