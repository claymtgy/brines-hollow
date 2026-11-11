class_name ItemDB
extends RefCounted
## Central registry of all items and resources in Brine's Hollow.
## Maps items to voxel palette materials, categories, and tags.

static var _registry: Dictionary = {}
static var _voxel_to_item: Dictionary = {}
static var _initialized := false


static func init_db() -> void:
	if _initialized:
		return
	_initialized = true
	_registry.clear()
	_voxel_to_item.clear()

	_register_materials()
	_register_crops_and_farming()
	_register_fish_and_sea()
	_register_tools_and_weapons()
	_register_equipment_and_backpacks()
	_register_special_and_currencies()


static func get_item(p_id: StringName) -> ItemDef:
	if not _initialized:
		init_db()
	return _registry.get(p_id, null)


static func has_item(p_id: StringName) -> bool:
	if not _initialized:
		init_db()
	return _registry.has(p_id)


static func get_by_voxel_mat(voxel_mat: int) -> ItemDef:
	if not _initialized:
		init_db()
	match voxel_mat:
		Palette.GRASS, Palette.GRASS_DRY:
			return _voxel_to_item.get(Palette.DIRT, null)
		Palette.WET_SAND:
			return _voxel_to_item.get(Palette.SAND, null)
		Palette.GRAVEL:
			return _voxel_to_item.get(Palette.STONE, null)
		Palette.SANDSTONE_B, Palette.SANDSTONE_C:
			return _voxel_to_item.get(Palette.SANDSTONE_A, null)
		Palette.LEAVES_DARK:
			return _voxel_to_item.get(Palette.LEAVES, null)
	return _voxel_to_item.get(voxel_mat, null)


static func get_all_items() -> Array[ItemDef]:
	if not _initialized:
		init_db()
	var arr: Array[ItemDef] = []
	for item in _registry.values():
		arr.append(item)
	return arr


static func get_by_category(category: ItemDef.Category) -> Array[ItemDef]:
	if not _initialized:
		init_db()
	var results: Array[ItemDef] = []
	for item in _registry.values():
		if item.category == category:
			results.append(item)
	return results


static func get_by_tag(tag: String) -> Array[ItemDef]:
	if not _initialized:
		init_db()
	var results: Array[ItemDef] = []
	for item in _registry.values():
		if item.has_tag(tag):
			results.append(item)
	return results


static func register_item(def: ItemDef) -> void:
	_registry[def.id] = def
	if def.voxel_mat >= 0:
		_voxel_to_item[def.voxel_mat] = def


# -------------------------------------------------------------------------
# Default Catalogue Registration
# -------------------------------------------------------------------------

