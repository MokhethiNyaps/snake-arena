extends SceneTree
## Hand-rolled headless test runner (§9A explicitly allows this instead of
## GUT — decision #13). Zero external dependencies.
##
## Run:  godot --headless --path . --script res://tests/run_tests.gd
## Exit code: 0 = all green, 1 = at least one failure.
##
## Discovers res://tests/test_*.gd; a test script is any script whose
## methods named test_*() return a bool (true = pass). Failures may also
## print context themselves before returning false.

var _passes: int = 0
var _fails: Array[String] = []
var _script_fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(" COILCLASH TEST SUITE")
	print("==================================================")
	var test_files: Array[String] = _discover_test_files()
	test_files.sort()
	if test_files.is_empty():
		print("No test_*.gd files found — that is itself a failure.")
		quit(1)
		return
	for path in test_files:
		await _run_script(path)
	print("==================================================")
	print(" RESULTS: %d passed, %d failed" % [_passes, _fails.size()])
	for f in _script_fails:
		print("  SCRIPT ERROR: %s" % f)
	for f in _fails:
		print("  FAIL: %s" % f)
	print("==================================================")
	quit(1 if (_fails.size() + _script_fails.size()) > 0 else 0)


func _discover_test_files() -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open("res://tests")
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("test_") and name.ends_with(".gd") and not dir.current_is_dir():
			out.append("res://tests/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _run_script(path: String) -> void:
	var script: GDScript = load(path) as GDScript
	if script == null:
		_script_fails.append("%s (load failed)" % path)
		return
	var instance: RefCounted = script.new()
	if instance == null:
		_script_fails.append("%s (instantiate failed)" % path)
		return
	var method_count: int = 0
	for method in script.get_script_method_list():
		var method_name: String = method["name"]
		if not method_name.begins_with("test_"):
			continue
		method_count += 1
		var result: Variant = await _run_method(instance, method_name)
		if typeof(result) == TYPE_BOOL and result == true:
			_passes += 1
		else:
			var detail: String = str(result) if typeof(result) != TYPE_BOOL else ""
			_fails.append("%s.%s %s" % [path.get_file(), method_name, detail])
		_reset_contract_state()
	if method_count == 0:
		_script_fails.append("%s (no test_* methods)" % path)


## Drives one test method to completion, whether it is synchronous or a
## coroutine (await on a plain value returns it immediately). A test that
## never resolves within TEST_TIMEOUT_S fails as "timeout" so a hung
## coroutine can never wedge the whole suite.
const TEST_TIMEOUT_S: float = 30.0


func _run_method(instance: RefCounted, method_name: String) -> Variant:
	var finished: Array = [false]
	var slot: Array = [null]
	var driver := func() -> void:
		slot[0] = await instance.call(method_name)
		finished[0] = true
	driver.call()
	var timer: SceneTreeTimer = create_timer(TEST_TIMEOUT_S, true)
	while not finished[0] and timer.time_left > 0.0:
		await create_timer(0.05, true).timeout
	if not finished[0]:
		return "TIMEOUT after %.0fs" % TEST_TIMEOUT_S
	return slot[0]


## Contract safety net: if a test fails mid-ad, the next test must not
## inherit a paused tree / suspended input / ducked audio / ad state.
## NOTE: the runner is the --script main script and cannot reference
## autoload identifiers at parse time (startup ordering), and must NOT
## preload gameplay scripts either (that would force-compile them in the
## same broken context). Autoloads are reached through the tree, and the
## enum via a RUNTIME load().
func _reset_contract_state() -> void:
	if paused:
		paused = false
	var im: Node = root.get_node_or_null("InputManager")
	if im != null:
		im.call("set_suspended", false)
	var am: Node = root.get_node_or_null("AudioManager")
	if am != null:
		am.call("restore_audio")
	var gm: Node = root.get_node_or_null("GameManager")
	if gm != null:
		var gm_script: GDScript = load("res://scripts/autoload/game_manager.gd")
		if gm.get("current_state") == gm_script.State.PAUSED_FOR_AD:
			gm.call("request_state", gm_script.State.PLAYING)
