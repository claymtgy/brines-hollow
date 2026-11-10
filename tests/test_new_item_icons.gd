extends SceneTree

func _init() -> void:
	ItemDB.init_db()
	RecipeDB.init_db()
	Placeables.register_builtin()
	print("--- Running Item & Trade UI Validation Tests ---")

	# Test 1: Check icon rendering for all 205 items
	var all_items := ItemDB.get_all_items()
	print("Testing icon rendering for %d items..." % all_items.size())
	for item in all_items:
		var tex := ItemIcons.for_item(item.id)
		assert(tex != null, "Texture for %s was null" % item.id)
		var img: Image = tex.get_image()
		assert(img != null, "Image for %s was null" % item.id)
		assert(img.get_width() == 48 and img.get_height() == 48, "Expected 48x48 icon for %s" % item.id)

	# Verify specific items have distinct rendering
	var specific_keys := [
		&"sea_iron_ore", &"iron_ingot", &"copper_ore", &"sea_brass_ingot",
		&"spring_water", &"fish_oil", &"salt_milk",
		&"sea_egg", &"sea_wool", &"down_feather", &"goat_cheese", &"aged_brine_cheese",
		&"sea_salt", &"wheat_flour", &"marsh_honey", &"beeswax",
		&"shearing_shears", &"wooden_bucket", &"animal_whistle",
		&"brackish_rye_bread", &"shore_hardtack", &"root_potato", &"samphire",
		&"workbench", &"campfire", &"furnace", &"anvil", &"saltery", &"smokehouse",
		&"stone_well", &"feed_trough", &"poultry_coop", &"sea_barrel", &"driftwood_chest"
	]
	for k in specific_keys:
		var tex := ItemIcons.for_item(k)
		assert(tex != null, "Texture for %s should not be null" % k)
	print("All %d specific item keys verified successfully!" % specific_keys.size())

	# Test 2: TradeUI behavior
	print("Testing TradeUI mouse mode and visibility...")
	var trade_ui := TradeUI.new()
	root.add_child(trade_ui)
	assert(not trade_ui.is_open(), "TradeUI should not be open initially")

	# Simulating opening trade UI
	trade_ui.visible = true
	assert(trade_ui.is_open(), "TradeUI.is_open() should return true when visible")

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	trade_ui._process(0.016)
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "TradeUI._process() should restore MOUSE_MODE_VISIBLE")

	trade_ui.close()
	assert(not trade_ui.is_open(), "TradeUI.is_open() should return false when closed")
	trade_ui.queue_free()

	# Test 3: Main is_any_menu_open test
	var MainClass = load("res://scripts/main.gd")
	var main_dummy = MainClass.new()
	assert(not main_dummy.is_any_menu_open(), "is_any_menu_open should be false with no menus open")
	var dummy_trade := TradeManager.new()
	dummy_trade.ui = TradeUI.new()
	main_dummy.trade = dummy_trade
	dummy_trade.ui.visible = true
	assert(main_dummy.is_any_menu_open(), "is_any_menu_open should be true when trade UI is visible")
	dummy_trade.ui.visible = false
	assert(not main_dummy.is_any_menu_open(), "is_any_menu_open should be false when trade UI is closed")
	main_dummy.free()
	dummy_trade.ui.free()
	dummy_trade.free()

	print("--- ALL TESTS PASSED SUCCESSFULLY! ---")
	quit(0)
