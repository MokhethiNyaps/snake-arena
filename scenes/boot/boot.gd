extends Node
## Phase 8 run director — owns the world lifecycle (arena + player), the
## MENU ↔ RUN navigation, pause, game-over stats + panel, the §45.5 revive
## path, replay (with INTER_RUN pacing), the §13.4 FTUE first-run flow,
## and the sandbox verification env hooks (CC_SMOKE_TEST / CC_SCREENSHOT /
## CC_RUN_TESTS — they force a run regardless of saved FTUE state so CI is
## deterministic even with a persisted user:// settings file).
##
## Owns: world nodes, run counters (absorbs, revives), best score.
## Talks to: GameManager, UIManager, EventBus, AdManager, Analytics.
## Screens reach this node via the "run_director" group (no node paths).

const ARENA_SCENE: String = "res://scenes/arena/arena.tscn"
const PLAYER_SCENE: String = "res://scenes/player/player_snake.tscn"
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const MENU_SCENE: PackedScene = preload("res://scenes/ui/main_menu.tscn")
const PAUSE_SCENE: PackedScene = preload("res://scenes/ui/pause.tscn")
const GAME_OVER_SCENE: PackedScene = preload("res://scenes/ui/game_over.tscn")

var _arena: Node3D = null
var _player: Node3D = null
var _snake: SnakeController = null
var _hud: Control = null

var _run_index: int = 0
var _revives_used_this_run: int = 0
var _absorbed_this_run: int = 0
var _death_power: float = 2.0
var _death_length: int = 6
var _best_score: float = 0.0
## Phase 9 meta systems (children so they tick + receive events with us).
var _skins: SkinManager = null
var _missions: MissionManager = null
var _leaderboards: LeaderboardManager = null
## Coins earned by the LAST completed run (game-over "×2" doubles this).
var _coins_earned_this_run: int = 0


func _ready() -> void:
	add_to_group("run_director")
	_skins = SkinManager.new()
	_skins.name = "SkinManager"
	add_child(_skins)
	_missions = MissionManager.new()
	_missions.name = "MissionManager"
	add_child(_missions)
	_leaderboards = LeaderboardManager.new()
	_leaderboards.name = "LeaderboardManager"
	add_child(_leaderboards)
	EventBus.player_died.connect(_on_player_died)
	EventBus.snake_died.connect(_on_snake_died)
	EventBus.game_state_changed.connect(_on_state_changed)
	EventBus.settings_changed.connect(_on_setting_changed)
	_best_score = SaveManager.get_best_score()
	_apply_saved_audio()
	var ui_verify: bool = OS.get_environment("CC_UI_VERIFY") != ""
	if ui_verify:
		# Fresh-install simulation: the UI driver re-runs the real flow.
		DirAccess.remove_absolute("user://settings.cfg")
		SaveManager._settings = ConfigFile.new()
		DirAccess.remove_absolute("user://save.json")
		DirAccess.remove_absolute("user://save.json.corrupt")
		SaveManager.reset_for_verify()
	var forced_run: bool = not ui_verify and (
		OS.get_environment("CC_SMOKE_TEST") != ""
		or OS.get_environment("CC_SCREENSHOT") != ""
		or OS.get_environment("CC_RUN_TESTS") != "")
	var ftue_done: bool = SaveManager.is_ftue_done()
	if ftue_done and not forced_run:
		_to_menu()
	else:
		# §13.4: first launch drops straight into a run — no menu, no ads.
		start_run(not ftue_done)
	if ui_verify:
		var driver: Node = (load("res://tests/ui_verify_driver.gd") as GDScript).new()
		add_child(driver)
	_handle_test_env()


# --- run lifecycle -----------------------------------------------------------

func start_run(ftue: bool = false) -> void:
	_set_world_active(false)
	UIManager.clear_screens()
	_teardown_world()
	if not GameManager.request_state(GameManager.State.LOADING):
		return
	_build_world()
	_run_index += 1
	_revives_used_this_run = 0
	_absorbed_this_run = 0
	Engine.time_scale = 1.0
	get_tree().paused = false
	InputManager.set_suspended(false)
	GameManager.request_state(GameManager.State.PLAYING)
	EventBus.run_started.emit()
	Analytics.track(&"run_started", {"run_index": _run_index, "ftue": ftue})
	_hud = UIManager.push_screen(HUD_SCENE)
	_hud.bind(_arena, _snake)
	_apply_saved_settings_to_world()
	if ftue:
		_hud.start_ftue()


