extends Node
## Phase 8 UI verify driver (CC_UI_VERIFY=1). Drives the REAL boot flow
## (fresh install → §13.4 straight-into-run FTUE → HUD → pause → death →
## game-over panel → mock-rewarded revive → second death (revive hidden) →
## main menu → PLAY → run 3) entirely with REAL input events (mouse clicks
## on buttons, keyboard pause). Prints CC_UI_* markers; exit 0 on
## CC_UI_VERIFY_PASS, 1 on CC_UI_VERIFY_FAIL. Screenshots each screen.
##
## Runs under: xvfb-run -a -s "-screen 0 1280x720x24" \
##   env CC_UI_VERIFY=1 godot --path . --resolution 1280x720
## Portrait pass: --resolution 720x1280 + CC_UI_STAGE=portrait.

const STEP_TIMEOUT_S: float = 25.0

var _director: Node = null
var _ads_seen: int = 0
var _phase_wall: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Fast, deterministic mock ads (§45.7 knobs).
	if AdManager.provider is AdProviderMock:
		var mock: AdProviderMock = AdManager.provider
		mock.auto_close_seconds = 1.0
		mock.latency_seconds = 0.1
		mock.forced_outcome = AdProviderMock.ForcedOutcome.COMPLETED
	AdManager.ad_finished.connect(func(_p: int, _r: AdResult) -> void: _ads_seen += 1)
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _sec(t: float) -> void:
	await get_tree().create_timer(t, true).timeout


func _wait_state(state: int, what: String) -> bool:
	_phase_wall = Time.get_ticks_msec()
	while GameManager.current_state != state:
		if Time.get_ticks_msec() - _phase_wall > STEP_TIMEOUT_S * 1000.0:
			return _fail("timeout waiting for %s (at %s)" % [what, GameManager.state_name()])
		await get_tree().process_frame
	return true


func _fail(reason: String) -> bool:
	print("CC_UI_VERIFY_FAIL %s" % reason)
	get_tree().quit(1)
	return false


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var dir: String = OS.get_environment("CC_UI_SHOTS")
	if dir == "":
		dir = "/tmp"
	img.save_png("%s/ui_%s.png" % [dir, name])
	print("CC_UI_SHOT %s" % name)


func _screen() -> Control:
	return UIManager.get_current_screen()


func _find_button(root: Node, btn_name: String) -> Button:
	if root == null:
		return null
	var b: Button = root.find_child(btn_name, true, false) as Button
	return b


## Emulated touchscreen tap at a screen point (real InputEventScreenTouch;
## GUI click synthesis comes from the engine's emulate_mouse_from_touch).
func _tap(screen_pos: Vector2) -> void:
	var down: InputEventScreenTouch = InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = screen_pos
	Input.parse_input_event(down)
	await _frames(2)
	var up: InputEventScreenTouch = InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = screen_pos
	Input.parse_input_event(up)
	await _frames(2)


func _click(b: Button) -> void:
	# Real mouse path: motion to the button centre, then press + release.
	var centre: Vector2 = b.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = centre
	motion.global_position = centre
	Input.parse_input_event(motion)
	await _frames(2)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = centre
	press.global_position = centre
	Input.parse_input_event(press)
	await _frames(2)
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = centre
	release.global_position = centre
	Input.parse_input_event(release)
	await _frames(3)


func _press_key(key: int) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var ev2: InputEventKey = InputEventKey.new()
	ev2.physical_keycode = key
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await _frames(3)


## Mirrors verify.gd's death scenario: shrink the player, grow one AI,
## teleport the head into its trail.
func _kill_player() -> void:
	var snake: SnakeController = _director._snake
	var arena: Node3D = _director._arena
	if snake.has_meta("invulnerable_until"):
		snake.remove_meta("invulnerable_until")
	Engine.time_scale = 1.0
	snake.power = 2.0
	snake._update_derived_stats()
	snake._sync_segment_target()
	var big: SnakeController = null
	for ai in arena.ai_director.ai_controllers:
		if ai.snake != null and ai.snake.alive:
			big = ai.snake
			break
	if big == null:
		_fail("no live AI to kill the player")
		return
	big.power = 120.0
	big._update_derived_stats()
	big._sync_segment_target()
	var trail: Array = []
	big.history.trail_samples(trail, 40)
	snake.global_position = trail[6]


func _run() -> void:
	await _frames(20)
	_director = get_tree().get_first_node_in_group("run_director")
	if _director == null:
		_fail("run_director missing")
		return
	# Combat is live (decision #47): god-mode the player for the whole
	# scenario EXCEPT the scripted deaths (removed in _kill_player).
	if _director._snake != null:
		_director._snake.set_meta("invulnerable_until", 1.0e9)
	if OS.get_environment("CC_UI_STAGE") == "portrait":
		await _stage_portrait()
		return
	await _stage_full_loop()


