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
	get_tree().quit(0)
