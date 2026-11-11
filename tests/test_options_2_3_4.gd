extends SceneTree

class TestPlayer extends Node:
	var inventory: Inventory

var _passed := 0
var _failed := 0


func _init() -> void:
	print("\n=== STARTING OPTIONS 2, 3, 4 VERIFICATION TEST SUITE ===")
	VoxelWorld.push_palette()
	ItemDB.init_db()
	RecipeDB.init_db()
	Placeables.register_builtin()

	test_option_2_village_life_and_workplaces()
	test_option_3_audio_foley_and_tactile_soundscape()
	test_option_4_biome_bosses_and_exploration()

	print("\n=== TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [_passed, _failed])
	if _failed > 0:
		printerr("FAILED with %d errors" % _failed)
		quit(1)
	else:
		print("ALL OPTIONS 2, 3, 4 TESTS PASSED SUCCESSFULLY!")
		quit(0)


func assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)


# -----------------------------------------------------------------------------
# 1. OPTION 2: VILLAGE LIFE & DRIFTER WORKPLACES
# -----------------------------------------------------------------------------
func test_option_2_village_life_and_workplaces() -> void:
	print("\n--- Test: Option 2 - Village Life & Drifter Workplaces ---")

	var def := DrifterDef.new(&"drifter_test", "Finn", DrifterDef.Profession.FISHER)
	assert_true(def.profession == DrifterDef.Profession.FISHER, "Drifter initialized with Fisher profession")
	assert_true(def.last_gift_time == -9999.0, "Drifter starts ready for daily gratitude gift")

	var npc := DrifterNPC.new()
	npc.setup(0, def, Vector3(10, 5, 10), 1234)
	root.add_child(npc)

	# Verify face_player
	npc.facing = 0.0
	npc.face_player(Vector3(10, 5, 15)) # player is directly South (+Z)
	assert_true(is_equal_approx(npc.facing, 0.0), "Facing adjusted South toward player")
	npc.face_player(Vector3(15, 5, 10)) # player is East (+X)
	assert_true(npc.facing > 1.5 and npc.facing < 1.6, "Facing adjusted East toward player")
	assert_true(npc.talk_look_t > 0.0, "talk_look_t timer activated")

	# Verify tool selection by profession
	npc.activity = 2 # Working
	npc._process(0.016)
	assert_true(npc.model._current_tool_idx == 3, "Fisher holds fishing rod (tool 3) while working")

	def.profession = DrifterDef.Profession.FARMER
	npc._process(0.016)
	assert_true(npc.model._current_tool_idx == 4, "Farmer holds hoe (tool 4) while working")

	def.profession = DrifterDef.Profession.CARPENTER
	npc._process(0.016)
	assert_true(npc.model._current_tool_idx == 1, "Carpenter holds hammer (tool 1) while working")

	def.profession = DrifterDef.Profession.LAMPLIGHTER
	npc._process(0.016)
	assert_true(npc.model._current_tool_idx == 8, "Lamplighter holds lantern (tool 8) while working")

	def.profession = DrifterDef.Profession.RANCHER
	npc._process(0.016)
	assert_true(npc.model._current_tool_idx == 9, "Rancher holds shears/axe (tool 9) while working")

	npc.queue_free()