func _build_world() -> void:
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(_arena)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	add_child(_player)
	_snake = _player.get_node("Snake")
	# §16: skins are VISUAL-ONLY and applied at the SnakeBody layer — the
	# controller never sees them (test-enforced invariant).
	if _skins != null:
		_skins.apply_equipped_to(_snake.body)
	var rig: CameraRig = _player.get_node("CameraRig")
	rig.set_target(_snake)
	if _arena.has_method("setup_world"):
		_arena.setup_world(_player, _snake)


func _teardown_world() -> void:
	if _arena != null:
		_arena.queue_free()
		_arena = null
	if _player != null:
		_player.queue_free()
		_player = null
	_snake = null
	_hud = null


func _to_menu() -> void:
	_teardown_world()
	UIManager.clear_screens()
	GameManager.request_state(GameManager.State.MENU)
	UIManager.push_screen(MENU_SCENE)


func quit_to_menu() -> void:
	get_tree().paused = false
	InputManager.set_suspended(false)
	Engine.time_scale = 1.0
	_to_menu()
	# §45.3 MENU_RETURN: min 180 s gap, never back-to-back with INTER_RUN;
	# the pacer decides (Null provider → instant DISABLED, no interruption).
	var result: AdResult = await AdManager.request_ad(AdPlacementId.ID.MENU_RETURN)
	if result.code == AdResult.Code.SHOWN_COMPLETED:
		Analytics.track(&"ad_shown", {"placement": "MENU_RETURN"})


# --- pause (§7 pause action; toggle) ------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if GameManager.is_in(GameManager.State.PLAYING):
			pause_game()
		elif GameManager.is_in(GameManager.State.PAUSED):
			resume_from_pause()
		get_viewport().set_input_as_handled()


func pause_game() -> void:
	if not GameManager.request_state(GameManager.State.PAUSED):
		return
	get_tree().paused = true
	InputManager.set_suspended(true)
	UIManager.push_screen(PAUSE_SCENE)


func resume_from_pause() -> void:
	UIManager.pop_screen()
	get_tree().paused = false
	InputManager.set_suspended(false)
	GameManager.request_state(GameManager.State.PLAYING)


# --- death → game over (§12) ---------------------------------------------------

func _on_player_died() -> void:
	# Capture BEFORE the dissolve shrinks the body to zero segments.
	if _snake != null:
		_death_power = _snake.power
		_death_length = _snake.get_segment_count()
	Analytics.track(&"run_ended", {"phase": "dying"})


func _on_snake_died(killer_id: int, _victim_id: int) -> void:
	if _snake != null and killer_id == _snake.get_instance_id():
		_absorbed_this_run += 1


func _on_state_changed(_from: int, to: int) -> void:
	if to == GameManager.State.GAME_OVER and _arena != null:
		_push_game_over()


func _collect_stats() -> Dictionary:
	var entries: Array = []
	if _snake != null:
		entries.append({"name": "YOU", "power": _death_power, "is_player": true, "id": 0})
	if _arena != null and _arena.ai_director != null:
		for ai in _arena.ai_director.ai_controllers:
			if ai.snake != null:
				entries.append({"name": ai.display_name, "power": ai.snake.power, "is_player": false, "id": 1})
	var score: float = _arena.score_manager.get_score() if _arena != null and _arena.score_manager != null else 0.0
	var stats: Dictionary = _settle_meta(score, entries)
	var new_best: bool = bool(stats.get("new_best", false))
	if new_best:
		_best_score = score
	return {
		"score": score,
		"power": _death_power,
		"length": _death_length,
		"rank": LeaderboardSort.player_rank(entries),
		"field_size": entries.size(),
		"time_s": float(int(_arena.combat_manager._elapsed)) if _arena != null and _arena.combat_manager != null else 0.0,
		"absorbed": _absorbed_this_run,
		"new_best": new_best,
		"coins": _coins_earned_this_run,
		"level": SaveManager.get_level(),
	}


func _push_game_over() -> void:
	var stats: Dictionary = _collect_stats()
	var screen: Control = GAME_OVER_SCENE.instantiate()
	screen.set_meta("stats", stats)
	screen.set_meta("revive_available", _revives_used_this_run < 1)
	UIManager.push_screen_instance(screen)


