class_name BollardEntity
extends WorldEntity
## Mooring Bollard: an iron-capped post for a pier or quay. An empty boat within a boat's
## length of one is tied up: it won't drift on the current or blow away in a storm.

const U := VoxelWorld.VS * 0.5


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"mooring_bollard", "Mooring Bollard", p_coord)
	entity_type = EntityType.DECOR
	size = Vector3(5, 9, 5) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(5, 10, 5)
	g.box(1, 0, 1, 3, 7, 3, Palette.DARK_WOOD)
	g.box(0, 7, 0, 4, 8, 4, Palette.METAL)
	g.box(1, 9, 1, 3, 9, 3, Palette.METAL)
	g.box(0, 4, 1, 4, 4, 3, Palette.HANDLE)          # a coil of rope
	g.box(1, 4, 0, 3, 4, 4, Palette.HANDLE)
	_mesh_instance = _voxel_model(g)


func get_interaction_prompt(_player: Player) -> String:
	return "Mooring Bollard: an empty boat tied up here won't drift"
