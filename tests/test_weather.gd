extends SceneTree
## Weather system tests:  godot --headless --path . -s tests/test_weather.gd

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
	# --- determinism
	var a := WeatherModel.sample(1106, 3.37)
	var b := WeatherModel.sample(1106, 3.37)
	check(a.state == b.state and is_equal_approx(a.rain, b.rain) and is_equal_approx(a.wind, b.wind), "same seed + time -> identical weather")
	var differs := false
	for d in 40:
		if WeatherModel.front_state(1106, d + 1) != WeatherModel.front_state(42, d + 1):
			differs = true
	check(differs, "different seeds produce different schedules")
	check(WeatherModel.sample(1106, 0.05).state == WeatherModel.State.CLEAR, "a new world starts on a clear front")

	# --- variety over a few in-game days, and storms never back-to-back
	var seen := {}
	var back_to_back := false
	var prev := -1
	for i in range(1, 200):
		var s := WeatherModel.front_state(1106, i)
		seen[s] = true
		if s == WeatherModel.State.STORM and prev == WeatherModel.State.STORM:
			back_to_back = true
		prev = s
	check(seen.size() == 5, "all five states occur (%s)" % str(seen.keys()))
	check(not back_to_back, "no two storm fronts in a row")
	var first_days := {}
	for i in range(1, int(5.0 / WeatherModel.FRONT_DAYS)):
		first_days[WeatherModel.front_state(1106, i)] = true
	check(first_days.size() >= 4, "at least 4 weather types within 5 in-game days (%d)" % first_days.size())

	# --- smooth transitions (no pops between consecutive frames)
	var max_step := 0.0
	var t := 0.0
	var last := WeatherModel.sample(7, 0.0)
	while t < 6.0:
		t += 1.0 / (60.0 * 720.0)  * 30.0   # 30 frames of game time at 60 fps
		var cur := WeatherModel.sample(7, t)
		for k: String in ["cloud", "fog", "rain", "storm"]:
			max_step = maxf(max_step, absf(cur[k] - last[k]))
		last = cur
	check(max_step < 0.05, "parameters change smoothly (max step %.4f per 0.5 s)" % max_step)

	# --- swell function: bounded by amplitude, zero-mean-ish, follows wind
	var hmax := 0.0
	for i in 200:
		hmax = maxf(hmax, absf(WeatherModel.wave_height(Vector2(i * 1.7, i * 0.9), i * 0.13, 1.0, Vector2(1, 0))))
	check(hmax <= WeatherModel.swell_amp(1.0) + 0.0001 and hmax > 0.1, "storm swell is within its amplitude (%.2f m)" % hmax)
	check(WeatherModel.swell_amp(0.1) < 0.05, "calm sea is nearly flat")
	check(WeatherModel.surge_vox(1.0, 1.0) > 1.5 and WeatherModel.surge_vox(1.0, -1.0) == 0.0 and WeatherModel.surge_vox(0.0, 1.0) == 0.0,
		"storm surge only at high tide, only in storms")

	# --- sheltered-rain check on a synthetic roof
	var store := VoxelStore.new()
	store.setup(Vector3i(64, 64, 64), VoxelWorld.VS)
	for x in range(10, 30):
		for z in range(10, 30):
			store.set_voxel(x, 30, z, Palette.PLANK)
	var q := func(x: int, y: int, z: int) -> int: return store.get_voxel(x, y, z)
	check(WeatherModel.is_sheltered(q, Vector3i(20, 20, 20)), "under a plank roof is sheltered")
	check(not WeatherModel.is_sheltered(q, Vector3i(45, 20, 45)), "in the open is not sheltered")
	check(not WeatherModel.is_sheltered(q, Vector3i(20, 35, 20)), "standing on the roof is not sheltered")
	for x in range(40, 60):
		for z in range(40, 60):
			store.set_voxel(x, 30, z, Palette.LEAVES)
	check(not WeatherModel.is_sheltered(q, Vector3i(50, 20, 50)), "leaf canopy doesn't count as a roof")

	# --- rain waters crops (farm tick hook)
	ItemDB.init_db()
	CropDB.init_db()
	var farm := FarmManager.new(30.0, 7.0)
	var dry_plot := farm.till_plot(Vector3i(5, 60, 5))
	var wet_plot := farm.till_plot(Vector3i(9, 60, 9))
	dry_plot.hydration = 0.2
	wet_plot.hydration = 0.2
	for i in 60:
		dry_plot.tick(1.0, 30.0, false)
		wet_plot.tick(1.0, 30.0, true)
	check(wet_plot.hydration > dry_plot.hydration + 0.3, "rain raises plot hydration (%.2f vs %.2f)" % [wet_plot.hydration, dry_plot.hydration])

	_scene_checks.call_deferred()


func _scene_checks() -> void:
	# --- save/load roundtrip of the weather clock
	var sky := SkyCycle.new()
	root.add_child(sky)
	await process_frame
	sky.day = 17
	sky.time_of_day = 0.4
	var saved := sky.weather.serialize()
	sky.day = 0
	sky.weather.deserialize(saved)
	check(sky.day == 17, "weather clock (day) survives save/load")
	sky.weather.update(0.016)
	var expect := WeatherModel.sample(sky.weather.seed_value(), 17.4)
	check(sky.weather.params.state == expect.state, "live weather matches the model for the restored clock")
	check(sky.name == "Sky" and sky.weather.name == "Weather", "fixed node path for weather RPCs")
	sky.queue_free()

	print("Summary: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)
