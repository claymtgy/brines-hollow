class_name TreeSaplingEntity
extends WorldEntity
## Plantable and growable Pine Sapling entity.
## Progresses through 3 visible 3D sapling stages over time (or faster when watered/tended with F),
## then erupts into a full-size choppable voxel tree in VoxelWorld.

const U := VoxelWorld.VS * 0.5
const GROW_DURATION_SEC := 40.0
const WATER_BOOST_FRAC := 0.35

var growth: float = 0.0        # 0.0 -> 1.0
var stage: int = -1            # 0 = sprout, 1 = young sapling, 2 = tall sapling
var tree_seed: int = 1
var _maturing: bool = false


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"pine_sapling", "Pine Sapling", p_coord)
	item_id = &"pine_sapling"
	solid = false
	size = Vector3(4.0 * U, 8.0 * U, 4.0 * U)
	interaction_radius = 2.8
	tree_seed = abs(int(p_coord.x * 73856093 ^ p_coord.y * 19349663 ^ p_coord.z * 83492791)) + 1


func _build_visuals() -> void:
	_rebuild_stage_mesh(0)
	_apply_growth_scale()


func _stage_for_growth(g: float) -> int:
	if g < 0.38:
		return 0
	elif g < 0.75:
		return 1
	return 2


func _rebuild_stage_mesh(new_stage: int) -> void:
	stage = new_stage
	if _mesh_instance != null:
		_mesh_instance.queue_free()
		_mesh_instance = null

	var g: Prefabs.Grid
	match stage:
		0:
			# Small newly-planted seedling sprout
			g = Prefabs.Grid.new(5, 7, 5)
			g.setv(2, 0, 2, Palette.DIRT)
			g.box(2, 1, 2, 2, 3, 2, Palette.TRUNK)
			g.box(1, 3, 2, 3, 4, 2, Palette.LEAVES)
			g.box(2, 3, 1, 2, 4, 3, Palette.LEAVES)
			g.setv(2, 5, 2, Palette.LEAVES_DARK)
		1:
			# Young two-tiered pine sapling
			g = Prefabs.Grid.new(7, 12, 7)
			g.box(2, 0, 2, 4, 0, 4, Palette.DIRT)
			g.box(3, 1, 3, 3, 7, 3, Palette.TRUNK)
			g.box(1, 4, 2, 5, 5, 4, Palette.LEAVES_DARK)
			g.box(2, 4, 1, 4, 5, 5, Palette.LEAVES_DARK)
			g.box(2, 7, 2, 4, 8, 4, Palette.LEAVES)
			g.setv(3, 9, 3, Palette.LEAVES)
			g.setv(3, 10, 3, Palette.LEAVES_DARK)
		_:
			# Tall sturdy sapling nearly ready to become a full tree
			g = Prefabs.Grid.new(9, 16, 9)
			g.box(3, 0, 3, 5, 0, 5, Palette.DIRT)
			g.box(4, 1, 4, 4, 11, 4, Palette.TRUNK)
			g.box(1, 5, 2, 7, 6, 6, Palette.LEAVES_DARK)
			g.box(2, 5, 1, 6, 6, 7, Palette.LEAVES_DARK)
			g.box(2, 8, 2, 6, 10, 6, Palette.LEAVES)
			g.box(3, 11, 3, 5, 13, 5, Palette.LEAVES_DARK)
			g.box(4, 14, 4, 4, 15, 4, Palette.LEAVES)

	_mesh_instance = _voxel_model(g)


func _apply_growth_scale() -> void:
	if _mesh_instance == null:
		return
	var s := lerpf(0.82, 1.18, clampf(growth, 0.0, 1.0))
	_mesh_instance.scale = Vector3(s, s, s)


