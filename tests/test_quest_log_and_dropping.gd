extends SceneTree
## Headless test suite for Quest Log, Drop Items, Starter Quest Block Building & Overhead Quest Markers:
##   godot --headless --path . -s tests/test_quest_log_and_dropping.gd

const QuestLogUI := preload("res://scripts/ui/quest_log_ui.gd")

var passed := 0
var total := 0

func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		push_error("  [FAIL] " + label)
		print("  [FAIL] ", label)


func _initialize() -> void:
	print("==================================================")
	print("Running Quest Log, Dropping & Quest Marker Tests...")
	print("==================================================")

	ItemDB.init_db()
	RecipeDB.init_db()

	# -------------------------------------------------------------------------
	# 1. Test Inventory.remove_from_slot
	# -------------------------------------------------------------------------
	var inv := Inventory.new(16)
	inv.slots[0] = ItemSlot.new(&"driftwood", 10)
	inv.slots[1] = ItemSlot.new(&"sand", 5)

	var removed_part := inv.remove_from_slot(0, 3)
	check(removed_part == 3, "remove_from_slot removed 3 driftwood")
	check(inv.slots[0].count == 7, "Slot 0 remaining count is 7")

	var removed_all := inv.remove_from_slot(0, 7)
	check(removed_all == 7, "remove_from_slot removed remaining 7 driftwood")
	check(inv.slots[0].is_empty(), "Slot 0 is now empty")

	var removed_full_by_default := inv.remove_from_slot(1, -1)
	check(removed_full_by_default == 5, "remove_from_slot with -1 cleared slot 1 (removed 5)")
	check(inv.slots[1].is_empty(), "Slot 1 is now empty")

	# -------------------------------------------------------------------------
	# 2. Test Player.drop_item_from_inventory
	# -------------------------------------------------------------------------
	var player := Player.new()
	player.inventory = Inventory.new(16)
	player.inventory.slots[2] = ItemSlot.new(&"stone", 8)

	var root_node := Node.new()
	root_node.add_child(player)

	var drop1 := player.drop_item_from_inventory(2, 2)
	check(drop1 != null, "drop_item_from_inventory returned a DroppedItem")
	check(drop1.item_id == &"stone" and drop1.count == 2, "DroppedItem has item_id stone and count 2")
	check(player.inventory.slots[2].count == 6, "Player slot 2 now has 6 stone")
	check(drop1.pickup_delay >= 1.5, "DroppedItem has pickup delay >= 1.5s so it is not immediately re-collected")

	var drop2 := player.drop_item_from_inventory(2, -1)
	check(drop2 != null and drop2.count == 6, "drop_item_from_inventory with -1 dropped remaining 6 stone")
	check(player.inventory.slots[2].is_empty(), "Slot 2 is now empty")

	# -------------------------------------------------------------------------
	# 3. Test Starter Quest & Hammer Placement Mode (Blocks vs Fabrications)
	# -------------------------------------------------------------------------
	check(player.hammer_build_mode == 1, "Default hammer_build_mode is 1 (Individual Blocks, not Fabrications)")
	check(player.brush == 0, "Default brush is 0 (1x1 block)")

	# Player equips hammer and has sand from digging quest
	player.inventory.add_item(&"builders_hammer", 1)
	player.inventory.add_item(&"sand", 6)
	player.inventory.set_active_hotbar_index(0)
	player._sync_tool_from_hotbar()

	check(player.is_hammer_equipped(), "Hammer is equipped in active hotbar slot")
	check(player.tool == 1, "Equipping hammer with mode 1 sets tool to 1 (Block placement)")
	check(BuildCosts.item_for(Palette.BUILDABLE[player.mat_index]) == &"sand", "Hammer automatically selected buildable material paid for by Sand in bag")

	# Setup quest manager with tutorial mission 2: "Make Your Mark"
	var qm := QuestManager.new()
	var tut2 := QuestDef.new(&"tut_2_mark", "Make Your Mark", "Wren the Wayfarer")
	tut2.add_step("Place 5 blocks with the hammer", QuestDef.ObjectiveType.PLACE_VOXELS, &"", 5)
	qm.register_available_quest(tut2)
	qm.accept_quest(&"tut_2_mark")
	player.quests = qm

	# Simulate placing blocks with hammer
	for i in 5:
		player.quest_event(QuestDef.ObjectiveType.PLACE_VOXELS, &"")

	check(tut2.steps[0].is_completed, "Placing 5 blocks completes the quest objective step")
	check(tut2.steps[0].current_count == 5, "Step progress is 5/5")

	# Verify placing prefabs/fabrications does NOT complete PLACE_VOXELS
	var tut2_check := QuestDef.new(&"tut_2_verify", "Make Your Mark Verify", "Wren")
	tut2_check.add_step("Place 5 blocks with the hammer", QuestDef.ObjectiveType.PLACE_VOXELS, &"", 5)
	qm.register_available_quest(tut2_check)
	qm.accept_quest(&"tut_2_verify")

	for i in 3:
		player.quest_event(QuestDef.ObjectiveType.PLACE_PREFAB, &"")
	check(tut2_check.steps[0].current_count == 0, "Placing fabrications (PLACE_PREFAB) does not count towards PLACE_VOXELS")

	# -------------------------------------------------------------------------
	# 4. Test QuestLogUI
	# -------------------------------------------------------------------------
	var main_mock := Node.new()
	main_mock.set("quests", qm)
	main_mock.set("player", player)

	var quest_log = QuestLogUI.new()
	main_mock.add_child(quest_log)
	quest_log.setup(main_mock)

	check(not quest_log.is_open(), "QuestLogUI starts closed")
	quest_log.open()
	check(quest_log.is_open(), "QuestLogUI.open() opens the UI")
	check(quest_log.current_tab == QuestLogUI.Tab.ACTIVE, "QuestLogUI starts on ACTIVE tab")

	quest_log.current_tab = QuestLogUI.Tab.COMPLETED
	quest_log.refresh()
	check(quest_log.current_tab == QuestLogUI.Tab.COMPLETED, "Switched to COMPLETED tab")

	quest_log.toggle()
	check(not quest_log.is_open(), "QuestLogUI.toggle() closed the UI")

	# -------------------------------------------------------------------------
	# 5. Test Pausing Quest Rewards when Inventory is Full
	# -------------------------------------------------------------------------
	var full_inv := Inventory.new()
	for slot_i in full_inv.capacity:
		full_inv.slots[slot_i] = ItemSlot.new(&"rusty_cutlass", 1) # Full bag of non-stackable cutlasses

	var reward_quest := QuestDef.new(&"reward_test_quest", "Reward Test Quest", "Elder Brenda")
	reward_quest.add_step("Dig up 1 stone", QuestDef.ObjectiveType.GATHER_ITEM, &"stone", 1)
	reward_quest.rewards["brass_guilder"] = 15
	reward_quest.rewards["items"] = [{"id": "driftwood", "count": 10}]
	qm.register_available_quest(reward_quest)
	qm.accept_quest(&"reward_test_quest")

	check(not qm.can_accept_rewards(full_inv, reward_quest), "can_accept_rewards returns false when inventory has no room for driftwood and brass")

	# Complete the objective step with full inventory
	qm.notify_event(QuestDef.ObjectiveType.GATHER_ITEM, &"stone", 1, full_inv)

	check(qm.paused_reward_quests.has(&"reward_test_quest"), "Quest rewards are paused and added to paused_reward_quests")
	check(not qm.is_quest_completed(&"reward_test_quest"), "Quest is NOT marked completed while rewards are paused")
	check(qm.is_quest_active(&"reward_test_quest"), "Quest remains active awaiting reward claim")
	check(full_inv.get_item_count(&"driftwood") == 0, "No reward items were lost or added to full inventory")

	# Now free space in inventory by dropping/clearing 2 cutlasses (for 2 distinct reward items)
	full_inv.remove_from_slot(0, -1)
	full_inv.remove_from_slot(1, -1)
	check(full_inv.slots[0].is_empty() and full_inv.slots[1].is_empty(), "Cleared slots 0 & 1 to make room in inventory")
	check(qm.can_accept_rewards(full_inv, reward_quest), "can_accept_rewards now returns true with slots freed")

	# Check paused rewards
	var claimed_ids := qm.check_paused_rewards(full_inv)
	check(claimed_ids.has(&"reward_test_quest"), "check_paused_rewards claimed reward_test_quest")
	check(not qm.paused_reward_quests.has(&"reward_test_quest"), "reward_test_quest removed from paused_reward_quests")
	check(qm.is_quest_completed(&"reward_test_quest"), "Quest is now finalized and marked completed")
	check(full_inv.get_item_count(&"driftwood") == 10, "Player received 10 driftwood reward in newly freed space")
	check(full_inv.get_item_count(&"brass_guilder") == 15, "Player received 15 brass guilders reward")

	# -------------------------------------------------------------------------
	# 6. Test Quest Markers Above Characters (DrifterNPC & Wren)
	# -------------------------------------------------------------------------
	var npc_mara := DrifterNPC.new()
	var def_mara := DrifterDef.new(&"drifter_0", "Mara", DrifterDef.Profession.FISHER)
	npc_mara.setup(0, def_mara, Vector3(10, 0, 10), 1234)

	check(npc_mara.marker != null, "DrifterNPC has overhead marker Label3D")
	check(npc_mara.marker.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "Marker is billboarded")
	check(npc_mara.marker.no_depth_test == true, "Marker has no_depth_test enabled so it's visible through obstacles")

	# QuestManager has chore_mara_catch registered in available_quests with giver "Mara"
	var qm2 := QuestManager.new()
	check(qm2.available_quests.has(&"chore_mara_catch"), "chore_mara_catch is in available_quests")

	npc_mara.refresh_marker(qm2)
	check(npc_mara.marker.text == "!", "Character with an available quest displays '!' marker overhead")

	# Accept the quest: now Mara has an active quest with steps not yet completed
	qm2.accept_quest(&"chore_mara_catch")
	npc_mara.refresh_marker(qm2)
	check(npc_mara.marker.text == "", "Character with an active in-progress quest clears overhead marker")

	# Complete the first step (catch 2 silver mackerel). Remaining step is 'Return to Mara' (TALK_TO)
	qm2.notify_event(QuestDef.ObjectiveType.CATCH_FISH, &"silver_mackerel", 2, null)
	var active_mara_q: QuestDef = qm2.active_quests.get(&"chore_mara_catch")
	check(active_mara_q != null and active_mara_q.steps[0].is_completed, "Step 1 (catch fish) is completed")
	check(not active_mara_q.steps[1].is_completed, "Step 2 (Return to Mara) is waiting for turn-in")

	npc_mara.refresh_marker(qm2)
	check(npc_mara.marker.text == "?", "Character with quest ready to turn in displays '?' marker overhead")

	# Test paused rewards displays '?'
	var full_inv2 := Inventory.new()
	for slot_i in full_inv2.capacity:
		full_inv2.slots[slot_i] = ItemSlot.new(&"rusty_cutlass", 1)
	# Turn in TALK_TO with full bag
	qm2.notify_event(QuestDef.ObjectiveType.TALK_TO, &"Mara", 1, full_inv2)
	check(qm2.paused_reward_quests.has(&"chore_mara_catch"), "Rewards paused on full inventory")
	npc_mara.refresh_marker(qm2)
	check(npc_mara.marker.text == "?", "Character keeps '?' marker when quest rewards are paused awaiting bag room")

	# Clear bag and claim
	full_inv2.remove_from_slot(0, -1)
	full_inv2.remove_from_slot(1, -1)
	qm2.check_paused_rewards(full_inv2)
	check(qm2.is_quest_completed(&"chore_mara_catch"), "Quest fully completed after space freed")
	npc_mara.refresh_marker(qm2)
	check(npc_mara.marker.text == "", "Character marker clears after quest is completed and rewards collected")

	print("==================================================")
	print("Tests finished: %d / %d passed" % [passed, total])
	print("==================================================")
	quit(0 if passed == total else 1)
