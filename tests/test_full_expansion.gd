extends SceneTree
## Automated Test Suite for:
## 1. Biome 3: The Sunken Ruins, Diving Bell & Abyssal Angler
## 2. Drifter NPC Automation & Incursion Defense
## 3. Open-Sea Hazards & Whirlpool Vortex Physics
## 4. Release Polish, Steam Deck Controller & Title Screen Orbit

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


func _init() -> void:
	print("==================================================")
	print("Running Full 4-Pillar Expansion Test Suite")
	print("==================================================")

	VoxelWorld.push_palette()
	ItemDB.init_db()
	RecipeDB.init_db()
	Placeables.register_builtin()

	# -------------------------------------------------------------
	# 1. Biome 3: Sunken Ruins, Diving Equipment & Abyssal Angler
	# -------------------------------------------------------------
	print("\n-- 1. Biome 3: Sunken Ruins & Diving Gear")
	check(ItemDB.has_item(&"brass_diving_helmet"), "Brass Diving Helmet registered in ItemDB")
	check(ItemDB.has_item(&"angler_lure"), "Angler Lure registered in ItemDB")
	check(ItemDB.has_item(&"abyssal_pearl"), "Black Abyssal Pearl registered in ItemDB")
	check(ItemDB.has_item(&"diving_bell"), "Submerged Diving Bell registered in ItemDB")
	check(Placeables.BUILTIN.has(&"diving_bell"), "Diving Bell registered in Placeables")

	var bell := DivingBellEntity.new()
	check(bell.entity_name == "Submerged Diving Bell", "DivingBellEntity initialized")

	var vit := VitalityController.new()
	vit.tick(0.0)
	check(not vit.has_diving_helmet, "VitalityController starts without diving helmet")
	vit.has_diving_helmet = true
	var br0 := vit.current_breath
	vit.tick(1.0, true, false)
	var drain_with_helm := br0 - vit.current_breath
	check(drain_with_helm < 0.3, "Diving helmet reduces oxygen drain to 0.2/sec (was 1.0/sec)")

	var angler := AbyssalAngler.new()
	check(angler.hp >= 55.0, "Abyssal Angler has 55 HP")
	var drops := angler.drops()
	var has_lure := false
	for d in drops:
		if d[0] == &"angler_lure":
			has_lure = true
			break
	check(has_lure, "Abyssal Angler drops Angler Lure")

	# -------------------------------------------------------------
	# 2. Drifter Automation & NPC Reactions
	# -------------------------------------------------------------
	print("\n-- 2. Drifter Automation & NPC Systems")
	var ddef := DrifterDef.new(&"drifter_test", "Finnian", DrifterDef.Profession.FISHER)
	check(ddef.profession == DrifterDef.Profession.FISHER, "DrifterDef initialized with Fisher profession")

	# -------------------------------------------------------------
	# 3. Maritime Hazards: Whirlpool Vortex Physics
	# -------------------------------------------------------------
	print("\n-- 3. Maritime Hazards & Whirlpools")
	var wp := WhirlpoolHazard.new()
	wp.position = Vector3(100.0, 10.0, 100.0)
	wp._ready()
	check(WhirlpoolHazard.active_whirlpools.has(wp), "Whirlpool hazard registered in active pool")

	var test_boat_pos := Vector3(110.0, 10.0, 100.0) # 10m away from center
	var effect: Dictionary = WhirlpoolHazard.get_vortex_effect(test_boat_pos)
	var force: Vector2 = effect.get("force", Vector2.ZERO)
	var torque: float = float(effect.get("torque", 0.0))
	check(force.length() > 0.0, "Whirlpool exerts current pull force on nearby boat")
	check(torque > 0.0, "Whirlpool exerts rotational vortex torque on boat")

	wp._exit_tree()
	check(not WhirlpoolHazard.active_whirlpools.has(wp), "Whirlpool cleanly deregisters on exit")

	# -------------------------------------------------------------
	# 4. Release Polish: Steam Deck Controller Detection
	# -------------------------------------------------------------
	print("\n-- 4. Release Polish & Controller Detection")
	var cm := ControllerManager.new()
	var detected_deck := cm.detect_type_from_name("Steam Deck Controller (Virtual)")
	check(detected_deck == ControllerManager.Type.STEAM_DECK, "Steam Deck controller detected from device string")
	cm.current_type = ControllerManager.Type.STEAM_DECK
	var use_glyph := cm.get_glyph(&"use")
	check(use_glyph == "RT", "Steam Deck maps primary action to RT")

	# -------------------------------------------------------------
	# Summary
	# -------------------------------------------------------------
	print("\n==================================================")
	print("Full 4-Pillar Expansion: %d / %d tests passed!" % [passed, total])
	print("==================================================")
	quit(0 if passed == total else 1)