## §45.5 revive: 65% of death power, 2.5 s invulnerability, away from threats.
func do_revive(power: float) -> void:
	if _snake == null or _arena == null:
		return
	_revives_used_this_run += 1
	var pos: Vector3 = _safe_revive_position()
	_snake.revive_at(pos, power)
	if _arena.combat_manager != null:
		_arena.combat_manager.set_player_invulnerable(
			float(_arena.combat_manager._elapsed) + 2.5)
	_death_power = _snake.power
	get_tree().paused = false
	InputManager.set_suspended(false)
	Engine.time_scale = 1.0
	GameManager.request_state(GameManager.State.PLAYING)
	EventBus.player_spawned.emit()
	Analytics.track(&"run_started", {"run_index": _run_index, "revive": true})


func _safe_revive_position() -> Vector3:
	# Try random points inside the live radius; require >= 30 units from
	# every live snake head (§45.5 "away from immediate threats").
	var radius: float = _arena.combat_manager.current_radius() if _arena.combat_manager != null else 120.0
	var heads: Array[Vector3] = []
	if _arena.ai_director != null:
		for ai in _arena.ai_director.ai_controllers:
			if ai.snake != null and ai.snake.alive:
				heads.append(ai.snake.global_position)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for i in 40:
		var ang: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * maxf(10.0, radius - 8.0)
		var cand: Vector3 = Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var ok: bool = true
		for h in heads:
			if h.distance_to(cand) < 30.0:
				ok = false
				break
		if ok:
			return cand
	return Vector3.ZERO


## §16 meta settlement — runs ONCE per run, at game over (never on revive).
## Coins: floor(score/120) + 25 top-3 bonus. XP: score/10. Also: high-score
## submit (with skin), daily missions, lifetime stats.
func _settle_meta(score: float, entries: Array) -> Dictionary:
	var cfg: MetaConfig = SaveManager.meta_config()
	var coins: int = int(floor(score / cfg.coins_per_score))
	var rank: int = LeaderboardSort.player_rank(entries)
	if rank <= 3:
		coins += cfg.top3_coin_bonus
	_coins_earned_this_run = coins
	if coins > 0:
		SaveManager.add_coins(coins, &"run_payout")
	var skin_id: String = _skins.get_equipped_id() if _skins != null else "classic"
	var new_best: bool = _leaderboards.submit_run(score, {"skin": skin_id}) if _leaderboards != null else false
	SaveManager.add_xp(int(floor(score / cfg.xp_per_score)))
	SaveManager.record_run_finished(score, _absorbed_this_run)
	var stats: Dictionary = {
		"score": score, "rank": rank, "field_size": entries.size(),
		"absorbed": _absorbed_this_run,
	}
	if _missions != null:
		_missions.on_run_ended(stats)
	return {"new_best": new_best}


## Rewarded ×2 coins (§45.5): doubles the RUN payout only — no score effect.
func grant_double_coins() -> void:
	if _coins_earned_this_run <= 0:
		return
	SaveManager.add_coins(_coins_earned_this_run, &"double_coins")
	_coins_earned_this_run *= 2
	Analytics.track(&"coins_earned", {"amount": _coins_earned_this_run, "doubled": true})


# --- settings → live world -----------------------------------------------------

