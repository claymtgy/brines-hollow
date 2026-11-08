class_name Placeables
extends RefCounted
## Built-in placeable entity types: their items, build costs and recipes.
##
## Every placeable can be obtained two ways:
##   * Blueprints tool (3): Q/E cycles past the voxel prefabs into "furniture"; placing pays
##     the build cost below straight from the inventory (survival, no crafting UI needed).
##   * As an item (picked up, crafted at a workbench, traded): hold it in the hotbar with the
##     item tool (5) and place it; the item itself is consumed.
##
## Other systems add their own types with EntityManager.register_type(); call
## Placeables.add_item(...) too if the type should be buildable/pick-up-able.

## type -> [display name, build cost {item: count}, placement rule, item stack size]
const BUILTIN := {
	&"crab_pot":        ["Wicker Crab Pot",        {&"driftwood": 3, &"kelp_frond": 4}, &"intertidal", 10],
	&"salt_pan":        ["Clay Salt Pan",          {&"stone": 4, &"sand": 4},           &"intertidal", 10],
	&"sea_barrel":      ["Watertight Sea Barrel",  {&"wood_plank": 6, &"kelp_frond": 2}, &"ground", 10],
	&"storage_crate":   ["Storage Crate",          {&"wood_plank": 6},                  &"ground", 10],
	&"driftwood_chest": ["Driftwood Chest",        {&"driftwood": 6},                   &"ground", 10],
	&"fisher_bed":      ["Fisher's Bunk",          {&"wood_plank": 8, &"leaves": 6},    &"ground", 5],
	&"barber_mirror":   ["Barber's Looking Glass", {&"wood_plank": 3, &"sea_glass": 2}, &"ground", 5],
	&"workbench":       ["Carpentry Workbench",    {&"driftwood": 8},                   &"ground", 5],
	&"campfire":        ["Campfire",               {&"driftwood": 4, &"stone": 4},      &"ground", 5],
	&"hearth_pot":      ["Hearth Stew Pot",        {&"cobblestone": 6, &"wood_plank": 2}, &"ground", 5],
	&"smokehouse":      ["Fisher's Smokehouse",    {&"wood_plank": 12, &"cobblestone": 6}, &"ground", 5],
	&"saltery":         ["Brine Saltery",          {&"wood_plank": 6, &"stone": 4},     &"ground", 5],
	&"brewery":         ["Coastal Teahouse",       {&"wood_plank": 6, &"sea_glass": 2}, &"ground", 5],
	&"furnace":         ["Smelting Furnace",       {&"stone": 8, &"driftwood": 4},      &"ground", 5],
	&"anvil":           ["Blacksmith's Anvil",     {&"iron_ingot": 2, &"stone": 4},     &"ground", 5],
	&"pine_sapling":    ["Pine Sapling",           {&"leaves": 2, &"driftwood": 1},     &"soil", 20],
	&"feed_trough":     ["Livestock Trough",       {&"wood_plank": 6, &"stone": 2},     &"ground", 5],
	&"poultry_coop":    ["Shore Poultry Coop",     {&"wood_plank": 8, &"driftwood": 4}, &"ground", 5],
	&"lantern_post":    ["Kelp-Oil Lantern Post",  {&"driftwood": 3, &"kelp_frond": 2, &"stone": 1}, &"ground", 10],
	&"pen_gate":        ["Latched Pen Gate",       {&"wood_plank": 6, &"driftwood": 2}, &"ground", 10],
	&"live_trap":       ["Live-Capture Trap",      {&"driftwood": 4, &"wood_plank": 2, &"kelp_frond": 2}, &"ground", 5],
	&"dog_kennel":      ["Guard Dog Kennel",       {&"wood_plank": 10, &"driftwood": 4, &"silver_mackerel": 2}, &"ground", 1],
	&"cat_basket":      ["Dock Cat's Basket",      {&"kelp_frond": 6, &"driftwood": 2, &"silver_mackerel": 1}, &"ground", 1],
	&"scarecrow":       ["Oilskin Scarecrow",      {&"driftwood": 4, &"leaves": 4, &"wood_plank": 2}, &"ground", 5],
	&"pantry_barrel":   ["Sealed Pantry Barrel",   {&"wood_plank": 6, &"kelp_frond": 2, &"stone": 1}, &"ground", 10],
}

const TroughEntityClass := preload("res://scripts/entities/trough_entity.gd")
const CoopEntityClass := preload("res://scripts/entities/coop_entity.gd")

const BAIT_ITEMS := [&"kelp_frond", &"silver_mackerel", &"tidepool_flounder", &"shore_crab"]

