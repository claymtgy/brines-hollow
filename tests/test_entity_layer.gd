extends SceneTree
## Automated headless test suite for Brine's Hollow Entity Layer (Placeable Workstations & Furniture).

func _init() -> void:
	print("==================================================")
	print("Running Brine's Hollow Entity Layer Tests...")
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
	RecipeDB.init_db()

	# -------------------------------------------------------------------------
	# 1. EntityManager Lifecycle & Spawning
	# -------------------------------------------------------------------------
	var em := EntityManager.new()
	assert_test.call("EntityManager instantiates cleanly", em != null)
	assert_test.call("Initially contains 0 entities", em.get_count() == 0)

	var wb: StationEntity = em.spawn_entity(&"workbench", Vector3i(10, 5, 10)) as StationEntity
	assert_test.call("Spawned workbench as StationEntity", wb != null and wb.station_tag == &"workbench")
	assert_test.call("EntityManager count is now 1", em.get_count() == 1)
	assert_test.call("Entity located at (10, 5, 10)", em.has_entity_at(Vector3i(10, 5, 10)))

	var chest: ChestEntity = em.spawn_entity(&"driftwood_chest", Vector3i(12, 5, 10)) as ChestEntity
	assert_test.call("Spawned driftwood chest as ChestEntity", chest != null and chest.container != null)

	var bed: BedEntity = em.spawn_entity(&"fisher_bed", Vector3i(8, 5, 10)) as BedEntity
	assert_test.call("Spawned fisher bed as BedEntity", bed != null and bed.entity_type == WorldEntity.EntityType.BED)

	var mirror: MirrorEntity = em.spawn_entity(&"barber_mirror", Vector3i(10, 5, 12)) as MirrorEntity
	assert_test.call("Spawned barber mirror as MirrorEntity", mirror != null and mirror.entity_type == WorldEntity.EntityType.MIRROR)

	assert_test.call("Total entity count is 4", em.get_count() == 4)

	# -------------------------------------------------------------------------
	# 2. Proximity Spatial Queries
	# -------------------------------------------------------------------------
	# Player standing right next to workbench (10.5 * VS, 5 * VS, 10.5 * VS)
	var wb_world_pos := (Vector3(10, 5, 10) + Vector3(0.5, 0, 0.5)) * VoxelWorld.VS
	var closest_wb := em.get_closest_interactable(wb_world_pos + Vector3(0.05, 0, 0))
	assert_test.call("Closest interactable at workbench pos is workbench", closest_wb == wb)

	var far_pos := Vector3(100.0, 5.0, 100.0)
	var far_interactable := em.get_closest_interactable(far_pos)
	assert_test.call("Query far away (>3.2m) returns null", far_interactable == null)

	# -------------------------------------------------------------------------
	# 3. Workstation Entity Interaction & Crafting
	# -------------------------------------------------------------------------
	var player := Player.new()
	player.inventory.add_item(&"driftwood", 4)
	assert_test.call("Workbench interaction prompt reflects craftable plank", "Craft Wood Planks" in wb.get_interaction_prompt(player))

	wb.interact(player)
	assert_test.call("Interacting with workbench crafted wood planks", player.inventory.get_item_count(&"wood_plank") == 4)
	assert_test.call("Consumed 1 driftwood from player inventory", player.inventory.get_item_count(&"driftwood") == 3)

	# Smokehouse with fuel
	var smokehouse: StationEntity = em.spawn_entity(&"smokehouse", Vector3i(14, 5, 10)) as StationEntity
	assert_test.call("Smokehouse is initially unfueled", smokehouse.station.fuel_remaining_sec == 0.0)
	smokehouse.interact(player) # player has driftwood, should add fuel
	assert_test.call("Interacting with unfueled smokehouse fueled it", smokehouse.station.fuel_remaining_sec > 0.0)

	# -------------------------------------------------------------------------
	# 4. Chest Entity Storage (Deposit & Retrieval)
	# -------------------------------------------------------------------------
	player.inventory.active_hotbar_index = 0
	# Slot 0 contains driftwood
	var active_slot := player.inventory.get_active_item()
	var prev_dw_count := active_slot.count

	chest.interact(player) # should deposit active item into chest
	assert_test.call("Deposited active driftwood into chest", chest.container.inventory.get_item_count(&"driftwood") == prev_dw_count)
	assert_test.call("Player inventory slot is now empty", player.inventory.get_active_item().is_empty())

	chest.interact(player) # active slot is empty; should retrieve stored driftwood from chest
	assert_test.call("Retrieved driftwood back from chest", player.inventory.has_item(&"driftwood", 1))

	# -------------------------------------------------------------------------
	# 5. Bed Entity Restful Sleep & Vitality Buff
	# -------------------------------------------------------------------------
	player.vitality.current_hp = 10.0
	player.vitality.current_stamina = 5.0
	player.vitality.is_rested = false

	bed.interact(player)
	assert_test.call("Bed interaction restored HP to max", player.vitality.current_hp >= 25.0)
	assert_test.call("Bed interaction restored Stamina to max", player.vitality.current_stamina >= 50.0)
	assert_test.call("Bed interaction applied Sea-Breeze Rested buff", player.vitality.is_rested)

	# -------------------------------------------------------------------------
	# 6. Mirror Entity Fisherfolk Wardrobe Customization
	# -------------------------------------------------------------------------
	var init_hair := player.customizer.hair_style
	mirror.interact(player)
	assert_test.call("Interacting with barber mirror cycled hairstyle", player.customizer.hair_style != init_hair)

	# -------------------------------------------------------------------------
	# 7. Entity Layer Persistence & Deserialization
	# -------------------------------------------------------------------------
	var saved_data := em.serialize()
	assert_test.call("Serialized entity array contains all active entities", saved_data.size() == em.get_count())

	var em_restored := EntityManager.new()
	em_restored.deserialize(saved_data)
	assert_test.call("Restored entity manager has matching count", em_restored.get_count() == saved_data.size())

	var restored_wb := em_restored.get_entity_at(Vector3i(10, 5, 10)) as StationEntity
	assert_test.call("Restored workbench exists at (10, 5, 10)", restored_wb != null and restored_wb.station_tag == &"workbench")

	var restored_chest := em_restored.get_entity_at(Vector3i(12, 5, 10)) as ChestEntity
	assert_test.call("Restored chest exists and retains stored items", restored_chest != null and restored_chest.container != null)

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	if stats[0] == stats[1]:
		print("ALL ENTITY LAYER TESTS PASSED!")
		quit(0)
	else:
		push_error("SOME TESTS FAILED!")
		quit(1)
