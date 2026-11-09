extends SceneTree
## The outer isles (layout 2+): the home lighthouse, Mud-Claw camps (never near home), the old
## brass mines, flooded sumps and freshwater springs, stone wells, beached shipwrecks, and the
## rare recipe scrolls dealt out among them.
##   godot --headless --path . -s tests/test_outer_isles.gd

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
	var hut := Vector2(g.starter.hut.x, g.starter.hut.z)
	var s := make_store(g)

	print("-- the lighthouse")
	var lh: Variant = g.starter.get("lighthouse")
	check(lh is Vector3i, "a lighthouse is planned on the home island")
	if lh is Vector3i:
		var d := Vector2((lh as Vector3i).x, (lh as Vector3i).z).distance_to(hut) * VoxelWorld.VS
		check(d < 60.0, "the lighthouse stands near the starting house (%.0f m)" % d)

	print("-- Mud-Claw camps")
	check(g.camps.size() >= 2, "camps are planned (%d)" % g.camps.size())
	var far := true
	var off_home := true
	for c: Dictionary in g.camps:
		if Vector2(c.center.x, c.center.z).distance_to(hut) < WorldGen.CAMP_MIN_HOME:
			far = false
		if int(c.island) == 0:
			off_home = false
	check(far, "no camp within ~300 m of the starting house")
	check(off_home, "no camp on the home island")
	var mc := MudClaw.new(false)
	var mb := MudClaw.new(true)
	check(mb.max_hp > mc.max_hp * 3, "a brute is much tougher than a swarmer")
	mc.free()
	mb.free()

	print("-- brass mines")
	check(g.mines.size() >= 1, "old brass mines are planned (%d)" % g.mines.size())
	if not g.mines.is_empty():
		var m: Dictionary = g.mines[0]
		check(int(m.island) != 0, "mines are never on the home island")
		var gal: Vector3i = m.gallery
		var cal := 0
		for y in range(gal.y, gal.y + 14, 2):
			for z in range(gal.z - 14, gal.z + 15, 2):
				for x in range(gal.x - 14, gal.x + 15, 2):
					if vox(s, x, y, z) == Palette.CALAMINE:
						cal += 1
		check(cal > 10, "the gallery walls are crusted with calamine (%d sampled)" % cal)
		var open := 0
		for y in range(gal.y, gal.y + 10):
			if vox(s, gal.x, y, gal.z) == 0:
				open += 1
		check(open >= 9, "the gallery has headroom for a player (%d voxels)" % open)

	print("-- sumps and springs")
	check(g.sumps.size() >= 1, "flooded sumps are planned (%d)" % g.sumps.size())
	check(g.springs.size() >= g.sumps.size(), "every karst cavern with a sump also has a spring")
	if not g.sumps.is_empty():
		var sp: Dictionary = g.sumps[0]
		var ch: Vector3i = sp.chest
		check(ch.y < g.sea_low, "the sunken cache lies below the lowest tide")
		check(vox(s, ch.x, ch.y + 1, ch.z) == 0, "the sump chamber is open (water-filled) around the cache")

	print("-- shipwrecks")
	check(g.wrecks.size() >= 3, "beached shipwrecks are planned (%d)" % g.wrecks.size())
	var wood_ok := true
	var near_home := false
	for w: Dictionary in g.wrecks:
		var c: Vector3i = w.center
		if Vector2(c.x, c.z).distance_to(hut) < WorldGen.WRECK_MIN_HOME:
			near_home = true
		var wood := 0
		for y in range(c.y - 2, c.y + 16):
			for k in range(-WorldGen.WRECK_B - 6, WorldGen.WRECK_B + 7):
				var d: Vector2i = w.dir
				var m := vox(s, c.x + d.x * k, y, c.z + d.y * k)
				if m == Palette.DARK_WOOD or m == Palette.PLANK or m == Palette.DRIFTWOOD:
					wood += 1
		if wood < 8:
			wood_ok = false
	check(wood_ok, "every wreck has a hull of planks on the shore")
	check(not near_home, "no wreck right on the starting house's doorstep")

	print("-- planning is a pure function of the seed")
	var g2 := make_gen(1106)
	check(g2.camps.size() == g.camps.size() and g2.mines.size() == g.mines.size()
			and g2.wrecks.size() == g.wrecks.size(), "same seed, same camps, mines and wrecks")
	if not g.wrecks.is_empty() and not g2.wrecks.is_empty():
		check(g2.wrecks[0].center == g.wrecks[0].center, "same seed, same first wreck")

	print("-- recipe scrolls")
	var book := RecipeBook.new()
	check(not book.knows(RecipeBook.MINE_SCROLL), "fine sea-brass starts locked")
	check(not book.knows(&"place_stone_well"), "the stone well starts locked")
	var all_items := true
	for rid: StringName in RecipeBook.FOUND_SCROLLS:
		all_items = all_items and ItemDB.has_item(RecipeBook.scroll_item(rid))
		all_items = all_items and RecipeDB.has_recipe(rid)
	check(all_items, "every rare scroll is a real item for a real recipe")
	var inv := Inventory.new(10)
	inv.add_item(RecipeBook.scroll_item(RecipeBook.MINE_SCROLL), 1)
	var learned := book.on_item_acquired(RecipeBook.scroll_item(RecipeBook.MINE_SCROLL), inv)
	check(learned.has(RecipeBook.MINE_SCROLL) and book.knows(RecipeBook.MINE_SCROLL), "reading the mine scroll teaches fine sea-brass")
	check(inv.get_item_count(RecipeBook.scroll_item(RecipeBook.MINE_SCROLL)) == 0, "the scroll is read into the book")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var wl := ChestEntity.wreck_loot(rng)
	check(wl.size() >= 4, "a wreck locker holds salvage and coin")

	print("-- springs and wells")
	var well := WaterSourceEntity.make_well(Vector3i.ZERO)
	var r1: Dictionary = well.server_action(&"draw", {}, 1)
	var r2: Dictionary = well.server_action(&"draw", {}, 1)
	check(r1.get("grant", []) == [[&"spring_water", WaterSourceEntity.WELL_MAX]], "a full well gives four flasks")
	check(r2.is_empty(), "then it is dry")
	well.server_tick(WaterSourceEntity.WELL_SEEP_SEC + 0.5, {})
	check(well.stored == 1, "and seeps back a flask at a time")
	var d2 := well.serialize()
	var well2 := WaterSourceEntity.make_well(Vector3i.ZERO)
	well2.deserialize(d2)
	check(well2.stored == 1, "a well's water is saved")
	var spring := WaterSourceEntity.make_spring(Vector3i.ZERO)
	check(spring.server_action(&"draw", {}, 1).get("grant", []) == [[&"spring_water", WaterSourceEntity.SPRING_FILL]], "a spring never runs dry")
	well.free()
	well2.free()
	spring.free()
	check(ItemDB.get_item(&"spring_water").category == ItemDef.Category.FOOD, "spring water is a drink")
	check(RecipeDB.has_recipe(&"furnace_fine_brass"), "the furnace can quench fine sea-brass")

	print("Outer isles suite: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)
