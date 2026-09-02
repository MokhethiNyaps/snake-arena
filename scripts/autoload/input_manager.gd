extends Node
## AUTOLOAD #8 — InputManager (§7). The ONLY file allowed to touch Input.*.
##
## Schemes (all live, auto-detected on first input of each type — §7):
##   MOUSE    raycast through the cursor onto the Y=0 plane; steer toward
##            that world point; 1.2 u dead zone around the head. DEFAULT.
##   KEYBOARD WASD/arrows absolute direction vector.
##   TOUCH    dynamic virtual joystick: touch-down anywhere in the left 65%
##            of the screen plants the origin; drag steers (90 px max
##            radius, 12 px dead zone). Boost = double-tap-and-hold anywhere.
##   GAMEPAD  left stick steers; A/cross boosts (via the boost action).
##
## Owns: scheme detection, steering vector, boost edge signals, suspension,
##       the touch-joystick origin + drag state, the mouse world target.
## Does NOT own: game state; it only reports what the player is doing.
## Talks to: player/UI code via the API below, AdManager (§45.6 suspends).

enum Scheme { MOUSE, KEYBOARD, TOUCH, GAMEPAD }

signal boost_pressed
signal boost_released
signal scheme_changed(scheme: Scheme)

## §7 tunables (designer-facing values live here; §4 allows input-feel
## constants in code when they are engine-level, but they stay grouped).
const MOUSE_DEAD_ZONE_UNITS: float = 1.2
const JOYSTICK_MAX_RADIUS_PX: float = 90.0
const JOYSTICK_DEAD_ZONE_PX: float = 12.0
const TOUCH_AREA_FRACTION: float = 0.65
const DOUBLE_TAP_WINDOW_S: float = 0.3

var _active_scheme: Scheme = Scheme.MOUSE
var _suspended: bool = false
var _was_boosting: bool = false
var _last_direction: Vector3 = Vector3.ZERO

# Mouse state.
var _mouse_screen_pos: Vector2 = Vector2.INF
var _mouse_world_pos: Vector3 = Vector3.INF
# Touch joystick state.
var _touch_active: bool = false
var _touch_index: int = -1
var _touch_origin: Vector2 = Vector2.ZERO
var _touch_current: Vector2 = Vector2.ZERO
var _touch_dir: Vector2 = Vector2.ZERO
# Double-tap-and-hold boost.
var _last_tap_ms: int = -1000000
var _double_tap_holding: bool = false
var _double_tap_index: int = -1

var _ground_plane: Plane = Plane(Vector3.UP, 0.0)


func _ready() -> void:
	set_process(false)  # input is polled from gameplay ticks; no idle work


func _physics_process(_delta: float) -> void:
	# Boost edge detection → signals (gameplay never polls Input for boost).
	var boosting_now: bool = _is_boost_held()
	if boosting_now and not _was_boosting:
		boost_pressed.emit()
	elif not boosting_now and _was_boosting:
		boost_released.emit()
	_was_boosting = boosting_now


# --- input events (scheme auto-detect + state capture) ------------------------

## Raw capture lives in _input (not _unhandled_input): empirically, parsed
## InputEventMouseMotion events never reach _unhandled_input in 4.7 (the
## GUI layer consumes motion for hover), while _input receives everything.
## We never mark events handled, so GUI buttons still work normally.
func _input(event: InputEvent) -> void:
	# Touch-synthesized mouse events (emulate_mouse_from_touch, needed so
	# touchscreen taps drive GUI buttons) must NOT flip the scheme back to
	# MOUSE — the originating ScreenTouch already set TOUCH.
	if (event is InputEventMouseMotion or event is InputEventMouseButton) \
			and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		_set_scheme(Scheme.MOUSE)
		_mouse_screen_pos = event.position
		_update_mouse_world()
	elif event is InputEventMouseButton:
		_set_scheme(Scheme.MOUSE)
		_mouse_screen_pos = event.position
		_update_mouse_world()
		# LMB boost flows through the "boost" action (already mapped).
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.2:
			_set_scheme(Scheme.GAMEPAD)
	elif event is InputEventJoypadButton:
		_set_scheme(Scheme.GAMEPAD)
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			if key.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D] \
					or key.physical_keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
				_set_scheme(Scheme.KEYBOARD)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if not event.pressed:
		# Release: clear the joystick or the double-tap-hold boost.
		if event.index == _touch_index:
			_touch_active = false
			_touch_index = -1
			_touch_dir = Vector2.ZERO
		if event.index == _double_tap_index:
			_double_tap_holding = false
			_double_tap_index = -1
		return
	var on_left: bool = event.position.x < get_viewport().get_visible_rect().size.x * TOUCH_AREA_FRACTION
	# First finger in the steer area owns the joystick; §7 also allows
	# double-tap-and-hold ANYWHERE as boost — a double-tap in the steer
	# area still steers (the origin re-plants), which is the standard feel.
	var now_ms: int = Time.get_ticks_msec()
	if on_left and _touch_index == -1:
		_set_scheme(Scheme.TOUCH)
		_touch_active = true
		_touch_index = event.index
		_touch_origin = event.position
		_touch_current = event.position
		_touch_dir = Vector2.ZERO
	# Double-tap-and-hold → boost (any screen area).
	if now_ms - _last_tap_ms <= int(DOUBLE_TAP_WINDOW_S * 1000.0) and _double_tap_index == -1:
		_set_scheme(Scheme.TOUCH)
		_double_tap_holding = true
		_double_tap_index = event.index
		_last_tap_ms = -1000000
	else:
		_last_tap_ms = now_ms


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index == _touch_index:
		_touch_current = event.position
		var offset: Vector2 = _touch_current - _touch_origin
		if offset.length() < JOYSTICK_DEAD_ZONE_PX:
			_touch_dir = Vector2.ZERO
		else:
			var clamped: Vector2 = offset.limit_length(JOYSTICK_MAX_RADIUS_PX)
			_touch_dir = clamped / JOYSTICK_MAX_RADIUS_PX
		_set_scheme(Scheme.TOUCH)


