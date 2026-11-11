extends SceneTree
## The village cook's pantry orders: targets, cooking from the town's stores, saving, the screen.

var counts := {"total": 0, "passed": 0}


func check(name: String, cond: bool) -> void:
	counts.total += 1
	if cond:
		counts.passed += 1
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)


## Stands in for VillageManager on the orders screen.
class FakeVillage extends Node:
	var main: Node
	var orders := CookOrders.new()
	var stores: Array = []
	var stations: Array = []
	func cook_orders() -> CookOrders: return orders
	func town_stores() -> Array: return stores
	func town_cook_stations() -> Array: return stations
	func set_cook_order(id: StringName, n: int) -> void: orders.set_target(id, n)


class FakeMain extends Node:
	var player: Player


func _init() -> void:
	print("\n== Cook pantry orders ==")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _stock(inv: Inventory, r: RecipeDef, times: int) -> void:
	for inp: Dictionary in r.inputs:
		inv.add_item(StringName(inp["item_id"]), int(inp["count"]) * times)


func _run() -> void:
	ItemDB.init_db()
	RecipeDB.init_db()
	var meals := CookOrders.meal_recipes()
	check("There are meals a cook can make", meals.size() >= 3)
	var all_food := true
	for r in meals:
		var it := ItemDB.get_item(r.output_item_id)
		if it == null or it.category != ItemDef.Category.FOOD or not CraftingStation.is_cooking_station(r.required_station):
			all_food = false
	check("Only timed food at cooking stations", all_food)

	var stew := RecipeDB.get_recipe(&"cook_bouillabaisse")
	var orders := CookOrders.new()
	orders.set_target(stew.output_item_id, 999)
	check("Target clamps to the max", orders.target(stew.output_item_id) == CookOrders.MAX_TARGET)
	orders.set_target(stew.output_item_id, 0)
	check("0 turns an order off", not orders.has_orders())

	# --- cooking from the stores
	var pantry := Inventory.new(16)
	var depot := Inventory.new(36)
	var stores: Array = [pantry, depot]
	var pot := CraftingStation.new(&"hearth_pot", "Hearth Stew Pot")
	var key := CookOrders.key_for(Vector3i(3, 4, 5))
	var want := stew.output_count * 2
	orders.set_target(stew.output_item_id, want)
	check("No ingredients: nothing to cook", orders.next_meal(&"hearth_pot", stores) == null)
	check("Status names the missing ingredient", orders.status(stew.output_item_id, stores).begins_with("Needs"))
	_stock(depot, stew, 5)
	check("Wrong station isn't used", orders.next_meal(&"campfire", stores) == null or orders.next_meal(&"campfire", stores).required_station == &"campfire")
	var r := orders.work_station(pot, key, stores)
	check("Cook starts the stew from the depot", r == stew and pot.is_active)
	check("Ingredients came out of the stores", CookOrders.count_in(stores, StringName(stew.inputs[0]["item_id"]))
		== int(stew.inputs[0]["count"]) * 4)
	check("Status says it's cooking", orders.status(stew.output_item_id, stores).begins_with("Cooking"))
	check("Busy pot: no second dish yet", orders.work_station(pot, key, stores) == null and pot.queue.is_empty())
	pot.tick(stew.craft_time_sec)
	orders.work_station(pot, key, stores)
	check("Finished dish goes to the pantry first", pantry.get_item_count(stew.output_item_id) == stew.output_count
		and pot.output.is_empty())
	check("And the next one starts", pot.is_active)
	pot.tick(stew.craft_time_sec)
	var r3 := orders.work_station(pot, key, stores)
	check("At the target the cook stops", r3 == null and not pot.is_active
		and CookOrders.count_in(stores, stew.output_item_id) == want)
	check("Status: stocked", orders.status(stew.output_item_id, stores) == "Stocked")
	check("Nothing left pending", not orders.pending.has(key))
	pantry.remove_item(stew.output_item_id, 1)
	check("Someone eats one: the cook makes more", orders.work_station(pot, key, stores) == stew)
	pot.tick(stew.craft_time_sec)
	orders.collect(pot, key, stores)

	# --- a player's dish in the tray is left alone
	var p_inv := Inventory.new(20)
	_stock(p_inv, stew, 1)
	pot.craft_recipe(stew.id, p_inv, 1)
	pot.tick(stew.craft_time_sec)
	var before := CookOrders.count_in(stores, stew.output_item_id)
	orders.collect(pot, key, stores)
	check("Player's dish stays in the tray", pot.output_count() == stew.output_count
		and CookOrders.count_in(stores, stew.output_item_id) == before)
	pot.take_output(p_inv)

	# --- fires get fed from the stores
	var smoke := RecipeDB.get_recipe(&"smoke_fish_ration")
	var smoker := CraftingStation.new(&"smokehouse", "Smokehouse", true)
	orders.set_target(smoke.output_item_id, 4)
	_stock(depot, smoke, 2)
	depot.add_item(&"driftwood", 4)
	var r4 := orders.work_station(smoker, "smoker", stores)
	check("Cook lights the smokehouse with store wood", smoker.fuel_remaining_sec > 0.0
		and depot.get_item_count(&"driftwood") < 4)
	check("and starts smoking", r4 == smoke)

	# --- recipe book: unknown meals aren't offered
	var book := RecipeBook.new()
	var known := CookOrders.meal_recipes(book)
	check("Locked meals need learning first", known.size() < meals.size() or not known.has(stew) or book.knows(stew.id))

	# --- save / load
	var saved := orders.serialize()
	var back := CookOrders.new()
	back.deserialize(JSON.parse_string(JSON.stringify(saved)))
	check("Orders survive save/load", back.target(stew.output_item_id) == want and back.target(smoke.output_item_id) == 4)
	check("Pending dishes survive save/load", back.pending_count(smoke.output_item_id) == orders.pending_count(smoke.output_item_id))
	var town := SettlementManager.new()
	town.cook_orders.set_target(stew.output_item_id, 10)
	var town2 := SettlementManager.new()
	town2.deserialize(JSON.parse_string(JSON.stringify(town.serialize())))
	check("Settlement saves the cook's orders", town2.cook_orders.target(stew.output_item_id) == 10)
	var old_save := SettlementManager.new()
	old_save.deserialize({"name": "Old"})
	check("Old saves load with no orders", not old_save.cook_orders.has_orders())

	# --- the orders screen
	var fm := FakeMain.new()
	root.add_child(fm)
	fm.player = Player.new()
	root.add_child(fm.player)
	var fv := FakeVillage.new()
	fv.main = fm
	fv.stores = stores
	root.add_child(fv)
	var ui := CookOrdersUI.new()
	root.add_child(ui)
	await process_frame
	for m in meals:
		fm.player.recipes.learn(m.id, "test")
	ui.open(fv, "Corwin")
	check("Screen opens with a row per known meal", ui.is_open() and ui._rows.size() == meals.size())
	check("Title names the cook", "Corwin" in ui._title.text)
	check("No fire in town is called out", "no cooking fire" in ui._where.text)
	var i := ui._items.find(stew.output_item_id)
	ui._sel = i
	ui._bump(stew.output_item_id, CookOrders.STEP)
	check("+ raises the order by a step", fv.orders.target(stew.output_item_id) == CookOrders.STEP)
	ui._refresh()
	check("Row shows the order", (ui._rows[i].target as Label).text == str(CookOrders.STEP))
	ui._bump(stew.output_item_id, -99)
	ui._refresh()
	check("Down to 0 shows off", (ui._rows[i].target as Label).text == "off")
	ui.close()
	check("Close hands control back", not ui.is_open() and fm.player.input_enabled)

	print("Results: %d/%d passed" % [counts.passed, counts.total])
	quit(0 if counts.passed == counts.total else 1)
