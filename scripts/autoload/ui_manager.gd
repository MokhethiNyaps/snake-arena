extends Node
## AUTOLOAD #11 — UIManager (§13.1). Owns the screen stack and 0.18 s fades.
## No screen ever references another screen directly — transitions go through
## this stack.
##
## Owns: the UIRoot CanvasLayer and stack bookkeeping.
## Does NOT own: screen internals (each scenes/ui/*.tscn owns its layout).
## Talks to: GameManager state changes decide pushes/pops; screens call
##           push/pop/replace themselves at the top level.

const FADE_TIME: float = 0.18
const UI_LAYER: int = 10

var _ui_root: CanvasLayer = null
var _screen_stack: Array[Control] = []


func _ready() -> void:
	_ui_root = CanvasLayer.new()
	_ui_root.name = "UIRoot"
	_ui_root.layer = UI_LAYER
	add_child(_ui_root)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Pushes a screen on top. Returns the instantiated Control.
func push_screen(scene: PackedScene) -> Control:
	return push_screen_instance(scene.instantiate())


## Pushes an ALREADY-instantiated screen (callers that must configure the
## screen before its _ready runs — e.g. the game-over stats snapshot).
func push_screen_instance(screen: Control) -> Control:
	_ui_root.add_child(screen)
	_screen_stack.append(screen)
	screen.modulate.a = 0.0
	var tween: Tween = screen.create_tween()
	tween.tween_property(screen, "modulate:a", 1.0, FADE_TIME)
	return screen


## Pops the top screen (with fade). Returns the popped screen (freed at end
## of fade) or null if the stack is empty.
func pop_screen() -> Control:
	if _screen_stack.is_empty():
		return null
	var screen: Control = _screen_stack.pop_back()
	var tween: Tween = screen.create_tween()
	tween.tween_property(screen, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(screen.queue_free)
	return screen


## Replaces the whole stack with one screen.
func replace_screen(scene: PackedScene) -> Control:
	clear_screens()
	return push_screen(scene)


## Pops everything, immediately (no fades) — used on hard resets.
func clear_screens() -> void:
	for screen in _screen_stack:
		if is_instance_valid(screen):
			screen.queue_free()
	_screen_stack.clear()


func get_current_screen() -> Control:
	return _screen_stack.back() if not _screen_stack.is_empty() else null


func screen_count() -> int:
	return _screen_stack.size()