func _set_scheme(scheme: Scheme) -> void:
	if _active_scheme == scheme:
		return
	_active_scheme = scheme
	scheme_changed.emit(scheme)


## Projects the mouse position onto the Y=0 plane through the active camera.
func _update_mouse_world() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var ray_from: Vector3 = cam.project_ray_origin(_mouse_screen_pos)
	var ray_dir: Vector3 = cam.project_ray_normal(_mouse_screen_pos)
	var hit: Variant = _ground_plane.intersects_ray(ray_from, ray_dir)
	if hit != null:
		_mouse_world_pos = hit


# --- §7 public API --------------------------------------------------------------

## Normalized XZ steer direction, or ZERO. When suspended, returns the last
## held direction (§7). `from_world_pos` anchors the mouse dead zone.
func get_steer_direction(from_world_pos: Vector3 = Vector3.ZERO) -> Vector3:
	if _suspended:
		return _last_direction
	var dir: Vector3 = Vector3.ZERO
	match _active_scheme:
		Scheme.MOUSE:
			if _mouse_world_pos != Vector3.INF:
				var to_mouse: Vector3 = _mouse_world_pos - from_world_pos
				to_mouse.y = 0.0
				if to_mouse.length() >= MOUSE_DEAD_ZONE_UNITS:
					dir = to_mouse.normalized()
		Scheme.TOUCH:
			if _touch_dir.length_squared() > 0.0001:
				# Screen up = world -Z, right = +X (matches keyboard mapping).
				dir = Vector3(_touch_dir.x, 0.0, _touch_dir.y).normalized()
		Scheme.GAMEPAD:
			var stick: Vector2 = Vector2(
				Input.get_joy_axis(0, JOY_AXIS_LEFT_X),
				Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
			if stick.length_squared() > 0.04:
				dir = Vector3(stick.x, 0.0, stick.y).normalized()
		Scheme.KEYBOARD:
			dir = _keyboard_direction()
	_last_direction = dir
	return dir


func _keyboard_direction() -> Vector3:
	var input_vec: Vector2 = Input.get_vector("steer_left", "steer_right", "steer_up", "steer_down")
	if input_vec.length_squared() < 0.0001:
		return Vector3.ZERO
	# Screen "up" (W) = world -Z. get_vector returns +y for steer_up.
	return Vector3(input_vec.x, 0.0, input_vec.y).normalized()


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


## True while input is centrally suspended (§7).
func is_suspended() -> bool:
	return _suspended


## Test/editor hook: force a scheme (auto-detect still runs on real input).
func set_scheme_for_test(scheme: Scheme) -> void:
	_active_scheme = scheme
	scheme_changed.emit(scheme)


## Test hook: inject a mouse world position (headless runs have no camera).
func set_mouse_world_for_test(pos: Vector3) -> void:
	_mouse_world_pos = pos


## Test hook: inject touch-joystick state (headless touch emulation).
func set_touch_dir_for_test(dir_px: Vector2) -> void:
	_touch_dir = dir_px / JOYSTICK_MAX_RADIUS_PX if dir_px.length() >= JOYSTICK_DEAD_ZONE_PX else Vector2.ZERO


## §20 — debug toggle edge (F3). Polled by the debug panel; keeps all
## Input.* access inside this file per §7.
func debug_toggle_pressed() -> bool:
	if _suspended:
		return false
	return Input.is_action_just_pressed("debug_toggle")


func _is_boost_held() -> bool:
	# LMB / Space / Shift / gamepad A via the action map, plus the §7 touch
	# double-tap-and-hold (the visible thumb button arrives with Phase 10's
	# control polish — the boost RING in the HUD already reads state).
	return Input.is_action_pressed("boost") or _double_tap_holding