func get_interaction_prompt(_player: Player) -> String:
	var pct := int(round(clampf(growth, 0.0, 1.0) * 100.0))
	var rem_sec := int(ceil(maxf(0.0, (1.0 - growth) * GROW_DURATION_SEC)))
	return "F  Water / Tend Pine Sapling (Growth: %d%% — %ds left)" % [pct, rem_sec]


func client_interact(player: Player) -> void:
	if _maturing:
		return
	growth = minf(1.0, growth + WATER_BOOST_FRAC)
	var new_st := _stage_for_growth(growth)
	if new_st != stage:
		_rebuild_stage_mesh(new_st)
	_apply_growth_scale()
	_spawn_growth_particles(false)

	if growth >= 1.0:
		_mature_into_tree(player)
	else:
		var pct := int(round(growth * 100.0))
		if player != null and player.hud != null:
			player.hud.show_toast("Watered Pine Sapling! Growth: %d%%" % pct)
		if manager != null:
			manager.push_state(self)


func tick(delta: float) -> void:
	if _maturing:
		return
	growth = minf(1.0, growth + delta / GROW_DURATION_SEC)
	var new_st := _stage_for_growth(growth)
	if new_st != stage:
		_rebuild_stage_mesh(new_st)
	_apply_growth_scale()

	if growth >= 1.0 and (manager == null or manager.is_authority()):
		var p: Player = manager.main.player if (manager != null and manager.main != null and manager.main.get("player") != null) else null
		_mature_into_tree(p)


func _spawn_growth_particles(big_burst: bool) -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.emitting = false
	burst.amount = 24 if big_burst else 10
	burst.lifetime = 0.85
	burst.explosiveness = 0.9
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.09
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.COLORS[Palette.LEAVES]
	mat.roughness = 0.8
	bm.material = mat
	burst.mesh = bm
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.35 if big_burst else 0.18
	burst.direction = Vector3.UP
	burst.spread = 55.0
	burst.initial_velocity_min = 1.2
	burst.initial_velocity_max = 2.8 if big_burst else 1.9
	burst.gravity = Vector3(0.0, -7.5, 0.0)
	get_parent().add_child(burst)
	burst.global_position = global_position + Vector3(0.0, 0.45, 0.0)
	burst.emitting = true
	get_tree().create_timer(1.1).timeout.connect(burst.queue_free)


func _mature_into_tree(player: Player = null) -> void:
	if _maturing:
		return
	_maturing = true
	_spawn_growth_particles(true)

	var main_node: Node = manager.main if manager != null else null
	if main_node != null and main_node.get("world") != null:
		var w: VoxelWorld = main_node.world
		# Move the player slightly aside if they are standing right inside the new 3x3 trunk
		if player != null and is_instance_valid(player):
			var trunk_center := (Vector3(grid_coord) + Vector3(0.5, 0.0, 0.5)) * VoxelWorld.VS
			var horiz := Vector2(player.global_position.x - trunk_center.x, player.global_position.z - trunk_center.z)
			if horiz.length() < 0.65:
				var push_dir := horiz.normalized() if horiz.length() > 0.01 else Vector2(1.0, 0.0)
				player.global_position.x = trunk_center.x + push_dir.x * 0.78
				player.global_position.z = trunk_center.z + push_dir.y * 0.78
			if player.global_position.distance_to(global_position) <= 18.0 and player.hud != null:
				player.hud.show_toast("Pine Sapling grew into a full Pine Tree!")
		if main_node.has_method("_on_command_requested"):
			main_node._on_command_requested({"t": "grow_tree", "p": grid_coord, "s": tree_seed})
		else:
			w.grow_tree_at(grid_coord, tree_seed)

	if manager != null:
		manager.remove_entity(grid_coord)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["growth"] = growth
	d["tree_seed"] = tree_seed
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	growth = float(data.get("growth", 0.0))
	tree_seed = int(data.get("tree_seed", 1))
	var st := _stage_for_growth(growth)
	if st != stage:
		_rebuild_stage_mesh(st)
	_apply_growth_scale()