static func _register_materials() -> void:
	# Raw Voxel & Natural Materials
	var mats := [
		ItemDef.new(&"driftwood", "Driftwood", ItemDef.Category.MATERIAL, 999, Palette.DRIFTWOOD, [&"timber", &"wood", &"shore"]),
		ItemDef.new(&"pine_wood", "Pine Wood", ItemDef.Category.MATERIAL, 999, Palette.TRUNK, [&"timber", &"wood", &"forest"]),
		ItemDef.new(&"dark_wood", "Tarred Wood", ItemDef.Category.MATERIAL, 999, Palette.DARK_WOOD, [&"timber", &"refined"]),
		ItemDef.new(&"wood_plank", "Wood Plank", ItemDef.Category.MATERIAL, 999, Palette.PLANK, [&"timber", &"refined"]),
		ItemDef.new(&"stone", "Limestone", ItemDef.Category.MATERIAL, 999, Palette.STONE, [&"stone", &"quarry"]),
		ItemDef.new(&"cobblestone", "Cobblestone", ItemDef.Category.MATERIAL, 999, Palette.COBBLE, [&"stone", &"masonry"]),
		ItemDef.new(&"sandstone", "Sandstone", ItemDef.Category.MATERIAL, 999, Palette.SANDSTONE_A, [&"stone", &"shore"]),
		ItemDef.new(&"sand", "Sand", ItemDef.Category.MATERIAL, 999, Palette.SAND, [&"sand", &"shore"]),
		ItemDef.new(&"dirt", "Loam Soil", ItemDef.Category.MATERIAL, 999, Palette.DIRT, [&"earth", &"soil"]),
		ItemDef.new(&"kelp_frond", "Kelp Fronds", ItemDef.Category.MATERIAL, 999, Palette.KELP, [&"kelp", &"flora", &"fuel"]),
		ItemDef.new(&"leaves", "Forest Foliage", ItemDef.Category.MATERIAL, 999, Palette.LEAVES, [&"flora", &"thatch"]),
	]
	for m in mats:
		register_item(m)

	# Minerals & Ingot Refinements (Non-voxel materials)
	var ores := [
		ItemDef.new(&"sea_iron_ore", "Brine-Iron Ore", ItemDef.Category.MATERIAL, 999, -1, [&"ore", &"metal"]),
		ItemDef.new(&"iron_ingot", "Iron Ingot", ItemDef.Category.MATERIAL, 999, -1, [&"metal", &"refined"]),
		ItemDef.new(&"copper_ore", "Copper Ore", ItemDef.Category.MATERIAL, 999, -1, [&"ore", &"metal"]),
		ItemDef.new(&"sea_brass_ingot", "Sea-Brass Ingot", ItemDef.Category.MATERIAL, 999, -1, [&"metal", &"alloy"]),
		ItemDef.new(&"sea_salt", "Sea Salt", ItemDef.Category.MATERIAL, 999, -1, [&"salt", &"cure", &"cooking"]),
		ItemDef.new(&"sea_glass", "Polished Sea Glass", ItemDef.Category.MATERIAL, 999, -1, [&"salvage", &"decor"]),
		ItemDef.new(&"chitin_plate", "Heavy Chitin Plate", ItemDef.Category.MATERIAL, 999, -1, [&"salvage", &"armor_mat"]),
		ItemDef.new(&"gloom_gland", "Gloom-Crawler Gland", ItemDef.Category.MATERIAL, 999, -1, [&"salvage", &"glow"]),
		ItemDef.new(&"hulk_pearl", "The Hulk's Pearl", ItemDef.Category.MATERIAL, 1, -1, [&"trophy", &"legendary", &"decor"]),
		ItemDef.new(&"siren_heart", "Heart of the Siren", ItemDef.Category.MATERIAL, 1, -1, [&"trophy", &"legendary", &"abyssal"]),
		ItemDef.new(&"abyssal_chitin", "Abyssal Chitin", ItemDef.Category.MATERIAL, 999, -1, [&"salvage", &"armor_mat", &"abyssal"]),
		ItemDef.new(&"phosphor_cluster", "Phosphor Cluster", ItemDef.Category.MATERIAL, 999, -1, [&"ore", &"light", &"chemical"]),
		ItemDef.new(&"fish_oil", "Refined Fish Oil", ItemDef.Category.MATERIAL, 99, -1, [&"oil", &"fuel", &"refined"]),
		ItemDef.new(&"ancient_weapon_fragment", "Ancient Weapon Fragment", ItemDef.Category.MATERIAL, 99, -1, [&"salvage", &"legendary"]),
		ItemDef.new(&"reaver_crest", "Sea-Reaver War Crest", ItemDef.Category.MATERIAL, 99, -1, [&"trophy", &"metal"]),
		ItemDef.new(&"calamine_ore", "Calamine Ore", ItemDef.Category.MATERIAL, 999, -1, [&"ore", &"metal"]),
		ItemDef.new(&"brass_diving_helmet", "Brass Diving Helmet", ItemDef.Category.TOOL, 1, -1, [&"gear", &"diving", &"armor"]),
		ItemDef.new(&"angler_lure", "Bioluminescent Angler Lure", ItemDef.Category.MATERIAL, 99, -1, [&"trophy", &"light"]),
		ItemDef.new(&"abyssal_pearl", "Black Abyssal Pearl", ItemDef.Category.MATERIAL, 99, -1, [&"treasure", &"gem"]),
		ItemDef.new(&"diving_bell", "Submerged Diving Bell", ItemDef.Category.SPECIAL, 5, -1, [&"placeable", &"diving"]),
		ItemDef.new(&"caldera_basalt_plate", "Volcanic Basalt Plate", ItemDef.Category.MATERIAL, 999, -1, [&"salvage", &"armor_mat", &"volcanic"]),
		ItemDef.new(&"geothermal_core", "Geothermal Core", ItemDef.Category.MATERIAL, 1, -1, [&"trophy", &"legendary", &"relic"]),
		ItemDef.new(&"wheat_flour", "Shore Wheat Flour", ItemDef.Category.MATERIAL, 99, -1, [&"food", &"ingredient"]),
		ItemDef.new(&"undertow_crest", "Undertow Champion's Crest", ItemDef.Category.MATERIAL, 1, -1, [&"trophy", &"legendary"]),
		ItemDef.new(&"regulator_keystone", "Ancient Regulator Keystone", ItemDef.Category.MATERIAL, 1, -1, [&"relic", &"legendary", &"quest"]),
		ItemDef.new(&"tide_wheel", "Tide Mill Water Wheel", ItemDef.Category.SPECIAL, 5, -1, [&"placeable", &"engineering"]),
		ItemDef.new(&"automated_grain_mill", "Automated Grain Mill", ItemDef.Category.SPECIAL, 5, -1, [&"placeable", &"engineering"]),
		ItemDef.new(&"automated_sawmill", "Automated Sawmill", ItemDef.Category.SPECIAL, 5, -1, [&"placeable", &"engineering"]),
		ItemDef.new(&"sluice_gate", "Tidal Sluice Gate", ItemDef.Category.SPECIAL, 10, -1, [&"placeable", &"engineering"]),
		ItemDef.new(&"tide_regulator", "Ancient Tide Regulator", ItemDef.Category.SPECIAL, 1, -1, [&"placeable", &"relic"]),
		ItemDef.new(&"glacial_tusk", "Glacial Ivory Tusk", ItemDef.Category.MATERIAL, 99, -1, [&"trophy", &"material", &"frost"]),
		ItemDef.new(&"borean_fur", "Borean Mammoth-Seal Fur", ItemDef.Category.MATERIAL, 99, -1, [&"textile", &"material", &"frost"]),
		ItemDef.new(&"deluge_core", "Core of the Great Deluge", ItemDef.Category.MATERIAL, 1, -1, [&"trophy", &"legendary", &"relic"]),
		ItemDef.new(&"beeswax", "Natural Beeswax", ItemDef.Category.MATERIAL, 50, -1, [&"crafting", &"material", &"wax"]),
		ItemDef.new(&"exotic_spice", "Exotic Eastern Spice", ItemDef.Category.MATERIAL, 99, -1, [&"trade", &"luxury", &"cooking"]),
		ItemDef.new(&"dye_indigo", "Imperial Indigo Dye", ItemDef.Category.MATERIAL, 99, -1, [&"trade", &"dye", &"crafting"]),
		ItemDef.new(&"silk_bolt", "High-Seas Silk Bolt", ItemDef.Category.MATERIAL, 99, -1, [&"trade", &"textile"]),
		# Archery & Black Powder Ammunition
		ItemDef.new(&"flint_arrow", "Flint Hunting Arrow", ItemDef.Category.MATERIAL, 64, -1, [&"ammo", &"arrow"]),
		ItemDef.new(&"iron_broadhead", "Iron Broadhead Arrow", ItemDef.Category.MATERIAL, 64, -1, [&"ammo", &"arrow", &"pierce"]),
		ItemDef.new(&"paper_cartridge", "Paper Black-Powder Cartridge", ItemDef.Category.MATERIAL, 30, -1, [&"ammo", &"bullet", &"powder"]),
		ItemDef.new(&"black_powder", "Black Powder", ItemDef.Category.MATERIAL, 40, -1, [&"crafting", &"powder"]),
	]
	for o in ores:
		register_item(o)


