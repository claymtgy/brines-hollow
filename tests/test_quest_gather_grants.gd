extends SceneTree
## Harvesting from placed furniture (salt pans, crab pots...) counts toward "collect N" quests;
## taking items out of a chest does not.
##   godot --headless --path . -s tests/test_quest_gather_grants.gd

var counts := {"total": 0, "passed": 0}


func check(name: String, cond: bool) -> void:
	counts.total += 1
	if cond:
		counts.passed += 1
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)


class FakeMain extends Node:
	var player: Player
	var hud = null
	var is_net := false


func _init() -> void:
	print("\n== Quest credit for harvested items ==")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _salt_step(qm: QuestManager) -> QuestDef.QuestStep:
	return (qm.active_quests[&"story_tide_tackle"] as QuestDef).steps[1]


func _run() -> void:
	ItemDB.init_db()
	var main := FakeMain.new()
	get_root().add_child(main)
	var p := Player.new()
	p.quests = QuestManager.new()
	main.player = p
	var em := EntityManager.new()
	em.main = main
	em.process_mode = Node.PROCESS_MODE_DISABLED   # no world or sky here
	main.add_child(em)
	p.quests.accept_quest(&"story_tide_tackle")

	var pan := em.spawn_entity(&"salt_pan", Vector3i(10, 5, 10), 0) as SaltPanEntity
	pan.pan.accumulated_salt = 3
	em._authority_action(pan.grid_coord, &"harvest", {}, 1)
	check("Collected salt lands in the pack", p.inventory.get_item_count(&"sea_salt") == 3)
	check("Placed salt pan counts toward the sea salt step", _salt_step(p.quests).is_completed)

	# a fresh copy of the quest: chest withdrawals must not count
	p.quests = QuestManager.new()
	p.quests.accept_quest(&"story_tide_tackle")
	var chest := em.spawn_entity(&"chest", Vector3i(20, 5, 20), 0) as ChestEntity
	if chest != null:
		chest.container.deposit(&"sea_salt", 5)
		em._grant(1, [[&"sea_salt", 2]], "Took 2 sea salt")   # what a chest withdrawal does
		check("Taking salt from a chest doesn't count", _salt_step(p.quests).current_count == 0)
	else:
		check("chest entity type exists", false)

	print("\nSummary: %d / %d tests passed!" % [counts.passed, counts.total])
	p.free()
	main.queue_free()
	quit(0 if counts.passed == counts.total else 1)
