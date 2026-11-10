extends SceneTree

# -------------------------------------------------------------------------
# Test Suite: HUD Bow Reticle Aiming & Boat Nautical Indicator
# -------------------------------------------------------------------------

var _passed := 0
var _failed := 0


func _init() -> void:
	print("\n==================================================")
	print("Running HUD Bow Reticle & Boat Nautical Indicator Suite")
	print("==================================================\n")
	run_tests()
	print("\n==================================================")
	print("HUD Suite: %d / %d tests passed!" % [_passed, _passed + _failed])
	print("==================================================\n")
	quit(0 if _failed == 0 else 1)


func assert_eq(got: Variant, expected: Variant, msg: String) -> void:
	if got == expected:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		print("  [FAIL] %s - expected '%s', got '%s'" % [msg, str(expected), str(got)])


func assert_true(cond: bool, msg: String) -> void:
	assert_eq(cond, true, msg)


func assert_false(cond: bool, msg: String) -> void:
	assert_eq(cond, false, msg)


func run_tests() -> void:
	test_reticle_and_bow_aiming()
	test_hud_tool_context_ranged()
	test_boat_nautical_hud_panel()
	test_boat_field_patch_aboard()


func _make_mock_player() -> Player:
	var p := Player.new()
	p.position = Vector3(0, 5, 0)
	var combat := PlayerCombat.new()
	combat.player = p
	p.combat = combat
	return p


func test_reticle_and_bow_aiming() -> void:
	print("-- 1. HUD Bow Reticle & Tension Calculation")
	var hud := Hud.new()
	hud._ready()
	assert_true(hud.reticle != null, "HUD reticle container initialized")
	assert_true(hud.crosshair != null, "HUD center crosshair TextureRect initialized")
	assert_true(hud.reticle_draw != null, "HUD reticle_draw custom CanvasItem initialized")

	var p := _make_mock_player()
	var sky := SkyCycle.new()
	var world := VoxelWorld.new()

	# Initially unarmed
	hud.update_hud(p, sky, "Solo", world, false)
	assert_false(hud._reticle_is_bow, "Reticle is not in bow mode when unarmed")
	assert_false(hud._reticle_is_flintlock, "Reticle is not in flintlock mode when unarmed")
	assert_false(hud._reticle_is_drawing, "Reticle is not drawing")
	assert_eq(hud._reticle_draw_ratio, 0.0, "Reticle draw ratio is 0.0")

	# Equip bow
	p.inventory.slots[0] = ItemSlot.new(&"hunting_bow", 1)
	p.inventory.active_hotbar_index = 0
	p.tool = 5
	p.inventory.slots[1] = ItemSlot.new(&"flint_arrow", 25)
	p.inventory.slots[2] = ItemSlot.new(&"iron_broadhead", 10)

	assert_true(p.combat.is_holding_bow(), "Player is recognized as holding bow")
	assert_eq(p.combat.get_arrow_ammo_count(), 35, "Player has 35 total arrows")

	hud.update_hud(p, sky, "Solo", world, false)
	assert_true(hud._reticle_is_bow, "Reticle is now in bow mode")
	assert_false(hud._reticle_is_drawing, "Bow is resting (not drawing yet)")
	assert_eq(hud._reticle_ammo_count, 35, "Reticle tracks 35 arrows in pack")

	# Simulate drawing bow halfway
	p.combat.is_drawing_bow = true
	p.combat.bow_draw_t = 0.375 # 50% draw (0.375 / 0.75)
	hud.update_hud(p, sky, "Solo", world, false)
	assert_true(hud._reticle_is_drawing, "Reticle is actively drawing")
	assert_eq(snapped(hud._reticle_draw_ratio, 0.01), 0.5, "Reticle draw ratio tracks 0.50 tension")

	# Simulate max draw tension
	p.combat.bow_draw_t = 0.75 # 100% draw (0.75 / 0.75)
	hud.update_hud(p, sky, "Solo", world, false)
	assert_eq(snapped(hud._reticle_draw_ratio, 0.01), 1.0, "Reticle draw ratio reaches 1.0 at full tension")

	# Switch to flintlock
	p.combat.is_drawing_bow = false
	p.combat.bow_draw_t = 0.0
	p.inventory.slots[0] = ItemSlot.new(&"flintlock_pistol", 1)
	p.inventory.slots[3] = ItemSlot.new(&"paper_cartridge", 14)
	assert_true(p.combat.is_holding_flintlock(), "Player is recognized as holding flintlock")
	assert_eq(p.combat.get_cartridge_ammo_count(), 14, "Player has 14 paper cartridges")

	hud.update_hud(p, sky, "Solo", world, false)
	assert_false(hud._reticle_is_bow, "Reticle bow mode deactivated")
	assert_true(hud._reticle_is_flintlock, "Reticle flintlock mode activated")
	assert_eq(hud._reticle_ammo_count, 14, "Reticle tracks 14 cartridges")

	hud.queue_free()
	sky.queue_free()
	world.queue_free()
	p.queue_free()


