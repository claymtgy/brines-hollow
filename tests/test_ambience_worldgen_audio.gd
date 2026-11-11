extends SceneTree

var passed := 0
var failed := 0

func assert_true(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("  [PASS] %s" % msg)
	else:
		failed += 1
		printerr("  [FAIL] %s" % msg)

func _init() -> void:
	print("\n=== STARTING AMBIENCE, WORLDGEN & AUDIO TEST SUITE ===")

	# -------------------------------------------------------------
	# 1. Shift-Line Block Building & Key State Hardening
	# -------------------------------------------------------------
	print("\n--- Test: Shift-Line Block Building ---")
	var player_script := load("res://scripts/player.gd")
	assert_true(player_script != null, "player.gd loaded successfully")
	var dummy_player = player_script.new()
	assert_true(dummy_player != null, "Player instance created")
	assert_true(dummy_player.has_method("is_shift_held"), "Player has dedicated is_shift_held() helper")
	assert_true(not dummy_player.is_shift_held(), "is_shift_held() is false when Shift is physically not pressed")
	assert_true(dummy_player._line_anchor == Vector3i(-99999, -99999, -99999), "Initial _line_anchor is cleared (-99999)")

	# Key release clears _line_anchor immediately
	dummy_player._line_anchor = Vector3i(10, 5, 2)
	var rel_event := InputEventKey.new()
	rel_event.keycode = KEY_SHIFT
	rel_event.physical_keycode = KEY_SHIFT
	rel_event.pressed = false
	dummy_player._unhandled_input(rel_event)
	assert_true(dummy_player._line_anchor == Vector3i(-99999, -99999, -99999), "Releasing Shift clears _line_anchor immediately")
	dummy_player.free()

	# -------------------------------------------------------------
	# 2. Marine Life & Visual Ambience
	# -------------------------------------------------------------
	print("\n--- Test: Marine Life & Visual Ambience ---")
	var fish_mgr_script := load("res://scripts/ambient_fish.gd")
	assert_true(fish_mgr_script != null, "ambient_fish.gd loaded successfully")
	var fish_mgr: AmbientFishManager = fish_mgr_script.new()
	fish_mgr.setup(null, null, null)
	assert_true(fish_mgr._fish_textures.size() == 3, "AmbientFishManager creates 3 distinct fish species textures")
	assert_true(fish_mgr._fish.size() == AmbientFishManager.FISH_COUNT, "AmbientFishManager spawns %d swimming fish" % AmbientFishManager.FISH_COUNT)
	assert_true(fish_mgr._ripples.size() == AmbientFishManager.MAX_RIPPLES, "Ripple pool allocated with %d sprites" % AmbientFishManager.MAX_RIPPLES)

	# Test gull soaring logic
	var gull_script := load("res://scripts/creatures/gull.gd")
	assert_true(gull_script != null, "gull.gd loaded successfully")
	var gull: Gull = gull_script.new()
	assert_true(gull != null, "Gull instantiated")
	assert_true(gull.kind == &"gull", "Gull creature kind is gull")
	fish_mgr.free()
	gull.free()

	# -------------------------------------------------------------
	# 3. Island Biome Variants & Worldgen Depth
	# -------------------------------------------------------------
	print("\n--- Test: Island Biomes & Calamity Galleons ---")
	assert_true(IslandAtlas.STYLE_SUFFIX.has(5), "IslandAtlas includes Style 5 (Estuary / Mangrove / Channels)")
	var worldgen_script := load("res://scripts/worldgen.gd")
	assert_true(worldgen_script != null, "worldgen.gd loaded successfully")
	var gen: WorldGen = worldgen_script.new(12345, 128, 64, 128, 20.0, 2.0, {})
	gen.starter = {"hut": Vector3i(64, 22, 64)}
	gen.islands = [
		{"center": Vector2(64, 64), "radius": 30.0},
		{"center": Vector2(200, 200), "radius": 45.0},
		{"center": Vector2(-200, -200), "radius": 50.0}
	]
	gen.plan_calamity_galleons(2)
	assert_true(gen.has_method("plan_calamity_galleons"), "WorldGen has plan_calamity_galleons()")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var loot := ChestEntity.calamity_galleon_loot(rng)
	assert_true(not loot.is_empty(), "Calamity galleon loot table returns items")
	var has_guilders := false
	var has_pearls := false
	for it in loot:
		if it[0] == &"brass_guilder": has_guilders = true
		if it[0] == &"abyssal_pearl": has_pearls = true
	assert_true(has_guilders, "Calamity galleon loot contains brass guilders")
	assert_true(has_pearls, "Calamity galleon loot contains abyssal pearls")

	# -------------------------------------------------------------
	# 4. Tavern Life & Maritime Audio Atmosphere
	# -------------------------------------------------------------
	print("\n--- Test: Tavern Life & Maritime Soundscape ---")
	var audio_script := load("res://scripts/weather/ambient_audio.gd")
	assert_true(audio_script != null, "ambient_audio.gd loaded successfully")
	var audio = audio_script.new()
	audio._bake_all()
	assert_true(audio._baked.has("tavern_accordion"), "ambient_audio bakes tavern_accordion")
	assert_true(audio._baked.has("rigging_wind"), "ambient_audio bakes rigging_wind")
	var accordion_stream: AudioStreamWAV = audio._baked.get("tavern_accordion")
	var rigging_stream: AudioStreamWAV = audio._baked.get("rigging_wind")
	assert_true(accordion_stream != null and accordion_stream.data.size() > 0, "tavern_accordion generates non-empty PCM samples")
	assert_true(rigging_stream != null and rigging_stream.data.size() > 0, "rigging_wind generates non-empty PCM samples")
	audio.free()

	# Boat bow spray verification
	var boat_script := load("res://scripts/boat.gd")
	assert_true(boat_script != null, "boat.gd loaded successfully")
	var boat = boat_script.new(Boat.KIND_SKIFF)
	boat.setup(1, null, null, Vector3.ZERO, 0.0, Boat.KIND_SKIFF)
	assert_true(boat._bow_spray != null, "Boat has _bow_spray particle system initialized")
	assert_true(boat._bow_spray.amount >= 20, "Bow spray particle count is configured")
	boat.free()

	print("\n=== TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [passed, failed])
	if failed == 0:
		print("ALL AMBIENCE, WORLDGEN & AUDIO TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("SOME TESTS FAILED!")
	quit()
