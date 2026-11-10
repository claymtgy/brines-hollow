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
	&"stone_well":      ["Stone Well",             {&"cobblestone": 12, &"wood_plank": 6, &"kelp_frond": 4}, &"ground", 5],
	&"mooring_bollard": ["Mooring Bollard",        {&"driftwood": 4, &"iron_ingot": 1}, &"ground", 10],
	&"tide_hearth":     ["Tide Hearth",            {&"cobblestone": 16, &"driftwood": 8, &"sea_brass_ingot": 2}, &"ground", 1],
	&"village_bell":    ["Harbour Bell",           {&"iron_ingot": 2, &"wood_plank": 8, &"cobblestone": 4}, &"ground", 1],
	&"phosphor_brazier": ["Phosphor Brazier",       {&"copper_ore": 4, &"sea_glass": 2, &"stone": 4}, &"ground", 5],
	&"defense_barricade": ["Spike Barricade",       {&"driftwood": 6, &"iron_ingot": 1}, &"ground", 10],
	&"sparring_ring":    ["Town Sparring Ring",    {&"sand": 12, &"wood_plank": 4, &"driftwood": 4}, &"ground", 1],
	&"regatta_buoy":     ["Regatta Checkpoint Buoy", {&"wood_plank": 4, &"sea_brass_ingot": 1}, &"intertidal", 10],
	&"diving_bell":      ["Submerged Diving Bell", {&"sea_brass_ingot": 6, &"wood_plank": 8, &"cobblestone": 4}, &"intertidal", 1],
	&"tide_wheel":       ["Tide Mill Water Wheel", {&"wood_plank": 16, &"iron_ingot": 4, &"driftwood": 8}, &"intertidal", 5],
	&"automated_grain_mill": ["Automated Grain Mill", {&"stone": 12, &"wood_plank": 8, &"sea_brass_ingot": 2}, &"ground", 5],
	&"automated_sawmill": ["Automated Sawmill", {&"wood_plank": 12, &"iron_ingot": 6, &"sea_brass_ingot": 2}, &"ground", 5],
	&"sluice_gate":      ["Tidal Sluice Gate", {&"wood_plank": 8, &"iron_ingot": 2}, &"intertidal", 10],
	&"undertow_altar":   ["Undertow Gauntlet Altar", {&"cobblestone": 12, &"sea_glass": 4}, &"intertidal", 1],
	&"tide_regulator":   ["Ancient Tide Regulator", {&"cobblestone": 20, &"ancient_weapon_fragment": 2}, &"ground", 1],
	&"drafting_desk":    ["Architect's Drafting Desk", {&"wood_plank": 8, &"driftwood": 4, &"sea_brass_ingot": 1}, &"ground", 5],
	&"fish_trophy":      ["Taxidermy Fish Mount",    {&"wood_plank": 2, &"driftwood": 2, &"silver_mackerel": 1}, &"ground", 10],
	&"aquarium":         ["Glass Living Aquarium",   {&"sea_glass": 6, &"sea_brass_ingot": 2, &"sand": 2}, &"ground", 5],
	&"heraldic_banner":  ["Heraldic Settlement Banner", {&"sea_wool": 4, &"driftwood": 4, &"sea_brass_ingot": 1}, &"ground", 10],
	&"aging_cask":       ["Oak Aging Cask",          {&"wood_plank": 6, &"iron_ingot": 2, &"driftwood": 2}, &"ground", 5],
	&"oyster_rack":      ["Tidal Oyster Rack",       {&"wood_plank": 6, &"kelp_frond": 4, &"stone": 2}, &"intertidal", 5],
	&"mangrove_beehive": ["Mangrove Beehive",        {&"wood_plank": 8, &"marsh_honey": 1, &"leaves": 4}, &"ground", 5],
	&"banquet_table":    ["Communal Banquet Table",  {&"wood_plank": 12, &"driftwood": 6, &"sea_wool": 2}, &"ground", 2],
	&"community_chest":  ["Community Stockpile Chest", {&"wood_plank": 14, &"driftwood": 8, &"sea_brass_ingot": 2}, &"ground", 1],
	&"construction_site": ["House Construction Site", {&"driftwood": 4, &"wood_plank": 2}, &"ground", 5],
	&"notice_board":     ["Town Notice Board",       {&"wood_plank": 8, &"driftwood": 4, &"sea_glass": 1}, &"ground", 1],
	&"market_stall":     ["Village Market Stall",    {&"wood_plank": 10, &"driftwood": 6, &"sea_wool": 2}, &"ground", 1],
	&"farming_station":  ["Farmer's Seed Stand",     {&"wood_plank": 4, &"seed_shore_wheat": 2}, &"ground", 5],
	&"ranch_station":    ["Rancher's Hitching Post", {&"driftwood": 4, &"wood_plank": 2},       &"ground", 5],
	&"fisher_station":   ["Fisher's Tackle Bench",   {&"wood_plank": 4, &"driftwood": 2},       &"ground", 5],
	&"sawhorse":         ["Sawyer's Sawhorse",       {&"driftwood": 4, &"wood_plank": 2},       &"ground", 5],
	&"boat_slipway":     ["Harbor Slipway Dry-Dock", {&"wood_plank": 18, &"iron_ingot": 4, &"driftwood": 8}, &"intertidal", 1],
	&"reaver_dock":      ["Sea-Reaver Outpost Dock", {&"wood_plank": 12, &"driftwood": 8, &"reaver_crest": 1}, &"intertidal", 1],
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
	EntityManager.register_type(&"village_bell", VillageBellEntity, {"aliases": [&"bell"]})
	EntityManager.register_type(&"farming_station", func(c: Vector3i) -> WorldEntity: return StationEntity.new(&"farming_station", "Farmer's Seed Stand", c), {"aliases": [&"farm_stand"]})
	EntityManager.register_type(&"ranch_station", func(c: Vector3i) -> WorldEntity: return StationEntity.new(&"ranch_station", "Rancher's Hitching Post", c), {"aliases": [&"ranch_post"]})
	EntityManager.register_type(&"fisher_station", func(c: Vector3i) -> WorldEntity: return StationEntity.new(&"fisher_station", "Fisher's Tackle Bench", c), {"aliases": [&"tackle_bench"]})
	EntityManager.register_type(&"sawhorse", func(c: Vector3i) -> WorldEntity: return StationEntity.new(&"sawhorse", "Sawyer's Sawhorse", c))
	EntityManager.register_type(&"barnacled_chest", func(c: Vector3i) -> WorldEntity: return ChestEntity.make_barnacled(c), {"item": &""})
	EntityManager.register_type(&"stone_well", func(c: Vector3i) -> WorldEntity: return WaterSourceEntity.make_well(c), {"aliases": [&"well"]})
	EntityManager.register_type(&"freshwater_spring", func(c: Vector3i) -> WorldEntity: return WaterSourceEntity.make_spring(c), {"item": &""})
	EntityManager.register_type(&"war_horn_totem", WarHornEntity, {"item": &""})
	EntityManager.register_type(&"tide_hearth", TideHearthEntity, {"aliases": [&"hearth"]})
	EntityManager.register_type(&"mooring_bollard", BollardEntity, {"aliases": [&"bollard"]})
	EntityManager.register_type(&"loose_boulder", BoulderEntity, {"item": &""})
	EntityManager.register_type(&"pantry_barrel", func(c: Vector3i) -> WorldEntity: return ChestEntity.make_pantry_barrel(c), {"aliases": [&"pantry"]})
	EntityManager.register_type(&"phosphor_brazier", PhosphorBrazierEntity, {"aliases": [&"brazier"]})
	EntityManager.register_type(&"defense_barricade", BarricadeEntity, {"aliases": [&"barricade"]})
	EntityManager.register_type(&"sparring_ring", SparringRingEntity, {"aliases": [&"sparring"]})
	EntityManager.register_type(&"regatta_buoy", RegattaBuoyEntity, {"aliases": [&"buoy"]})
	EntityManager.register_type(&"diving_bell", DivingBellEntity, {"aliases": [&"bell_dive"]})
	EntityManager.register_type(&"tide_wheel", TideWheelEntity, {"rule": &"intertidal", "aliases": [&"mill_wheel"]})
	EntityManager.register_type(&"automated_grain_mill", AutomatedGrainMillEntity, {"aliases": [&"grain_mill", &"mill"]})
	EntityManager.register_type(&"automated_sawmill", AutomatedSawmillEntity, {"aliases": [&"sawmill"]})
	EntityManager.register_type(&"sluice_gate", SluiceGateEntity, {"rule": &"intertidal", "aliases": [&"sluice"]})
	EntityManager.register_type(&"undertow_altar", UndertowGauntletAltar, {"rule": &"intertidal", "aliases": [&"gauntlet"]})
	EntityManager.register_type(&"tide_regulator", TideRegulatorEntity, {"aliases": [&"regulator", &"monolith"]})
	EntityManager.register_type(&"drafting_desk", DraftingDeskEntity, {"aliases": [&"desk", &"architect"]})
	EntityManager.register_type(&"fish_trophy", FishTrophyEntity, {"aliases": [&"trophy"]})
	EntityManager.register_type(&"aquarium", AquariumEntity, {"aliases": [&"fish_tank"]})
	EntityManager.register_type(&"heraldic_banner", HeraldicBannerEntity, {"aliases": [&"banner", &"flag"]})
	EntityManager.register_type(&"aging_cask", AgingCaskEntity, {"aliases": [&"cask", &"barrel_aging"]})
	EntityManager.register_type(&"oyster_rack", OysterRackEntity, {"rule": &"intertidal", "aliases": [&"oysters", &"aquaculture"]})
	EntityManager.register_type(&"mangrove_beehive", MangroveBeehiveEntity, {"aliases": [&"beehive", &"apiary", &"bees"]})
	EntityManager.register_type(&"banquet_table", BanquetTableEntity, {"aliases": [&"feast_table", &"feast"]})
	EntityManager.register_type(&"community_chest", func(c: Vector3i) -> WorldEntity: return ChestEntity.make_community_chest(c), {"aliases": [&"stockpile", &"town_chest"]})
	EntityManager.register_type(&"construction_site", ConstructionSiteEntity, {"aliases": [&"building_site", &"plot_marker"]})
	EntityManager.register_type(&"notice_board", NoticeBoardEntity, {"aliases": [&"bulletin", &"chores_board"]})
	EntityManager.register_type(&"market_stall", MarketStallEntity, {"aliases": [&"stall", &"purser_stall"]})
	EntityManager.register_type(&"boat_slipway", BoatSlipwayEntity, {"rule": &"intertidal", "aliases": [&"slipway", &"drydock"]})
	EntityManager.register_type(&"reaver_dock", ReaverDockEntity, {"rule": &"intertidal", "aliases": [&"pirate_dock"]})
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
