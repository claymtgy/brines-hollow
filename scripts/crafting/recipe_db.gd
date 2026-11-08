class_name RecipeDB
extends RefCounted
## Central registry of all crafting, cooking, and refining recipes in Brine's Hollow.

static var _recipes: Dictionary = {}
static var _by_station: Dictionary = {}
static var _by_category: Dictionary = {}
static var _initialized := false


static func init_db() -> void:
	if _initialized:
		return
	_initialized = true
	_recipes.clear()
	_by_station.clear()
	_by_category.clear()

	_register_basic_and_tools()
	_register_culinary_and_hearth()
	_register_smokehouse_and_saltery()
	_register_weapons_and_armor()


static func register_recipe(recipe: RecipeDef) -> void:
	_recipes[recipe.id] = recipe

	# Index by required station
	var st_key := recipe.required_station
	if not _by_station.has(st_key):
		_by_station[st_key] = []
	_by_station[st_key].append(recipe)

	# Index by category
	var cat_key := recipe.category
	if not _by_category.has(cat_key):
		_by_category[cat_key] = []
	_by_category[cat_key].append(recipe)


static func get_recipe(recipe_id: StringName) -> RecipeDef:
	if not _initialized:
		init_db()
	return _recipes.get(recipe_id, null)


static func has_recipe(recipe_id: StringName) -> bool:
	if not _initialized:
		init_db()
	return _recipes.has(recipe_id)


const STATION_NAMES := {
	&"none": "Hand Crafting",
	&"workbench": "Carpentry Workbench",
	&"furnace": "Smelting Furnace",
	&"anvil": "Blacksmith's Anvil",
	&"campfire": "Campfire Skillet",
	&"hearth_pot": "Hearth Stew Pot",
	&"smokehouse": "Fisher's Smokehouse",
	&"saltery": "Brine Saltery",
	&"brewery": "Coastal Teahouse",
}


static func get_station_exclusive_recipes(station: StringName) -> Array[RecipeDef]:
	if not _initialized:
		init_db()
	var list: Array[RecipeDef] = []
	if _by_station.has(station):
		for r in _by_station[station]:
			list.append(r)
	return list


static func get_recipes_for_station(station: StringName) -> Array[RecipeDef]:
	if not _initialized:
		init_db()
	var list: Array[RecipeDef] = []
	if _by_station.has(station):
		for r in _by_station[station]:
			list.append(r)
	if station != &"none" and _by_station.has(&"none"):
		for r in _by_station[&"none"]:
			list.append(r)
	return list


static func get_recipes_by_category(cat: RecipeDef.Category) -> Array[RecipeDef]:
	if not _initialized:
		init_db()
	var list: Array[RecipeDef] = []
	if _by_category.has(cat):
		for r in _by_category[cat]:
			list.append(r)
	return list


static func get_all_recipes() -> Array[RecipeDef]:
	if not _initialized:
		init_db()
	var list: Array[RecipeDef] = []
	for r in _recipes.values():
		list.append(r)
	return list


## Returns all recipes that the player currently has enough ingredients to craft at a given station.
static func get_craftable_recipes(inv: Inventory, station: StringName = &"none") -> Array[RecipeDef]:
	var candidate_list := get_recipes_for_station(station)
	var craftable: Array[RecipeDef] = []
	for recipe in candidate_list:
		if recipe.can_craft_with(inv):
			craftable.append(recipe)
	return craftable


# -------------------------------------------------------------------------
# Recipe Catalogue Registration
# -------------------------------------------------------------------------