static func _register_crops_and_farming() -> void:
	var crops := [
		# Seeds
		ItemDef.new(&"seed_shore_wheat", "Shore Wheat Seed", ItemDef.Category.MATERIAL, 99, -1, [&"seed", &"sweet_soil"]),
		ItemDef.new(&"seed_samphire", "Samphire Cutting", ItemDef.Category.MATERIAL, 99, -1, [&"seed", &"brackish_soil"]),
		ItemDef.new(&"seed_tide_kale", "Tide Kale Spores", ItemDef.Category.MATERIAL, 99, -1, [&"seed", &"brackish_soil"]),
		ItemDef.new(&"seed_root_potato", "Root Potato Eye", ItemDef.Category.MATERIAL, 99, -1, [&"seed", &"sweet_soil"]),

		# Harvested Crops
		ItemDef.new(&"shore_wheat", "Shore Wheat", ItemDef.Category.FOOD, 99, -1, [&"crop", &"grain"]),
		ItemDef.new(&"samphire", "Sea Samphire", ItemDef.Category.FOOD, 99, -1, [&"crop", &"vegetable", &"salty"]),
		ItemDef.new(&"tide_kale", "Tide Kale", ItemDef.Category.FOOD, 99, -1, [&"crop", &"vegetable"]),
		ItemDef.new(&"root_potato", "Root Potato", ItemDef.Category.FOOD, 99, -1, [&"crop", &"staple"]),

		# Animal & Farm Products
		ItemDef.new(&"salt_milk", "Salt-Goat Milk", ItemDef.Category.FOOD, 20, -1, [&"dairy", &"cooking"]),
		ItemDef.new(&"sea_wool", "Shore-Sheep Wool", ItemDef.Category.MATERIAL, 99, -1, [&"textile", &"crafting"]),
		ItemDef.new(&"sea_egg", "Shore-Duck Egg", ItemDef.Category.FOOD, 20, -1, [&"food", &"egg", &"cooking"]),
		ItemDef.new(&"down_feather", "Down Feather", ItemDef.Category.MATERIAL, 99, -1, [&"feather", &"crafting", &"textile"]),
		ItemDef.new(&"goat_cheese", "Salt-Goat Cheese", ItemDef.Category.FOOD, 20, -1, [&"food", &"meal", &"dairy", &"cheese"]),
		ItemDef.new(&"marsh_honey", "Marsh Honey", ItemDef.Category.FOOD, 50, -1, [&"sweet", &"cooking"]),
		ItemDef.new(&"seed_brackish_rye", "Brackish Rye Seed", ItemDef.Category.MATERIAL, 99, -1, [&"seed", &"hybrid", &"brackish_soil"]),
		ItemDef.new(&"brackish_rye", "Brackish Rye", ItemDef.Category.FOOD, 99, -1, [&"crop", &"grain", &"hybrid"]),
		ItemDef.new(&"aged_brine_cheese", "Aged Brine-Cured Cheese", ItemDef.Category.FOOD, 20, -1, [&"food", &"dairy", &"cured"]),
		ItemDef.new(&"vintage_maritime_ale", "Vintage Maritime Cask Ale", ItemDef.Category.FOOD, 20, -1, [&"food", &"beverage", &"fermented"]),
		ItemDef.new(&"brackish_rye_bread", "Crusty Brackish Rye Bread", ItemDef.Category.FOOD, 20, -1, [&"food", &"bread"]),
		ItemDef.new(&"maritime_stout", "Archipelago Maritime Stout", ItemDef.Category.FOOD, 20, -1, [&"food", &"beverage"]),

		# Cooked Meals & Gourmet Provisions
		ItemDef.new(&"smoked_fish_ration", "Smoked Fish Ration", ItemDef.Category.FOOD, 20, -1, [&"food", &"meal", &"preserved"]),
		ItemDef.new(&"hearty_clam_chowder", "Hearty Clam Chowder", ItemDef.Category.FOOD, 10, -1, [&"food", &"meal", &"soup", &"buff"]),
		ItemDef.new(&"roasted_mackerel", "Charred Sea Mackerel", ItemDef.Category.FOOD, 20, -1, [&"food", &"meal", &"roasted"]),
		ItemDef.new(&"roasted_flounder", "Crisp Tidepool Flounder", ItemDef.Category.FOOD, 20, -1, [&"food", &"meal", &"roasted"]),
		ItemDef.new(&"samphire_bouillabaisse", "Samphire Bouillabaisse", ItemDef.Category.FOOD, 10, -1, [&"food", &"meal", &"soup", &"buff"]),
		ItemDef.new(&"glazed_abyssal_crab", "Honey-Glazed Abyssal Crab", ItemDef.Category.FOOD, 10, -1, [&"food", &"meal", &"banquet", &"buff"]),
		ItemDef.new(&"shore_hardtack", "Shore-Wheat Hardtack", ItemDef.Category.FOOD, 40, -1, [&"food", &"bread", &"travel"]),
		ItemDef.new(&"smoked_salmon_strips", "Smoked Salmon Strips", ItemDef.Category.FOOD, 20, -1, [&"food", &"meal", &"preserved"]),
		ItemDef.new(&"pickled_samphire_jar", "Pickled Samphire Jar", ItemDef.Category.FOOD, 20, -1, [&"food", &"pickled", &"cure"]),
		ItemDef.new(&"peppermint_kelp_tea", "Peppermint Kelp Tea", ItemDef.Category.FOOD, 20, -1, [&"drink", &"tea", &"tonic"]),
		ItemDef.new(&"roasted_chicory_brew", "Roasted Chicory Sea-Brew", ItemDef.Category.FOOD, 20, -1, [&"drink", &"coffee", &"tonic"]),
		# Secret recipes from the rarest catches
		ItemDef.new(&"leviathan_feast", "Leviathan Feast", ItemDef.Category.FOOD, 5, -1, [&"food", &"meal", &"banquet", &"buff", &"secret"]),
		ItemDef.new(&"storm_smoked_eel", "Storm-Smoked Eel", ItemDef.Category.FOOD, 20, -1, [&"food", &"meal", &"smoked", &"secret"]),
		ItemDef.new(&"phosphor_broth", "Phosphor Ink Broth", ItemDef.Category.FOOD, 10, -1, [&"food", &"soup", &"buff", &"secret"]),
	]

	# Configure food buffs & 3-meal satiety stomach attributes (keyed by id, not list
	# position, so adding items above can't silently shift the buffs).
	var food_buffs := {
		&"smoked_fish_ration": {"hp_bonus": 25, "stamina_bonus": 25, "regen_hp_sec": 1.2, "duration_sec": 900.0, "swim_speed": 1.25},
		&"hearty_clam_chowder": {"hp_bonus": 40, "stamina_bonus": 30, "regen_hp_sec": 1.5, "duration_sec": 1200.0, "cold_immunity": true},
		&"roasted_mackerel": {"hp_bonus": 18, "stamina_bonus": 25, "regen_hp_sec": 1.0, "duration_sec": 900.0},
		&"roasted_flounder": {"hp_bonus": 20, "stamina_bonus": 20, "regen_hp_sec": 1.0, "duration_sec": 900.0},
		&"samphire_bouillabaisse": {"hp_bonus": 45, "stamina_bonus": 40, "regen_hp_sec": 1.8, "duration_sec": 1500.0, "swim_speed": 1.20},
		&"glazed_abyssal_crab": {"hp_bonus": 70, "stamina_bonus": 60, "regen_hp_sec": 2.5, "duration_sec": 1800.0, "cold_immunity": true, "extra_breath_sec": 60.0},
		&"shore_hardtack": {"hp_bonus": 15, "stamina_bonus": 50, "regen_hp_sec": 0.8, "duration_sec": 1200.0},
		&"smoked_salmon_strips": {"hp_bonus": 25, "stamina_bonus": 35, "regen_hp_sec": 1.2, "duration_sec": 1200.0},
		&"pickled_samphire_jar": {"hp_bonus": 22, "stamina_bonus": 30, "regen_hp_sec": 1.0, "duration_sec": 1080.0},
		&"peppermint_kelp_tea": {"hp_bonus": 10, "stamina_bonus": 15, "stamina_regen_mult": 1.75, "duration_sec": 600.0},
		&"roasted_chicory_brew": {"hp_bonus": 10, "stamina_bonus": 20, "stamina_regen_mult": 1.75, "duration_sec": 600.0},
		&"salt_milk": {"hp_bonus": 15, "stamina_bonus": 20, "regen_hp_sec": 0.8, "duration_sec": 600.0},
		&"sea_egg": {"hp_bonus": 12, "stamina_bonus": 15, "regen_hp_sec": 0.5, "duration_sec": 600.0},
		&"goat_cheese": {"hp_bonus": 35, "stamina_bonus": 30, "regen_hp_sec": 1.2, "duration_sec": 1200.0},
		&"aged_brine_cheese": {"hp_bonus": 50, "stamina_bonus": 45, "regen_hp_sec": 2.0, "duration_sec": 1800.0, "cold_immunity": true},
		&"vintage_maritime_ale": {"hp_bonus": 30, "stamina_bonus": 50, "stamina_regen_mult": 2.2, "duration_sec": 1200.0, "cold_immunity": true},
		&"brackish_rye_bread": {"hp_bonus": 35, "stamina_bonus": 40, "regen_hp_sec": 1.5, "duration_sec": 1500.0},
		&"maritime_stout": {"hp_bonus": 40, "stamina_bonus": 60, "stamina_regen_mult": 2.0, "duration_sec": 1500.0, "cold_immunity": true},
		&"leviathan_feast": {"hp_bonus": 100, "stamina_bonus": 80, "regen_hp_sec": 3.0, "duration_sec": 2400.0, "cold_immunity": true, "extra_breath_sec": 120.0, "swim_speed": 1.3},
		&"storm_smoked_eel": {"hp_bonus": 30, "stamina_bonus": 60, "stamina_regen_mult": 2.0, "regen_hp_sec": 1.0, "duration_sec": 1200.0},
		&"phosphor_broth": {"hp_bonus": 35, "stamina_bonus": 30, "regen_hp_sec": 1.4, "duration_sec": 1500.0, "extra_breath_sec": 90.0, "swim_speed": 1.2},
	}
	for c: ItemDef in crops:
		if food_buffs.has(c.id):
			c.food_data = food_buffs[c.id]

	for c in crops:
		register_item(c)
	# Spring water from cavern springs and stone wells: a plain drink, and the furnace's quench.
	var water := ItemDef.new(&"spring_water", "Flask of Spring Water", ItemDef.Category.FOOD, 20, -1, [&"drink", &"water", &"fresh"])
	water.food_data = {"hp_bonus": 4, "stamina_bonus": 10, "stamina_regen_mult": 1.35, "regen_hp_sec": 0.3, "duration_sec": 480.0}
	register_item(water)


