extends SceneTree

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\n=== STARTING ACT IV & HOMESTEAD EXPANSION TEST SUITE ===")
	run_tests()
	print("\n=== TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [_passed, _failed])
	if _failed > 0:
		print("FAILED with %d errors" % _failed)
	else:
		print("ALL ACT IV & HOMESTEAD EXPANSION TESTS PASSED!")
	quit(0 if _failed == 0 else 1)


func assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)


func run_tests() -> void:
	test_pillar1_frost_shoals_and_borean()
	test_pillar2_maelstrom_and_sovereign()
	test_gear_and_item_registry()
	test_pillar3_advanced_architecture()
	test_pillar4_homestead_and_companions()
	test_act4_storyline_quests()


# -----------------------------------------------------------------------------
# PILLAR 1: THE FROST-SHOALS & BOREAN GORE-FIN
# -----------------------------------------------------------------------------
func test_pillar1_frost_shoals_and_borean() -> void:
	print("\n--- Pillar 1: The Frost-Shoals & Borean Gore-Fin ---")
	var borean := BoreanGoreFin.new()
	assert_true(borean != null, "BoreanGoreFin instantiates successfully")
	assert_true(borean.kind == &"borean_gore_fin", "Borean kind is &\"borean_gore_fin\"")
	assert_true(borean.max_hp >= 400.0, "Borean Gore-Fin has boss-level HP (%f >= 400)" % borean.max_hp)

	borean.setup(99, null, Vector3(0, 0, 0), true)
	var drops: Array = borean.drops()
	assert_true(drops.size() >= 2, "Borean drops at least 2 item stacks")
	var has_tusk := false
	var has_fur := false
	for d in drops:
		if d[0] == &"glacial_tusk": has_tusk = true
		if d[0] == &"borean_fur": has_fur = true
	assert_true(has_tusk and has_fur, "Borean drops both Glacial Ivory Tusk and Borean Fur")

	# Test Borean Lair
	var lair := BoreanLair.new()
	assert_true(lair != null, "BoreanLair instantiates successfully")
	assert_true(not lair.slain, "BoreanLair initial slain state is false")
	lair.on_borean_slain(1)
	assert_true(lair.slain, "BoreanLair marks slain when on_borean_slain called")
	borean.free()
	lair.free()


# -----------------------------------------------------------------------------
# PILLAR 2: THE MAELSTROM SPIRE & THE TIDE SOVEREIGN
# -----------------------------------------------------------------------------
func test_pillar2_maelstrom_and_sovereign() -> void:
	print("\n--- Pillar 2: The Maelstrom Spire & The Tide Sovereign ---")
	var sovereign := TideSovereign.new()
	assert_true(sovereign != null, "TideSovereign instantiates successfully")
	assert_true(sovereign.kind == &"tide_sovereign", "TideSovereign kind is &\"tide_sovereign\"")
	assert_true(sovereign.max_hp >= 600.0, "TideSovereign has climax boss HP (%f >= 600)" % sovereign.max_hp)

	sovereign.setup(100, null, Vector3(0, 0, 0), true)
	assert_true(sovereign.hydro_barrier > 0.0, "Tide Sovereign starts with hydro-barrier shield (%f)" % sovereign.hydro_barrier)

	# Barrier absorption test
	var start_hp := sovereign.hp
	sovereign.on_hit(20.0, Vector3.FORWARD, 0.0, 1)
	assert_true(sovereign.hp == start_hp, "Hydro barrier absorbs damage before HP is harmed")

	var drops: Array = sovereign.drops()
	var has_trident := false
	var has_core := false
	for d in drops:
		if d[0] == &"sovereign_trident": has_trident = true
		if d[0] == &"deluge_core": has_core = true
	assert_true(has_trident and has_core, "Tide Sovereign drops Sovereign Trident and Deluge Core")

	# Test Maelstrom Spire Lair
	var spire := MaelstromSpire.new()
	assert_true(spire != null, "MaelstromSpire instantiates successfully")
	assert_true(not spire.slain, "MaelstromSpire initial slain state is false")
	spire.on_sovereign_slain(1)
	assert_true(spire.slain, "MaelstromSpire marks slain when on_sovereign_slain called")
	sovereign.free()
	spire.free()


