class_name DebugPanel
extends CanvasLayer
## §20/§45.7 — The debug AD panel: mock knobs (fill rate, latency, forced
## outcome, auto-close), force-trigger buttons, last-result readout, and the
## §45.4 decision log ("Log every decision ... to the debug ad panel").
##
## Toggled with F3 (§20) via InputManager.debug_toggle_pressed() — this
## script never touches Input directly (InputManager owns that, §7).
##
## Phase 4 ships the Ads panel; the Perf/Player/AI/Spawn panels join the
## full debug mode in later phases (§20 lists them all).
##
## Owns: its controls + the wiring to AdManager/AdProviderMock.
## Does NOT own: ad logic (AdManager), input (InputManager).
## Talks to: AdManager (signals + request_ad), the mock provider (knobs).

const LOG_LINES: int = 16

@onready var root: PanelContainer = $Root

var _built: bool = false
var _fill_slider: HSlider = null
var _latency_slider: HSlider = null
var _outcome_option: OptionButton = null
var _auto_close_spin: SpinBox = null
var _result_label: Label = null
var _log_label: RichTextLabel = null
var _lines: Array[String] = []

## Last resolved result code (verify harness reads this).
var last_result_code: int = -1
var last_rewarded: bool = false


func _ready() -> void:
	_build_ui()
	# Connect lazily on the first process frame: AdManager's _ready adds
	# this panel, so other autoloads (InputManager is #8) may not exist yet
	# during our own _ready.
	set_process(true)


func _process(_delta: float) -> void:
	if not _built:
		_built = true
		_connect_manager()
		_sync_knobs()
	if InputManager.debug_toggle_pressed():
		root.visible = not root.visible


func _connect_manager() -> void:
	AdManager.decision_logged.connect(_on_decision_logged)
	AdManager.ad_started.connect(func(p: int) -> void: _append("AD STARTED %s" % AdPlacementId.name_of(p)))
	AdManager.ad_finished.connect(_on_ad_finished)
	AdManager.ad_reward_granted.connect(func(p: int, r: StringName) -> void:
		_append("REWARD GRANTED %s (%s)" % [AdPlacementId.name_of(p), r]))
	AdManager.ad_failed.connect(func(p: int, reason: String) -> void:
		_append("AD FAILED %s (%s)" % [AdPlacementId.name_of(p), reason]))
	if AdManager.provider != null and AdManager.provider.get_script() != null:
		_append("panel ready — provider: %s" % AdManager.provider.get_script().get_global_name())
	else:
		_append("panel ready — provider: none")


func _build_ui() -> void:
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	root.add_child(vbox)
	var title: Label = Label.new()
	title.text = "AD DEBUG (F3)"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	# Fill rate 0-100%.
	var fill_row: HBoxContainer = HBoxContainer.new()
	fill_row.add_child(_make_caption("Fill %"))
	_fill_slider = HSlider.new()
	_fill_slider.min_value = 0.0
	_fill_slider.max_value = 100.0
	_fill_slider.step = 1.0
	_fill_slider.custom_minimum_size = Vector2(180.0, 0.0)
	_fill_slider.value_changed.connect(_on_fill_changed)
	fill_row.add_child(_fill_slider)
	vbox.add_child(fill_row)
	# Latency 0-8 s.
	var latency_row: HBoxContainer = HBoxContainer.new()
	latency_row.add_child(_make_caption("Latency s"))
	_latency_slider = HSlider.new()
	_latency_slider.min_value = 0.0
	_latency_slider.max_value = 8.0
	_latency_slider.step = 0.1
	_latency_slider.custom_minimum_size = Vector2(180.0, 0.0)
	_latency_slider.value_changed.connect(_on_latency_changed)
	latency_row.add_child(_latency_slider)
	vbox.add_child(latency_row)
	# Forced outcome.
	var outcome_row: HBoxContainer = HBoxContainer.new()
	outcome_row.add_child(_make_caption("Outcome"))
	_outcome_option = OptionButton.new()
	for i in AdProviderMock.ForcedOutcome.size():
		_outcome_option.add_item(AdProviderMock.ForcedOutcome.keys()[i], i)
	_outcome_option.item_selected.connect(_on_outcome_changed)
	outcome_row.add_child(_outcome_option)
	vbox.add_child(outcome_row)
	# Auto-close seconds.
	var autoclose_row: HBoxContainer = HBoxContainer.new()
	autoclose_row.add_child(_make_caption("Auto-close s"))
	_auto_close_spin = SpinBox.new()
	_auto_close_spin.min_value = 0.0
	_auto_close_spin.max_value = 30.0
	_auto_close_spin.step = 0.5
	_auto_close_spin.value = 5.0
	_auto_close_spin.value_changed.connect(_on_auto_close_changed)
	autoclose_row.add_child(_auto_close_spin)
	vbox.add_child(autoclose_row)
	# Trigger buttons.
	var btn_row: HBoxContainer = HBoxContainer.new()
	var btn_inter: Button = Button.new()
	btn_inter.text = "▶ Interstitial"
	btn_inter.pressed.connect(trigger_interstitial)
	btn_row.add_child(btn_inter)
	var btn_reward: Button = Button.new()
	btn_reward.text = "★ Rewarded"
	btn_reward.pressed.connect(trigger_rewarded)
	btn_row.add_child(btn_reward)
	var btn_banner: Button = Button.new()
	btn_banner.text = "▬ Banner"
	btn_banner.pressed.connect(trigger_banner)
	btn_row.add_child(btn_banner)
	vbox.add_child(btn_row)
	# Last result.
	_result_label = Label.new()
	_result_label.text = "last result: —"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_result_label)
	# Decision log.
	var log_title: Label = Label.new()
	log_title.text = "Decision log:"
	vbox.add_child(log_title)
	_log_label = RichTextLabel.new()
	_log_label.custom_minimum_size = Vector2(420.0, 180.0)
	_log_label.scroll_following = true
	_log_label.bbcode_enabled = true
	vbox.add_child(_log_label)


