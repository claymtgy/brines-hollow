extends SceneTree
## Verifies Wren dialogue polish, lighthouse messaging, and Act I quest bridging.

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
	print("Running Wren Dialogue & Lighthouse Polish Tests...")
	print("==================================================")

	ItemDB.init_db()
	RecipeDB.init_db()

	# 1. Check tut_7_sea in MISSIONS
	var tut7: Dictionary = {}
	for m in Tutorial.MISSIONS:
		if m.id == &"tut_7_sea":
			tut7 = m
			break

	check(not tut7.is_empty(), "tut_7_sea exists in Tutorial.MISSIONS")
	check(tut7.get("intro", "").contains("lighthouse"), "tut_7_sea intro mentions lighthouse")
	check(tut7.get("done", "").contains("lighthouse"), "tut_7_sea done mentions lighthouse")
	check(tut7.get("done", "").contains("fish oil"), "tut_7_sea done mentions fish oil")
	check(tut7.get("done", "").contains("Elder Brenda and Old Corin"), "tut_7_sea done mentions Brenda and Corin")
	check(tut7.get("done", "").contains("don't need to sail searching"), "tut_7_sea done clarifies players do not need to search for them first")
	check(tut7.get("done", "").contains("{quest_log_toggle}"), "tut_7_sea done references {quest_log_toggle}")

	# 2. Check Tutorial instance hints and formatting
	var tut := Tutorial.new()
	var qm := QuestManager.new()

	var q1: QuestDef = qm.available_quests[&"story_first_hearth"]
	var hint_q1_s0: String = tut._hint_for(q1, 0)
	var hint_q1_s1: String = tut._hint_for(q1, 1)
	var hint_q1_s2: String = tut._hint_for(q1, 2)
	check(hint_q1_s0.contains("Pickaxe"), "story_first_hearth step 0 hint mentions Pickaxe")
	check(hint_q1_s1.contains("Hammer"), "story_first_hearth step 1 hint mentions Hammer and room requirements")
	check(hint_q1_s2.contains("signal smoke"), "story_first_hearth step 2 hint mentions signal smoke and inviting a drifter")

	var q2: QuestDef = qm.available_quests[&"story_tide_tackle"]
	var hint_q2_s0: String = tut._hint_for(q2, 0)
	var hint_q2_s1: String = tut._hint_for(q2, 1)
	check(hint_q2_s0.contains("Rod"), "story_tide_tackle step 0 hint mentions Rod")
	check(hint_q2_s1.contains("Salt Pan"), "story_tide_tackle step 1 hint mentions Salt Pan")

	# 3. Check QuestLogUI lore
	var qlog := QuestLogUI.new()
	var lore_q1: String = qlog._get_lore_for_quest(q1)
	var lore_q2: String = qlog._get_lore_for_quest(q2)
	check(lore_q1.contains("word across the water") and lore_q1.contains("shore"), "QuestLogUI lore for story_first_hearth explains word was sent across the water")
	check(lore_q2.contains("word asking") and lore_q2.contains("on your beach"), "QuestLogUI lore for story_tide_tackle explains tasks are done on your beach")

	tut.queue_free()
	qlog.queue_free()

	print("==================================================")
	print("Results: %d/%d passed" % [passed, total])
	print("==================================================")
	quit(0 if passed == total else 1)