# -----------------------------------------------------------------------------
# GEAR, WEAPONS & ITEM REGISTRY
# -----------------------------------------------------------------------------
func test_gear_and_item_registry() -> void:
	print("\n--- Gear, Weapons & Item Registry ---")
	ItemDB.init_db()

	assert_true(ItemDB.has_item(&"borean_parka"), "ItemDB contains borean_parka")
	var parka: ItemDef = ItemDB.get_item(&"borean_parka")
	assert_true(parka.equip_slot == &"body", "Borean parka equips to body slot")
	assert_true(float(parka.armor_data.get("cold_protection", 0.0)) >= 1.0, "Borean parka grants complete cold protection")
	assert_true(bool(parka.armor_data.get("frost_immunity", false)), "Borean parka grants frost immunity")

	assert_true(ItemDB.has_item(&"glacial_ice_lance"), "ItemDB contains glacial_ice_lance")
	var lance: ItemDef = ItemDB.get_item(&"glacial_ice_lance")
	assert_true(int(lance.tool_data.get("damage", 0)) >= 25, "Glacial lance deals heavy damage")

	assert_true(ItemDB.has_item(&"sovereign_trident"), "ItemDB contains sovereign_trident")
	var trident: ItemDef = ItemDB.get_item(&"sovereign_trident")
	assert_true(int(trident.tool_data.get("damage", 0)) >= 45, "Sovereign trident deals climax tier damage")
	assert_true(bool(trident.tool_data.get("cavitation", false)), "Sovereign trident has cavitation shockwave")

	assert_true(ItemDB.has_item(&"deluge_core"), "ItemDB contains deluge_core")
	assert_true(ItemDB.has_item(&"blueprint_scroll"), "ItemDB contains blueprint_scroll")
	assert_true(ItemDB.has_item(&"aged_brine_cheese"), "ItemDB contains aged_brine_cheese")
	assert_true(ItemDB.has_item(&"vintage_maritime_ale"), "ItemDB contains vintage_maritime_ale")
	assert_true(ItemDB.has_item(&"brackish_rye_bread"), "ItemDB contains brackish_rye_bread")
	assert_true(ItemDB.has_item(&"maritime_stout"), "ItemDB contains maritime_stout")

	# Recipes
	RecipeDB.init_db()
	assert_true(RecipeDB.has_recipe(&"craft_borean_parka"), "RecipeDB contains craft_borean_parka")
	assert_true(RecipeDB.has_recipe(&"anvil_glacial_ice_lance"), "RecipeDB contains anvil_glacial_ice_lance")
	assert_true(RecipeDB.has_recipe(&"cook_brackish_rye_bread"), "RecipeDB contains cook_brackish_rye_bread")
	assert_true(RecipeDB.has_recipe(&"cook_maritime_stout"), "RecipeDB contains cook_maritime_stout")


# -----------------------------------------------------------------------------
# PILLAR 3: ADVANCED ARCHITECTURE
# -----------------------------------------------------------------------------
func test_pillar3_advanced_architecture() -> void:
	print("\n--- Pillar 3: Advanced Architecture & Placeables ---")
	Placeables.register_builtin()

	assert_true(Placeables.BUILTIN.has(&"drafting_desk"), "Placeables contains drafting_desk")
	assert_true(Placeables.BUILTIN.has(&"fish_trophy"), "Placeables contains fish_trophy")
	assert_true(Placeables.BUILTIN.has(&"aquarium"), "Placeables contains aquarium")
	assert_true(Placeables.BUILTIN.has(&"heraldic_banner"), "Placeables contains heraldic_banner")
	assert_true(Placeables.BUILTIN.has(&"aging_cask"), "Placeables contains aging_cask")

	# Drafting desk functionality
	var desk := DraftingDeskEntity.new(Vector3i(10, 0, 10))
	assert_true(desk.item_id == &"drafting_desk", "DraftingDeskEntity initialized")
	var inv := Inventory.new(16)
	inv.add_item(&"driftwood", 4)
	var fake_player := CharacterBody3D.new()
	fake_player.set_script(load("res://scripts/player.gd"))
	fake_player.inventory = inv
	desk.interact(fake_player)
	assert_true(inv.has_item(&"blueprint_scroll"), "Interacting with DraftingDesk produces blueprint_scroll")
	assert_true(desk.drafts_completed == 1, "DraftingDesk tracks completed drafts")
	desk.free()

	# Trophy & Aquarium visuals
	var trophy := FishTrophyEntity.new(Vector3i(10, 2, 10))
	assert_true(trophy.entity_type == WorldEntity.EntityType.DECOR, "Fish trophy is decor type")
	trophy.free()

	var aquarium := AquariumEntity.new(Vector3i(10, 0, 10))
	assert_true(aquarium.item_id == &"aquarium", "AquariumEntity initialized")
	aquarium.free()

	var banner := HeraldicBannerEntity.new(Vector3i(10, 0, 10))
	assert_true(banner.item_id == &"heraldic_banner", "HeraldicBannerEntity initialized")
	banner.free()

	# Aging cask functionality & curing lifecycle
	var cask := AgingCaskEntity.new(Vector3i(10, 0, 10))
	var dairy_inv := Inventory.new(16)
	dairy_inv.add_item(&"salt_milk", 2)
	fake_player.inventory = dairy_inv
	cask.interact(fake_player)
	assert_true(cask.is_fermenting, "AgingCask begins fermenting when salt_milk supplied")
	assert_true(cask.current_output == &"aged_brine_cheese", "AgingCask targets aged_brine_cheese from salt_milk")

	# Fast forward aging
	cask.advance_time(50.0)
	assert_true(cask.output_ready, "AgingCask output is ready after process time")
	cask.interact(fake_player)
	assert_true(dairy_inv.has_item(&"aged_brine_cheese"), "AgingCask deposits aged_brine_cheese into player inventory")
	cask.free()
	fake_player.free()


