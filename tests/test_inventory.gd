extends SceneTree
## Headless test suite for the Brine's Hollow Inventory & Item System:
##   godot --headless --path . -s tests/test_inventory.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("==================================================")
	print("Running Brine's Hollow Inventory & Item Tests...")
	print("==================================================")

	var stats := [0, 0] # [passed, total]

	var assert_test := func(desc: String, condition: bool) -> void:
		stats[1] += 1
		if condition:
			stats[0] += 1
			print("  [PASS] ", desc)
		else:
			push_error("  [FAIL] " + desc)
			print("  [FAIL] ", desc)

	ItemDB.init_db()

	# -------------------------------------------------------------------------
	# 1. ItemDB Registry & Lookup Tests
	# -------------------------------------------------------------------------
	var wood_def: ItemDef = ItemDB.get_item(&"driftwood")
	assert_test.call("ItemDB contains driftwood", wood_def != null)
	assert_test.call("Driftwood max_stack is 999", wood_def and wood_def.max_stack == 999)
	assert_test.call("Driftwood voxel_mat is Palette.DRIFTWOOD", wood_def and wood_def.voxel_mat == Palette.DRIFTWOOD)

	var fish_def: ItemDef = ItemDB.get_item(&"silver_mackerel")
	assert_test.call("ItemDB contains silver_mackerel with tag 'fish'", fish_def and fish_def.has_tag("fish"))
	assert_test.call("Silver Mackerel max_stack is 20", fish_def and fish_def.max_stack == 20)

	var pick_def: ItemDef = ItemDB.get_item(&"driftwood_pickaxe")
	assert_test.call("Pickaxe is Category.TOOL with max_stack 1", pick_def and pick_def.category == ItemDef.Category.TOOL and pick_def.max_stack == 1)

	var voxel_item: ItemDef = ItemDB.get_by_voxel_mat(Palette.STONE)
	assert_test.call("Palette.STONE maps to Limestone item", voxel_item and voxel_item.id == &"stone")

	# -------------------------------------------------------------------------
	# 2. Inventory Stacking & Overflows
	# -------------------------------------------------------------------------
	var inv := Inventory.new(8) # Small 8-slot inventory for testing
	var rem1 := inv.add_item(&"silver_mackerel", 15)
	assert_test.call("Add 15 mackerel fits into single slot (rem=0)", rem1 == 0 and inv.slots[0].count == 15)

	var rem2 := inv.add_item(&"silver_mackerel", 10)
	assert_test.call("Add 10 mackerel stacks 5 onto slot 0 (count=20) and 5 onto slot 1",
		rem2 == 0 and inv.slots[0].count == 20 and inv.slots[1].count == 5)

	assert_test.call("get_item_count returns total of 25 mackerel", inv.get_item_count(&"silver_mackerel") == 25)

	# Fill remaining 6 slots
	for i in range(2, 8):
		inv.add_item(&"driftwood_pickaxe", 1)
	assert_test.call("Inventory slots are all occupied", inv.slots[7].item_id == &"driftwood_pickaxe")

	var overflow := inv.add_item(&"driftwood_pickaxe", 1)
	assert_test.call("Attempting to add to full inventory returns remainder 1", overflow == 1)

	# -------------------------------------------------------------------------
	# 3. Item Removal & Count Tracking
	# -------------------------------------------------------------------------
	var removed := inv.remove_item(&"silver_mackerel", 8)
	assert_test.call("Removed 8 mackerel successfully", removed == 8)
	assert_test.call("Remaining mackerel count is 17", inv.get_item_count(&"silver_mackerel") == 17)
	assert_test.call("Slot 1 cleared (had 5, needed 5), Slot 0 has 17 left", inv.slots[1].is_empty() and inv.slots[0].count == 17)

	# -------------------------------------------------------------------------
	# 4. Swapping & Stack Merging
	# -------------------------------------------------------------------------
	# Directly place 2 mackerel into slot 1 to test merging
	inv.slots[1] = ItemSlot.new(&"silver_mackerel", 2)
	assert_test.call("Slot 1 now has 2 mackerel", inv.slots[1].count == 2)

	# Merge slot 1 into slot 0 (slot 0 has 17, max is 20; adding 2 brings it to 19)
	var merged := inv.swap_or_merge_slots(1, 0)
	assert_test.call("Merged slot 1 into slot 0 (slot 0=19, slot 1 empty)",
		merged and inv.slots[0].count == 19 and inv.slots[1].is_empty())

	# -------------------------------------------------------------------------
	# 5. Split Stack
	# -------------------------------------------------------------------------
	# Split 9 from slot 0 (which has 19) into empty slot 1
	var split_ok := inv.split_stack(0, 1, 9)
	assert_test.call("Split stack: slot 0 has 10, slot 1 has 9",
		split_ok and inv.slots[0].count == 10 and inv.slots[1].count == 9)

	# -------------------------------------------------------------------------
	# 6. Quick Sort & Stack Consolidation
	# -------------------------------------------------------------------------
	var sort_inv := Inventory.new(16)
	# Directly configure hotbar slots (0..7) to verify they are preserved
	sort_inv.slots[0] = ItemSlot.new(&"stone", 50)
	sort_inv.slots[1] = ItemSlot.new(&"silver_mackerel", 5)
	# Add scattered items in non-hotbar slots (8..15)
	sort_inv.slots[9] = ItemSlot.new(&"driftwood", 40)
	sort_inv.slots[11] = ItemSlot.new(&"shore_wheat", 10)
	sort_inv.slots[13] = ItemSlot.new(&"driftwood", 25)

	# Quick sort preserving hotbar
	sort_inv.quick_sort(true)
	assert_test.call("Quick sort preserved hotbar slots (slot 0=50 stone, slot 1=5 mackerel)",
		sort_inv.slots[0].item_id == &"stone" and sort_inv.slots[0].count == 50 and
		sort_inv.slots[1].item_id == &"silver_mackerel" and sort_inv.slots[1].count == 5)
	assert_test.call("Non-hotbar driftwood consolidated into single slot (count=65)",
		sort_inv.slots[8].item_id == &"driftwood" and sort_inv.slots[8].count == 65)

	# -------------------------------------------------------------------------
	# 7. Equipment & Backpack Expansion
	# -------------------------------------------------------------------------
	var char_inv := Inventory.new(24) # Base 24 capacity
	char_inv.add_item(&"backpack_driftwood", 1)
	assert_test.call("Equip slot 0 with driftwood backpack", char_inv.equip_item_from_slot(0))
	assert_test.call("Equipping backpack expands capacity to 36 slots", char_inv.capacity == 36 and char_inv.slots.size() == 36)
	assert_test.call("Backpack equipment slot is occupied", char_inv.equipment[&"backpack"].item_id == &"backpack_driftwood")

	assert_test.call("Unequip backpack", char_inv.unequip_item(&"backpack"))
	assert_test.call("Unequipping backpack restores capacity to base 24", char_inv.capacity == 24 and char_inv.slots.size() == 24)

	# -------------------------------------------------------------------------
	# 8. Filtered Storage Containers (Watertight Barrel)
	# -------------------------------------------------------------------------
	var fish_barrel := StorageContainer.new("Fish Barrel", 18, [&"fish", &"shellfish"], true)
	var fish_rem := fish_barrel.deposit(&"silver_mackerel", 12)
	assert_test.call("Fish barrel accepts silver_mackerel", fish_rem == 0 and fish_barrel.inventory.get_item_count(&"silver_mackerel") == 12)

	var stone_rem := fish_barrel.deposit(&"stone", 10)
	assert_test.call("Fish barrel rejects stone (returns all 10)", stone_rem == 10)

	# -------------------------------------------------------------------------
	# 9. Serialization Roundtrip
	# -------------------------------------------------------------------------
	var save_data := char_inv.serialize()
	var loaded_inv := Inventory.new(8)
	var loaded_ok := loaded_inv.deserialize(save_data)
	assert_test.call("Inventory deserialization succeeds", loaded_ok)
	assert_test.call("Deserialized inventory matches capacity and contents",
		loaded_inv.capacity == char_inv.capacity and
		loaded_inv.get_item_count(&"backpack_driftwood") == char_inv.get_item_count(&"backpack_driftwood"))

	print("==================================================")
	# -------------------------------------------------------------------------
	# 10. Configurable Hotbar, Hammer Detection & Quick Transfer
	# -------------------------------------------------------------------------
	var hammer_def: ItemDef = ItemDB.get_item(&"builders_hammer")
	assert_test.call("ItemDB contains builders_hammer with tag 'hammer'", hammer_def != null and hammer_def.has_tag("hammer"))
	var hoe_def: ItemDef = ItemDB.get_item(&"driftwood_hoe")
	assert_test.call("ItemDB contains driftwood_hoe with tag 'hoe'", hoe_def != null and hoe_def.has_tag("hoe"))

	var hb_inv := Inventory.new(24)
	hb_inv.slots[10] = ItemSlot.new(&"builders_hammer", 1)
	hb_inv.slots[11] = ItemSlot.new(&"driftwood", 30)
	assert_test.call("Move builders_hammer from backpack slot 10 to hotbar slot 2",
		hb_inv.move_to_hotbar(10, 2) and hb_inv.slots[2].item_id == &"builders_hammer" and hb_inv.slots[10].is_empty())
	hb_inv.set_active_hotbar_index(2)
	assert_test.call("is_hammer_active() returns true when hammer is in active hotbar slot", hb_inv.is_hammer_active())
	hb_inv.set_active_hotbar_index(0)
	assert_test.call("is_hammer_active() returns false when active slot is empty", not hb_inv.is_hammer_active())

	# Quick transfer between backpack and hotbar
	assert_test.call("Quick transfer backpack slot 11 moves driftwood to first open hotbar slot (0)",
		hb_inv.quick_transfer_slot(11) and hb_inv.slots[0].item_id == &"driftwood" and hb_inv.slots[0].count == 30)
	assert_test.call("Quick transfer hotbar slot 0 moves driftwood back to backpack (slot 8)",
		hb_inv.quick_transfer_slot(0) and hb_inv.slots[0].is_empty() and hb_inv.slots[8].item_id == &"driftwood")

	# -------------------------------------------------------------------------
	# 11. Player Configurable Hotbar & Hammer Build Modes
	# -------------------------------------------------------------------------
	var player := Player.new()
	player.inventory.slots[0] = ItemSlot.new(&"driftwood_pickaxe", 1)
	player.inventory.slots[1] = ItemSlot.new(&"builders_hammer", 1)
	player.inventory.slots[2] = ItemSlot.new(&"whittle_rod", 1)
	player.inventory.slots[3] = ItemSlot.new(&"driftwood_hoe", 1)
	player.inventory.slots[4] = ItemSlot.new(&"rusty_cutlass", 1)
	player.select_hotbar_slot(0)
	assert_test.call("Selecting pickaxe slot sets tool to 0 (Sculpt/Mine) and unequips hammer",
		player.tool == 0 and not player.is_hammer_equipped())
	player.select_hotbar_slot(1)
	assert_test.call("Selecting hammer slot equips hammer", player.is_hammer_equipped())
	player.select_hammer_prefab(3)
	assert_test.call("Selecting hammer prefab sets hammer_build_mode=0 (PREFAB) and tool=2",
		player.hammer_build_mode == 0 and player.tool == 2 and player.prefab_id == 3)
	player.select_hammer_block(4)
	assert_test.call("Selecting hammer block sets hammer_build_mode=1 (BLOCK) and tool=1 with mat_index=4",
		player.hammer_build_mode == 1 and player.tool == 1 and player.mat_index == 4)
	var first_furniture: StringName = Placeables.blueprint_types()[0]
	player.select_hammer_furniture(first_furniture)
	assert_test.call("Selecting hammer furniture sets hammer_build_mode=2 (FURNITURE) and tool=2",
		player.hammer_build_mode == 2 and player.tool == 2 and (player.placement == null or player.placement.entity_blueprint == first_furniture))
	player.select_hotbar_slot(2)
	assert_test.call("Selecting rod slot sets tool to 3 (Fishing Rod)", player.tool == 3 and not player.is_hammer_equipped())
	player.select_hotbar_slot(3)
	assert_test.call("Selecting hoe slot sets tool to 4 (Farming)", player.tool == 4)

	# -------------------------------------------------------------------------
	# 12. Tool Tiers & Material Harvesting Gating
	# -------------------------------------------------------------------------
	assert_test.call("Tiered pickaxes exist in ItemDB (stone, copper, iron)",
		ItemDB.has_item(&"stone_pickaxe") and ItemDB.has_item(&"copper_pickaxe") and ItemDB.has_item(&"iron_pickaxe"))
	assert_test.call("Tiered hatchets exist in ItemDB (driftwood, stone, copper, iron)",
		ItemDB.has_item(&"driftwood_axe") and ItemDB.has_item(&"stone_axe") and ItemDB.has_item(&"copper_axe") and ItemDB.has_item(&"iron_axe"))
	assert_test.call("Tiered shovels exist in ItemDB (driftwood, stone, iron)",
		ItemDB.has_item(&"driftwood_shovel") and ItemDB.has_item(&"stone_shovel") and ItemDB.has_item(&"iron_shovel"))

	# Equip pickaxe (slot 0) -> can harvest stone, dirt, and tree trunks
	player.select_hotbar_slot(0)
	assert_test.call("With pickaxe equipped: can harvest STONE and DIRT",
		player.can_harvest_voxel(Palette.STONE) and player.can_harvest_voxel(Palette.DIRT))

	# Equip hatchet in slot 5 -> can harvest tree trunks and dirt, NOT stone
	player.inventory.slots[5] = ItemSlot.new(&"driftwood_axe", 1)
	player.select_hotbar_slot(5)
	assert_test.call("With hatchet equipped: can harvest TRUNK and DIRT, but NOT STONE",
		player.can_harvest_voxel(Palette.TRUNK) and player.can_harvest_voxel(Palette.DIRT) and not player.can_harvest_voxel(Palette.STONE))
	assert_test.call("A hatchet fells trees (has_axe_equipped)", player.has_axe_equipped() and player.can_cut_wood())
	player.select_hotbar_slot(0)
	assert_test.call("A pickaxe chips wood but does not count as a hatchet", player.can_cut_wood() and not player.has_axe_equipped())
	player.select_hotbar_slot(5)

	# Empty slot 6 (bare hands) -> can harvest DIRT and GRASS, NOT STONE or TRUNK
	player.inventory.slots[6] = ItemSlot.new()
	player.select_hotbar_slot(6)
	assert_test.call("Bare-handed: can harvest DIRT and GRASS, but NOT STONE or TRUNK",
		player.can_harvest_voxel(Palette.DIRT) and player.can_harvest_voxel(Palette.GRASS) and not player.can_harvest_voxel(Palette.STONE) and not player.can_harvest_voxel(Palette.TRUNK))

	# -------------------------------------------------------------------------
	# 13. DroppedItem Walk-Over Pickup
	# -------------------------------------------------------------------------
	var drop_root := Node3D.new()
	player.position = Vector3(10.0, 5.0, 10.0)
	var stone_before := player.inventory.get_item_count(&"stone")
	var drop := DroppedItem.spawn_drop(drop_root, null, player, Vector3(20.0, 5.0, 20.0), &"stone", 4)
	assert_test.call("DroppedItem spawns at mined location without adding to inventory while far away",
		drop != null and player.inventory.get_item_count(&"stone") == stone_before)
	# Walk player over to the dropped item after pickup_delay
	drop.age = 1.0
	player.position = Vector3(20.0, 5.0, 20.0)
	for _step in 10:
		drop._process(0.05)
	assert_test.call("Walking over DroppedItem magnetizes and collects items into player inventory",
		player.inventory.get_item_count(&"stone") == stone_before + 4)
	drop_root.free()

	# -------------------------------------------------------------------------
	# 14. InventoryUI & BuildMenuUI Instantiation
	# -------------------------------------------------------------------------
	var inv_ui := InventoryUI.new()
	var build_ui := BuildMenuUI.new()
	assert_test.call("InventoryUI and BuildMenuUI instantiate cleanly", inv_ui != null and build_ui != null)
	inv_ui.free()
	build_ui.free()
	player.free()

	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	quit(0 if stats[0] == stats[1] else 1)
