extends SceneTree
## Pack page: stat previews, in-place slot updates, clicks, equip, bigger backpacks, chest-free refresh.

var counts := {"total": 0, "passed": 0}


func check(name: String, cond: bool) -> void:
	counts.total += 1
	if cond:
		counts.passed += 1
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)


func _init() -> void:
	print("\n== Pack UI ==")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var p := Player.new()
	root.add_child(p)
	var ui := InventoryUI.new()
	root.add_child(ui)
	await process_frame
	ui.player = p
	var inv: Inventory = p.inventory
	for i in inv.capacity:
		inv.slots[i] = ItemSlot.new()

	# --- Inventory.preview_stats
	var before := inv.gear_stats()
	var pv := inv.preview_stats(&"oilskin_souwester")
	check("Preview names the slot", pv.get("slot") == &"head")
	check("Preview shows defense going up", int(pv["after"]["defense"]) == int(before["defense"]) + 2)
	check("Preview shows cold protection going up", float(pv["after"]["cold"]) > float(before["cold"]))
	check("Preview leaves the head slot empty", (inv.equipment[&"head"] as ItemSlot).is_empty())
	check("Preview of a bigger backpack reports its slots", int(inv.preview_stats(&"backpack_driftwood")["after"]["capacity"]) == 36)
	check("Non-gear has no preview", inv.preview_stats(&"driftwood").is_empty())

	# --- formatting helpers
	check("Delta text for defense", InventoryUI.stat_delta_text("defense", 0, 2) == "+2")
	check("Delta text for cold", InventoryUI.stat_delta_text("cold", 0.0, 0.25) == "+25%")
	check("No delta when unchanged", InventoryUI.stat_delta_text("depth", 15.0, 15.0) == "")
	check("Depth reads in metres", InventoryUI.stat_text("depth", 20.0) == "20 m")
	check("Swim speed text still works", InventoryUI.swim_speed_text(1.2) == "+20%")

	# --- page builds once and updates in place
	ui.visible = true
	ui.refresh()
	check("One slot view per inventory slot", ui._slot_views.size() == inv.capacity)
	check("All 8 gear slots shown", ui._equip_views.size() == 8)
	var first_view: ItemSlotView = ui._slot_views[9]
	inv.add_item(&"driftwood", 5)
	ui.refresh()
	check("Refresh reuses slot views", ui._slot_views[9] == first_view)
	var dw_idx := -1
	for i in inv.capacity:
		if inv.slots[i].item_id == &"driftwood":
			dw_idx = i
	check("Slot view shows the item", dw_idx >= 0 and ui._slot_views[dw_idx].item_id == &"driftwood")
	check("Compare lines for the hat", ui.compare_lines(&"oilskin_souwester").size() >= 2)

	# --- click to pick up and place
	var dest := inv.capacity - 1
	ui._slot_primary(dw_idx, false)
	check("Click picks up the stack", ui._held_slot_idx == dw_idx)
	ui._slot_primary(dest, false)
	check("Second click places it", inv.slots[dest].item_id == &"driftwood" and ui._held_slot_idx == -1)

	# --- right-click equips gear and the figure / stats follow
	inv.add_item(&"oilskin_souwester", 1)
	var hat_idx := -1
	for i in inv.capacity:
		if inv.slots[i].item_id == &"oilskin_souwester":
			hat_idx = i
	ui._slot_secondary(hat_idx)
	check("Right-click equips the hat", (inv.equipment[&"head"] as ItemSlot).item_id == &"oilskin_souwester")
	check("Gear slot shows the hat", (ui._equip_views[&"head"] as ItemSlotView).item_id == &"oilskin_souwester")
	check("Stats table shows the new defense", (ui._stat_values["defense"] as Label).text == str(inv.get_total_defense()))
	ui._on_equip_clicked(&"head", true)
	check("Right-click on worn gear takes it off", (inv.equipment[&"head"] as ItemSlot).is_empty())

	# --- a bigger backpack rebuilds the grid
	inv.add_item(&"backpack_driftwood", 1)
	for i in inv.capacity:
		if inv.slots[i].item_id == &"backpack_driftwood":
			inv.equip_item_from_slot(i)
			break
	ui.refresh()
	check("Bigger backpack grows the grid", inv.capacity == 36 and ui._slot_views.size() == 36)

	# --- the gear figure exists once opened
	ui._ensure_preview()
	ui.refresh()
	check("Gear preview model built", ui._preview_model != null)

	print("Results: %d/%d passed" % [counts.passed, counts.total])
	quit(0 if counts.passed == counts.total else 1)