# -----------------------------------------------------------------------------
# 2. OPTION 3: AUDIO FOLEY & TACTILE SOUNDSCAPE
# -----------------------------------------------------------------------------
func test_option_3_audio_foley_and_tactile_soundscape() -> void:
	print("\n--- Test: Option 3 - Audio Foley & Tactile Soundscape ---")

	CombatAudio.init_audio(true)

	var required_sounds := [
		"shears_snip", "bucket_slosh", "oil_refuel",
		"flatten_scrape", "animal_whistle", "tame_chime", "saw_wood"
	]

	for s in required_sounds:
		assert_true(CombatAudio._sounds.has(s), "CombatAudio synthesizes sound: %s" % s)
		var stream: AudioStreamWAV = CombatAudio._sounds.get(s)
		assert_true(stream != null, "AudioStreamWAV for %s is non-null" % s)
		assert_true(stream.data.size() > 0, "AudioStreamWAV for %s has baked PCM sample data" % s)

	# Test livestock interaction sound hooks
	var sheep = LivestockAnimal.new()
	sheep.species = &"shore_sheep"
	sheep.wool_grown = true
	sheep.is_tamed = true
	root.add_child(sheep)

	var dummy_player := TestPlayer.new()
	var inv := Inventory.new(36)
	dummy_player.inventory = inv
	inv.add_item(&"shearing_shears", 1)
	inv.active_hotbar_index = 0

	var res: Dictionary = sheep.interact(dummy_player)
	assert_true(res.get("ok", false), "Sheep sheared successfully with shearing shears")
	assert_true(not sheep.wool_grown, "Wool was shorn from sheep")
	assert_true(inv.has_item(&"sea_wool", 2), "Player received shorn sea wool")

	# Test goat milking
	var goat = LivestockAnimal.new()
	goat.species = &"salt_goat"
	goat.yield_timer = 0.0
	goat.hunger = 80.0
	goat.thirst = 80.0
	goat.is_tamed = true
	root.add_child(goat)

	inv.slots[1].item_id = &"wooden_bucket"
	inv.slots[1].count = 1
	inv.active_hotbar_index = 1 # slot with bucket

	var milk_res: Dictionary = goat.interact(dummy_player)
	assert_true(milk_res.get("ok", false), "Goat milked successfully with wooden bucket")
	assert_true(inv.has_item(&"salt_milk", 1), "Player received salt milk")
	assert_true(not inv.has_item(&"wooden_bucket", 1), "Bucket was filled and consumed into milk")

	# Test wild animal taming
	var wild_duck = LivestockAnimal.new()
	wild_duck.species = &"shore_duck"
	wild_duck.is_tamed = false
	wild_duck.taming_feeds = LivestockAnimal.TAMING_FEEDS_NEEDED - 1
	root.add_child(wild_duck)

	inv.slots[2].item_id = &"shore_wheat"
	inv.slots[2].count = 1
	inv.active_hotbar_index = 2 # wheat

	var tame_res: Dictionary = wild_duck.interact(dummy_player)
	assert_true(tame_res.get("ok", false), "Offered final feed to wild animal")
	assert_true(tame_res.get("tamed", false), "Animal became tamed on final feed")
	assert_true(wild_duck.is_tamed, "wild_duck.is_tamed is true")

	sheep.queue_free()
	goat.queue_free()
	wild_duck.queue_free()
	dummy_player.queue_free()


# -----------------------------------------------------------------------------
# 3. OPTION 4: BIOME BOSSES & NAUTICAL EXPLORATION
# -----------------------------------------------------------------------------
func test_option_4_biome_bosses_and_exploration() -> void:
	print("\n--- Test: Option 4 - Biome Bosses & Exploration ---")

	# Boss 1: The Barnacled Hulk (Biome 1: Hollow Flats)
	var hulk := BarnacledHulk.new()
	assert_true(hulk.hp >= 100.0, "Barnacled Hulk has 100+ HP")
	assert_true(hulk.is_armored(), "Barnacled Hulk starts with armored barnacle shell")
	var hulk_drops := hulk.drops()
	var has_hulk_pearl := false
	for d in hulk_drops:
		if d[0] == &"hulk_pearl": has_hulk_pearl = true
	assert_true(has_hulk_pearl, "Barnacled Hulk drops The Hulk's Pearl")
	hulk.free()

	# Boss 2: The Abyssal Siren (Biome 2: Murk-Reef)
	var siren := AbyssalSiren.new()
	assert_true(siren.hp >= 120.0, "Abyssal Siren has 120+ HP")
	var siren_drops := siren.drops()
	var has_siren_heart := false
	for d in siren_drops:
		if d[0] == &"siren_heart": has_siren_heart = true
	assert_true(has_siren_heart, "Abyssal Siren drops Heart of the Siren")
	siren.free()

	# Boss 3: The Caldera Shell (Biome 3: Basalt Skerries)
	var caldera := CalderaShell.new()
	assert_true(caldera.hp >= 140.0, "Caldera Shell has 140+ HP")
	assert_true(caldera.is_armored(), "Caldera Shell has armored basalt carapace")
	var caldera_drops := caldera.drops()
	var has_geo_core := false
	for d in caldera_drops:
		if d[0] == &"geothermal_core": has_geo_core = true
	assert_true(has_geo_core, "Caldera Shell drops Geothermal Core")
	caldera.free()

	# Boss 4: Borean Gore-Fin (Biome 4: Frost-Shoals)
	var borean := BoreanGoreFin.new()
	assert_true(borean.hp >= 150.0, "Borean Gore-Fin has 150+ HP")
	var borean_drops := borean.drops()
	var has_tusk := false
	for d in borean_drops:
		if d[0] == &"glacial_tusk": has_tusk = true
	assert_true(has_tusk, "Borean Gore-Fin drops Glacial Ivory Tusk")
	borean.free()

	# Climax Boss: The Tide Sovereign (Maelstrom Spire)
	var sovereign := TideSovereign.new()
	assert_true(sovereign.hp >= 160.0, "Tide Sovereign has 160+ HP")
	var sov_drops := sovereign.drops()
	var has_deluge := false
	for d in sov_drops:
		if d[0] == &"deluge_core": has_deluge = true
	assert_true(has_deluge, "Tide Sovereign drops Core of the Great Deluge")
	sovereign.free()
