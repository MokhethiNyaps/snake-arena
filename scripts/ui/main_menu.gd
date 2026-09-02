extends Control
## §13.1 MainMenu — title, PLAY (ui_confirm/click), HOW TO PLAY, SETTINGS.
## Banner-safe (§45.3 BANNER_MENU is menu-only; the layout reserves the
## bottom strip). Talks to: the run director (group "run_director"),
## UIManager (pushes sub-screens). Does NOT own: run lifecycle.

var _director: Node = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_director = get_tree().get_first_node_in_group("run_director")
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.09, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-150, -190)
	col.custom_minimum_size = Vector2(300, 0)
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	var title: Label = _label(52, Color(0.55, 0.95, 1.0))
	title.text = "COILCLASH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var tagline: Label = _label(18, Color(0.7, 0.8, 0.9))
	tagline.text = "Absorb the arena."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tagline)
	var play_b: Button = _button("PLAY", _on_play, 30)
	play_b.name = "BtnPlay"
	col.add_child(play_b)
	var how_b: Button = _button("HOW TO PLAY", _on_how, 22)
	how_b.name = "BtnHowTo"
	col.add_child(how_b)
	col.add_child(_button("SETTINGS", _on_settings, 22))
	var version: Label = _label(14, Color(0.5, 0.55, 0.6))
	version.text = "v0.8.0-dev"
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.position = Vector2(10, -24)
	add_child(version)
	# §45.3: BANNER_MENU shows on menu screens only (no-op with Null/Mock
	# without a banner — get_banner_height_px() returns 0).
	AdManager.show_banner(0)


## Keyboard path: ui_confirm (Enter/Space/gamepad A) triggers PLAY so the
## full loop is navigable without a mouse too.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_confirm"):
		_on_play()
		get_viewport().set_input_as_handled()


func _label(size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, handler: Callable, size: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(300, 56)
	b.pressed.connect(handler)
	return b


func _on_play() -> void:
	AdManager.hide_banner()
	if _director != null:
		_director.call("start_run")


func _on_how() -> void:
	UIManager.push_screen(load("res://scenes/ui/how_to_play.tscn"))


func _on_settings() -> void:
	UIManager.push_screen(load("res://scenes/ui/settings.tscn"))
