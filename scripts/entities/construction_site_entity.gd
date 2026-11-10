class_name ConstructionSiteEntity
extends WorldEntity
## A municipal house construction plot marker and building site.
## Tracks required building materials, staged inventory, and construction progress.
## Villager Builders haul supplies from the Community Chest and construct the building.

signal material_deposited(item_id: StringName, count: int)
signal construction_completed(site: ConstructionSiteEntity)

const U := VoxelWorld.VS * 0.5

const BUILDINGS := {
	&"fisher_hut": {
		"name": "Fisher's Hut",
		"prefab_idx": 5,
		"materials": {&"wood_plank": 18, &"cobblestone": 12, &"driftwood": 6}
	},
	&"drifter_cottage": {
		"name": "Drifter's Cottage",
		"prefab_idx": 5,
		"materials": {&"wood_plank": 24, &"cobblestone": 16, &"sea_glass": 2}
	},
	&"stone_storeroom": {
		"name": "Stone Storeroom",
		"prefab_idx": 9, # Stone Arch / shelter style
		"materials": {&"cobblestone": 24, &"wood_plank": 12, &"iron_ingot": 2}
	}
}

var blueprint_id: StringName = &"fisher_hut"
var building_name: String = "Fisher's Hut"
var prefab_index: int = 5
var required_materials: Dictionary = {}
var staged_materials: Dictionary = {}
var build_progress: float = 0.0
var is_completed: bool = false
var builder_assigned_id: StringName = &""


func _init(
	p_coord: Vector3i = Vector3i.ZERO,
	p_blueprint_id: StringName = &"fisher_hut"
) -> void:
	super._init(&"construction_site", "House Construction Site", p_coord)
	entity_type = EntityType.WORKSTATION
	size = Vector3(10, 6, 10) * U
	solid = false # Players can walk through construction site scaffolding
	setup_blueprint(p_blueprint_id)


func setup_blueprint(p_bp_id: StringName) -> void:
	blueprint_id = p_bp_id
	if BUILDINGS.has(blueprint_id):
		var info: Dictionary = BUILDINGS[blueprint_id]
		building_name = info.name
		prefab_index = info.prefab_idx
		required_materials = info.materials.duplicate()
	else:
		building_name = "Custom Building"
		prefab_index = 5
		required_materials = {&"wood_plank": 20, &"cobblestone": 10}
	entity_name = "Construction Site (%s)" % building_name


## Returns dictionary of still needed materials {item_id: missing_count}.
func get_missing_materials() -> Dictionary:
	var missing: Dictionary = {}
	for item_id in required_materials:
		var req: int = required_materials[item_id]
		var staged: int = staged_materials.get(item_id, 0)
		if staged < req:
			missing[item_id] = req - staged
	return missing


## Returns true if all required materials have been staged on site.
func is_materials_satisfied() -> bool:
	return get_missing_materials().is_empty()


## Deposits materials into this construction site. Returns amount accepted.
func deposit_material(item_id: StringName, count: int) -> int:
	if is_completed or count <= 0:
		return 0
	var missing: Dictionary = get_missing_materials()
	if not missing.has(item_id):
		return 0
	var needed: int = missing[item_id]
	var to_add: int = mini(count, needed)
	staged_materials[item_id] = staged_materials.get(item_id, 0) + to_add
	state_changed.emit()
	material_deposited.emit(item_id, to_add)
	return to_add


## Pulls needed materials from a Community Chest or container.
## Returns total count of items pulled.
func pull_from_chest(chest: ChestEntity) -> int:
	if is_completed or chest == null:
		return 0
	var missing: Dictionary = get_missing_materials()
	var total_pulled: int = 0
	for item_id in missing:
		var need: int = missing[item_id]
		if chest.has_supplies(item_id, 1):
			var pulled: int = chest.withdraw_supplies(item_id, need)
			if pulled > 0:
				deposit_material(item_id, pulled)
				total_pulled += pulled
	return total_pulled


## Advances construction progress by delta.
## Progress only advances once at least some materials are staged.
func build_step(amount: float, world: VoxelWorld = null) -> bool:
	if is_completed:
		return false
	if not is_materials_satisfied() and staged_materials.is_empty():
		return false # Cannot build without any materials staged

	build_progress = clampf(build_progress + amount, 0.0, 1.0)
	state_changed.emit()

	if build_progress >= 1.0 and is_materials_satisfied():
		complete_construction(world)
		return true
	return false


