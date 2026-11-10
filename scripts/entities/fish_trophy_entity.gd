class_name FishTrophyEntity
extends WorldEntity
## Taxidermy Fish Trophy: Wall or table mounted prize catch plaque.
## Displays fine craftsmanship and celebrates maritime angling accomplishments.

const U := VoxelWorld.VS * 0.5


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"fish_trophy", "Taxidermy Fish Mount", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"fish_trophy"
	size = Vector3(6, 6, 2) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(6, 6, 2)
	# Varnished wood mounting plaque
	g.box(0, 0, 0, 5, 5, 0, Palette.DARK_WOOD)
	g.box(1, 1, 0, 4, 4, 0, Palette.DRIFTWOOD)
	# Mounted prize fish (body, fins, eye)
	g.box(1, 2, 1, 4, 3, 1, Palette.GLOW_TEAL)
	g.box(4, 2, 1, 4, 4, 1, Palette.CLEAR)
	g.box(0, 2, 1, 0, 3, 1, Palette.CLEAR) # Tail fin
	g.setv(3, 3, 1, Palette.EYE)           # Beaded eye

	_mesh_instance = _voxel_model(g)
