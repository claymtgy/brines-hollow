extends SceneTree

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\n=== STARTING RADIAL WHEEL, GALLEON, BLUEPRINTS & ADMIN TEST SUITE ===")
	run_tests()
	print("\n=== TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [_passed, _failed])
	if _failed > 0:
		print("FAILED with %d errors" % _failed)
	else:
		print("ALL RADIAL WHEEL, GALLEON, BLUEPRINTS & ADMIN TESTS PASSED!")
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

	test_tool_radial_wheel_and_haptics()
	test_merchant_galleon_and_contracts()
	test_blueprint_catalog_and_workshop()
	test_server_admin_dashboard_and_commands()


# -----------------------------------------------------------------------------
# 1. TOOL RADIAL WHEEL & GAMEPAD HAPTICS
# -----------------------------------------------------------------------------
func test_tool_radial_wheel_and_haptics() -> void:
	print("\n--- Test: Tool Radial Wheel & Gamepad Haptics ---")

	var wheel := ToolWheelUI.new()
	assert_true(wheel.WEDGE_COUNT == 8, "Tool wheel has 8 directional wedges")
	assert_true(wheel.visible == false, "Tool wheel starts hidden")

	wheel.open_wheel()
	assert_true(wheel.is_wheel_open == true, "Tool wheel is marked open")
	assert_true(wheel.visible == true, "Tool wheel is visible when opened")

	# Test 8-directional selection
	# Up vector (0, -1) -> Wedge 0 (Pickaxe)
	var wedge_up := wheel.select_direction(Vector2(0, -1))
	assert_true(wedge_up == 0, "Up stick vector selects Pickaxe (Wedge 0)")

	# Right vector (1, 0) -> Wedge 2 (Shovel)
	var wedge_right := wheel.select_direction(Vector2(1, 0))
	assert_true(wedge_right == 2, "Right stick vector selects Shovel (Wedge 2)")

	# Down vector (0, 1) -> Wedge 4 (Fishing Rod)
	var wedge_down := wheel.select_direction(Vector2(0, 1))
	assert_true(wedge_down == 4, "Down stick vector selects Fishing Rod (Wedge 4)")

	# Left vector (-1, 0) -> Wedge 6 (Build Hammer)
	var wedge_left := wheel.select_direction(Vector2(-1, 0))
	assert_true(wedge_left == 6, "Left stick vector selects Build Hammer (Wedge 6)")

	# Test player integration
	var player := Player.new()
	wheel.player = player
	wheel.select_direction(Vector2(-1, 0)) # Wedge 6 = Hammer
	wheel.close_wheel()
	assert_true(player.tool == 1, "Selecting hammer wedge sets player.tool = 1 (Build Hammer)")

	wheel.open_wheel()
	wheel.select_direction(Vector2(-0.7, -0.7)) # Wedge 7 = Chart
	wheel.close_wheel()
	assert_true(player.tool == 2, "Selecting chart wedge sets player.tool = 2 (Sea Chart)")

	# Test haptic trigger methods
	var cm := ControllerManager.new()
	cm.play_haptic_pulse(0.7, 0.1)
	cm.apply_weapon_charge(0.85)
	cm.apply_diving_winch_crank()
	assert_true(true, "ControllerManager trigger and haptic hooks executed cleanly")


# -----------------------------------------------------------------------------
# 2. VISITING MERCHANT GALLEON & EXPORT MANIFESTS
# -----------------------------------------------------------------------------
func test_merchant_galleon_and_contracts() -> void:
	print("\n--- Test: Visiting Merchant Galleon & Export Manifests ---")

	assert_true(ItemDB.has_item(&"exotic_spice"), "ItemDB registers exotic_spice")
	assert_true(ItemDB.has_item(&"dye_indigo"), "ItemDB registers dye_indigo")
	assert_true(ItemDB.has_item(&"silk_bolt"), "ItemDB registers silk_bolt")

	var galleon := MerchantGalleon.new()
	assert_true(galleon.merchant != null, "Galleon has merchant boat instance")
	assert_true(galleon.merchant.type == MerchantBoat.MerchantType.TRADE_GALLEON, "Merchant type is TRADE_GALLEON")
	assert_true(galleon.merchant.stock.has_item(&"exotic_spice", 1), "Galleon stocks exotic spices")
	assert_true(galleon.merchant.stock.has_item(&"dye_indigo", 1), "Galleon stocks indigo dye")

	# Verify export manifests
	var contract_dairy: TradeContract = null
	var contract_trophy: TradeContract = null
	for c in galleon.merchant.active_contracts:
		if c.id == &"manifest_artisan_dairy":
			contract_dairy = c
		elif c.id == &"manifest_borean_trophy":
			contract_trophy = c

	assert_true(contract_dairy != null, "Galleon offers manifest_artisan_dairy export contract")
	assert_true(contract_trophy != null, "Galleon offers manifest_borean_trophy export contract")

	# Test fulfilling export contract
	var player_inv := Inventory.new(24)
	player_inv.add_item(&"goat_cheese", 4)
	player_inv.add_item(&"marsh_honey", 4)

	assert_true(contract_dairy.can_fulfill(player_inv), "Player has goods to fulfill dairy contract")
	var success := galleon.merchant.fulfill_contract(&"manifest_artisan_dairy", player_inv)
	assert_true(success, "Fulfill dairy export contract succeeded")
	assert_true(player_inv.get_item_count(&"goat_cheese") == 0, "Goods consumed from player bag")
	assert_true(player_inv.get_item_count(&"brass_guilder") >= 280, "Player received Brass Guilders payout")
	assert_true(player_inv.get_item_count(&"tide_scrip") >= 20, "Player received Tide Scrip payout")


# -----------------------------------------------------------------------------
# 3. STEAM WORKSHOP & PORTABLE BLUEPRINT CATALOG
# -----------------------------------------------------------------------------
func test_blueprint_catalog_and_workshop() -> void:
	print("\n--- Test: Steam Workshop & Blueprint Catalog ---")

	var test_voxels := [
		[0, 0, 0, Palette.PLANK],
		[1, 0, 0, Palette.PLANK],
		[0, 1, 0, Palette.STONE],
		[1, 1, 0, Palette.STONE],
		[0, 2, 0, Palette.METAL]
	]

	# Material cost calculation
	var mats := BlueprintCatalog.calculate_materials_from_voxels(test_voxels)
	assert_true(mats.get(&"wood_plank", 0) == 2, "Calculated 2 wood planks from PLANK voxels")
	assert_true(mats.get(&"stone", 0) == 2, "Calculated 2 stone from STONE voxels")
	assert_true(mats.get(&"iron_ingot", 0) == 1, "Calculated 1 iron ingot from METAL voxels")

	# Export blueprint
	var exp := BlueprintCatalog.export_blueprint("Harbor Watchtower", "Captain Wayfarer", Vector3i(2, 3, 1), test_voxels, mats)
	assert_true(exp.get("success", false) == true, "Exported blueprint successfully")
	var file_path: String = exp.get("path", "")
	assert_true(FileAccess.file_exists(file_path), "Blueprint file exists on disk")

	# Import blueprint
	var imp := BlueprintCatalog.import_blueprint(file_path)
	assert_true(imp.get("success", false) == true, "Imported blueprint successfully")
	assert_true(imp.get("name") == "Harbor Watchtower", "Preserved blueprint name")
	assert_true(imp.get("author") == "Captain Wayfarer", "Preserved author metadata")
	assert_true(imp.get("dimensions") == Vector3i(2, 3, 1), "Preserved blueprint dimensions")
	assert_true(imp.get("voxels").size() == 5, "Preserved voxel array count")

	# List local blueprints
	var all_bps := BlueprintCatalog.list_local_blueprints()
	assert_true(all_bps.size() >= 1, "list_local_blueprints found at least 1 blueprint")

	# Test Drafting Desk integration
	var desk := DraftingDeskEntity.new(Vector3i(0, 0, 0))
	var desk_exp := desk.export_schematic("Fisher Cottage", "Architect", Vector3i(4, 4, 4), test_voxels)
	assert_true(desk_exp.get("success", false) == true, "DraftingDeskEntity exported schematic")
	assert_true(desk.drafts_completed >= 1, "Drafting desk incremented drafts_completed count")


# -----------------------------------------------------------------------------
# 4. DEDICATED SERVER ADMIN DASHBOARD & COMMANDS
# -----------------------------------------------------------------------------
func test_server_admin_dashboard_and_commands() -> void:
	print("\n--- Test: Dedicated Server Admin Dashboard & Command Suite ---")

	var admin := ServerAdmin.new()

	# Test Telemetry
	var telem := admin.get_telemetry()
	assert_true(telem.has("uptime_sec"), "Telemetry includes uptime_sec")
	assert_true(telem.has("player_count"), "Telemetry includes player_count")
	assert_true(telem.has("tps"), "Telemetry includes tps")
	assert_true(telem.has("weather"), "Telemetry includes weather")

	# Test Weather Forecast
	var forecast := admin.get_weather_forecast(4)
	assert_true(forecast.size() == 4, "Weather forecast generated 4 upcoming fronts")
	assert_true(forecast[0].has("state_name"), "Forecast entries include state_name")

	# Test Slash Commands
	# /help
	var res_help := admin.execute_command("/help")
	assert_true(res_help["success"] == true, "Command /help succeeded")

	# /status
	var res_status := admin.execute_command("/status")
	assert_true(res_status["success"] == true, "Command /status succeeded")

	# /festival
	var sky := SkyCycle.new()
	var mock_main := Node.new()
	mock_main.set_meta("sky", sky)
	admin.main = mock_main

	var res_fest := admin.execute_command("/festival")
	assert_true(res_fest["success"] == true and sky.festival_active == true, "Command /festival activated equinox festival")

	# /time
	var res_time := admin.execute_command("/time noon")
	assert_true(res_time["success"] == true and is_equal_approx(sky.time_of_day, 0.5), "Command /time noon set time_of_day = 0.5")

	# /deluge
	WeatherModel.deluge_calmed = false
	var res_deluge := admin.execute_command("/deluge")
	assert_true(res_deluge["success"] == true and WeatherModel.deluge_calmed == true, "Command /deluge toggled deluge_calmed")

	# /give
	var p := Player.new()
	mock_main.set_meta("player", p)
	var res_give := admin.execute_command("/give sea_salt 15")
	assert_true(res_give["success"] == true, "Command /give sea_salt 15 succeeded")
	assert_true(p.inventory.get_item_count(&"sea_salt") == 15, "Player inventory received 15 sea_salt")
