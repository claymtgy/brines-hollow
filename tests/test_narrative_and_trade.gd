extends SceneTree
## Headless test suite for Brine's Hollow Quests, Narrative & Maritime Trade:
##   godot --headless --path . -s tests/test_narrative_and_trade.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("==================================================")
	print("Running Brine's Hollow Quest & Trade Tests...")
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

	var player_inv := Inventory.new(24)
	var quest_mgr := QuestManager.new()

	# -------------------------------------------------------------------------
	# 1. Quest Catalogue & Acceptance
	# -------------------------------------------------------------------------
	assert_test.call("Quest catalogue has story_first_hearth available",
		quest_mgr.available_quests.has(&"story_first_hearth"))

	var accept_ok := quest_mgr.accept_quest(&"story_first_hearth")
	assert_test.call("Accepted story_first_hearth quest", accept_ok and quest_mgr.is_quest_active(&"story_first_hearth"))
	assert_test.call("Quest removed from available board", not quest_mgr.available_quests.has(&"story_first_hearth"))

	var q: QuestDef = quest_mgr.active_quests[&"story_first_hearth"]
	assert_test.call("Quest has 3 objective steps", q.steps.size() == 3)

	# -------------------------------------------------------------------------
	# 2. Objective Progression & Event Notifications
	# -------------------------------------------------------------------------
	# Step 1: Collect 10 Driftwood
	quest_mgr.notify_event(QuestDef.ObjectiveType.GATHER_ITEM, &"driftwood", 6)
	assert_test.call("Gathered 6/10 driftwood; step in-progress",
		q.steps[0].current_count == 6 and not q.steps[0].is_completed)

	quest_mgr.notify_event(QuestDef.ObjectiveType.GATHER_ITEM, &"driftwood", 4)
	assert_test.call("Gathered remaining 4 driftwood; step 1 completed",
		q.steps[0].current_count == 10 and q.steps[0].is_completed)
	assert_test.call("Quest still active (steps 2 & 3 pending)", quest_mgr.is_quest_active(&"story_first_hearth"))

	# Step 2: Build and validate room
	quest_mgr.notify_event(QuestDef.ObjectiveType.BUILD_ROOM, &"shelter", 1, player_inv)
	assert_test.call("Built room completed step 2", q.steps[1].is_completed)
	assert_test.call("Quest still active (step 3 pending)", quest_mgr.is_quest_active(&"story_first_hearth"))

	# Step 3: Invite a stranded drifter from the beach
	quest_mgr.notify_event(QuestDef.ObjectiveType.TALK_TO, &"drifter_recruit", 1, player_inv)
	assert_test.call("Recruiting drifter completed step 3 and finalized quest",
		quest_mgr.is_quest_completed(&"story_first_hearth") and not quest_mgr.is_quest_active(&"story_first_hearth"))

	# Payout check: 25 brass + 5 wheat seeds
	assert_test.call("Player received 25 brass guilders reward", player_inv.get_item_count(&"brass_guilder") == 25)
	assert_test.call("Player received 5 shore wheat seeds reward", player_inv.get_item_count(&"seed_shore_wheat") == 5)

	# -------------------------------------------------------------------------
	# 3. Quest Manager Serialization
	# -------------------------------------------------------------------------
	# Accept chore
	quest_mgr.accept_quest(&"chore_winter_kale")
	var quest_save := quest_mgr.serialize()

	var loaded_qm := QuestManager.new()
	loaded_qm.deserialize(quest_save)
	assert_test.call("Deserialized QuestManager retains completed quests",
		loaded_qm.is_quest_completed(&"story_first_hearth"))
	assert_test.call("Deserialized QuestManager retains active chore_winter_kale",
		loaded_qm.is_quest_active(&"chore_winter_kale"))

	# -------------------------------------------------------------------------
	# 4. Maritime Trade: Selling to Raft Peddler
	# -------------------------------------------------------------------------
	var peddler := MerchantBoat.new("Peddler Barnaby", MerchantBoat.MerchantType.RAFT_PEDDLER)
	player_inv.add_item(&"shore_crab", 4)

	var brass_earned := peddler.sell_item(&"shore_crab", 4, player_inv)
	assert_test.call("Sold 4 shore crabs to peddler for 24 brass (6 each)",
		brass_earned == 24 and player_inv.get_item_count(&"shore_crab") == 0)
	assert_test.call("Player total brass is now 49 (25 reward + 24 sale)",
		player_inv.get_item_count(&"brass_guilder") == 49)

	# -------------------------------------------------------------------------
	# 5. Maritime Trade: Buying from Raft Peddler
	# -------------------------------------------------------------------------
	# Buy 3 samphire seeds (cost = 3 each = 9 brass)
	var buy_ok := peddler.buy_item(&"seed_samphire", 3, player_inv)
	assert_test.call("Purchased 3 samphire seeds from peddler", buy_ok)
	assert_test.call("Player received 3 samphire seeds", player_inv.get_item_count(&"seed_samphire") == 3)
	assert_test.call("Deducted 9 brass (40 brass remaining)", player_inv.get_item_count(&"brass_guilder") == 40)

	# -------------------------------------------------------------------------
	# 6. Maritime Trade: Shipping Export Manifests (Trade Galleon)
	# -------------------------------------------------------------------------
	var galleon := MerchantBoat.new("The Sea Swallow", MerchantBoat.MerchantType.TRADE_GALLEON)
	assert_test.call("Galleon offers export manifests", galleon.active_contracts.size() >= 2)

	# Try to fulfill export manifest without required items (should fail)
	var fulfill_fail := galleon.fulfill_contract(&"manifest_cured_fish", player_inv)
	assert_test.call("Fulfill manifest fails without required smoked fish", not fulfill_fail)

	# Provide required smoked fish
	player_inv.add_item(&"smoked_fish_ration", 10)
	var fulfill_success := galleon.fulfill_contract(&"manifest_cured_fish", player_inv)
	assert_test.call("Export manifest fulfilled successfully", fulfill_success)
	assert_test.call("Manifest consumed 10 smoked fish rations", player_inv.get_item_count(&"smoked_fish_ration") == 0)
	assert_test.call("Payout awarded: 140 brass + 10 tide scrip",
		player_inv.get_item_count(&"brass_guilder") == 180 and player_inv.get_item_count(&"tide_scrip") == 10)

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	quit(0 if stats[0] == stats[1] else 1)
