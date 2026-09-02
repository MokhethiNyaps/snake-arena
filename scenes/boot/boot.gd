extends Node
## Boot entry driver (§13.1 Boot → MainMenu → Game). Loads the arena and the
## player, and drives the initial GameManager state sequence.
##
## Owns: the startup sequence and the smoke/screenshot env hooks used by the
##        sandbox verification harness (CC_SMOKE_TEST / CC_SCREENSHOT).
## Does NOT own: screens (UIManager), the arena (arena.tscn), the player.
## Talks to: GameManager, UIManager.
##
## Phase-2 note: the menu screen still does not exist (§21 tree, Phase 8),
## so boot goes straight to the arena — matches the §13.4 FTUE philosophy
## and is logged as decision #14.

const ARENA_SCENE: String = "res://scenes/arena/arena.tscn"
const PLAYER_SCENE: String = "res://scenes/player/player_snake.tscn"

var _arena: Node3D = null
var _player: Node3D = null


func _ready() -> void:
	GameManager.request_state(GameManager.State.LOADING)
	_load_arena()
	_load_player()
	GameManager.request_state(GameManager.State.PLAYING)
	print("BOOT_DONE")
	_handle_test_env()


func _load_arena() -> void:
	var arena_scene: PackedScene = load(ARENA_SCENE)
	_arena = arena_scene.instantiate()
	add_child(_arena)


func _load_player() -> void:
	var player_scene: PackedScene = load(PLAYER_SCENE)
	_player = player_scene.instantiate()
	add_child(_player)
	var snake: SnakeController = _player.get_node("Snake")
	var rig: CameraRig = _player.get_node("CameraRig")
	rig.set_target(snake)
	# Phase 3: wire the arena economy to the player.
	if _arena != null and _arena.has_method("setup_world"):
		_arena.setup_world(_player, snake)


## Sandbox verification hooks (harmless in shipped builds; controlled by env).
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


## Drives the REAL test suite (class names are globally registered NOW since
## autoloads finished booting). Mirrors run_tests.gd discovery / logic but
## with autoloads available so typed annotations resolve at parse-time.
func _run_full_test_suite() -> void:
	var _passes: int = 0
	var _fails: Array[String] = []
	var _script_fails: Array[String] = []
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
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("test_") and name.ends_with(".gd") and not dir.current_is_dir():
			test_files.append("res://tests/" + name)
		name = dir.get_next()
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
			_script_fails.append("%s (load failed)" % path)
			continue
		var instance: RefCounted = script.new()
		if instance == null:
			_script_fails.append("%s (instantiate failed)" % path)
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
				_passes += 1
			else:
				var detail: String = str(result) if typeof(result) != TYPE_BOOL else ""
				_fails.append("%s.%s %s" % [path.get_file(), method_name, detail])
			_reset_contract()
		if method_count == 0:
			_script_fails.append("%s (no test_* methods)" % path)
	print("==================================================")
	print(" RESULTS: %d passed, %d failed" % [_passes, _fails.size()])
	for f in _script_fails:
		print("  SCRIPT ERROR: %s" % f)
	for f in _fails:
		print("  FAIL: %s" % f)
	print("==================================================")
	get_tree().quit(1 if (_fails.size() + _script_fails.size()) > 0 else 0)


func _reset_contract() -> void:
	if get_tree().paused:
		get_tree().paused = false
	var im: Node = get_tree().root.get_node_or_null("InputManager")
	if im != null:
		im.call("set_suspended", false)
	var am: Node = get_tree().root.get_node_or_null("AudioManager")
	if am != null and am.has_method("_ducked"):
		am._ducked = false
	var adm: Node = get_tree().root.get_node_or_null("AdManager")
	if adm != null:
		if adm.has_method("_overlay") and adm._overlay != null:
			adm._overlay.visible = false
		if adm.has_method("_busy"):
			adm._busy = false
