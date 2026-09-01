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
		_run_script(path)
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
		var result: Variant = instance.call(method_name)
		if typeof(result) == TYPE_BOOL and result == true:
			_passes += 1
		else:
			var detail: String = str(result) if typeof(result) != TYPE_BOOL else ""
			_fails.append("%s.%s %s" % [path.get_file(), method_name, detail])
	if method_count == 0:
		_script_fails.append("%s (no test_* methods)" % path)