## Finalizes construction: stamps the prefab into the world and signals completion.
func complete_construction(world: VoxelWorld = null) -> void:
	if is_completed:
		return
	is_completed = true
	build_progress = 1.0

	if world != null:
		world.apply_prefab(prefab_index, grid_coord, rotation_steps)

	construction_completed.emit(self)
	state_changed.emit()


func _build_visuals() -> void:
	# Wooden corner stakes with batter boards, rope lines, and blueprint draft table
	var g := Prefabs.Grid.new(10, 5, 10)
	# Corner batter board stakes
	for cx in [0, 9]:
		for cz in [0, 9]:
			g.box(cx, 0, cz, cx, 4, cz, Palette.DARK_WOOD)
	# Perimeter batter rails
	g.box(0, 3, 0, 9, 3, 0, Palette.PLANK)
	g.box(0, 3, 9, 9, 3, 9, Palette.PLANK)
	g.box(0, 3, 0, 0, 3, 9, Palette.PLANK)
	g.box(9, 3, 0, 9, 3, 9, Palette.PLANK)
	# Blueprint easel table in center
	g.box(4, 0, 4, 5, 2, 5, Palette.HANDLE)
	g.box(3, 2, 3, 6, 2, 6, Palette.WHITEWASH)
	g.box(4, 2, 4, 5, 2, 5, Palette.ROOF_BLUE)
	_mesh_instance = _voxel_model(g)


func get_interaction_prompt(player: Player) -> String:
	if is_completed:
		return "Construction Complete"
	var missing := get_missing_materials()
	if missing.is_empty():
		return "F Work on Construction · %d%% Complete" % [int(build_progress * 100.0)]

	var active := player.inventory.get_active_item() if player.inventory != null else null
	var dep_text := ""
	if active != null and not active.is_empty() and missing.has(active.item_id):
		dep_text = "    Shift+F Deliver %s" % active.item_id
	var summary := []
	for m in missing:
		summary.append("%d %s" % [missing[m], m])
	return "F Inspect Site · Needs: %s%s · %d%% Done" % [", ".join(summary), dep_text, int(build_progress * 100.0)]


func client_interact(player: Player) -> void:
	interacted.emit(player)
	var missing := get_missing_materials()
	if missing.is_empty():
		# Advance build by hammering
		build_step(0.1, player.world if "world" in player else null)
		return

	# Deliver matching items from inventory
	if player.inventory != null:
		var active := player.inventory.get_active_item()
		if active != null and not active.is_empty() and missing.has(active.item_id):
			var to_take := mini(active.count, int(missing[active.item_id]))
			if to_take > 0:
				player.inventory.remove_item(active.item_id, to_take)
				deposit_material(active.item_id, to_take)
				return

		# Check all slots if no matching active item
		for slot in player.inventory.slots:
			if not slot.is_empty() and missing.has(slot.item_id):
				var need := int(missing[slot.item_id])
				var to_take := mini(slot.count, need)
				if to_take > 0:
					player.inventory.remove_item(slot.item_id, to_take)
					deposit_material(slot.item_id, to_take)
					return


func serialize() -> Dictionary:
	return {
		"blueprint_id": String(blueprint_id),
		"building_name": building_name,
		"prefab_index": prefab_index,
		"required_materials": required_materials,
		"staged_materials": staged_materials,
		"build_progress": build_progress,
		"is_completed": is_completed,
		"builder_assigned_id": String(builder_assigned_id)
	}


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	blueprint_id = StringName(data.get("blueprint_id", "fisher_hut"))
	building_name = data.get("building_name", "Fisher's Hut")
	prefab_index = int(data.get("prefab_index", 5))
	required_materials = data.get("required_materials", {}).duplicate()
	staged_materials = data.get("staged_materials", {}).duplicate()
	build_progress = float(data.get("build_progress", 0.0))
	is_completed = bool(data.get("is_completed", false))
	builder_assigned_id = StringName(data.get("builder_assigned_id", ""))
	setup_blueprint(blueprint_id)
