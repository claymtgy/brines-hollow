extends SceneTree
## The archipelago: island layout and variety (native generator), island names, landfall
## detection and per-player discovery.
##   godot --headless --path . -s tests/test_archipelago.gd

var passed := 0
var total := 0


func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)


func atlas_for(seed: int) -> Array:
	var gen := WorldGen.new(seed, VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ, VoxelWorld.SEA_MID, VoxelWorld.TIDE_AMP)
	var a := IslandAtlas.new()
	a.setup(gen.islands, seed, gen.native.column_height, gen.native.column_island, VoxelWorld.SEA_MID)
	return [gen, a]


## A land column near the island's centre (the centre itself may be a hill or a lagoon).
func land_spot(gen: WorldGen, a: IslandAtlas, idx: int) -> Vector3:
	var c: Vector3 = a.islands[idx].center
	var r: float = a.islands[idx].radius_m
	for ring in 12:
		for k in 16:
			var ang := TAU * k / 16.0
			var p := c + Vector3(cos(ang), 0, sin(ang)) * r * ring / 14.0
			if a.island_at(p) == idx:
				return p
	return Vector3.INF


func _init() -> void:
	print("-- layout and variety")
	var pair := atlas_for(1106)
	var gen: WorldGen = pair[0]
	var a: IslandAtlas = pair[1]
	var types := {}
	var styles := {}
	for isl: Dictionary in gen.islands:
		types[int(isl.type)] = int(types.get(int(isl.type), 0)) + 1
		if int(isl.type) == 1:
			styles[int(isl.style)] = true
	check(int(types.get(0, 0)) == 1, "one home island")
	check(int(types.get(1, 0)) >= 4, "several larger islands (%d)" % int(types.get(1, 0)))
	check(int(types.get(2, 0)) >= 5, "a scatter of islets (%d)" % int(types.get(2, 0)))
	check(styles.size() >= 4, "the larger islands come in different styles (%d)" % styles.size())
	var radii := gen.islands.map(func(i: Dictionary) -> float: return float(i.radius))
	check(radii.max() > radii.min() * 3.0, "island sizes vary widely")
	var apart := true
	for i in gen.islands.size():
		for j in range(i + 1, gen.islands.size()):
			var A: Dictionary = gen.islands[i]
			var B: Dictionary = gen.islands[j]
			if (A.center as Vector2).distance_to(B.center) < (float(A.radius) + float(B.radius)) * 0.6:
				apart = false
	check(apart, "islands don't overlap: there's open sea between them")
	var h0: Dictionary = gen.islands[0]
	var h1: Dictionary = gen.islands[1]
	var mid: Vector2 = ((h0.center as Vector2) + (h1.center as Vector2)) * 0.5
	var sea_between := 0
	for t in 21:
		var p: Vector2 = (h0.center as Vector2).lerp(h1.center, float(t) / 20.0)
		if gen.native.column_height(int(p.x), int(p.y)) < VoxelWorld.SEA_MID - 4:
			sea_between += 1
	check(sea_between >= 3, "sailing from home to the next island crosses open water (%d samples)" % sea_between)
	var other := atlas_for(77)[0] as WorldGen
	check((other.islands[1].center as Vector2).distance_to(gen.islands[1].center) > 1.0, "another seed lays islands out differently")

	print("-- names")
	check(a.islands.size() == gen.islands.size(), "every island gets an entry")
	check(a.name_of(0) == IslandAtlas.HOME_NAME, "the home island is Brine's Hollow")
	var names := {}
	for isl: Dictionary in a.islands:
		names[isl.name] = true
	check(names.size() == a.islands.size(), "every island has its own name")
	var again: IslandAtlas = atlas_for(1106)[1]
	check(again.name_of(3) == a.name_of(3) and again.name_of(9) == a.name_of(9), "names are the same for everyone in a world")
	var other_a: IslandAtlas = atlas_for(77)[1]
	var differ := false
	for i in range(1, mini(other_a.islands.size(), a.islands.size())):
		if other_a.name_of(i) != a.name_of(i):
			differ = true
	check(differ, "a different world names its islands differently")
	var crags := -1
	for i in a.islands.size():
		if int(a.islands[i].style) == 3 and int(a.islands[i].type) == 1:
			crags = i
	check(crags < 0 or (a.name_of(crags).ends_with("Crags") or a.name_of(crags).ends_with("Tors") or a.name_of(crags).ends_with("Scar")),
			"names suit the island (%s)" % a.name_of(crags))
	print("   e.g. ", ", ".join(a.islands.slice(0, 7).map(func(i: Dictionary) -> String: return "%s (%s)" % [i.name, i.style_name])))

	print("-- landfall and discovery")
	var home_spot := land_spot(gen, a, 0)
	check(home_spot != Vector3.INF and a.island_at(home_spot) == 0, "standing on the home island is detected")
	var far_sea := Vector3(5, 0, 5)
	check(a.island_at(far_sea) == -1, "the open sea is no island")
	var ev := a.update(home_spot)
	check(ev.get("new", false) and ev.get("name") == IslandAtlas.HOME_NAME, "first landfall on an island is a discovery")
	check(a.update(home_spot).is_empty(), "walking about on the same island says nothing")
	var spot1 := land_spot(gen, a, 1)
	a.update(far_sea)
	ev = a.update(spot1)
	check(spot1 != Vector3.INF and ev.get("new", false) and ev.get("idx") == 1, "reaching a new island discovers it")
	a.update(far_sea)
	ev = a.update(home_spot)
	check(not ev.is_empty() and not ev.get("new", true), "coming home again names it but isn't a discovery")
	check(a.discovered_count() == 2, "two islands charted")
	var labels := a.chart_labels()
	check(labels.size() == 2 and labels.any(func(l: Dictionary) -> bool: return l.home), "the chart labels discovered islands only")
	var b: IslandAtlas = atlas_for(1106)[1]
	b.deserialize(a.serialize())
	check(b.is_discovered(0) and b.is_discovered(1) and not b.is_discovered(2), "discoveries are saved with the character")
	ev = b.update(spot1)
	check(not ev.get("new", true), "and a reload doesn't rediscover them")

	print("-- layout 2: bigger islands, deeper world")
	check(VoxelWorld.layout == 1 and VoxelWorld.WX == 5632 and VoxelWorld.SEA_MID == 30.0, "worlds default to the original layout")
	var t0 := Time.get_ticks_msec()
	var g1 := WorldGen.new(1106, 5632, 128, 5632, 30.0, VoxelWorld.TIDE_AMP)
	VoxelWorld.apply_layout(2)
	check(VoxelWorld.WX == 14336 and VoxelWorld.WY == 256 and VoxelWorld.SEA_MID == 64.0, "layout 2 is 2.6 km across and 46 m tall")
	var g2 := WorldGen.new(1106, VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ, VoxelWorld.SEA_MID, VoxelWorld.TIDE_AMP, VoxelWorld.layout_params(2))
	print("   layout 2 configure: %d ms" % (Time.get_ticks_msec() - t0))
	var a2 := IslandAtlas.new()
	a2.setup(g2.islands, 1106, g2.native.column_height, g2.native.column_island, VoxelWorld.SEA_MID)
	# Land extent of the home island along 8 rays from its centre.
	var hc: Vector2 = g2.islands[0].center
	var reach := 0.0
	for k in 8:
		var dir := Vector2.from_angle(TAU * k / 8.0)
		var last_land := 0.0
		for s in range(0, 4000, 8):
			var p := hc + dir * s
			if g2.native.column_height(int(p.x), int(p.y)) >= VoxelWorld.SEA_MID and g2.native.column_island(int(p.x), int(p.y)) == 0:
				last_land = s
		reach += last_land / 8.0
	var across_m := reach * 2.0 * VoxelWorld.VS
	check(across_m > 600.0 and across_m < 800.0, "the home island is ~700 m across (%d m)" % int(across_m))
	var t2 := g2.islands.filter(func(i: Dictionary) -> bool: return int(i.type) == 1)
	var t1 := g1.islands.filter(func(i: Dictionary) -> bool: return int(i.type) == 1)
	var avg := func(arr: Array) -> float: return arr.reduce(func(acc: float, i: Dictionary) -> float: return acc + float(i.radius), 0.0) / maxf(1.0, arr.size())
	check(float(avg.call(t2)) > float(avg.call(t1)) * 1.4, "the other islands are larger too (%d vs %d voxels)" % [int(avg.call(t2)), int(avg.call(t1))])
	check(t2.size() >= 6, "and there are more of them to find (%d)" % t2.size())
	var top1 := 0
	var top2 := 0
	for z in range(0, 5632, 23):
		for x in range(0, 5632, 23):
			top1 = maxi(top1, g1.native.column_height(x, z))
	for z in range(0, 14336, 41):
		for x in range(0, 14336, 41):
			top2 = maxi(top2, g2.native.column_height(x, z))
	check(float(top2 - 64) > float(top1 - 30) * 1.5, "the land stands much taller above the sea (%d vs %d voxels)" % [top2 - 64, top1 - 30])
	check(top2 < VoxelWorld.WY - 10, "and still fits under the sky (%d of %d)" % [top2, VoxelWorld.WY])
	var floor2 := g2.native.column_height(40, 40)
	check(floor2 >= 64 - 26 and floor2 <= 64 - 16, "the open sea is as deep as before, with rock under it (%d)" % floor2)
	check(a2.name_of(0) == IslandAtlas.HOME_NAME and a2.islands.size() == g2.islands.size(), "islands are named in the big layout too")
	var spot := land_spot(g2, a2, 1)
	check(spot != Vector3.INF and a2.update(spot).get("new", false), "and landfall works there")
	g2.plan_starter()
	check(not g2.starter.is_empty(), "the starter hut and dock find a site on the big home island")
	VoxelWorld.apply_layout(1)
	check(VoxelWorld.WX == 5632 and VoxelWorld.WY == 128 and VoxelWorld.SEA_MID == 30.0, "switching back restores layout 1")

	print("Archipelago suite: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)
