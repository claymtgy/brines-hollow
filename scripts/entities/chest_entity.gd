class_name ChestEntity
extends WorldEntity
## Storage chest / crate / watertight sea barrel. Contents live on the host/server.
##   F            take up to 5 of the first stored stack
##   Shift + F    deposit the active hotbar stack (if this container accepts it)
## Deposits and withdrawals are server actions, so two players can't duplicate items.

signal container_accessed(player: Player)

const U := VoxelWorld.VS * 0.5

var container: StorageContainer
var style := &"chest"   # chest | crate | barrel
## Sealed stores (sea barrels, pantry barrels) are rat-proof: shore rats only raid
## open chests and crates with food in them.
var sealed := false


func _init(
	p_name: String = "Driftwood Storage Chest",
	p_coord: Vector3i = Vector3i.ZERO,
	p_capacity: int = 18,
	p_tags: PackedStringArray = PackedStringArray()
) -> void:
	super._init(&"driftwood_chest", p_name, p_coord)
	entity_type = EntityType.CONTAINER
	container = StorageContainer.new(p_name, p_capacity, p_tags)
	size = Vector3(9, 6, 6) * U


static func make_crate(coord: Vector3i) -> ChestEntity:
	var c := ChestEntity.new("Storage Crate", coord, 24)
	c.entity_id = &"storage_crate"
	c.style = &"crate"
	c.size = Vector3(8, 8, 8) * U
	return c


## Seafood-only barrel that keeps catches fresh.
static func make_sea_barrel(coord: Vector3i) -> ChestEntity:
	var c := ChestEntity.new("Watertight Sea Barrel", coord, 12, PackedStringArray(["fish", "shellfish"]))
	c.container.preserves_freshness = true
	c.entity_id = &"sea_barrel"
	c.style = &"barrel"
	c.sealed = true
	c.size = Vector3(7, 10, 7) * U
	return c


## Barnacle-crusted chest found in cave grottos and caverns. Can't be picked up.
## `loot` is filled once by the host when the world's caves are first stocked.
static func make_barnacled(coord: Vector3i) -> ChestEntity:
	var c := ChestEntity.new("Barnacled Chest", coord, 9)
	c.entity_id = &"barnacled_chest"
	c.style = &"chest"
	c.sealed = true
	return c