# --- landscape: the full §13.4 / §12 / §45.5 loop ------------------------------

func _stage_full_loop() -> void:
	# S1 — fresh install: straight into a run, FTUE hint 1 visible, NO ad.
	if not GameManager.is_in(GameManager.State.PLAYING):
		_fail("fresh install did not drop into a run (state=%s)" % GameManager.state_name())
		return
	var hud: Control = _director._hud
	if hud == null:
		_fail("HUD not pushed on first run")
		return
	await _frames(20)
	# Hint 1 shows at t=0 but fades after ~3.8 s; cold-start frame jitter
	# under xvfb can outrun card visibility, so assert the FTUE machinery
	# engaged (hint index >= 0 means hint 1 scheduled/shown).
	if hud._hint_index < 0 and not hud._hint_card.visible:
		_fail("FTUE never engaged (index=%d)" % hud._hint_index)
		return
	if _ads_seen > 0:
		_fail("an ad fired before/during the first run (§45.3 violation)")
		return
	print("CC_UI_FTUE hint1=%s" % hud._hint_card.visible)
	await _shot("01_ftue")
	# S2 — hint 2 arrives at ~4 s; then skip the FTUE tail (verified enough).
	await _sec(5.2)
	if hud._hint_index < 1:
		_fail("FTUE hint 2 never appeared (index=%d)" % hud._hint_index)
		return
	print("CC_UI_FTUE2 ok")
	# Combat is live (decision #47): god-mode the player until the scripted
	# deaths, so an unplanned AI kill can't break the scenario order.
	_director._snake.set_meta("invulnerable_until", 1.0e9)
	SaveManager.set_setting("ftue", "completed", true)
	# S3 — HUD live data: leaderboard rows filled, score label formats.
	if _director._arena.collectible_manager.non_mote_count() < 400:
		_fail("economy not populated (%d)" % _director._arena.collectible_manager.non_mote_count())
		return
	var score_before: float = _director._arena.score_manager.get_score()
	_director._arena.score_manager.add_score(1234.0)
	await _sec(0.3)
	# The label refreshes at 10 Hz vs the 60 Hz manager — allow 1 of lag.
	var label_val: int = int(hud._score_label.text.replace(",", ""))
	var manager_val: int = int(round(_director._arena.score_manager.get_score()))
	if absi(label_val - manager_val) > 1 or label_val <= int(score_before):
		_fail("score label not tracking (label=%d manager=%.0f before=%.0f)" % [
			label_val, _director._arena.score_manager.get_score(), score_before])
		return
	if hud._board_rows[0].text == "":
		_fail("leaderboard row 1 empty")
		return
	print("CC_UI_HUD score=%s board1='%s'" % [hud._score_label.text, hud._board_rows[0].text])
	await _shot("02_hud")
	# S3.5 — §7 mouse steering (default scheme): hold the cursor to the
	# RIGHT of the snake's screen position; the heading must swing toward
	# +X relative to the camera. Real mouse motion events, real camera ray.
	var cam: Camera3D = get_viewport().get_camera_3d()
	var head_screen: Vector2 = cam.unproject_position(_director._snake.global_position)
	var facing_before: float = _director._snake.facing_angle_deg
	var target_px: Vector2 = head_screen + Vector2(160.0, 0.0)
	var motion_ev: InputEventMouseMotion = InputEventMouseMotion.new()
	motion_ev.position = target_px
	motion_ev.global_position = target_px
	var head_t0: Vector3 = _director._snake.global_position
	var speed_t0: float = _director._snake.current_speed
	var ts0: float = Engine.time_scale
	Input.parse_input_event(motion_ev)
	await _sec(1.2)
	var facing_after: float = _director._snake.facing_angle_deg
	print("CC_UI_MOVE_DIAG moved=%.3f speed=%.2f time_scale=%.2f steer=%s suspended=%s state=%s" % [
		_director._snake.global_position.distance_to(head_t0), speed_t0, ts0,
		str(InputManager.get_steer_direction(_director._snake.global_position)),
		str(InputManager.is_suspended()), GameManager.state_name()])
	var delta_facing: float = fmod(facing_after - facing_before + 540.0, 360.0) - 180.0
	# Camera-relative +X maps to a world heading near 90° (+X); the turn-rate
	# limiter guarantees a bounded but non-trivial swing (> 25° in 1.2 s).
	if absf(delta_facing) < 25.0:
		print("CC_UI_MOUSE_DIAG scheme=%s mouse_screen=%s mouse_world=%s head=%s target_px=%s" % [
			InputManager.Scheme.keys()[InputManager.get_active_scheme()],
			str(InputManager._mouse_screen_pos), str(InputManager._mouse_world_pos),
			str(_director._snake.global_position), str(target_px)])
		_fail("mouse steering did not turn the snake (Δ%.1f°)" % delta_facing)
		return
	print("CC_UI_MOUSE_STEER ok Δ%.1f° scheme=%s" % [delta_facing, InputManager.get_active_scheme()])
	# S4 — pause toggle (P), screenshot, resume by click.
	await _press_key(KEY_P)
	if not GameManager.is_in(GameManager.State.PAUSED) or not get_tree().paused:
		_fail("pause did not engage (state=%s paused=%s)" % [GameManager.state_name(), get_tree().paused])
		return
	var resume_b: Button = _find_button(_screen(), "BtnResume")
	if resume_b == null:
		_fail("pause screen missing RESUME")
		return
	await _shot("03_pause")
	await _click(resume_b)
	if not GameManager.is_in(GameManager.State.PLAYING) or get_tree().paused:
		_fail("resume failed (state=%s paused=%s)" % [GameManager.state_name(), get_tree().paused])
		return
	print("CC_UI_PAUSE ok")
	# S5 — die → game-over panel (§12.2 layout + count-ups).
	_kill_player()
	await _wait_state(GameManager.State.GAME_OVER, "GAME_OVER")
	await _sec(0.8)
	var go: Control = _screen()
	if _find_button(go, "BtnPlayAgain") == null:
		_fail("game-over panel missing PLAY AGAIN")
		return
	var again: Button = _find_button(go, "BtnPlayAgain")
	if not again.visible or again.disabled:
		_fail("PLAY AGAIN is hidden or disabled (§12.2 forbids)")
		return
	var revive: Button = _find_button(go, "BtnRevive")
	if revive == null or not revive.visible:
		_fail("REVIVE button should be visible on run 1 with mock provider")
		return
	var score_l: Label = go.find_child("Valscore", true, false) as Label
	if score_l == null or score_l.text == "0":
		_fail("game-over score row missing/zero: '%s'" % (score_l.text if score_l else "null"))
		return
	print("CC_UI_GAMEOVER revive_visible=%s play_again_ok=%s score='%s'" % [revive.visible, not again.disabled, score_l.text])
	await _shot("04_game_over")
	# S6 — revive via mock rewarded ad (§45.5: 65% power, resume run).
	var death_power: float = _director._death_power
	await _click(revive)
	if not await _wait_state(GameManager.State.PLAYING, "PLAYING after revive"):
		return
	var revived_power: float = _director._snake.power
	if absf(revived_power - death_power * 0.65) > maxf(1.0, death_power * 0.1):
		_fail("revive power %.1f != ~65%% of %.1f" % [revived_power, death_power])
		return
	if not _director._snake.alive:
		_fail("revived snake not alive")
		return
	print("CC_UI_REVIVE ok power=%.1f (65%% of %.1f)" % [revived_power, death_power])
	await _shot("05_revived")
	# S7 — die again: REVIVE must now be hidden (max 1 per run).
	_kill_player()
	await _wait_state(GameManager.State.GAME_OVER, "GAME_OVER after 2nd death")
	await _sec(0.5)
	var revive2: Button = _find_button(_screen(), "BtnRevive")
	if revive2 != null and revive2.visible:
		_fail("REVIVE visible after the single allowed use")
		return
	print("CC_UI_REVIVE_CAPPED ok")
	# S8 — MAIN MENU → menu screen → PLAY → run 3 (INTER_RUN eligible).
	var menu_b: Button = _find_button(_screen(), "BtnGameOverMenu")
	if menu_b == null:
		_fail("game-over missing MAIN MENU")
		return
	await _click(menu_b)
	if not await _wait_state(GameManager.State.MENU, "MENU"):
		return
	if _find_button(_screen(), "BtnPlay") == null:
		_fail("main menu missing PLAY")
		return
	print("CC_UI_MENU ok")
	await _shot("06_menu")
	# S8.4 — touchscreen navigation: tap HOW TO PLAY with an emulated
	# finger (engine synthesizes the GUI click), tap BACK the same way.
	var htp_b: Button = _find_button(_screen(), "BtnHowTo")
	if htp_b == null:
		_fail("main menu missing HOW TO PLAY")
		return
	await _tap(htp_b.get_global_rect().get_center())
	if _screen() == null or not _screen().name.to_lower().contains("how"):
		_fail("touch tap did not open HOW TO PLAY")
		return
	await _frames(10)
	var back_b: Button = _find_button(_screen(), "BtnBack")
	if back_b == null:
		_fail("HOW TO PLAY missing BACK")
		return
	await _tap(back_b.get_global_rect().get_center())
	await _frames(10)
	if _find_button(_screen(), "BtnPlay") == null:
		_fail("touch tap did not return to the main menu")
		return
	print("CC_UI_TOUCH_TAP ok")
	var play_b: Button = _find_button(_screen(), "BtnPlay")
	await _click(play_b)
	if not await _wait_state(GameManager.State.PLAYING, "PLAYING from menu (run 3)"):
		return
	if _director._hud == null:
		_fail("HUD missing on run 3")
		return
	print("CC_UI_RUN3 ok ads_seen=%d" % _ads_seen)
	# S8.5 — touchscreen STEERING (exit criterion: full loop navigable with
	# only a touchscreen). Fresh snake on run 3: god-mode it, plant the
	# dynamic joystick in the left half, drag right (+X steer), verify the
	# scheme auto-switched and the snake actually turned, then release.
	if _director._snake != null:
		_director._snake.set_meta("invulnerable_until", 1.0e9)
	await _frames(10)
	var facing_t0: float = _director._snake.facing_angle_deg
	var origin_px: Vector2 = Vector2(200.0, 400.0)
	var tdown: InputEventScreenTouch = InputEventScreenTouch.new()
	tdown.index = 1
	tdown.pressed = true
	tdown.position = origin_px
	Input.parse_input_event(tdown)
	await _frames(2)
	var tdrag: InputEventScreenDrag = InputEventScreenDrag.new()
	tdrag.index = 1
	tdrag.position = origin_px + Vector2(90.0, 0.0)
	tdrag.pressure = 1.0
	Input.parse_input_event(tdrag)
	# Motion-class events are accumulated and flushed at frame end — wait a
	# frame before asserting on their effects (probe-verified in 4.7).
	await _frames(2)
	if InputManager.get_active_scheme() != InputManager.Scheme.TOUCH:
		_fail("touch did not activate the TOUCH scheme (got %s)" % InputManager.Scheme.keys()[InputManager.get_active_scheme()])
		return
	var steer: Vector3 = InputManager.get_steer_direction(_director._snake.global_position)
	if steer.dot(Vector3(1, 0, 0)) < 0.99:
		_fail("touch drag right steered %s, expected +X" % str(steer))
		return
	await _sec(2.5)
	if absf(_director._snake.facing_angle_deg - facing_t0) < 25.0:
		var sn: SnakeController = _director._snake
		print("CC_UI_TOUCH_TURN_DIAG turn_rate=%.1f speed=%.2f power=%.1f boosting=%s segs=%d steer_target=%s" % [
			sn.current_turn_rate, sn.current_speed, sn.power, str(sn.is_boosting()),
			sn.get_segment_count(), str(sn._steer_target)])
		_fail("touch steering did not turn the snake (Δ%.1f°)" % absf(_director._snake.facing_angle_deg - facing_t0))
		return
	var tup: InputEventScreenTouch = InputEventScreenTouch.new()
	tup.index = 1
	tup.pressed = false
	tup.position = origin_px + Vector2(90.0, 0.0)
	Input.parse_input_event(tup)
	await _frames(2)
	if InputManager.get_steer_direction(_director._snake.global_position) != Vector3.ZERO:
		_fail("touch release did not clear steering")
		return
	print("CC_UI_TOUCH_STEER ok Δ%.1f°" % absf(_director._snake.facing_angle_deg - facing_t0))
	await _frames(30)
	await _shot("07_run3")
	print("CC_UI_VERIFY_PASS")
	get_tree().quit(0)


# --- portrait pass ----------------------------------------------------------------

func _stage_portrait() -> void:
	# Returning player (FTUE done from the landscape pass): menu → play →
	# HUD must lay out in 9:16 (exit criteria: portrait + landscape).
	if GameManager.is_in(GameManager.State.MENU):
		var play_b: Button = _find_button(_screen(), "BtnPlay")
		if play_b == null:
			_fail("portrait: menu missing PLAY")
			return
		await _click(play_b)
		if not await _wait_state(GameManager.State.PLAYING, "portrait PLAYING"):
			return
	elif not GameManager.is_in(GameManager.State.PLAYING):
		_fail("portrait: unexpected state %s" % GameManager.state_name())
		return
	await _sec(1.5)
	var hud: Control = _director._hud
	if hud == null:
		_fail("portrait: HUD missing")
		return
	var vp: Vector2 = hud.get_viewport_rect().size
	if vp.y < vp.x:
		_fail("portrait: viewport is %s (landscape?)" % str(vp))
		return
	await _shot("08_portrait_hud")
	print("CC_UI_VERIFY_PASS")
	get_tree().quit(0)
