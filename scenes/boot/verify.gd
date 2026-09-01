extends Node3D
## Phase 2 verification harness. Runs the REAL arena + player scenes and
## drives them with simulated input (Input.parse_input_event), asserting
## the phase's exit criteria and saving a screenshot.
##
## Run:  xvfb-run -a -s "-screen 0 1280x720x24" \
##         godot --path . --resolution 1280x720 res://scenes/boot/verify.tscn
## Headless assertions only (no screenshot): add --headless.
## Exit code: 0 = PASS, 1 = FAIL (with CC_VERIFY_FAIL reason printed).

var _arena: Node3D = null
var _player: Node3D = null
var _snake: SnakeController = null
var _rig: CameraRig = null
var _phase: int = 0
var _phase_frames: int = 0
var _heading_frames: int = 0
var _boost_frames: int = 0
var _boost_start_power: float = 0.0
var _start_pos: Vector3 = Vector3.ZERO
var _fail_reason: String = ""

var _max_frame_ms: float = 0.0
var _frame_samples: int = 0
var _frame_acc_ms: float = 0.0


func _ready() -> void:
	_build_world()


func _build_world() -> void:
	# Replicate the boot sequence: the PlayerController only drives the
	# snake while GameManager is PLAYING.
	GameManager.request_state(GameManager.State.LOADING)
	_arena = (load("res://scenes/arena/arena.tscn") as PackedScene).instantiate()
	add_child(_arena)
	_player = (load("res://scenes/player/player_snake.tscn") as PackedScene).instantiate()
	add_child(_player)
	_snake = _player.get_node("Snake")
	_rig = _player.get_node("CameraRig")
	_rig.set_target(_snake)
	GameManager.request_state(GameManager.State.PLAYING)
	# Player starts at origin; give the rig a frame to snap.
	print("CC_VERIFY_START")


var _finished: bool = false


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_phase_frames += 1
	# Frame-time budget sampling (sandbox llvmpipe numbers are NOT target
	# hardware — this is regression detection only).
	var frame_ms: float = delta * 1000.0
	_frame_acc_ms += frame_ms
	_frame_samples += 1
	_max_frame_ms = maxf(_max_frame_ms, frame_ms)
	match _phase:
		0:  # settle: 30 ticks (0.5 s)
			if _phase_frames >= 30:
				_enter_phase(1)
		1:  # drive right for 240 ticks (4 s), then release
			Input.parse_input_event(_key(KEY_D, true))
			_heading_frames += 1
			if _heading_frames >= 240:
				Input.parse_input_event(_key(KEY_D, false))
				_enter_phase(2)
		2:  # hold boost 90 ticks (1.5 s) — power must drain, boosting flag on
			# §3.4: boost is disallowed at power <= 4.0; the snake spawns at
			# 2.0, so simulate early growth first (as collectibles would).
			if _boost_frames == 0:
				_snake.add_power(10.0)
				_boost_start_power = _snake.power
			Input.parse_input_event(_key(KEY_SPACE, true))
			_boost_frames += 1
			if _snake != null and not _snake.boosting and _boost_frames > 10:
				_fail("boost did not engage (power=%.1f min=%.1f)" % [_snake.power, _snake.config.min_boost_power])
				return
			if _boost_frames >= 90:
				Input.parse_input_event(_key(KEY_SPACE, false))
				_enter_phase(3)
		3:  # settle after boost, then final checks
			if _phase_frames >= 30:
				_final_checks()


func _enter_phase(p: int) -> void:
	_phase = p
	_phase_frames = 0


func _key(key: int, pressed: bool) -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = pressed
	return ev


## The Phase 2 exit criteria, asserted on the live game.
func _final_checks() -> void:
	if _finished:
		return
	_finished = true
	# 1. Snake moved meaningfully while steering right.
	var moved: float = _snake.global_position.distance_to(Vector3.ZERO)
	if moved < 20.0:
		_fail("snake moved only %.1f units in ~6s (speed=%.2f)" % [moved, _snake.current_speed])
		return
	# 2. Boost drained power (risk loop live).
	if _snake.power >= _boost_start_power:
		_fail("boost did not drain power (%.1f vs start %.1f)" % [_snake.power, _boost_start_power])
		return
	# 3. Body follows: segment 0 trails the head by roughly one spacing.
	var head: Vector3 = _snake.global_position
	var seg0: Vector3 = _snake.get_history().read_at_arc(
		_snake.get_history().newest_arc() - _snake.config.segment_spacing_radius_factor * _snake.current_radius, 0)
	var head_to_seg: float = head.distance_to(seg0)
	if head_to_seg < 0.1 or head_to_seg > 3.0:
		_fail("segment 0 not trailing head correctly (dist=%.2f)" % head_to_seg)
		return
	# 4. Camera: damped follow, distance in bounds, camera is current.
	var view_cam: Camera3D = get_viewport().get_camera_3d()
	if view_cam == null or view_cam != _rig.cam:
		_fail("camera rig camera is not current")
		return
	var cam_dist: float = _rig.global_position.distance_to(head)
	if cam_dist < 10.0 or cam_dist > 100.0:
		_fail("camera distance out of bounds: %.1f" % cam_dist)
		return
	# 5. Segment count follows the §3.2 formula (after boost drain, the
	# snake must have SHRUNK back toward the target for its current power).
	var expected_segs: int = _snake._segments_for_power(_snake.power)
	if _snake.get_segment_count() != expected_segs:
		_fail("segment count %d != expected %d at power %.1f" % [
			_snake.get_segment_count(), expected_segs, _snake.power])
		return
	# 6. Framing debug: where does the snake sit on screen? (kept as a
	# regression aid — the head must be inside the viewport, near centre).
	var view_cam2: Camera3D = get_viewport().get_camera_3d()
	var head_screen: Vector2 = view_cam2.unproject_position(_snake.head_position())
	var on_screen: bool = (
		head_screen.x > 0.0 and head_screen.x < float(view_cam2.get_viewport().get_visible_rect().size.x)
		and head_screen.y > 0.0 and head_screen.y < float(view_cam2.get_viewport().get_visible_rect().size.y)
		and not view_cam2.is_position_behind(_snake.head_position()))
	print("CC_VERIFY_FRAME head_screen=%s on_screen=%s rig_pos=%s rig_rot=%s cam_fwd=%s head=%s" % [
		head_screen, on_screen, _rig.global_position, _rig.global_rotation_degrees,
		-view_cam2.global_transform.basis.z, _snake.head_position()])
	if not on_screen:
		_fail("snake head is off-screen at %s" % head_screen)
		return
	# 7. Screenshot (skipped in headless mode — no renderer).
	if not DisplayServer.get_name() == "headless":
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(OS.get_environment("CC_SCREENSHOT") if OS.get_environment("CC_SCREENSHOT") != "" else "/tmp/cc_verify.png")
	_win()


func _win() -> void:
	print("CC_VERIFY_PASS moved=%.1f power=%.1f speed=%.2f segs=%d max_frame_ms=%.1f avg_frame_ms=%.1f" % [
		_snake.global_position.distance_to(Vector3.ZERO), _snake.power,
		_snake.current_speed, _snake.get_segment_count(), _max_frame_ms,
		_frame_acc_ms / maxf(1.0, float(_frame_samples))])
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("CC_VERIFY_FAIL " + reason)
	get_tree().quit(1)