static func _register_fish_and_sea() -> void:
	var fish := [
		ItemDef.new(&"silver_mackerel", "Silver Mackerel", ItemDef.Category.FOOD, 20, -1, [&"fish", &"pelagic", &"fresh"]),
		ItemDef.new(&"cliff_salmon", "Cliff Salmon", ItemDef.Category.FOOD, 20, -1, [&"fish", &"pelagic", &"fresh"]),
		ItemDef.new(&"tidepool_flounder", "Tidepool Flounder", ItemDef.Category.FOOD, 20, -1, [&"fish", &"benthic", &"fresh"]),
		ItemDef.new(&"lightning_eel", "Lightning Eel", ItemDef.Category.FOOD, 20, -1, [&"fish", &"storm", &"fresh"]),
		ItemDef.new(&"ghost_squid", "Ghost Squid", ItemDef.Category.FOOD, 20, -1, [&"fish", &"night", &"luminescent"]),
		ItemDef.new(&"abyssal_ray", "Abyssal Leviathan Ray", ItemDef.Category.FOOD, 5, -1, [&"fish", &"legendary", &"trophy"]),
		ItemDef.new(&"shore_crab", "Shore Crab", ItemDef.Category.FOOD, 20, -1, [&"shellfish", &"trap"]),
		ItemDef.new(&"brine_oyster", "Brine Oyster", ItemDef.Category.FOOD, 50, -1, [&"shellfish", &"aquaculture"]),
		ItemDef.new(&"hearty_clam", "Hearty Tide-Clam", ItemDef.Category.FOOD, 50, -1, [&"shellfish", &"seafood", &"cooking"]),
	]
	for f in fish:
		register_item(f)


