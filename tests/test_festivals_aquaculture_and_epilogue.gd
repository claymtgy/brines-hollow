extends SceneTree

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\n=== STARTING FESTIVALS, AQUACULTURE, DIVING WINCH & EPILOGUE TEST SUITE ===")
	run_tests()
	print("\n=== TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [_passed, _failed])
	if _failed > 0:
		print("FAILED with %d errors" % _failed)
	else:
		print("ALL FESTIVALS, AQUACULTURE, DIVING WINCH & EPILOGUE TESTS PASSED!")
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

	test_aquaculture_and_items()
	test_mangrove_beehive()
	test_banquet_table_and_festivals()
	test_salvage_diving_winch()
	test_campaign_epilogue_and_creative_mode()
	test_endless_undertow_gauntlet()


# -----------------------------------------------------------------------------
# 1. COASTAL AQUACULTURE & OYSTER RACKS
# -----------------------------------------------------------------------------
func test_aquaculture_and_items() -> void:
	print("\n--- Test: Coastal Aquaculture & Oyster Racks ---")

	assert_true(ItemDB.has_item(&"brine_oyster"), "ItemDB registers brine_oyster")
	assert_true(ItemDB.has_item(&"hearty_clam"), "ItemDB registers hearty_clam")
	assert_true(ItemDB.has_item(&"beeswax"), "ItemDB registers beeswax")
	assert_true(ItemDB.has_item(&"scented_candle"), "ItemDB registers scented_candle")
	assert_true(ItemDB.has_item(&"oyster_rack"), "ItemDB registers oyster_rack")
	assert_true(Placeables.BUILTIN.has(&"oyster_rack"), "Placeables BUILTIN has oyster_rack")

	var rack := OysterRackEntity.new(Vector3i(10, 5, 10))
	assert_true(rack.item_id == &"oyster_rack", "OysterRackEntity item_id is oyster_rack")
	assert_true(rack.get_total_harvest() == 0, "Oyster rack starts empty")

	# Test simulated tidal submerged ticking
	rack.submerged_time = OysterRackEntity.CYCLE_SUBMERGED_SEC
	# Direct production test
	rack._produce_seafood()
	assert_true(rack.get_total_harvest() == 1, "Oyster rack produced 1 shellfish")

	# Fill rack up to capacity
	for i in 20:
		rack._produce_seafood()
	assert_true(rack.get_total_harvest() <= OysterRackEntity.MAX_CAPACITY + 1, "Oyster rack respects capacity")

	# Test serialization
	var data := rack.serialize()
	var rack2 := OysterRackEntity.new(Vector3i(10, 5, 10))
	rack2.deserialize(data)
	assert_true(rack2.get_total_harvest() == rack.get_total_harvest(), "Oyster rack preserves harvest across serialization")

	# Test harvest interaction
	var dummy_player := Player.new()
	var player_inv := dummy_player.inventory

	var before_count := player_inv.get_item_count(&"brine_oyster") + player_inv.get_item_count(&"hearty_clam") + player_inv.get_item_count(&"abyssal_pearl")
	rack2.client_interact(dummy_player)
	var after_count := player_inv.get_item_count(&"brine_oyster") + player_inv.get_item_count(&"hearty_clam") + player_inv.get_item_count(&"abyssal_pearl")
	assert_true(after_count > before_count, "Harvesting oyster rack transfers shellfish into player inventory")
	assert_true(rack2.get_total_harvest() == 0, "Oyster rack is empty after harvest")


# -----------------------------------------------------------------------------
# 2. MANGROVE BEEHIVE & APICULTURE
# -----------------------------------------------------------------------------
func test_mangrove_beehive() -> void:
	print("\n--- Test: Mangrove Beehive & Apiculture ---")

	assert_true(ItemDB.has_item(&"mangrove_beehive"), "ItemDB registers mangrove_beehive")
	assert_true(Placeables.BUILTIN.has(&"mangrove_beehive"), "Placeables BUILTIN has mangrove_beehive")

	var hive := MangroveBeehiveEntity.new(Vector3i(5, 5, 5))
	assert_true(hive.item_id == &"mangrove_beehive", "Hive item_id is mangrove_beehive")
	assert_true(hive.honey_stored == 0 and hive.wax_stored == 0, "Hive starts empty")

	# Tick hive cycle
	hive.tick(MangroveBeehiveEntity.BASE_CYCLE_SEC + 1.0)
	assert_true(hive.honey_stored == 1, "Hive produced 1 honey")
	assert_true(hive.wax_stored == 1, "Hive produced 1 wax")

	# Test serialization
	var data := hive.serialize()
	var hive2 := MangroveBeehiveEntity.new(Vector3i(5, 5, 5))
	hive2.deserialize(data)
	assert_true(hive2.honey_stored == 1 and hive2.wax_stored == 1, "Hive preserves honey and wax across serialization")

	# Test harvesting into player inventory
	var dummy_player := Player.new()
	var player_inv := dummy_player.inventory

	hive2.client_interact(dummy_player)
	assert_true(player_inv.get_item_count(&"marsh_honey") == 1, "Player received harvested marsh_honey")
	assert_true(player_inv.get_item_count(&"beeswax") == 1, "Player received harvested beeswax")
	assert_true(hive2.honey_stored == 0 and hive2.wax_stored == 0, "Hive is cleared after harvest")


# -----------------------------------------------------------------------------
# 3. TIDAL FESTIVALS & COMMUNAL BANQUETS
# -----------------------------------------------------------------------------
func test_banquet_table_and_festivals() -> void:
	print("\n--- Test: Communal Banquets & Tidal Festivals ---")

	assert_true(ItemDB.has_item(&"banquet_table"), "ItemDB registers banquet_table")
	assert_true(Placeables.BUILTIN.has(&"banquet_table"), "Placeables BUILTIN has banquet_table")

	var table := BanquetTableEntity.new(Vector3i(20, 5, 20))
	assert_true(table.dishes.is_empty(), "Banquet table starts with 0 dishes")

	var feast_player := Player.new()
	var player_inv := feast_player.inventory
	player_inv.add_item(&"hearty_clam_chowder", 2)
	player_inv.add_item(&"glazed_abyssal_crab", 2)
	player_inv.set_active_hotbar_index(0)

	# Contribute dishes
	table.client_interact(feast_player)
	assert_true(table.dishes.size() == 1, "Contributed 1st dish to banquet table")
	table.client_interact(feast_player)
	assert_true(table.dishes.size() == 2, "Contributed 2nd dish to banquet table")

	player_inv.set_active_hotbar_index(1)
	table.client_interact(feast_player)
	assert_true(table.dishes.size() == 3, "Contributed 3rd dish to banquet table")

	# Partake in feast
	var hp_before := feast_player.vitality.current_hp
	table._partake_feast(feast_player)
	assert_true(table.dishes.is_empty(), "Banquet dishes consumed in grand feast")
	assert_true(feast_player.vitality.current_hp > hp_before, "Banquet Rested buff applied (+50 bonus HP)")

	# Test SkyCycle equinox tides and floating lantern festival
	var sky := SkyCycle.new()
	sky.day = 7 # multiple of 7 = equinox
	assert_true(sky.is_equinox_tide(), "Day 7 is an Equinox Spring Tide")

	var normal_tide := VoxelWorld.SEA_MID + VoxelWorld.TIDE_AMP
	sky.day = 1
	var normal_calc := sky.tide_level(0.0)
	sky.day = 7
	var equinox_calc := sky.tide_level(0.0)
	assert_true(absf(equinox_calc - VoxelWorld.SEA_MID) > absf(normal_calc - VoxelWorld.SEA_MID), "Equinox spring tide has amplified tidal swing")

	sky.time_of_day = 0.85 # Night
	assert_true(sky.is_floating_lantern_festival(), "Night of the Equinox triggers Floating Lantern Festival")


# -----------------------------------------------------------------------------
# 4. SALVAGE DIVING TENDER WINCH ON BOATS
# -----------------------------------------------------------------------------
func test_salvage_diving_winch() -> void:
	print("\n--- Test: Salvage Diving Tender Winch on Boats ---")

	assert_true(ItemDB.has_item(&"diving_winch"), "ItemDB registers diving_winch")
	assert_true(RecipeDB.has_recipe(&"craft_diving_winch"), "RecipeDB registers craft_diving_winch")

	var sloop := Boat.new()
	sloop.kind = Boat.KIND_SLOOP
	assert_true(sloop.can_install_fixture(1, &"diving_winch"), "Sloop allows diving_winch on slot 1")

	var schooner := Boat.new()
	schooner.setup(2, null, null, Vector3.ZERO, 0.0, Boat.KIND_SCHOONER)
	assert_true(schooner.can_install_fixture(2, &"diving_winch"), "Schooner allows diving_winch on slot 2")

	# Install winch
	var ok := schooner.install_fixture(2, &"diving_winch")
	assert_true(ok, "Installed diving_winch successfully")
	assert_true(schooner.deck_fixtures[2]["lowered"] == false, "Winch starts raised")

	# Toggle winch lowering
	var dummy_player = Node.new()
	dummy_player.set("hud", null)
	schooner.interact_fixture(2, dummy_player)
	assert_true(schooner.deck_fixtures[2]["lowered"] == true, "Winch interacted and lowered")

	# Verify visual bell position adjusted
	var node: Node3D = schooner.deck_fixtures[2]["node"]
	var bell: Node3D = node.get_node_or_null("DivingBell")
	assert_true(bell != null and is_equal_approx(bell.position.y, -8.0), "Diving Bell lowered 8 meters beneath deck")

	# Test serialization of lowered state
	var saved := schooner.serialize_fixtures()
	var schooner2 := Boat.new()
	schooner2.setup(3, null, null, Vector3.ZERO, 0.0, Boat.KIND_SCHOONER)
	schooner2.deserialize_fixtures(saved)
	assert_true(schooner2.deck_fixtures[2]["lowered"] == true, "Lowered winch state restored from serialization")

	# Test underwater breath replenishment
	var p := Player.new()
	p.vitality.current_breath = 5.0 # Low breath
	var vis_pos := schooner.visual.position if schooner.visual != null else Vector3.ZERO
	var bell_pos: Vector3 = schooner.position + vis_pos + node.position + bell.position
	p.position = bell_pos + Vector3(1.0, 0, 1.0) # within 5.5m

	# Set up mock EntityManager.current
	var em := EntityManager.new()
	var mock_main := Node.new()
	mock_main.set_meta("player", p)
	em.main = mock_main
	EntityManager.current = em

	schooner._tick_diving_winches()
	assert_true(p.vitality.current_breath >= p.vitality.get_max_breath() - 0.1, "Submerged diving bell replenishes diver breath")


# -----------------------------------------------------------------------------
# 5. CAMPAIGN EPILOGUE & WORLD STATE TRANSFORMATION
# -----------------------------------------------------------------------------
func test_campaign_epilogue_and_creative_mode() -> void:
	print("\n--- Test: Campaign Epilogue & World State Transformation ---")

	var regulator := TideRegulatorEntity.new(Vector3i(0, 10, 0))
	assert_true(regulator.fully_restored == false, "Regulator starts unrestored")

	# Test Deluge Core attunement
	var epilogue_player := Player.new()
	epilogue_player.inventory.add_item(&"deluge_core", 1)

	regulator.client_interact(epilogue_player)
	assert_true(regulator.fully_restored == true, "Deluge Core fully restores Grand Equilibrium")
	assert_true(WeatherModel.deluge_calmed == true, "WeatherModel recognizes deluge_calmed = true")

	# Test Weather calming
	var sample := WeatherModel.sample(1337, 4.5)
	assert_true(sample["storm"] == 0.0, "Deluge calmed forces storms to 0.0")
	assert_true(sample["wind"] <= 0.25, "Deluge calmed limits sea winds to peaceful breeze")

	# Test Post-game Creative Mode
	var player := Player.new()
	player.set_creative_mode(true)
	assert_true(player.creative_mode == true, "Player creative_mode is enabled")
	assert_true(player.inventory.creative_mode == true, "Player inventory creative_mode is enabled")

	# Test recipe crafting without ingredients in creative mode
	var recipe := RecipeDB.get_recipe(&"craft_diving_winch")
	assert_true(recipe != null, "Recipe craft_diving_winch exists")
	var empty_inv := Inventory.new(24)
	empty_inv.creative_mode = true
	assert_true(recipe.can_craft_with(empty_inv), "Creative mode allows crafting without materials")
	assert_true(recipe.consume_ingredients(empty_inv), "Creative mode crafting succeeds without consuming ingredients")


# -----------------------------------------------------------------------------
# 6. ENDLESS UNDERTOW GAUNTLET
# -----------------------------------------------------------------------------
func test_endless_undertow_gauntlet() -> void:
	print("\n--- Test: Endless Undertow Gauntlet ---")

	var altar := UndertowGauntletAltar.new(Vector3i(15, 2, 15))
	assert_true(altar.active == false, "Gauntlet starts inactive")

	var started := altar.start_endless_mode()
	assert_true(started, "Endless mode started")
	assert_true(altar.is_endless == true, "Altar is_endless flag is true")
	assert_true(altar.current_wave == 1, "Starts on Wave 1")

	# Simulate wave clears past total waves (endless)
	altar._advance_wave()
	assert_true(altar.current_wave == 2, "Endless Gauntlet advances to Wave 2")
	altar._advance_wave()
	assert_true(altar.current_wave == 3, "Endless Gauntlet advances to Wave 3")
	altar._advance_wave()
	assert_true(altar.current_wave == 4 and altar.active == true, "Endless Gauntlet continues past Wave 3 indefinitely")
	assert_true(altar.highest_wave >= 3, "High-score wave counter tracks deepest wave")
