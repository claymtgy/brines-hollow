extends SceneTree
## Talking to settlement villagers opens a real dialogue, and you can pick their job by hand.
##   godot --headless --path . -s tests/test_village_jobs.gd

var counts := {"total": 0, "passed": 0}


func check(name: String, cond: bool) -> void:
	counts.total += 1
	if cond:
		counts.passed += 1
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)


class FakeHud extends Node:
	var last := ""
	func show_toast(t: String) -> void: last = t
	func set_prompt(_t: String) -> void: pass


class FakeEntities extends Node:
	var entities := {}


class FakeVillages extends Node:
	var dialogue: DialogueBox


class FakeMain extends Node:
	var village: SettlementManager
	var entities: FakeEntities
	var hud: FakeHud
	var npc_villages: FakeVillages
	var player = null
	var quests = null
	var settings_menu = null
	var is_net := false


func _init() -> void:
	print("\n== Village jobs and villager dialogue ==")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _buttons(dlg: DialogueBox) -> Array:
	var out := []
	for b in dlg._choices.get_children():
		if b is Button and not b.is_queued_for_deletion():
			out.append(b)
	return out


func _labels(dlg: DialogueBox) -> Array:
	return _buttons(dlg).map(func(b: Button) -> String: return b.text)


func _press(dlg: DialogueBox, text: String) -> bool:
	for b: Button in _buttons(dlg):
		if b.text == text or b.text == "• " + text:
			b.pressed.emit()
			return true
	return false


func _run() -> void:
	ItemDB.init_db()
	# --- the job lock survives a save
	var d := DrifterDef.new(&"drifter_0", "Mara", DrifterDef.Profession.FISHER)
	d.job_locked = true
	var back := DrifterDef.deserialize(d.serialize())
	check("Job lock is saved", back.job_locked)
	check("Old saves load unlocked", not DrifterDef.deserialize({"id": "x", "name": "X"}).job_locked)

	# --- a little town: two recruited villagers and a farming station nobody works
	var main := FakeMain.new()
	get_root().add_child(main)
	main.village = SettlementManager.new()
	main.hud = FakeHud.new()
	main.add_child(main.hud)
	main.entities = FakeEntities.new()
	main.add_child(main.entities)
	main.npc_villages = FakeVillages.new()
	main.add_child(main.npc_villages)
	main.npc_villages.dialogue = DialogueBox.new()
	main.npc_villages.add_child(main.npc_villages.dialogue)
	main.npc_villages.dialogue.setup(main)

	var vm := VillageManager.new()
	vm.main = main
	main.add_child(vm)
	vm._ready_done = true
	vm.process_mode = Node.PROCESS_MODE_DISABLED   # no world here: test the logic, not the walking
	for i in 2:
		var def := DrifterDef.new(StringName("drifter_%d" % i), ["Mara", "Tobin"][i],
			[DrifterDef.Profession.FISHER, DrifterDef.Profession.CARPENTER][i])
		def.morale = 0.5   # no gratitude gift in the way
		var npc := DrifterNPC.new()
		vm.add_child(npc)
		npc.setup(i, def, Vector3(i * 2.0, 0, 0), 7 + i)
		npc.recruited = true
		vm.npcs.append(npc)
		main.village.drifters.append(def)
	var mara := vm.npcs[0]
	var tobin := vm.npcs[1]
	var dlg := main.npc_villages.dialogue

	# --- talking opens the dialogue box, not just a toast
	vm._talk(mara)
	check("Talking opens a dialogue", dlg.is_open())
	check("Dialogue offers Change job and Goodbye", _labels(dlg).has("Change job") and _labels(dlg).has("Goodbye"))
	check("Speaker is the villager", dlg._speaker.text.begins_with("Mara"))

	# --- the job menu
	_press(dlg, "Change job")
	var labels := _labels(dlg)
	check("Job menu lists every job plus Any job and Back", labels.size() == VillageManager.JOB_ORDER.size() + 2
		and labels.has("Any job") and labels.has("Back"))
	check("Current job is marked", labels.has("• Fisher"))
	_press(dlg, "Farmer")
	check("Picking a job changes it", mara.def.profession == DrifterDef.Profession.FARMER)
	check("A picked job is locked", mara.def.job_locked)
	check("The villager's label follows", mara.label.text.contains("Farmer"))
	check("Back at the main menu after choosing", _labels(dlg).has("Change job"))

	# --- the town's auto-assignment leaves locked villagers alone
	var st := WorldEntity.new()
	st.entity_id = &"ranch_station"
	main.entities.add_child(st)
	main.entities.entities[Vector3i.ZERO] = st
	vm._update_job_assignments()
	check("Locked villager isn't pulled to an empty station", mara.def.profession == DrifterDef.Profession.FARMER)
	check("An unlocked villager fills it instead", tobin.def.profession == DrifterDef.Profession.RANCHER and not tobin.def.job_locked)

	# --- "Any job" hands the villager back to the town
	vm.set_job(0, DrifterDef.Profession.TRADER, false)
	check("Any job unlocks", not mara.def.job_locked)
	vm.set_job(1, DrifterDef.Profession.BUILDER, true)
	vm._update_job_assignments()
	check("Unlocked villager now covers the empty ranch", mara.def.profession == DrifterDef.Profession.RANCHER)
	check("Locked builder stays a builder", tobin.def.profession == DrifterDef.Profession.BUILDER)

	_press(dlg, "Goodbye")
	check("Goodbye closes the dialogue", not dlg.is_open())

	# --- a villager with a task to offer can still be given a new job
	main.quests = QuestManager.new()   # the catalogue includes "Mara's Tide Catch"
	vm._talk(mara)
	check("Mara opens with her task", dlg._text.text.contains("Mara's Tide Catch"))
	check("The task offer has Change job too", _labels(dlg).has("Change job"))
	_press(dlg, "Change job")
	check("Change job from the offer opens the job menu", _labels(dlg).has("Any job"))
	_press(dlg, "Fisher")
	check("...and assigns the job", mara.def.profession == DrifterDef.Profession.FISHER and mara.def.job_locked)
	check("The task is still on offer from the menu", _labels(dlg).has("Any tasks?"))
	_press(dlg, "Goodbye")
	vm._talk(mara)
	check("After putting it off she doesn't open with the task again", _labels(dlg).has("Change job")
		and _labels(dlg).has("Any tasks?") and not _labels(dlg).has("I'll do it"))
	_press(dlg, "Any tasks?")
	_press(dlg, "Not now")
	check("Not now goes back to the conversation instead of closing", dlg.is_open() and _labels(dlg).has("Change job"))
	_press(dlg, "Any tasks?")
	_press(dlg, "I'll do it")
	check("The task can still be accepted", main.quests.is_quest_active(&"chore_mara_catch"))
	main.quests = null

	# --- the dialogue's buttons wrap instead of running off the panel
	check("Choice row wraps", dlg._choices is HFlowContainer)

	print("\nSummary: %d / %d tests passed!" % [counts.passed, counts.total])
	main.queue_free()
	quit(0 if counts.passed == counts.total else 1)
