extends Node
## Boot entry driver (§13.1 Boot → MainMenu → Game). Loads the arena and
## drives the initial GameManager state sequence.
##
## Owns: the startup sequence and the smoke/screenshot env hooks used by the
##        sandbox verification harness (CC_SMOKE_TEST / CC_SCREENSHOT).
## Does NOT own: screens (UIManager), the arena (arena.tscn).
## Talks to: GameManager, UIManager.
##
## Phase-1 note: the menu screen does not exist yet (§21 tree, Phase 8), so
## boot goes straight to the arena — matches the FTUE philosophy in §13.4
## and is logged as decision #14.

const ARENA_SCENE: String = "res://scenes/arena/arena.tscn"

var _arena: Node3D = null


func _ready() -> void:
	GameManager.request_state(GameManager.State.LOADING)
	_load_arena()
	GameManager.request_state(GameManager.State.PLAYING)
	print("BOOT_DONE")
	_handle_test_env()


func _load_arena() -> void:
	var arena_scene: PackedScene = load(ARENA_SCENE)
	_arena = arena_scene.instantiate()
	add_child(_arena)


## Sandbox verification hooks (harmless in shipped builds; controlled by env).
func _handle_test_env() -> void:
	var smoke: String = OS.get_environment("CC_SMOKE_TEST")
	var shot: String = OS.get_environment("CC_SCREENSHOT")
	if smoke == "" and shot == "":
		return
	_run_test_hooks(smoke, shot)


func _run_test_hooks(smoke: String, shot: String) -> void:
	# Let the scene process and render a stable number of frames first.
	for i in 30:
		await get_tree().process_frame
	if smoke != "":
		var arena_ok: bool = _arena != null and _arena.get_node_or_null("Ground") != null
		print("CC_SMOKE_OK arena_loaded=%s state=%s" % [arena_ok, GameManager.state_name()])
	if shot != "":
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(shot)
		print("CC_SCREENSHOT_OK saved=%s" % shot)
	get_tree().quit(0)
