extends SceneTree
## Automated headless test suite for Brine's Hollow Crafting Stations & Culinary Cooking Systems.

func _init() -> void:
	print("==================================================")
	print("Running Brine's Hollow Crafting & Culinary Tests...")
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
	# 1. Recipe Registry & Database Indexing
	# -------------------------------------------------------------------------
	assert_test.call("RecipeDB contains craft_wood_plank", RecipeDB.has_recipe(&"craft_wood_plank"))
	assert_test.call("RecipeDB contains cook_roasted_mackerel", RecipeDB.has_recipe(&"cook_roasted_mackerel"))
	assert_test.call("RecipeDB contains cook_bouillabaisse", RecipeDB.has_recipe(&"cook_bouillabaisse"))
	assert_test.call("RecipeDB contains smoke_fish_ration", RecipeDB.has_recipe(&"smoke_fish_ration"))
	assert_test.call("RecipeDB contains cure_pickled_samphire", RecipeDB.has_recipe(&"cure_pickled_samphire"))
	assert_test.call("RecipeDB contains brew_kelp_tea", RecipeDB.has_recipe(&"brew_kelp_tea"))

	var campfire_recipes := RecipeDB.get_recipes_for_station(&"campfire")
	assert_test.call("Campfire station has at least 2 roasted fish recipes", campfire_recipes.size() >= 2)

	var hearth_recipes := RecipeDB.get_recipes_for_station(&"hearth_pot")
	assert_test.call("Hearth pot station has at least 4 culinary recipes", hearth_recipes.size() >= 4)

	var basic_recipes := RecipeDB.get_recipes_by_category(RecipeDef.Category.BASIC)
	assert_test.call("Category.BASIC returns field hand-crafting recipes", basic_recipes.size() >= 3)

	# -------------------------------------------------------------------------
	# 2. Ingredient Validation & Dynamic Craftability
	# -------------------------------------------------------------------------
	var inv := Inventory.new(24)
	var plank_recipe := RecipeDB.get_recipe(&"craft_wood_plank")
	assert_test.call("Empty inventory cannot craft wood planks", not plank_recipe.can_craft_with(inv))

	inv.add_item(&"driftwood", 5)
	assert_test.call("Inventory with driftwood can craft wood planks", plank_recipe.can_craft_with(inv))

	var craftable_basic := RecipeDB.get_craftable_recipes(inv, &"none")
	assert_test.call("get_craftable_recipes returns craft_wood_plank for 5 driftwood",
		craftable_basic.any(func(r: RecipeDef) -> bool: return r.id == &"craft_wood_plank"))

	# -------------------------------------------------------------------------
	# 3. Instant Field Crafting (Hand Crafting)
	# -------------------------------------------------------------------------
	var field_station := CraftingStation.new(&"none", "Field Crafting")
	var craft_ok := field_station.craft_recipe(&"craft_wood_plank", inv, 2)
	assert_test.call("Crafting 2 batches of wood planks succeeds", craft_ok)
	assert_test.call("Driftwood count reduced by 2 (3 remaining)", inv.get_item_count(&"driftwood") == 3)
	assert_test.call("Produced 8 wood planks in inventory", inv.get_item_count(&"wood_plank") == 8)

	# -------------------------------------------------------------------------
	# 4. Station Gating & Error Signals
	# -------------------------------------------------------------------------
	var workbench := CraftingStation.new(&"workbench", "Carpenter's Bench")
	var halt_sig := [""]
	workbench.station_halted.connect(func(reason: String) -> void:
		halt_sig[0] = reason
	)

	# Attempt to cook soup on a carpenter's workbench
	var wrong_station := workbench.craft_recipe(&"cook_bouillabaisse", inv)
	assert_test.call("Crafting bouillabaisse on workbench fails station check", not wrong_station)
	assert_test.call("Station emitted mismatch reason", halt_sig[0].contains("requires station 'hearth_pot'"))

	# -------------------------------------------------------------------------
	# 5. Timed Culinary Cooking & Batch Ticks (Hearth Cauldron)
	# -------------------------------------------------------------------------
	var hearth := CraftingStation.new(&"hearth_pot", "Hearth Cauldron")
	inv.add_item(&"cliff_salmon", 1)
	inv.add_item(&"shore_crab", 1)
	inv.add_item(&"samphire", 2)

	var cook_started_sig := ["", 0.0]
	hearth.craft_started.connect(func(id: StringName, dur: float) -> void:
		cook_started_sig[0] = String(id)
		cook_started_sig[1] = dur
	)

	var completed_sig := ["", 0]
	hearth.craft_completed.connect(func(id: StringName, out_id: StringName, count: int) -> void:
		completed_sig[0] = String(out_id)
		completed_sig[1] = count
	)

	var cook_started := hearth.craft_recipe(&"cook_bouillabaisse", inv)
	assert_test.call("Starting bouillabaisse cooking succeeds", cook_started and hearth.is_active)
	assert_test.call("Cook started event fired with 10s cook duration",
		cook_started_sig[0] == "cook_bouillabaisse" and cook_started_sig[1] == 10.0)
	assert_test.call("Ingredients consumed up front upon starting cook",
		inv.get_item_count(&"cliff_salmon") == 0 and inv.get_item_count(&"shore_crab") == 0)

	# Advance time halfway (5 seconds)
	hearth.tick(5.0, inv)
	assert_test.call("Halfway through cook, dish is not yet completed", hearth.is_active and inv.get_item_count(&"samphire_bouillabaisse") == 0)

	# Advance remaining 5 seconds to complete dish
	hearth.tick(5.0, inv)
	assert_test.call("Cooking completed and station deactivated", not hearth.is_active)
	assert_test.call("Completed signal emitted with samphire_bouillabaisse", completed_sig[0] == "samphire_bouillabaisse" and completed_sig[1] == 1)
	assert_test.call("Inventory received 1 Samphire Bouillabaisse", inv.get_item_count(&"samphire_bouillabaisse") == 1)

	# -------------------------------------------------------------------------
	# 6. Fuel Mechanics & Smokehouse Preservation
	# -------------------------------------------------------------------------
	var smokehouse := CraftingStation.new(&"smokehouse", "Tidal Smokehouse", true) # Requires fuel
	assert_test.call("Smokehouse is initially unfueled", not smokehouse.is_fueled())

	inv.add_item(&"silver_mackerel", 2)
	inv.add_item(&"sea_salt", 1)
	inv.add_item(&"dark_wood", 2)

	halt_sig[0] = ""
	smokehouse.station_halted.connect(func(reason: String) -> void:
		halt_sig[0] = reason
	)

	var smoke_unfueled := smokehouse.craft_recipe(&"smoke_fish_ration", inv)
	assert_test.call("Unfueled smokehouse rejects smoking", not smoke_unfueled and halt_sig[0].contains("requires fuel"))

	# Fuel smokehouse with 1 dark_wood (provides 60 seconds of burn time)
	var fueled_count := smokehouse.add_fuel_from_inventory(inv, &"dark_wood", 1)
	assert_test.call("Consumed 1 dark_wood for fuel", fueled_count == 1 and inv.get_item_count(&"dark_wood") == 1)
	assert_test.call("Smokehouse now has 60s burn time", smokehouse.fuel_remaining_sec == 60.0 and smokehouse.is_fueled())

	# Start smoking rations
	var smoke_started := smokehouse.craft_recipe(&"smoke_fish_ration", inv)
	assert_test.call("Smoking fish ration starts successfully when fueled", smoke_started and smokehouse.is_active)

	# Progress 10s of smoking
	smokehouse.tick(10.0, inv)
	assert_test.call("Smoking completed: produced 2 Smoked Fish Rations", inv.get_item_count(&"smoked_fish_ration") == 2)
	assert_test.call("Fuel burned by 10s (50s fuel remaining)", is_equal_approx(smokehouse.fuel_remaining_sec, 50.0))

	# -------------------------------------------------------------------------
	# 7. Saltery Curing & Teahouse Infusions
	# -------------------------------------------------------------------------
	var brewery := CraftingStation.new(&"brewery", "Coastal Teahouse")
	inv.add_item(&"kelp_frond", 2)
	inv.add_item(&"marsh_honey", 1)

	var brew_ok := brewery.craft_recipe(&"brew_kelp_tea", inv)
	assert_test.call("Brewing peppermint kelp tea starts", brew_ok and brewery.is_active)
	brewery.tick(5.0, inv)
	assert_test.call("Brewed Peppermint Kelp Tea delivered to inventory", inv.get_item_count(&"peppermint_kelp_tea") == 1)

	# -------------------------------------------------------------------------
	# 8. Satiety & Buff Data Integrity
	# -------------------------------------------------------------------------
	var tea_def := ItemDB.get_item(&"peppermint_kelp_tea")
	assert_test.call("Peppermint Kelp Tea grants +75% stamina regen", tea_def.food_data.get("stamina_regen_mult", 1.0) == 1.75)

	var bouillabaisse_def := ItemDB.get_item(&"samphire_bouillabaisse")
	assert_test.call("Bouillabaisse grants +45 Max HP and +40 Max Stamina",
		bouillabaisse_def.food_data.get("hp_bonus", 0) == 45 and bouillabaisse_def.food_data.get("stamina_bonus", 0) == 40)
	assert_test.call("Bouillabaisse grants +20% swim speed buff",
		bouillabaisse_def.food_data.get("swim_speed", 1.0) == 1.20)

	var crab_def := ItemDB.get_item(&"glazed_abyssal_crab")
	assert_test.call("Glazed Abyssal Crab grants +70 Max HP, cold immunity, and +60s breath",
		crab_def.food_data.get("hp_bonus", 0) == 70 and crab_def.food_data.get("cold_immunity", false) == true and
		crab_def.food_data.get("extra_breath_sec", 0.0) == 60.0)

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	if stats[0] == stats[1]:
		quit(0)
	else:
		quit(1)
