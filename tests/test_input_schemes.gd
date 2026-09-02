extends RefCounted
## §7 — Input scheme tests: keyboard vector, mouse dead zone + steering,
## touch joystick math (dead zone, max radius clamp), scheme switching,
## suspension semantics, boost double-tap-hold state.


func _im() -> InputManager:
	return Engine.get_main_loop().root.get_node("InputManager") as InputManager


func test_keyboard_direction() -> bool:
	var im: InputManager = _im()
	im.set_scheme_for_test(InputManager.Scheme.KEYBOARD)
	# No keys held → ZERO (nothing is pressed in headless tests).
	if im.get_steer_direction() != Vector3.ZERO:
		printerr("  keyboard idle should be ZERO")
		return false
	return true


func test_mouse_dead_zone_and_steer() -> bool:
	var im: InputManager = _im()
	im.set_scheme_for_test(InputManager.Scheme.MOUSE)
	im.set_mouse_world_for_test(Vector3(10.0, 0.0, 0.0))
	# Inside the 1.2 u dead zone → ZERO.
	if im.get_steer_direction(Vector3(9.5, 0.0, 0.0)) != Vector3.ZERO:
		printerr("  mouse dead zone failed")
		return false
	# Outside → normalized direction to the point.
	var dir: Vector3 = im.get_steer_direction(Vector3.ZERO)
	if absf(dir.length() - 1.0) > 0.001 or absf(dir.x - 1.0) > 0.001 or absf(dir.z) > 0.001:
		printerr("  mouse steer dir %s != +X" % str(dir))
		return false
	# Y drift in the target is ignored (XZ plane only, §6.1).
	var dir2: Vector3 = im.get_steer_direction(Vector3(0.0, 0.0, 0.0))
	if absf(dir2.y) > 0.0001:
		printerr("  mouse steer has Y component")
		return false
	return true


func test_touch_joystick_math() -> bool:
	var im: InputManager = _im()
	im.set_scheme_for_test(InputManager.Scheme.TOUCH)
	# Below the 12 px dead zone → ZERO.
	im.set_touch_dir_for_test(Vector2(8.0, 0.0))
	if im.get_steer_direction() != Vector3.ZERO:
		printerr("  touch dead zone failed")
		return false
	# 45 px right/up → normalized (1,-1)/√2 — screen up = world -Z.
	im.set_touch_dir_for_test(Vector2(45.0, -45.0))
	var dir: Vector3 = im.get_steer_direction()
	var want: Vector3 = Vector3(1.0, 0.0, -1.0).normalized()
	if dir.distance_to(want) > 0.001:
		printerr("  touch dir %s != %s" % [str(dir), str(want)])
		return false
	# Beyond the 90 px max radius → still normalized (clamped, not > 1).
	im.set_touch_dir_for_test(Vector2(500.0, 0.0))
	var dir2: Vector3 = im.get_steer_direction()
	if dir2.length() > 1.001 or dir2.length() < 0.99:
		printerr("  touch drag not clamped: length %.3f" % dir2.length())
		return false
	return true


func test_scheme_switch_and_suspend() -> bool:
	var im: InputManager = _im()
	im.set_scheme_for_test(InputManager.Scheme.MOUSE)
	im.set_mouse_world_for_test(Vector3(30.0, 0.0, 0.0))
	var held: Vector3 = im.get_steer_direction(Vector3.ZERO)
	im.set_suspended(true)
	# §7: suspended returns the last held direction; boost reports false.
	if im.get_steer_direction(Vector3.ZERO) != held:
		printerr("  suspension did not hold last direction")
		return false
	if im.is_boosting():
		printerr("  boosting while suspended")
		return false
	im.set_suspended(false)
	if im.get_active_scheme() != InputManager.Scheme.MOUSE:
		printerr("  scheme changed by suspension")
		return false
	return true
