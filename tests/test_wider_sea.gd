extends SceneTree
## The wider sea (layout 2+): castaways in the wrecks, Gloom-Crawlers, secret recipes and
## scroll copying, Sea-Reaver outposts, the Tide Hearth and town morale, the bigger boats,
## and the Barnacled Hulk.
##   godot --headless --path . -s tests/test_wider_sea.gd

var passed := 0
var total := 0


func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)


func make_gen(seed: int) -> WorldGen:
	VoxelWorld.apply_layout(2)
	var g := WorldGen.new(seed, VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ, VoxelWorld.SEA_MID,
			VoxelWorld.TIDE_AMP, VoxelWorld.layout_params(2))
	g.plan_starter()
	g.plan_villages()
	g.plan_camps()
	g.plan_underground()
	g.plan_wrecks()
	g.plan_outposts()
	g.plan_hulk()
	return g


func make_store(gen: WorldGen) -> VoxelStore:
	var s := VoxelStore.new()
	s.setup(Vector3i(VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ), VoxelWorld.VS)
	s.set_generator(gen.native)
	return s


func vox(s: VoxelStore, x: int, y: int, z: int) -> int:
	var col := Vector2i(x >> 5, z >> 5)
	if not s.is_column_generated(col):
		s.generate_column(col)
	return s.get_voxel(x, y, z)


