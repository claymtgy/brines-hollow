class_name HeraldicBannerEntity
extends WorldEntity
## Heraldic Settlement Banner: Placeable fluttering nautical clan pennant.
## Marks village territory, clan docks, and architectural fortifications.

const U := VoxelWorld.VS * 0.5

var _banner_mesh: MeshInstance3D
var _wind_t: float = 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"heraldic_banner", "Heraldic Settlement Banner", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"heraldic_banner"
	size = Vector3(4, 16, 4) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(4, 16, 4)
	# Sturdy stone pedestal
	g.box(0, 0, 0, 3, 1, 3, Palette.STONE)
	# Tall timber flagpole
	g.box(1, 1, 1, 2, 14, 2, Palette.DARK_WOOD)
	# Brass finial spearhead
	g.box(1, 15, 1, 2, 15, 2, Palette.METAL)

	_mesh_instance = _voxel_model(g)

	# Fluttering fabric banner
	var bg := Prefabs.Grid.new(8, 8, 1)
	bg.box(0, 0, 0, 7, 7, 0, Palette.ROOF_RED)
	bg.box(2, 2, 0, 5, 5, 0, Palette.SAND) # Heraldic crest center
	_banner_mesh = _voxel_model(bg)
	_banner_mesh.position = Vector3(2 * U, 7 * U, 1 * U)
	add_child(_banner_mesh)


func _process(dt: float) -> void:
	if not is_inside_tree() or _banner_mesh == null:
		return
	_wind_t += dt * 3.5
	_banner_mesh.rotation.y = sin(_wind_t) * 0.15
	_banner_mesh.rotation.z = sin(_wind_t * 0.7) * 0.08
