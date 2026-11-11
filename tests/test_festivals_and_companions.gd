extends SceneTree

var passed := 0
var failed := 0

func assert_true(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("  [PASS] %s" % msg)
	else:
		failed += 1
		printerr("  [FAIL] %s" % msg)

func _init() -> void:
	print("\n=== STARTING FESTIVALS & COMPANIONS TEST SUITE ===")

	# 1. Floating Lanterns
	print("\n--- Test: Night of the Floating Lanterns ---")
	var flm_script := load("res://scripts/festivals/floating_lanterns.gd")
	assert_true(flm_script != null, "floating_lanterns.gd loads successfully")
	var flm = flm_script.new()
	assert_true(flm != null, "FloatingLanternManager instantiates")
	flm.setup(null, null, null)
	assert_true(flm._lantern_mesh != null, "Lantern mesh template created")
	assert_true(flm._lantern_mat != null and flm._lantern_mat.emission_enabled, "Lantern emission material enabled")
	flm.spawn_player_wish_lantern(Vector3(10, 18, 10))
	assert_true(flm._lanterns.size() == 1, "Player wish lantern successfully spawned")
	assert_true(flm._lanterns[0].is_player_wish, "Spawned lantern marked as player wish")
	flm.free()

	# 2. Communal Banquet Table Steam & Feast
	print("\n--- Test: Banquet Table Presentation & Festivities ---")
	var b_script := load("res://scripts/entities/banquet_table_entity.gd")
	assert_true(b_script != null, "banquet_table_entity.gd loads successfully")
	var table: BanquetTableEntity = b_script.new()
	table._build_visuals()
	table.dishes = [&"shore_soup", &"baked_fish", &"fruit_tart"]
	table._update_dish_visuals()
	assert_true(table._dishes_group.get_child_count() == 3, "3 dishes with plates placed on banquet table")
	var p_script := load("res://scripts/player.gd")
	var test_player = p_script.new()
	table._partake_feast(test_player)
	assert_true(table.dishes.is_empty(), "Dishes cleared after feast celebrated")
	test_player.free()
	table.free()

	# 3. Drifter Tavern Dancing
	print("\n--- Test: Drifter Tavern Dancing ---")
	var d_script := load("res://scripts/village/drifter_npc.gd")
	assert_true(d_script != null, "drifter_npc.gd loads successfully")
	var d_def_script := load("res://scripts/village/drifter_def.gd")
	var d_def = d_def_script.new(&"drifter_1", "Old Barnaby", 0)
	d_def.morale = 0.85
	var npc = d_script.new()
	npc.setup(0, d_def, Vector3.ZERO, 123)
	npc.activity = 1 # WANDER / social
	assert_true(npc.def.morale >= 0.5, "Drifter has high morale for social celebration")
	npc.free()

	# 4. Sea Otter Companion
	print("\n--- Test: Sea Otter Companion ---")
	var otter_script := load("res://scripts/wildlife/otter.gd")
	assert_true(otter_script != null, "otter.gd loads successfully")
	var otter = otter_script.new()
	assert_true(otter.pet_name != "", "Otter has default pet name")
	otter.befriend(1)
	assert_true(otter.is_friend(), "Otter is befriended by player 1")
	assert_true(otter.pet_name != "", "Otter assigned cute companion name (%s)" % otter.pet_name)
	assert_true(otter.GIFTS.size() >= 8, "Otter gift table expanded with shellfish and pearls")
	otter.free()

	# 5. Dock Cat Feeding & Buffs
	print("\n--- Test: Dock Cat Feeding & Morale ---")
	var guard_script := load("res://scripts/entities/guard_animal_entity.gd")
	assert_true(guard_script != null, "guard_animal_entity.gd loads successfully")
	var cat: GuardAnimalEntity = guard_script.make_cat_basket(Vector3i(10, 5, 10))
	assert_true(not cat.is_dog(), "Guard animal is cat")
	assert_true(cat.pet_name == "Barnacle", "Cat has pet name Barnacle")
	var dummy_p2 = p_script.new()
	var prompt := cat.get_interaction_prompt(dummy_p2)
	assert_true(prompt.contains("Barnacle"), "Interaction prompt references cat name")
	cat.client_interact(dummy_p2)
	dummy_p2.free()
	cat.free()

	# 6. Sea-Hawk Scouting
	print("\n--- Test: Sea-Hawk Scouting ---")
	var boat_script := load("res://scripts/boat.gd")
	var boat = boat_script.new(Boat.KIND_SKIFF)
	boat.setup(1, null, null, Vector3.ZERO, 0.0, Boat.KIND_SKIFF)
	assert_true(boat.scout_surroundings() == "", "No scouting report without sea hawk perch")
	boat.install_fixture(0, &"sea_hawk_perch", {})
	assert_true(boat.has_sea_hawk, "Boat has sea hawk fixture active")
	var report: String = boat.scout_surroundings()
	assert_true(report.contains("Sea-Hawk"), "Sea-hawk generates scouting report")
	boat.free()

	print("\n=== TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [passed, failed])
	if failed == 0:
		print("ALL FESTIVALS & COMPANIONS TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("SOME TESTS FAILED!")
	quit()