static var _done := false
static var _costs := {}       # type -> cost dictionary
static var _order: Array = [] # types in blueprint-cycle order


static func register_builtin() -> void:
	if _done:
		return
	_done = true
	ItemDB.init_db()
	RecipeDB.init_db()
	var stations := {
		&"workbench": "Carpentry Workbench", &"campfire": "Campfire Skillet",
		&"hearth_pot": "Hearth Stew Pot", &"smokehouse": "Fisher's Smokehouse",
		&"saltery": "Brine Saltery", &"brewery": "Coastal Teahouse",
		&"furnace": "Smelting Furnace", &"anvil": "Blacksmith's Anvil",
	}
	for tag: StringName in stations:
		var name: String = stations[tag]
		EntityManager.register_type(tag, func(c: Vector3i) -> WorldEntity: return StationEntity.new(tag, name, c),
				{"rule": BUILTIN[tag][2]})
	EntityManager.register_type(&"driftwood_chest", func(c: Vector3i) -> WorldEntity: return ChestEntity.new("Driftwood Storage Chest", c),
			{"aliases": [&"chest"]})
	EntityManager.register_type(&"storage_crate", func(c: Vector3i) -> WorldEntity: return ChestEntity.make_crate(c))
	EntityManager.register_type(&"sea_barrel", func(c: Vector3i) -> WorldEntity: return ChestEntity.make_sea_barrel(c))
	EntityManager.register_type(&"fisher_bed", BedEntity, {"aliases": [&"bed"]})
	EntityManager.register_type(&"barber_mirror", MirrorEntity, {"aliases": [&"mirror"]})
	EntityManager.register_type(&"crab_pot", CrabPotEntity, {"rule": &"intertidal"})
	EntityManager.register_type(&"salt_pan", SaltPanEntity, {"rule": &"intertidal"})
	EntityManager.register_type(&"pine_sapling", TreeSaplingEntity, {"rule": &"soil", "aliases": [&"sapling"]})
	EntityManager.register_type(&"feed_trough", TroughEntityClass, {"aliases": [&"trough"]})
	EntityManager.register_type(&"poultry_coop", CoopEntityClass, {"aliases": [&"coop"]})
	EntityManager.register_type(&"lantern_post", LanternEntity, {"aliases": [&"lantern"]})
	EntityManager.register_type(&"pen_gate", GateEntity, {"aliases": [&"gate"]})
	EntityManager.register_type(&"live_trap", LiveTrapEntity, {"aliases": [&"trap"]})
	EntityManager.register_type(&"dog_kennel", func(c: Vector3i) -> WorldEntity: return GuardAnimalEntity.make_kennel(c), {"aliases": [&"kennel", &"dog"]})
	EntityManager.register_type(&"cat_basket", func(c: Vector3i) -> WorldEntity: return GuardAnimalEntity.make_cat_basket(c), {"aliases": [&"cat"]})
	EntityManager.register_type(&"scarecrow", ScarecrowEntity)
	EntityManager.register_type(&"pantry_barrel", func(c: Vector3i) -> WorldEntity: return ChestEntity.make_pantry_barrel(c), {"aliases": [&"pantry"]})
	for type: StringName in BUILTIN:
		var b: Array = BUILTIN[type]
		add_item(type, b[0], b[1], b[3])


## Registers the placeable item for `type` (same id), its build cost and a workbench recipe.
static func add_item(type: StringName, display_name: String, cost: Dictionary, stack := 10) -> void:
	ItemDB.init_db()
	RecipeDB.init_db()
	if not ItemDB.has_item(type):
		ItemDB.register_item(ItemDef.new(type, display_name, ItemDef.Category.SPECIAL, stack, -1, [&"placeable"]))
	_costs[type] = cost
	if not _order.has(type):
		_order.append(type)
	var rid := StringName("place_" + String(type))
	if not RecipeDB.has_recipe(rid):
		var inputs: Array[Dictionary] = []
		for item: StringName in cost:
			inputs.append({"item_id": item, "count": cost[item]})
		RecipeDB.register_recipe(RecipeDef.new(rid, display_name, RecipeDef.Category.WORKBENCH, &"workbench",
				inputs, type, 1, 2.0, PackedStringArray(["placeable"])))


static func build_cost(type: StringName) -> Dictionary:
	register_builtin()
	return _costs.get(type, {})


## Placeable types in Blueprints-tool order.
static func blueprint_types() -> Array:
	register_builtin()
	return _order


static func is_bait(item: StringName) -> bool:
	return BAIT_ITEMS.has(item)
