extends SceneTree

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\n=== STARTING MODULAR DECK OUTFITTING & SOUNDSCAPE TEST SUITE ===")
	run_tests()
	print("\n=== TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [_passed, _failed])
	if _failed > 0:
		print("FAILED with %d errors" % _failed)
	else:
		print("ALL DECK OUTFITTING & SOUNDSCAPE TESTS PASSED!")
	quit(0 if _failed == 0 else 1)


func assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)


func run_tests() -> void:
	test_boat_deck_slots()
	test_fixture_installation_and_visuals()
	test_cargo_crate_storage()
	test_fixture_interactions()
	test_fixture_serialization()
	test_ambient_maritime_soundscape()


# -----------------------------------------------------------------------------
# 1. BOAT DECK SLOTS
# -----------------------------------------------------------------------------
func test_boat_deck_slots() -> void:
	print("\n--- 1. Boat Deck Slots ---")
	ItemDB.init_db()
	RecipeDB.init_db()

	var sloop := Boat.new()
	sloop.setup(1, null, null, Vector3.ZERO, 0.0, Boat.KIND_SLOOP)
	var sloop_slots: Array[Dictionary] = sloop.get_deck_slots()
	assert_true(sloop_slots.size() >= 3, "Coastal Sloop has at least 3 deck fixture slots (found %d)" % sloop_slots.size())

	var schooner := Boat.new()
	schooner.setup(2, null, null, Vector3.ZERO, 0.0, Boat.KIND_SCHOONER)
	var schooner_slots: Array[Dictionary] = schooner.get_deck_slots()
	assert_true(schooner_slots.size() >= 5, "Ocean Schooner has at least 5 deck fixture slots (found %d)" % schooner_slots.size())

	var barge := Boat.new()
	barge.setup(3, null, null, Vector3.ZERO, 0.0, Boat.KIND_BARGE)
	var barge_slots: Array[Dictionary] = barge.get_deck_slots()
	assert_true(barge_slots.size() >= 3, "Tide-Barge has at least 3 deck fixture slots (found %d)" % barge_slots.size())

	sloop.free()
	schooner.free()
	barge.free()


# -----------------------------------------------------------------------------
# 2. FIXTURE INSTALLATION & TRANSFORMS
# -----------------------------------------------------------------------------
func test_fixture_installation_and_visuals() -> void:
	print("\n--- 2. Fixture Installation & Visuals ---")
	var boat := Boat.new()
	boat.setup(10, null, null, Vector3(0, 0, 0), 0.0, Boat.KIND_SCHOONER)

	# Bow pulpit lantern
	assert_true(boat.can_install_fixture(0, &"deck_lantern"), "Slot 0 can install deck_lantern")
	var ok_lantern: bool = boat.install_fixture(0, &"deck_lantern")
	assert_true(ok_lantern, "Installed deck_lantern at slot 0")
	assert_true(boat.deck_fixtures.has(0), "deck_fixtures tracks slot 0")

	# Check node is child of visual
	var lantern_rec: Dictionary = boat.deck_fixtures[0]
	var lantern_node: Node3D = lantern_rec["node"]
	assert_true(lantern_node.get_parent() == boat.visual, "Fixture node is child of boat visual (follows roll/pitch/yaw)")

	# Foredeck cargo crate
	assert_true(boat.can_install_fixture(1, &"cargo_crate"), "Slot 1 can install cargo_crate")
	var ok_crate: bool = boat.install_fixture(1, &"cargo_crate")
	assert_true(ok_crate, "Installed cargo_crate at slot 1")

	# Midship navigation table
	assert_true(boat.can_install_fixture(3, &"navigation_table"), "Slot 3 can install navigation_table")
	var ok_nav: bool = boat.install_fixture(3, &"navigation_table")
	assert_true(ok_nav, "Installed navigation_table at slot 3")

	# Quarterdeck sea cot
	assert_true(boat.can_install_fixture(4, &"sea_cot"), "Slot 4 can install sea_cot")
	var ok_cot: bool = boat.install_fixture(4, &"sea_cot")
	assert_true(ok_cot, "Installed sea_cot at slot 4")

	# Slot occupied check
	assert_true(not boat.can_install_fixture(0, &"deck_lantern"), "Cannot install on already occupied slot")

	boat.free()


# -----------------------------------------------------------------------------
# 3. CARGO CRATE STORAGE
# -----------------------------------------------------------------------------
func test_cargo_crate_storage() -> void:
	print("\n--- 3. Cargo Crate Storage ---")
	var boat := Boat.new()
	boat.setup(11, null, null, Vector3.ZERO, 0.0, Boat.KIND_SLOOP)

	boat.install_fixture(1, &"cargo_crate")
	var crate_rec: Dictionary = boat.deck_fixtures[1]
	var crate_inv: Inventory = crate_rec.get("hold")
	assert_true(crate_inv != null, "Cargo crate provides an onboard Inventory hold")
	assert_true(crate_inv.slots.size() == 9, "Cargo crate provides 9 storage slots")

	# Add cargo to ship crate
	var rem: int = crate_inv.add_item(&"sea_salt", 10)
	assert_true(rem == 0, "Added sea_salt into deck cargo crate")
	assert_true(crate_inv.has_item(&"sea_salt"), "Deck crate holds sea_salt")
	assert_true(crate_inv.count_item(&"sea_salt") == 10, "Cargo crate count is exactly 10")

	boat.free()


