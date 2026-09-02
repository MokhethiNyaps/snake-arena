extends Control
## §12.2 Game-over panel — SCORE/POWER/LENGTH/RANK/TIME/ABSORBED with 0.6 s
## count-up tweens, REVIVE (rewarded, hidden unless actually available and
## revives_used < 1), ×2 DOUBLE COINS (rewarded), PLAY AGAIN (never smaller
## than 80% of rewarded buttons, never disabled/delayed), MAIN MENU.
## NEW BEST badge + celebration. Talks to: run director (group), AdManager.


const REVIVE_SHARE: float = 0.65   # §45.5: revive restores 65% of death power

var stats: Dictionary = {}
var _revive_used: bool = false
var _director: Node = null
var _rows: Dictionary = {}
var _best_badge: Label = null
var _revive_btn: Button = null
var _coins_doubled: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	stats = get_meta("stats", {})
	_revive_used = not bool(get_meta("revive_available", false))
	_director = get_tree().get_first_node_in_group("run_director")
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-230, -290)
	col.custom_minimum_size = Vector2(460, 0)
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var title: Label = _label(42, Color(0.95, 0.45, 0.45))
	title.text = "RUN OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_best_badge = _label(22, Color(1.0, 0.85, 0.3))
	_best_badge.text = "NEW BEST!"
	_best_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_badge.visible = bool(stats.get("new_best", false))
	col.add_child(_best_badge)
	# Stats rows (values count up over 0.6 s).
	for key in [["score", "SCORE"], ["power", "POWER"], ["length", "LENGTH"],
			["rank", "RANK"], ["time", "TIME"], ["absorbed", "ABSORBED"]]:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_l: Label = _label(20, Color(0.6, 0.7, 0.8))
		name_l.text = str(key[1])
		name_l.custom_minimum_size = Vector2(150, 26)
		var val_l: Label = _label(24, Color(1.0, 1.0, 1.0))
		val_l.text = "0"
		val_l.name = "Val" + str(key[0])
		row.add_child(name_l)
		row.add_child(val_l)
		col.add_child(row)
		_rows[str(key[0])] = val_l
		_count_up(val_l, float(stats.get(key[0], 0.0)), str(key[0]))
	# Buttons — PLAY AGAIN is never smaller than 80% of the rewarded pair
	# and is never disabled (§12.2 button-order rules).
	_revive_btn = _button("▶  REVIVE — WATCH AD", _on_revive, 26, Color(0.25, 0.85, 0.45))
	_revive_btn.name = "BtnRevive"
	col.add_child(_revive_btn)
	var again_b: Button = _button("PLAY AGAIN", _on_play_again, 24, Color(0.35, 0.65, 0.95))
	again_b.name = "BtnPlayAgain"
	col.add_child(again_b)
	col.add_child(_button("×2 DOUBLE COINS — WATCH AD", _on_double_coins, 20, Color(0.85, 0.7, 0.3)))
	var go_menu_b: Button = _button("MAIN MENU", _on_menu, 20, Color(0.7, 0.7, 0.75))
	go_menu_b.name = "BtnGameOverMenu"
	col.add_child(go_menu_b)
	# §12.2: hide the revive button entirely when no ad is loadable or the
	# single revive was spent — never show a button that fails.
	var revive_ok: bool = not _revive_used \
		and AdManager.is_available(AdPlacementId.ID.REVIVE) \
		and AdManager.can_show(AdPlacementId.ID.REVIVE).get("allowed", false)
	_revive_btn.visible = revive_ok
	Analytics.track(&"run_ended", {
		"score": stats.get("score", 0.0), "power": stats.get("power", 0.0),
		"length": stats.get("length", 0), "rank": stats.get("rank", 0),
		"duration_s": stats.get("time_s", 0.0),
		"absorbs": stats.get("absorbed", 0), "revived": false,
	})


func _label(size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, handler: Callable, size: int, tint: Color) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", tint)
	b.custom_minimum_size = Vector2(460, 54)
	b.pressed.connect(handler)
	return b


func _count_up(label: Label, target: float, key: String) -> void:
	# §12.2: numbers count up over 0.6 s (tween), they do not just appear.
	if key == "rank":
		label.text = "#%d of %d" % [int(target), int(stats.get("field_size", 9))]
		return
	if key == "time":
		var t: int = int(target)
		label.text = "%02d:%02d" % [t / 60, t % 60]
		return
	var state: Array = [0.0]
	var tween: Tween = create_tween()
	tween.tween_method(func(v: float) -> void:
		label.text = _fmt(v), 0.0, target, 0.6)


func _fmt(v: float) -> String:
	var i: int = int(round(v))
	var s: String = str(i)
	var out: String = ""
	var digits: int = 0
	for c_idx in range(s.length() - 1, -1, -1):
		out = s[c_idx] + out
		digits += 1
		if digits % 3 == 0 and c_idx > 0:
			out = "," + out
	return out


func _on_revive() -> void:
	# §45.5: revive grants ONLY on SHOWN_COMPLETED — never on failure.
	_revive_btn.disabled = true
	var result: AdResult = await AdManager.request_ad(AdPlacementId.ID.REVIVE)
	_revive_btn.disabled = false
	if result.rewarded:
		_revive_used = true
		if _director != null:
			_director.call("do_revive", stats.get("power", 2.0) * REVIVE_SHARE)
		UIManager.pop_screen()
	else:
		_show_toast("No ad available right now — PLAY AGAIN is ready.")


func _on_play_again() -> void:
	# §45.3 INTER_RUN: between runs, on tapping PLAY AGAIN. The pacer blocks
	# it before run #3 / 120 s / caps; Null provider resolves instantly and
	# the game stays fully playable (§45.1).
	await AdManager.request_ad(AdPlacementId.ID.INTER_RUN)
	if _director != null:
		_director.call("start_run")


func _on_double_coins() -> void:
	if _coins_doubled:
		return
	var result: AdResult = await AdManager.request_ad(AdPlacementId.ID.DOUBLE_COINS)
	if result.rewarded:
		_coins_doubled = true
		if _director != null:
			_director.call("grant_double_coins")
		_show_toast("Coins doubled!")
	else:
		_show_toast("No ad available right now.")


func _on_menu() -> void:
	if _director != null:
		_director.call("quit_to_menu")


var _toast: Label = null


func _show_toast(text: String) -> void:
	if _toast != null and is_instance_valid(_toast):
		_toast.queue_free()
	_toast = _label(18, Color(1.0, 0.9, 0.7))
	_toast.text = text
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(-200, -120)
	_toast.custom_minimum_size = Vector2(400, 24)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_toast)
