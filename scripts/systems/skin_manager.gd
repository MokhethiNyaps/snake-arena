class_name SkinManager
extends Node
## §16 skins — catalogue, ownership, purchase, equip. COSMETIC ONLY.
##
## Owns: the skin catalogue (resources/skins/*.tres) + purchase/equip rules.
## Does NOT own: persistence (SaveManager) or the visual application —
##        SnakeBody.apply_skin() renders; this manager just decides.
## Talks to: SaveManager, SnakeBody (visual layer only), Analytics.
## §16 invariant: SnakeController contains ZERO skin code. Enforced by
## test_meta.gd (static scan of snake_controller.gd for "skin").

const SKINS_DIR: String = "res://resources/skins"

var _defs: Array[SkinDef] = []


func _ready() -> void:
	_load_catalogue()


func _load_catalogue() -> void:
	_defs.clear()
	var dir: DirAccess = DirAccess.open(SKINS_DIR)
	if dir == null:
		push_warning("[SkinManager] skins directory missing.")
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var def: SkinDef = load(SKINS_DIR + "/" + file_name) as SkinDef
			if def != null:
				_defs.append(def)
		file_name = dir.get_next()
	dir.list_dir_end()
	_defs.sort_custom(func(a: SkinDef, b: SkinDef) -> bool: return a.unlock_level < b.unlock_level)
	if _defs.is_empty():
		push_warning("[SkinManager] no skin definitions found.")


## Ordered by unlock level (menu grid order).
func get_all() -> Array[SkinDef]:
	return _defs


func get_def(id: String) -> SkinDef:
	for d in _defs:
		if d.id == id:
			return d
	return null


func is_owned(id: String) -> bool:
	return SaveManager.get_owned_skins().has(id)


func get_equipped_id() -> String:
	return SaveManager.get_equipped_skin()


## Level gate satisfied AND not already owned.
func can_buy(def: SkinDef) -> bool:
	return def != null and not is_owned(def.id) \
		and SaveManager.get_level() >= def.unlock_level


## Purchase: level gate + coin spend (§16 — coins are cosmetic-only).
func buy(def: SkinDef) -> bool:
	if not can_buy(def):
		return false
	if def.price > 0 and not SaveManager.try_spend(def.price, &"skin_buy"):
		return false
	SaveManager.own_skin(def.id)
	Analytics.track(&"skin_owned", {"skin": def.id, "price": def.price})
	return true


## Equip only what is owned. Returns the equipped id (unchanged on failure).
func equip(id: String) -> bool:
	if not is_owned(id) or get_def(id) == null:
		return false
	SaveManager.set_equipped_skin(id)
	Analytics.track(&"skin_equipped", {"skin": id})
	return true


## Applies the equipped skin to a snake's VISUAL layer (SnakeBody). Called by
## boot at run start; SnakeController is never involved.
func apply_equipped_to(body: SnakeBody) -> void:
	if body == null:
		return
	var def: SkinDef = get_def(get_equipped_id())
	if def == null:
		def = get_def("classic")
	if def == null:
		return
	body.apply_skin(def.body_colour, def.emission_colour, def.emission_energy, def.head_colour)


func trail_colour() -> Color:
	var def: SkinDef = get_def(get_equipped_id())
	return def.trail_colour if def != null else Color(0.4, 0.95, 1.0)
