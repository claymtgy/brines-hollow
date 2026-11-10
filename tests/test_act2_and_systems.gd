extends SceneTree
## Automated Test Suite for Storyline Act II Quests,
## Boat Upgrades & Holds, Ambient Audio / CC0 System, and Settings Key Rebinding.

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
	print("Running Act II, Boat Upgrades, Audio & Settings Tests")
	print("==================================================")

	VoxelWorld.push_palette()
	ItemDB.init_db()
	RecipeDB.init_db()
	Placeables.register_builtin()

	# -------------------------------------------------------------
	# 1. Storyline Act II & Quest Catalogue
	# -------------------------------------------------------------
	print("\n-- 1. Storyline Act II Quests")
	var qm := QuestManager.new()
	check(qm.available_quests.has(&"story_phosphor_flare"), "Phosphor Brazier story quest registered")
	check(qm.available_quests.has(&"story_siren_hunt"), "Abyssal Siren hunt story quest registered")
	check(qm.available_quests.has(&"story_storm_fortress"), "Storm Fortress incursion story quest registered")
	check(qm.available_quests.has(&"chore_regatta_trial"), "Regatta Trial chore registered")
	check(qm.available_quests.has(&"chore_sparring_bout"), "Sparring bout chore registered")

	var siren_q: QuestDef = qm.available_quests[&"story_siren_hunt"]
	check(siren_q.storyline_act == 2, "Siren quest is assigned to Act II")
	check(siren_q.steps.size() >= 2, "Siren quest has multiple steps")
	check(siren_q.steps[0].type == QuestDef.ObjectiveType.DEFEAT_ENEMY, "Siren step 1 is DEFEAT_ENEMY")

	# -------------------------------------------------------------
	# 2. Boat Upgrades & Small Hold
	# -------------------------------------------------------------
	print("\n-- 2. Boat Upgrades & Small Hold")
	var boat := Boat.new()
	boat.setup(1, null, null, Vector3.ZERO, 0.0, Boat.KIND_ROWBOAT)
	check(boat.get_hold() != null, "Rowboat allocates a small cargo hold")
	check(boat.get_hold().slots.size() >= 6, "Rowboat small hold has at least 6 slots")
	check(not boat.has_lantern, "Boat starts without lantern installed")
	boat.install_lantern()
	check(boat.has_lantern and boat.lantern_lit, "Installing lantern mounts light and sets lit flag")
	boat.toggle_lantern()
	check(not boat.lantern_lit, "Toggling lantern extinguishes it")
	boat.toggle_lantern()
	check(boat.lantern_lit, "Toggling lantern relights it")

	# -------------------------------------------------------------
	# 3. Audio Synthesizer: Water Lap & Fanfare
	# -------------------------------------------------------------
	print("\n-- 3. Audio Synthesizer & Ambience")
	CombatAudio.init_audio(true)
	check(CombatAudio._sounds.has("water_lap"), "CombatAudio baked water_lap stream")
	check(CombatAudio._sounds.has("fanfare"), "CombatAudio baked fanfare stream")

	# -------------------------------------------------------------
	# 4. Settings Rebindable Combat Actions
	# -------------------------------------------------------------
	print("\n-- 4. Settings Menu Rebinding")
	var rebind_actions: Array = []
	for p: Array in SettingsMenu.REBINDABLE:
		rebind_actions.append(p[0])
	check(rebind_actions.has("use"), "Attack / Primary is present in REBINDABLE")
	check(rebind_actions.has("alt_use"), "Block / Parry is present in REBINDABLE")
	check(rebind_actions.has("dodge"), "Dodge roll is present in REBINDABLE")
	check(rebind_actions.has("sneak"), "Sneak / Crouch is present in REBINDABLE")

	# -------------------------------------------------------------
	# Summary
	# -------------------------------------------------------------
	print("\n==================================================")
	print("Act II, Boat & Settings: %d / %d tests passed!" % [passed, total])
	print("==================================================")
	quit(0 if passed == total else 1)