## Loot for a cave chest: sea glass and copper in the tidal grottos, more iron in caverns.
static func cave_loot(kind: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = [[&"sea_glass", rng.randi_range(2, 5)], [&"copper_ore", rng.randi_range(3, 6)]]
	if kind == 1:
		out.append([&"sea_iron_ore", rng.randi_range(2, 4)])
		if rng.randf() < 0.5:
			out.append([&"iron_ingot", 1])
	else:
		if rng.randf() < 0.6:
			out.append([&"sea_brass_ingot", 1])
	return out


## An old miner's strongbox: brass, calamine, a little copper.
static func mine_loot(rng: RandomNumberGenerator) -> Array:
	var out: Array = [[&"calamine_ore", rng.randi_range(3, 6)], [&"copper_ore", rng.randi_range(2, 4)],
		[&"sea_brass_ingot", rng.randi_range(1, 3)]]
	if rng.randf() < 0.5:
		out.append([&"iron_ingot", 1])
	return out


## Whatever sank to the bottom of a flooded sump: the best of the caves, for those who dive.
static func sump_loot(rng: RandomNumberGenerator) -> Array:
	var out: Array = [[&"sea_glass", rng.randi_range(4, 8)], [&"sea_brass_ingot", rng.randi_range(2, 3)],
		[&"iron_ingot", rng.randi_range(1, 2)]]
	if rng.randf() < 0.5:
		out.append([&"chitin_plate", rng.randi_range(1, 3)])
	return out


## A wrecked cutter's locker: what the sea left of her cargo and the captain's purse.
static func wreck_loot(rng: RandomNumberGenerator) -> Array:
	var out: Array = [[&"wood_plank", rng.randi_range(4, 8)], [&"brass_guilder", rng.randi_range(6, 18)],
		[&"sea_glass", rng.randi_range(1, 4)]]
	match rng.randi_range(0, 3):
		0: out.append([&"sea_wool", rng.randi_range(2, 4)])
		1: out.append([&"iron_ingot", rng.randi_range(1, 2)])
		2: out.append([&"sea_salt", rng.randi_range(4, 8)])
		_: out.append([&"shore_hardtack", rng.randi_range(2, 3)])
	return out


## A Sunken Calamity Galleon's abyssal strongbox: deep-sea armada relics, brass ingots, and treasures.
static func calamity_galleon_loot(rng: RandomNumberGenerator) -> Array:
	var out: Array = [
		[&"sea_brass_ingot", rng.randi_range(3, 6)],
		[&"brass_guilder", rng.randi_range(25, 60)],
		[&"abyssal_pearl", rng.randi_range(2, 4)],
		[&"chitin_plate", rng.randi_range(3, 6)],
		[&"sea_glass", rng.randi_range(4, 8)]
	]
	if rng.randf() < 0.7:
		out.append([&"diving_helmet", 1])
	else:
		out.append([&"harpoon_trident", 1])
	return out


## What the Mud-Claws hoard: reef salvage, shell and the odd bit of worked metal.
static func camp_loot(rng: RandomNumberGenerator) -> Array:
	var out: Array = [[&"sea_glass", rng.randi_range(3, 6)], [&"chitin_plate", rng.randi_range(2, 4)],
		[&"copper_ore", rng.randi_range(2, 5)]]
	if rng.randf() < 0.6:
		out.append([&"sea_brass_ingot", rng.randi_range(1, 2)])
	if rng.randf() < 0.5:
		out.append([&"iron_ingot", 1])
	return out


## A Sea-Reaver strongbox: the outpost's plunder.
static func outpost_loot(rng: RandomNumberGenerator) -> Array:
	var out: Array = [[&"brass_guilder", rng.randi_range(30, 60)], [&"iron_ingot", rng.randi_range(2, 4)],
		[&"sea_brass_ingot", rng.randi_range(2, 4)], [&"wood_plank", rng.randi_range(6, 12)]]
	match rng.randi_range(0, 2):
		0: out.append([&"sea_wool", rng.randi_range(3, 6)])
		1: out.append([&"marsh_honey", rng.randi_range(2, 4)])
		_: out.append([&"sea_glass", rng.randi_range(4, 8)])
	return out


## Tar-sealed pantry barrel: holds any food and keeps shore rats out.
static func make_pantry_barrel(coord: Vector3i) -> ChestEntity:
	var c := ChestEntity.new("Sealed Pantry Barrel", coord, 16)
	c.entity_id = &"pantry_barrel"
	c.style = &"barrel"
	c.sealed = true
	c.size = Vector3(7, 10, 7) * U
	return c


## High-capacity village community stockpile chest (48 slots) shared between players and workers.
static func make_community_chest(coord: Vector3i) -> ChestEntity:
	var c := ChestEntity.new("Community Stockpile Chest", coord, 48)
	c.entity_id = &"community_chest"
	c.style = &"community"
	c.sealed = true # Rat-proof
	c.size = Vector3(12, 8, 8) * U
	return c


## Deposits supplies into this chest. Returns count successfully deposited.
func deposit_supplies(item_id: StringName, count: int, custom_data: Dictionary = {}) -> int:
	var remainder := container.deposit(item_id, count, custom_data)
	return count - remainder


## Returns whether the chest contains at least `count` of `item_id`.
func has_supplies(item_id: StringName, count: int = 1) -> bool:
	return container.inventory.get_item_count(item_id) >= count


## Withdraws up to `count` items of `item_id`. Returns amount successfully withdrawn.
func withdraw_supplies(item_id: StringName, count: int) -> int:
	return container.withdraw(item_id, count)


## Returns dictionary of all available supplies {item_id: total_count}.
func get_available_supplies() -> Dictionary:
	var dict: Dictionary = {}
	for slot in container.inventory.slots:
		if not slot.is_empty():
			dict[slot.item_id] = dict.get(slot.item_id, 0) + slot.count
	return dict


## Food a shore rat could carry off (empty if sealed).
func raidable_food() -> Array:
	var out: Array = []
	if sealed:
		return out
	for slot in container.inventory.slots:
		if not slot.is_empty():
			var def: ItemDef = ItemDB.get_item(slot.item_id)
			if def != null and def.category == ItemDef.Category.FOOD:
				out.append(slot.item_id)
	return out


func _build_visuals() -> void:
	var g: Prefabs.Grid
	match style:
		&"crate":
			g = Prefabs.Grid.new(8, 8, 8)
			g.box(0, 0, 0, 7, 7, 7, Palette.PLANK)
			for e in [0, 7]:
				g.box(e, 0, 0, e, 7, 0, Palette.DARK_WOOD); g.box(e, 0, 7, e, 7, 7, Palette.DARK_WOOD)
				g.box(0, e, 0, 7, e, 0, Palette.DARK_WOOD); g.box(0, e, 7, 7, e, 7, Palette.DARK_WOOD)
			g.box(1, 3, 0, 6, 4, 0, Palette.DRIFTWOOD)
		&"barrel":
			g = Prefabs.Grid.new(7, 10, 7)
			for y in 10:
				var r := 3.3 if (y > 1 and y < 8) else 2.9
				for z in 7:
					for x in 7:
						if Vector2(x - 3, z - 3).length() <= r:
							g.setv(x, y, z, Palette.PLANK if (x + z) % 2 == 0 else Palette.DRIFTWOOD)
			for y in [1, 8]:
				for z in 7:
					for x in 7:
						if g.getv(x, y, z) != 0 and Vector2(x - 3, z - 3).length() > 2.2:
							g.setv(x, y, z, Palette.METAL)
			g.box(2, 9, 2, 4, 9, 4, Palette.DARK_WOOD)
			if entity_id == &"pantry_barrel":
				g.box(1, 9, 1, 5, 9, 5, Palette.BEDROCK)   # tarred lid
		&"community":
			g = Prefabs.Grid.new(12, 8, 8)
			g.box(0, 0, 0, 11, 7, 7, Palette.DARK_WOOD)     # Reinforced heavy frame
			g.box(1, 1, 1, 10, 6, 6, Palette.PLANK)         # Sanded oak panels
			g.box(0, 6, 0, 11, 7, 7, Palette.DARK_WOOD)     # Heavy arched lid
			g.box(1, 7, 1, 10, 7, 6, Palette.ROOF_BLUE)      # Painted municipal crest lid
			for x in [0, 11]:
				g.box(x, 0, 0, x, 7, 1, Palette.FLOWER_Y)
				g.box(x, 0, 6, x, 7, 7, Palette.FLOWER_Y)
			g.box(3, 4, 7, 4, 6, 7, Palette.FLOWER_Y)
			g.box(7, 4, 7, 8, 6, 7, Palette.FLOWER_Y)
		_:
			g = Prefabs.Grid.new(9, 6, 6)
			g.box(0, 0, 0, 8, 5, 5, Palette.DRIFTWOOD)
			g.box(0, 4, 0, 8, 5, 5, Palette.PLANK)          # lid
			for x in [0, 8]:
				g.box(x, 0, 0, x, 5, 5, Palette.DARK_WOOD)
			g.box(4, 3, 5, 4, 4, 5, Palette.METAL)           # latch (front = +z)
	_mesh_instance = _voxel_model(g)


func _stored_count() -> int:
	var n := 0
	for slot in container.inventory.slots:
		if not slot.is_empty():
			n += slot.count
	return n


func get_interaction_prompt(player: Player) -> String:
	var active := player.inventory.get_active_item()
	var dep := ""
	if active != null and not active.is_empty() and container.can_accept_item(active.item_id):
		dep = "    Shift+F  Store %s" % _item_name(active.item_id)
	var verb := "Open" if player.inventory_ui != null else "Take from"
	return "F  %s %s · %d Stored%s" % [verb, entity_name, _stored_count(), dep]


static func _item_name(id: StringName) -> String:
	var def: ItemDef = ItemDB.get_item(id)
	return def.name if def != null else String(id)


func client_interact(player: Player) -> void:
	container_accessed.emit(player)
	if Input.is_action_pressed("sprint"):
		var active := player.inventory.get_active_item()
		if active == null or active.is_empty():
			_toast(player, "Select a hotbar stack to store it.")
			return
		var id := active.item_id
		if not container.can_accept_item(id):
			_toast(player, "%s only holds seafood." % entity_name if style == &"barrel" else "That won't fit in %s." % entity_name)
			return
		var n := player.inventory.remove_item(id, active.count)
		if n > 0:
			manager.request_action(self, &"deposit", {"item": id, "n": n})
		return
	if player.inventory_ui != null and (not is_inside_tree() or multiplayer.is_server()):
		player.inventory_ui.open(self)
		return
	if _stored_count() == 0:
		_toast(player, "%s is empty. Hold Shift and press F to store your active stack." % entity_name)
		return
	manager.request_action(self, &"take", {})


func _toast(player: Player, t: String) -> void:
	if player.hud:
		player.hud.show_toast(t)


func server_action(action: StringName, args: Dictionary, _peer: int) -> Dictionary:
	match action:
		&"deposit":
			var id := StringName(args.get("item", ""))
			var n := int(args.get("n", 0))
			if n <= 0:
				return {}
			var left := container.deposit(id, n)
			var res := {"changed": left < n, "toast": "Stored %d %s" % [n - left, _item_name(id)]}
			if left > 0:
				res["grant"] = [[id, left]]   # didn't fit: give it back
				res["toast"] = "%s is full" % entity_name if left == n else res["toast"] + " (%d didn't fit)" % left
			elif args.get("quiet", false):
				res.erase("toast")   # the Chest screen shows the move itself
			return res
		&"take_slot":
			# Chest screen: take `n` from one particular slot.
			var i := int(args.get("slot", -1))
			var n := int(args.get("n", 0))
			var inv: Inventory = container.inventory
			if n <= 0 or i < 0 or i >= inv.capacity or inv.slots[i].is_empty():
				return {}
			var id: StringName = inv.slots[i].item_id
			var taken := inv.remove_from_slot(i, n)
			return {"changed": taken > 0, "grant": [[id, taken]]}
		&"sort":
			container.inventory.quick_sort(false)
			return {"changed": true}
		&"take":
			for slot in container.inventory.slots:
				if not slot.is_empty():
					var id: StringName = slot.item_id
					var taken := container.withdraw(id, mini(slot.count, 5))
					return {"changed": true, "grant": [[id, taken]], "toast": "Took %d %s" % [taken, _item_name(id)]}
	return {}


## Legacy local interaction (unit tests / older callers): same rules, applied directly.
func interact(player: Player) -> void:
	super.interact(player)
	container_accessed.emit(player)
	var active_slot := player.inventory.get_active_item()
	if active_slot and not active_slot.is_empty() and container.can_accept_item(active_slot.item_id):
		var deposit_id: StringName = active_slot.item_id
		var remaining := container.inventory.add_item(deposit_id, active_slot.count)
		var transferred := active_slot.count - remaining
		if transferred > 0:
			player.inventory.remove_item(deposit_id, transferred)
			return
	for slot in container.inventory.slots:
		if not slot.is_empty():
			var item_id: StringName = slot.item_id
			var taken := mini(slot.count, 5) - player.inventory.add_item(item_id, mini(slot.count, 5))
			if taken > 0:
				container.inventory.remove_item(item_id, taken)
			return


## Picking a container up returns it with its contents.
func pickup_items() -> Array:
	var out := super.pickup_items()
	for slot in container.inventory.slots:
		if not slot.is_empty():
			out.append([slot.item_id, slot.count])
	return out


func serialize() -> Dictionary:
	var d := super.serialize()
	d["items"] = container.inventory.serialize()
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	if data.has("items"):
		container.inventory.deserialize(data["items"])
