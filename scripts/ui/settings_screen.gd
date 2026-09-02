extends Control
## §14 Settings — audio (master/music/SFX dB + mute), camera shake %,
## minimap on/off, floating score numbers on/off, high-contrast HUD.
## Every change applies IMMEDIATELY and persists (SaveManager settings.cfg;
## EventBus.settings_changed notifies live systems). Does NOT own: the
## settings themselves (SaveManager does). Ad-privacy entry arrives with
## the Phase 11 consent screen.


const SECTION: String = "settings"

var _director: Node = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_director = get_tree().get_first_node_in_group("run_director")
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-240, -260)
	col.custom_minimum_size = Vector2(480, 0)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var title: Label = _label(34, Color(0.55, 0.95, 1.0))
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_slider(col, "Master volume", "master_db", -40.0, 6.0, 0.0)
	_slider(col, "Music volume", "music_db", -40.0, 6.0, -6.0)
	_slider(col, "SFX volume", "sfx_db", -40.0, 6.0, 0.0)
	_check(col, "Mute all", "muted", false)
	_slider(col, "Camera shake %", "shake_percent", 0.0, 100.0, 100.0)
	_check(col, "Show minimap", "minimap", true)
	_check(col, "Floating score numbers", "floating_numbers", true)
	_check(col, "High-contrast HUD", "high_contrast", false)
	col.add_child(_button("BACK", _on_back))


func _label(size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(200, 48)
	b.pressed.connect(handler)
	return b


func _slider(parent: Node, label_text: String, key: String, lo: float, hi: float, default: float) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l: Label = _label(19, Color(0.75, 0.82, 0.9))
	l.text = label_text
	l.custom_minimum_size = Vector2(230, 26)
	row.add_child(l)
	var s: HSlider = HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1.0
	s.custom_minimum_size = Vector2(200, 26)
	s.value = float(SaveManager.get_setting(SECTION, key, default))
	s.value_changed.connect(func(v: float) -> void: _apply(key, v))
	row.add_child(s)
	parent.add_child(row)


func _check(parent: Node, label_text: String, key: String, default: bool) -> void:
	var cb: CheckBox = CheckBox.new()
	cb.text = label_text
	cb.add_theme_font_size_override("font_size", 19)
	cb.button_pressed = bool(SaveManager.get_setting(SECTION, key, default))
	cb.toggled.connect(func(v: bool) -> void: _apply(key, v))
	parent.add_child(cb)


func _apply(key: String, value: Variant) -> void:
	SaveManager.set_setting(SECTION, key, value)
	_apply_setting_now(key, value)
	EventBus.settings_changed.emit(SECTION, key)
	Analytics.track(&"settings_changed", {"key": key})


## Applies a setting to the live systems immediately (§14). Non-audio keys
## are consumed by live systems via EventBus.settings_changed (HUD minimap/
## contrast, camera rig shake, collectible floating labels via the director).
static func _apply_setting_now(key: String, value: Variant) -> void:
	match key:
		"master_db":
			var muted: bool = bool(SaveManager.get_setting(SECTION, "muted", false))
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"),
				-80.0 if muted else float(value))
		"muted":
			var master_v: float = float(SaveManager.get_setting(SECTION, "master_db", 0.0))
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"),
				-80.0 if bool(value) else master_v)
		"music_db":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), float(value))
		"sfx_db":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), float(value))


func _on_back() -> void:
	UIManager.pop_screen()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_on_back()
		get_viewport().set_input_as_handled()
