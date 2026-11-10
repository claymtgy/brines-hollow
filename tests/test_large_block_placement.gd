extends SceneTree

var total_tests := 0
var passed_tests := 0

func check(cond: bool, msg: String) -> void:
	total_tests += 1
	if cond:
		passed_tests += 1
		print("  [PASS] %s" % msg)
	else:
		printerr("  [FAIL] %s" % msg)

func _initialize() -> void:
	print("\n==================================================")
	print("Running Large Block Placement Test Suite...")
	print("==================================================")

	var cm := ControllerManager.new()
	cm.setup_input_map()
	ItemDB.init_db()

	# -------------------------------------------------------------------------
	# 1. Test Brush Size Preservation & Cycling
	# -------------------------------------------------------------------------
	print("\n-- 1. Brush Size Preservation & Cycling")
	var player := Player.new()
	player.rig = CameraRig.new()
	player.rig.cam = Camera3D.new()
	player.rig.add_child(player.rig.cam)
	player.add_child(player.rig)

	check(player.brush == 0, "Initial player brush is 0 (1x1)")
	check(Player.BRUSHES.size() == 5, "BRUSHES array has 5 sizes (0, 1, 2, 3, 5)")

	# Cycle through all brush sizes
	player.cycle_brush_size()
	check(player.brush == 1, "cycle_brush_size advanced brush to 1 (3x3, r=1)")
	player.cycle_brush_size()
	check(player.brush == 2, "cycle_brush_size advanced brush to 2 (5x5, r=2)")
	player.cycle_brush_size()
	check(player.brush == 3, "cycle_brush_size advanced brush to 3 (7x7, r=3)")
	player.cycle_brush_size()
	check(player.brush == 4, "cycle_brush_size advanced brush to 4 (11x11, r=5)")
	player.cycle_brush_size()
	check(player.brush == 0, "cycle_brush_size wrapped back to 0 (1x1)")

	# Set brush to 2 (5x5) and test that syncing tool from hotbar preserves it
	player.brush = 2
	player.inventory.add_item(&"dirt", 20)
	player.inventory.set_active_hotbar_index(0)
	player._sync_tool_from_hotbar()

	check(player.tool == 1, "Tool is 1 (block placement) when holding Dirt")
	check(player.brush == 2, "Brush size 2 (5x5) is preserved when syncing Dirt from hotbar")

	# Add stone and switch hotbar slot to Stone
	player.inventory.add_item(&"stone", 20)
	player.inventory.set_active_hotbar_index(1)
	player._sync_tool_from_hotbar()

	check(player.tool == 1, "Tool is 1 (block placement) when switching to Stone")
	check(player.brush == 2, "Brush size 2 (5x5) is preserved when switching from Dirt to Stone")

	# -------------------------------------------------------------------------
	# 2. Test Input Event Handling for Brush Resizing
	# -------------------------------------------------------------------------
	print("\n-- 2. Input Event Handling for Brush Resizing")
	# Create alt_use event (Right-click / LT) while holding blocks directly
	var ev_alt := InputEventAction.new()
	ev_alt.action = &"alt_use"
	ev_alt.pressed = true
	player._unhandled_input(ev_alt)
	check(player.brush == 3, "Pressing alt_use (RMB) when holding Dirt/Stone cycles brush size to 3 (7x7)")

	# Test brush_up and brush_down actions
	var ev_up := InputEventAction.new()
	ev_up.action = &"brush_up"
	ev_up.pressed = true
	player._unhandled_input(ev_up)
	check(player.brush == 4, "Pressing brush_up (X / D-Pad Up) sets brush to 4 (11x11)")

	var ev_down := InputEventAction.new()
	ev_down.action = &"brush_down"
	ev_down.pressed = true
	player._unhandled_input(ev_down)
	check(player.brush == 3, "Pressing brush_down (Z / D-Pad Down) sets brush back to 3 (7x7)")

	# -------------------------------------------------------------------------
	# 3. Test Multi-voxel Cost Calculation for Dirt and Stone
	# -------------------------------------------------------------------------
	print("\n-- 3. Multi-voxel Cost Calculation for Dirt and Stone")
	var world := VoxelWorld.new()
	root.add_child(world)
	world.store.setup(Vector3i(64, 64, 64), VoxelWorld.VS)
	world.ready_for_play = true

	# Cost of single block (r=0): 1 voxel -> ceil(1/4) = 1 item
	var cost_r0 := BuildCosts.brush_cost(world, Vector3i(10, 10, 10), 0, Palette.DIRT)
	check(cost_r0.get(&"dirt", 0) == 1, "Single block of Dirt (r=0) costs 1 Dirt item")

	# Cost of 3x3 brush (r=1) in empty air:
	# r2 = 1*1 + 1 = 2 -> 19 voxels -> ceil(19 / 4) = 5 items
	var cost_r1 := BuildCosts.brush_cost(world, Vector3i(10, 10, 10), 1, Palette.DIRT)
	check(cost_r1.get(&"dirt", 0) == 5, "3x3 brush of Dirt (r=1, 19 voxels) costs 5 Dirt items (4 voxels/item)")

	# Cost of 5x5 brush (r=2) in empty air:
	var cost_r2_stone := BuildCosts.brush_cost(world, Vector3i(20, 20, 20), 2, Palette.STONE)
	check(cost_r2_stone.get(&"stone", 0) > 5, "5x5 brush of Stone (r=2) costs more than 5 Stone items")

	# -------------------------------------------------------------------------
	# 4. Test Filling Holes and Cavities with Dirt & Stone
	# -------------------------------------------------------------------------
	print("\n-- 4. Filling Holes and Cavities with Dirt & Stone")
	# Create a 3x3 hole in the world at y=10
	for x in range(8, 13):
		for z in range(8, 13):
			world.set_voxel(x, 9, z, Palette.STONE) # bedrock beneath hole
			# solid walls around hole:
			if x == 8 or x == 12 or z == 8 or z == 12:
				world.set_voxel(x, 10, z, Palette.STONE)
			else:
				# inside hole (9 voxels of air from x=9..11, z=9..11)
				world.set_voxel(x, 10, z, 0)

	# Verify center of hole is currently air
	check(world.get_voxel(10, 10, 10) == 0, "Hole interior voxel (10, 10, 10) is currently air")

	# Target center of hole bottom
	player.world = world
	player.inventory = Inventory.new(24)
	player.inventory.add_item(&"dirt", 30)
	player.inventory.set_active_hotbar_index(0)
	player._sync_tool_from_hotbar()
	player.brush = 1 # 3x3 brush

	# Simulate placing into the hole: target bottom face (normal = UP)
	var hole_bottom := Vector3i(10, 9, 10)
	player.target = {"cell": hole_bottom, "normal": Vector3i(0, 1, 0)}

	# Place blocks via _use_tool
	var initial_dirt: int = player.inventory.get_item_count(&"dirt")
	var recorded_cmds: Array = []
	player.command_requested.connect(func(cmd: Dictionary) -> void:
		recorded_cmds.append(cmd)
	)

	player._use_cd = 0.0
	player._use_tool()

	var place_cmd: Dictionary = recorded_cmds[0] if not recorded_cmds.is_empty() else {}
	check(not place_cmd.is_empty(), "command_requested emitted place command")
	check(place_cmd.get("t") == "place", "Command type is 'place'")
	check(place_cmd.get("r") == 1, "Command radius is 1 (3x3)")
	check(place_cmd.get("m") == Palette.DIRT, "Command material is Dirt")
	check(player.inventory.get_item_count(&"dirt") < initial_dirt, "Dirt was consumed from player inventory to pay for placement")

	# Apply command to world
	world.apply_command(place_cmd)

	# Verify hole was filled with dirt
	check(world.get_voxel(10, 10, 10) == Palette.DIRT, "Hole center (10, 10, 10) is now filled with Dirt")
	check(world.get_voxel(9, 10, 10) == Palette.DIRT, "Hole space (9, 10, 10) is now filled with Dirt")
	check(world.get_voxel(11, 10, 10) == Palette.DIRT, "Hole space (11, 10, 10) is now filled with Dirt")
	check(world.get_voxel(8, 10, 10) == Palette.STONE, "Pre-existing stone wall at (8, 10, 10) was NOT overwritten")

	# -------------------------------------------------------------------------
	# 5. Test _brush_hits_self Prevents Suffocation but Allows Hole Filling
	# -------------------------------------------------------------------------
	print("\n-- 5. Player Overlap Checks (_brush_hits_self)")
	# Player standing on solid ground at (8, 11, 10) beside the hole
	player.position = Vector3(7.0, 11.0, 10.5) * VoxelWorld.VS
	# The placed dirt was at (10, 10, 10), player's feet rest at (8, 11, 10) which is solid stone.
	# Placing into the hole at center (10, 10, 10) with r=1:
	check(not player._brush_hits_self(Vector3i(10, 10, 10), 1), "Player standing beside the hole is NOT blocked by _brush_hits_self")

	# Now test if player is standing directly inside the placement volume (air):
	player.position = Vector3(10.5, 12.0, 10.5) * VoxelWorld.VS
	check(player._brush_hits_self(Vector3i(10, 12, 10), 1), "Placing directly where player is standing in air IS blocked by _brush_hits_self")

	# -------------------------------------------------------------------------
	# 6. Only a hatchet fells a whole tree; a pick only chips the trunk
	# -------------------------------------------------------------------------
	print("\n-- 6. Tree felling: hatchet vs pick")
	var plant := func(x: int, z: int) -> void:
		for y in range(20, 30):
			world.set_voxel(x, y, z, Palette.TRUNK)
		for y in range(27, 32):
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if dx != 0 or dz != 0:
						world.set_voxel(x + dx, y, z + dz, Palette.LEAVES_DARK)
	var felled := [0]
	world.tree_felled.connect(func(_p: Vector3, _h: float, _c: float, _pine: bool, _n: int) -> void: felled[0] += 1)
	plant.call(30, 30)
	world.apply_command({"t": "dig", "p": Vector3i(30, 21, 30), "r": 0, "allow_stone": true, "allow_wood": true, "fell": false})
	check(world.get_voxel(30, 21, 30) == 0 and world.get_voxel(30, 25, 30) == Palette.TRUNK and felled[0] == 0,
		"A pick (fell=false) removes only the struck trunk block; the tree stands")
	plant.call(45, 45)
	world.apply_command({"t": "dig", "p": Vector3i(45, 21, 45), "r": 0, "allow_stone": false, "allow_wood": true, "fell": true})
	check(world.get_voxel(45, 25, 45) == 0 and world.get_voxel(46, 29, 45) == 0 and felled[0] == 1,
		"A hatchet (fell=true) brings down the whole trunk and canopy")

	print("\n==================================================")
	print("Large Block Placement Suite: %d / %d tests passed!" % [passed_tests, total_tests])
	print("==================================================")

	quit(0 if passed_tests == total_tests else 1)