func _init() -> void:
	VoxelWorld.push_palette()
	ItemDB.init_db()
	RecipeDB.init_db()
	Placeables.register_builtin()
	RecipeBook.register_scroll_items()
	var g := make_gen(1106)
	var s := make_store(g)
	var hut := Vector2(g.starter.hut.x, g.starter.hut.z)
	_castaways(g, s)
	_crawlers()
	_recipes()
	_outposts(g, s, hut)
	_extra(g, s, hut)
	print("Wider sea suite: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)


func _castaways(g: WorldGen, s: VoxelStore) -> void:
	print("-- castaways in the wrecks")
	var picks := VillageManager.castaway_wrecks(g.wrecks.size())
	check(picks.size() >= 2, "some wrecks hold a castaway (%d)" % picks.size())
	var ok := true
	for k: int in picks:
		var c := VillageManager.castaway_cell(g.wrecks[k])
		var below := vox(s, c.x, c.y - 1, c.z)
		var head := vox(s, c.x, c.y + 6, c.z)
		if below == 0 or vox(s, c.x, c.y, c.z) != 0 or head != 0:
			ok = false
			print("     castaway cell %s: below %d at %d head %d" % [c, below, vox(s, c.x, c.y, c.z), head])
	check(ok, "each castaway stands on the wreck's floor with headroom")
	check(VillageManager.CASTAWAYS.size() == 3, "three castaways to find")


func _crawlers() -> void:
	print("-- Gloom-Crawlers")
	var gc := GloomCrawler.new()
	check(gc.hostile and gc.max_hp > 10.0, "a Gloom-Crawler is a hostile cave hunter")
	var loud := {"speed": 4.0, "sneaking": false, "sprinting": false, "in_water": false, "dist": 5.0}
	var soft := {"speed": 2.0, "sneaking": true, "sprinting": false, "in_water": false, "dist": 5.0}
	check(gc._hears(loud), "it hears a walking player 5 m off")
	check(not gc._hears(soft), "but not one sneaking past")
	check(gc._repelled({"has_light": true, "dist": 3.0}, {"lights": []}), "a held lantern keeps it off")
	check(ItemDB.has_item(&"gloom_gland"), "it drops a gland")
	gc.free()
	check(CreatureNet.KINDS.has(&"gloomcrawler"), "Gloom-Crawlers are networked creatures")


func _recipes() -> void:
	print("-- secret recipes and scroll copies")
	var book := RecipeBook.new()
	check(not book.knows(&"cook_leviathan_feast"), "the Leviathan Feast starts locked")
	var inv := Inventory.new(10)
	inv.add_item(&"abyssal_ray", 1)
	var got := book.on_item_acquired(&"abyssal_ray", inv)
	check(got.has(&"cook_leviathan_feast"), "landing the Abyssal Ray teaches its secret feast")
	check(FishDB.get_fish(&"abyssal_ray") != null and FishDB.get_fish(&"abyssal_ray").item_id == &"abyssal_ray",
			"the ray lands as itself, not a mackerel")
	check(ItemDB.get_item(&"leviathan_feast").food_data.has("extra_breath_sec"), "the feast is a real buff meal")
	check(RecipeBook.source_of(&"smoke_storm_eel").begins_with("Secret"), "the book hints where a secret comes from")
	check(not book.copy_scroll(&"cook_leviathan_feast", inv), "copying needs parchment")
	inv.add_item(&"shore_wheat", 2)
	check(book.copy_scroll(&"cook_leviathan_feast", inv), "with 2 shore wheat you write out a copy")
	var sc := RecipeBook.scroll_item(&"cook_leviathan_feast")
	check(inv.get_item_count(sc) == 1 and inv.get_item_count(&"shore_wheat") == 0, "the copy is in your bag, the wheat spent")
	book.on_item_acquired(sc, inv)
	check(inv.get_item_count(sc) == 1, "a scroll you already know is kept, not read")
	var friend := RecipeBook.new()
	var inv2 := Inventory.new(10)
	inv2.add_item(sc, 1)
	check(friend.on_item_acquired(sc, inv2).has(&"cook_leviathan_feast") and inv2.get_item_count(sc) == 0,
			"a friend who picks it up learns it")
	check(not book.can_copy(&"cook_roasted_mackerel") or book.knows(&"cook_roasted_mackerel"), "only known recipes copy")


func _outposts(g: WorldGen, s: VoxelStore, hut: Vector2) -> void:
	print("-- Sea-Reaver outposts")
	check(g.outposts.size() >= 1, "outposts are planned (%d)" % g.outposts.size())
	var far := true
	var lonely := true
	for o: Dictionary in g.outposts:
		var c: Vector3 = o.center
		if Vector2(c.x, c.z).distance_to(hut) < WorldGen.OUT_MIN_HOME:
			far = false
		for cp: Dictionary in g.camps:
			if int(cp.island) == int(o.island):
				lonely = false
		for v: Dictionary in g.villages:
			if int(v.island) == int(o.island):
				lonely = false
	check(far, "no outpost within ~400 m of the starting house")
	check(lonely, "outposts never share an island with a camp or village")
	if g.outposts.is_empty():
		return
	var o: Dictionary = g.outposts[0]
	var t: Vector3 = o.tower
	var plat := vox(s, floori(t.x), int(t.y) - 1, floori(t.z))
	check(plat == Palette.PLANK, "the watchtower has a plank lookout platform (got %d)" % plat)
	var wood := 0
	var c: Vector3 = o.center
	var gate: Vector2 = o.gate
	for k in 64:
		var a := TAU * k / 64.0
		if absf(angle_difference(a, atan2(gate.y, gate.x))) < 0.3:
			continue
		var x := floori(c.x + cos(a) * WorldGen.CAMP_R)
		var z := floori(c.z + sin(a) * WorldGen.CAMP_R)
		for y in range(int(c.y), int(c.y) + 12):
			var m := vox(s, x, y, z)
			if m == Palette.TRUNK or m == Palette.DARK_WOOD:
				wood += 1
				break
	check(wood > 40, "a stockade rings the outpost (%d of 64 samples)" % wood)
	var sr := SeaReaver.new()
	var hp := SeaReaver.new(true)
	check(sr.hostile and hp.harpooner and hp.strike_range > 8.0, "cutlass reavers and ranged harpooners")
	sr.free()
	hp.free()
	var ro := ReaverOutposts.new()
	check(ro.garrison(CombatMath.Difficulty.TIDEWATCH)[&"reaver_harpooner"] >= 1, "every muster has a harpooner for the tower")
	ro.free()
	var tot := WarHornEntity.new(Vector3i.ZERO)
	tot.outpost = 1
	tot.toppled = true
	var tot2 := WarHornEntity.new(Vector3i.ZERO)
	tot2.deserialize(tot.serialize())
	check(tot2.toppled and tot2.outpost == 1, "a toppled totem stays toppled when saved")
	tot.free()
	tot2.free()
	var g2 := make_gen(1106)
	check(g2.outposts.size() == g.outposts.size() and (g2.outposts.is_empty() or g2.outposts[0].center == g.outposts[0].center),
			"same seed, same outposts")


func _extra(g: WorldGen, s: VoxelStore, hut: Vector2) -> void:
	print("-- the Tide Hearth and town morale")
	var town := SettlementManager.new(Vector3i(10, 11, 10))
	var d := DrifterDef.new(&"t1", "Tess", DrifterDef.Profession.FISHER)
	town.recruit_drifter(d)
	var bare: float = town.morale_parts(d).total
	town.rooms.append({"id": 0, "center": Vector3i(12, 11, 12), "quality": 80, "valid": true, "assigned_drifter_id": &""})
	town.assign_drifter_to_room(&"t1", 0)
	town.food_kinds = 4
	town.safety = 1.0
	town.found_at(Vector3i(10, 11, 10))
	var good: float = town.morale_parts(d).total
	check(good > bare + 0.4, "a home, food variety, safety and a hearth lift morale (%.2f -> %.2f)" % [bare, good])
	d.morale = 0.2
	for i in 40:
		town.tick_settlement(5.0, 0.4)
	check(d.morale > 0.6, "morale settles toward its target over time (%.2f)" % d.morale)
	town.town_depot.deposit(&"silver_mackerel", 3)
	var goods := town.collect_depot()
	check(goods.size() >= 1 and town.depot_count() == 0, "the hearth hands over the town depot")
	check(town.report().contains("morale"), "the hearth gives a town report")
	var t2 := SettlementManager.new()
	t2.deserialize(town.serialize())
	check(t2.hearth_placed and t2.food_kinds == 4, "the hearth and town conditions are saved")
	check(RecipeDB.has_recipe(&"place_tide_hearth"), "the Tide Hearth can be built")

	print("-- the Tide-Barge and the Coastal Sloop")
	var barge := Boat.new()
	barge.setup(1, null, null, Vector3.ZERO, 0.0, Boat.KIND_BARGE)
	check(barge.occupants.size() == 4 and barge.hold != null and barge.hold.slots.size() == Boat.HOLD_SLOTS,
			"the barge seats four and has a 27-stack hold")
	barge.hold.add_item(&"cobblestone", 60)
	check(barge.hold_used() >= 1 and not barge.has_sail(), "cargo goes in the hold; the barge is rowed")
	var sloop := Boat.new()
	sloop.setup(2, null, null, Vector3.ZERO, 0.0, Boat.KIND_SLOOP)
	check(sloop.occupants.size() == 3 and sloop.has_sail(), "the sloop seats three and sails")
	var head := Vector2(0, 1)
	var wind := Vector2(0, -1).rotated(deg_to_rad(35.0))   # 145 degrees off: close to the wind
	check(Boat.sail_efficiency(head, wind, 150.0) > 0.0 and Boat.sail_efficiency(head, wind) == 0.0,
			"the sloop points higher than a skiff")
	check(RecipeDB.has_recipe(&"craft_barge_kit") and RecipeDB.has_recipe(&"craft_sloop_kit"), "both are built at a workbench")
	check(BoatManager.KITS.has(&"barge_kit") and BoatManager.KITS.has(&"sloop_kit"), "both launch from a kit")
	barge.free()
	sloop.free()
	check(RecipeDB.has_recipe(&"place_mooring_bollard"), "mooring bollards can be built")

	print("-- the Barnacled Hulk")
	check(not g.hulk.is_empty(), "the Hulk's strand is planned")
	if not g.hulk.is_empty():
		var lair: Vector3 = g.hulk.lair
		check(Vector2(lair.x, lair.z).distance_to(hut) > WorldGen.HULK_MIN_HOME, "on the far side of the archipelago")
		check(lair.y - 1 < g.sea_mid, "on flats below half tide (so the ebb leaves it in the mud)")
		check(g.hulk.boulders.size() == 2, "two boulders on the rocks above")
		var b: Vector3i = g.hulk.boulders[0]
		check(vox(s, b.x, b.y - 1, b.z) != 0 and b.y > int(lair.y) + 8, "each boulder sits up on solid rock")
	var h := BarnacledHulk.new()
	check(h.effective_damage(100.0) < 20.0, "the galleon shell turns most of a blow")
	h.cracks = 2
	check(h.effective_damage(100.0) == 100.0, "split, every blow lands")
	h.set_meta("mired", true)
	h.state = Creature.State.STAGGER
	check(h.effective_damage(100.0) == 250.0, "mired in the mud, its underside takes 2.5x")
	check(h.drops()[0][0] == &"hulk_pearl" and ItemDB.has_item(&"hulk_pearl"), "it drops its pearl")
	h.free()
	var bo := BoulderEntity.new(Vector3i.ZERO)
	var r := bo.server_action(&"push", {}, 1)
	check(bo.pushed and r.get("changed", false), "a boulder can be pushed")
	bo.server_tick(BoulderEntity.REGROW_SEC + 1.0, {})
	check(not bo.pushed, "and another works loose later")
	bo.free()
