class_name RecipeBook
extends RefCounted
## A player's known recipes. Saved in the player profile (per player, like inventory).
##
## Recipes are known by default UNLESS they appear in an unlock table below, so a new
## recipe added anywhere is never accidentally unreachable. Locked recipes are learned by:
##   - discovery: the first time a key ingredient enters your inventory
##   - quests: tutorial / story rewards (learn(id, "quest"))
##   - drifters: recruiting a profession teaches its trade recipes
##   - recipe scrolls: any "recipe_scroll_<recipe id>" item is read on pickup (merchants sell some)

signal recipe_learned(recipe_id: StringName, source: String)

## First time you hold the item -> learn these.
const DISCOVERY := {
	&"silver_mackerel": [&"cook_roasted_mackerel", &"place_sea_barrel"],
	&"tidepool_flounder": [&"cook_roasted_flounder", &"place_sea_barrel"],
	&"cliff_salmon": [&"smoke_salmon_strips", &"place_smokehouse"],
	&"brine_oyster": [&"cook_clam_chowder", &"place_hearth_pot"],
	&"shore_crab": [&"cook_glazed_crab"],
	&"shore_wheat": [&"cook_hardtack", &"craft_parchment_chart"],
	&"samphire": [&"cure_pickled_samphire"],
	&"kelp_frond": [&"brew_kelp_tea", &"place_brewery"],
	&"sea_salt": [&"place_saltery"],
	&"sea_wool": [&"craft_backpack_driftwood", &"forge_oilskin_coat"],
	&"sea_brass_ingot": [&"craft_ocean_caster_rod", &"forge_rusty_cutlass", &"forge_harpoon_lance"],
	&"ghost_squid": [&"craft_hydrographic_chart"],
}

## Taught by recruiting a drifter of this profession (DrifterDef.Profession values).
const PROFESSION := {
	0: [&"place_crab_pot", &"place_sea_barrel", &"craft_ocean_caster_rod"],              # FISHER
	1: [&"place_salt_pan", &"cure_pickled_samphire"],                                     # FARMER
	2: [&"place_storage_crate", &"place_barber_mirror"],                                  # CARPENTER
	3: [&"place_smokehouse", &"smoke_fish_ration", &"cook_clam_chowder", &"cook_bouillabaisse"],  # SMOKER_CHEF
	4: [&"brew_kelp_tea"],                                                                # LAMPLIGHTER
	5: [&"brew_chicory_coffee", &"craft_parchment_chart"],                                # TRADER
}

## Only obtainable as rewards or scrolls (listed so they start locked).
const REWARD_ONLY := [&"place_crab_pot", &"place_salt_pan", &"smoke_fish_ration", &"cook_bouillabaisse",
	&"brew_chicory_coffee", &"place_barber_mirror", &"place_storage_crate"]

## Scrolls the merchants may carry.
const MERCHANT_SCROLLS := [&"cook_bouillabaisse", &"brew_chicory_coffee", &"cook_glazed_crab", &"place_barber_mirror"]

const SCROLL_PREFIX := "recipe_scroll_"

static var _locked: Dictionary = {}

var known := {}            # recipe id -> true (locked recipes the player has learned)


static func locked_ids() -> Dictionary:
	if _locked.is_empty():
		for list in DISCOVERY.values():
			for r in list:
				_locked[r] = true
		for list in PROFESSION.values():
			for r in list:
				_locked[r] = true
		for r in REWARD_ONLY:
			_locked[r] = true
	return _locked


static func is_lockable(recipe_id: StringName) -> bool:
	return locked_ids().has(recipe_id)


func knows(recipe_id: StringName) -> bool:
	return known.has(recipe_id) or not is_lockable(recipe_id)


## Returns true if this was new.
func learn(recipe_id: StringName, source: String = "") -> bool:
	Placeables.register_builtin()
	if knows(recipe_id) or not RecipeDB.has_recipe(recipe_id):
		return false
	known[recipe_id] = true
	recipe_learned.emit(recipe_id, source)
	return true


func learn_all(ids: Array, source: String) -> Array:
	var out := []
	for r in ids:
		if learn(StringName(r), source):
			out.append(r)
	return out


## Hook to Inventory.item_added. Returns recipes learned.
func on_item_acquired(item_id: StringName, inv: Inventory = null) -> Array:
	var s := String(item_id)
	if s.begins_with(SCROLL_PREFIX):
		var rid := StringName(s.trim_prefix(SCROLL_PREFIX))
		if inv != null:
			inv.remove_item(item_id, 1)   # the scroll is read and kept in the book
		return [rid] if learn(rid, "scroll") else []
	if DISCOVERY.has(item_id):
		return learn_all(DISCOVERY[item_id], "discovery")
	return []


func on_drifter_recruited(profession: int) -> Array:
	return learn_all(PROFESSION.get(profession, []), "drifter")


## Recipes for a station, split into what the player knows and how many are still hidden.
func recipes_for(station: StringName) -> Dictionary:
	Placeables.register_builtin()
	RecipeDB.init_db()
	var known_list: Array[RecipeDef] = []
	var hidden := 0
	for r: RecipeDef in RecipeDB.get_recipes_for_station(station):
		if knows(r.id):
			known_list.append(r)
		else:
			hidden += 1
	return {"known": known_list, "hidden": hidden}


## Registers a readable scroll item for every lockable recipe (call once at startup).
static func register_scroll_items() -> void:
	Placeables.register_builtin()
	RecipeDB.init_db()
	ItemDB.init_db()
	for rid: StringName in locked_ids():
		var item := StringName(SCROLL_PREFIX + String(rid))
		if ItemDB.has_item(item):
			continue
		var r: RecipeDef = RecipeDB.get_recipe(rid)
		if r == null:
			continue
		var def := ItemDef.new(item, "Recipe: " + r.name, ItemDef.Category.BLUEPRINT, 5, -1, PackedStringArray(["recipe", "scroll"]))
		def.value_brass = 18
		ItemDB.register_item(def)


func serialize() -> Array:
	var out := []
	for r in known:
		out.append(String(r))
	return out


func deserialize(data: Variant) -> void:
	known.clear()
	if data is Array:
		for r in data:
			known[StringName(r)] = true
