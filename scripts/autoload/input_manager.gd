extends Node
## AUTOLOAD #8 — InputManager (§7). The ONLY file allowed to touch Input.*.
##
## Owns: scheme detection, steering vector, boost edge signals, suspension.
## Phase 1: keyboard scheme functional; mouse/touch/gamepad paths are stubs
##          to be completed in Phase 2/3. The public API is final — gameplay
##          code will never change shape when those land.
## Does NOT own: game state; it only reports what the player is doing.
## Talks to: player/UI code via the API below; AdManager suspends it (§45.6).

enum Scheme { MOUSE, KEYBOARD, TOUCH, GAMEPAD }

signal boost_pressed
signal boost_released
signal scheme_changed(scheme: Scheme)

var _active_scheme: Scheme = Scheme.KEYBOARD
var _suspended: bool = false
var _was_boosting: bool = false
var _last_direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	set_process(false)  # input is polled from gameplay ticks; no idle work yet


func _physics_process(_delta: float) -> void:
	# Boost edge detection → signals (gameplay never polls Input for boost).
	var boosting_now: bool = _is_boost_held()
	if boosting_now and not _was_boosting:
		boost_pressed.emit()
	elif not boosting_now and _was_boosting:
		boost_released.emit()
	_was_boosting = boosting_now


## §7 API — normalized XZ steer direction, or ZERO.
## Keyboard (Phase 1): WASD/arrows. Mouse/touch/gamepad fill this in later.
## When suspended, returns the last held direction (§7).
func get_steer_direction(_from_world_pos: Vector3 = Vector3.ZERO) -> Vector3:
	if _suspended:
		return _last_direction
	var input_vec: Vector2 = Input.get_vector("steer_left", "steer_right", "steer_up", "steer_down")
	if input_vec.length_squared() < 0.0001:
		_last_direction = Vector3.ZERO
		return Vector3.ZERO
	# Screen "up" (W) = world -Z. get_vector returns +y for steer_up.
	var dir: Vector3 = Vector3(input_vec.x, 0.0, input_vec.y).normalized()
	_last_direction = dir
	return dir


## §7 API — true while boost is held and input is not suspended.
func is_boosting() -> bool:
	if _suspended:
		return false
	return _is_boost_held()


func get_active_scheme() -> Scheme:
	return _active_scheme


## §7 API — central suspension (pause, game-over, and critically the ad layer).
func set_suspended(suspended: bool) -> void:
	if _suspended == suspended:
		return
	_suspended = suspended
	if suspended and _was_boosting:
		boost_released.emit()
		_was_boosting = false


## Test/editor hook: force a scheme (auto-detection lands in Phase 2).
func set_scheme_for_test(scheme: Scheme) -> void:
	_active_scheme = scheme
	scheme_changed.emit(scheme)


func _is_boost_held() -> bool:
	return Input.is_action_pressed("boost")