# -----------------------------------------------------------------------------
# PILLAR 4: HOMESTEAD DEEPENING & WORKING COMPANIONS
# -----------------------------------------------------------------------------
func test_pillar4_homestead_and_companions() -> void:
	print("\n--- Pillar 4: Homestead Deepening & Companions ---")
	CropDB.init_db()
	assert_true(CropDB.has_crop(&"brackish_rye"), "CropDB has brackish_rye registered")

	# Crop hybridization test
	var farm := FarmManager.new(30.0, 7.0)
	var p_wheat := farm.till_plot(Vector3i(10, 35, 10))
	var p_samphire := farm.till_plot(Vector3i(11, 35, 10)) # Adjacent plot
	p_wheat.plant(&"shore_wheat")
	p_samphire.plant(&"samphire")

	# Advance both crops to maturity
	p_wheat.current_stage = 4
	p_samphire.current_stage = 4

	var harvest_inv := Inventory.new(16)
	var hybrid_found := false
	for attempt in 10:
		p_wheat.plant(&"shore_wheat")
		p_wheat.current_stage = 4
		farm.harvest_to_inventory(Vector3i(10, 35, 10), harvest_inv)
		if harvest_inv.has_item(&"seed_brackish_rye") or harvest_inv.has_item(&"brackish_rye"):
			hybrid_found = true
			break
	assert_true(harvest_inv.has_item(&"shore_wheat"), "Harvest yielded Shore Wheat")
	assert_true(hybrid_found, "Cross-pollination produced Brackish Rye hybrid seeds or crop")

	# Working Otter Companion
	var otter := SeaOtter.new()
	assert_true(not otter.is_friend(), "Otter starts wild")
	otter.befriend(1)
	assert_true(otter.is_friend(), "Otter befriended by player 1")
	var foraging := otter.command_dive_forage(1)
	assert_true(foraging, "Commanding friend otter to dive forage succeeds")
	otter.free()


# -----------------------------------------------------------------------------
# STORYLINE ACT IV QUESTS
# -----------------------------------------------------------------------------
func test_act4_storyline_quests() -> void:
	print("\n--- Act IV Storyline Quests ---")
	var qm := QuestManager.new()
	var act4_quests: Array = qm.get_quests_by_act(4)
	assert_true(act4_quests.size() >= 3, "Act IV has at least 3 quests (found %d)" % act4_quests.size())

	var has_borean_quest := false
	var has_sovereign_quest := false
	var has_arch_quest := false
	for q in act4_quests:
		if q.id == &"story_borean_hunt": has_borean_quest = true
		if q.id == &"story_tide_sovereign": has_sovereign_quest = true
		if q.id == &"story_grand_architecture": has_arch_quest = true

	assert_true(has_borean_quest, "Quest 'story_borean_hunt' registered for Act IV")
	assert_true(has_sovereign_quest, "Quest 'story_tide_sovereign' registered for Act IV")
	assert_true(has_arch_quest, "Quest 'story_grand_architecture' registered for Act IV")

	# Test progressing story_borean_hunt
	qm.accept_quest(&"story_borean_hunt")
	assert_true(qm.is_quest_active(&"story_borean_hunt"), "Accepted story_borean_hunt")
	qm.notify_event(QuestDef.ObjectiveType.DEFEAT_ENEMY, &"borean_gore_fin", 1)
	qm.notify_event(QuestDef.ObjectiveType.CRAFT_ITEM, &"borean_parka", 1)
	assert_true(qm.is_quest_completed(&"story_borean_hunt"), "Completed story_borean_hunt")
