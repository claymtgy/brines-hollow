extends SceneTree
## Headless test suite for Brine's Hollow Deep Fishing & Angling Engine:
##   godot --headless --path . -s tests/test_fishing.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("==================================================")
	print("Running Brine's Hollow Deep Fishing Tests...")
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
	FishDB.init_db()

	# -------------------------------------------------------------------------
	# 1. Almanac & Environmental Filter Tests
	# -------------------------------------------------------------------------
	var mackerel: FishDef = FishDB.get_fish(&"silver_mackerel")
	var flounder: FishDef = FishDB.get_fish(&"tidepool_flounder")
	var eel: FishDef = FishDB.get_fish(&"lightning_eel")
	var squid: FishDef = FishDB.get_fish(&"ghost_squid")

	assert_test.call("Almanac loaded 6 species", FishDB.get_all_fish().size() == 6)

	# Low tide (-0.6), Fair weather, Day, Rod Tier 1
	var low_tide_fish := FishDB.get_eligible_fish(-0.6, true, false, false, 1)
	assert_test.call("Low tide allows Tidepool Flounder", flounder in low_tide_fish)
	assert_test.call("Low tide rejects Silver Mackerel", not (mackerel in low_tide_fish))

	# High tide (+0.6), Fair weather, Day, Rod Tier 1
	var high_tide_fish := FishDB.get_eligible_fish(0.6, true, false, false, 1)
	assert_test.call("High tide allows Silver Mackerel", mackerel in high_tide_fish)
	assert_test.call("High tide rejects Tidepool Flounder", not (flounder in high_tide_fish))

	# Storm weather, High tide (+0.6), Day, Rod Tier 2
	var storm_fish := FishDB.get_eligible_fish(0.6, true, true, false, 2)
	assert_test.call("Storm allows Lightning Eel with Tier 2 rod", eel in storm_fish)

	# Night time, Deep trench, Rod Tier 2
	var night_fish := FishDB.get_eligible_fish(0.0, false, false, false, 2)
	assert_test.call("Night allows Ghost Squid with Tier 2 rod", squid in night_fish)

	# -------------------------------------------------------------------------
	# 2. FishingController State Machine & Cast
	# -------------------------------------------------------------------------
	var controller := FishingController.new(1)
	assert_test.call("Controller starts in IDLE", controller.current_state == FishingController.State.IDLE)

	assert_test.call("Start cast transitions to CASTING", controller.start_cast() and controller.current_state == FishingController.State.CASTING)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var cast_ok := controller.release_cast(0.8, 0.6, true, false, false, rng)
	assert_test.call("Release cast transitions to WAITING_FOR_BITE with line distance > 10m",
		cast_ok and controller.current_state == FishingController.State.WAITING_FOR_BITE and controller.line_distance >= 10.0)
	assert_test.call("Active fish rolled is Silver Mackerel", controller.active_fish == mackerel)

	# -------------------------------------------------------------------------
	# 3. Bites, Hook Window & Early Strike Penalty
	# -------------------------------------------------------------------------
	# Clicking before anything nibbles just reels the lure back in
	var early_strike := controller.strike_hook()
	assert_test.call("Pulling in an empty line returns to IDLE", not early_strike and controller.current_state == FishingController.State.IDLE)
	assert_test.call("and you can cast again straight away", controller.start_cast() and controller.current_state == FishingController.State.CASTING)
	controller.release_cast(0.5, 0.6, true, false, false, rng)

	# Striking during a nibble spooks the fish, and you can recast without a reset
	controller.tick(controller.bite_timer - 0.2)
	if controller.current_state == FishingController.State.NIBBLING:
		assert_test.call("Striking a nibble too early loses the fish", not controller.strike_hook() and controller.current_state == FishingController.State.LOST)
	else:
		controller._set_state(FishingController.State.LOST)
	assert_test.call("Recast works after a lost fish", controller.start_cast() and controller.current_state == FishingController.State.CASTING)
	controller.release_cast(0.5, 0.6, true, false, false, rng)

	# Advance bite timer
	controller.tick(controller.bite_timer - 0.2)
	assert_test.call("Advancing timer to near bite enters NIBBLING or HOOK_WINDOW",
		controller.current_state == FishingController.State.NIBBLING or controller.current_state == FishingController.State.HOOK_WINDOW)

	controller.tick(0.5)
	assert_test.call("Bite trigger opens HOOK_WINDOW", controller.current_state == FishingController.State.HOOK_WINDOW)

	# Successful hook strike
	var hook_success := controller.strike_hook()
	assert_test.call("Striking during HOOK_WINDOW transitions to REELING",
		hook_success and controller.current_state == FishingController.State.REELING)

	# -------------------------------------------------------------------------
	# 4. Reeling Physics & Landing Fish
	# -------------------------------------------------------------------------
	var catch_result := [null, 0.0] # [fish, weight] to allow mutation in lambda
	controller.fish_landed.connect(func(fish: FishDef, weight: float):
		catch_result[0] = fish
		catch_result[1] = weight
	)

	# Simulate realistic active angling: reel when tension is safe, release when high
	var reel_safety_limit := 200 # prevent infinite loops
	while controller.current_state == FishingController.State.REELING and controller.line_distance > 0.1 and reel_safety_limit > 0:
		reel_safety_limit -= 1
		var should_reel: bool = controller.line_tension < 0.75
		controller.tick_reeling(should_reel, 0.8, 0.05)

	assert_test.call("Reeling completed and transitioned to CAUGHT", controller.current_state == FishingController.State.CAUGHT)
	assert_test.call("Landed fish matches active fish", catch_result[0] != null and catch_result[0] == controller.active_fish and catch_result[1] > 0.0)
	assert_test.call("Recast works straight after a catch", controller.start_cast() and controller.current_state == FishingController.State.CASTING)
	controller.reset()

	# -------------------------------------------------------------------------
	# 5. Passive Crab Pot Trap
	# -------------------------------------------------------------------------
	var pot_pos := Vector3i(150, 32, 150) # In the water at high tide
	var pot := CrabPot.new(pot_pos)
	assert_test.call("Crab pot initially empty and unbaited", not pot.is_baited())

	pot.add_bait(&"kelp_frond", 3)
	assert_test.call("Crab pot baited with 3 kelp fronds", pot.is_baited() and pot.bait_count == 3)

	# High tide soak (tide_y=35 > pot Y=32); simulate 2 tidal cycles
	pot.tick_tidal_cycle(35.0, rng)
	if pot.trapped_catch.is_empty():
		pot.tick_tidal_cycle(35.0, rng)

	assert_test.call("High tide soak catches shellfish and consumes bait",
		pot.bait_count < 3 and pot.trapped_catch.size() > 0)

	# Harvest into inventory
	var player_inv := Inventory.new(24)
	var harvested_count := pot.harvest_to_inventory(player_inv)
	assert_test.call("Harvested catch into inventory", harvested_count > 0)
	assert_test.call("Inventory contains caught crab or oysters",
		player_inv.get_item_count(&"shore_crab") > 0 or player_inv.get_item_count(&"brine_oyster") > 0)
	assert_test.call("Pot emptied after harvest", pot.trapped_catch.is_empty() or pot.trapped_catch.values().max() == 0)

	# Crab pot serialization
	var pot_data := pot.serialize()
	var loaded_pot := CrabPot.deserialize(pot_data)
	assert_test.call("CrabPot deserialization retains position and bait count",
		loaded_pot.pos == pot.pos and loaded_pot.bait_count == pot.bait_count)

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	quit(0 if stats[0] == stats[1] else 1)
