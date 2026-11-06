extends SceneTree
## Automated headless test suite for Brine's Hollow Randomized Starter Island Spawns.

func _init() -> void:
	print("==================================================")
	print("Running Brine's Hollow Randomized Spawns Tests...")
	print("==================================================")

	var stats := [0, 0] # [passed, total]

	var assert_test := func(desc: String, condition: bool) -> void:
		stats[1] += 1
		if condition:
			stats[0] += 1
			print("  [PASS] %s" % desc)
		else:
			push_error("  [FAIL] %s" % desc)

	var gen := WorldGen.new(1106, VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ, VoxelWorld.SEA_MID, VoxelWorld.TIDE_AMP)
	gen.plan_starter()

	# -------------------------------------------------------------------------
	# 1. Multiple Starter Spawns Population
	# -------------------------------------------------------------------------
	assert_test.call("starter_spawns array is populated", not gen.starter_spawns.is_empty())
	assert_test.call("starter_spawns contains at least 8 diverse coastal sites", gen.starter_spawns.size() >= 8)

	var home: Dictionary = gen.islands[0]
	var hc: Vector2 = home.center
	var hr: float = home.radius

	# -------------------------------------------------------------------------
	# 2. Validation of Each Spawn Location
	# -------------------------------------------------------------------------
	var all_valid_coords := true
	var all_above_tide := true
	var all_on_starter_island := true
	var has_unique_names := true
	var names_seen: Dictionary = {}

	for s: Dictionary in gen.starter_spawns:
		if not s.has("pos") or not s.has("yaw") or not s.has("name") or not s.has("id"):
			all_valid_coords = false
		if s.pos.y < gen.sea_high:
			all_above_tide = false
		var d_center: float = (Vector2(s.pos.x, s.pos.z) - hc).length()
		if d_center > hr * 0.85:
			all_on_starter_island = false
		names_seen[s.name] = true

	assert_test.call("All starter spawns have id, name, pos, and yaw", all_valid_coords)
	assert_test.call("All starter spawns are safely above high tide", all_above_tide)
	assert_test.call("All starter spawns reside on the starter island footprint", all_on_starter_island)
	assert_test.call("Starter spawns have diverse named coastal landmarks", names_seen.size() >= 6)

	# -------------------------------------------------------------------------
	# 3. Distance Spread & Independence
	# -------------------------------------------------------------------------
	var max_dist_m := 0.0
	var primary_pos: Vector3 = gen.starter_spawns[0].pos
	for i in range(1, gen.starter_spawns.size()):
		var p: Vector3 = gen.starter_spawns[i].pos
		var dist_m: float = (Vector2(p.x, p.z) - Vector2(primary_pos.x, primary_pos.z)).length() * VoxelWorld.VS
		if dist_m > max_dist_m:
			max_dist_m = dist_m

	assert_test.call("Spawn points span across starter island with > 150m maximum spread", max_dist_m > 150.0)

	# -------------------------------------------------------------------------
	# 4. Multi-peer Distribution (Players can play apart)
	# -------------------------------------------------------------------------
	var p1_spawn: Dictionary = gen.get_spawn_for_player(1) # Host
	var p2_spawn: Dictionary = gen.get_spawn_for_player(2) # Peer 2
	var p3_spawn: Dictionary = gen.get_spawn_for_player(3) # Peer 3
	var p4_spawn: Dictionary = gen.get_spawn_for_player(4) # Peer 4

	assert_test.call("Player 1 gets valid spawn", not p1_spawn.is_empty())
	assert_test.call("Player 2 gets different spawn from Player 1", p2_spawn.id != p1_spawn.id)
	assert_test.call("Player 3 gets different spawn from Player 2", p3_spawn.id != p2_spawn.id)
	assert_test.call("Player 4 gets different spawn from Player 3", p4_spawn.id != p3_spawn.id)

	var p1_p2_dist_m: float = (Vector2(p1_spawn.pos.x, p1_spawn.pos.z) - Vector2(p2_spawn.pos.x, p2_spawn.pos.z)).length() * VoxelWorld.VS
	assert_test.call("Player 1 and Player 2 are separated by > 50m of coastline", p1_p2_dist_m > 50.0)

	# -------------------------------------------------------------------------
	# 5. Randomizer & Determinism
	# -------------------------------------------------------------------------
	var rand1: Dictionary = gen.get_random_spawn(42)
	var rand2: Dictionary = gen.get_random_spawn(42)
	assert_test.call("get_random_spawn with identical seed is deterministic", rand1.id == rand2.id and rand1.pos == rand2.pos)

	var rand3: Dictionary = gen.get_random_spawn(999)
	assert_test.call("get_random_spawn selects valid spawn within bounds", rand3.id >= 0 and rand3.id < gen.starter_spawns.size())

	# Index accessor wrapping
	var wrap_spawn: Dictionary = gen.get_spawn_by_index(gen.starter_spawns.size() + 2)
	assert_test.call("get_spawn_by_index wraps safely with modulo", wrap_spawn.id == 2)

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	if stats[0] == stats[1]:
		quit(0)
	else:
		quit(1)
