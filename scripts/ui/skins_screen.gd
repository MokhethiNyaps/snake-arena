extends Control
## §16 skins screen — buy with coins, equip what you own. COSMETIC ONLY.
## Talks to: run director (SkinManager child), SaveManager (wallet/level),
##           UIManager (back).

const COLS: int = 4

var _director: Node = null
var _skins: SkinManager = null
var _grid: GridContainer = null
var _wallet: Label = null
var _status: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_director = get_tree().get_first_node_in_group("run_director")
	_skins = _director._skins if _director != null else null
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-300, -270)
	col.custom_minimum_size = Vector2(600, 0)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var title: Label = _label(38, Color(0.55, 0.95, 1.0))
	title.text = "SKINS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_wallet = _label(18, Color(1.0, 0.85, 0.3))
	_wallet.name = "LblWallet"
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_wallet)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	col.add_child(_grid)
	_status = _label(16, Color(0.8, 0.8, 0.85))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	var back: Button = Button.new()
	back.name = "BtnBack"
	back.text = "BACK"
	back.add_theme_font_size_override("font_size", 22)
	back.custom_minimum_size = Vector2(200, 48)
	col.add_child(back)
	back.pressed.connect(_on_back)
	_rebuild()


func _rebuild() -> void:
	for c in _grid.get_children():
		c.queue_free()
	if _skins == null:
		return
	_wallet.text = "Coins %d    Level %d" % [SaveManager.get_coins(), SaveManager.get_level()]
	var equipped: String = _skins.get_equipped_id()
	for def in _skins.get_all():
		var tile: Button = Button.new()
		tile.name = "Skin" + def.id
		tile.toggle_mode = false
		tile.custom_minimum_size = Vector2(140, 150)
		tile.add_theme_font_size_override("font_size", 15)
		var state: String
		if def.id == equipped:
			state = "EQUIPPED"
		elif _skins.is_owned(def.id):
			state = "OWNED — tap to equip"
		elif SaveManager.get_level() < def.unlock_level:
			state = "Unlocks at level %d" % def.unlock_level
		else:
			state = ("FREE" if def.price == 0 else "%d coins" % def.price) + " — tap to buy"
		tile.text = "%s\n\n%s" % [def.display_name, state]
		tile.modulate = Color(1, 1, 1) if def.id != equipped else Color(0.7, 1.0, 0.8)
		tile.pressed.connect(_on_tile.bind(def))
		_grid.add_child(tile)


func _on_tile(def: SkinDef) -> void:
	_status.text = ""
	if def.id == _skins.get_equipped_id():
		return
	if _skins.is_owned(def.id):
		if _skins.equip(def.id):
			_status.text = "%s equipped." % def.display_name
		_rebuild()
		return
	if not _skins.can_buy(def):
		_status.text = "Reach level %d first." % def.unlock_level
		return
	if not _skins.buy(def):
		_status.text = "Not enough coins (%d needed)." % def.price
		return
	_skins.equip(def.id)
	_status.text = "%s unlocked and equipped!" % def.display_name
	_rebuild()


func _on_back() -> void:
	UIManager.pop_screen()


func _label(size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
