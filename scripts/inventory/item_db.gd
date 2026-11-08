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
	}
	for c: ItemDef in crops:
		if food_buffs.has(c.id):
			c.food_data = food_buffs[c.id]

	for c in crops:
		register_item(c)


static func _register_fish_and_sea() -> void:
	var fish := [
		ItemDef.new(&"silver_mackerel", "Silver Mackerel", ItemDef.Category.FOOD, 20, -1, [&"fish", &"pelagic", &"fresh"]),
		ItemDef.new(&"cliff_salmon", "Cliff Salmon", ItemDef.Category.FOOD, 20, -1, [&"fish", &"pelagic", &"fresh"]),
		ItemDef.new(&"tidepool_flounder", "Tidepool Flounder", ItemDef.Category.FOOD, 20, -1, [&"fish", &"benthic", &"fresh"]),
		ItemDef.new(&"lightning_eel", "Lightning Eel", ItemDef.Category.FOOD, 20, -1, [&"fish", &"storm", &"fresh"]),
		ItemDef.new(&"ghost_squid", "Ghost Squid", ItemDef.Category.FOOD, 20, -1, [&"fish", &"night", &"luminescent"]),
		ItemDef.new(&"shore_crab", "Shore Crab", ItemDef.Category.FOOD, 20, -1, [&"shellfish", &"trap"]),
		ItemDef.new(&"brine_oyster", "Brine Oyster", ItemDef.Category.FOOD, 50, -1, [&"shellfish", &"aquaculture"]),
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
	]

	# Backpack properties
	gear[0].equip_slot = &"backpack"
	gear[0].tool_data = {"capacity": 24}
	gear[1].equip_slot = &"backpack"
	gear[1].tool_data = {"capacity": 36}
	gear[2].equip_slot = &"backpack"
	gear[2].tool_data = {"capacity": 44}

	# Headgear
	gear[3].equip_slot = &"head"
	gear[3].tool_data = {"extra_breath_sec": 60}
	gear[3].armor_data = {"defense": 2, "extra_breath_sec": 60.0, "max_safe_depth_m": 30.0}

	gear[4].equip_slot = &"head"
	gear[4].armor_data = {"defense": 2, "cold_protection": 0.25, "max_safe_depth_m": 20.0}

	gear[5].equip_slot = &"head"
	gear[5].armor_data = {"defense": 6, "extra_breath_sec": 180.0, "max_safe_depth_m": 85.0}

	# Body Armor
	gear[6].equip_slot = &"body"
	gear[6].armor_data = {"defense": 4, "cold_protection": 0.35, "max_safe_depth_m": 25.0}

	gear[7].equip_slot = &"body"
	gear[7].armor_data = {"defense": 10, "cold_protection": 0.5, "max_safe_depth_m": 85.0, "swim_speed_mult": 0.3, "buoyancy_offset": -1.5}

	gear[8].equip_slot = &"body"
	gear[8].armor_data = {"defense": 8, "crush_reduction": 0.3, "max_safe_depth_m": 50.0}

	# Legs
	gear[9].equip_slot = &"legs"
	gear[9].armor_data = {"defense": 3, "cold_protection": 0.25, "max_safe_depth_m": 20.0}

	# Boots
	gear[10].equip_slot = &"boots"
	gear[10].tool_data = {"ice_slip_immunity": true}
	gear[10].armor_data = {"defense": 2, "cold_protection": 0.15}

	gear[11].equip_slot = &"boots"
	gear[11].armor_data = {"defense": 1, "swim_speed_mult": 1.35, "buoyancy_offset": 0.2}

	gear[12].equip_slot = &"boots"
	gear[12].armor_data = {"defense": 5, "max_safe_depth_m": 85.0, "swim_speed_mult": 0.35, "buoyancy_offset": -1.5}

	# Map Charts
	gear[13].equip_slot = &"map"
	gear[13].tool_data = {"map_tier": 1, "reveals_coastlines": true}

	gear[14].equip_slot = &"map"
	gear[14].tool_data = {"map_tier": 2, "reveals_coastlines": true, "reveals_tides": true, "reveals_bathymetry": true}

	gear[15].equip_slot = &"map"
	gear[15].tool_data = {"map_tier": 3, "reveals_coastlines": true, "reveals_tides": true, "reveals_bathymetry": true, "reveals_wind": true, "reveals_caves": true}

	for g in gear:
		register_item(g)


static func _register_special_and_currencies() -> void:
	var specials := [
		ItemDef.new(&"brass_guilder", "Brass Guilder", ItemDef.Category.SPECIAL, 9999, -1, [&"currency", &"trade"]),
		ItemDef.new(&"tide_scrip", "Tide Scrip", ItemDef.Category.SPECIAL, 9999, -1, [&"currency", &"export"]),
		ItemDef.new(&"gilded_ship_wheel", "Gilded Ship Wheel", ItemDef.Category.SPECIAL, 1, -1, [&"trophy", &"boss_drop"]),
		ItemDef.new(&"blueprint_tide_mill", "Blueprint: Tide Mill", ItemDef.Category.BLUEPRINT, 1, -1, [&"blueprint", &"engineering"]),
		ItemDef.new(&"blueprint_dry_dock", "Blueprint: Dry Dock", ItemDef.Category.BLUEPRINT, 1, -1, [&"blueprint", &"maritime"]),
		ItemDef.new(&"pine_sapling", "Pine Sapling", ItemDef.Category.SPECIAL, 20, -1, [&"placeable", &"sapling", &"forestry"]),
	]
	for s in specials:
		register_item(s)
