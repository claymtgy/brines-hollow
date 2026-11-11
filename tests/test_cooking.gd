extends SceneTree
## Timed cooking: queue, fire-out pause, output tray, collecting, cancelling, saving.

var counts := {"total": 0, "passed": 0}


func check(name: String, cond: bool) -> void:
	counts.total += 1
	if cond:
		counts.passed += 1
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)


func _init() -> void:
	print("\n== Timed cooking ==")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _stock(inv: Inventory, r: RecipeDef, times: int) -> void:
	for inp: Dictionary in r.inputs:
		inv.add_item(StringName(inp["item_id"]), int(inp["count"]) * times)


func _run() -> void:
	var stew := RecipeDB.get_recipe(&"cook_bouillabaisse")
	var smoke := RecipeDB.get_recipe(&"smoke_fish_ration")
	check("Stew is a timed recipe", CraftingStation.is_timed(stew))
	var planks: RecipeDef = null
	for r in RecipeDB.get_all_recipes():
		if r.required_station == &"workbench" and r.craft_time_sec > 0.0:
			planks = r
			break
	check("Workbench recipes stay instant", planks == null or not CraftingStation.is_timed(planks))

	# --- queue and tray
	var inv := Inventory.new()
	var pot := CraftingStation.new(&"hearth_pot", "Hearth Stew Pot")
	_stock(inv, stew, 3)
	check("Cook x3 accepted", pot.craft_recipe(stew.id, inv, 3))
	check("One cooking, two queued", pot.is_active and pot.queue.size() == 2 and pot.batch_remaining == 3)
	check("All ingredients paid up front", not stew.can_craft_with(inv))
	pot.tick(stew.craft_time_sec)
	check("First dish lands in the tray", pot.output_count() == stew.output_count and pot.queue.size() == 1)
	check("Next dish starts on its own", pot.is_active and pot.cook_timer == 0.0)
	pot.tick(stew.craft_time_sec)
	pot.tick(stew.craft_time_sec)
	check("All three done, pot idle", not pot.is_active and pot.output_count() == stew.output_count * 3)
	var taken := pot.take_output(inv)
	check("Take output moves dishes to the bag", int(taken.get(stew.output_item_id, 0)) == stew.output_count * 3
		and inv.get_item_count(stew.output_item_id) == stew.output_count * 3 and pot.output.is_empty())

	# --- queue limit
	_stock(inv, stew, 10)
	pot.craft_recipe(stew.id, inv, 10)
	check("Queue caps at one cooking + MAX_QUEUE", pot.batch_remaining == CraftingStation.MAX_QUEUE + 1)
	check("Full pot rejects more", pot.queue_full() and not pot.craft_recipe(stew.id, inv, 1))

	# --- cancel refunds
	var before := inv.get_item_count(StringName(stew.inputs[0]["item_id"]))
	check("Cancel a queued dish", pot.cancel_queued(0, inv))
	check("Cancel refunds ingredients",
		inv.get_item_count(StringName(stew.inputs[0]["item_id"])) == before + int(stew.inputs[0]["count"]))

	# --- save / load round trip
	var saved := pot.serialize_cooking()
	var pot2 := CraftingStation.new(&"hearth_pot", "Pot 2")
	pot2.deserialize_cooking(saved)
	check("Queue survives save/load", pot2.queue == pot.queue)

	# --- fire out pauses instead of cancelling
	var smoker := CraftingStation.new(&"smokehouse", "Smokehouse", true)
	smoker.add_fuel_time(smoke.craft_time_sec * 0.5)
	_stock(inv, smoke, 1)
	smoker.craft_recipe(smoke.id, inv, 1)
	smoker.tick(smoke.craft_time_sec * 0.5)
	smoker.tick(1.0)
	check("Fire out: dish paused, progress kept", smoker.is_paused() and is_equal_approx(smoker.cook_progress(), 0.5))
	smoker.add_fuel_time(60.0)
	smoker.tick(smoke.craft_time_sec * 0.5)
	check("Refuelled: dish finishes", not smoker.is_active and smoker.output_count() == smoke.output_count)

	# --- station entity: collect + quest credit + prompt
	var p := Player.new()
	root.add_child(p)
	await process_frame
	var ent := StationEntity.new(&"hearth_pot", "Hearth Stew Pot", Vector3i.ZERO)
	_stock(p.inventory, stew, 2)
	ent.station.craft_recipe(stew.id, p.inventory, 2)
	check("Prompt shows what's cooking", "cooking" in ent.get_interaction_prompt(p))
	ent.tick(stew.craft_time_sec)
	ent.tick(stew.craft_time_sec)
	check("Prompt offers to collect", ent.get_interaction_prompt(p).begins_with("F  Collect"))
	var got := ent.collect_output(p)
	check("Collect fills the bag", got == stew.output_count * 2 and ent.station.output.is_empty())

	# --- crafting page starts cooking at the station
	var ui := CraftingUI.new()
	root.add_child(ui)
	await process_frame
	ui.player = p
	ui._origin_station = ent
	check("Locked recipe can't be cooked", ui.craft(stew, 1) == 0 or p.recipes == null or p.recipes.knows(stew.id))
	if p.recipes != null:
		p.recipes.learn(stew.id, "test")
	_stock(p.inventory, stew, 2)
	var started := ui.craft(stew, 2)
	check("Crafting page queues dishes instead of making them instantly",
		started == 2 and ent.station.batch_remaining == 2 and p.inventory.get_item_count(stew.output_item_id) == stew.output_count * 2)
	ui.visible = true
	ui._where = &"hearth_pot"
	ui._rebuild_all()
	check("Cooking panel tracks live bars", ui._live.size() >= 2)
	ent.tick(stew.craft_time_sec)
	ui._rebuild_all()
	check("Where list and panel rebuild with a dish in the tray", ui._list.get_child_count() > 0)

	print("Results: %d/%d passed" % [counts.passed, counts.total])
	quit(0 if counts.passed == counts.total else 1)
