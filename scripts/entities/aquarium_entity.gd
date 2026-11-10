class_name AquariumEntity
extends WorldEntity
## Living Glass Aquarium: Decorative maritime water tank with swimming aquatic fauna.
## Radiates gentle bioluminescent sea foam light.

const U := VoxelWorld.VS * 0.5

var _light: OmniLight3D
var _fish_mesh: MeshInstance3D
var _anim_t: float = 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"aquarium", "Glass Living Aquarium", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"aquarium"
	size = Vector3(8, 6, 6) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(8, 6, 6)
	# Brass tank base and frame
	g.box(0, 0, 0, 7, 0, 5, Palette.METAL)
	g.box(0, 5, 0, 7, 5, 5, Palette.METAL)
	# 4 Corner brass posts
	g.box(0, 1, 0, 0, 4, 0, Palette.METAL)
	g.box(7, 1, 0, 7, 4, 0, Palette.METAL)
	g.box(0, 1, 5, 0, 4, 5, Palette.METAL)
	g.box(7, 1, 5, 7, 4, 5, Palette.METAL)
	# Pebble substrate bottom
	g.box(1, 1, 1, 6, 1, 4, Palette.SAND)
	# Kelp sprig
	g.box(2, 2, 2, 2, 4, 2, Palette.KELP)

	_mesh_instance = _voxel_model(g)

	# Ambient sea light
	_light = OmniLight3D.new()
	_light.light_color = Color(0.2, 0.7, 0.85)
	_light.light_energy = 0.8
	_light.omni_range = 4.5
	_light.position = Vector3(0, 3 * U, 0)
	add_child(_light)

	# Swimming miniature fish inside the tank
	var fish_grid := Prefabs.Grid.new(3, 1, 1)
	fish_grid.setv(0, 0, 0, Palette.ROOF_RED)
	fish_grid.setv(1, 0, 0, Palette.EYE)
	fish_grid.setv(2, 0, 0, Palette.ROOF_RED)
	_fish_mesh = _voxel_model(fish_grid)
	_fish_mesh.position = Vector3(0, 3 * U, 0)
	add_child(_fish_mesh)


func _process(dt: float) -> void:
	if not is_inside_tree() or _fish_mesh == null:
		return
	_anim_t += dt * 2.0
	_fish_mesh.position.x = sin(_anim_t) * 1.5 * U
	_fish_mesh.position.y = (3.0 + sin(_anim_t * 1.5) * 0.5) * U
	_fish_mesh.rotation.y = 0.0 if cos(_anim_t) >= 0.0 else PI
