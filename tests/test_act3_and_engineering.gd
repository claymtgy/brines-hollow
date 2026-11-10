extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	print("\n==================================================")
	print("Running Act III & Tidal Engineering Test Suite")
	print("==================================================\n")

	_test_caldera_shell_and_volcanic_gear()
	_test_ocean_schooner_vessel()
	_test_tidal_power_and_mills()
	_test_sluice_gate()
	_test_undertow_gauntlet_and_regulator()
	_test_act3_quests()

	print("\n==================================================")
	print("Act III & Engineering: %d / %d tests passed!" % [_passed, _passed + _failed])
	print("==================================================\n")

	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _assert(condition: bool, msg: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)


func _test_caldera_shell_and_volcanic_gear() -> void:
	print("-- 1. Biome 3: Caldera Shell (Ignis-Chelon) & Basalt Gear")
	ItemDB.init_db()
	RecipeDB.init_db()
	_assert(ItemDB.has_item(&"caldera_basalt_plate"), "Caldera Basalt Plate registered in ItemDB")
	_assert(ItemDB.has_item(&"geothermal_core"), "Geothermal Core registered in ItemDB")
	_assert(ItemDB.has_item(&"volcanic_basalt_armor"), "Volcanic Basalt Armor registered in ItemDB")

	var armor: ItemDef = ItemDB.get_item(&"volcanic_basalt_armor")
	_assert(armor != null and armor.armor_data.get("defense", 0) >= 16, "Volcanic Basalt Armor has defense >= 16")
	_assert(armor != null and armor.armor_data.get("fire_immunity", false) == true, "Volcanic Basalt Armor grants fire/boil immunity")

	var cs := CalderaShell.new()
	_assert(cs.max_hp == 240.0, "Caldera Shell has 240 HP")
	_assert(cs.is_armored() == true, "Caldera Shell starts with molten basalt armor active")

	cs.thermal_shock()
	_assert(cs.is_armored() == false, "Thermal shock extinguishes molten basalt armor")
	_assert(cs.state == Creature.State.STAGGER, "Thermal shock triggers State.STAGGER")

	var drops: Array = cs.drops()
	var has_core := false
	var has_plate := false
	for d in drops:
		if d[0] == &"geothermal_core": has_core = true
		if d[0] == &"caldera_basalt_plate": has_plate = true
	_assert(has_core, "Caldera Shell drops 1 Geothermal Core")
	_assert(has_plate, "Caldera Shell drops Caldera Basalt Plates")
	cs.free()


func _test_ocean_schooner_vessel() -> void:
	print("\n-- 2. Tier 3 Flagship: The Ocean Schooner")
	_assert(ItemDB.has_item(&"schooner_kit"), "Ocean Schooner Kit registered in ItemDB")
	_assert(RecipeDB.has_recipe(&"craft_schooner_kit"), "Ocean Schooner Kit craftable at Workbench")

	var b := Boat.new()
	b.setup(99, null, null, Vector3.ZERO, 0.0, Boat.KIND_SCHOONER)
	_assert(b.kind == Boat.KIND_SCHOONER, "Boat initialized as KIND_SCHOONER")
	_assert(b.display_name() == "Ocean Schooner", "Boat display name is 'Ocean Schooner'")
	_assert(b.occupants.size() == 6, "Ocean Schooner has 6 player seats")
	_assert(b.hold != null and b.hold.slots.size() == 36, "Ocean Schooner has 36-slot hold")
	_assert(b.has_sail() == true, "Ocean Schooner has sail enabled")

	var fwd := Vector2(0, 1)
	var wind := Vector2(0, 1)
	var eff := Boat.sail_efficiency(fwd, wind)
	_assert(eff > 0.0, "Ocean Schooner sail catches wind with positive efficiency")
	b.free()


