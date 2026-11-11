extends SceneTree

func _init() -> void:
	print("\n==================================================")
	print("Running Craftable Rowboat Tests...")
	print("==================================================")

	var counts := {"total": 0, "passed": 0}

	var assert_test := func(name: String, condition: bool) -> void:
		counts.total += 1
		if condition:
			counts.passed += 1
			print("  [PASS] %s" % name)
		else:
			print("  [FAIL] %s" % name)

	# 1. ItemDB registration
	ItemDB.init_db()
	var item_def: ItemDef = ItemDB.get_item(&"rowboat_kit")
	assert_test.call("rowboat_kit registered in ItemDB", item_def != null)
	if item_def != null:
		assert_test.call("rowboat_kit name is 'Rowboat (kit)'", item_def.name == "Rowboat (kit)")
		assert_test.call("rowboat_kit has 'maritime' tag", item_def.has_tag("maritime"))
		assert_test.call("rowboat_kit has 'boat' tag", item_def.has_tag("boat"))

	# 2. RecipeDB recipes
	RecipeDB.init_db()
	var wb_rec: RecipeDef = RecipeDB.get_recipe(&"craft_rowboat_kit")
	assert_test.call("craft_rowboat_kit registered in RecipeDB", wb_rec != null)
	if wb_rec != null:
		assert_test.call("craft_rowboat_kit outputs rowboat_kit", wb_rec.output_item_id == &"rowboat_kit")
		assert_test.call("craft_rowboat_kit crafted at workbench", wb_rec.required_station == &"workbench")
	var has_input := func(rec: RecipeDef, item_id: StringName) -> bool:
		for inp: Dictionary in rec.inputs:
			if inp.get("item_id") == item_id:
				return true
		return false

	var em_rec: RecipeDef = RecipeDB.get_recipe(&"emergency_rowboat_kit")
	assert_test.call("emergency_rowboat_kit registered in RecipeDB", em_rec != null)
	if em_rec != null:
		assert_test.call("emergency_rowboat_kit outputs rowboat_kit", em_rec.output_item_id == &"rowboat_kit")
		assert_test.call("emergency_rowboat_kit is hand-crafted without station", em_rec.required_station == &"none")
		assert_test.call("emergency_rowboat_kit requires driftwood", has_input.call(em_rec, &"driftwood"))
		assert_test.call("emergency_rowboat_kit requires kelp fronds", has_input.call(em_rec, &"kelp_frond"))

	if wb_rec != null:
		assert_test.call("craft_rowboat_kit requires wood planks", has_input.call(wb_rec, &"wood_plank"))
		assert_test.call("craft_rowboat_kit requires driftwood", has_input.call(wb_rec, &"driftwood"))
		assert_test.call("craft_rowboat_kit requires kelp fronds", has_input.call(wb_rec, &"kelp_frond"))

	# 3. BoatManager integration
	assert_test.call("BoatManager.KITS recognizes rowboat_kit", BoatManager.KITS.has(&"rowboat_kit"))
	assert_test.call("rowboat_kit maps to Boat.KIND_ROWBOAT", BoatManager.KITS.get(&"rowboat_kit") == Boat.KIND_ROWBOAT)
	assert_test.call("BoatManager.KIT_HINT has rowboat hint", BoatManager.KIT_HINT.has(Boat.KIND_ROWBOAT))

	# 4. Fleet saving logic for crafted rowboats vs world-spawn rowboats
	var bm := BoatManager.new()
	var b_world := Boat.new()
	b_world.kind = Boat.KIND_ROWBOAT
	b_world.is_world_spawn = true
	b_world.position = Vector3(10, 0, 10)
	bm.boats[1] = b_world

	var b_crafted := Boat.new()
	b_crafted.kind = Boat.KIND_ROWBOAT
	b_crafted.is_world_spawn = false
	b_crafted.position = Vector3(50, 0, 50)
	bm.boats[2] = b_crafted

	var saved: Array = bm._save_fleet()
	assert_test.call("Fleet save contains exactly 1 boat (crafted rowboat)", saved.size() == 1)
	if not saved.is_empty():
		assert_test.call("Saved boat is KIND_ROWBOAT", saved[0].get("kind") == Boat.KIND_ROWBOAT)
		assert_test.call("Saved boat position matches crafted boat", (saved[0].get("pos") as Vector3).is_equal_approx(Vector3(50, 0, 50)))

	b_world.free()
	b_crafted.free()
	bm.free()

	print("==================================================")
	print("Results: %d/%d passed" % [counts.passed, counts.total])
	print("==================================================")

	if counts.passed == counts.total and counts.total > 0:
		quit(0)
	else:
		quit(1)
