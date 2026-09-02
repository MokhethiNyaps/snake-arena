extends Control
## §13.2 HUD — score + combo ring (top-left), live leaderboard + minimap
## (top-right), power pill (bottom-left), boost ring (bottom-right),
## power-up chips with radial timers (bottom-centre), event banners
## (top-centre), FTUE hint cards, safe-area margins, and the §45.3
## banner-ad safe zone (bottom margin from AdManager.get_banner_height_px()).
##
## PERF (§19): refs cached; text rebuilt at 10 Hz max; leaderboard 4 Hz;
## custom drawing in ONE _draw pass (rings/chips) + the minimap's own pass.
## Owns: HUD widgets only. Reads: bound arena/player. Talks to: EventBus
## (banners), SaveManager (ftue_completed). Does NOT own: pause/settings.

const UPDATE_HZ: float = 10.0
const LEADERBOARD_HZ: float = 4.0
const FTUE_HINTS: Array = [
	[0.0, "MOVE", "Follow your cursor"],
	[4.0, "EAT", "Collect cells to grow"],
	[12.0, "HUNT", "Absorb anything smaller — avoid anything bigger"],
]

var arena: Node3D = null
var player_snake: SnakeController = null

var _score_label: Label = null
var _power_label: Label = null
var _power_panel: PanelContainer = null
var _board_root: VBoxContainer = null
var _board_rows: Array[Label] = []
var _minimap: Control = null
var _banner_label: Label = null
var _hint_card: PanelContainer = null
var _hint_title: Label = null
var _hint_body: Label = null

# Cached draw state (single _draw pass, zero allocations).
var _chips: Array = []          # [{color: Color, frac: float}]
var _combo_frac: float = 0.0
var _combo_active: bool = false
var _boost_frac: float = 0.0
var _boost_can: bool = false
var _boosting: bool = false
var _inset_left_top: Vector2 = Vector2.ZERO
var _inset_right_bottom: Vector2 = Vector2.ZERO

var _update_acc: float = 1.0
var _board_acc: float = 1.0
var _hint_index: int = -1
var _hint_timer: float = 0.0
var _ftue_active: bool = false
var high_contrast: bool = false:
	set(v):
		high_contrast = v
		_apply_outline(_score_label, v)
		_apply_outline(_power_label, v)
		_apply_outline(_banner_label, v)
var minimap_enabled: bool = true:
	set(v):
		minimap_enabled = v
		if _minimap != null:
			_minimap.show_map = v


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_apply_safe_area()
	EventBus.surge_incoming.connect(_banner)
	EventBus.arena_shrinking.connect(_on_shrink)
	EventBus.snake_died.connect(_on_snake_died)


func bind(p_arena: Node3D, snake: SnakeController) -> void:
	arena = p_arena
	player_snake = snake
	if _minimap != null:
		_minimap.arena = p_arena
		_minimap.player_snake = snake


func start_ftue() -> void:
	_ftue_active = true
	_hint_index = -1
	_hint_timer = 0.0


# --- build -------------------------------------------------------------------

func _label(size: int, color: Color = Color.WHITE) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _apply_outline(l: Label, on: bool) -> void:
	if l == null:
		return
	if on:
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	else:
		l.remove_theme_constant_override("outline_size")
		l.remove_theme_color_override("font_outline_color")


func _build() -> void:
	_score_label = _label(34)
	_score_label.position = Vector2(18, 12)
	_score_label.text = "0"
	add_child(_score_label)
	_banner_label = _label(24, Color(0.75, 0.95, 1.0))
	_banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_label.position = Vector2(-130, 14)
	_banner_label.custom_minimum_size = Vector2(260, 30)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.modulate.a = 0.0
	add_child(_banner_label)
	_board_root = VBoxContainer.new()
	_board_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_board_root.position = Vector2(-190, 12)
	_board_root.custom_minimum_size = Vector2(175, 0)
	_board_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board_root)
	for i in 6:
		var row: Label = _label(17, Color(0.85, 0.9, 0.95, 0.9))
		_board_root.add_child(row)
		_board_rows.append(row)
	var minimap_script: GDScript = load("res://scripts/ui/minimap.gd")
	_minimap = Control.new()
	_minimap.set_script(minimap_script)
	_board_root.add_child(_minimap)
	_power_panel = PanelContainer.new()
	_power_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_power_panel.position = Vector2(16, -74)
	_power_panel.custom_minimum_size = Vector2(150, 52)
	_power_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_power_panel)
	_power_label = _label(30)
	_power_panel.add_child(_power_label)
	_hint_card = PanelContainer.new()
	_hint_card.set_anchors_preset(Control.PRESET_CENTER)
	_hint_card.position = Vector2(-220, 40)
	_hint_card.custom_minimum_size = Vector2(440, 84)
	_hint_card.visible = false
	_hint_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_card)
	var hint_v: VBoxContainer = VBoxContainer.new()
	_hint_card.add_child(hint_v)
	_hint_title = _label(26, Color(0.55, 0.95, 1.0))
	_hint_body = _label(19)
	hint_v.add_child(_hint_title)
	hint_v.add_child(_hint_body)


