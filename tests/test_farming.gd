extends SceneTree
## Headless test suite for Brine's Hollow Coastal Farming & Soil Salinity:
##   godot --headless --path . -s tests/test_farming.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("==================================================")
	print("Running Brine's Hollow Coastal Farming Tests...")
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
	CropDB.init_db()

	var farm := FarmManager.new(30.0, 7.0) # sea_mid=30, tide_amp=7 (high_tide=37)
	var inv := Inventory.new(24)

	# -------------------------------------------------------------------------
	# 1. Database & Elevation Salinity Tests
	# -------------------------------------------------------------------------
	var wheat_def: CropDef = CropDB.get_crop(&"shore_wheat")
	assert_test.call("CropDB has shore_wheat", wheat_def != null)
	assert_test.call("Wheat seed maps to shore_wheat crop", CropDB.get_crop_by_seed(&"seed_shore_wheat") == wheat_def)

	var samphire_def: CropDef = CropDB.get_crop(&"samphire")
	assert_test.call("Samphire is halophyte (preferred BRACKISH_SOIL, can_regrow=true)",
		samphire_def != null and samphire_def.preferred_soil == CropDef.SoilType.BRACKISH_SOIL and samphire_def.can_regrow)

	# Till plots at different heights
	var terrace_pos := Vector3i(100, 48, 100) # High cliff terrace (above high tide 37)
	var mudflat_pos := Vector3i(200, 32, 200) # Intertidal flat (below high tide 37)

	var terrace_plot: CropPlot = farm.till_plot(terrace_pos)
	var mudflat_plot: CropPlot = farm.till_plot(mudflat_pos)

	assert_test.call("High terrace plot has natural sweet soil (salinity=0.0)", terrace_plot.salinity == 0.0)
	assert_test.call("Intertidal mudflat plot has natural brackish soil (salinity >= 0.8)", mudflat_plot.salinity >= 0.8)

	# -------------------------------------------------------------------------
	# 2. Inventory Seeding & Planting
	# -------------------------------------------------------------------------
	inv.add_item(&"seed_shore_wheat", 5)
	inv.add_item(&"seed_samphire", 3)

	# Plant wheat on terrace
	inv.set_active_hotbar_index(0) # active slot has wheat seed
	var wheat_planted: bool = farm.plant_from_inventory(terrace_pos, inv)
	assert_test.call("Planted wheat from inventory on terrace plot", wheat_planted and terrace_plot.crop_id == &"shore_wheat")
	assert_test.call("Consumed 1 wheat seed (4 remaining)", inv.get_item_count(&"seed_shore_wheat") == 4)

	# Plant samphire on mudflat
	inv.set_active_hotbar_index(1) # active slot has samphire seed
	var samphire_planted: bool = farm.plant_from_inventory(mudflat_pos, inv)
	assert_test.call("Planted samphire from inventory on mudflat plot", samphire_planted and mudflat_plot.crop_id == &"samphire")
	assert_test.call("Consumed 1 samphire seed (2 remaining)", inv.get_item_count(&"seed_samphire") == 2)

	# -------------------------------------------------------------------------
	# 3. Growth Simulation & Salinity Interaction
	# -------------------------------------------------------------------------
	# Water terrace plot with freshwater
	farm.water_plot(terrace_pos, 0.8, 0.0)
	assert_test.call("Terrace plot hydrated with freshwater", terrace_plot.hydration >= 0.8 and terrace_plot.salinity == 0.0)

	# Simulate 100 seconds of growth for terrace wheat
	terrace_plot.tick(100.0, 30.0, false)
	assert_test.call("Wheat grew to mature stage in sweet soil", terrace_plot.is_mature() and terrace_plot.current_stage == 4)

	# High tide inundation on mudflat: tide reaches 35 (above plot Y=32)
	mudflat_plot.tick(10.0, 35.0, false)
	assert_test.call("High tide automatically watered mudflat samphire (hydration=1.0)", mudflat_plot.hydration == 1.0)
	assert_test.call("Mudflat salinity maintained at marine level", mudflat_plot.salinity >= 0.85)

	# Simulate remaining growth for samphire
	mudflat_plot.tick(120.0, 30.0, false)
	assert_test.call("Samphire grew to maturity in tidal brackish mud", mudflat_plot.is_mature())

	# -------------------------------------------------------------------------
	# 4. Harvest into Inventory & Regrowth
	# -------------------------------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# Harvest wheat
	var wheat_harvested: bool = farm.harvest_to_inventory(terrace_pos, inv, rng)
	assert_test.call("Wheat harvested into inventory", wheat_harvested)
	assert_test.call("Inventory received harvested shore_wheat", inv.get_item_count(&"shore_wheat") > 0)
	assert_test.call("Inventory received seeds back", inv.get_item_count(&"seed_shore_wheat") >= 5)
	assert_test.call("Terrace plot cleared after wheat harvest (not regrowing)", terrace_plot.is_empty())

	# Harvest samphire
	var samphire_harvested: bool = farm.harvest_to_inventory(mudflat_pos, inv, rng)
	assert_test.call("Samphire harvested into inventory", samphire_harvested)
	assert_test.call("Inventory received harvested samphire", inv.get_item_count(&"samphire") > 0)
	assert_test.call("Samphire regrows: plot remains planted at stage 2",
		mudflat_plot.crop_id == &"samphire" and mudflat_plot.current_stage == 2)

	# -------------------------------------------------------------------------
	# 5. Tidal Salt Evaporation Pan
	# -------------------------------------------------------------------------
	var pan_pos := Vector3i(205, 33, 205)
	var pan: SaltPan = farm.add_salt_pan(pan_pos)

	# 1. High tide floods pan (tide Y=35 > pan Y=33)
	pan.tick(5.0, 35.0, true, false)
	assert_test.call("High tide fills salt pan with brine (brine_level=1.0)", pan.brine_level == 1.0)

	# 2. Low tide + daylight evaporates water (tide Y=25 < pan Y=33)
	pan.tick(60.0, 25.0, true, false)
	assert_test.call("Daylight low tide evaporates brine and crystallizes sea salt", pan.accumulated_salt > 0)

	# 3. Harvest salt into inventory
	var salt_added: int = farm.harvest_salt_to_inventory(pan_pos, inv)
	assert_test.call("Harvested sea salt into inventory", salt_added > 0 and inv.get_item_count(&"sea_salt") == salt_added)
	assert_test.call("Salt pan emptied after harvest", pan.accumulated_salt == 0)

	# -------------------------------------------------------------------------
	# 6. FarmManager Serialization
	# -------------------------------------------------------------------------
	var farm_data := farm.serialize()
	var loaded_farm := FarmManager.new(30.0, 7.0)
	loaded_farm.deserialize(farm_data)

	assert_test.call("FarmManager deserialization restores crop plots and salt pans",
		loaded_farm.plots.has(mudflat_pos) and loaded_farm.salt_pans.has(pan_pos))

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	quit(0 if stats[0] == stats[1] else 1)
