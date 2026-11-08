extends SceneTree
## Sea eagles, shore rats and their answers (guard dogs, dock cats, scarecrows, roofs,
## sealed barrels), otter friends that persist, and livestock co-op mirroring.
##   godot --headless --path . -s tests/test_farm_guardians.gd

var passed := 0
var total := 0
const VS := VoxelWorld.VS
const FLOOR := 20


class FakeNet:
	extends Node
	var main: Node
	var creatures := {}
	var wildlife: WildlifeDirector
	var difficulty := CombatMath.Difficulty.TIDEWATCH
	var roofs := {}                 # Vector2i(x, z) -> voxel y of a roof slab
	var despawned := []
	var alerts := []
	var lights := []
	var _next := 1

	func voxel(x: int, y: int, z: int) -> int:
		if y <= FLOOR:
			return Palette.SAND
		if roofs.has(Vector2i(x, z)) and y == int(roofs[Vector2i(x, z)]):
			return Palette.PLANK
		return 0

	func is_authority() -> bool:
		return true

	func local_id() -> int:
		return 1

	func despawn(c: Creature) -> void:
		despawned.append(c)
		creatures.erase(c.cid)

	func spawn(kind: StringName, pos: Vector3, _cid := -1) -> Creature:
		var c: Creature
		match kind:
			&"fox": c = RedFox.new()
			&"stoat": c = Stoat.new()
			&"rat": c = ShoreRat.new()
			&"eagle": c = SeaEagle.new()
			&"otter": c = SeaOtter.new()
			_: return null
		c.setup(_next, self, pos, true)
		creatures[_next] = c
		_next += 1
		return c

	func _count(kind: StringName, near: Vector3, r: float) -> int:
		var n := 0
		for c: Creature in creatures.values():
			if c.kind == kind and (r <= 0.0 or c.position.distance_to(near) < r):
				n += 1
		return n

	func _context() -> Dictionary:
		return {"lights": lights}

	func _ensure_column(_x: int, _z: int) -> void:
		pass

	func wild_alert(text: String) -> void:
		alerts.append(text)

	func broadcast_dens(_list: Array) -> void:
		pass


class FakeMain:
	extends Node
	var sky := SkyCycle.new()
	var livestock_mgr: Node
	var world = null


func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)


func player(pos: Vector3) -> Dictionary:
	return {"id": 7, "pos": pos, "speed": 0.0, "sneaking": false, "sprinting": false, "in_water": false,
		"has_bait": false, "has_light": false, "holding_fish": false}


func ctx(players: Array, opts := {}) -> Dictionary:
	var c := {"players": players, "lights": [], "water_y": (FLOOR - 2) * VS, "night": 0.0, "darkness": 0.0,
		"difficulty": CombatMath.Difficulty.TIDEWATCH}
	c.merge(opts, true)
	return c


func run(c: Creature, cx: Dictionary, seconds: float, net: FakeNet) -> void:
	var t := 0.0
	while t < seconds:
		if not net.creatures.has(c.cid):
			return
		c.simulate(0.05, cx)
		t += 0.05


func make_net() -> FakeNet:
	var net := FakeNet.new()
	var m := FakeMain.new()
	m.livestock_mgr = LivestockManager.new()
	net.main = m
	net.wildlife = WildlifeDirector.new(net)
	return net


func duck(net: FakeNet, pos: Vector3) -> Node3D:
	var a: Node3D = net.main.livestock_mgr.spawn_animal(&"shore_duck", pos, "Pip")
	a.yield_timer = 100.0
	return a


func raider(net: FakeNet, kind: StringName, pos: Vector3) -> Raider:
	var r: Raider = net.spawn(kind, pos)
	r.den = pos + Vector3(-30, 0, 0)
	return r


func eagle_at(net: FakeNet, d: Node3D) -> SeaEagle:
	var e := net.spawn(&"eagle", d.position + Vector3(20, 14, 0)) as SeaEagle
	e.den = d.position + Vector3(-120, 30, 0)
	e.raid_site = d.position
	e.target_animal_id = d.animal_id
	return e


func vox(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / VS), FLOOR + 1, floori(p.z / VS))


