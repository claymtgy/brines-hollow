extends SceneTree
## NPC villages (layout 2+), their people and the elder's requests; village traders; and
## the reworked trees (lean, lopsided crowns, see-through leaves).
##   godot --headless --path . -s tests/test_villages.gd

var passed := 0
var total := 0


func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)


func make_gen(layout: int, seed: int) -> WorldGen:
	VoxelWorld.apply_layout(layout)
	return WorldGen.new(seed, VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ, VoxelWorld.SEA_MID,
			VoxelWorld.TIDE_AMP, VoxelWorld.layout_params(layout))


func make_store(gen: WorldGen) -> VoxelStore:
	VoxelWorld.apply_layout(2)
	var s := VoxelStore.new()
	s.setup(Vector3i(VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ), VoxelWorld.VS)
	s.set_generator(gen.native)
	return s


func vox(s: VoxelStore, x: int, y: int, z: int) -> int:
	var col := Vector2i(x >> 5, z >> 5)
	if not s.is_column_generated(col):
		s.generate_column(col)
	return s.get_voxel(x, y, z)


func atlas_for(g: WorldGen, seed: int) -> IslandAtlas:
	var a := IslandAtlas.new()
	var n: ArchipelagoGen = g.native
	a.setup(g.islands, seed, n.column_height, n.column_island, VoxelWorld.SEA_MID)
	return a