func test_hud_tool_context_ranged() -> void:
	print("-- 2. Tool Context Line with Ranged Weapons & Ammo")
	var hud := Hud.new()
	hud._ready()
	var p := _make_mock_player()
	var sky := SkyCycle.new()
	var world := VoxelWorld.new()

	p.tool = 5
	p.inventory.slots[0] = ItemSlot.new(&"hunting_bow", 1)
	p.inventory.slots[1] = ItemSlot.new(&"flint_arrow", 18)
	p.inventory.active_hotbar_index = 0

	# Resting bow context
	hud.update_hud(p, sky, "Solo", world, false)
	assert_true("Hold" in hud.info_label.text, "Context instructs to hold LMB to draw & aim")
	assert_true("Arrows: 18" in hud.info_label.text, "Context shows 18 arrows")

	# Actively drawing bow context
	p.combat.is_drawing_bow = true
	p.combat.bow_draw_t = 0.60 # 80% tension (0.60 / 0.75)
	hud.update_hud(p, sky, "Solo", world, false)
	assert_true("Drawing... 80% tension" in hud.info_label.text, "Context shows tension percentage")
	assert_true("Release" in hud.info_label.text, "Context instructs to release to shoot")

	# Flintlock context
	p.combat.is_drawing_bow = false
	p.combat.bow_draw_t = 0.0
	p.inventory.slots[0] = ItemSlot.new(&"flintlock_pistol", 1)
	p.inventory.slots[2] = ItemSlot.new(&"paper_cartridge", 8)
	hud.update_hud(p, sky, "Solo", world, false)
	assert_true("Cartridges: 8" in hud.info_label.text, "Context shows 8 cartridges for flintlock")
	assert_true("quickfire" in hud.info_label.text, "Context shows quickfire action")

	hud.queue_free()
	sky.queue_free()
	world.queue_free()
	p.queue_free()