static func _register_tools_and_weapons() -> void:
	var tools := [
		# Harvest Tools
		ItemDef.new(&"driftwood_pickaxe", "Driftwood Pickaxe", ItemDef.Category.TOOL, 1, -1, [&"tool", &"pickaxe"]),
		ItemDef.new(&"iron_pickaxe", "Iron Pickaxe", ItemDef.Category.TOOL, 1, -1, [&"tool", &"pickaxe"]),
		ItemDef.new(&"whittle_rod", "Whittled Fishing Rod", ItemDef.Category.TOOL, 1, -1, [&"tool", &"fishing_rod"]),
		ItemDef.new(&"ocean_caster_rod", "Ocean Caster Rod", ItemDef.Category.TOOL, 1, -1, [&"tool", &"fishing_rod"]),
		ItemDef.new(&"masons_chisel", "Mason's Chisel", ItemDef.Category.TOOL, 1, -1, [&"tool", &"chisel"]),

		# Weapons & Combat Armaments
		ItemDef.new(&"rusty_cutlass", "Rusty Cutlass", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"cutlass", &"blade"]),
		ItemDef.new(&"corsair_sabre", "Corsair's Brass Sabre", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"cutlass", &"blade"]),
		ItemDef.new(&"harpoon_lance", "Harpoon Lance", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"harpoon", &"thrust"]),
		ItemDef.new(&"heavy_harpoon", "Titan Barbed Harpoon", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"harpoon", &"tether"]),
		ItemDef.new(&"anchor_maul", "Lead-Weighted Anchor Maul", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"maul", &"blunt"]),
		ItemDef.new(&"pneumatic_speargun", "Pneumatic Speargun", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"speargun", &"ranged"]),
		ItemDef.new(&"weighted_trapper_net", "Weighted Throwing Net", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"trapper", &"net"]),
		ItemDef.new(&"phosphor_lantern_staff", "Phosphor Lantern Staff", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"occult", &"light"]),
		ItemDef.new(&"net_launcher", "Net Launcher", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"trapper"]),
		ItemDef.new(&"builders_hammer", "Builder's Hammer", ItemDef.Category.TOOL, 1, -1, [&"tool", &"hammer"]),
		ItemDef.new(&"driftwood_hoe", "Driftwood Hoe", ItemDef.Category.TOOL, 1, -1, [&"tool", &"hoe"]),
		ItemDef.new(&"stone_pickaxe", "Stone Pickaxe", ItemDef.Category.TOOL, 1, -1, [&"tool", &"pickaxe"]),
		ItemDef.new(&"copper_pickaxe", "Copper Pickaxe", ItemDef.Category.TOOL, 1, -1, [&"tool", &"pickaxe"]),
		ItemDef.new(&"driftwood_axe", "Wooden Hatchet", ItemDef.Category.TOOL, 1, -1, [&"tool", &"axe"]),
		ItemDef.new(&"stone_axe", "Stone Hatchet", ItemDef.Category.TOOL, 1, -1, [&"tool", &"axe"]),
		ItemDef.new(&"copper_axe", "Copper Hatchet", ItemDef.Category.TOOL, 1, -1, [&"tool", &"axe"]),
		ItemDef.new(&"iron_axe", "Iron Hatchet", ItemDef.Category.TOOL, 1, -1, [&"tool", &"axe"]),
		ItemDef.new(&"driftwood_shovel", "Wooden Shovel", ItemDef.Category.TOOL, 1, -1, [&"tool", &"shovel"]),
		ItemDef.new(&"stone_shovel", "Stone Shovel", ItemDef.Category.TOOL, 1, -1, [&"tool", &"shovel"]),
		ItemDef.new(&"iron_shovel", "Iron Shovel", ItemDef.Category.TOOL, 1, -1, [&"tool", &"shovel"]),
		ItemDef.new(&"stone_hoe", "Stone Hoe", ItemDef.Category.TOOL, 1, -1, [&"tool", &"hoe"]),
		ItemDef.new(&"iron_hoe", "Iron Hoe", ItemDef.Category.TOOL, 1, -1, [&"tool", &"hoe"]),
		ItemDef.new(&"shearing_shears", "Shearing Shears", ItemDef.Category.TOOL, 1, -1, [&"tool", &"shears"]),
		ItemDef.new(&"wooden_bucket", "Wooden Pail", ItemDef.Category.TOOL, 1, -1, [&"tool", &"bucket", &"pail"]),
		ItemDef.new(&"animal_whistle", "Shepherd's Whistle", ItemDef.Category.TOOL, 1, -1, [&"tool", &"whistle"]),
		ItemDef.new(&"glacial_ice_lance", "Glacial Ice Lance", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"harpoon", &"thrust", &"frost"]),
		ItemDef.new(&"sovereign_trident", "Sovereign Hydro-Trident", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"trident", &"legendary"]),
		ItemDef.new(&"hunting_bow", "Whittled Shore Bow", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"bow", &"ranged"]),
		ItemDef.new(&"driftwood_recurve", "Driftwood Recurve Bow", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"bow", &"ranged"]),
		ItemDef.new(&"flintlock_pistol", "Sea-Dog's Brass Flintlock", ItemDef.Category.TOOL, 1, -1, [&"weapon", &"flintlock", &"ranged", &"firearm"]),
	]

	# Tool properties
	tools[0].tool_data = {"tier": 1, "power": 1.0, "durability": 60}
	tools[1].tool_data = {"tier": 2, "power": 2.5, "durability": 250}
	tools[2].tool_data = {"tackle_tier": 1, "durability": 50}
	tools[3].tool_data = {"tackle_tier": 2, "durability": 200}
	tools[4].tool_data = {"carve_power": 1}
	tools[5].tool_data = {"weapon_type": "cutlass", "damage": 15, "speed": 1.2}
	tools[5].weapon_data = {"weapon_type": WeaponDef.WeaponType.CUTLASS, "damage": 15, "attack_rate": 1.2, "reach_m": 2.0}

	tools[6].tool_data = {"weapon_type": "cutlass", "damage": 24, "speed": 1.4}
	tools[6].weapon_data = {"weapon_type": WeaponDef.WeaponType.CUTLASS, "damage": 24, "attack_rate": 1.4, "reach_m": 2.2, "harvests_kelp": true}

	tools[7].tool_data = {"weapon_type": "harpoon", "damage": 28, "reach": 3.5}
	tools[7].weapon_data = {"weapon_type": WeaponDef.WeaponType.HARPOON, "damage": 28, "attack_rate": 1.0, "reach_m": 3.5}

	tools[8].tool_data = {"weapon_type": "harpoon", "damage": 38, "reach": 4.0, "tether": 15.0}
	tools[8].weapon_data = {"weapon_type": WeaponDef.WeaponType.HARPOON, "damage": 38, "attack_rate": 0.8, "reach_m": 4.0, "tether_length_m": 15.0, "underwater_efficiency": 0.95}

	tools[9].tool_data = {"weapon_type": "maul", "damage": 45, "breaks_rock": true}
	tools[9].weapon_data = {"weapon_type": WeaponDef.WeaponType.ANCHOR_MAUL, "damage": 45, "attack_rate": 0.6, "reach_m": 2.0, "stagger_power": 2.5, "breaks_rock": true}

	tools[10].tool_data = {"weapon_type": "speargun", "damage": 30, "ranged": true}
	tools[10].weapon_data = {"weapon_type": WeaponDef.WeaponType.SPEARGUN, "damage": 30, "projectile_speed_m_s": 25.0, "is_ranged": true, "underwater_efficiency": 1.0}

	tools[11].tool_data = {"weapon_type": "net", "damage": 5, "tether": 8.0}
	tools[11].weapon_data = {"weapon_type": WeaponDef.WeaponType.TRAPPER_NET, "damage": 5, "tether_length_m": 8.0, "is_ranged": true}

	tools[12].tool_data = {"weapon_type": "occult", "damage": 20, "light": true}
	tools[12].weapon_data = {"weapon_type": WeaponDef.WeaponType.TIDAL_LANTERN, "damage": 20, "reach_m": 3.0}

	tools[13].tool_data = {"weapon_type": "trapper", "durability": 40}
	tools[14].tool_data = {"tier": 1, "build_power": 1.0, "durability": 120}
	tools[15].tool_data = {"tier": 1, "till_power": 1.0, "durability": 80}
	tools[16].tool_data = {"tier": 2, "power": 1.6, "durability": 120}
	tools[17].tool_data = {"tier": 3, "power": 2.1, "durability": 180}
	tools[18].tool_data = {"tier": 1, "power": 1.0, "durability": 60}
	tools[19].tool_data = {"tier": 2, "power": 1.6, "durability": 120}
	tools[20].tool_data = {"tier": 3, "power": 2.2, "durability": 180}
	tools[21].tool_data = {"tier": 4, "power": 3.0, "durability": 280}
	tools[22].tool_data = {"tier": 1, "power": 1.2, "durability": 60}
	tools[23].tool_data = {"tier": 2, "power": 1.8, "durability": 120}
	tools[24].tool_data = {"tier": 4, "power": 2.6, "durability": 240}
	tools[25].tool_data = {"tier": 2, "till_power": 1.6, "durability": 140}
	tools[26].tool_data = {"tier": 4, "till_power": 2.5, "durability": 240}
	tools[1].tool_data = {"tier": 4, "power": 2.8, "durability": 280}
	for t in tools:
		match t.id:
			&"glacial_ice_lance":
				t.tool_data = {"weapon_type": "harpoon", "damage": 42, "reach": 3.8, "frost": true}
				t.weapon_data = {"weapon_type": WeaponDef.WeaponType.HARPOON, "damage": 42, "attack_rate": 1.1, "reach_m": 3.8, "frost": true}
			&"sovereign_trident":
				t.tool_data = {"weapon_type": "trident", "damage": 65, "reach": 4.2, "cavitation": true, "legendary": true}
				t.weapon_data = {"weapon_type": WeaponDef.WeaponType.HARPOON, "damage": 65, "attack_rate": 1.3, "reach_m": 4.2, "cavitation": true, "legendary": true}
			&"hunting_bow":
				t.tool_data = {"weapon_type": "bow", "damage": 22, "reach": 35.0, "is_ranged": true}
				t.weapon_data = {"weapon_type": WeaponDef.WeaponType.BOW, "damage": 22, "attack_rate": 1.0, "reach_m": 35.0, "projectile_speed_m_s": 32.0, "is_ranged": true, "underwater_efficiency": 0.3}
			&"driftwood_recurve":
				t.tool_data = {"weapon_type": "bow", "damage": 34, "reach": 45.0, "is_ranged": true}
				t.weapon_data = {"weapon_type": WeaponDef.WeaponType.BOW, "damage": 34, "attack_rate": 1.2, "reach_m": 45.0, "projectile_speed_m_s": 42.0, "is_ranged": true, "underwater_efficiency": 0.35}
			&"flintlock_pistol":
				t.tool_data = {"weapon_type": "flintlock", "damage": 48, "reach": 22.0, "is_ranged": true}
				t.weapon_data = {"weapon_type": WeaponDef.WeaponType.FLINTLOCK, "damage": 48, "attack_rate": 0.8, "reach_m": 22.0, "projectile_speed_m_s": 60.0, "is_ranged": true, "stagger_power": 2.2, "underwater_efficiency": 0.0}
		register_item(t)


