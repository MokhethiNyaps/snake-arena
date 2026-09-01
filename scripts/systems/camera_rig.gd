class_name CameraRig
extends Node3D
## §5 — The camera rig. The Camera3D is a CHILD and is never moved directly;
## this rig owns all positioning: damped follow, power-based distance/pitch,
## look-ahead, boost FOV, and trauma-based shake.
##
## Owns: the rig transform and the camera's FOV.
## Does NOT own: the camera's render settings; nothing else.
## Talks to: SnakeController (target) — read-only; Settings (shake toggle).

@onready var cam: Camera3D = $Camera3D

@export var profile: CameraProfile

var target: SnakeController = null

var _pos: Vector3 = Vector3.ZERO
var _dist: float = 0.0
var _pitch_deg: float = 0.0
var _yaw_deg: float = 0.0
var _fov: float = 55.0
var _trauma: float = 0.0
var _noise_t: float = 0.0


func _ready() -> void:
	if profile == null:
		profile = load("res://resources/config/camera_default.tres")
	if target != null:
		_snap_to_target()
	_pitch_deg = profile.pitch_start_deg
	_fov = profile.fov_base
	cam.make_current()


func set_target(snake: SnakeController) -> void:
	target = snake
	_snap_to_target()


func _snap_to_target() -> void:
	if target == null:
		return
	_yaw_deg = _camera_yaw_for(target.facing_angle_deg)
	_pitch_deg = profile.pitch_start_deg
	_dist = _desired_distance()
	_pos = target.head_position()
	_apply_transform()


## Convention bridge: the snake's facing angle (0 = +Z, positive = toward +X)
## and Godot's camera yaw (0 = -Z, positive = toward -X) differ by 180°.
## camera_yaw = facing + 180 (verified against look_at semantics).
func _camera_yaw_for(facing_deg: float) -> float:
	return MathUtil.normalize_angle_deg(facing_deg + 180.0)


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Settings hook: 0 = shake fully disabled (§5 accessibility).
func set_shake_intensity(value: float) -> void:
	if profile != null:
		profile.shake_intensity = clampf(value, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	# Trauma decays first (§5).
	_trauma = maxf(0.0, _trauma - profile.trauma_decay * delta)
	# Desired framing values.
	var desired_pitch: float = _desired_pitch()
	var desired_dist: float = _desired_distance()
	var desired_pos: Vector3 = _desired_focus_pos()
	# Critically-damped springs (frame-rate independent, §5).
	_pitch_deg = Smoothing.damp(_pitch_deg, desired_pitch, profile.smoothing_half_life, delta)
	_dist = Smoothing.damp(_dist, desired_dist, profile.smoothing_half_life, delta)
	_yaw_deg = Smoothing.damp_angle_deg(_yaw_deg, _camera_yaw_for(target.facing_angle_deg), profile.smoothing_half_life, delta)
	_pos = Smoothing.damp_vector(_pos, desired_pos, profile.smoothing_half_life, delta)
	# FOV: grow with distance (arcade feel) + boost kick.
	var target_fov: float = profile.fov_base + (profile.fov_max - profile.fov_base) * clampf((_dist - profile.dist_min) / (profile.dist_max - profile.dist_min), 0.0, 1.0)
	if target.boosting:
		target_fov += profile.fov_boost_add
	_fov = Smoothing.damp(_fov, target_fov, 0.2, delta)
	cam.fov = _fov
	_apply_transform()


## Camera target = head + velocity_dir * lookahead (§5), reduced 40% while
## boosting so the player keeps their own head on screen.
func _desired_focus_pos() -> Vector3:
	var lookahead: float = profile.lookahead_base + target.current_speed * profile.lookahead_speed_factor
	if target.boosting:
		lookahead *= profile.lookahead_boost_scale
	return target.head_position() + target.head_forward() * lookahead


func _desired_pitch() -> float:
	var t: float = clampf((target.power - 2.0) / 800.0, 0.0, 1.0)
	return lerpf(profile.pitch_start_deg, profile.pitch_max_deg, t)


func _desired_distance() -> float:
	var dist: float = profile.dist_base + profile.dist_power * pow(maxf(1.0, target.power), profile.dist_exponent)
	dist = clampf(dist, profile.dist_min, profile.dist_max)
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		dist *= profile.mobile_multiplier
	return dist


## Rig sits at pitch/distance behind the (damped) focus position, offset by
## trauma shake, looking at the focus.
func _apply_transform() -> void:
	var shake_offset: Vector3 = Vector3.ZERO
	var shake_roll: float = 0.0
	if profile.shake_intensity > 0.0 and _trauma > 0.0:
		_noise_t += 0.05
		var s: float = _trauma * _trauma * profile.shake_intensity
		shake_offset = Vector3(
			randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * profile.shake_max_offset * s
		shake_roll = randf_range(-1.0, 1.0) * profile.shake_max_angle_deg * s
	var yaw_rad: float = deg_to_rad(_yaw_deg)
	var pitch_rad: float = deg_to_rad(_pitch_deg)
	# Camera look direction (its -Z) has horizontal component
	# (-sin yaw, -cos yaw); behind the focus = the opposite horizontal.
	var back: Vector3 = Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))
	global_position = _pos + back * _dist + Vector3.UP * (_dist * tan(-pitch_rad))
	global_position += shake_offset
	global_rotation_degrees = Vector3(_pitch_deg, _yaw_deg, shake_roll)