func test_boat_nautical_hud_panel() -> void:
	print("-- 3. Nautical Helm & Boat Hull HUD")
	var hud := Hud.new()
	hud._ready()
	var p := _make_mock_player()
	var sky := SkyCycle.new()
	var world := VoxelWorld.new()

	assert_true(hud.boat_panel != null, "Boat panel initialized in HUD")
	assert_false(hud.boat_panel.visible, "Boat panel is hidden when on foot")
	assert_true(hud.bottom_bar.visible, "Foot hotbar is visible when on foot")

	# Spawn boat & seat player
	var boat := Boat.new()
	boat.setup(1, world, sky, Vector3(0, 0, 0), 0.0, Boat.KIND_ROWBOAT)
	boat.max_hull_hp = 100.0
	boat.hull_hp = 100.0
	p.board(boat, 0)
	assert_true(p.is_seated(), "Player is seated in boat")

	# Update HUD while seated
	hud.update_hud(p, sky, "Solo", world, false)
	assert_true(hud.boat_panel.visible, "Boat panel is visible when seated")
	assert_false(hud.bottom_bar.visible, "Hotbar is hidden when seated")
	assert_eq(hud.boat_name_label.text, "Rowboat", "Boat name displays 'Rowboat'")
	assert_eq(hud.boat_hull_bar.max_value, 100.0, "Hull bar max value is 100.0")
	assert_eq(hud.boat_hull_bar.value, 100.0, "Hull bar value is 100.0")
	assert_true("100/100 HP (100%)" in hud.boat_hull_label.text, "Hull label displays full HP")
	assert_eq(hud.boat_leak_label.text, "Watertight Hull", "Watertight label when no leaks")
	assert_false(hud.boat_wheel_badge.visible, "Gilded wheel badge hidden initially")
	assert_false(hud.boat_hawk_badge.visible, "Sea-Hawk badge hidden initially")

	# Apply damage & fracture (leak)
	boat.take_hull_damage(65.0) # Down to 35 HP (< 50% triggers leak)
	assert_true(boat.is_leaking(), "Boat sprang a leak")
	assert_eq(boat.hull_hp, 35.0, "Boat at 35 HP")

	hud.update_hud(p, sky, "Solo", world, false)
	assert_eq(hud.boat_hull_bar.value, 35.0, "Hull bar updated to 35.0")
	assert_true("35/100 HP (35%)" in hud.boat_hull_label.text, "Hull label shows 35%")
	assert_true("LEAKING" in hud.boat_leak_label.text, "Leak warning displayed on HUD")
	assert_true("Field Patch" in hud.boat_controls_label.text, "Field Patch prompt shown when damaged")

	# Upgrade with Gilded Wheel and Sea Hawk
	boat.has_gilded_wheel = true
	boat.has_sea_hawk = true
	hud.update_hud(p, sky, "Solo", world, false)
	assert_true(hud.boat_wheel_badge.visible, "Gilded wheel badge is visible when installed")
	assert_true(hud.boat_hawk_badge.visible, "Sea-Hawk badge is visible when perched")

	# Test speed readout (set velocity)
	boat.vel = Vector2(2.5, 0.0) # ~4.9 kts
	hud.update_hud(p, sky, "Solo", world, false)
	assert_true("4.9 kts" in hud.boat_speed_label.text, "Speedometer displays knots velocity")

	hud.queue_free()
	sky.queue_free()
	world.queue_free()
	boat.queue_free()
	p.queue_free()


func test_boat_field_patch_aboard() -> void:
	print("-- 4. At-Sea Field Patching aboard Damaged Boat")
	var p := _make_mock_player()
	var hud := Hud.new()
	hud._ready()
	p.hud = hud
	var sky := SkyCycle.new()
	var world := VoxelWorld.new()

	var boat := Boat.new()
	boat.setup(2, world, sky, Vector3(0, 0, 0), 0.0, Boat.KIND_ROWBOAT)
	boat.take_hull_damage(60.0) # 40 HP, leaking
	p.board(boat, 0)
	assert_true(boat.is_leaking(), "Boat is leaking")

	# Try field repair without timber
	var ev_c := InputEventKey.new()
	ev_c.pressed = true
	ev_c.keycode = KEY_C
	p._unhandled_input(ev_c)
	assert_eq(boat.hull_hp, 40.0, "Repair fails without timber in pack")

	# Give player wood plank and patch
	p.inventory.slots[0] = ItemSlot.new(&"wood_plank", 3)
	p._unhandled_input(ev_c)
	assert_eq(boat.hull_hp, 80.0, "Repair restores 40 HP (40 -> 80)")
	assert_eq(p.inventory.slots[0].count, 2, "Consumed 1 wood plank")

	hud.queue_free()
	sky.queue_free()
	world.queue_free()
	boat.queue_free()
	p.queue_free()
