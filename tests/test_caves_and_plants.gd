extends SceneTree
## Cave systems (tidal sea caves, karst caverns, ore veins) in the big archipelago, and
## flowers / grass tufts as walk-through plants.
##   godot --headless --path . -s tests/test_caves_and_plants.gd

var passed := 0
var total := 0


func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)


func make_gen(layout: int, seed: int = 1106) -> WorldGen:
	VoxelWorld.apply_layout(layout)
	return WorldGen.new(seed, VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ, VoxelWorld.SEA_MID,
			VoxelWorld.TIDE_AMP, VoxelWorld.layout_params(layout))


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


## Flood the cave's air from `start`; true once it reaches open air above the land or sea.
func reaches_outside(s: VoxelStore, gen: WorldGen, start: Vector3i, limit: int) -> Array:
	var seen := {start: true}
	var q: Array[Vector3i] = [start]
	var head := 0
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	while head < q.size() and head < limit:
		var c: Vector3i = q[head]
		head += 1
		if c.y > gen.col_h(c.x, c.z) + 1:
			return [true, head]
		for d: Vector3i in dirs:
			var n: Vector3i = c + d
			if seen.has(n) or n.y < 1 or n.y >= VoxelWorld.WY - 1:
				continue
			var m := vox(s, n.x, n.y, n.z)
			if m != 0 and not Palette.is_plant(m):
				continue
			seen[n] = true
			q.append(n)
	return [false, head]


