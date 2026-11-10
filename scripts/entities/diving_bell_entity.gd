class_name DivingBellEntity
extends WorldEntity
## Submerged Diving Bell: a heavy brass dome lowered into deep coastal trenches and sunken ruins.
## Traps an air pocket underneath that restores player breath and provides a luminous deep-sea staging outpost.

const U := VoxelWorld.VS * 0.5
const AIR_RADIUS := 3.8

var _light: OmniLight3D
var _check_t := 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"diving_bell", "Submerged Diving Bell", p_coord)
	entity_type = EntityType.WORKSTATION
	item_id = &"diving_bell"
	size = Vector3(12, 16, 12) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(12, 16, 12)
	# Heavy brass domed roof
	g.box(2, 12, 2, 9, 15, 9, Palette.METAL)
	g.box(3, 15, 3, 8, 16, 8, Palette.METAL)      # top cable hoist ring
	# 4 Heavy iron corner columns
	g.box(1, 1, 1, 3, 12, 3, Palette.DARK_WOOD)
	g.box(8, 1, 1, 10, 12, 3, Palette.DARK_WOOD)
	g.box(1, 1, 8, 3, 12, 10, Palette.DARK_WOOD)
	g.box(8, 1, 8, 10, 12, 10, Palette.DARK_WOOD)
	# Brass ballast ring base
	g.box(0, 0, 0, 11, 2, 11, Palette.STONE)
	g.box(2, 0, 2, 9, 2, 9, Palette.CLEAR)         # open center to swim up inside

	_mesh_instance = _voxel_model(g)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.85, 0.45)
	_light.light_energy = 1.8
	_light.omni_range = 10.0
	_light.position = Vector3(0, 12 * U, 0)
	add_child(_light)


func _process(dt: float) -> void:
	if not is_inside_tree():
		return
	_check_t -= dt
	if _check_t > 0.0:
		return
	_check_t = 0.25

	var em := EntityManager.current
	if em == null or em.main == null:
		return
	var p: Player = em.main.player
	if p != null and position.distance_to(p.position) <= AIR_RADIUS:
		# Replenish player breath/oxygen
		if p.vitality != null and "breath" in p.vitality:
			p.vitality.breath = p.vitality.max_breath


func get_interaction_prompt(_player: Player) -> String:
	return "Diving Bell · Air Pocket & Submerged Staging Post"
