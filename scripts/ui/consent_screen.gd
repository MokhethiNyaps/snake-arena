extends Control
## §45.8 PrivacyConsent — first-launch consent (web + mobile). Purely
## informational + ACCEPT/DECLINE: what data is collected, Privacy/Terms
## links (from ads.tres — URLs are HUMAN-filled), and the note that
## declining keeps the game fully playable, just ad-free.
## Talks to: ConsentManager (state), UIManager (pop), OS (links).

var _status: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var cfg: AdConfig = load("res://resources/config/ads.tres") as AdConfig
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-280, -270)
	col.custom_minimum_size = Vector2(560, 0)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var title: Label = _label(34, Color(0.55, 0.95, 1.0))
	title.text = "WELCOME TO COILCLASH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var body: Label = _label(17, Color(0.82, 0.87, 0.93))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 150)
	body.text = "This game may show ads and collects anonymous gameplay analytics (events like runs, scores and ad outcomes) to keep the game fair and improve it.\n\nYou can decline: the game stays fully playable — it just runs ad-free.\n\nYou can change this any time in SETTINGS → AD PRIVACY."
	col.add_child(body)
	# Links (§45.8): only clickable once the human fills the URLs (ads.tres).
	if cfg.privacy_policy_url != "":
		col.add_child(_link_button("PRIVACY POLICY", cfg.privacy_policy_url))
	else:
		var pending: Label = _label(14, Color(0.55, 0.6, 0.66))
		pending.text = "(Privacy Policy URL pending — site owner, fill ads.tres)"
		pending.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(pending)
	if cfg.terms_url != "":
		col.add_child(_link_button("TERMS OF SERVICE", cfg.terms_url))
	var accept: Button = Button.new()
	accept.name = "BtnAccept"
	accept.text = "ACCEPT ADS + ANALYTICS"
	accept.add_theme_font_size_override("font_size", 20)
	accept.custom_minimum_size = Vector2(560, 52)
	col.add_child(accept)
	accept.pressed.connect(_on_accept)
	var decline: Button = Button.new()
	decline.name = "BtnDecline"
	decline.text = "DECLINE ADS (game stays fully playable)"
	decline.add_theme_font_size_override("font_size", 17)
	decline.custom_minimum_size = Vector2(560, 44)
	col.add_child(decline)
	decline.pressed.connect(_on_decline)
	_status = _label(14, Color(0.6, 0.8, 0.6))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)


func _on_accept() -> void:
	ConsentManager.set_consent(ConsentManager.ConsentState.GRANTED, ConsentManager.CONSENT_VERSION)
	_pop()


func _on_decline() -> void:
	ConsentManager.set_consent(ConsentManager.ConsentState.DENIED, ConsentManager.CONSENT_VERSION)
	_pop()


func _pop() -> void:
	# Guard: boot's post-consent flow may have already cleared this screen
	# (start_run → clear_screens). Popping unconditionally would pop the
	# NEW top screen (the HUD) and free it — probe-caught in the UI harness.
	if UIManager.get_current_screen() == self:
		UIManager.pop_screen()


func _link_button(text: String, url: String) -> Button:
	var b: Button = Button.new()
	b.text = text + " ↗"
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(560, 38)
	b.pressed.connect(func() -> void: OS.shell_open(url))
	return b


func _label(size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
