class_name RecipeBook
extends RefCounted
## A player's known recipes. Saved in the player profile (per player, like inventory).
##
## Recipes are known by default UNLESS they appear in an unlock table below, so a new
## recipe added anywhere is never accidentally unreachable. Locked recipes are learned by:
##   - discovery: the first time a key ingredient enters your inventory
##   - quests: tutorial / story rewards (learn(id, "quest"))
##   - drifters: recruiting a profession teaches its trade recipes
##   - recipe scrolls: any "recipe_scroll_<recipe id>" item is read on pickup (merchants sell some;
##     the rare ones turn up in shipwreck lockers, sunken caches, cave chests and old mines)

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

## Secret recipes: landing one of the rarest catches teaches its own dish, and nothing else
## ever does (no scrolls are dealt for these, though you can copy yours for a friend).
const SECRET := {
	&"abyssal_ray": [&"cook_leviathan_feast"],
	&"ghost_squid": [&"cook_phosphor_broth"],
	&"lightning_eel": [&"smoke_storm_eel"],
}

## Copying a recipe you know onto a scroll (to give, trade or sell): the parchment.
const COPY_COST := [[&"shore_wheat", 2]]

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

## Only ever found as scrolls (old mines, wrecks, flooded sumps): listed so they start locked.
const FOUND_ONLY := [&"furnace_fine_brass", &"place_stone_well"]

## The old brass mines' secret: one scroll in every miner's strongbox.
const MINE_SCROLL := &"furnace_fine_brass"

## The rare scrolls dealt out (a shuffled deck per world) to wreck lockers, sunken caches, and
## now and then a cave chest or a Mud-Claw hoard. Fine sea-brass is the old mines' own secret.
const FOUND_SCROLLS := [&"place_stone_well", &"cook_bouillabaisse", &"smoke_fish_ration",
	&"brew_chicory_coffee", &"place_storage_crate", &"place_salt_pan", &"place_barber_mirror"]

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
		for r in FOUND_ONLY:
			_locked[r] = true
		for list in SECRET.values():
			for r in list:
				_locked[r] = true
	return _locked


static func scroll_item(recipe_id: StringName) -> StringName:
	return StringName(SCROLL_PREFIX + String(recipe_id))


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
		if knows(rid):
			return []                     # already in the book: keep the scroll to give or trade
		if inv != null:
			inv.remove_item(item_id, 1)   # the scroll is read and kept in the book
		return [rid] if learn(rid, "scroll") else []
	var out: Array = []
	if DISCOVERY.has(item_id):
		out.append_array(learn_all(DISCOVERY[item_id], "discovery"))
	if SECRET.has(item_id):
		out.append_array(learn_all(SECRET[item_id], "secret"))
	return out


## Can this recipe be copied onto a scroll? (one you know that others have to find)
func can_copy(recipe_id: StringName) -> bool:
	return is_lockable(recipe_id) and known.has(recipe_id)


## Copy a known recipe onto a scroll for another player. Costs COPY_COST. True on success.
func copy_scroll(recipe_id: StringName, inv: Inventory) -> bool:
	if inv == null or not can_copy(recipe_id):
		return false
	for c: Array in COPY_COST:
		if inv.get_item_count(c[0]) < int(c[1]):
			return false
	register_scroll_items()
	var item := scroll_item(recipe_id)
	if not ItemDB.has_item(item):
		return false
	for c: Array in COPY_COST:
		inv.remove_item(c[0], int(c[1]))
	if inv.add_item(item, 1) > 0:
		for c: Array in COPY_COST:
			inv.add_item(c[0], int(c[1]))   # no room: give the parchment back
		return false
	return true


## How a locked recipe is learned (for the Recipe Book's hints).
static func source_of(recipe_id: StringName) -> String:
	for k: StringName in SECRET:
		if SECRET[k].has(recipe_id):
			var it: ItemDef = ItemDB.get_item(k)
			return "Secret: land a %s" % (it.name if it != null else String(k))
	for k: StringName in DISCOVERY:
		if DISCOVERY[k].has(recipe_id):
			var it: ItemDef = ItemDB.get_item(k)
			return "Discover: get your hands on %s" % (it.name if it != null else String(k))
	for prof: int in PROFESSION:
		if PROFESSION[prof].has(recipe_id):
			return "Taught by a drifter"
	if recipe_id == MINE_SCROLL:
		return "A scroll in an old brass mine"
	if FOUND_SCROLLS.has(recipe_id) or FOUND_ONLY.has(recipe_id):
		return "A rare scroll: wrecks, sunken caches, caves"
	if REWARD_ONLY.has(recipe_id):
		return "A quest reward or a merchant's scroll"
	return "Known from the start"


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