func _init() -> void:
	VoxelWorld.push_palette()
	ItemDB.init_db()

	print("-- villages are planned on the larger islands")
	var counts: Array = []
	for sd in [1106, 77, 4242]:
		var gs := make_gen(2, sd)
		gs.plan_starter()
		gs.plan_villages()
		counts.append(gs.villages.size())
	print("   villages per seed: %s" % [counts])
	check(counts.min() >= 2, "every tested seed gets at least two villages")
	var g := make_gen(2, 1106)
	g.plan_starter()
	g.plan_villages()
	var islands_used := {}
	for v: Dictionary in g.villages:
		islands_used[int(v.island)] = true
	check(not islands_used.has(0) and islands_used.size() == g.villages.size(), "one village per island, never on the home island")
	var g2 := make_gen(2, 1106)
	g2.plan_starter()
	g2.plan_villages()
	check(str(g.villages) == str(g2.villages), "village plans are a pure function of the seed (same on every peer)")
	var g1 := make_gen(1, 1106)
	g1.plan_starter()
	check(g1.villages.is_empty(), "classic worlds don't get villages")

	print("-- what's built there")
	var st := make_store(g)
	var v0: Dictionary = g.villages[0]
	check(v0.cottages.size() >= 3, "at least three cottages (%d)" % v0.cottages.size())
	var planks := 0
	var de: Vector3 = v0.dock_end
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			for dy in range(-3, 3):
				if vox(st, int(de.x) + dx, int(de.y) + dy, int(de.z) + dz) == Palette.PLANK:
					planks += 1
	check(planks > 5, "a pier runs out to the dock end (%d planks there)" % planks)
	var walls := 0
	var door: Vector3 = v0.cottages[0].door
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			for dy in range(1, 7):
				var m := vox(st, int(door.x) + dx, int(door.y) + dy, int(door.z) + dz)
				if m != 0 and not Palette.is_plant(m) and not Palette.is_foliage(m):
					walls += 1
	check(walls > 40, "a cottage stands at the first door (%d built voxels above the ground)" % walls)
	var door_air := vox(st, int(door.x), int(door.y), int(door.z)) == 0 or Palette.is_plant(vox(st, int(door.x), int(door.y), int(door.z)))
	check(door_air, "and its doorway is open")

	print("-- names, people and requests")
	var atlas := atlas_for(g, 1106)
	var recs := NpcVillages.build_records(g.villages, atlas, 1106)
	check(recs.size() == g.villages.size(), "a record per village")
	var r0: Dictionary = recs[0]
	var isl_pre := atlas.name_of(int(r0.island)).split(" ")[0]
	check(String(r0.name).begins_with(isl_pre), "the village is named after its island (%s on %s)" % [r0.name, atlas.name_of(int(r0.island))])
	var roles := {}
	var names := {}
	for rec: Dictionary in recs:
		for p: Dictionary in rec.people:
			roles[p.role] = int(roles.get(p.role, 0)) + 1
			names[p.name] = true
	check(roles.get("trader", 0) == recs.size() and roles.get("elder", 0) == recs.size(), "one trader and one elder per village")
	check(names.size() == recs.size() * NpcVillages.ROLES.size(), "every villager has their own name")
	var home_ok := true
	for p: Dictionary in r0.people:
		if (p.home as Vector3).distance_to(r0.center) > 80.0 or (p.work as Vector3).distance_to(r0.center) > 80.0:
			home_ok = false
	check(home_ok, "homes and work spots are in the village (metres)")
	check(str(recs) == str(NpcVillages.build_records(g2.villages, atlas_for(g2, 1106), 1106)), "every peer names the same people")
	var req_ok := true
	for rec: Dictionary in recs:
		var seen := {}
		for i: int in rec.requests:
			if seen.has(i) or ItemDB.get_item(NpcVillages.REQUESTS[i][0]) == null:
				req_ok = false
			seen[i] = true
	check(req_ok and (r0.requests as Array).size() == NpcVillages.CHAIN_LEN, "each elder has a chain of %d different requests for real items" % NpcVillages.CHAIN_LEN)

	print("-- villager routine")
	var npc := VillagerNPC.new()
	var sky := SkyCycle.new()
	npc.setup("t:fisher", "fisher", "Ewan", Vector3(0, 5, 0), Vector3(20, 5, 0), 3, null, sky)
	sky.time_of_day = 0.5
	var noon := npc.goal()
	sky.time_of_day = 0.95
	var night := npc.goal()
	check(noon.distance_to(Vector3(20, 5, 0)) < 3.5 and night == Vector3(0, 5, 0), "at work by day, home at night")
	npc.free()
	sky.free()

	print("-- the elder's requests are real quests")
	var nv := NpcVillages.new()
	var q := nv.request_def(r0, 0)
	var rq: Array = NpcVillages.REQUESTS[r0.requests[0]]
	var qm := QuestManager.new()
	var inv := Inventory.new(24)
	qm.register_available_quest(q)
	check(qm.accept_quest(q.id), "accepting a request starts a quest (%s)" % q.title)
	qm.notify_event(QuestDef.ObjectiveType.TALK_TO, StringName("vel_" + r0.key), 1, inv)
	check(qm.is_quest_completed(q.id) and inv.get_item_count(&"brass_guilder") == int(rq[2]), "handing over the goods completes it and pays %d brass" % rq[2])
	var data := qm.serialize()
	var qm2 := QuestManager.new()
	qm2.deserialize(data)
	check(qm2.is_quest_completed(q.id), "village requests survive a save")
	nv.free()

	print("-- village traders")
	var m := TradeManager.village_wares("Tamsin of Test Haven", 3, 1)
	check(m.stock.get_item_count(&"copper_ore") > 0 and TradeRules.price_to_buy(m, &"copper_ore", 1) > 0, "a crags village sells copper ore")
	check(m.active_contracts.is_empty(), "village traders don't carry export manifests")
	var m2 := TradeManager.village_wares("x", 0, 1)
	check(m2.stock.get_item_count(&"seed_shore_wheat") > 0 and m2.buying_prices.has(&"silver_mackerel"), "a meadow village sells seed and buys fish")
	var cost := TradeRules.server_buy(m2, &"wood_plank", 2)
	check(cost > 0 and m2.stock.get_item_count(&"wood_plank") == 28, "buying takes from the village's own stock")
	var back := TradeRules.deserialize_merchant(TradeRules.serialize_merchant(m2))
	check(back.stock.get_item_count(&"wood_plank") == 28 and back.merchant_name == "x", "village stock saves and syncs")

	print("-- trees: each its own shape")
	var leaned := 0
	var trees := 0
	var lopsided := 0
	var hc: Vector2 = g.islands[0].center
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			var col := Vector2i((int(hc.x) >> 5) + cx, (int(hc.y) >> 5) + cz)
			var layers: Array = g.native.generate_column_debug(col.x, col.y)
			# trunks: connected trunk voxels; compare the centre low down with the centre up top
			var cells := {}
			for y in layers.size():
				var l: PackedByteArray = layers[y]
				for i in l.size():
					if l[i] == Palette.TRUNK:
						cells[Vector3i(i % 32, y * 32 + i / 1024, (i / 32) % 32)] = true   # 32^3 chunks, stacked
			var seen := {}
			for c0: Vector3i in cells:
				if seen.has(c0):
					continue
				var comp: Array = []
				var stack: Array = [c0]
				seen[c0] = true
				var edge := false
				while not stack.is_empty():
					var c: Vector3i = stack.pop_back()
					comp.append(c)
					if c.x == 0 or c.x == 31 or c.z == 0 or c.z == 31:
						edge = true
					for dy in [-1, 0, 1]:
						for dz in [-1, 0, 1]:
							for dx in [-1, 0, 1]:
								var n := c + Vector3i(dx, dy, dz)
								if cells.has(n) and not seen.has(n):
									seen[n] = true
									stack.append(n)
				if edge:
					continue
				var y0 := 9999
				var y1 := -1
				for c: Vector3i in comp:
					y0 = mini(y0, c.y)
					y1 = maxi(y1, c.y)
				if y1 - y0 < 10:
					continue
				var lo := Vector2.ZERO
				var nlo := 0
				var hi := Vector2.ZERO
				var nhi := 0
				for c: Vector3i in comp:
					if c.y >= y0 + 2 and c.y <= y0 + 4:
						lo += Vector2(c.x, c.z)
						nlo += 1
					elif c.y >= y1 - 6 and c.y <= y1 - 4:
						hi += Vector2(c.x, c.z)
						nhi += 1
				if nlo == 0 or nhi == 0:
					continue
				trees += 1
				if (lo / nlo).distance_to(hi / nhi) >= 0.9:
					leaned += 1
			# leaves around the column's centre of mass: crowns aren't mirror images
			var lx := 0.0
			var ln := 0
			var tx := 0.0
			var tn := 0
			for y in layers.size():
				var l: PackedByteArray = layers[y]
				for i in l.size():
					if Palette.is_leafy(l[i]):
						lx += i % 32
						ln += 1
					elif l[i] == Palette.TRUNK:
						tx += i % 32
						tn += 1
			if ln > 200 and tn > 20 and absf(lx / ln - tx / tn) > 0.6:
				lopsided += 1
	print("   %d trunks, %d leaning; %d columns with off-centre foliage" % [trees, leaned, lopsided])
	check(trees > 3 and leaned * 3 >= trees, "many trees lean or bend (%d of %d)" % [leaned, trees])
	check(lopsided >= 3, "crowns sit off-centre of their trunks")

	print("-- leaves are partly see-through")
	VoxelWorld.apply_layout(1)
	var ps := VoxelStore.new()
	ps.setup(Vector3i(64, 64, 64), VoxelWorld.VS)
	for x in range(2, 6):
		for y in range(2, 6):
			for z in range(2, 6):
				ps.set_voxel(x, y, z, Palette.LEAVES)
	var leaf_mesh: Array = ps.mesh_chunk(Vector3i(0, 0, 0))
	var leaf_v := ((leaf_mesh[0] as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for x in range(2, 6):
		for y in range(2, 6):
			for z in range(2, 6):
				ps.set_voxel(x, y, z, Palette.STONE)
	var stone_mesh: Array = ps.mesh_chunk(Vector3i(0, 0, 0))
	var stone_v := ((stone_mesh[0] as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	check(leaf_v > stone_v * 2, "a leaf clump draws its inner faces, to be seen through its gaps (%d vs %d verts)" % [leaf_v, stone_v])
	var cols: PackedColorArray = (leaf_mesh[0] as Array)[Mesh.ARRAY_COLOR]
	check(cols.size() > 0 and cols[0].a >= 0.75, "and its faces are flagged for the shader's leaf gaps")
	check(Palette.is_leafy(Palette.LEAVES_DARK) and not Palette.is_leafy(Palette.FLOWER_Y) and not Palette.is_leafy(Palette.KELP),
		"only leaf blocks get gaps")
	var hit: Dictionary = ps.raycast(Vector3(4, 30, 4) * VoxelWorld.VS, Vector3.DOWN, 20.0, false)
	check(not hit.is_empty(), "leaves (and the stone here) still block raycasts and digging")

	print("Villages and trees suite: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)