## §13.2: SafeArea margins + §45.3 banner strip at the bottom.
func _apply_safe_area() -> void:
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var vp: Vector2 = get_viewport_rect().size
	var win_size: Vector2 = Vector2(float(safe.size.x), float(safe.size.y))
	if win_size.x < 1.0 or win_size.y < 1.0:
		win_size = vp
	var scale_x: float = vp.x / win_size.x
	var scale_y: float = vp.y / win_size.y
	_inset_left_top = Vector2(0.0, 0.0)
	_inset_right_bottom = Vector2(0.0, float(maxi(0, AdManager.get_banner_height_px())) * scale_y)
	_score_label.position += _inset_left_top
	_board_root.position += -Vector2(_inset_right_bottom.x, 0.0)
	_power_panel.position += Vector2(0.0, -_inset_right_bottom.y)
	# Boost ring + chips are drawn in _draw; they read the insets directly.


# --- per-frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	if player_snake == null or arena == null:
		return
	_update_acc += delta
	_board_acc += delta
	if _update_acc >= 1.0 / UPDATE_HZ:
		_update_acc = 0.0
		_tick_10hz()
	if _board_acc >= 1.0 / LEADERBOARD_HZ:
		_board_acc = 0.0
		_tick_board()
		if _minimap != null:
			_minimap.queue_redraw()
		_sample_draw_state()
		queue_redraw()
	if _ftue_active:
		_tick_ftue(delta)


func _fmt(n: float) -> String:
	# Thousands-separated integer; called at 10 Hz only (§19 string budget).
	var i: int = int(round(n))
	var s: String = str(i)
	var out: String = ""
	var digits: int = 0
	for c_idx in range(s.length() - 1, -1, -1):
		out = s[c_idx] + out
		digits += 1
		if digits % 3 == 0 and c_idx > 0:
			out = "," + out
	return out


func _tick_10hz() -> void:
	if arena.score_manager != null:
		_score_label.text = _fmt(arena.score_manager.get_score())
	if player_snake != null:
		_power_label.text = "PWR %d" % player_snake.display_power()
		var tier: int = player_snake.power_tier()
		_power_panel.add_theme_stylebox_override("panel", _pill_style(tier))


func _pill_style(tier: int) -> StyleBoxFlat:
	# Power-tier colour bands (§3.2) — hue rotates by tier. Built at 10 Hz.
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color.from_hsv(fmod(0.55 + float(maxi(0, tier)) * 0.11, 1.0), 0.55, 0.30, 0.92)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 4.0
	return sb


func _tick_board() -> void:
	if arena.ai_director == null or player_snake == null:
		return
	var entries: Array = []
	entries.append({
		"name": "YOU", "power": player_snake.power,
		"is_player": true, "id": player_snake.get_instance_id(),
	})
	for ai in arena.ai_director.ai_controllers:
		if ai.snake == null:
			continue
		entries.append({
			"name": ai.display_name, "power": ai.snake.power,
			"is_player": false, "id": ai.get_instance_id(),
		})
	var rows: Array = LeaderboardSort.build_rows(entries, 5)
	var shown: int = 0
	for row in rows:
		if shown >= _board_rows.size():
			break
		var l: Label = _board_rows[shown]
		if bool(row["is_player"]):
			l.add_theme_color_override("font_color", Color(0.45, 1.0, 0.85))
		else:
			l.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.9))
		l.text = "%d. %s  %d" % [shown + 1, str(row["name"]), int(round(float(row["power"])))]
		shown += 1
	for i in range(shown, _board_rows.size()):
		_board_rows[i].text = ""