static func _register_basic_and_tools() -> void:
	# Hand Crafting (No station required)
	register_recipe(RecipeDef.new(
		&"craft_wood_plank", "Wood Planks", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 1}],
		&"wood_plank", 4, 0.0, [&"timber", &"building"]
	))

	register_recipe(RecipeDef.new(
		&"craft_whittle_rod", "Whittled Fishing Rod", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"kelp_frond", "count": 1}],
		&"whittle_rod", 1, 0.0, [&"tool", &"fishing"]
	))

	register_recipe(RecipeDef.new(
		&"craft_parchment_chart", "Parchment Shore Chart", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"shore_wheat", "count": 2}],
		&"parchment_shore_chart", 1, 0.0, [&"map", &"chart"]
	))

	register_recipe(RecipeDef.new(
		&"craft_builders_hammer", "Builder's Hammer", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"wood_plank", "count": 1}],
		&"builders_hammer", 1, 0.0, [&"tool", &"hammer", &"building"]
	))

	register_recipe(RecipeDef.new(
		&"craft_driftwood_pickaxe", "Driftwood Pickaxe", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"wood_plank", "count": 2}],
		&"driftwood_pickaxe", 1, 0.0, [&"tool", &"pickaxe"]
	))

	register_recipe(RecipeDef.new(
		&"craft_driftwood_hoe", "Driftwood Hoe", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"wood_plank", "count": 1}],
		&"driftwood_hoe", 1, 0.0, [&"tool", &"hoe", &"farming"]
	))

	register_recipe(RecipeDef.new(
		&"craft_driftwood_axe", "Wooden Hatchet", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"wood_plank", "count": 1}],
		&"driftwood_axe", 1, 0.0, [&"tool", &"axe", &"forestry"]
	))

	register_recipe(RecipeDef.new(
		&"craft_driftwood_shovel", "Wooden Shovel", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 1}, {"item_id": &"wood_plank", "count": 2}],
		&"driftwood_shovel", 1, 0.0, [&"tool", &"shovel"]
	))

	register_recipe(RecipeDef.new(
		&"craft_pine_plank", "Pine Wood Planks", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"pine_wood", "count": 1}],
		&"wood_plank", 4, 0.0, [&"timber", &"building"]
	))

	register_recipe(RecipeDef.new(
		&"craft_pine_sapling", "Pine Sapling", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"leaves", "count": 2}, {"item_id": &"pine_wood", "count": 1}],
		&"pine_sapling", 2, 0.0, [&"placeable", &"sapling", &"forestry"]
	))

	register_recipe(RecipeDef.new(
		&"craft_pine_sapling_drift", "Pine Sapling (Driftwood)", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"leaves", "count": 2}, {"item_id": &"driftwood", "count": 1}],
		&"pine_sapling", 1, 0.0, [&"placeable", &"sapling", &"forestry"]
	))

	register_recipe(RecipeDef.new(
		&"craft_tarred_wood", "Tarred Wood", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"pine_wood", "count": 2}, {"item_id": &"kelp_frond", "count": 1}],
		&"dark_wood", 2, 0.0, [&"timber", &"refined"]
	))

	register_recipe(RecipeDef.new(
		&"craft_stone_pickaxe", "Stone Pickaxe", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"stone", "count": 3}],
		&"stone_pickaxe", 1, 0.0, [&"tool", &"pickaxe"]
	))

	register_recipe(RecipeDef.new(
		&"craft_stone_axe", "Stone Hatchet", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"stone", "count": 2}],
		&"stone_axe", 1, 0.0, [&"tool", &"axe"]
	))

	register_recipe(RecipeDef.new(
		&"craft_stone_shovel", "Stone Shovel", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"stone", "count": 2}],
		&"stone_shovel", 1, 0.0, [&"tool", &"shovel"]
	))

	register_recipe(RecipeDef.new(
		&"craft_stone_hoe", "Stone Hoe", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"stone", "count": 2}],
		&"stone_hoe", 1, 0.0, [&"tool", &"hoe"]
	))

	register_recipe(RecipeDef.new(
		&"smelt_copper_ingot", "Smelt Sea-Brass Ingot", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"copper_ore", "count": 2}],
		&"sea_brass_ingot", 1, 0.0, [&"metal", &"alloy"]
	))

	register_recipe(RecipeDef.new(
		&"smelt_iron_ingot", "Smelt Iron Ingot", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"sea_iron_ore", "count": 2}],
		&"iron_ingot", 1, 0.0, [&"metal", &"refined"]
	))

	register_recipe(RecipeDef.new(
		&"craft_copper_pickaxe", "Copper Pickaxe", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"pine_wood", "count": 2}, {"item_id": &"sea_brass_ingot", "count": 3}],
		&"copper_pickaxe", 1, 0.0, [&"tool", &"pickaxe"]
	))

	register_recipe(RecipeDef.new(
		&"craft_copper_axe", "Copper Hatchet", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"pine_wood", "count": 2}, {"item_id": &"sea_brass_ingot", "count": 2}],
		&"copper_axe", 1, 0.0, [&"tool", &"axe"]
	))

	register_recipe(RecipeDef.new(
		&"craft_iron_pickaxe", "Iron Pickaxe", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"dark_wood", "count": 2}, {"item_id": &"iron_ingot", "count": 3}],
		&"iron_pickaxe", 1, 0.0, [&"tool", &"pickaxe"]
	))

	register_recipe(RecipeDef.new(
		&"craft_iron_axe", "Iron Hatchet", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"dark_wood", "count": 2}, {"item_id": &"iron_ingot", "count": 2}],
		&"iron_axe", 1, 0.0, [&"tool", &"axe"]
	))

	register_recipe(RecipeDef.new(
		&"craft_iron_shovel", "Iron Shovel", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"dark_wood", "count": 2}, {"item_id": &"iron_ingot", "count": 1}],
		&"iron_shovel", 1, 0.0, [&"tool", &"shovel"]
	))

	register_recipe(RecipeDef.new(
		&"craft_iron_hoe", "Iron Hoe", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"dark_wood", "count": 2}, {"item_id": &"iron_ingot", "count": 2}],
		&"iron_hoe", 1, 0.0, [&"tool", &"hoe"]
	))

	# Workbench Crafting
	register_recipe(RecipeDef.new(
		&"craft_backpack_driftwood", "Driftwood Rucksack", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"driftwood", "count": 4}, {"item_id": &"sea_wool", "count": 2}],
		&"backpack_driftwood", 1, 3.0, [&"backpack", &"storage"]
	))

	register_recipe(RecipeDef.new(
		&"craft_ocean_caster_rod", "Ocean Caster Rod", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"dark_wood", "count": 3}, {"item_id": &"sea_brass_ingot", "count": 1}],
		&"ocean_caster_rod", 1, 4.0, [&"tool", &"fishing"]
	))

	register_recipe(RecipeDef.new(
		&"craft_hydrographic_chart", "Hydrographic Sea Chart", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"parchment_shore_chart", "count": 1}, {"item_id": &"ghost_squid", "count": 1}],
		&"hydrographic_sea_chart", 1, 2.0, [&"map", &"chart"]
	))

	# Livestock Husbandry & Tools
	register_recipe(RecipeDef.new(
		&"craft_shearing_shears", "Shearing Shears", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"stone", "count": 2}, {"item_id": &"driftwood", "count": 2}],
		&"shearing_shears", 1, 2.0, [&"tool", &"shears", &"livestock"]
	))

	register_recipe(RecipeDef.new(
		&"craft_wooden_bucket", "Wooden Pail", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"wood_plank", "count": 4}, {"item_id": &"driftwood", "count": 1}],
		&"wooden_bucket", 1, 2.0, [&"tool", &"bucket", &"livestock"]
	))

	register_recipe(RecipeDef.new(
		&"craft_animal_whistle", "Shepherd's Whistle", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"wood_plank", "count": 2}, {"item_id": &"sea_glass", "count": 1}],
		&"animal_whistle", 1, 2.0, [&"tool", &"whistle", &"livestock"]
	))

	register_recipe(RecipeDef.new(
		&"craft_feed_trough", "Livestock Trough", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"wood_plank", "count": 6}, {"item_id": &"stone", "count": 2}],
		&"feed_trough", 1, 3.0, [&"placeable", &"furniture", &"livestock"]
	))

	register_recipe(RecipeDef.new(
		&"craft_poultry_coop", "Shore Poultry Coop", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"wood_plank", "count": 8}, {"item_id": &"driftwood", "count": 4}],
		&"poultry_coop", 1, 4.0, [&"placeable", &"furniture", &"livestock"]
	))

	# Hand-craftable starter stations (so you can build stations from inventory without a Hammer)
	register_recipe(RecipeDef.new(
		&"hand_craft_workbench", "Carpentry Workbench", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 4}, {"item_id": &"wood_plank", "count": 4}],
		&"workbench", 1, 0.0, [&"placeable", &"station"]
	))
	register_recipe(RecipeDef.new(
		&"hand_craft_campfire", "Campfire Skillet", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"driftwood", "count": 4}, {"item_id": &"stone", "count": 4}],
		&"campfire", 1, 0.0, [&"placeable", &"station"]
	))
	register_recipe(RecipeDef.new(
		&"hand_craft_campfire_pine", "Campfire (Pine Logs)", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"pine_wood", "count": 3}, {"item_id": &"stone", "count": 4}],
		&"campfire", 1, 0.0, [&"placeable", &"station"]
	))
	register_recipe(RecipeDef.new(
		&"hand_craft_furnace", "Smelting Furnace", RecipeDef.Category.BASIC, &"none",
		[{"item_id": &"stone", "count": 8}, {"item_id": &"driftwood", "count": 4}],
		&"furnace", 1, 0.0, [&"placeable", &"station"]
	))

	# Smelting Furnace Recipes (&"furnace")
	register_recipe(RecipeDef.new(
		&"furnace_smelt_copper", "Smelt Sea-Brass Ingot", RecipeDef.Category.FORGE, &"furnace",
		[{"item_id": &"copper_ore", "count": 2}],
		&"sea_brass_ingot", 1, 0.0, [&"metal", &"alloy"]
	))
	register_recipe(RecipeDef.new(
		&"furnace_smelt_iron", "Smelt Iron Ingot", RecipeDef.Category.FORGE, &"furnace",
		[{"item_id": &"sea_iron_ore", "count": 2}],
		&"iron_ingot", 1, 0.0, [&"metal", &"refined"]
	))
	register_recipe(RecipeDef.new(
		&"furnace_fire_sea_glass", "Fire Sea Glass", RecipeDef.Category.FORGE, &"furnace",
		[{"item_id": &"sand", "count": 3}],
		&"sea_glass", 2, 0.0, [&"glass", &"refined"]
	))
	register_recipe(RecipeDef.new(
		&"furnace_bake_cobble", "Kiln-Fired Cobblestone", RecipeDef.Category.FORGE, &"furnace",
		[{"item_id": &"stone", "count": 2}, {"item_id": &"dirt", "count": 1}],
		&"cobblestone", 4, 0.0, [&"stone", &"building"]
	))

	# Blacksmith's Anvil Recipes (&"anvil")
	register_recipe(RecipeDef.new(
		&"anvil_copper_pickaxe", "Forge Copper Pickaxe", RecipeDef.Category.FORGE, &"anvil",
		[{"item_id": &"pine_wood", "count": 2}, {"item_id": &"sea_brass_ingot", "count": 3}],
		&"copper_pickaxe", 1, 0.0, [&"tool", &"pickaxe"]
	))
	register_recipe(RecipeDef.new(
		&"anvil_copper_axe", "Forge Copper Hatchet", RecipeDef.Category.FORGE, &"anvil",
		[{"item_id": &"pine_wood", "count": 2}, {"item_id": &"sea_brass_ingot", "count": 2}],
		&"copper_axe", 1, 0.0, [&"tool", &"axe"]
	))
	register_recipe(RecipeDef.new(
		&"anvil_iron_pickaxe", "Forge Iron Pickaxe", RecipeDef.Category.FORGE, &"anvil",
		[{"item_id": &"dark_wood", "count": 2}, {"item_id": &"iron_ingot", "count": 3}],
		&"iron_pickaxe", 1, 0.0, [&"tool", &"pickaxe"]
	))
	register_recipe(RecipeDef.new(
		&"anvil_iron_axe", "Forge Iron Hatchet", RecipeDef.Category.FORGE, &"anvil",
		[{"item_id": &"dark_wood", "count": 2}, {"item_id": &"iron_ingot", "count": 2}],
		&"iron_axe", 1, 0.0, [&"tool", &"axe"]
	))
	register_recipe(RecipeDef.new(
		&"anvil_iron_shovel", "Forge Iron Shovel", RecipeDef.Category.FORGE, &"anvil",
		[{"item_id": &"dark_wood", "count": 2}, {"item_id": &"iron_ingot", "count": 1}],
		&"iron_shovel", 1, 0.0, [&"tool", &"shovel"]
	))
	register_recipe(RecipeDef.new(
		&"anvil_iron_hoe", "Forge Iron Hoe", RecipeDef.Category.FORGE, &"anvil",
		[{"item_id": &"dark_wood", "count": 2}, {"item_id": &"iron_ingot", "count": 2}],
		&"iron_hoe", 1, 0.0, [&"tool", &"hoe"]
	))
	register_recipe(RecipeDef.new(
		&"anvil_rusty_cutlass", "Forge Mariner's Cutlass", RecipeDef.Category.FORGE, &"anvil",
		[{"item_id": &"iron_ingot", "count": 2}, {"item_id": &"dark_wood", "count": 1}],
		&"rusty_cutlass", 1, 0.0, [&"weapon", &"cutlass"]
	))
	register_recipe(RecipeDef.new(
		&"anvil_harpoon_lance", "Forge Harpoon Lance", RecipeDef.Category.FORGE, &"anvil",
		[{"item_id": &"dark_wood", "count": 3}, {"item_id": &"iron_ingot", "count": 1}],
		&"harpoon_lance", 1, 0.0, [&"weapon", &"harpoon"]
	))
	register_recipe(RecipeDef.new(
		&"anvil_diving_helmet", "Forge Brass Diving Helm", RecipeDef.Category.FORGE, &"anvil",
		[{"item_id": &"sea_brass_ingot", "count": 4}, {"item_id": &"sea_glass", "count": 2}],
		&"diving_helmet" if ItemDB.has_item(&"diving_helmet") else &"brass_diving_helmet", 1, 0.0, [&"armor", &"head"]
	))

	# Additional Carpentry Workbench Recipes (&"workbench")
	register_recipe(RecipeDef.new(
		&"wb_stone_pickaxe", "Stone Pickaxe", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"stone", "count": 3}],
		&"stone_pickaxe", 1, 0.0, [&"tool", &"pickaxe"]
	))
	register_recipe(RecipeDef.new(
		&"wb_stone_axe", "Stone Hatchet", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"stone", "count": 2}],
		&"stone_axe", 1, 0.0, [&"tool", &"axe"]
	))
	register_recipe(RecipeDef.new(
		&"wb_stone_shovel", "Stone Shovel", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"stone", "count": 2}],
		&"stone_shovel", 1, 0.0, [&"tool", &"shovel"]
	))
	register_recipe(RecipeDef.new(
		&"wb_stone_hoe", "Stone Hoe", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"driftwood", "count": 2}, {"item_id": &"stone", "count": 2}],
		&"stone_hoe", 1, 0.0, [&"tool", &"hoe"]
	))
	register_recipe(RecipeDef.new(
		&"wb_tarred_wood", "Tarred Wood", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"pine_wood", "count": 2}, {"item_id": &"kelp_frond", "count": 1}],
		&"dark_wood", 2, 0.0, [&"timber", &"refined"]
	))