func _make_caption(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(110.0, 0.0)
	return l


# --- knob handlers (write through to the mock provider) -------------------

func _mock() -> AdProviderMock:
	return AdManager.provider as AdProviderMock


func _sync_knobs() -> void:
	var mock: AdProviderMock = _mock()
	if mock == null:
		return
	_fill_slider.set_value_no_signal(roundf(mock.fill_rate * 100.0))
	_latency_slider.set_value_no_signal(mock.latency_seconds)
	_outcome_option.select(int(mock.forced_outcome))
	_auto_close_spin.set_value_no_signal(mock.auto_close_seconds)


func _on_fill_changed(v: float) -> void:
	var mock: AdProviderMock = _mock()
	if mock != null:
		mock.fill_rate = v / 100.0


func _on_latency_changed(v: float) -> void:
	var mock: AdProviderMock = _mock()
	if mock != null:
		mock.latency_seconds = v


func _on_outcome_changed(idx: int) -> void:
	var mock: AdProviderMock = _mock()
	if mock != null:
		mock.forced_outcome = idx


func _on_auto_close_changed(v: float) -> void:
	var mock: AdProviderMock = _mock()
	if mock != null:
		mock.auto_close_seconds = v


# --- trigger handlers (the same code path the buttons use) ----------------

func trigger_interstitial() -> void:
	await _trigger(AdPlacementId.ID.INTER_RUN, false)


func trigger_rewarded() -> void:
	await _trigger(AdPlacementId.ID.REVIVE, true)


func _trigger(placement: int, _rewarded: bool) -> void:
	_result_label.text = "showing %s..." % AdPlacementId.name_of(placement)
	var result: AdResult = await AdManager.request_ad(placement, true)
	_show_result(placement, result)


func trigger_banner() -> void:
	if AdManager.get_banner_height_px() > 0:
		AdManager.hide_banner()
		_append("banner hidden")
	else:
		AdManager.show_banner(0)
		_append("banner shown")


func _show_result(placement: int, result: AdResult) -> void:
	last_result_code = result.code
	last_rewarded = result.rewarded
	_result_label.text = "last result: %s → %s%s" % [
		AdPlacementId.name_of(placement), AdResult.Code.keys()[result.code],
		"  ★REWARDED" if result.rewarded else ""]


func _on_ad_finished(placement: int, result: AdResult) -> void:
	_show_result(placement, result)


func _on_decision_logged(entry: String) -> void:
	_append(entry)


func _append(line: String) -> void:
	_lines.append(line)
	if _lines.size() > LOG_LINES:
		_lines.pop_front()
	if _log_label != null:
		_log_label.text = "\n".join(_lines)
