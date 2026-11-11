extends SceneTree
## Stranded drifters are spread along the home island's shore, not crowded round the starter hut.

var counts := {"total": 0, "passed": 0}


func check(name: String, cond: bool) -> void:
	counts.total += 1
	if cond:
		counts.passed += 1
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)


func _init() -> void:
	print("\n== Drifter spread ==")
	for layout in [2, 1]:
		VoxelWorld.apply_layout(layout)
		for seed in [1106, 42, 7, 90210]:
			var gen := WorldGen.new(seed, VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ, VoxelWorld.SEA_MID,
					VoxelWorld.TIDE_AMP, VoxelWorld.layout_params(layout))
			gen.plan_starter()
			if gen.starter.is_empty():
				continue
			var hut: Vector3i = gen.starter.hut
			var spots := VillageManager.roster_spots(gen)
			var tag := "layout %d seed %d" % [layout, seed]
			var near_hut := 999.0
			var min_gap := 999.0
			var on_land := true
			var on_home := true
			var home: Dictionary = gen.islands[0]
			var dists: Array[String] = []
			for i in spots.size():
				var s: Vector3i = spots[i]
				var d := Vector2(s.x - hut.x, s.z - hut.z).length() * VoxelWorld.VS
				dists.append("%d" % int(d))
				near_hut = minf(near_hut, d)
				if Vector2(s.x, s.z).distance_to(home.center) > float(home.radius) * 1.15:
					on_home = false
				if gen.col_h(s.x, s.z) < gen.sea_high or s.y != gen.col_h(s.x, s.z) + 1:
					on_land = false
				for j in i:
					var t: Vector3i = spots[j]
					min_gap = minf(min_gap, Vector2(s.x - t.x, s.z - t.z).length() * VoxelWorld.VS)
			print("    %s: metres from hut %s, closest pair %d m" % [tag, ", ".join(dists), int(min_gap)])
			check("%s: one per roster drifter" % tag, spots.size() == VillageManager.ROSTER.size())
			check("%s: nobody within 30 m of the hut" % tag, near_hut >= 30.0)
			check("%s: drifters at least 35 m apart" % tag, min_gap >= 35.0)
			check("%s: all standing on land above high tide" % tag, on_land)
			check("%s: all on the home island (radius %d m)" % [tag, int(float(home.radius) * VoxelWorld.VS)], on_home)
			var first: Vector3i = spots[0]
			var d0 := Vector2(first.x - hut.x, first.z - hut.z).length() * VoxelWorld.VS
			check("%s: first drifter findable (under 90 m)" % tag, d0 <= 90.0)
			check("%s: same spots every time" % tag, VillageManager.roster_spots(gen) == spots)
	VoxelWorld.apply_layout(2)
	print("Results: %d/%d passed" % [counts.passed, counts.total])
	quit(0 if counts.passed == counts.total else 1)
