extends SceneTree
## Recipe unlocks + tutorial data:  godot --headless --path . -s tests/test_recipes_tutorial.gd

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
	RecipeDB.init_db()
	Placeables.register_builtin()
	RecipeBook.register_scroll_items()

	var book := RecipeBook.new()
	check(book.knows(&"craft_wood_plank"), "plain recipes are known from the start")
	check(not book.knows(&"cook_roasted_mackerel"), "mackerel recipe starts locked")
	check(not book.knows(&"place_crab_pot"), "crab pot recipe starts locked")

	# Every lockable recipe exists and has at least one way to be learned.
	var all_exist := true
	var reachable := true
	var scroll_ok := true
	for rid: StringName in RecipeBook.locked_ids():
		if not RecipeDB.has_recipe(rid):
			all_exist = false
			print("     missing recipe: ", rid)
		var via := false
		for list in RecipeBook.DISCOVERY.values():
			via = via or list.has(rid)
		for list in RecipeBook.PROFESSION.values():
			via = via or list.has(rid)
		for m in Tutorial.MISSIONS:
			via = via or m.rewards.get("recipes", []).has(rid)
		via = via or RecipeBook.MERCHANT_SCROLLS.has(rid)
		via = via or RecipeBook.FOUND_SCROLLS.has(rid) or rid == RecipeBook.MINE_SCROLL
		for list in RecipeBook.SECRET.values():
			via = via or list.has(rid)
		via = via or RecipeBook.auto_key(rid) != &""   # learned on first holding its key ingredient
		if not via:
			reachable = false
			print("     unreachable: ", rid)
		scroll_ok = scroll_ok and ItemDB.has_item(StringName(RecipeBook.SCROLL_PREFIX + String(rid)))
	check(all_exist, "every lockable recipe id exists in RecipeDB")
	check(reachable, "every locked recipe has an unlock path (discovery, drifter, tutorial or scroll)")
	check(scroll_ok, "every locked recipe has a readable scroll item")

	# Discovery through the inventory signal.
	var inv := Inventory.new()
	var learned := []
	book.recipe_learned.connect(func(r: StringName, src: String) -> void: learned.append([r, src]))
	inv.item_added.connect(func(id: StringName, _n: int) -> void: book.on_item_acquired(id, inv))
	inv.add_item(&"silver_mackerel", 1)
	check(book.knows(&"cook_roasted_mackerel"), "catching a mackerel teaches roasted mackerel")
	check(learned.size() >= 1 and learned[0][1] == "discovery", "discovery is reported as the source")
	var n := learned.size()
	inv.add_item(&"silver_mackerel", 1)
	check(learned.size() == n, "a second mackerel teaches nothing new")

	# Scroll: learned and consumed on pickup.
	inv.add_item(&"recipe_scroll_brew_chicory_coffee", 1)
	check(book.knows(&"brew_chicory_coffee"), "reading a scroll teaches its recipe")
	check(inv.get_item_count(&"recipe_scroll_brew_chicory_coffee") == 0, "the scroll is consumed")

	# Drifter professions.
	var got := book.on_drifter_recruited(3)   # SMOKER_CHEF
	check(book.knows(&"place_smokehouse") and book.knows(&"cook_bouillabaisse"), "recruiting a smoker-chef teaches their trade")
	check(got.size() >= 2, "drifter unlocks report what was learned")

	# Station listing splits known / hidden.
	var fresh := RecipeBook.new()
	var info := fresh.recipes_for(&"campfire")
	check(info.hidden > 0, "a fresh player sees hidden campfire recipes")
	var before: int = info.known.size()
	fresh.learn(&"cook_roasted_mackerel", "quest")
	check(fresh.recipes_for(&"campfire").known.size() == before + 1, "learning moves a recipe into the known list")

	# Save / load.
	var copy := RecipeBook.new()
	copy.deserialize(book.serialize())
	check(copy.knows(&"brew_chicory_coffee") and copy.knows(&"cook_roasted_mackerel"), "recipe book round-trips through serialize")

	# Tutorial data sanity.
	var ok_types := true
	var ok_rewards := true
	for m in Tutorial.MISSIONS:
		for o: Array in m.objectives:
			ok_types = ok_types and int(o[1]) >= 0 and int(o[1]) < QuestDef.ObjectiveType.size()
		for r in m.rewards.get("recipes", []):
			ok_rewards = ok_rewards and RecipeDB.has_recipe(r)
		for it: Array in m.rewards.get("items", []) + m.get("gifts", []):
			ok_rewards = ok_rewards and ItemDB.has_item(StringName(it[0]))
	check(Tutorial.MISSIONS.size() == 7, "seven tutorial missions")
	check(ok_types, "tutorial objectives use valid objective types")
	check(ok_rewards, "tutorial rewards and gifts reference real items and recipes")
	var ok_journal := true
	for st: Array in Tutorial.JOURNAL.steps:
		ok_journal = ok_journal and int(st[1]) >= 0 and int(st[1]) < QuestDef.ObjectiveType.size() and String(st[4]) != ""
	check(ok_journal, "washed-ashore journal steps are valid and each has a hint")
	for it: Array in Tutorial.GREETING_GIFTS:
		check(ItemDB.has_item(StringName(it[0])), "Wren's greeting gift %s exists" % it[0])

	# Opening: starter recipes stay known, advanced ones wait for their ingredient.
	var fresh2 := RecipeBook.new()
	check(fresh2.knows(&"hand_craft_campfire"), "a castaway can hand-craft a campfire")
	check(fresh2.knows(&"hand_craft_workbench"), "a castaway can hand-craft a workbench")
	check(not fresh2.knows(&"craft_sluice_gate"), "iron recipes start hidden")
	var inv2 := Inventory.new()
	inv2.item_added.connect(func(id: StringName, _n: int) -> void: fresh2.on_item_acquired(id, inv2))
	inv2.add_item(&"iron_ingot", 1)
	check(fresh2.knows(&"craft_sluice_gate"), "first iron ingot teaches iron recipes")
	var old := RecipeBook.new()
	old.deserialize(["place_crab_pot"])   # a version-1 profile
	check(old.knows(&"craft_sluice_gate") and old.knows(&"place_crab_pot"), "old profiles keep recipes they knew by default")

	print("Summary: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)
