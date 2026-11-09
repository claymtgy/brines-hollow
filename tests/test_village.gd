extends SceneTree
## Headless test suite for Brine's Hollow Village, Housing & Settlement Management:
##   godot --headless --path . -s tests/test_village.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("==================================================")
	print("Running Brine's Hollow Village & Housing Tests...")
	print("==================================================")

	var stats := [0, 0] # [passed, total]

	var assert_test := func(desc: String, condition: bool) -> void:
		stats[1] += 1
		if condition:
			stats[0] += 1
			print("  [PASS] ", desc)
		else:
			push_error("  [FAIL] " + desc)
			print("  [FAIL] ", desc)

	ItemDB.init_db()

	# -------------------------------------------------------------------------
	# Helper: Mock Voxel World (a 3D dictionary of voxels)
	# -------------------------------------------------------------------------
	var voxels: Dictionary = {} # Vector3i -> int

	var query_voxel := func(p: Vector3i) -> int:
		return voxels.get(p, 0) # 0 = Air

	# Helper to build a hollow box room
	var build_room := func(
		min_p: Vector3i,
		max_p: Vector3i,
		wall_mat: int,
		add_door: bool,
		add_bed: bool,
		add_light: bool,
		has_roof: bool
	) -> void:
		voxels.clear()
		for x in range(min_p.x, max_p.x + 1):
			for y in range(min_p.y, max_p.y + 1):
				for z in range(min_p.z, max_p.z + 1):
					var is_x_wall: bool = (x == min_p.x or x == max_p.x)
					var is_y_wall: bool = (y == min_p.y or y == max_p.y)
					var is_z_wall: bool = (z == min_p.z or z == max_p.z)

					# Ceiling / Roof
					if y == max_p.y:
						if has_roof:
							voxels[Vector3i(x, y, z)] = wall_mat
						continue

					# Floor or Walls
					if is_x_wall or is_y_wall or is_z_wall:
						voxels[Vector3i(x, y, z)] = wall_mat

		var inside_min := min_p + Vector3i(1, 1, 1)
		var center := (min_p + max_p) / 2

		# Add Fixtures
		if add_door:
			# Place door in the center of the wall
			voxels[Vector3i(min_p.x, inside_min.y, center.z)] = RoomDetector.V_DOOR
		if add_bed:
			# Place bed in the corner
			voxels[Vector3i(max_p.x - 1, inside_min.y, max_p.z - 1)] = RoomDetector.V_BED
		if add_light:
			# Hang lantern from ceiling center
			voxels[Vector3i(center.x, max_p.y - 1, center.z)] = RoomDetector.V_LIGHT

	# -------------------------------------------------------------------------
	# 1. RoomDetector 3D Flood-Fill Tests
	# -------------------------------------------------------------------------
	var r_min := Vector3i(10, 10, 10)
	var r_max := Vector3i(14, 13, 14) # Interior is 3 x 2 x 3 = 18 air voxels
	var inside_center := Vector3i(12, 11, 12)

	# Case 1: Valid Complete Room
	build_room.call(r_min, r_max, Palette.PLANK, true, true, true, true)
	var res1: RoomDetector.RoomValidationResult = RoomDetector.validate_room(inside_center, query_voxel)
	assert_test.call("Enclosed room with bed, door, and lantern is valid", res1.is_valid)
	assert_test.call("Room interior air volume is 16 voxels", res1.volume == 16)
	assert_test.call("Room quality score is >= 10", res1.quality_score >= 10)

	# Case 2: Missing Bed
	build_room.call(r_min, r_max, Palette.PLANK, true, false, true, true)
	var res2: RoomDetector.RoomValidationResult = RoomDetector.validate_room(inside_center, query_voxel)
	assert_test.call("Room missing bed is invalid", not res2.is_valid and not res2.has_bed)

	# Case 3: Missing Light
	build_room.call(r_min, r_max, Palette.PLANK, true, true, false, true)
	var res3: RoomDetector.RoomValidationResult = RoomDetector.validate_room(inside_center, query_voxel)
	assert_test.call("Room missing light is invalid", not res3.is_valid and not res3.has_light)

	# Case 4: Missing Roof (Open Sky Leak)
	build_room.call(r_min, r_max, Palette.PLANK, true, true, true, false)
	var res4: RoomDetector.RoomValidationResult = RoomDetector.validate_room(inside_center, query_voxel)
	assert_test.call("Room missing roof leaks and is invalid", not res4.is_valid and not res4.has_roof)

	# -------------------------------------------------------------------------
	# 2. SettlementManager & Housing Registration
	# -------------------------------------------------------------------------
	build_room.call(r_min, r_max, Palette.PLANK, true, true, true, true)
	var town := SettlementManager.new(Vector3i(0, 30, 0), "Hollow Bay")
	assert_test.call("Town starts at CAMP tier", town.current_tier == SettlementManager.TownTier.CAMP)

	var room_id_0: int = town.validate_and_register_room(inside_center, query_voxel)
	assert_test.call("Registered valid room with id=0", room_id_0 == 0 and town.rooms.size() == 1)

	# -------------------------------------------------------------------------
	# 3. Drifter Recruitment & Room Comfort Boost
	# -------------------------------------------------------------------------
	var fisher := DrifterDef.new(&"drifter_sam", "Old Sam", DrifterDef.Profession.FISHER)
	var initial_morale := fisher.morale

	assert_test.call("Recruited Drifter Fisher", town.recruit_drifter(fisher))
	assert_test.call("Fisher auto-assigned to vacant room 0", fisher.assigned_room_id == 0)
	assert_test.call("Assigned housing boosted drifter morale", fisher.morale > initial_morale)

	# -------------------------------------------------------------------------
	# 4. Town Tier Progression
	# -------------------------------------------------------------------------
	# Add 2 more rooms (total 3 rooms)
	town.rooms.append({"id": 1, "center": Vector3i(20, 11, 20), "assigned_drifter_id": &""})
	town.rooms.append({"id": 2, "center": Vector3i(30, 11, 30), "assigned_drifter_id": &""})

	# Recruit 3 more drifters (total 4 drifters with 3 rooms -> HAMLET tier)
	town.recruit_drifter(DrifterDef.new(&"drifter_carpenter", "Sawyer", DrifterDef.Profession.CARPENTER))
	town.recruit_drifter(DrifterDef.new(&"drifter_farmer", "Mallow", DrifterDef.Profession.FARMER))
	town.recruit_drifter(DrifterDef.new(&"drifter_cook", "Barnaby", DrifterDef.Profession.SMOKER_CHEF))
	assert_test.call("Without a Tide Hearth the town stays a camp",
		town.current_tier == SettlementManager.TownTier.CAMP)
	town.found_at(Vector3i(10, 11, 10))

	assert_test.call("Settlement upgraded to HAMLET tier with 4 villagers and 3 homes",
		town.current_tier == SettlementManager.TownTier.HAMLET)
	assert_test.call("Municipal territory radius expanded to 100m", town.territory_radius_m == 100.0)

	# -------------------------------------------------------------------------
	# 5. Automated Town Depot & Production Chores
	# -------------------------------------------------------------------------
	var carpenter: DrifterDef = town.get_drifter(&"drifter_carpenter")
	assert_test.call("Retrieved carpenter drifter", carpenter != null)

	# Stock depot with 2 raw driftwood
	town.town_depot.deposit(&"driftwood", 2)
	assert_test.call("Town depot stocked with 2 driftwood", town.town_depot.inventory.get_item_count(&"driftwood") == 2)

	# Simulate 1 hour of morning work shift (day_fraction = 0.4)
	# Carpenter work cycle ticks every 60 seconds
	carpenter.current_routine = DrifterDef.Routine.WORK
	var yield_items: Dictionary = carpenter.tick_work(70.0, town.town_depot)

	assert_test.call("Carpenter consumed 1 driftwood and produced 4 wood planks",
		yield_items.get(&"wood_plank", 0) == 4 and
		town.town_depot.inventory.get_item_count(&"wood_plank") == 4 and
		town.town_depot.inventory.get_item_count(&"driftwood") == 1)

	# -------------------------------------------------------------------------
	# 6. SettlementManager Serialization Roundtrip
	# -------------------------------------------------------------------------
	var town_save := town.serialize()
	var loaded_town := SettlementManager.new()
	loaded_town.deserialize(town_save)

	assert_test.call("SettlementManager deserialized tier matches HAMLET",
		loaded_town.current_tier == SettlementManager.TownTier.HAMLET)
	assert_test.call("Deserialized drifters count is 4", loaded_town.drifters.size() == 4)
	assert_test.call("Deserialized depot retains wood planks",
		loaded_town.town_depot.inventory.get_item_count(&"wood_plank") == 4)

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	quit(0 if stats[0] == stats[1] else 1)