static func _register_culinary_and_hearth() -> void:
	# Campfire Skillet
	register_recipe(RecipeDef.new(
		&"cook_roasted_mackerel", "Charred Sea Mackerel", RecipeDef.Category.COOKING, &"campfire",
		[{"item_id": &"silver_mackerel", "count": 1}],
		&"roasted_mackerel", 1, 4.0, [&"food", &"roasted", &"fish"]
	))

	register_recipe(RecipeDef.new(
		&"cook_roasted_flounder", "Crisp Tidepool Flounder", RecipeDef.Category.COOKING, &"campfire",
		[{"item_id": &"tidepool_flounder", "count": 1}],
		&"roasted_flounder", 1, 4.0, [&"food", &"roasted", &"fish"]
	))

	register_recipe(RecipeDef.new(
		&"cook_fried_sea_egg", "Skillet Shore-Egg", RecipeDef.Category.COOKING, &"campfire",
		[{"item_id": &"sea_egg", "count": 1}, {"item_id": &"samphire", "count": 1}],
		&"sea_egg", 1, 4.0, [&"food", &"egg", &"breakfast"]
	))

	# Hearth Pot / Cauldron
	register_recipe(RecipeDef.new(
		&"cook_clam_chowder", "Hearty Clam Chowder", RecipeDef.Category.COOKING, &"hearth_pot",
		[{"item_id": &"brine_oyster", "count": 2}, {"item_id": &"root_potato", "count": 1}, {"item_id": &"salt_milk", "count": 1}],
		&"hearty_clam_chowder", 1, 8.0, [&"food", &"chowder", &"soup"]
	))

	register_recipe(RecipeDef.new(
		&"cook_bouillabaisse", "Samphire Bouillabaisse", RecipeDef.Category.COOKING, &"hearth_pot",
		[{"item_id": &"cliff_salmon", "count": 1}, {"item_id": &"shore_crab", "count": 1}, {"item_id": &"samphire", "count": 2}],
		&"samphire_bouillabaisse", 1, 10.0, [&"food", &"bouillabaisse", &"seafood"]
	))

	register_recipe(RecipeDef.new(
		&"cook_glazed_crab", "Honey-Glazed Abyssal Crab", RecipeDef.Category.COOKING, &"hearth_pot",
		[{"item_id": &"shore_crab", "count": 2}, {"item_id": &"marsh_honey", "count": 1}, {"item_id": &"sea_salt", "count": 1}],
		&"glazed_abyssal_crab", 1, 12.0, [&"food", &"banquet", &"buff"]
	))

	register_recipe(RecipeDef.new(
		&"cook_hardtack", "Shore-Wheat Hardtack", RecipeDef.Category.COOKING, &"hearth_pot",
		[{"item_id": &"shore_wheat", "count": 3}, {"item_id": &"sea_salt", "count": 1}],
		&"shore_hardtack", 2, 6.0, [&"food", &"bread", &"travel"]
	))


