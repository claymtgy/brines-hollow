class_name CrabPotEntity
extends WorldEntity
## Wicker crab pot (wraps fishing/crab_pot.gd). Place it on the tidal flats at low tide,
## bait it, and the rising tide does the rest: every SOAK_ROLL_SEC it spends under water
## it may trap shore crabs or oysters (consuming bait). Collect when the tide is out.
## Simulated only on the host/server; the catch is granted to whoever collects it.

const U := VoxelWorld.VS * 0.5
const SOAK_ROLL_SEC := 40.0

var pot: CrabPot
var soak_t := 0.0
var submerged := false
var _rng := RandomNumberGenerator.new()


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"crab_pot", "Wicker Crab Pot", p_coord)
	entity_type = EntityType.TRAP
	pot = CrabPot.new(p_coord)
	size = Vector3(8, 6, 8) * U
	_rng.seed = hash(p_coord)


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(8, 7, 8)
	for y in 6:
		for z in 8:
			for x in 8:
				var edge := x == 0 or x == 7 or z == 0 or z == 7 or y == 0 or y == 5
				if edge and ((x + y + z) % 2 == 0 or y == 0 or y == 5):
					g.setv(x, y, z, Palette.DRIFTWOOD)
	for c in [Vector2i(0, 0), Vector2i(7, 0), Vector2i(0, 7), Vector2i(7, 7)]:
		g.box(c.x, 0, c.y, c.x, 5, c.y, Palette.DARK_WOOD)
	g.box(3, 6, 3, 4, 6, 4, Palette.BUOY)               # marker float
	g.box(3, 1, 3, 4, 2, 4, Palette.KELP)               # bait bundle
	_mesh_instance = _voxel_model(g)


func _catch_count() -> int:
	var n := 0
	for k in pot.trapped_catch:
		n += int(pot.trapped_catch[k])
	return n


func get_interaction_prompt(player: Player) -> String:
	var n := _catch_count()
	if n > 0:
		return "F  Collect %d shellfish from the crab pot" % n
	if not pot.is_baited():
		var bait := _bait_in(player.inventory)
		return "F  Bait crab pot with %s" % ChestEntity._item_name(bait) if bait != &"" else "Crab pot needs bait · Kelp Fronds or Small Fish"
	return "Crab Pot Baited · %d · %s" % [pot.bait_count, "Soaking..." if submerged else "Waiting for the Tide"]


static func _bait_in(inv: Inventory) -> StringName:
	var active := inv.get_active_item()
	if active != null and not active.is_empty() and Placeables.is_bait(active.item_id):
		return active.item_id
	for b: StringName in Placeables.BAIT_ITEMS:
		if inv.has_item(b, 1):
			return b
	return &""


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if _catch_count() > 0:
		manager.request_action(self, &"collect", {})
		return
	if pot.is_baited():
		if player.hud:
			player.hud.show_toast("Already baited (%d). Leave it for the high tide." % pot.bait_count)
		return
	var bait := _bait_in(player.inventory)
	if bait == &"":
		if player.hud:
			player.hud.show_toast("You need bait: kelp fronds or a small fish.")
		return
	var n := player.inventory.remove_item(bait, mini(3, player.inventory.get_item_count(bait)))
	if n > 0:
		manager.request_action(self, &"bait", {"item": bait, "n": n})


func server_action(action: StringName, args: Dictionary, _peer: int) -> Dictionary:
	match action:
		&"bait":
			var item := StringName(args.get("item", ""))
			var n := int(args.get("n", 0))
			if not Placeables.is_bait(item) or n <= 0:
				return {}
			var refused := pot.add_bait(item, n)
			if refused > 0:
				return {"grant": [[item, refused]], "toast": "The pot already holds different bait."}
			return {"changed": true, "toast": "Baited the crab pot with %d %s." % [n, ChestEntity._item_name(item)]}
		&"collect":
			var grants := []
			var total := 0
			for k in pot.trapped_catch.keys():
				var c := int(pot.trapped_catch[k])
				if c > 0:
					grants.append([k, c])
					total += c
			pot.trapped_catch.clear()
			if total == 0:
				return {}
			return {"changed": true, "grant": grants, "toast": "Collected %d shellfish!" % total}
	return {}


## Authority: each SOAK_ROLL_SEC under water rolls a catch (CrabPot.tick_tidal_cycle).
func server_tick(delta: float, env: Dictionary) -> bool:
	var was := submerged
	submerged = float(env.get("tide_vox", 0.0)) >= grid_coord.y + 1.0
	if not submerged:
		soak_t = 0.0
		return was != submerged
	if not pot.is_baited():
		return was != submerged
	soak_t += delta
	if soak_t < SOAK_ROLL_SEC:
		return was != submerged
	soak_t = 0.0
	var before := _catch_count()
	var bait_before := pot.bait_count
	pot.tick_tidal_cycle(float(env.get("tide_vox", 0.0)), _rng)
	return was != submerged or _catch_count() != before or pot.bait_count != bait_before


## Picking the pot up also returns its bait and any catch.
func pickup_items() -> Array:
	var out := super.pickup_items()
	if pot.is_baited():
		out.append([pot.bait_item_id, pot.bait_count])
	for k in pot.trapped_catch:
		if int(pot.trapped_catch[k]) > 0:
			out.append([k, int(pot.trapped_catch[k])])
	return out


func serialize() -> Dictionary:
	var d := super.serialize()
	d["pot"] = pot.serialize()
	d["soak"] = soak_t
	d["sub"] = submerged
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	if data.has("pot"):
		pot = CrabPot.deserialize(data["pot"])
		pot.pos = grid_coord
	soak_t = float(data.get("soak", 0.0))
	submerged = bool(data.get("sub", false))
