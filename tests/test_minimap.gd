extends SceneTree
## Automated headless test suite for Brine's Hollow Diegetic Nautical Minimap & Charts.

func _init() -> void:
	print("==================================================")
	print("Running Brine's Hollow Minimap & Chart Tests...")
	print("==================================================")

	var stats := [0, 0] # [passed, total]

	var assert_test := func(desc: String, condition: bool) -> void:
		stats[1] += 1
		if condition:
			stats[0] += 1
			print("  [PASS] %s" % desc)
		else:
			push_error("  [FAIL] %s" % desc)

	ItemDB.init_db()

	var mm := Minimap.new()
	assert_test.call("Minimap instantiates cleanly", mm != null)
	assert_test.call("Initial chart tier is 0", mm.chart_tier == 0)

	# -------------------------------------------------------------------------
	# 1. Equipment-Gated Visibility & Tier 0
	# -------------------------------------------------------------------------
	mm.update_state(0, "", Vector3(100, 10, 100), 0.0, 14.0)
	assert_test.call("Minimap is hidden when chart_tier is 0", not mm.visible)

	# -------------------------------------------------------------------------
	# 2. Tier 1: Parchment Shore Chart (Coastline & Compass)
	# -------------------------------------------------------------------------
	mm.update_state(1, "Parchment Shore Chart", Vector3(207, 12, 207), 0.0, 14.0)
	assert_test.call("Minimap becomes visible with Tier 1 chart", mm.visible)
	assert_test.call("Tier is 1", mm.chart_tier == 1)
	assert_test.call("Bearing facing north (yaw=0) is N", mm._get_compass_bearing(0.0) == "N")
	assert_test.call("Bearing facing east (yaw=-PI/2) is E", mm._get_compass_bearing(-PI * 0.5) == "E")
	assert_test.call("Bearing facing south (yaw=PI) is S", mm._get_compass_bearing(PI) == "S")
	assert_test.call("Bearing facing west (yaw=PI/2) is W", mm._get_compass_bearing(PI * 0.5) == "W")

	# -------------------------------------------------------------------------
	# 3. Tier 2: Hydrographic Sea Chart (Depth Soundings & Boats)
	# -------------------------------------------------------------------------
	var boat_pos := Vector3(220, 14, 180)
	mm.update_state(
		2,
		"Hydrographic Sea Chart",
		Vector3(200, 8, 200),
		0.0,
		14.0, # water_level = 14.0m, player y = 8.0m -> depth 6.0m
		[],
		[boat_pos]
	)
	assert_test.call("Tier 2 activates", mm.chart_tier == 2)
	assert_test.call("Depth sounding calculates 6.0m depth", is_equal_approx(mm.depth_sounding, 6.0))
	assert_test.call("Boats list contains 1 boat", mm.boats.size() == 1)

	# -------------------------------------------------------------------------
	# 4. Tier 3: Master Chronometer Chart (Landmarks & Peers)
	# -------------------------------------------------------------------------
	var mock_landmarks: Array[Dictionary] = [
		{"name": "Homestead Pier", "pos": Vector3(207, 14, 207)},
		{"name": "East Shingle Beach", "pos": Vector3(350, 14, 207)}
	]
	var mock_peers: Array[Vector3] = [Vector3(150, 15, 250)]

	mm.update_state(
		3,
		"Master Chronometer Chart",
		Vector3(207, 15, 207),
		0.0,
		14.0,
		mock_landmarks,
		[boat_pos],
		mock_peers
	)
	assert_test.call("Tier 3 activates", mm.chart_tier == 3)
	assert_test.call("Landmarks registered (count = 2)", mm.landmarks.size() == 2)
	assert_test.call("Peer positions registered (count = 1)", mm.peer_positions.size() == 1)

	# -------------------------------------------------------------------------
	# 5. Coordinate Projection Math
	# -------------------------------------------------------------------------
	var center_world := Vector3(mm.world_size_m.x * 0.5, 0, mm.world_size_m.y * 0.5)
	var map_center := Vector2(95, 105)
	var projected_center := mm._world_to_minimap(center_world, map_center, 80.0)
	assert_test.call("Island world center maps directly to minimap center", projected_center.is_equal_approx(map_center))

	var east_world := Vector3(mm.world_size_m.x, 0, mm.world_size_m.y * 0.5)
	var projected_east := mm._world_to_minimap(east_world, map_center, 80.0)
	assert_test.call("East island boundary projects to right edge", is_equal_approx(projected_east.x, map_center.x + 80.0))

	# -------------------------------------------------------------------------
	# 6. Unequipping Closes Minimap
	# -------------------------------------------------------------------------
	mm.update_state(0, "", Vector3(207, 15, 207), 0.0, 14.0)
	assert_test.call("Unequipping chart sets minimap invisible", not mm.visible)

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	if stats[0] == stats[1]:
		print("ALL MINIMAP TESTS PASSED!")
		quit(0)
	else:
		push_error("SOME TESTS FAILED!")
		quit(1)
