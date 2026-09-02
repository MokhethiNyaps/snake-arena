extends Control
## §13.1 HowToPlay — static control scheme + goal reference, per §7 schemes.
## Talks to: UIManager (back). Reads: InputManager scheme (highlights the
## active scheme's row).


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-260, -250)
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var title: Label = _label(34, Color(0.55, 0.95, 1.0))
	title.text = "HOW TO PLAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var goal: Label = _label(19, Color(0.85, 0.9, 0.95))
	goal.text = "Grow your coil. Absorb cells, cut off smaller rivals,\nand avoid anything bigger — red means it can eat you."
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(goal)
	col.add_child(_row("MOUSE", "Snake follows the cursor. Hold LMB or SPACE to boost."))
	col.add_child(_row("KEYBOARD", "WASD / arrows steer. SHIFT or SPACE boosts."))
	col.add_child(_row("TOUCH", "Drag anywhere left-of-centre to steer. Thumb button (or double-tap-hold) boosts."))
	col.add_child(_row("GAMEPAD", "Left stick steers. A / cross boosts."))
	var hint: Label = _label(17, Color(0.6, 0.65, 0.72))
	hint.text = "Boosting drains power and drops it behind you — spend it wisely."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var back: Button = Button.new()
	back.name = "BtnBack"
	back.text = "BACK"
	back.add_theme_font_size_override("font_size", 22)
	back.custom_minimum_size = Vector2(200, 48)
	back.pressed.connect(_on_back)
	col.add_child(back)


func _label(size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _row(scheme: String, text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tag: Label = _label(18, Color(0.45, 0.9, 1.0))
	tag.text = scheme
	tag.custom_minimum_size = Vector2(110, 44)
	var body: Label = _label(18, Color(0.85, 0.9, 0.95))
	body.text = text
	body.custom_minimum_size = Vector2(400, 44)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(tag)
	row.add_child(body)
	return row


func _on_back() -> void:
	UIManager.pop_screen()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_on_back()
		get_viewport().set_input_as_handled()
