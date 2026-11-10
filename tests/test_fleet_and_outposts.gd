class_name TestFleetAndOutposts
extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	print("\n==================================================")
	print("Running Fleet, Slipway Dry-Dock & Outposts Test Suite")
	print("==================================================\n")

	_test_boat_hull_damage_and_leaks()
	_test_at_sea_repairs()
	_test_boat_slipway_drydock_restoration()
	_test_gilded_wheel_and_sea_hawk_fixtures()
	_test_barnacled_hulk_harpoon_finisher()
	_test_reaver_outpost_dock_capture()

	print("\n==================================================")
	print("Fleet & Outposts Suite: %d / %d tests passed!" % [_passed, _passed + _failed])
	print("==================================================\n")

	if _failed > 0:
		print("FAILED with %d errors" % _failed)
	quit(_failed)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("  [PASS] %s" % message)
		_passed += 1
	else:
		print("  [FAIL] %s" % message)
		_failed += 1


func _test_boat_hull_damage_and_leaks() -> void:
	print("-- 1. Vessel Hull Durability, Damage & Leaks")
	var boat := Boat.new()
	boat.setup(1, null, null, Vector3.ZERO, 0.0, Boat.KIND_ROWBOAT)

	_assert(boat.max_hull_hp == 100.0, "Rowboat has 100.0 max hull HP")
	_assert(boat.hull_hp == 100.0, "Hull starts at 100% integrity")
	_assert(not boat.is_leaking(), "Hull is initially watertight (no leaks)")

	var skiff := Boat.new()
	skiff.setup(2, null, null, Vector3.ZERO, 0.0, Boat.KIND_SKIFF)
	_assert(skiff.max_hull_hp == 150.0, "Skiff has 150.0 max hull HP")

	var schooner := Boat.new()
	schooner.setup(3, null, null, Vector3.ZERO, 0.0, Boat.KIND_SCHOONER)
	_assert(schooner.max_hull_hp == 350.0, "Schooner has 350.0 max hull HP")
	_assert(schooner.reinforced_hull == true, "Schooner has reinforced hull")

	# Inflict light damage (does not breach threshold)
	boat.take_hull_damage(30.0)
	_assert(boat.hull_hp == 70.0, "Hull took 30 damage (70 HP remaining)")
	_assert(not boat.is_leaking(), "Light damage does not spring a leak (> 50% HP)")

	# Inflict heavy damage (< 50% HP threshold)
	boat.take_hull_damage(35.0)
	_assert(boat.hull_hp == 35.0, "Hull at 35 HP (< 50% max)")
	_assert(boat.is_leaking(), "Severe hull fracture sprang a leak!")
	_assert(boat.leak_amount > 0.0, "Leak amount is positive (%.2f)" % boat.leak_amount)

	boat.free()
	skiff.free()
	schooner.free()


func _test_at_sea_repairs() -> void:
	print("\n-- 2. At-Sea Emergency Hull Repairs")
	var boat := Boat.new()
	boat.setup(1, null, null, Vector3.ZERO, 0.0, Boat.KIND_SKIFF)
	boat.take_hull_damage(100.0) # Hull down to 50 HP (33%), leaking

	_assert(boat.is_leaking(), "Boat is leaking before repair")

	var p := Player.new()
	p.hud = MockHud.new()
	p._ready()

	# Attempt repair without materials
	var repaired_no_wood := boat.repair_at_sea(p)
	_assert(not repaired_no_wood, "Repair fails if player lacks timber/planks")

	# Add wood plank to player
	p.inventory.add_item(&"wood_plank", 2)
	var leak_before := boat.leak_amount
	var hp_before := boat.hull_hp

	var repaired := boat.repair_at_sea(p)
	_assert(repaired, "Field repair succeeds with wood plank")
	_assert(boat.hull_hp > hp_before, "Hull HP restored by emergency patching (%.1f -> %.1f)" % [hp_before, boat.hull_hp])
	_assert(boat.leak_amount < leak_before, "Leak rate reduced by field repair")
	_assert(p.inventory.get_item_count(&"wood_plank") == 1, "Consumed 1 wood plank")

	boat.free()
	p.free()