static func _register_equipment_and_backpacks() -> void:
	var gear := [
		# Backpacks
		ItemDef.new(&"backpack_canvas", "Canvas Pouch", ItemDef.Category.EQUIPMENT, 1, -1, [&"backpack"]),
		ItemDef.new(&"backpack_driftwood", "Driftwood Rucksack", ItemDef.Category.EQUIPMENT, 1, -1, [&"backpack"]),
		ItemDef.new(&"backpack_seal_leather", "Seal-Leather Haversack", ItemDef.Category.EQUIPMENT, 1, -1, [&"backpack"]),
		# Head
		ItemDef.new(&"diving_rebreather", "Brass Diving Rebreather", ItemDef.Category.EQUIPMENT, 1, -1, [&"diving", &"head"]),
		ItemDef.new(&"oilskin_souwester", "Oilskin Sou'wester", ItemDef.Category.EQUIPMENT, 1, -1, [&"armor", &"head"]),
		ItemDef.new(&"deep_diving_helmet", "Lead Deep-Diving Helmet", ItemDef.Category.EQUIPMENT, 1, -1, [&"diving", &"armor", &"head"]),
		# Body
		ItemDef.new(&"oilskin_coat", "Heavy Oilskin Coat", ItemDef.Category.EQUIPMENT, 1, -1, [&"armor", &"body", &"chest"]),
		ItemDef.new(&"lead_diving_suit", "Reinforced Lead Diving Suit", ItemDef.Category.EQUIPMENT, 1, -1, [&"diving", &"armor", &"body", &"chest"]),
		ItemDef.new(&"chitin_carapace", "Crab Chitin Carapace", ItemDef.Category.EQUIPMENT, 1, -1, [&"armor", &"body", &"chest"]),
		ItemDef.new(&"volcanic_basalt_armor", "Volcanic Basalt Armor", ItemDef.Category.EQUIPMENT, 1, -1, [&"armor", &"body", &"chest", &"volcanic"]),
		ItemDef.new(&"borean_parka", "Borean Insulated Parka", ItemDef.Category.EQUIPMENT, 1, -1, [&"armor", &"body", &"chest", &"frost"]),
		# Legs
		ItemDef.new(&"fisherman_waders", "Waterproof Waders", ItemDef.Category.EQUIPMENT, 1, -1, [&"armor", &"legs"]),
		# Boots
		ItemDef.new(&"spiked_ice_boots", "Spiked Ice Boots", ItemDef.Category.EQUIPMENT, 1, -1, [&"armor", &"boots"]),
		ItemDef.new(&"flippers_seal_leather", "Seal-Skin Flippers", ItemDef.Category.EQUIPMENT, 1, -1, [&"armor", &"boots", &"aquatic"]),
		ItemDef.new(&"lead_diving_boots", "Weighted Lead Boots", ItemDef.Category.EQUIPMENT, 1, -1, [&"diving", &"armor", &"boots"]),
		# Navigational Charts (Map Slot)
		ItemDef.new(&"parchment_shore_chart", "Parchment Shore Chart", ItemDef.Category.EQUIPMENT, 1, -1, [&"map", &"chart", &"navigation"]),
		ItemDef.new(&"hydrographic_sea_chart", "Hydrographic Sea Chart", ItemDef.Category.EQUIPMENT, 1, -1, [&"map", &"chart", &"navigation"]),
		ItemDef.new(&"master_chronometer_chart", "Master Chronometer Chart", ItemDef.Category.EQUIPMENT, 1, -1, [&"map", &"chart", &"navigation"]),
		# Off-Hand & Tactical Gear
		ItemDef.new(&"boarding_shield", "Reinforced Boarding Shield", ItemDef.Category.EQUIPMENT, 1, -1, [&"armor", &"shield", &"accessory", &"offhand"]),
		ItemDef.new(&"offhand_brass_lantern", "Mariner's Belt Lantern", ItemDef.Category.EQUIPMENT, 1, -1, [&"accessory", &"offhand", &"light"]),
	]

	for g: ItemDef in gear:
		match g.id:
			&"boarding_shield":
				g.equip_slot = &"accessory"
				g.armor_data = {"defense": 6, "guard_efficiency": 0.5, "parry_window_bonus": 0.05, "block_angle_deg": 140.0}
			&"offhand_brass_lantern":
				g.equip_slot = &"accessory"
				g.tool_data = {"light_radius": 14.0}
			&"backpack_canvas":
				g.equip_slot = &"backpack"
				g.tool_data = {"capacity": 24}
			&"backpack_driftwood":
				g.equip_slot = &"backpack"
				g.tool_data = {"capacity": 36}
			&"backpack_seal_leather":
				g.equip_slot = &"backpack"
				g.tool_data = {"capacity": 44}
			&"diving_rebreather":
				g.equip_slot = &"head"
				g.tool_data = {"extra_breath_sec": 60}
				g.armor_data = {"defense": 2, "extra_breath_sec": 60.0, "max_safe_depth_m": 30.0}
			&"oilskin_souwester":
				g.equip_slot = &"head"
				g.armor_data = {"defense": 2, "cold_protection": 0.25, "max_safe_depth_m": 20.0}
			&"deep_diving_helmet":
				g.equip_slot = &"head"
				g.armor_data = {"defense": 6, "extra_breath_sec": 180.0, "max_safe_depth_m": 85.0}
			&"oilskin_coat":
				g.equip_slot = &"body"
				g.armor_data = {"defense": 4, "cold_protection": 0.35, "max_safe_depth_m": 25.0}
			&"lead_diving_suit":
				g.equip_slot = &"body"
				g.armor_data = {"defense": 10, "cold_protection": 0.5, "max_safe_depth_m": 85.0, "swim_speed_mult": 0.3, "buoyancy_offset": -1.5}
			&"chitin_carapace":
				g.equip_slot = &"body"
				g.armor_data = {"defense": 8, "crush_reduction": 0.3, "max_safe_depth_m": 50.0}
			&"volcanic_basalt_armor":
				g.equip_slot = &"body"
				g.armor_data = {"defense": 16, "fire_immunity": true, "boil_immunity": true, "max_safe_depth_m": 120.0}
			&"borean_parka":
				g.equip_slot = &"body"
				g.armor_data = {"defense": 14, "cold_protection": 1.0, "frost_immunity": true, "hypothermia_immunity": true}
			&"fisherman_waders":
				g.equip_slot = &"legs"
				g.armor_data = {"defense": 3, "cold_protection": 0.25, "max_safe_depth_m": 20.0}
			&"spiked_ice_boots":
				g.equip_slot = &"boots"
				g.tool_data = {"ice_slip_immunity": true}
				g.armor_data = {"defense": 2, "cold_protection": 0.15}
			&"flippers_seal_leather":
				g.equip_slot = &"boots"
				g.armor_data = {"defense": 1, "swim_speed_mult": 1.35, "buoyancy_offset": 0.2}
			&"lead_diving_boots":
				g.equip_slot = &"boots"
				g.armor_data = {"defense": 5, "max_safe_depth_m": 85.0, "swim_speed_mult": 0.35, "buoyancy_offset": -1.5}
			&"parchment_shore_chart":
				g.equip_slot = &"map"
				g.tool_data = {"map_tier": 1, "reveals_coastlines": true}
			&"hydrographic_sea_chart":
				g.equip_slot = &"map"
				g.tool_data = {"map_tier": 2, "reveals_coastlines": true, "reveals_tides": true, "reveals_bathymetry": true}
			&"master_chronometer_chart":
				g.equip_slot = &"map"
				g.tool_data = {"map_tier": 3, "reveals_coastlines": true, "reveals_tides": true, "reveals_bathymetry": true, "reveals_wind": true, "reveals_caves": true}
		register_item(g)


