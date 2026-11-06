extends SceneTree
## Server-side farm rules for co-op (NetFarm.server_apply):
##   godot --headless --path . -s tests/test_netfarm.gd

var passed := 0
var total := 0


func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)


func _init() -> void:
	ItemDB.init_db()
	CropDB.init_db()
	var farm := NetFarm.new(30.0, 7.0)   # no session: acts as the authority
	var crop_def: CropDef = CropDB.get_crop_by_seed(&"seed_shore_wheat")
	check(crop_def != null, "shore wheat crop exists")
	var crop: StringName = crop_def.id
	var cell := Vector3i(10, 50, 10)

	var g := farm.server_apply(cell, {"a": "plant", "crop": crop})
	check(farm.get_plot(cell) != null and not farm.get_plot(cell).is_empty(), "plant on untilled ground tills and plants")
	check(g.is_empty(), "first planter gets no refund")

	g = farm.server_apply(cell, {"a": "plant", "crop": crop})
	check(g.size() == 1 and g[0][0] == crop_def.seed_item_id and g[0][1] == 1, "second planter on the same plot is refunded their seed")

	g = farm.server_apply(cell, {"a": "harvest"})
	check(g.is_empty(), "harvesting an unripe crop grants nothing")

	var plot: CropPlot = farm.get_plot(cell)
	plot.current_stage = crop_def.growth_stages
	g = farm.server_apply(cell, {"a": "harvest"})
	check(g.size() == 2 and int(g[0][1]) > 0, "harvesting a mature crop grants produce + seeds")
	g = farm.server_apply(cell, {"a": "harvest"})
	check(g.is_empty(), "a second harvest of the same plot grants nothing (no duplication)")

	var pan := farm.add_salt_pan(Vector3i(20, 30, 20))
	pan.accumulated_salt = 3
	g = farm.server_apply(Vector3i(20, 30, 20), {"a": "salt"})
	check(g.size() == 1 and g[0][0] == &"sea_salt" and g[0][1] == 3, "salt pan harvest grants the accumulated salt")
	g = farm.server_apply(Vector3i(20, 30, 20), {"a": "salt"})
	check(g.is_empty(), "salt can't be harvested twice")

	var state := farm.cell_state(cell)
	var replica := NetFarm.new(30.0, 7.0)
	replica.apply_cell_state(cell, state)
	check(replica.get_plot(cell) != null and replica.get_plot(cell).crop_id == plot.crop_id, "cell state replicates to a client copy")
	replica.apply_cell_state(cell, {})
	check(replica.get_plot(cell) == null, "empty cell state removes the plot on the client")

	var cost := BuildCosts.prefab_cost(5, 0)
	check(cost.has(&"wood_plank") and cost.has(&"sand") and cost.has(&"cobblestone"), "hut costs planks, sand (whitewash) and cobblestone")
	var inv := Inventory.new()
	check(not BuildCosts.can_afford(inv, cost), "empty inventory can't afford the hut")
	for item: StringName in cost:
		inv.add_item(item, cost[item])
	check(BuildCosts.can_afford(inv, cost), "inventory with exact materials can afford the hut")
	BuildCosts.pay(inv, cost)
	check(not BuildCosts.can_afford(inv, cost), "paying removes the materials")

	print("Summary: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)
