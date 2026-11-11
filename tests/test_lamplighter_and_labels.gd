extends SceneTree
## Lamplighter renders fish into lamp oil and keeps the lighthouse filled; every job has its own label.

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


class FakeMain extends Node:
	var village: SettlementManager
	var entities = null
	var hud: FakeHud
	var is_net := false
	var _beam: LighthouseBeam


func _init() -> void:
	print("\n== Lamplighter and job labels ==")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _lamplighter() -> DrifterDef:
	var d := DrifterDef.new(&"wren", "Wren", DrifterDef.Profession.LAMPLIGHTER)
	d.assigned_room_id = 0
	d.morale = 1.0
	d.current_routine = DrifterDef.Routine.WORK
	return d


func _run() -> void:
	ItemDB.init_db()
	# --- every profession has its own name on the villager
	var all_named := true
	for prof in DrifterDef.Profession.values():
		var npc := DrifterNPC.new()
		npc.def = DrifterDef.new(&"x", "X", prof)
		var label := npc.profession_name()
		var expect: String = npc.def.profession_name().replace("Smoker-Chef", "Smoker & Cook")
		if label != expect:
			all_named = false
			print("    %s labelled %s" % [expect, label])
		npc.free()
	check("Every job label matches its profession", all_named)
	var b := DrifterNPC.new()
	b.def = DrifterDef.new(&"b", "Bram", DrifterDef.Profession.BUILDER)
	check("Builders are labelled Builder", b.profession_name() == "Builder")
	check("Builder label isn't Rancher", b.profession_name() != "Rancher")
	b.free()

	# --- shift work: fish -> lamp oil, kelp left alone
	var depot := StorageContainer.new("Depot", 36)
	depot.deposit(&"silver_mackerel", 4)
	depot.deposit(&"kelp_frond", 5)
	var w := _lamplighter()
	var made := w.tick_work(200.0, depot)
	check("A shift renders fish into fish oil", int(made.get(&"fish_oil", 0)) == 1
		and depot.inventory.get_item_count(&"fish_oil") == 1)
	check("Two mackerel per flask", depot.inventory.get_item_count(&"silver_mackerel") == 2)
	check("Kelp isn't destroyed any more", depot.inventory.get_item_count(&"kelp_frond") == 5)
	check("No phantom kelp_fuel", not made.has(&"kelp_fuel"))
	depot.deposit(&"fish_oil", DrifterDef.LAMP_OIL_STOCK)
	var made2 := w.tick_work(200.0, depot)
	check("Stops at the oil stock so fishers' catch isn't all burned", made2.is_empty()
		and depot.inventory.get_item_count(&"silver_mackerel") == 2)
	var dry := StorageContainer.new("Empty", 8)
	check("No fish: nothing made", w.tick_work(200.0, dry).is_empty())

	# --- the lighthouse lamp
	var fm := FakeMain.new()
	fm.hud = FakeHud.new()
	fm.add_child(fm.hud)
	fm.village = SettlementManager.new()
	fm._beam = LighthouseBeam.new()
	fm.add_child(fm._beam)
	root.add_child(fm)
	var vm := VillageManager.new()
	vm.main = fm
	var npc := DrifterNPC.new()
	npc.def = _lamplighter()
	npc.recruited = true
	vm.npcs.append(npc)
	fm._beam.fuel_sec = 100.0
	check("No oil in store: lamp stays as it is", not vm.lamplighter_shift() and fm._beam.fuel_sec == 100.0)
	fm.village.town_depot.deposit(&"fish_oil", 2)
	check("Low lamp + oil in store: lamplighter fills it", vm.lamplighter_shift()
		and is_equal_approx(fm._beam.fuel_sec, 100.0 + VillageManager.LAMP_OIL_SEC))
	check("One flask used", fm.village.town_depot.inventory.get_item_count(&"fish_oil") == 1)
	check("The town hears about it", "Wren" in fm.hud.last and "lighthouse" in fm.hud.last)
	fm._beam.fuel_sec = VillageManager.LAMP_REFILL_BELOW + 10.0
	check("Lamp well stocked: oil kept", not vm.lamplighter_shift()
		and fm.village.town_depot.inventory.get_item_count(&"fish_oil") == 1)
	fm._beam.fuel_sec = 0.0
	npc.def.current_routine = DrifterDef.Routine.SLEEP
	check("Asleep: no refill", not vm.lamplighter_shift())
	npc.def.current_routine = DrifterDef.Routine.SOCIALIZE
	check("Up at dusk: refills", vm.lamplighter_shift())
	npc.recruited = false
	fm._beam.fuel_sec = 0.0
	check("Not yet recruited: no refill", not vm.lamplighter_shift())
	npc.free()
	vm.free()

	print("Results: %d/%d passed" % [counts.passed, counts.total])
	quit(0 if counts.passed == counts.total else 1)