# -----------------------------------------------------------------------------
# 4. FIXTURE INTERACTIONS
# -----------------------------------------------------------------------------
func test_fixture_interactions() -> void:
	print("\n--- 4. Fixture Interactions ---")
	var boat := Boat.new()
	boat.setup(12, null, null, Vector3.ZERO, 0.0, Boat.KIND_SLOOP)

	boat.install_fixture(0, &"harpoon_swivel")
	boat.install_fixture(2, &"sea_cot")

	var player := CharacterBody3D.new()
	player.set_script(load("res://scripts/player.gd"))
	player.vitality.current_hp = 10.0
	player.vitality.current_stamina = 5.0

	# Resting in cot
	boat.interact_fixture(2, player)
	assert_true(player.vitality.current_hp >= player.vitality.get_max_hp(), "Resting in sea_cot restores HP to full")
	assert_true(player.vitality.current_stamina >= player.vitality.get_max_stamina(), "Resting in sea_cot restores Stamina to full")

	# Swivel harpoon interaction
	boat.interact_fixture(0, player)
	assert_true(boat.deck_fixtures.has(0), "Swivel harpoon interaction processed cleanly")

	player.free()
	boat.free()


# -----------------------------------------------------------------------------
# 5. FIXTURE SERIALIZATION & RESTORATION
# -----------------------------------------------------------------------------
func test_fixture_serialization() -> void:
	print("\n--- 5. Fixture Serialization & Restoration ---")
	var boat1 := Boat.new()
	boat1.setup(14, null, null, Vector3(10, 0, 10), 1.2, Boat.KIND_SCHOONER)

	boat1.install_fixture(0, &"deck_lantern")
	boat1.install_fixture(1, &"cargo_crate")
	var crate_inv: Inventory = boat1.deck_fixtures[1]["hold"]
	crate_inv.add_item(&"ancient_weapon_fragment", 2)
	boat1.install_fixture(4, &"sea_cot")

	var saved_fixtures: Array = boat1.serialize_fixtures()
	assert_true(saved_fixtures.size() == 3, "Serialized 3 deck fixtures")

	var boat2 := Boat.new()
	boat2.setup(15, null, null, Vector3(20, 0, 20), 0.5, Boat.KIND_SCHOONER)
	boat2.deserialize_fixtures(saved_fixtures)

	assert_true(boat2.deck_fixtures.size() == 3, "Deserialized 3 deck fixtures on boat2")
	assert_true(boat2.deck_fixtures.has(0) and boat2.deck_fixtures[0]["id"] == &"deck_lantern", "Restored deck_lantern at slot 0")
	assert_true(boat2.deck_fixtures.has(1) and boat2.deck_fixtures[1]["id"] == &"cargo_crate", "Restored cargo_crate at slot 1")
	var restored_inv: Inventory = boat2.deck_fixtures[1]["hold"]
	assert_true(restored_inv.count_item(&"ancient_weapon_fragment") == 2, "Cargo crate inventory restored with contents intact")
	assert_true(boat2.deck_fixtures.has(4) and boat2.deck_fixtures[4]["id"] == &"sea_cot", "Restored sea_cot at slot 4")

	# Removal test
	var removed_id := boat2.remove_fixture(0)
	assert_true(removed_id == &"deck_lantern", "Removed fixture returns id")
	assert_true(not boat2.deck_fixtures.has(0), "Slot 0 is now freed")

	boat1.free()
	boat2.free()


# -----------------------------------------------------------------------------
# 6. AMBIENT MARITIME SOUNDSCAPE
# -----------------------------------------------------------------------------
func test_ambient_maritime_soundscape() -> void:
	print("\n--- 6. Ambient Maritime Soundscape ---")
	var st := {"rng": RandomNumberGenerator.new(), "a": 0.0, "b": 0.0, "c": 0.0}
	st.rng.seed = 999

	# Test procedural generators
	var shanty_sample: float = AmbientAudio._gen_shanty_whistle(100, 8 * AmbientAudio.RATE, st)
	assert_true(absf(shanty_sample) <= 1.0, "Procedural shanty_whistle sample is within valid amplitude range (-1.0 to 1.0)")

	var harbor_sample: float = AmbientAudio._gen_harbor_drone(100, 6 * AmbientAudio.RATE, st)
	assert_true(absf(harbor_sample) <= 1.0, "Procedural harbor_drone sample is within valid amplitude range (-1.0 to 1.0)")

	# AudioStream baking test
	var whistle_stream: AudioStream = AmbientAudio._load_or_bake("shanty_whistle", 1.0, AmbientAudio._gen_shanty_whistle)
	assert_true(whistle_stream != null, "Baked shanty_whistle AudioStream")

	var drone_stream: AudioStream = AmbientAudio._load_or_bake("harbor_drone", 1.0, AmbientAudio._gen_harbor_drone)
	assert_true(drone_stream != null, "Baked harbor_drone AudioStream")
