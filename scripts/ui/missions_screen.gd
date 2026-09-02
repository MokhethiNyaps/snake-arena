extends Control
## §16 daily missions screen. Talks to: run director (MissionManager child),
## AdManager (MISSION_REROLL rewarded), UIManager (back).

var _director: Node = null
var _missions: MissionManager = null
var _rows_container: VBoxContainer = null
var _status: Label = null
var _reroll_b: Button = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_director = get_tree().get_first_node_in_group("run_director")
	_missions = _director._missions if _director != null else null
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-260, -280)
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var title: Label = _label(38, Color(0.55, 0.95, 1.0))
	title.text = "DAILY MISSIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var wallet: Label = _label(18, Color(1.0, 0.85, 0.3))
	wallet.name = "LblWallet"
	wallet.text = "Coins %d    Level %d" % [SaveManager.get_coins(), SaveManager.get_level()]
	wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(wallet)
	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 8)
	col.add_child(_rows_container)
	_status = _label(16, Color(0.8, 0.8, 0.85))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	_reroll_b = Button.new()
	_reroll_b.name = "BtnReroll"
	_reroll_b.text = "REROLL (watch ad)"
	_reroll_b.add_theme_font_size_override("font_size", 20)
	_reroll_b.custom_minimum_size = Vector2(240, 46)
	col.add_child(_reroll_b)
	_reroll_b.pressed.connect(_on_reroll)
	var back: Button = Button.new()
	back.name = "BtnBack"
	back.text = "BACK"
	back.add_theme_font_size_override("font_size", 22)
	back.custom_minimum_size = Vector2(200, 48)
	col.add_child(back)
	back.pressed.connect(_on_back)
	_rebuild()


func _rebuild() -> void:
	for c in _rows_container.get_children():
		c.queue_free()
	if _missions == null:
		return
	_reroll_b.visible = _missions.can_reroll()
	_reroll_b.disabled = not (AdManager.is_available(AdPlacementId.ID.MISSION_REROLL) \
		and AdManager.can_show(AdPlacementId.ID.MISSION_REROLL).get("allowed", false))
	for m in _missions.get_missions():
		_rows_container.add_child(_row(m))


func _row(m: Dictionary) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.16)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var desc: Label = _label(19, Color(0.9, 0.93, 0.97))
	desc.text = str(m["desc"]) + ("  ✓" if m["done"] else "")
	left.add_child(desc)
	var bar_bg: ColorRect = ColorRect.new()
	bar_bg.color = Color(0.15, 0.18, 0.24)
	bar_bg.custom_minimum_size = Vector2(320, 8)
	left.add_child(bar_bg)
	var bar: ColorRect = ColorRect.new()
	bar.name = "BarFill"
	bar.color = Color(0.35, 0.9, 1.0) if not m["done"] else Color(0.4, 1.0, 0.5)
	var frac: float = clampf(float(m["progress"]) / maxf(1.0, float(m["goal"])), 0.0, 1.0)
	bar.custom_minimum_size = Vector2(320.0 * frac, 8)
	bar_bg.add_child(bar)
	var prog: Label = _label(15, Color(0.6, 0.7, 0.8))
	prog.text = "%s / %s" % [_fmt(m["progress"]), _fmt(m["goal"])]
	left.add_child(prog)
	var reward: Label = _label(20, Color(1.0, 0.85, 0.3))
	reward.text = "+%d" % int(m["reward"])
	reward.custom_minimum_size = Vector2(64, 0)
	row.add_child(reward)
	return panel


func _fmt(v: float) -> String:
	if v >= 100.0 or v == floorf(v):
		return str(int(round(v)))
	return "%.0f" % v


func _on_reroll() -> void:
	_status.text = ""
	var result: AdResult = await AdManager.request_ad(AdPlacementId.ID.MISSION_REROLL)
	if result == null or not (result.code == AdResult.Code.SHOWN_COMPLETED):
		_status.text = "No ad available right now."
		_rebuild()
		return
	if _missions != null and _missions.reroll_all():
		_status.text = "Missions rerolled!"
	_rebuild()


func _on_back() -> void:
	UIManager.pop_screen()


func _label(size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
