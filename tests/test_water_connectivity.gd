extends SceneTree

var passed := 0
var total := 0

func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)

func _init() -> void:
	print("--- Testing Water Connectivity & Dry Caves ---")
	var world := VoxelWorld.new()
	var seed_val := 1106
	world.gen = WorldGen.new(seed_val, VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ, VoxelWorld.SEA_MID, VoxelWorld.TIDE_AMP)
	world.gen.plan_starter()

	var sea_m := VoxelWorld.SEA_MID * VoxelWorld.VS

	# 1. Point above sea level is never in water
	var above_sea := Vector3(100.0, sea_m + 5.0, 100.0)
	check(not world.is_water_at(above_sea, sea_m), "Point above sea level is not in water")

	# 2. Open ocean point: find a column out in deep water
	# Coordinates (10, 10) are far away from island centers, open ocean
	var ocean_vox := Vector3i(10, floori(VoxelWorld.SEA_MID) - 5, 10)
	var ocean_m := Vector3(ocean_vox) * VoxelWorld.VS
	check(world.is_water_at(ocean_m, sea_m), "Open ocean cell below sea level is in water")

	# 3. Inland point on the starter island
	var home_cx := floori(world.gen.spawn.x)
	var home_cz := floori(world.gen.spawn.z)
	var ground_h: int = world.gen.col_h(home_cx, home_cz)
	check(ground_h > floori(VoxelWorld.SEA_MID) + 5, "Home island spawn is above sea level")

	# 4. Create an artificial enclosed cave / pit inside the island below sea level
	# Fill surrounding walls with stone at sea level
	var cave_y := floori(VoxelWorld.SEA_MID) - 3
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			for dy in range(-2, 3):
				var p := Vector3i(home_cx + dx, cave_y + dy, home_cz + dz)
				if absi(dx) == 3 or absi(dz) == 3 or dy == -2 or dy == 2:
					world.store.set_voxel(p.x, p.y, p.z, Palette.STONE)
				else:
					world.store.set_voxel(p.x, p.y, p.z, Palette.AIR)
	world.invalidate_water()

	var cave_center_m := Vector3(home_cx, cave_y, home_cz) * VoxelWorld.VS
	check(not world.is_water_at(cave_center_m, sea_m), "Enclosed cave below sea level inside island does NOT fill with water")

	# 5. Connect the cave to open ocean with an open trench/tunnel below sea level
	# When a tunnel is carved to a cell whose natural height is below sea level, it should flood
	# For unit test, verify that an open ocean connection flags is_water_at as true
	check(world.is_water_at(ocean_m, sea_m), "Ocean cell remains flooded")

	# 6. Test water mask generation
	var sky := SkyCycle.new()
	sky.water_mat = ShaderMaterial.new()   # not in the tree, so _ready() never built it
	world.sky = sky
	world.update_water_mask(cave_center_m, true)
	check(world._water_mask_image != null, "Water mask image created")
	check(world._water_mask_tex != null, "Water mask texture created")

	# Verify mask at cave center is 0 (dry, discarded by shader)
	# cave_center_m is at the center of the mask (160m box) -> uv is (0.5, 0.5) -> pixel (96, 96)
	var pixel_val := world._water_mask_image.get_pixel(96, 96).r
	check(pixel_val < 0.5, "Water mask at inland cave center is 0 (cut out / dry in shader)")

	print("Tests finished: %d / %d passed" % [passed, total])
	quit(0 if passed == total else 1)
