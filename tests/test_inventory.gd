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
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	quit(0 if stats[0] == stats[1] else 1)
