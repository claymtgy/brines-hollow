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
	print("Running Brine's Hollow New Features Test Suite...")
	print("==================================================")

	var cm := ControllerManager.new()
	cm.setup_input_map()
	ItemDB.init_db()
	RecipeDB.init_db()
	Placeables.register_builtin()

	var root := get_root()

	# -------------------------------------------------------------------------
	# 1. Test Fish Oil & Lighthouse Fueling
	# -------------------------------------------------------------------------
	print("\n-- 1. Fish Oil & Lighthouse Refueling")
	check(ItemDB.has_item(&"fish_oil"), "ItemDB has fish_oil registered")
	var oil_def := ItemDB.get_item(&"fish_oil")
	check(oil_def != null and oil_def.category == ItemDef.Category.MATERIAL, "Fish Oil is a MATERIAL item")

	var r_oil_mackerel := RecipeDB.get_recipe(&"refine_fish_oil")
	check(r_oil_mackerel != null and r_oil_mackerel.output_item_id == &"fish_oil", "Fish oil recipe from mackerel exists")
	var r_oil_salmon := RecipeDB.get_recipe(&"refine_fish_oil_salmon")
	check(r_oil_salmon != null and r_oil_salmon.output_item_id == &"fish_oil", "Fish oil recipe from cliff salmon exists")

	var sky := SkyCycle.new()
	root.add_child(sky)
	var beam := LighthouseBeam.new()
	root.add_child(beam)
	beam.setup(sky, Vector3(0, 10, 0))
	check(beam.fuel_sec > 0.0, "Lighthouse beam initializes with positive fuel")
	var initial_fuel := beam.fuel_sec
	beam.add_fuel(720.0)
	check(beam.fuel_sec > initial_fuel, "Adding fish oil refuels the lighthouse beam")
	check(beam.can_refuel(), "can_refuel reports status correctly")

	# -------------------------------------------------------------------------
	# 2. Test Job Blocks & Rancher Profession
	# -------------------------------------------------------------------------
	print("\n-- 2. Job Blocks & Rancher Profession")
	check(ItemDB.has_item(&"farming_station"), "ItemDB has farming_station registered")
	check(ItemDB.has_item(&"ranch_station"), "ItemDB has ranch_station registered")
	check(ItemDB.has_item(&"fisher_station"), "ItemDB has fisher_station registered")
	check(ItemDB.has_item(&"sawhorse"), "ItemDB has sawhorse registered")

	var d_rancher := DrifterDef.new(&"rancher_1", "Giles", DrifterDef.Profession.RANCHER)
	check(d_rancher.profession == DrifterDef.Profession.RANCHER, "DrifterDef supports RANCHER profession")
	var npc := DrifterNPC.new()
	root.add_child(npc)
	npc.setup(0, d_rancher, Vector3.ZERO, 123)
	check(npc.profession_name() == "Rancher", "DrifterNPC displays 'Rancher' title")

	# -------------------------------------------------------------------------
	# 3. Test Pickaxe Flatten Land Mode
	# -------------------------------------------------------------------------
	print("\n-- 3. Pickaxe Flatten Land Mode")
	var player := Player.new()
	player.rig = CameraRig.new()
	player.rig.cam = Camera3D.new()
	player.rig.add_child(player.rig.cam)
	root.add_child(player)

	# Give pickaxe to player
	player.inventory.add_item(&"driftwood_pickaxe", 1)
	player.select_hotbar_slot(0)
	check(player.has_pickaxe_equipped(), "Player has pickaxe equipped")
	check(not player.pickaxe_flatten_mode, "Pickaxe flatten mode starts false")

	player.toggle_pickaxe_flatten_mode()
	check(player.pickaxe_flatten_mode, "Toggling activates pickaxe flatten mode")
	player.toggle_pickaxe_flatten_mode()
	check(not player.pickaxe_flatten_mode, "Toggling again deactivates pickaxe flatten mode")

	# Test VoxelWorld flatten command
	var world := VoxelWorld.new()
	root.add_child(world)
	world.store.setup(Vector3i(64, 64, 64), VoxelWorld.VS)
	world.ready_for_play = true

	# Set up a small mound: target_y = 10, voxels at y=10, 11, 12
	world.store.set_voxel(15, 10, 15, Palette.DIRT)
	world.store.set_voxel(15, 11, 15, Palette.DIRT)
	world.store.set_voxel(15, 12, 15, Palette.DIRT)
	check(world.store.get_voxel(15, 12, 15) == Palette.DIRT, "Voxel at y=12 is solid before flatten")

	world.apply_command({
		"t": "flatten",
		"p": Vector3i(15, 10, 15),
		"r": 2,
		"target_y": 10
	})

	check(world.store.get_voxel(15, 10, 15) == Palette.DIRT, "Base ground at target_y=10 is preserved")
	check(world.store.get_voxel(15, 11, 15) == 0, "Mound voxel at y=11 was flattened to air")
	check(world.store.get_voxel(15, 12, 15) == 0, "Mound voxel at y=12 was flattened to air")

	# -------------------------------------------------------------------------
	# 4. Test Single Block Straight Line Placement (Shift)
	# -------------------------------------------------------------------------
	print("\n-- 4. Single Block Straight Line Placement with Shift")
	for s in player.inventory.slots:
		s.item_id = &""
		s.count = 0
	player.inventory.add_item(&"dirt", 100)
	player.select_hotbar_slot(0)
	check(player.tool == 1, "Player is in block placement tool")
	player.brush = 0
	check(player.brush == 0, "Player brush is 0 (single 1x1 block)")

	player._line_anchor = Vector3i(10, 5, 10)
	check(player._line_anchor == Vector3i(10, 5, 10), "_line_anchor is tracked")

	# When switching tool, line anchor resets
	player._set_tool(0)
	check(player._line_anchor.x == -99999, "Switching tool resets _line_anchor")

	print("\n==================================================")
	print("Summary: %d / %d tests passed!" % [passed_tests, total_tests])
	print("==================================================")
	if passed_tests == total_tests:
		print("ALL NEW FEATURE TESTS PASSED!")
	quit()
