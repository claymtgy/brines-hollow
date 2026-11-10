extends SceneTree
## Automated Test Suite for Biome 2 (The Murk-Reef & Abyssal Siren),
## Storm Incursions, and Village Competitions (Sparring & Regatta Buoys).

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
	print("Running Murk-Reef, Incursions & Competitions Tests")
	print("==================================================")

	VoxelWorld.push_palette()
	ItemDB.init_db()
	RecipeDB.init_db()
	Placeables.register_builtin()

	# -------------------------------------------------------------
	# 1. New Material & Trophy Registrations
	# -------------------------------------------------------------
	print("\n-- 1. Materials and Trophies")
	check(ItemDB.has_item(&"siren_heart"), "Heart of the Siren registered in ItemDB")
	check(ItemDB.has_item(&"abyssal_chitin"), "Abyssal Chitin registered in ItemDB")
	check(ItemDB.has_item(&"phosphor_cluster"), "Phosphor Cluster registered in ItemDB")
	check(ItemDB.has_item(&"ancient_weapon_fragment"), "Ancient Weapon Fragment registered in ItemDB")
	check(ItemDB.has_item(&"reaver_crest"), "Sea-Reaver War Crest registered in ItemDB")

	# -------------------------------------------------------------
	# 2. Placeables Registration
	# -------------------------------------------------------------
	print("\n-- 2. New Placeable Entities")
	check(Placeables.BUILTIN.has(&"phosphor_brazier"), "Phosphor Brazier registered in Placeables")
	check(Placeables.BUILTIN.has(&"defense_barricade"), "Spike Barricade registered in Placeables")
	check(Placeables.BUILTIN.has(&"sparring_ring"), "Town Sparring Ring registered in Placeables")
	check(Placeables.BUILTIN.has(&"regatta_buoy"), "Regatta Buoy registered in Placeables")

	var brazier := PhosphorBrazierEntity.new()
	check(brazier.entity_name == "Phosphor Brazier", "PhosphorBrazier entity initialized")
	check(not brazier.lit, "PhosphorBrazier starts unlit")
	brazier.ignite()
	check(brazier.lit and brazier.flare_timer > 0.0, "Igniting PhosphorBrazier triggers chemical flare timer")

	var barricade := BarricadeEntity.new()
	check(barricade.entity_name == "Spike Barricade", "BarricadeEntity initialized")

	var sparring := SparringRingEntity.new()
	check(sparring.entity_name == "Town Sparring Ring", "SparringRingEntity initialized")
	sparring._ready()
	check(SparringRingEntity.is_in_sparring_ring(sparring.position), "Position inside Sparring Ring is detected")
	check(not SparringRingEntity.is_in_sparring_ring(sparring.position + Vector3(20, 0, 0)), "Position outside Sparring Ring is detected")

	var buoy := RegattaBuoyEntity.new()
	buoy._ready()
	check(buoy.gate_number >= 1, "RegattaBuoy registers gate number")

	# -------------------------------------------------------------
	# 3. Biome 2: The Murk-Reef & Abyssal Siren
	# -------------------------------------------------------------
	print("\n-- 3. Biome 2 & Abyssal Siren Boss")
	var siren := AbyssalSiren.new()
	check(siren.max_hp >= 180.0, "Abyssal Siren has boss-scale health (>= 180)")
	check(siren.is_armored(), "Abyssal Siren has armored scales when active")
	siren.on_phosphor_stun()
	check(siren._stun_timer > 0.0, "Phosphor flare induces stun state on Siren")
	check(not siren.is_armored(), "Stunned Siren underbelly is vulnerable (not armored)")

	var drops := siren.drops()
	var has_heart := false
	for d in drops:
		if d[0] == &"siren_heart":
			has_heart = true
			break
	check(has_heart, "Abyssal Siren drops Heart of the Siren trophy")

	# -------------------------------------------------------------
	# 4. Storm Incursions
	# -------------------------------------------------------------
	print("\n-- 4. Storm Incursions")
	var incursion_mgr := StormIncursionManager.new()
	incursion_mgr._ready()
	check(not incursion_mgr.active, "Incursion manager starts inactive")

	# -------------------------------------------------------------
	# Summary
	# -------------------------------------------------------------
	print("\n==================================================")
	print("Murk-Reef, Incursions & Competitions: %d / %d tests passed!" % [passed, total])
	print("==================================================")
	quit(0 if passed == total else 1)