func _test_boat_slipway_drydock_restoration() -> void:
	print("\n-- 3. Harbor Slipway Dry-Dock Complete Overhaul")
	var slipway := BoatSlipwayEntity.new(Vector3i(10, 2, 10))
	root.add_child(slipway)

	var boat := Boat.new()
	root.add_child(boat)
	boat.setup(1, null, null, slipway.position + Vector3(0, 0, 1.5), 0.0, Boat.KIND_ROWBOAT)
	boat.add_to_group("boats")

	# Damage boat heavily
	boat.take_hull_damage(80.0)
	_assert(boat.hull_hp == 20.0, "Boat heavily damaged before haul-out")
	_assert(boat.is_leaking(), "Boat leaking before dry-dock")

	var p := Player.new()
	p.hud = MockHud.new()
	p._ready()

	# Interacting with slipway dry-docks boat
	slipway.interact(p)

	_assert(boat.hull_hp == boat.max_hull_hp, "Slipway restored hull to 100%% (%.1f / %.1f)" % [boat.hull_hp, boat.max_hull_hp])
	_assert(not boat.is_leaking(), "Dry-dock caulking completely sealed all leaks")
	_assert(boat.reinforced_hull == true, "Dry-dock overhaul applied reinforced hull protection")

	slipway.queue_free()
	boat.queue_free()
	p.free()


func _test_gilded_wheel_and_sea_hawk_fixtures() -> void:
	print("\n-- 4. Gilded Ship Wheel & Trained Sea-Hawk Deck Fixtures")
	var skiff := Boat.new()
	skiff.setup(1, null, null, Vector3.ZERO, 0.0, Boat.KIND_SKIFF)

	_assert(not skiff.has_gilded_wheel, "Boat initially lacks gilded wheel")
	_assert(not skiff.has_sea_hawk, "Boat initially lacks sea hawk")

	# Verify deck slot permissions
	_assert(skiff.can_install_fixture(0, &"gilded_ship_wheel"), "Bow stem allows gilded wheel fixture")
	_assert(skiff.can_install_fixture(0, &"sea_hawk_perch"), "Bow stem allows sea hawk perch fixture")

	# Install gilded wheel
	skiff.install_fixture(0, &"gilded_ship_wheel")
	_assert(skiff.has_gilded_wheel, "has_gilded_wheel is true after installation")
	_assert(skiff.deck_fixtures.has(0), "Fixture stored in deck_fixtures dictionary")

	# Remove fixture
	skiff.remove_fixture(0)
	_assert(not skiff.has_gilded_wheel, "has_gilded_wheel is false after removal")

	# Install Sea-Hawk perch
	skiff.install_fixture(0, &"sea_hawk_perch")
	_assert(skiff.has_sea_hawk, "has_sea_hawk is true after installation")
	var report := skiff.scout_surroundings()
	_assert(report.length() > 0, "Trained Sea-Hawk scouts surrounding ocean")

	skiff.free()


func _test_barnacled_hulk_harpoon_finisher() -> void:
	print("\n-- 5. Barnacled Hulk Eye-Stalk Harpoon Finisher")
	var hulk := BarnacledHulk.new()
	hulk.hp = 650.0

	var normal_hit_dmg := 30.0
	var normal_dealt := hulk.effective_damage(normal_hit_dmg)
	_assert(normal_dealt < 10.0, "Galleon shell turns normal attack (only %.1f dmg penetrates)" % normal_dealt)

	# Execute Eye-Stalk Harpoon Strike
	var hp_before := hulk.hp
	var finisher_ok := hulk.eye_stalk_harpoon_strike(30.0, Vector3.FORWARD, 1)
	_assert(finisher_ok, "Eye-stalk harpoon strike succeeded")
	var actual_dmg_taken := hp_before - hulk.hp
	_assert(actual_dmg_taken >= 66.0, "Eye-stalk harpoon dealt 2.2x unmitigated weakpoint damage (%.1f dmg taken)" % actual_dmg_taken)

	hulk.free()


func _test_reaver_outpost_dock_capture() -> void:
	print("\n-- 6. Sea-Reaver Outpost Dock Capture")
	var dock := ReaverDockEntity.new(Vector3i(20, 2, 20))
	_assert(not dock.is_claimed, "Reaver dock is hostile/unclaimed initially")
	_assert(dock.interact_prompt().contains("Claim"), "Prompt offers claiming pirate dock")

	var p := Player.new()
	p.hud = MockHud.new()
	p._ready()

	# Capture dock
	dock.interact(p)
	_assert(dock.is_claimed, "Dock is marked claimed after interaction")
	_assert(p.inventory.get_item_count(&"skiff_kit") == 1, "Player awarded 1 seaworthy Skiff Kit")
	_assert(p.inventory.get_item_count(&"brass_guilder") == 15, "Player looted 15 Brass Guilders from outpost")

	dock.free()
	p.free()


class MockHud extends Hud:
	var last_toast := ""
	var last_banner_title := ""

	func _init() -> void:
		pass

	func show_toast(msg: String, _duration: float = 3.0, _immediate: bool = false) -> void:
		last_toast = msg

	func show_banner(title: String, _sub: String = "", _dur: float = 4.0) -> void:
		last_banner_title = title