func _init() -> void:
	VoxelWorld.push_palette()
	ItemDB.init_db()
	Placeables.register_builtin()
	var ground := (FLOOR + 1) * VS
	var night := {"night": 1.0, "darkness": 1.0}

	print("-- new placeables")
	for id: StringName in [&"dog_kennel", &"cat_basket", &"scarecrow", &"pantry_barrel"]:
		check(ItemDB.has_item(id) and RecipeDB.has_recipe(StringName("place_" + String(id))) \
				and EntityManager.get_type_def(id).has("factory"), "%s is an item, a workbench recipe and an entity" % id)

	print("-- guard dog")
	var net := make_net()
	var em := EntityManager.new()
	EntityManager.current = em
	var site := Vector3(20, ground, 20)
	var kennel: GuardAnimalEntity = em.spawn_entity(&"dog_kennel", vox(site + Vector3(3, 0, 0)), 0)
	check(kennel != null and kennel.is_dog(), "kennel places")
	var d := duck(net, site)
	var fox := raider(net, &"fox", site + Vector3(10, 0, 0))
	fox.raid_site = site
	fox.target_animal_id = d.animal_id
	run(fox, ctx([], night), 0.5, net)
	check(fox.state == Creature.State.FLEE, "a fox inside the dog's range bolts")
	check(kennel.is_chasing(), "the dog dashes out at it")
	check(net.alerts.any(func(t: String) -> bool: return t.contains("barks")), "everyone hears the bark")
	check(net.wildlife.is_defended(site), "the farm is remembered as defended")
	var far_fox := raider(net, &"fox", site + Vector3(60, 0, 0))
	far_fox.raid_site = site + Vector3(60, 0, 0)
	far_fox.target_animal_id = d.animal_id
	run(far_fox, ctx([], night), 0.2, net)
	check(far_fox.state != Creature.State.FLEE, "a fox well outside the dog's range carries on")
	var saved := kennel.serialize()
	check(saved.get("pet") == "Skipper" and saved.get("x") == kennel.grid_coord.x, "kennel saves its dog's name and place")

	print("-- dock cat")
	net = make_net()
	em = EntityManager.new()
	EntityManager.current = em
	var cat: GuardAnimalEntity = em.spawn_entity(&"cat_basket", vox(site), 0)
	d = duck(net, site + Vector3(2, 0, 0))
	fox = raider(net, &"fox", site + Vector3(6, 0, 0))
	fox.raid_site = site
	fox.target_animal_id = d.animal_id
	run(fox, ctx([], night), 0.3, net)
	check(fox.state != Creature.State.FLEE, "a cat doesn't take on a fox")
	var rat := raider(net, &"rat", site + Vector3(6, 0, 3))
	run(rat, ctx([], night), 0.3, net)
	check(rat.state == Creature.State.FLEE and cat.is_chasing(), "the cat chases a shore rat off")

	print("-- shore rats and sealed stores")
	net = make_net()
	em = EntityManager.new()
	EntityManager.current = em
	net.difficulty = CombatMath.Difficulty.COZY
	var crate: ChestEntity = em.spawn_entity(&"storage_crate", vox(site), 0)
	crate.container.deposit(&"silver_mackerel", 4)
	crate.container.deposit(&"stone", 5)
	var pantry: ChestEntity = em.spawn_entity(&"pantry_barrel", vox(site + Vector3(8, 0, 0)), 0)
	pantry.container.deposit(&"silver_mackerel", 4)
	var sea: ChestEntity = em.spawn_entity(&"sea_barrel", vox(site + Vector3(-8, 0, 0)), 0)
	check(crate.raidable_food() == [&"silver_mackerel"], "an open crate's food is raidable (stone isn't food)")
	check(pantry.sealed and pantry.raidable_food().is_empty(), "the sealed pantry barrel can't be raided")
	check(sea.sealed, "the watertight sea barrel is sealed too")
	var stores := net.wildlife.raidable_stores([player(site + Vector3(30, 0, 0))])
	check(stores.size() == 1 and stores[0] == crate, "only open stores with food are rat targets")
	var pdata := pantry.serialize()
	var pantry2: ChestEntity = ChestEntity.make_pantry_barrel(Vector3i.ZERO)
	pantry2.deserialize(pdata)
	check(pantry2.sealed and pantry2._stored_count() == 4, "pantry barrel keeps its food and seal through a save")
	rat = raider(net, &"rat", site + Vector3(12, 0, 0))
	rat.raid_site = site
	rat.target_store = crate.grid_coord
	run(rat, ctx([], night), 12.0, net)
	check(crate.container.inventory.get_item_count(&"silver_mackerel") == 3, "Cozy: a rat that gets in eats one bite")
	check(crate.container.inventory.get_item_count(&"stone") == 5, "rats leave non-food alone")
	check(rat.state == Creature.State.REPELLED or net.despawned.has(rat), "and then it leaves")
	net.difficulty = CombatMath.Difficulty.UNDERTOW
	var rat2 := raider(net, &"rat", site + Vector3(12, 0, 2))
	rat2.raid_site = site
	rat2.target_store = crate.grid_coord
	run(rat2, ctx([], night), 12.0, net)
	check(crate.container.inventory.get_item_count(&"silver_mackerel") == 0, "Undertow: a rat eats three")
	net.wildlife.last_storm_day = net.main.sky.day
	check(net.wildlife.storm_recent(), "rats know a storm just passed")
	net.main.sky.day += 3
	check(not net.wildlife.storm_recent(), "and forget it a couple of days later")
	var lit_net := make_net()
	lit_net.lights = [crate.position + Vector3(0, 1, 1)]
	check(lit_net.wildlife.raidable_stores([player(site)]).is_empty(), "a lit store isn't raided")

	print("-- sea eagles")
	net = make_net()
	em = EntityManager.new()
	EntityManager.current = em
	net.difficulty = CombatMath.Difficulty.COZY
	d = duck(net, site)
	var far_player := player(site + Vector3(40, 0, 0))
	check(net.wildlife.open_ducks([far_player]).has(d), "a duck in the open is an eagle target")
	var e := eagle_at(net, d)
	run(e, ctx([far_player]), 6.0, net)
	check(e.state == Creature.State.WANDER and e.position.y > site.y + 8.0, "the eagle circles high first (a warning)")
	run(e, ctx([far_player]), 10.0, net)
	check(net.main.livestock_mgr.get_animal_by_id(d.animal_id) != null and not e.is_carrying(),
			"Cozy: the stoop only scatters the ducks")
	net.difficulty = CombatMath.Difficulty.UNDERTOW
	var carried := false
	for i in 6:
		var dd := duck(net, site + Vector3(i * 0.1, 0, 0))
		var ee := eagle_at(net, dd)
		run(ee, ctx([far_player]), 16.0, net)
		if ee.is_carrying():
			carried = true
			ee.on_hit(1.0, ee.position + Vector3(1, 0, 0), 1.0, 7)
			check(not ee.is_carrying() and net.main.livestock_mgr.get_animal_by_id(dd.animal_id) != null,
					"hitting an eagle makes it drop the duck")
			break
	check(carried, "Undertow: an eagle can carry a duck off")
	# Answers.
	net = make_net()
	em = EntityManager.new()
	EntityManager.current = em
	net.difficulty = CombatMath.Difficulty.UNDERTOW
	d = duck(net, site)
	em.spawn_entity(&"scarecrow", vox(site + Vector3(5, 0, 0)), 0)
	check(not net.wildlife.open_ducks([far_player]).has(d), "a scarecrow nearby protects the duck")
	e = eagle_at(net, d)
	run(e, ctx([far_player]), 2.0, net)
	check(e.state == Creature.State.REPELLED, "an eagle won't stoop near a scarecrow")
	net = make_net()
	EntityManager.current = EntityManager.new()
	d = duck(net, site)
	var dv := vox(site)
	net.roofs[Vector2i(dv.x, dv.z)] = FLOOR + 12
	check(net.wildlife.roofed(d.position) and not net.wildlife.open_ducks([far_player]).has(d), "a duck under a roof is safe")
	e = eagle_at(net, d)
	run(e, ctx([far_player]), 2.0, net)
	check(e.state == Creature.State.REPELLED, "an eagle gives up on a roofed pen")
	net = make_net()
	d = duck(net, site)
	var near_player := player(site + Vector3(3, 0, 0))
	check(not net.wildlife.open_ducks([near_player]).has(d), "a duck with someone beside it isn't targeted")
	e = eagle_at(net, d)
	run(e, ctx([near_player]), 1.0, net)
	check(e.state == Creature.State.REPELLED, "standing with your ducks sees the eagle off")
	e = eagle_at(net, d)
	run(e, ctx([far_player], {"night": 1.0}), 0.5, net)
	check(e.state == Creature.State.REPELLED, "eagles don't hunt at night")

	print("-- otter friends persist")
	net = make_net()
	net.wildlife.remember_otter_friend(7)
	var w2 := WildlifeDirector.new(make_net())
	w2.deserialize(net.wildlife.serialize())
	check(w2.otter_friends.has("7"), "who befriended an otter survives a save/load")
	var o := net.spawn(&"otter", Vector3(0, 0, 0)) as SeaOtter
	o.befriend(7)
	check(net.wildlife.has_otter_friend_here(7) and not net.wildlife.has_otter_friend_here(8), "the director knows whose otter is about")
	net.wildlife.rat_raids_left = 2
	net.wildlife.eagles_left = 1
	net.wildlife.last_storm_day = 4
	w2.deserialize(net.wildlife.serialize())
	check(w2.rat_raids_left == 2 and w2.eagles_left == 1 and w2.last_storm_day == 4, "rat/eagle budgets and the storm survive a save")

	print("-- livestock co-op mirroring")
	var host := LivestockManager.new()
	var client := LivestockManager.new()
	var a: Node3D = host.spawn_animal(&"shore_sheep", Vector3(3, 1, 4), "Daisy")
	host.spawn_animal(&"shore_duck", Vector3(5, 1, 4), "Pip")
	a.wool_grown = false
	a.yaw = 1.2
	var packs: Array = []
	for an in host.animals:
		packs.append(an.net_pack())
	client.apply_snapshot(packs)
	check(client.animals.size() == 2, "a client mirrors every animal the host has")
	var ca: Node3D = client.get_animal_by_id(a.animal_id)
	check(ca != null and ca.animal_name == "Daisy" and not ca.wool_grown, "names and shorn wool come across")
	a.position = Vector3(4, 1, 4)
	packs = [a.net_pack()]
	client.apply_snapshot(packs)
	for i in 40:
		ca.net_update(0.05)
	check(ca.position.distance_to(Vector3(4, 1, 4)) < 0.05, "client animals glide to where the host has them")
	check(absf(angle_difference(ca.yaw, 1.2)) < 0.05, "and face the same way")
	check(client.animals.size() == 1, "animals the host no longer has disappear on the client")
	ca.pet_cooldown = 45.0
	ca.happiness = 99.0
	a.apply_interact_state(ca.interact_state())
	check(a.pet_cooldown == 45.0 and a.happiness == 99.0, "a client's petting / shearing is applied on the host")
	check(LivestockAnimal_holds_test(), "herd bait detection works for any player node")

	print("-- harbour bell")
	check(ItemDB.has_item(&"village_bell") and RecipeDB.has_recipe(&"place_village_bell")
			and EntityManager.resolve_type(&"bell") == &"village_bell", "the harbour bell is craftable and placeable")
	check(WildlifeDirector.compass(Vector3.ZERO, Vector3(0, 0, -20)) == "north"
			and WildlifeDirector.compass(Vector3.ZERO, Vector3(20, 0, 20)) == "south-east", "bell calls give compass directions")
	net = make_net()
	em = EntityManager.new()
	EntityManager.current = em
	var bell: VillageBellEntity = em.spawn_entity(&"village_bell", vox(site + Vector3(0, 0, 30)), 0)
	check(bell != null, "bell places")
	var lone := Vector3(400, ground, 400)
	check(not net.wildlife.ring_for_raid(lone, &"fox"), "a raid far from any bell rings nothing")
	crate = em.spawn_entity(&"storage_crate", vox(site), 0)
	crate.container.deposit(&"silver_mackerel", 3)
	net.alerts.clear()
	var r0 := net.wildlife.try_start_rat_raid([player(site + Vector3(40, 0, 0))])
	check(r0 != null and bell.is_ringing() and bell.beacon_active(), "a raid near the bell rings it and lights the beacon")
	check(bell.alarm_at.distance_to(crate.position) < 1.0, "the beacon marks the raid, not the bell")
	check(net.alerts.any(func(t: String) -> bool: return t.contains("harbour bell") and t.contains("north of the bell")),
			"everyone is told what and where (%s)" % [net.alerts])
	check(not bell.ring(site, "again"), "a bell can't be rung again while it's still humming")
	for i in 200:
		bell._process(0.05)
	check(bell.can_ring() and not bell.is_ringing(), "it settles and can ring again")
	var near_fox := raider(net, &"fox", bell.position + Vector3(8, 0, 0))
	var far_fox2 := raider(net, &"fox", bell.position + Vector3(60, 0, 0))
	var res: Dictionary = bell.server_action(&"ring", {}, 1)
	check(String(res.get("toast", "")).contains("bolts") and near_fox.state == Creature.State.FLEE,
			"ringing by hand sends a nearby raider running")
	check(far_fox2.state != Creature.State.FLEE, "raiders out of earshot carry on")
	check(not bell.serialize().has("alarm") and not bell.serialize().has("ring"), "old alarms aren't saved (loading never rings)")
	var client_bell := VillageBellEntity.new(bell.grid_coord)
	client_bell.play_ring(site, "Fox!")
	check(client_bell.is_ringing() and client_bell.beacon_active() and client_bell.alarm_text == "Fox!",
			"a client rings and shows the beacon when the host's ring arrives")
	client_bell.free()
	var toll := VillageBellEntity.toll_stream()
	check(toll != null and toll.data.size() > 40000, "the bell's toll is synthesised")

	EntityManager.current = null
	print("Farm guardians suite: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)


func LivestockAnimal_holds_test() -> bool:
	var LA := preload("res://scripts/livestock/livestock_animal.gd")
	var holder := Node3D.new()
	holder.set_meta("x", 1)
	var ok := not LA.holds_herd_bait(holder)
	holder.free()
	return ok