static func _register_special_and_currencies() -> void:
	var specials := [
		ItemDef.new(&"brass_guilder", "Brass Guilder", ItemDef.Category.SPECIAL, 9999, -1, [&"currency", &"trade"]),
		ItemDef.new(&"tide_scrip", "Tide Scrip", ItemDef.Category.SPECIAL, 9999, -1, [&"currency", &"export"]),
		ItemDef.new(&"gilded_ship_wheel", "Gilded Ship Wheel", ItemDef.Category.SPECIAL, 1, -1, [&"trophy", &"boss_drop", &"boat_fixture", &"placeable"]),
		ItemDef.new(&"sea_hawk_perch", "Trained Sea-Hawk Perch", ItemDef.Category.SPECIAL, 1, -1, [&"boat_fixture", &"placeable", &"companion"]),
		ItemDef.new(&"blueprint_tide_mill", "Blueprint: Tide Mill", ItemDef.Category.BLUEPRINT, 1, -1, [&"blueprint", &"engineering"]),
		ItemDef.new(&"blueprint_dry_dock", "Blueprint: Dry Dock", ItemDef.Category.BLUEPRINT, 1, -1, [&"blueprint", &"maritime"]),
		ItemDef.new(&"rowboat_kit", "Rowboat (kit)", ItemDef.Category.TOOL, 1, -1, [&"maritime", &"boat"]),
		ItemDef.new(&"skiff_kit", "Outrigger Skiff (kit)", ItemDef.Category.TOOL, 1, -1, [&"maritime", &"boat"]),
		ItemDef.new(&"barge_kit", "Tide-Barge (kit)", ItemDef.Category.TOOL, 1, -1, [&"maritime", &"boat"]),
		ItemDef.new(&"sloop_kit", "Coastal Sloop (kit)", ItemDef.Category.TOOL, 1, -1, [&"maritime", &"boat"]),
		ItemDef.new(&"schooner_kit", "Ocean Schooner (kit)", ItemDef.Category.TOOL, 1, -1, [&"maritime", &"boat"]),
		ItemDef.new(&"pine_sapling", "Pine Sapling", ItemDef.Category.SPECIAL, 20, -1, [&"placeable", &"sapling", &"forestry"]),
		ItemDef.new(&"blueprint_scroll", "Architectural Blueprint Scroll", ItemDef.Category.BLUEPRINT, 20, -1, [&"blueprint", &"architecture"]),
		ItemDef.new(&"deck_lantern", "Ship Deck Lantern", ItemDef.Category.SPECIAL, 5, -1, [&"boat_fixture", &"placeable", &"light"]),
		ItemDef.new(&"cargo_crate", "Watertight Cargo Crate", ItemDef.Category.SPECIAL, 5, -1, [&"boat_fixture", &"placeable", &"storage"]),
		ItemDef.new(&"harpoon_swivel", "Deck Harpoon Swivel", ItemDef.Category.SPECIAL, 2, -1, [&"boat_fixture", &"placeable", &"weapon"]),
		ItemDef.new(&"sea_cot", "Sailor's Sea Cot", ItemDef.Category.SPECIAL, 2, -1, [&"boat_fixture", &"placeable", &"rest"]),
		ItemDef.new(&"navigation_table", "Mariner's Chart Desk", ItemDef.Category.SPECIAL, 2, -1, [&"boat_fixture", &"placeable", &"navigation"]),
		ItemDef.new(&"diving_winch", "Salvage Diving Winch", ItemDef.Category.SPECIAL, 2, -1, [&"boat_fixture", &"placeable", &"salvage", &"diving"]),
		ItemDef.new(&"scented_candle", "Bayberry & Honey Candle", ItemDef.Category.SPECIAL, 20, -1, [&"placeable", &"light", &"decor"]),
		ItemDef.new(&"oyster_rack", "Tidal Oyster Rack", ItemDef.Category.SPECIAL, 5, -1, [&"placeable", &"aquaculture", &"homestead"]),
		ItemDef.new(&"mangrove_beehive", "Mangrove Beehive", ItemDef.Category.SPECIAL, 5, -1, [&"placeable", &"apiculture", &"homestead"]),
		ItemDef.new(&"banquet_table", "Communal Banquet Table", ItemDef.Category.SPECIAL, 2, -1, [&"placeable", &"furniture", &"community"]),
	]
	for s in specials:
		register_item(s)
