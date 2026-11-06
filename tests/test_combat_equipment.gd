extends SceneTree
## Automated headless test suite for Brine's Hollow Armor Tiers, Marine Weapons & Paperdoll Equipment.

func _init() -> void:
	print("==================================================")
	print("Running Brine's Hollow Combat & Equipment Tests...")
	print("==================================================")

	var stats := [0, 0] # [passed, total]

	var assert_test := func(desc: String, condition: bool) -> void:
		stats[1] += 1
		if condition:
			stats[0] += 1
			print("  [PASS] %s" % desc)
		else:
			push_error("  [FAIL] %s" % desc)

	ItemDB.init_db()

	# -------------------------------------------------------------------------
	# 1. Weapon Catalogue & Special Capabilities
	# -------------------------------------------------------------------------
	var sabre: ItemDef = ItemDB.get_item(&"corsair_sabre")
	assert_test.call("Corsair Sabre registered in ItemDB", sabre != null and sabre.category == ItemDef.Category.TOOL)
	assert_test.call("Corsair Sabre deals 24 slashing damage", sabre.weapon_data.get("damage", 0) == 24)
	assert_test.call("Corsair Sabre harvests dense kelp", sabre.weapon_data.get("harvests_kelp", false) == true)

	var harpoon: ItemDef = ItemDB.get_item(&"heavy_harpoon")
	assert_test.call("Heavy Harpoon registered in ItemDB", harpoon != null)
	assert_test.call("Heavy Harpoon has 15m tether cable", harpoon.weapon_data.get("tether_length_m", 0.0) == 15.0)
	assert_test.call("Heavy Harpoon has 95% underwater efficiency", harpoon.weapon_data.get("underwater_efficiency", 0.0) >= 0.95)

	var maul: ItemDef = ItemDB.get_item(&"anchor_maul")
	assert_test.call("Anchor Maul deals 45 damage with high stagger",
		maul.weapon_data.get("damage", 0) == 45 and maul.weapon_data.get("stagger_power", 0.0) >= 2.0)
	assert_test.call("Anchor Maul shatters rock and carapace", maul.weapon_data.get("breaks_rock", false) == true)

	var speargun: ItemDef = ItemDB.get_item(&"pneumatic_speargun")
	assert_test.call("Pneumatic Speargun is ranged with 25m/s projectile",
		speargun.weapon_data.get("is_ranged", false) == true and speargun.weapon_data.get("projectile_speed_m_s", 0.0) == 25.0)

	var net: ItemDef = ItemDB.get_item(&"weighted_trapper_net")
	assert_test.call("Trapper Net has 8m tether length", net.weapon_data.get("tether_length_m", 0.0) == 8.0)

	var staff: ItemDef = ItemDB.get_item(&"phosphor_lantern_staff")
	assert_test.call("Phosphor Lantern Staff registered with 3m reach", staff.weapon_data.get("reach_m", 0.0) == 3.0)

	# -------------------------------------------------------------------------
	# 2. Armor Catalogue & Properties
	# -------------------------------------------------------------------------
	var souwester: ItemDef = ItemDB.get_item(&"oilskin_souwester")
	assert_test.call("Oilskin Sou'wester equips to head", souwester != null and souwester.equip_slot == &"head")
	assert_test.call("Oilskin Sou'wester grants cold protection", souwester.armor_data.get("cold_protection", 0.0) == 0.25)

	var coat: ItemDef = ItemDB.get_item(&"oilskin_coat")
	assert_test.call("Oilskin Coat equips to body with 4 defense", coat != null and coat.armor_data.get("defense", 0) == 4)

	var waders: ItemDef = ItemDB.get_item(&"fisherman_waders")
	assert_test.call("Fisherman Waders equip to legs", waders != null and waders.equip_slot == &"legs")

	var deep_helm: ItemDef = ItemDB.get_item(&"deep_diving_helmet")
	assert_test.call("Deep-Diving Helmet grants 180s extra air and 85m safe depth",
		deep_helm.armor_data.get("extra_breath_sec", 0.0) == 180.0 and deep_helm.armor_data.get("max_safe_depth_m", 0.0) == 85.0)

	var lead_suit: ItemDef = ItemDB.get_item(&"lead_diving_suit")
	assert_test.call("Lead Diving Suit grants 10 defense but reduces swim speed to 0.3x",
		lead_suit.armor_data.get("defense", 0) == 10 and lead_suit.armor_data.get("swim_speed_mult", 1.0) == 0.3)
	assert_test.call("Lead Diving Suit has negative buoyancy (-1.5)", lead_suit.armor_data.get("buoyancy_offset", 0.0) == -1.5)

	var flippers: ItemDef = ItemDB.get_item(&"flippers_seal_leather")
	assert_test.call("Flippers boost swim speed to 1.35x and add positive buoyancy",
		flippers.armor_data.get("swim_speed_mult", 1.0) == 1.35 and flippers.armor_data.get("buoyancy_offset", 0.0) == 0.2)

	# -------------------------------------------------------------------------
	# 3. Paperdoll Equipment Slots & Aliasing
	# -------------------------------------------------------------------------
	var inv := Inventory.new(24)
	assert_test.call("Inventory has head equipment slot", inv.equipment.has(&"head"))
	assert_test.call("Inventory has body equipment slot", inv.equipment.has(&"body"))
	assert_test.call("Inventory has legs equipment slot", inv.equipment.has(&"legs"))
	assert_test.call("Inventory has boots equipment slot", inv.equipment.has(&"boots"))
	assert_test.call("Inventory has accessory equipment slot", inv.equipment.has(&"accessory"))
	assert_test.call("Inventory has map equipment slot", inv.equipment.has(&"map"))
	assert_test.call("Minimap is initially disabled without chart", not inv.is_minimap_enabled())

	# Test map equipping
	inv.add_item(&"hydrographic_sea_chart", 1)
	assert_test.call("Equip hydrographic sea chart into map slot", inv.equip_item_from_slot(0))
	assert_test.call("Map equipment slot holds hydrographic sea chart", inv.equipment[&"map"].item_id == &"hydrographic_sea_chart")
	assert_test.call("Minimap is enabled with equipped sea chart", inv.is_minimap_enabled())
	assert_test.call("Equipped map def retrieved with Tier 2 properties",
		inv.get_equipped_map_def() != null and inv.get_equipped_map_def().tool_data.get("map_tier", 0) == 2)

	inv.unequip_item(&"map")
	assert_test.call("Unequipping chart disables minimap", not inv.is_minimap_enabled())
	inv.remove_item(&"hydrographic_sea_chart", 1)

	# Test chest alias
	inv.add_item(&"oilskin_coat", 1)
	var equip_ok := inv.equip_item_from_slot(0)
	assert_test.call("Equip oilskin coat from slot 0 succeeds", equip_ok)
	assert_test.call("Oilskin coat equipped in 'body' slot", inv.equipment[&"body"].item_id == &"oilskin_coat")

	# Equip other pieces of Oilskin set
	inv.add_item(&"oilskin_souwester", 1)
	inv.equip_item_from_slot(0)
	inv.add_item(&"fisherman_waders", 1)
	inv.equip_item_from_slot(0)
	inv.add_item(&"spiked_ice_boots", 1)
	inv.equip_item_from_slot(0)

	assert_test.call("Oilskin set fully equipped in paperdoll",
		inv.equipment[&"head"].item_id == &"oilskin_souwester" and
		inv.equipment[&"body"].item_id == &"oilskin_coat" and
		inv.equipment[&"legs"].item_id == &"fisherman_waders" and
		inv.equipment[&"boots"].item_id == &"spiked_ice_boots")

	# -------------------------------------------------------------------------
	# 4. Cumulative Stat Calculations (Oilskin Tier 1)
	# -------------------------------------------------------------------------
	# Defense: souwester(2) + coat(4) + waders(3) + boots(2) = 11
	assert_test.call("Cumulative defense for Oilskin set is 11", inv.get_total_defense() == 11)

	# Cold protection: souwester(0.25) + coat(0.35) + waders(0.25) + boots(0.15) = 1.0 (clamped)
	assert_test.call("Cumulative cold protection is 1.0 (warm & storm-proof)", is_equal_approx(inv.get_cold_protection(), 1.0))

	# Safe depth for standard gear
	assert_test.call("Max safe depth for Oilskin set is 25m", inv.get_max_safe_depth() == 25.0)

	# Swim speed modifier
	assert_test.call("Standard boots swim speed is 1.0x", is_equal_approx(inv.get_swim_speed_multiplier(), 1.0))

	# -------------------------------------------------------------------------
	# 5. Deep-Diving Gear Tradeoffs (Tier 3)
	# -------------------------------------------------------------------------
	inv.unequip_item(&"head")
	inv.unequip_item(&"body")
	inv.unequip_item(&"boots")

	inv.add_item(&"deep_diving_helmet", 1)
	inv.equip_item_from_slot(inv.get_item_count(&"deep_diving_helmet") - 1)
	# Equip directly by adding into slot
	inv.equipment[&"head"] = ItemSlot.new(&"deep_diving_helmet", 1)
	inv.equipment[&"body"] = ItemSlot.new(&"lead_diving_suit", 1)
	inv.equipment[&"boots"] = ItemSlot.new(&"lead_diving_boots", 1)

	assert_test.call("Diving suit and waders boost defense to 24", inv.get_total_defense() == 24)
	assert_test.call("Diving helmet extends safe depth to 85m", inv.get_max_safe_depth() == 85.0)
	assert_test.call("Diving helmet adds 180s extra underwater breath", inv.get_extra_breath() == 180.0)

	var heavy_swim_mult := inv.get_swim_speed_multiplier()
	assert_test.call("Lead diving suit & boots severely penalize swim speed (< 0.15x)", heavy_swim_mult < 0.15)

	var heavy_buoyancy := inv.get_buoyancy_offset()
	assert_test.call("Lead diving suit & boots create heavy negative buoyancy (-3.0)", heavy_buoyancy <= -3.0)

	# -------------------------------------------------------------------------
	# 6. Flippers Aquatic Mobility
	# -------------------------------------------------------------------------
	inv.equipment[&"boots"] = ItemSlot.new(&"flippers_seal_leather", 1)
	inv.equipment[&"body"] = ItemSlot.new() # Remove heavy suit
	var fast_swim_mult := inv.get_swim_speed_multiplier()
	assert_test.call("Flippers provide 1.35x swim speed multiplier", is_equal_approx(fast_swim_mult, 1.35))
	assert_test.call("Flippers provide positive upward buoyancy", inv.get_buoyancy_offset() > 0.0)

	# -------------------------------------------------------------------------
	# 7. Active Weapon Detection
	# -------------------------------------------------------------------------
	inv.slots[inv.active_hotbar_index] = ItemSlot.new(&"corsair_sabre", 1)
	var active_wep := inv.get_active_weapon()
	assert_test.call("Active hotbar weapon detected as Corsair Sabre", active_wep != null and active_wep.id == &"corsair_sabre")

	inv.slots[inv.active_hotbar_index] = ItemSlot.new(&"stone", 10) # Not a weapon
	inv.equipment[&"main_hand"] = ItemSlot.new(&"heavy_harpoon", 1)
	var equipped_wep := inv.get_active_weapon()
	assert_test.call("Fallback to main_hand weapon when hotbar holds voxels", equipped_wep != null and equipped_wep.id == &"heavy_harpoon")

	# -------------------------------------------------------------------------
	# 8. Character Model Equipment Paperdoll Signals
	# -------------------------------------------------------------------------
	var model := CharacterModel.new()
	root.add_child(model)
	model.setup()

	# Wire equipment changed
	inv.equipment_changed.connect(func(slot_name: StringName, slot: ItemSlot) -> void:
		if slot_name == &"backpack":
			model.set_backpack_visible(not slot.is_empty())
		elif slot_name == &"head":
			var is_helm: bool = not slot.is_empty() and (slot.item_id == &"deep_diving_helmet" or slot.item_id == &"diving_rebreather")
			model.set_diving_helmet_visible(is_helm)
	)

	inv.equipment[&"backpack"] = ItemSlot.new(&"backpack_driftwood", 1)
	inv.equipment_changed.emit(&"backpack", inv.equipment[&"backpack"])
	assert_test.call("Equipping backpack makes 3D backpack visible on CharacterModel", model.backpack_node.visible)

	inv.equipment[&"backpack"] = ItemSlot.new()
	inv.equipment_changed.emit(&"backpack", inv.equipment[&"backpack"])
	assert_test.call("Unequipping backpack hides 3D backpack", not model.backpack_node.visible)

	inv.equipment[&"head"] = ItemSlot.new(&"deep_diving_helmet", 1)
	inv.equipment_changed.emit(&"head", inv.equipment[&"head"])
	assert_test.call("Equipping deep diving helmet activates 3D helmet on CharacterModel", model.diving_helmet_node.visible)

	inv.equipment[&"head"] = ItemSlot.new()
	inv.equipment_changed.emit(&"head", inv.equipment[&"head"])
	assert_test.call("Unequipping deep diving helmet hides 3D helmet", not model.diving_helmet_node.visible)

	model.queue_free()

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	if stats[0] == stats[1]:
		quit(0)
	else:
		quit(1)
