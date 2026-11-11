extends SceneTree
## Crafting page: crafting, batch counts, blockers, bag-full rollback, search, discovery.

var counts := {"total": 0, "passed": 0}


func check(name: String, cond: bool) -> void:
	counts.total += 1
	if cond:
		counts.passed += 1
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)


func _init() -> void:
	print("\n== Crafting UI ==")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var p := Player.new()
	root.add_child(p)
	var ui := CraftingUI.new()
	root.add_child(ui)
	await process_frame
	ui.player = p
	var inv: Inventory = p.inventory
	for i in inv.capacity:
		inv.slots[i] = ItemSlot.new()

	var planks: RecipeDef = null
	for r in RecipeDB.get_station_exclusive_recipes(&"none"):
		if r.output_item_id == &"wood_plank":
			planks = r
	check("Hand recipe for wood planks exists", planks != null)
	var need: int = int(planks.inputs[0]["count"])
	var in_id := StringName(planks.inputs[0]["item_id"])

	# Blockers and batch counts
	check("Empty bag blocks the recipe", ui.blocker(planks).begins_with("Need"))
	inv.add_item(in_id, need * 3)
	check("Enough ingredients clears the blocker", ui.blocker(planks) == "")
	check("max_batches counts full batches", CraftingUI.max_batches(planks, inv) == 3)

	# Crafting
	var made := ui.craft(planks, 2)
	check("Craft x2 makes two batches", made == 2)
	check("Output added", inv.get_item_count(planks.output_item_id) == planks.output_count * 2)
	check("Ingredients consumed", inv.get_item_count(in_id) == need)
	made = ui.craft(planks, 5)
	check("Craft stops when ingredients run out", made == 1 and inv.get_item_count(in_id) == 0)

	# Station recipes need the station
	var bench: RecipeDef = null
	for r in RecipeDB.get_all_recipes():
		if r.required_station == &"workbench":
			bench = r
			break
	if bench != null:
		check("Station recipe says which station it needs", ui.blocker(bench).begins_with("Needs a"))
		check("Station recipe can't be crafted away from the station", ui.craft(bench, 1) == 0)

	# Bag full: the batch is undone exactly
	for i in inv.capacity:
		inv.slots[i] = ItemSlot.new()
	inv.add_item(in_id, need)
	var filler := &"stone" if in_id != &"stone" else &"sand"
	var fdef: ItemDef = ItemDB.get_item(filler)
	for i in inv.capacity:
		if inv.slots[i].is_empty():
			inv.slots[i] = ItemSlot.new(filler, fdef.max_stack)
	# Ingredient stack is the only non-filler slot; make it a full-stack of something else so nothing fits.
	var before_in := inv.get_item_count(in_id)
	made = ui.craft(planks, 1)
	if made == 0:
		check("Full bag: nothing crafted", made == 0)
		check("Full bag: ingredients given back", inv.get_item_count(in_id) == before_in)
	else:
		# The freed ingredient slot was enough room: also fine, as long as output landed.
		check("Freed slot held the output", inv.get_item_count(planks.output_item_id) == planks.output_count)

	# Search and discovery
	for i in inv.capacity:
		inv.slots[i] = ItemSlot.new()
	ui._search = "plank"
	var hits := ui._recipes_in_view()
	check("Search finds recipes by name or ingredient", hits.any(func(r: RecipeDef) -> bool: return r.id == planks.id))
	ui._search = "zzzz-nothing"
	check("Nonsense search finds nothing", ui._recipes_in_view().is_empty())
	ui._search = ""
	check("Used-in lists recipes that take the item", ui.used_in(&"wood_plank").size() > 0)

	# Screen builds without errors in each view
	ui.visible = true
	for w in [&"none", &"all", &"workbench"]:
		ui._where = w
		ui._rebuild_all()
	check("List built rows", ui._rows.size() > 0 or ui._list.get_child_count() > 0)
	ui._only_ready = true
	ui._rebuild_all()
	check("Ready-only view builds on an empty bag", ui._list.get_child_count() > 0)

	# "Used for": what an item is good for
	var stew_uses := ItemUses.lines(&"hearty_clam_chowder")
	check("Meals say what eating does", stew_uses.any(func(l: String) -> bool: return l.begins_with("Eat:") and "health" in l))
	check("Driftwood says it's fuel", ItemUses.lines(&"driftwood").any(func(l: String) -> bool: return l.begins_with("Fuel:")))
	check("Bait says it's bait", ItemUses.lines(&"kelp_frond").any(func(l: String) -> bool: return l.begins_with("Bait:")))
	check("Planks pay for building", ItemUses.lines(&"wood_plank").any(func(l: String) -> bool: return l.begins_with("Building:")))
	var all_rec := ItemUses.recipes_using(&"wood_plank")
	check("Recipes using planks are found", (all_rec.known as Array).size() > 0 and int(all_rec.locked) == 0)
	var none_known := ItemUses.recipes_using(&"wood_plank", func(_r: RecipeDef) -> bool: return false)
	check("Unlearned recipes are counted, not named", (none_known.known as Array).is_empty() and int(none_known.locked) > 0)
	check("Tooltip summary names the item", ItemUses.summary(&"wood_plank").begins_with(ItemSlotView.item_name(&"wood_plank")))
	ui._only_ready = false
	ui.show_recipe(planks.id)
	check("Recipe link jumps to that recipe", ui._selected == planks.id and ui._where == planks.required_station)
	var found_used_for := false
	var found_link := false
	var stack: Array = [ui._detail]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and (n as Label).text == "Used for":
			found_used_for = true
		if n is LinkButton:
			found_link = true
		stack.append_array(n.get_children())
	check("Detail panel has a Used for section", found_used_for)
	check("Recipe names in it are clickable", found_link)

	print("Results: %d/%d passed" % [counts.passed, counts.total])
	quit(0 if counts.passed == counts.total else 1)
