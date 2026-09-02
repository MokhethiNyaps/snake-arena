extends Control
## §13.1 Pause — RESUME / SETTINGS / MAIN MENU. The tree is paused while
## this screen is up (PROCESS_MODE_ALWAYS via UIManager's layer); resume
## path unpauses and pops. Talks to: run director, UIManager, GameManager.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-130, -120)
	col.custom_minimum_size = Vector2(260, 0)
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	var title: Label = Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var resume_b: Button = _button("RESUME", _on_resume)
	resume_b.name = "BtnResume"
	col.add_child(resume_b)
	col.add_child(_button("SETTINGS", _on_settings))
	var menu_b: Button = _button("MAIN MENU", _on_menu)
	menu_b.name = "BtnMenu"
	col.add_child(menu_b)


func _button(text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(260, 52)
	b.pressed.connect(handler)
	return b


func _on_resume() -> void:
	var director: Node = get_tree().get_first_node_in_group("run_director")
	if director != null:
		director.call("resume_from_pause")


func _on_settings() -> void:
	UIManager.push_screen(load("res://scenes/ui/settings.tscn"))


func _on_menu() -> void:
	var director: Node = get_tree().get_first_node_in_group("run_director")
	if director != null:
		director.call("quit_to_menu")


## Esc/P toggles back to the game (pause is a toggle, §7 pause action).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_on_resume()
		get_viewport().set_input_as_handled()
