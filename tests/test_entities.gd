extends SceneTree
## Entity layer: registry, placement/removal/cost, crab pot + salt pan cycles, containers,
## collision and save/load round trip.
##   godot --headless --path . -s tests/test_entities.gd

var passed := 0
var total := 0


func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)


class TestThing:
	extends WorldEntity
	func _init(c: Vector3i = Vector3i.ZERO) -> void:
		super._init(&"test_thing", "Test Thing", c)
		size = Vector3(0.5, 0.5, 0.5)


func _initialize() -> void:
	ItemDB.init_db()
	var m := EntityManager.new()
	root.add_child(m)

	# --- registry
	EntityManager.register_type(&"test_lambda", func(c: Vector3i) -> WorldEntity: return WorldEntity.new(&"test_lambda", "Lambda", c), {"item": &""})
	EntityManager.register_type(&"test_thing", TestThing, {"rule": &"ground", "aliases": [&"thing"]})
	check(m.spawn_entity(&"test_lambda", Vector3i(0, 40, 0)) != null, "register_type with a Callable factory")
	var t := m.spawn_entity(&"thing", Vector3i(4, 40, 0))
	check(t is TestThing and t.entity_id == &"test_thing", "register_type with a Script + alias resolves")
	check(EntityManager.resolve_type(&"chest") == &"driftwood_chest", "built-in alias chest -> driftwood_chest")
	check(EntityManager.type_for_item(&"crab_pot") == &"crab_pot", "crab pot item maps to its entity type")
	check(EntityManager.type_for_item(&"stone") == &"", "ordinary items aren't placeable")
	check(ItemDB.has_item(&"sea_barrel") and RecipeDB.has_recipe(&"place_sea_barrel"), "placeables get items + workbench recipes")
	for type: StringName in [&"workbench", &"campfire", &"fisher_bed", &"barber_mirror", &"storage_crate"]:
		check(EntityManager.get_type_def(type).has("factory"), "built-in type registered: %s" % type)

	# --- place / remove / cost
	var cost := Placeables.build_cost(&"crab_pot")
	var inv := Inventory.new()
	check(not BuildCosts.can_afford(inv, cost), "empty inventory can't afford a crab pot")
	inv.add_item(&"driftwood", 3)
	inv.add_item(&"kelp_frond", 4)
	check(BuildCosts.can_afford(inv, cost), "3 driftwood + 4 kelp pays for a crab pot")
	check(m.request_place(&"crab_pot", Vector3i(20, 25, 20), 0), "authority places a crab pot")
	check(not m.request_place(&"crab_pot", Vector3i(20, 25, 20), 0), "can't place on top of another entity")
	check(m.overlaps_any(&"driftwood_chest", Vector3i(21, 25, 20), 0), "overlap test catches neighbouring footprint")
	var pot: CrabPotEntity = m.get_entity_at(Vector3i(20, 25, 20))
	check(pot != null and pot.item_id == &"crab_pot", "placed pot returns its item on pickup")

	# --- crab pot cycle (server side)
	var r: Dictionary = pot.server_action(&"bait", {"item": &"kelp_frond", "n": 3}, 1)
	check(r.get("changed", false) and pot.pot.bait_count == 3, "baiting adds 3 bait")
	r = pot.server_action(&"bait", {"item": &"stone", "n": 1}, 1)
	check(r.is_empty(), "stone isn't bait")
	var low := {"tide_vox": 23.0, "daylight": true}
	var high := {"tide_vox": 37.0, "daylight": true}
	for i in 200:
		pot.server_tick(1.0, low)
	check(pot._catch_count() == 0, "no catch while the tide is out")
	var rolls := 0
	while pot._catch_count() == 0 and rolls < 20:
		for i in int(CrabPotEntity.SOAK_ROLL_SEC):
			pot.server_tick(1.0, high)
		rolls += 1
	check(pot._catch_count() > 0, "high tide soak traps shellfish (%d rolls)" % rolls)
	var caught := pot._catch_count()
	r = pot.server_action(&"collect", {}, 1)
	var granted := 0
	for g: Array in r.get("grant", []):
		granted += int(g[1])
	check(granted == caught and pot._catch_count() == 0, "collect grants the whole catch and empties the pot")
	check(pot.server_action(&"collect", {}, 1).is_empty(), "collecting an empty pot grants nothing")

	# --- salt pan
	m.spawn_entity(&"salt_pan", Vector3i(30, 26, 30))
	var pan: SaltPanEntity = m.get_entity_at(Vector3i(30, 26, 30))
	pan.server_tick(1.0, high)
	check(pan.pan.brine_level == 1.0, "high tide fills the salt pan")
	for i in 60:
		pan.server_tick(1.0, low)
	check(pan.pan.accumulated_salt > 0, "sun at low tide crystallises salt")
	r = pan.server_action(&"harvest", {}, 1)
	check(r.get("grant", [[0, 0]])[0][0] == &"sea_salt" and pan.pan.accumulated_salt == 0, "salt harvest grants sea salt")

	# --- containers
	m.spawn_entity(&"sea_barrel", Vector3i(40, 40, 40))
	var barrel: ChestEntity = m.get_entity_at(Vector3i(40, 40, 40))
	r = barrel.server_action(&"deposit", {"item": &"silver_mackerel", "n": 4}, 1)
	check(r.get("changed", false) and barrel._stored_count() == 4, "sea barrel stores fish")
	r = barrel.server_action(&"deposit", {"item": &"stone", "n": 5}, 1)
	check(r.get("grant", [])[0][1] == 5 and barrel._stored_count() == 4, "sea barrel refuses stone and returns it")
	r = barrel.server_action(&"take", {}, 1)
	check(r.get("grant", [])[0] == [&"silver_mackerel", 4] and barrel._stored_count() == 0, "take withdraws up to 5")
	m.spawn_entity(&"driftwood_chest", Vector3i(50, 40, 50))
	var chest: ChestEntity = m.get_entity_at(Vector3i(50, 40, 50))
	chest.server_action(&"deposit", {"item": &"stone", "n": 12}, 1)
	var pick := chest.pickup_items()
	check(pick.size() == 2 and pick[0] == [&"driftwood_chest", 1] and pick[1] == [&"stone", 12], "picking up a chest returns it + contents")

	# --- collision
	var box := chest.get_aabb()
	check(m.blocks(box.get_center() - Vector3.ONE * 0.05, box.get_center() + Vector3.ONE * 0.05), "player box inside a chest is blocked")
	check(not m.blocks(box.end + Vector3(1, 0, 1), box.end + Vector3(1.5, 1, 1.5)), "space beside a chest is free")
	check(m.point_solid(pot.get_aabb().get_center()), "crab pot is solid")

	# --- save / load round trip
	pot.server_action(&"bait", {"item": &"kelp_frond", "n": 2}, 1)
	var saved := m.save_state()
	var m2 := EntityManager.new()
	root.add_child(m2)
	m2.load_state(saved)
	check(m2.get_count() == m.get_count(), "round trip keeps every entity (%d)" % m.get_count())
	var pot2: CrabPotEntity = m2.get_entity_at(Vector3i(20, 25, 20))
	check(pot2 != null and pot2.pot.bait_count == pot.pot.bait_count, "crab pot bait survives save/load")
	var chest2: ChestEntity = m2.get_entity_at(Vector3i(50, 40, 50))
	check(chest2 != null and chest2._stored_count() == 12, "chest contents survive save/load")
	var barrel2: ChestEntity = m2.get_entity_at(Vector3i(40, 40, 40))
	check(barrel2 != null and barrel2.style == &"barrel" and not barrel2.container.can_accept_item(&"stone"), "sea barrel keeps its seafood filter after load")
	check(m2.save_state().get("starter_done") == saved.get("starter_done"), "starter flag round-trips")

	# --- remove
	m.request_remove(Vector3i(20, 25, 20))
	check(not m.has_entity_at(Vector3i(20, 25, 20)), "pickup removes the entity")

	print("Summary: %d / %d tests passed!" % [passed, total])
	# The test types' factories point into this script; drop them (and the managers)
	# before the engine tears the script down, or shutdown crashes.
	EntityManager.unregister_type(&"test_lambda")
	EntityManager.unregister_type(&"test_thing")
	m.free()
	m2.free()
	EntityManager.current = null
	quit(0 if passed == total else 1)
