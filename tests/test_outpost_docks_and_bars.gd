extends SceneTree

func _init() -> void:
	print("\n==================================================")
	print("Running Outpost Docks & UI Visual Bars Tests...")
	print("==================================================")

	var counts := {"total": 0, "passed": 0}

	var assert_test := func(name: String, condition: bool) -> void:
		counts.total += 1
		if condition:
			counts.passed += 1
			print("  [PASS] %s" % name)
		else:
			print("  [FAIL] %s" % name)

	# 1. Fishing gauge: shows only while a line is active, sized per state
	var hud := Hud.new()
	var player := Player.new()
	player.fishing = FishingController.new()
	var fc: FishingController = player.fishing
	var gauge := FishingGauge.new()

	fc.current_state = FishingController.State.IDLE
	assert_test.call("Gauge hidden while idle", not gauge.sync(fc, 0.0, 0.016))

	fc.current_state = FishingController.State.CASTING
	assert_test.call("Gauge shows while casting", gauge.sync(fc, 0.65, 0.016))
	assert_test.call("Gauge carries cast power", is_equal_approx(gauge.cast_power, 0.65))

	fc.current_state = FishingController.State.WAITING_FOR_BITE
	assert_test.call("Gauge hidden while waiting for a bite", not gauge.sync(fc, 0.0, 0.016))

	fc.current_state = FishingController.State.HOOK_WINDOW
	fc.hook_window_timer = FishingController.HOOK_WINDOW_BASE * 0.5
	assert_test.call("Gauge shows the strike window", gauge.sync(fc, 0.0, 0.016))
	assert_test.call("Strike timer drains (half left)", is_equal_approx(gauge.hook_left, 0.5))

	fc.current_state = FishingController.State.REELING
	fc.cast_distance = 20.0
	fc.line_distance = 10.0
	fc.line_tension = 0.45
	fc.high_tension_timer = 0.375
	assert_test.call("Gauge shows while reeling", gauge.sync(fc, 0.0, 0.016))
	assert_test.call("Reel progress halfway", is_equal_approx(gauge.progress, 0.5))
	assert_test.call("Snap risk mirrors the snap timer", is_equal_approx(gauge.snap_risk, 0.5))
	assert_test.call("Reeling gauge is taller than the cast gauge", gauge.custom_minimum_size.y > 44.0)

	assert_test.call("Mid tension reads Steady", FishingGauge.tension_word(0.45) == "Steady")
	assert_test.call("High tension warns to ease off", FishingGauge.tension_word(0.90) == "Ease off!")
	assert_test.call("Low tension warns of slack", FishingGauge.tension_word(0.08).begins_with("Slack"))
	assert_test.call("High tension is drawn red", FishingGauge.tension_color(0.9) == FishingGauge.COL_SNAP)

	# 2. Tool-line text stays short and free of glyph bars
	for st in [FishingController.State.CASTING, FishingController.State.REELING, FishingController.State.HOOK_WINDOW]:
		fc.current_state = st
		var t := hud._fishing_text(player, "LMB")
		assert_test.call("Fishing text has no glyph bars (state %d)" % st, not t.contains("█") and not t.contains("░"))
	fc.current_state = FishingController.State.REELING
	assert_test.call("Reeling text explains the controls", hud._fishing_text(player, "LMB").contains("Hold LMB to reel"))

	# 3. Boat trim words and inventory stats
	assert_test.call("Trim word at full efficiency", Hud.trim_word(0.95) == "full sail")
	assert_test.call("Trim word when stalled", Hud.trim_word(0.05) == "no drive")
	var inv_ui := InventoryUI.new()
	assert_test.call("Swim speed normal", InventoryUI.swim_speed_text(1.0) == "Normal")
	assert_test.call("Swim speed bonus", InventoryUI.swim_speed_text(1.2) == "+20%")
	gauge.free()

	# 4. WorldGen Outpost Pier & Moored Skiff tests
	var gen := WorldGen.new(1106, VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ, VoxelWorld.SEA_MID, VoxelWorld.TIDE_AMP, VoxelWorld.layout_params(2))
	gen.plan_starter()
	gen.plan_outposts(2)

	assert_test.call("WorldGen planned at least 1 outpost", gen.outposts.size() >= 1)

	if not gen.outposts.is_empty():
		var out0: Dictionary = gen.outposts[0]
		assert_test.call("Outpost record contains dock_o coordinates", out0.has("dock_o") and out0.dock_o is Vector2i)
		assert_test.call("Outpost record contains dock_d direction", out0.has("dock_d") and out0.dock_d is Vector2i)
		assert_test.call("Outpost record contains dock_end sentry post", out0.has("dock_end") and out0.dock_end is Vector3)
		assert_test.call("Outpost record contains mooring data", out0.has("mooring") and out0.mooring is Dictionary)

		# Moored boat type
		var moor: Dictionary = out0.mooring
		assert_test.call("Outpost mooring specifies KIND_SKIFF", moor.get("kind", -1) == Boat.KIND_SKIFF)
		assert_test.call("Outpost mooring tagged with outpost island", moor.has("outpost"))

		# Boat spawns array includes the outpost skiff
		var found_skiff := false
		for sp: Dictionary in gen.boat_spawns:
			if sp.get("kind", -1) == Boat.KIND_SKIFF:
				found_skiff = true
				break
		assert_test.call("gen.boat_spawns includes the moored outpost skiff", found_skiff)

		# Patrol posts include dock sentry point
		var has_dock_post := false
		for p: Vector3 in out0.posts:
			if p.is_equal_approx(out0.dock_end):
				has_dock_post = true
				break
		assert_test.call("Outpost posts include dock_end pier sentry post", has_dock_post)

	# 5. ReaverOutposts forward harbor label on capture
	var ro := ReaverOutposts.new()
	ro.outposts = gen.outposts
	ro.discovered[0] = true
	ro.captured[0] = true
	var labels := ro.chart_labels()
	assert_test.call("Chart labels size matches discovered outposts", labels.size() == 1)
	if not labels.is_empty():
		assert_test.call("Captured outpost chart label is 'Forward harbor'", labels[0].get("name") == "Forward harbor")

	print("==================================================")
	print("Results: %d/%d passed" % [counts.passed, counts.total])
	print("==================================================")

	# Cleanup
	hud.free()
	player.free()
	inv_ui.free()
	ro.free()

	if counts.passed == counts.total and counts.total > 0:
		quit(0)
	else:
		quit(1)
