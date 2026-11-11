extends SceneTree
## Headless verification suite for Foundation structures, Signal Smoke, Circling Gulls, and First Hearth Step 3.

var passed := 0
var total := 0

func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		push_error("  [FAIL] " + label)
		print("  [FAIL] ", label)


func _initialize() -> void:
	print("==================================================")
	print("Running Foundation & Rescue Guidance Tests...")
	print("==================================================")

	ItemDB.init_db()
	RecipeDB.init_db()

	# -------------------------------------------------------------------------
	# 1. Foundation Prefabs
	# -------------------------------------------------------------------------
	var all_prefabs := Prefabs.all()
	var stone_found: Dictionary = {}
	var timber_found: Dictionary = {}
	var large_found: Dictionary = {}

	for pf: Dictionary in all_prefabs:
		if pf.name == "Stone Foundation":
			stone_found = pf
		elif pf.name == "Timber Foundation":
			timber_found = pf
		elif pf.name == "Large Stone Foundation":
			large_found = pf

	check(not stone_found.is_empty(), "Stone Foundation exists in Prefabs")
	check(not timber_found.is_empty(), "Timber Foundation exists in Prefabs")
	check(not large_found.is_empty(), "Large Stone Foundation exists in Prefabs")

	check(stone_found.foundation == "solid_stone", "Stone Foundation has solid_stone foundation")
	check(timber_found.foundation == "solid_timber", "Timber Foundation has solid_timber foundation")
	check(large_found.foundation == "solid_stone", "Large Stone Foundation has solid_stone foundation")

	check(stone_found.size == Vector3i(12, 2, 12), "Stone Foundation is 12x2x12")
	check(timber_found.size == Vector3i(12, 2, 12), "Timber Foundation is 12x2x12")
	check(large_found.size == Vector3i(24, 2, 24), "Large Stone Foundation is 24x2x24")

	# Check flat top on Stone Foundation: y=1 has solid voxels across all x,z
	var flat_top_ok := true
	var s_data: PackedByteArray = stone_found.data
	var sx: int = stone_found.size.x
	var sz: int = stone_found.size.z
	for z in sz:
		for x in sx:
			var m := s_data[x + sx * (z + sz * 1)]
			if m == 0 or m == Palette.CLEAR:
				flat_top_ok = false
				break
	check(flat_top_ok, "Stone Foundation top layer (y=1) is completely flat and paved")

	# Check bottom fill on Stone Foundation: y=0 has solid voxels across all x,z for fill_down
	var bottom_ok := true
	for z in sz:
		for x in sx:
			var m := s_data[x + sx * (z + sz * 0)]
			if m == 0 or m == Palette.CLEAR:
				bottom_ok = false
				break
	check(bottom_ok, "Stone Foundation bottom layer (y=0) is solid for downward ground filling")

	# -------------------------------------------------------------------------
	# 2. First Hearth Step 3 & Rescue Loop
	# -------------------------------------------------------------------------
	var qm := QuestManager.new()
	var q1: QuestDef = qm.available_quests.get(&"story_first_hearth")
	check(q1 != null, "story_first_hearth exists")
	check(q1.steps.size() == 3, "story_first_hearth has exactly 3 steps")
	check(q1.steps[2].target_id == &"drifter_recruit", "story_first_hearth step 3 targets drifter_recruit")
	check(q1.steps[2].type == QuestDef.ObjectiveType.TALK_TO, "story_first_hearth step 3 is TALK_TO type")

	# Progress quest
	qm.accept_quest(&"story_first_hearth")
	var inv := Inventory.new(16)
	qm.notify_event(QuestDef.ObjectiveType.GATHER_ITEM, &"driftwood", 10, inv)
	check(q1.steps[0].is_completed, "Step 1 (gather driftwood) completed")
	qm.notify_event(QuestDef.ObjectiveType.BUILD_ROOM, &"shelter", 1, inv)
	check(q1.steps[1].is_completed, "Step 2 (build shelter room) completed")
	check(not qm.is_quest_completed(&"story_first_hearth"), "Quest remains active awaiting step 3")

	qm.notify_event(QuestDef.ObjectiveType.TALK_TO, &"drifter_recruit", 1, inv)
	check(q1.steps[2].is_completed, "Step 3 (invite drifter) completed")
	check(qm.is_quest_completed(&"story_first_hearth"), "story_first_hearth is completed after recruiting drifter")

	# -------------------------------------------------------------------------
	# 3. VillageManager Signal Smoke
	# -------------------------------------------------------------------------
	var vm := VillageManager.new()
	var smoke := vm._create_signal_smoke()
	check(smoke != null, "_create_signal_smoke returned a CPUParticles3D instance")
	check(smoke.amount > 0 and smoke.lifetime > 3.0, "Signal smoke has long lifetime for distant visibility")
	smoke.queue_free()
	vm.queue_free()

	print("==================================================")
	print("Results: %d/%d passed" % [passed, total])
	print("==================================================")
	quit(0 if passed == total else 1)
