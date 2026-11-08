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


## Tar-sealed pantry barrel: holds any food and keeps shore rats out.
static func make_pantry_barrel(coord: Vector3i) -> ChestEntity:
	var c := ChestEntity.new("Sealed Pantry Barrel", coord, 16)
	c.entity_id = &"pantry_barrel"
	c.style = &"barrel"
	c.sealed = true
	c.size = Vector3(7, 10, 7) * U
	return c


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
	return "F  %s %s (%d stored)%s" % [verb, entity_name, _stored_count(), dep]


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
			return res
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