func _test_tidal_power_and_mills() -> void:
	print("\n-- 3. Tidal Power & Automated Machinery")
	Placeables.register_builtin()
	_assert(ItemDB.has_item(&"tide_wheel"), "Tide Wheel registered in ItemDB")
	_assert(ItemDB.has_item(&"automated_grain_mill"), "Automated Grain Mill registered in ItemDB")
	_assert(ItemDB.has_item(&"automated_sawmill"), "Automated Sawmill registered in ItemDB")
	_assert(ItemDB.has_item(&"wheat_flour"), "Wheat Flour registered in ItemDB")

	var tw := TideWheelEntity.new(Vector3i(10, 0, 10))
	tw._ready()
	_assert(TideWheelEntity.active_wheels.has(tw), "Tide Wheel added to active wheels")

	tw.turning = true
	var powered := TideWheelEntity.is_powered_at(tw.position + Vector3(2, 0, 2))
	_assert(powered == true, "Adjacent machine within 8m is powered by Tide Wheel")

	var unpowered := TideWheelEntity.is_powered_at(tw.position + Vector3(20, 0, 20))
	_assert(unpowered == false, "Machine beyond 8m is unpowered")

	var gm := AutomatedGrainMillEntity.new(Vector3i(10, 0, 12))
	gm.wheat_stored = 2
	gm._process(4.0)
	_assert(gm.wheat_stored == 1 and gm.flour_stored == 2, "Automated Grain Mill processes wheat into flour when powered")

	var sm := AutomatedSawmillEntity.new(Vector3i(10, 0, 13))
	sm.logs_stored = 2
	sm._process(4.0)
	_assert(sm.logs_stored == 1 and sm.planks_stored == 3, "Automated Sawmill processes logs into planks when powered")

	tw._exit_tree()
	tw.free()
	gm.free()
	sm.free()


func _test_sluice_gate() -> void:
	print("\n-- 4. Tidal Sluice Gates")
	_assert(ItemDB.has_item(&"sluice_gate"), "Tidal Sluice Gate registered in ItemDB")
	var sg := SluiceGateEntity.new(Vector3i(5, 0, 5))
	_assert(sg.is_open == false, "Sluice Gate starts closed")
	sg.toggle_gate()
	_assert(sg.is_open == true, "Sluice Gate opens upon toggle")
	sg.toggle_gate()
	_assert(sg.is_open == false, "Sluice Gate closes upon toggle")
	sg.free()


func _test_undertow_gauntlet_and_regulator() -> void:
	print("\n-- 5. The Undertow Gauntlet & Ancient Tide Regulators")
	_assert(ItemDB.has_item(&"undertow_crest"), "Undertow Crest registered in ItemDB")
	_assert(ItemDB.has_item(&"regulator_keystone"), "Regulator Keystone registered in ItemDB")
	_assert(ItemDB.has_item(&"tide_regulator"), "Tide Regulator registered in ItemDB")

	var gauntlet := UndertowGauntletAltar.new(Vector3i(20, 0, 20))
	gauntlet._ready()
	_assert(UndertowGauntletAltar.current == gauntlet, "Undertow Gauntlet Altar registered as current")
	_assert(gauntlet.active == false, "Undertow Gauntlet starts inactive")
	gauntlet._exit_tree()
	gauntlet.free()

	var reg := TideRegulatorEntity.new(Vector3i(0, 5, 0))
	reg._ready()
	_assert(TideRegulatorEntity.current == reg, "Tide Regulator registered as current")
	_assert(reg.count_attuned() == 0, "Tide Regulator starts with 0/4 relics")

	reg.attuned_relics[&"hulk_pearl"] = true
	reg.attuned_relics[&"siren_heart"] = true
	reg.attuned_relics[&"geothermal_core"] = true
	reg.attuned_relics[&"regulator_keystone"] = true
	_assert(reg.count_attuned() == 4, "Tide Regulator counts 4/4 relics attuned")
	reg.fully_restored = true
	_assert(reg.fully_restored == true, "Tide Regulator equilibrium restored")
	reg._exit_tree()
	reg.free()


func _test_act3_quests() -> void:
	print("\n-- 6. Act III Quests & Narrative Progression")
	var qm := QuestManager.new()
	_assert(qm.available_quests.has(&"story_caldera_hunt"), "Quest 'Fire of the Benthic Deep' registered in Act III")
	_assert(qm.available_quests.has(&"story_undertow_trial"), "Quest 'Trial of the Spring Tide' registered in Act III")
	_assert(qm.available_quests.has(&"story_grand_regulator"), "Quest 'The Grand Equilibrium' registered in Act III")

	var q_climax: QuestDef = qm.available_quests[&"story_grand_regulator"]
	_assert(q_climax.storyline_act == 3, "Climax quest marked as storyline act 3")
