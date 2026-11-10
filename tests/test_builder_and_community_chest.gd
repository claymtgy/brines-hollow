extends SceneTree

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\n=== STARTING BUILDER & COMMUNITY CHEST TEST SUITE ===")
	run_tests()
	print("\n=== TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [_passed, _failed])
	if _failed > 0:
		print("FAILED with %d errors" % _failed)
	else:
		print("ALL BUILDER & COMMUNITY CHEST TESTS PASSED!")
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

	test_community_chest()
	test_builder_drifter()
	test_construction_site()
	test_builder_working_on_site()
	test_settlement_manager_integration()


func test_community_chest() -> void:
	print("\n--- 1. Community Stockpile Chest ---")
	var chest: ChestEntity = ChestEntity.make_community_chest(Vector3i(10, 0, 10))

	assert_true(chest.entity_id == &"community_chest", "Chest entity ID is community_chest")
	assert_true(chest.style == &"community", "Chest style is community")
	assert_true(chest.sealed == true, "Community chest is rat-proof sealed")
	assert_true(chest.container.inventory.capacity == 48, "Community chest has 48 storage slots")

	# Test supply deposit
	var deposited := chest.deposit_supplies(&"wood_plank", 20)
	assert_true(deposited == 20, "Deposited 20 wood planks into community chest")
	assert_true(chest.has_supplies(&"wood_plank", 20), "Chest has 20 wood planks")
	assert_true(chest.has_supplies(&"wood_plank", 25) == false, "Chest does not have 25 planks")

	# Test supplies overview
	chest.deposit_supplies(&"cobblestone", 15)
	var supplies := chest.get_available_supplies()
	assert_true(supplies.get(&"wood_plank", 0) == 20, "Supplies dict contains 20 wood planks")
	assert_true(supplies.get(&"cobblestone", 0) == 15, "Supplies dict contains 15 cobblestone")

	# Test withdrawal
	var pulled := chest.withdraw_supplies(&"wood_plank", 8)
	assert_true(pulled == 8, "Successfully withdrew 8 wood planks")
	assert_true(chest.has_supplies(&"wood_plank", 12), "Remaining planks count is 12")


func test_builder_drifter() -> void:
	print("\n--- 2. Builder Drifter Definition ---")
	var builder := DrifterDef.new(&"drifter_bram", "Bram the Mason", DrifterDef.Profession.BUILDER)

	assert_true(builder.profession == DrifterDef.Profession.BUILDER, "Drifter profession is BUILDER")
	assert_true(builder.profession_name() == "Builder", "Profession display name is Builder")

	# Test fallback work when no construction site is active
	var depot := StorageContainer.new("Test Depot", 10)
	depot.deposit(&"stone", 4)
	builder.current_routine = DrifterDef.Routine.WORK
	builder.work_progress_sec = 60.0 # Force work cycle completion

	var yields := builder.tick_work(1.0, depot)
	assert_true(yields.get(&"cobblestone", 0) == 2, "Builder refines stone into cobblestone when no site active")


func test_construction_site() -> void:
	print("\n--- 3. House Construction Site Entity ---")
	var site := ConstructionSiteEntity.new(Vector3i(20, 0, 20), &"fisher_hut")

	assert_true(site.blueprint_id == &"fisher_hut", "Construction site blueprint is fisher_hut")
	assert_true(site.building_name == "Fisher's Hut", "Building name is Fisher's Hut")
	assert_true(site.is_completed == false, "Site starts uncompleted")
	assert_true(site.build_progress == 0.0, "Site build progress starts at 0.0")

	var missing := site.get_missing_materials()
	assert_true(missing.has(&"wood_plank"), "Missing materials includes wood_plank")
	assert_true(missing.has(&"cobblestone"), "Missing materials includes cobblestone")
	assert_true(site.is_materials_satisfied() == false, "Materials are not satisfied initially")

	# Test direct material deposit
	var accepted := site.deposit_material(&"wood_plank", 10)
	assert_true(accepted == 10, "Site accepted 10 wood planks")
	assert_true(site.staged_materials[&"wood_plank"] == 10, "Staged materials tracks 10 wood planks")

	# Cannot over-deposit beyond requirements
	var req_planks: int = site.required_materials[&"wood_plank"]
	var excess := site.deposit_material(&"wood_plank", 100)
	assert_true(site.staged_materials[&"wood_plank"] == req_planks, "Staged materials caps at required amount")


func test_builder_working_on_site() -> void:
	print("\n--- 4. Builder Working on Construction Site ---")
	var site := ConstructionSiteEntity.new(Vector3i(30, 0, 30), &"drifter_cottage")
	var chest := ChestEntity.make_community_chest(Vector3i(28, 0, 28))

	# Stock community chest with required supplies
	chest.deposit_supplies(&"wood_plank", 30)
	chest.deposit_supplies(&"cobblestone", 20)
	chest.deposit_supplies(&"sea_glass", 5)

	# Pull from community chest
	var pulled := site.pull_from_chest(chest)
	assert_true(pulled > 0, "Construction site pulled missing supplies from Community Chest")
	assert_true(site.is_materials_satisfied() == true, "All building materials are satisfied after chest pull")

	# Advance build progress
	var builder := DrifterDef.new(&"drifter_aldus", "Aldus", DrifterDef.Profession.BUILDER)
	builder.current_routine = DrifterDef.Routine.WORK
	builder.assigned_room_id = 0 # Housed builder

	var finished := false
	for i in range(30):
		finished = builder.tick_builder_site(1.0, site, chest)
		if finished:
			break

	assert_true(site.is_completed == true, "Construction completed by Builder")
	assert_true(site.build_progress >= 1.0, "Build progress reached 1.0")


func test_settlement_manager_integration() -> void:
	print("\n--- 5. SettlementManager & Community Chest Integration ---")
	var sm := SettlementManager.new(Vector3i(0, 0, 0), "Test Village")
	var chest := ChestEntity.make_community_chest(Vector3i(5, 0, 5))
	var site := ConstructionSiteEntity.new(Vector3i(15, 0, 15), &"fisher_hut")

	sm.community_chest = chest
	sm.active_construction_site = site

	assert_true(sm.community_chest != null, "SettlementManager holds community_chest reference")
	assert_true(sm.active_construction_site != null, "SettlementManager holds active_construction_site reference")

	# Stock chest and recruit a Builder
	chest.deposit_supplies(&"wood_plank", 20)
	chest.deposit_supplies(&"cobblestone", 15)
	chest.deposit_supplies(&"driftwood", 10)

	var builder := DrifterDef.new(&"drifter_mason", "Mason Drifter", DrifterDef.Profession.BUILDER)
	sm.recruit_drifter(builder)

	# Run settlement tick during work hours (day_fraction = 0.5)
	sm.tick_settlement(1.0, 0.5)

	assert_true(site.staged_materials.size() > 0, "Settlement tick staged materials onto construction site")
	assert_true(site.build_progress > 0.0, "Settlement tick advanced construction site build progress")