## Samples the ring/chip state at 4 Hz; _draw only reads these (no work).
func _sample_draw_state() -> void:
	if arena.score_manager != null:
		var combo: int = arena.score_manager.get_combo()
		_combo_active = combo > 0
		_combo_frac = clampf(arena.score_manager.combo_time_left(), 0.0, 1.0)
	if player_snake != null:
		var min_p: float = player_snake.config.min_boost_power
		_boost_can = player_snake.power > min_p
		_boosting = player_snake.boosting
		_boost_frac = clampf(player_snake.power / (min_p * 5.0), 0.05, 1.0)
	_chips.clear()
	if arena.powerup_manager != null and player_snake != null:
		var actives: Array = arena.powerup_manager.active_effects(player_snake)
		for e in actives:
			var def: PowerUpDef = e["def"]
			var dur: float = maxf(0.001, def.duration)
			_chips.append({
				"color": def.aura_color,
				"frac": clampf((float(e["until"]) - arena.powerup_manager.now()) / dur, 0.0, 1.0),
			})


func _draw() -> void:
	var vp: Vector2 = size
	# Combo ring beneath the score (§12.3 shrinking ring).
	if _combo_active:
		var cCentre: Vector2 = _score_label.position + Vector2(17.0, 60.0)
		draw_arc(cCentre, 13.0, -PI * 0.5, -PI * 0.5 + TAU * _combo_frac, 20,
			Color(1.0, 0.85, 0.3, 0.95), 3.0)
	# Boost ring, bottom-right (§3.4 power-drain ring; mobile gets a touch
	# target in Phase 10's control polish — the ring is the shared readout).
	var bCentre: Vector2 = Vector2(vp.x - 52.0 - _inset_right_bottom.x, vp.y - 52.0 - _inset_right_bottom.y)
	var bCol: Color = Color(0.35, 0.9, 1.0, 0.95) if _boost_can else Color(0.5, 0.5, 0.55, 0.8)
	draw_arc(bCentre, 22.0, -PI * 0.5, PI * 1.5, 32, Color(0.2, 0.25, 0.3, 0.8), 5.0)
	draw_arc(bCentre, 22.0, -PI * 0.5, -PI * 0.5 + TAU * _boost_frac, 32, bCol, 4.0)
	if _boosting:
		draw_circle(bCentre, 9.0, Color(0.95, 0.6, 0.15, 0.9))
	# Power-up chips, bottom-centre (§10: radial timers, aura colours).
	if not _chips.is_empty():
		var spacing: float = 52.0
		var startX: float = vp.x * 0.5 - (_chips.size() - 1) * 0.5 * spacing
		var y: float = vp.y - 46.0 - _inset_right_bottom.y
		for i in _chips.size():
			var chip: Dictionary = _chips[i]
			var col: Color = chip["color"]
			var centre: Vector2 = Vector2(startX + i * spacing, y)
			draw_circle(centre, 15.0, Color(col.r, col.g, col.b, 0.28))
			draw_arc(centre, 18.0, -PI * 0.5, PI * 1.5, 24, Color(col.r, col.g, col.b, 0.35), 2.0)
			if float(chip["frac"]) > 0.003:
				draw_arc(centre, 18.0, -PI * 0.5, -PI * 0.5 + TAU * float(chip["frac"]), 24,
					Color(col.r, col.g, col.b, 1.0), 3.0)


# --- banners + FTUE ------------------------------------------------------------

func _banner(text: String, _pos: Vector3 = Vector3.ZERO) -> void:
	_show_banner(text)


func _on_shrink(_r: float) -> void:
	_show_banner("ARENA COLLAPSING")


func _on_snake_died(killer_id: int, _victim_id: int) -> void:
	if player_snake != null and killer_id == player_snake.get_instance_id():
		_show_banner("RIVAL ABSORBED")


func _show_banner(text: String) -> void:
	_banner_label.text = text
	_banner_label.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(_banner_label, "modulate:a", 0.0, 0.5)


func _tick_ftue(delta: float) -> void:
	_hint_timer += delta
	if _hint_index < FTUE_HINTS.size() - 1 and _hint_timer >= float(FTUE_HINTS[_hint_index + 1][0]):
		_hint_index += 1
		_hint_title.text = str(FTUE_HINTS[_hint_index][1])
		_hint_body.text = str(FTUE_HINTS[_hint_index][2])
		_hint_card.visible = true
		_hint_card.modulate.a = 1.0
		var tween: Tween = create_tween()
		tween.tween_interval(3.4)
		tween.tween_property(_hint_card, "modulate:a", 0.0, 0.4)
		tween.tween_callback(func() -> void:
			if _hint_timer >= float(FTUE_HINTS[_hint_index][0]) + 3.8:
				_hint_card.visible = false)
	elif _hint_index >= FTUE_HINTS.size() - 1 and _hint_timer > float(FTUE_HINTS[_hint_index][0]) + 5.0:
		_ftue_active = false
		SaveManager.set_setting("ftue", "completed", true)
		_hint_card.visible = false