func _apply_saved_audio() -> void:
	var master: float = float(SaveManager.get_setting("settings", "master_db", 0.0))
	var muted: bool = bool(SaveManager.get_setting("settings", "muted", false))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), -80.0 if muted else master)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"),
		float(SaveManager.get_setting("settings", "music_db", -6.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"),
		float(SaveManager.get_setting("settings", "sfx_db", 0.0)))


func _apply_saved_settings_to_world() -> void:
	if _hud != null:
		_hud.minimap_enabled = bool(SaveManager.get_setting("settings", "minimap", true))
		_hud.high_contrast = bool(SaveManager.get_setting("settings", "high_contrast", false))
	if _player != null:
		var rig: CameraRig = _player.get_node("CameraRig")
		if rig != null:
			rig.set_shake_intensity(float(SaveManager.get_setting("settings", "shake_percent", 100.0)) / 100.0)
	if _arena != null and _arena.collectible_manager != null:
		_arena.collectible_manager.floating_labels_enabled = \
			bool(SaveManager.get_setting("settings", "floating_numbers", true))


func _on_setting_changed(section: String, key: String) -> void:
	if section != "settings":
		return
	match key:
		"shake_percent":
			if _player != null:
				var rig: CameraRig = _player.get_node("CameraRig")
				if rig != null:
					rig.set_shake_intensity(float(SaveManager.get_setting(section, key, 100.0)) / 100.0)
		"minimap":
			if _hud != null:
				_hud.minimap_enabled = bool(SaveManager.get_setting(section, key, true))
		"high_contrast":
			if _hud != null:
				_hud.high_contrast = bool(SaveManager.get_setting(section, key, false))
		"floating_numbers":
			if _arena != null and _arena.collectible_manager != null:
				_arena.collectible_manager.floating_labels_enabled = \
					bool(SaveManager.get_setting(section, key, true))


## Kept alive for compatibility with the world-freeze helper used by the
## verify harness (arena.gd checks GameManager state itself).
func _set_world_active(_active: bool) -> void:
	pass


# --- sandbox verification hooks (env-gated; shipped builds never hit these) ----

func _handle_test_env() -> void:
	var smoke: String = OS.get_environment("CC_SMOKE_TEST")
	var shot: String = OS.get_environment("CC_SCREENSHOT")
	var run_tests: String = OS.get_environment("CC_RUN_TESTS")
	if smoke == "" and shot == "" and run_tests == "":
		return
	_run_test_hooks(smoke, shot, run_tests)


func _run_test_hooks(smoke: String, shot: String, run_tests: String) -> void:
	# Let the scene process and render a stable number of frames first.
	for i in 30:
		await get_tree().process_frame
	if smoke != "":
		var arena_ok: bool = _arena != null and _arena.get_node_or_null("Ground") != null
		var player_ok: bool = _player != null and _player.get_node_or_null("Snake") != null
		var snake: SnakeController = _player.get_node("Snake") if player_ok else null
		print("CC_SMOKE_OK arena_loaded=%s player_loaded=%s segs=%s state=%s" % [
			arena_ok, player_ok,
			str(snake.get_segment_count()) if snake != null else "n/a",
			GameManager.state_name()])
	if shot != "":
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(shot)
		print("CC_SCREENSHOT_OK saved=%s" % shot)
	if run_tests != "":
		await _run_full_test_suite()
	get_tree().quit(0)


func _run_full_test_suite() -> void:
	var passes: int = 0
	var fails: Array[String] = []
	var script_fails: Array[String] = []
	const TEST_TIMEOUT_S: float = 30.0
	print("==================================================")
	print(" COILCLASH TEST SUITE (boot harness)")
	print("==================================================")
	var test_files: Array[String] = []
	var dir: DirAccess = DirAccess.open("res://tests")
	if dir == null:
		print("NO TESTS DIR")
		get_tree().quit(1)
		await get_tree().process_frame
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.begins_with("test_") and fname.ends_with(".gd") and not dir.current_is_dir():
			test_files.append("res://tests/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	test_files.sort()
	if test_files.is_empty():
		print("No test_*.gd files found")
		get_tree().quit(1)
		await get_tree().process_frame
		return
	for path in test_files:
		var script: GDScript = load(path) as GDScript
		if script == null:
			script_fails.append("%s (load failed)" % path)
			continue
		var instance: RefCounted = script.new()
		if instance == null:
			script_fails.append("%s (instantiate failed)" % path)
			continue
		var method_count: int = 0
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			method_count += 1
			var finished: Array = [false]
			var slot: Array = [null]
			var driver := func() -> void:
				slot[0] = await instance.call(method_name)
				finished[0] = true
			driver.call()
			var t: SceneTreeTimer = get_tree().create_timer(TEST_TIMEOUT_S, true)
			while not finished[0] and t.time_left > 0.0:
				await get_tree().create_timer(0.05, true).timeout
			var result: Variant = slot[0] if finished[0] else "TIMEOUT after %.0fs" % TEST_TIMEOUT_S
			if typeof(result) == TYPE_BOOL and result == true:
				passes += 1
			else:
				var detail: String = str(result) if typeof(result) != TYPE_BOOL else ""
				fails.append("%s.%s %s" % [path.get_file(), method_name, detail])
			_reset_contract()
		if method_count == 0:
			script_fails.append("%s (no test_* methods)" % path)
	print("==================================================")
	print(" RESULTS: %d passed, %d failed" % [passes, fails.size()])
	for f in script_fails:
		print("  SCRIPT ERROR: %s" % f)
	for f in fails:
		print("  FAIL: %s" % f)
	print("==================================================")
	get_tree().quit(1 if (fails.size() + script_fails.size()) > 0 else 0)


func _reset_contract() -> void:
	if get_tree().paused:
		get_tree().paused = false
	var im: Node = get_tree().root.get_node_or_null("InputManager")
	if im != null:
		im.call("set_suspended", false)
	var am: Node = get_tree().root.get_node_or_null("AudioManager")
	if am != null and am.has_method("_restore_duck"):
		am.call("_restore_duck")
