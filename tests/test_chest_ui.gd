extends SceneTree
## Chest screen: opening from the Pack UI, moving stacks both ways, room checks,
## filtered barrels, Store all / Add to stacks / Take all / Sort.

var counts := {"total": 0, "passed": 0}


func check(name: String, cond: bool) -> void:
	counts.total += 1
	if cond:
		counts.passed += 1
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)


func _init() -> void:
	print("\n== Chest UI ==")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _clear(inv: Inventory) -> void:
	for i in inv.capacity:
		inv.slots[i] = ItemSlot.new()


func _slot_of(inv: Inventory, id: StringName, from := 0) -> int:
	for i in range(from, inv.capacity):
		if inv.slots[i].item_id == id:
			return i
	return -1


func _run() -> void:
	var p := Player.new()
	root.add_child(p)
	var ui := InventoryUI.new()
	root.add_child(ui)
	await process_frame
	ui.player = p
	var inv: Inventory = p.inventory
	_clear(inv)

	# --- Inventory.room_for
	check("Room for in an empty pack", inv.room_for(&"stone") > 0)
	var spare := Inventory.new()
	var r0 := spare.room_for(&"driftwood")
	spare.add_item(&"driftwood", 1)
	check("Room for counts partial stacks and empty slots", spare.room_for(&"driftwood") == r0 - 1)
	for i in spare.capacity:
		spare.slots[i] = ItemSlot.new(&"stone", 1)
	check("No room in a pack full of other things", spare.room_for(&"driftwood") == 0)

	# --- opening
	var chest := ChestEntity.new("Driftwood Storage Chest", Vector3i.ZERO, 18)
	var closed_n := [0]
	ui.inventory_closed.connect(func() -> void: closed_n[0] += 1)
	ui.open(chest)
	var cui: ChestUI = ui.chest_ui
	check("Opening a chest shows the Chest screen", cui != null and cui.is_open())
	check("The Pack page stays hidden", not ui.visible)
	check("Pack UI counts as open while the chest is", ui.is_open())
	check("One view per chest slot", cui._chest_views.size() == 18)
	check("One view per pack slot", cui._pack_views.size() == inv.capacity)
	check("Hotbar row holds eight slots", cui._hotbar_row.get_child_count() == Inventory.MAX_HOTBAR_SLOTS)
	check("Title names the chest", cui._title.text == "Driftwood Storage Chest")

	# --- store and take
	inv.add_item(&"stone", 20)
	inv.add_item(&"driftwood", 6)
	var st := _slot_of(inv, &"stone")
	check("Store moves the whole stack", cui.store(st) == 20 and inv.get_item_count(&"stone") == 0
		and chest.container.inventory.get_item_count(&"stone") == 20)
	var dw := _slot_of(inv, &"driftwood")
	cui.store(dw, 1)
	check("Right-click stores one", inv.get_item_count(&"driftwood") == 5 and chest.has_supplies(&"driftwood", 1))
	var cst := _slot_of(chest.container.inventory, &"stone")
	cui.take(cst, 5)
	check("Take some from a chest slot", inv.get_item_count(&"stone") == 5 and chest.container.inventory.get_item_count(&"stone") == 15)
	cui.take(cst)
	check("Take the rest of the stack", inv.get_item_count(&"stone") == 20 and not chest.has_supplies(&"stone"))
	cui.refresh()
	check("Chest views follow the contents", cui._chest_views[cst].item_id == &"")

	# --- shift: all of that kind
	inv.add_item(&"kelp_frond", 3)
	var k2 := _slot_of(inv, &"kelp_frond")
	inv.split_stack(k2, inv.capacity - 1, 1)
	cui.store_kind(&"kelp_frond")
	check("Shift-click stores every stack of that kind", inv.get_item_count(&"kelp_frond") == 0 and chest.container.inventory.get_item_count(&"kelp_frond") == 3)
	cui.take_kind(&"kelp_frond")
	check("Shift-click takes every stack of that kind", inv.get_item_count(&"kelp_frond") == 3)

	# --- never takes more than fits
	_clear(inv)
	chest.container.inventory.add_item(&"copper_ore", 4)
	for i in inv.capacity:
		inv.slots[i] = ItemSlot.new(&"sand", ItemDB.get_item(&"sand").max_stack)
	var co := _slot_of(chest.container.inventory, &"copper_ore")
	check("A full pack takes nothing", cui.take(co) == 0 and chest.container.inventory.get_item_count(&"copper_ore") == 4)
	cui.take_all()
	check("Take all leaves what doesn't fit", chest.container.inventory.get_item_count(&"copper_ore") == 4)

	# --- Store all keeps the hotbar; Add to stacks only tops up
	_clear(inv)
	inv.slots[0] = ItemSlot.new(&"stone", 10)                       # hotbar
	inv.slots[Inventory.MAX_HOTBAR_SLOTS] = ItemSlot.new(&"stone", 7)   # backpack
	inv.slots[Inventory.MAX_HOTBAR_SLOTS + 1] = ItemSlot.new(&"sand", 9)
	cui.store_matching()
	check("Add to stacks stores nothing new", inv.get_item_count(&"sand") == 9 and inv.get_item_count(&"stone") == 17)
	chest.container.inventory.add_item(&"sand", 1)
	cui.store_matching()
	check("Add to stacks stores what the chest already holds", inv.get_item_count(&"sand") == 0)
	cui.store_all()
	check("Store all empties the backpack", inv.slots[Inventory.MAX_HOTBAR_SLOTS].is_empty())
	check("Store all leaves the hotbar alone", inv.slots[0].item_id == &"stone" and inv.slots[0].count == 10)
	cui.take_all()
	check("Take all empties the chest", chest._stored_count() == 0 and inv.get_item_count(&"copper_ore") == 4)

	# --- sort
	chest.container.inventory.slots[5] = ItemSlot.new(&"stone", 3)
	chest.container.inventory.slots[9] = ItemSlot.new(&"stone", 4)
	cui.sort_chest()
	check("Sort stacks and moves things to the front",
		chest.container.inventory.slots[0].item_id == &"stone" and chest.container.inventory.slots[0].count == 7)
	chest.container.inventory.slots[0] = ItemSlot.new()

	# --- a seafood barrel
	var barrel := ChestEntity.make_sea_barrel(Vector3i(3, 0, 0))
	ui.open(barrel)
	check("Opening another chest switches to it", cui.chest == barrel and cui._chest_views.size() == 12)
	check("Barrel notes mention freshness", ChestUI.notes_text(barrel).contains("fresh"))
	check("Plain chest notes warn about rats", ChestUI.notes_text(chest).contains("rats"))
	_clear(inv)
	inv.add_item(&"stone", 5)
	inv.add_item(&"silver_mackerel", 2)
	check("Barrel refuses stone", cui.store(_slot_of(inv, &"stone")) == 0 and inv.get_item_count(&"stone") == 5)
	cui.refresh()
	check("Refused items are faded", cui._pack_views[_slot_of(inv, &"stone")].modulate.a < 0.5)
	check("Barrel takes fish", cui.store(_slot_of(inv, &"silver_mackerel")) == 2 and barrel.has_supplies(&"silver_mackerel", 2))

	# --- chest action used by the screen
	var res := barrel.server_action(&"take_slot", {"slot": _slot_of(barrel.container.inventory, &"silver_mackerel"), "n": 1}, 0)
	check("take_slot grants from that slot", res.get("grant", []) == [[&"silver_mackerel", 1]] and barrel.container.inventory.get_item_count(&"silver_mackerel") == 1)
	check("Quiet deposits don't toast", not barrel.server_action(&"deposit", {"item": &"silver_mackerel", "n": 1, "quiet": true}, 0).has("toast"))

	# --- closing and switching to the Pack page
	ui.open()
	check("Opening the Pack page closes the chest", not cui.is_open() and ui.visible)
	check("Closing the chest reports inventory_closed", closed_n[0] >= 1)
	ui.close()
	ui.open(chest)
	ui.close()
	check("Close shuts the Chest screen", not cui.is_open() and not ui.is_open())

	print("Results: %d/%d passed" % [counts.passed, counts.total])
	quit(0 if counts.passed == counts.total else 1)
