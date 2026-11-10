extends SceneTree

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\n=== STARTING NOTICE BOARD & MARKET STALL TEST SUITE ===")
	run_tests()
	print("\n=== TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [_passed, _failed])
	if _failed > 0:
		print("FAILED with %d errors" % _failed)
	else:
		print("ALL NOTICE BOARD & MARKET STALL TESTS PASSED!")
	quit(0 if _failed == 0 else 1)


func assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)


func run_tests() -> void:
	ItemDB.init_db()
	RecipeDB.init_db()
	Placeables.register_builtin()

	test_notice_board_chores()
	test_notice_board_completion()
	test_market_stall_sales()
	test_market_stall_community_chest_deposit()


func test_notice_board_chores() -> void:
	print("\n--- 1. Town Notice Board & Chores ---")
	var board := NoticeBoardEntity.new(Vector3i(10, 0, 10))

	assert_true(board.entity_id == &"notice_board", "Notice board entity ID is notice_board")
	assert_true(board.get_active_chore_count() >= 3, "Notice board initializes with default chores")

	# Test refreshing chores based on drifter professions
	var drifters: Array[DrifterDef] = [
		DrifterDef.new(&"d1", "Mara", DrifterDef.Profession.FISHER),
		DrifterDef.new(&"d2", "Tobin", DrifterDef.Profession.CARPENTER),
		DrifterDef.new(&"d3", "Bram", DrifterDef.Profession.BUILDER)
	]

	board.refresh_chores(drifters)
	assert_true(board.active_chores.size() == 3, "Notice board generated 3 tailored chores from drifters")

	var has_builder_chore := false
	for c in board.active_chores:
		if c.item_requested == &"cobblestone":
			has_builder_chore = true
	assert_true(has_builder_chore, "Notice board includes cobblestone chore for Builder")


func test_notice_board_completion() -> void:
	print("\n--- 2. Chore Turn-In & Rewards ---")
	var board := NoticeBoardEntity.new(Vector3i(12, 0, 12))
	var player := Player.new()
	player.inventory = Inventory.new(16)

	# Give player silver mackerel for Mara's chore
	player.inventory.add_item(&"silver_mackerel", 5)
	assert_true(player.inventory.get_item_count(&"silver_mackerel") == 5, "Player has 5 silver mackerel")

	var initial_brass: int = player.inventory.get_item_count(&"brass_guilder")
	var success := board.complete_chore(&"chore_mara_fish", player)
	assert_true(success == true, "Chore turned in successfully")

	var remaining_mackerel: int = player.inventory.get_item_count(&"silver_mackerel")
	assert_true(remaining_mackerel == 2, "3 mackerel consumed by chore completion")

	var new_brass: int = player.inventory.get_item_count(&"brass_guilder")
	assert_true(new_brass == initial_brass + 15, "Player received 15 Brass Guilders reward")


func test_market_stall_sales() -> void:
	print("\n--- 3. Village Market Stall Operations ---")
	var stall := MarketStallEntity.new(Vector3i(20, 0, 20))

	assert_true(stall.entity_id == &"market_stall", "Market stall entity ID is market_stall")

	# Assign purser
	stall.assign_purser(&"drifter_fiona", "Fiona the Trader")
	assert_true(stall.purser_name == "Fiona the Trader", "Purser assigned to market stall")

	# Stock commodities
	stall.stock_item(&"smoked_fish_ration", 4)
	stall.stock_item(&"aged_cheese", 2)
	assert_true(stall.container.inventory.get_item_count(&"smoked_fish_ration") == 4, "Stall stocked with 4 smoked rations")

	# Advance sales tick (30s)
	var earned := stall.tick_market(35.0)
	assert_true(earned == 4, "Stall sold 1 smoked fish ration for 4 Brass Guilders")
	assert_true(stall.accumulated_brass == 4, "Accumulated brass is 4")
	assert_true(stall.container.inventory.get_item_count(&"smoked_fish_ration") == 3, "1 smoked ration deducted after sale")


func test_market_stall_community_chest_deposit() -> void:
	print("\n--- 4. Market Stall & Community Chest Integration ---")
	var stall := MarketStallEntity.new(Vector3i(25, 0, 25))
	var chest := ChestEntity.make_community_chest(Vector3i(24, 0, 24))

	stall.stock_item(&"aged_cheese", 1) # Price = 8 brass

	# Sales tick with Community Chest linked
	var earned := stall.tick_market(35.0, chest)
	assert_true(earned == 8, "Stall sold aged cheese for 8 Brass Guilders")
	assert_true(chest.has_supplies(&"brass_guilder", 8), "Market revenue deposited directly into Community Chest")