static func _register_smokehouse_and_saltery() -> void:
	# Smokehouse (Preserving catches for voyage and trade export)
	register_recipe(RecipeDef.new(
		&"smoke_fish_ration", "Smoked Fish Ration", RecipeDef.Category.SMOKEHOUSE, &"smokehouse",
		[{"item_id": &"silver_mackerel", "count": 2}, {"item_id": &"sea_salt", "count": 1}, {"item_id": &"dark_wood", "count": 1}],
		&"smoked_fish_ration", 2, 10.0, [&"food", &"smoked", &"ration"]
	))

	register_recipe(RecipeDef.new(
		&"smoke_salmon_strips", "Smoked Salmon Strips", RecipeDef.Category.SMOKEHOUSE, &"smokehouse",
		[{"item_id": &"cliff_salmon", "count": 1}, {"item_id": &"sea_salt", "count": 1}],
		&"smoked_salmon_strips", 2, 12.0, [&"food", &"smoked", &"ration"]
	))

	# Saltery Curing & Teahouse Brewing
	register_recipe(RecipeDef.new(
		&"cure_pickled_samphire", "Pickled Samphire Jar", RecipeDef.Category.SALTERY, &"saltery",
		[{"item_id": &"samphire", "count": 3}, {"item_id": &"sea_salt", "count": 2}],
		&"pickled_samphire_jar", 1, 8.0, [&"food", &"pickled", &"cure"]
	))

	register_recipe(RecipeDef.new(
		&"cure_goat_cheese", "Salt-Cured Goat Cheese", RecipeDef.Category.SALTERY, &"saltery",
		[{"item_id": &"salt_milk", "count": 2}, {"item_id": &"sea_salt", "count": 1}],
		&"goat_cheese", 1, 8.0, [&"food", &"dairy", &"cheese"]
	))

	register_recipe(RecipeDef.new(
		&"brew_kelp_tea", "Peppermint Kelp Tea", RecipeDef.Category.BREWING, &"brewery",
		[{"item_id": &"kelp_frond", "count": 2}, {"item_id": &"marsh_honey", "count": 1}],
		&"peppermint_kelp_tea", 1, 5.0, [&"drink", &"tea", &"stamina"]
	))

	register_recipe(RecipeDef.new(
		&"brew_chicory_coffee", "Roasted Chicory Sea-Brew", RecipeDef.Category.BREWING, &"brewery",
		[{"item_id": &"root_potato", "count": 1}, {"item_id": &"sea_salt", "count": 1}],
		&"roasted_chicory_brew", 1, 5.0, [&"drink", &"tonic", &"stamina"]
	))


static func _register_weapons_and_armor() -> void:
	register_recipe(RecipeDef.new(
		&"forge_rusty_cutlass", "Rusty Cutlass", RecipeDef.Category.FORGE, &"workbench",
		[{"item_id": &"iron_ingot", "count": 2}, {"item_id": &"dark_wood", "count": 1}],
		&"rusty_cutlass", 1, 5.0, [&"weapon", &"cutlass"]
	))

	register_recipe(RecipeDef.new(
		&"forge_harpoon_lance", "Harpoon Lance", RecipeDef.Category.FORGE, &"workbench",
		[{"item_id": &"dark_wood", "count": 3}, {"item_id": &"iron_ingot", "count": 1}],
		&"harpoon_lance", 1, 5.0, [&"weapon", &"harpoon"]
	))

	register_recipe(RecipeDef.new(
		&"forge_oilskin_coat", "Heavy Oilskin Coat", RecipeDef.Category.WORKBENCH, &"workbench",
		[{"item_id": &"sea_wool", "count": 4}, {"item_id": &"marsh_honey", "count": 1}],
		&"oilskin_coat", 1, 6.0, [&"armor", &"body"]
	))
