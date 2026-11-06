class_name BuildCosts
extends RefCounted
## Survival build costs. Placing voxels or prefabs consumes inventory items.
##
## Rate matches digging: digging returns 1 item per 4 voxels, so building costs
## 1 item per 4 voxels of the same material (rounded up per material).
##
## Materials without their own item yet map to a stand-in raw resource. These are
## placeholders until crafting adds refined goods (paint, lime wash, glass, iron).

const VOXELS_PER_ITEM := 4

const STAND_INS := {
	Palette.WHITEWASH: &"sand",        # lime wash, later: crafted from shells
	Palette.ROOF_RED: &"wood_plank",   # painted shingles
	Palette.ROOF_BLUE: &"wood_plank",
	Palette.SHUTTER: &"wood_plank",
	Palette.BUOY: &"driftwood",
	Palette.LANTERN: &"kelp_frond",    # kelp oil lamp
	Palette.GLOW_TEAL: &"kelp_frond",
	Palette.GRAVEL: &"stone",
	Palette.GRASS: &"dirt",
	Palette.GRASS_DRY: &"dirt",
	Palette.SANDSTONE_B: &"sandstone",
	Palette.SANDSTONE_C: &"sandstone",
	Palette.WET_SAND: &"sand",
	Palette.METAL: &"stone",           # until ore + smelting exist
	Palette.LEAVES_DARK: &"leaves",
	Palette.TRUNK: &"pine_wood",
}


## Item that pays for one voxel of material `m`, or &"" if it can't be built.
static func item_for(m: int) -> StringName:
	ItemDB.init_db()
	var def: ItemDef = ItemDB.get_by_voxel_mat(m)
	if def != null:
		return def.id
	return STAND_INS.get(m, &"")


## {item_id: count} for a {material: voxel_count} tally.
static func cost_for_counts(counts: Dictionary) -> Dictionary:
	var per_item := {}
	for m: int in counts:
		var item := item_for(m)
		if item == &"":
			continue
		per_item[item] = int(per_item.get(item, 0)) + int(counts[m])
	var out := {}
	for item: StringName in per_item:
		out[item] = int(ceil(float(per_item[item]) / VOXELS_PER_ITEM))
	return out


## Cost of placing a material brush of radius r at c (only air cells get filled).
static func brush_cost(world: VoxelWorld, c: Vector3i, r: int, m: int) -> Dictionary:
	var n := 0
	var r2 := r * r + r
	for y in range(-r, r + 1):
		for z in range(-r, r + 1):
			for x in range(-r, r + 1):
				if x * x + y * y + z * z <= r2 and world.get_voxel(c.x + x, c.y + y, c.z + z) == 0:
					n += 1
	return cost_for_counts({m: n}) if n > 0 else {}


## Cost of a prefab (every solid voxel it contains, foundations not included).
static func prefab_cost(id: int, rot: int) -> Dictionary:
	var pf := Prefabs.rotated(id, rot)
	var data: PackedByteArray = pf.data
	var counts := {}
	for m in data:
		if m != 0 and m != Palette.CLEAR:
			counts[m] = int(counts.get(m, 0)) + 1
	return cost_for_counts(counts)


static func can_afford(inv: Inventory, cost: Dictionary) -> bool:
	for item: StringName in cost:
		if not inv.has_item(item, cost[item]):
			return false
	return true


static func pay(inv: Inventory, cost: Dictionary) -> void:
	for item: StringName in cost:
		inv.remove_item(item, cost[item])


## Human-readable list of what's missing, e.g. "12 Wood Plank, 3 Sand".
static func describe_missing(inv: Inventory, cost: Dictionary) -> String:
	var parts := []
	for item: StringName in cost:
		var have := inv.get_item_count(item)
		if have < cost[item]:
			var def: ItemDef = ItemDB.get_item(item)
			var label: String = def.name if def != null else String(item)
			parts.append("%d %s" % [cost[item] - have, label])
	return ", ".join(parts)


static func describe(cost: Dictionary) -> String:
	var parts := []
	for item: StringName in cost:
		var def: ItemDef = ItemDB.get_item(item)
		parts.append("%d %s" % [cost[item], def.name if def != null else String(item)])
	return ", ".join(parts)
