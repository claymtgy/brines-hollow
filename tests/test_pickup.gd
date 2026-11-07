extends SceneTree

var passed := 0
var total := 0

func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)

func _init() -> void:
	print("--- Testing Block Drops & Player Walk-Over Pickup ---")
	ItemDB.init_db()

	# 1. Test ItemDB voxel material mappings including terrain variants
	check(ItemDB.get_by_voxel_mat(Palette.STONE) != null and ItemDB.get_by_voxel_mat(Palette.STONE).id == &"stone", "STONE drops limestone")
	check(ItemDB.get_by_voxel_mat(Palette.DIRT) != null and ItemDB.get_by_voxel_mat(Palette.DIRT).id == &"dirt", "DIRT drops dirt")
	check(ItemDB.get_by_voxel_mat(Palette.GRASS) != null and ItemDB.get_by_voxel_mat(Palette.GRASS).id == &"dirt", "GRASS drops dirt")
	check(ItemDB.get_by_voxel_mat(Palette.GRASS_DRY) != null and ItemDB.get_by_voxel_mat(Palette.GRASS_DRY).id == &"dirt", "GRASS_DRY drops dirt")
	check(ItemDB.get_by_voxel_mat(Palette.WET_SAND) != null and ItemDB.get_by_voxel_mat(Palette.WET_SAND).id == &"sand", "WET_SAND drops sand")
	check(ItemDB.get_by_voxel_mat(Palette.GRAVEL) != null and ItemDB.get_by_voxel_mat(Palette.GRAVEL).id == &"stone", "GRAVEL drops stone")
	check(ItemDB.get_by_voxel_mat(Palette.SANDSTONE_B) != null and ItemDB.get_by_voxel_mat(Palette.SANDSTONE_B).id == &"sandstone", "SANDSTONE_B drops sandstone")
	check(ItemDB.get_by_voxel_mat(Palette.LEAVES_DARK) != null and ItemDB.get_by_voxel_mat(Palette.LEAVES_DARK).id == &"leaves", "LEAVES_DARK drops leaves")

	# 2. Test Inventory.has_space_for
	var inv := Inventory.new(8)
	check(inv.has_space_for(&"stone", 5), "Empty inventory has space for 5 stone")
	inv.add_item(&"stone", 999) # fill one slot
	check(inv.has_space_for(&"stone", 10), "Inventory with empty slots still has space for more stone")

	# Fill entire inventory with different unstackable items
	for i in range(1, 8):
		inv.slots[i].item_id = StringName("filler_%d" % i)
		inv.slots[i].count = 999
	check(not inv.has_space_for(&"dirt", 1), "Completely full inventory has no space for dirt")
	check(inv.has_space_for(&"stone", 0), "Space for 0 items returns true")

	# 3. Test DroppedItem collection into Player
	var p := Player.new()
	p.inventory = Inventory.new(16)
	var drop := DroppedItem.new()
	drop.item_id = &"dirt"
	drop.count = 3
	var collected := drop.collect_into_player(p)
	check(collected == 3, "collect_into_player returns 3 items collected")
	check(p.inventory.get_item_count(&"dirt") == 3, "Player inventory now contains 3 dirt")
	check(drop.count == 0, "Drop count reduced to 0")
	check(drop.is_queued_for_deletion(), "Drop queued for deletion upon collection")

	print("Tests finished: %d / %d passed" % [passed, total])
	quit(0 if passed == total else 1)
