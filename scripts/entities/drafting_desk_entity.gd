class_name DraftingDeskEntity
extends WorldEntity
## Architect's Drafting Desk: Workstation for architectural planning and blueprint drafting.
## Enables rapid creation of Blueprint Scrolls and advanced building schematics.

const U := VoxelWorld.VS * 0.5

var drafts_completed: int = 0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"drafting_desk", "Architect's Drafting Desk", p_coord)
	entity_type = EntityType.WORKSTATION
	item_id = &"drafting_desk"
	size = Vector3(8, 8, 6) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(8, 8, 6)
	# 4 Heavy timber table legs
	g.box(0, 0, 0, 1, 6, 1, Palette.DARK_WOOD)
	g.box(6, 0, 0, 7, 6, 1, Palette.DARK_WOOD)
	g.box(0, 0, 4, 1, 6, 5, Palette.DARK_WOOD)
	g.box(6, 0, 4, 7, 6, 5, Palette.DARK_WOOD)
	# Slanted drafting tabletop
	g.box(0, 6, 0, 7, 7, 5, Palette.DRIFTWOOD)
	# Unrolled blueprint paper / vellum
	g.box(1, 7, 1, 5, 7, 4, Palette.SAND)
	# Brass compass & inkwell
	g.box(6, 7, 1, 6, 8, 2, Palette.METAL)
	g.box(6, 7, 3, 6, 8, 4, Palette.BEDROCK)

	_mesh_instance = _voxel_model(g)


func interact(player: Node) -> void:
	if player == null or not ("inventory" in player):
		return
	var inv: Inventory = player.inventory
	if inv == null:
		return

	# Drafting a blueprint scroll consumes 2 paper/parchment (or driftwood) and generates a blueprint_scroll
	if inv.has_item(&"driftwood") or inv.has_item(&"sea_glass"):
		if inv.has_item(&"driftwood"):
			inv.remove_item(&"driftwood", 1)
		drafts_completed += 1
		inv.add_item(&"blueprint_scroll", 1)
		if player.has_method("quest_event"):
			player.quest_event(QuestDef.ObjectiveType.CRAFT_ITEM, &"blueprint_scroll")


func export_schematic(schematic_name: String, author: String, dims: Vector3i, voxels: Array) -> Dictionary:
	drafts_completed += 1
	return BlueprintCatalog.export_blueprint(schematic_name, author, dims, voxels)


func list_available_blueprints() -> Array[Dictionary]:
	return BlueprintCatalog.list_local_blueprints()