func _init() -> void:
	VoxelWorld.push_palette()

	print("-- classic worlds have no new caves")
	var g1 := make_gen(1)
	check(g1.cave_sites().is_empty(), "layout 1 plans no cave systems")
	var tufts := 0
	var flowers := 0
	var gh: Vector2 = g1.islands[0].center
	for col in [Vector2i(int(gh.x) >> 5, int(gh.y) >> 5), Vector2i((int(gh.x) >> 5) + 3, (int(gh.y) >> 5) - 2)]:
		var layers: Array = g1.native.generate_column_debug(col.x, col.y)
		for l: PackedByteArray in layers:
			for b in l:
				if b == Palette.TUFT_GRASS or b == Palette.TUFT_DRY:
					tufts += 1
				elif b == Palette.FLOWER_Y or b == Palette.FLOWER_P:
					flowers += 1
	check(tufts > 0, "grass tufts are their own plant material now (%d, %d flowers)" % [tufts, flowers])

	print("-- the big archipelago's caves")
	var g := make_gen(2)
	var sites: Array = g.cave_sites()
	var kinds := {}
	for s: Dictionary in sites:
		kinds[int(s.kind)] = int(kinds.get(int(s.kind), 0)) + 1
	print("   %d cave systems: %d tidal, %d karst" % [sites.size(), int(kinds.get(0, 0)), int(kinds.get(1, 0))])
	check(int(kinds.get(0, 0)) >= 5, "tidal sea caves in the cliffs of several islands")
	check(int(kinds.get(1, 0)) >= 3, "karst caverns under the high ground")
	var islands_with := {}
	for s: Dictionary in sites:
		islands_with[int(s.island)] = true
	check(islands_with.has(0), "the home island has caves of its own")
	check(islands_with.size() >= 4, "and so do other islands (%d)" % islands_with.size())

	var st := make_store(g)
	var air_ok := 0
	var exits := 0
	var sand_floors := 0
	var tidal_floor_ok := 0
	var roofed := 0
	var ores := {Palette.COPPER_VEIN: 0, Palette.IRON_VEIN: 0}
	var glow := 0
	var stalactites := 0
	var t0 := Time.get_ticks_msec()
	for s: Dictionary in sites:
		var p: Vector3i = s.pos
		if vox(st, p.x, p.y, p.z) == 0:
			air_ok += 1
		# floor under the chest spot
		var fy := p.y
		while fy > 1 and vox(st, p.x, fy - 1, p.z) == 0:
			fy -= 1
		var floor_m := vox(st, p.x, fy - 1, p.z)
		if int(s.kind) == 0:
			if floor_m == Palette.SAND or floor_m == Palette.GRAVEL or floor_m == Palette.COPPER_VEIN or floor_m == Palette.IRON_VEIN or floor_m == Palette.GLOW_TEAL:
				sand_floors += 1
			if fy >= int(VoxelWorld.SEA_MID - VoxelWorld.TIDE_AMP) and fy <= int(VoxelWorld.SEA_MID + VoxelWorld.TIDE_AMP) + 2:
				tidal_floor_ok += 1
		else:
			var cy := p.y
			while cy < VoxelWorld.WY - 1 and vox(st, p.x, cy, p.z) == 0:
				cy += 1
			if cy < g.col_h(p.x, p.z) - 3:
				roofed += 1
		var res := reaches_outside(st, g, p, 400000)
		if res[0]:
			exits += 1
		else:
			print("   no way out: kind %d island %d at %s (flooded %d voxels)" % [int(s.kind), int(s.island), p, int(res[1])])
		# walls around the site
		for dz in range(-24, 25, 1):
			for dx in range(-24, 25, 1):
				for dy in range(-14, 16):
					var m := vox(st, p.x + dx, p.y + dy, p.z + dz)
					if ores.has(m):
						ores[m] += 1
					elif m == Palette.GLOW_TEAL:
						glow += 1
	# hanging stone: stone with air on both sides and below, under a chamber roof
	for s: Dictionary in sites:
		if int(s.kind) != 1:
			continue
		var p: Vector3i = s.pos
		for dz in range(-12, 13):
			for dx in range(-12, 13):
				for y in range(p.y, p.y + 14):
					if vox(st, p.x + dx, y, p.z + dz) == Palette.STONE and vox(st, p.x + dx, y - 1, p.z + dz) == 0 \
							and vox(st, p.x + dx + 1, y, p.z + dz) == 0 and vox(st, p.x + dx - 1, y, p.z + dz) == 0:
						stalactites += 1
	print("   cave scan: %d ms" % (Time.get_ticks_msec() - t0))
	check(air_ok == sites.size(), "every chest spot is open air inside its cave (%d/%d)" % [air_ok, sites.size()])
	check(exits == sites.size(), "every cave has a way out to the open air or sea (%d/%d)" % [exits, sites.size()])
	check(sand_floors >= int(kinds.get(0, 0)) - 1, "tidal grottos have sandy floors (%d/%d)" % [sand_floors, int(kinds.get(0, 0))])
	check(tidal_floor_ok == int(kinds.get(0, 0)), "and the high tide reaches into them (%d/%d)" % [tidal_floor_ok, int(kinds.get(0, 0))])
	check(roofed == int(kinds.get(1, 0)), "karst caverns are under solid rock (%d/%d)" % [roofed, int(kinds.get(1, 0))])
	check(int(ores[Palette.COPPER_VEIN]) > 20 and int(ores[Palette.IRON_VEIN]) > 10,
			"copper and iron veins line the cave walls (%d copper, %d iron voxels)" % [ores[Palette.COPPER_VEIN], ores[Palette.IRON_VEIN]])
	check(glow > 20, "with glowing moss (%d)" % glow)
	check(stalactites > 5, "karst chambers have stalactites (%d hanging stones)" % stalactites)

	print("-- cave generation is a pure function of the seed")
	var p0: Vector3i = sites[0].pos
	var a: Array = g.native.generate_column_debug(p0.x >> 5, p0.z >> 5)
	var g_again := make_gen(2)
	var b: Array = g_again.native.generate_column_debug(p0.x >> 5, p0.z >> 5)
	check(hash(str(a)) == hash(str(b)), "the same cave column comes out identical on every peer")
	g.plan_starter()
	var hut: Vector3i = g.starter.get("hut", Vector3i.ZERO)
	check(not g.starter.is_empty() and not g.native.cave_near(hut.x, hut.z, 20), "the starter hut is built away from the caves")

	print("-- flowers and grass are walk-through plants")
	VoxelWorld.apply_layout(1)
	var ps := VoxelStore.new()
	ps.setup(Vector3i(64, 64, 64), VoxelWorld.VS)
	for x in range(0, 8):
		for z in range(0, 8):
			ps.set_voxel(x, 10, z, Palette.GRASS)
	ps.set_voxel(2, 11, 2, Palette.TUFT_GRASS)
	ps.set_voxel(2, 12, 2, Palette.TUFT_DRY)
	ps.set_voxel(4, 11, 4, Palette.FLOWER_Y)
	var vs := VoxelWorld.VS
	var cell := func(x: int, y: int, z: int) -> Array: return [Vector3(x + 0.1, y + 0.1, z + 0.1) * vs, Vector3(x + 0.9, y + 0.9, z + 0.9) * vs]
	var c1: Array = cell.call(2, 11, 2)
	var c2: Array = cell.call(4, 11, 4)
	var c3: Array = cell.call(2, 10, 2)
	check(not ps.aabb_collides(c1[0], c1[1]) and not ps.aabb_collides(c2[0], c2[1]), "you walk straight through grass and flowers")
	check(ps.aabb_collides(c3[0], c3[1]), "but the ground under them is still solid")
	var hit: Dictionary = ps.raycast(Vector3(2.5, 20, 2.5) * vs, Vector3.DOWN, 10.0, false)
	check(not hit.is_empty() and hit.cell == Vector3i(2, 10, 2), "looking down past a tuft finds the ground (hit %s)" % [hit.get("cell")])
	var mesh: Array = ps.mesh_chunk(Vector3i(0, 0, 0))
	var verts: PackedVector3Array = (mesh[0] as Array)[Mesh.ARRAY_VERTEX]
	var tall := 0
	for v in verts:
		# plant sprites stand inside the voxel above the ground (not on its faces)
		if v.y > 11.05 * vs and v.y < 12.95 * vs:
			tall += 1
	check(tall >= 8, "plants are drawn as little crossed sprites (%d sprite verts)" % tall)
	var ground_top := 0
	for v in verts:
		if is_equal_approx(v.y, 11.0 * vs):
			ground_top += 1
	check(ground_top >= 4, "and the grass top under them still renders")
	check(ps.place_sphere(Vector3i(4, 11, 4), 0, Palette.PLANK) == 1 and ps.get_voxel(4, 11, 4) == Palette.PLANK,
			"placing a block where a flower grows replaces it")
	ps.set_voxel(2, 10, 2, 0)
	check(ps.get_voxel(2, 11, 2) == 0 and ps.get_voxel(2, 12, 2) == 0, "digging out the ground takes the tufts on it too")
	check(Palette.is_plant(Palette.FLOWER_P) and Palette.is_foliage(Palette.TUFT_DRY) and not Palette.is_plant(Palette.GRASS),
			"flowers and tufts are plants; grass blocks are not")

	print("Caves and plants suite: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)
