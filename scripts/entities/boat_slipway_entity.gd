class_name BoatSlipwayEntity
extends WorldEntity
## Harbor Slipway & Dry-Dock: placeable shoreline structure that cradles vessels,
## repairs hull fracture damage to 100%, seals leaks, and applies tarred hull reinforcements.

var visual_node: Node3D = null
var slipway_yaw: float = 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"boat_slipway", "Harbor Slipway Dry-Dock", p_coord)
	entity_type = EntityType.WORKSTATION


func _ready() -> void:
	super._ready()
	_build_visuals()


func _build_visuals() -> void:
	if visual_node != null:
		visual_node.queue_free()
	visual_node = Node3D.new()
	add_child(visual_node)

	# Timber slipway ramp with oak keel-blocks and iron hauling winches
	var g := Prefabs.Grid.new(16, 6, 24)
	# Inclined ramp runners
	g.box(2, 0, 0, 4, 2, 23, Palette.DARK_WOOD)
	g.box(11, 0, 0, 13, 2, 23, Palette.DARK_WOOD)
	# Cross-ties
	for z in range(0, 24, 3):
		g.box(2, 1, z, 13, 2, z + 1, Palette.PLANK)
	# Center keel support blocks
	g.box(7, 2, 2, 8, 3, 20, Palette.DARK_WOOD)
	# Iron winch capstan at head of ramp
	g.box(6, 3, 21, 9, 5, 23, Palette.METAL)
	g.box(7, 4, 20, 8, 4, 21, Palette.HANDLE)

	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.85)
	mi.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VoxelWorld.VS, mat, mat)
	mi.position = Vector3(-g.sx * 0.5, 0.0, -g.sz * 0.5) * VoxelWorld.VS
	visual_node.add_child(mi)


func interact_prompt() -> String:
	return "[E] Slipway Haul-Out & Dry-Dock Restoration"


func interact(player: Node, target_boat: Boat = null) -> void:
	var boat := target_boat if target_boat != null else find_nearest_boat(10.0)
	if boat == null:
		if player != null and "hud" in player and player.hud != null:
			player.hud.show_toast("No boat moored near the slipway to haul out.")
		return

	if boat.hull_hp < boat.max_hull_hp or boat.is_leaking() or not boat.reinforced_hull:
		boat.repair_hull(boat.max_hull_hp)
		boat.leak_amount = 0.0
		boat.reinforced_hull = true
		CombatAudio.play_sound("fanfare", boat.position)
		if player != null and "hud" in player and player.hud != null:
			player.hud.show_toast("Vessel Overhauled: Hull fully caulked, leaks sealed & reinforced!")
	else:
		if player != null and "hud" in player and player.hud != null:
			player.hud.show_toast("Vessel in dry-dock is already sound and seaworthy.")


func find_nearest_boat(max_dist: float = 10.0) -> Boat:
	var tree := get_tree() if is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	var world_pos := global_position if (is_inside_tree() and get_parent() != null and get_parent() != (tree.root if tree != null else null)) else position
	var best_dist := max_dist
	var best_boat: Boat = null

	var boats: Array = []
	if tree != null:
		for n in tree.get_nodes_in_group("boats"):
			if n is Boat:
				boats.append(n)
	if get_parent() != null:
		for ch in get_parent().get_children():
			if ch is Boat and not boats.has(ch):
				boats.append(ch)
	if boats.is_empty() and tree != null and tree.root != null:
		for ch in tree.root.get_children():
			if ch is Boat and not boats.has(ch):
				boats.append(ch)

	for b: Boat in boats:
		var b_pos: Vector3 = b.global_position if (b.is_inside_tree() and b.get_parent() != null and b.get_parent() != (tree.root if tree != null else null)) else b.position
		var d := world_pos.distance_to(b_pos)
		if d < best_dist:
			best_dist = d
			best_boat = b

	if best_boat == null and tree != null and tree.root != null:
		var main := tree.root.get_node_or_null("Main")
		if main != null and "boat_manager" in main and main.boat_manager != null:
			for b in main.boat_manager.boats.values():
				if b is Boat:
					var b_pos: Vector3 = b.global_position if b.is_inside_tree() else b.position
					var d := world_pos.distance_to(b_pos)
					if d < best_dist:
						best_dist = d
						best_boat = b
	return best_boat


func serialize() -> Dictionary:
	var data := super.serialize()
	data["yaw"] = slipway_yaw
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	slipway_yaw = float(data.get("yaw", 0.0))
