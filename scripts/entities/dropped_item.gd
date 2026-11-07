class_name DroppedItem
extends Node3D
## Physical 3D item drop spawned in the world when mining voxels or dropping items.
## Pops out with an initial velocity arc, lands on terrain (or floats on water),
## bobs and rotates in place, merges with nearby identical drops, and is picked up
## when the player walks over it.

const PICKUP_RADIUS := 1.85
const PICKUP_VERTICAL_RANGE := 2.2
const MAGNET_SPEED := 16.0
const COLLECT_DIST := 0.85
const MERGE_DIST := 0.85
const GRAVITY := 14.0
const MAX_LIFETIME := 300.0  # 5 minutes before despawn

static var active_drops: Array[DroppedItem] = []

var item_id: StringName = &""
var count: int = 1
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0
var pickup_delay: float = 0.25
var on_ground: bool = false

var world: VoxelWorld = null
var target_player: Player = null

var _magnetizing: bool = false
var _visual_root: Node3D = null
var _label: Label3D = null
var _bob_phase: float = 0.0


static func spawn_drop(
	parent: Node,
	p_world: VoxelWorld,
	p_player: Player,
	world_pos: Vector3,
	p_item_id: StringName,
	p_count: int = 1
) -> DroppedItem:
	if p_count <= 0 or p_item_id == &"":
		return null
	var drop := DroppedItem.new()
	drop.item_id = p_item_id
	drop.count = p_count
	drop.world = p_world
	drop.target_player = p_player
	var angle := randf() * TAU
	var horiz_spd := randf_range(0.9, 2.2)
	drop.velocity = Vector3(cos(angle) * horiz_spd, randf_range(2.6, 4.2), sin(angle) * horiz_spd)
	drop._bob_phase = randf() * TAU
	parent.add_child(drop)
	drop.global_position = world_pos + Vector3(cos(angle) * 0.14, 0.16, sin(angle) * 0.14)
	# Nudge out if spawned inside solid voxel
	if p_world != null:
		for _i in 4:
			if p_world.is_solid_at(drop.global_position):
				drop.global_position.y += VoxelWorld.VS
			else:
				break
	return drop


func _ready() -> void:
	active_drops.append(self)
	_build_visuals()


func _exit_tree() -> void:
	active_drops.erase(self)


func _build_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	var def: ItemDef = ItemDB.get_item(item_id)
	var col := _color_for_item(item_id, def)

	# 3D miniature voxel/resource chunk
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.24, 0.24, 0.24)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.78
	if item_id == &"copper_ore" or item_id == &"sea_iron_ore" or item_id == &"sea_brass_ingot" or item_id == &"iron_ingot":
		mat.metallic = 0.45
		mat.roughness = 0.45
	box.material = mat
	mesh_inst.mesh = box
	mesh_inst.rotation_degrees = Vector3(14.0, 25.0, -10.0)
	_visual_root.add_child(mesh_inst)

	# Ore / timber accent details
	if item_id == &"copper_ore" or item_id == &"sea_iron_ore":
		var speck := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(0.26, 0.10, 0.10)
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.88, 0.52, 0.26) if item_id == &"copper_ore" else Color(0.72, 0.78, 0.86)
		smat.metallic = 0.7
		smat.roughness = 0.3
		sbox.material = smat
		speck.mesh = sbox
		mesh_inst.add_child(speck)
	elif item_id == &"pine_wood" or item_id == &"driftwood":
		box.size = Vector3(0.16, 0.16, 0.32)

	# Floating icon sprite above/inside for non-voxel items
	if def != null and not def.is_voxel() and not (item_id in [&"copper_ore", &"sea_iron_ore", &"pine_wood", &"driftwood", &"stone", &"dirt"]):
		var sp := Sprite3D.new()
		sp.texture = ItemIcons.for_item(item_id)
		sp.pixel_size = 0.011
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.position = Vector3(0.0, 0.18, 0.0)
		_visual_root.add_child(sp)

	# Floating 3D label when player is nearby
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.pixel_size = 0.0032
	_label.font_size = 42
	_label.outline_size = 10
	_label.modulate = Color(0.98, 0.94, 0.82, 0.95)
	_label.outline_modulate = Color(0.08, 0.07, 0.05, 0.92)
	_label.position = Vector3(0.0, 0.38, 0.0)
	_label.visible = false
	add_child(_label)
	_update_label_text()


func _update_label_text() -> void:
	if _label == null:
		return
	var def: ItemDef = ItemDB.get_item(item_id)
	var item_name: String = def.name if def != null else String(item_id)
	_label.text = ("%s x%d" % [item_name, count]) if count > 1 else item_name


func _color_for_item(id: StringName, def: ItemDef) -> Color:
	if def != null and def.is_voxel() and def.voxel_mat >= 0 and def.voxel_mat < Palette.COLORS.size():
		return Palette.COLORS[def.voxel_mat]
	match id:
		&"copper_ore":
			return Color(0.76, 0.45, 0.25)
		&"sea_iron_ore":
			return Color(0.52, 0.56, 0.62)
		&"pine_wood":
			return Palette.COLORS[Palette.TRUNK]
		&"driftwood":
			return Palette.COLORS[Palette.DRIFTWOOD]
		&"stone":
			return Palette.COLORS[Palette.STONE]
		&"dirt":
			return Palette.COLORS[Palette.DIRT]
		&"sand":
			return Palette.COLORS[Palette.SAND]
		_:
			return Color(0.78, 0.68, 0.50)


func _process(delta: float) -> void:
	age += delta
	if age >= MAX_LIFETIME:
		queue_free()
		return

	# Spin and bob visuals
	if _visual_root != null:
		_visual_root.rotate_y(1.9 * delta)
		_visual_root.position.y = 0.14 + sin(age * 3.2 + _bob_phase) * 0.055

	# Check player proximity for label and walk-over pickup
	if target_player == null or not is_instance_valid(target_player):
		var tree := get_tree()
		if tree != null and tree.current_scene != null and "player" in tree.current_scene:
			target_player = tree.current_scene.player

	if target_player != null and is_instance_valid(target_player):
		var player_center := target_player.global_position + Vector3(0.0, 0.72, 0.0)
		var horiz_dist := Vector2(global_position.x - player_center.x, global_position.z - player_center.z).length()
		var vert_dist := absf(global_position.y - player_center.y)
		if _label != null:
			_label.visible = horiz_dist < 4.5 and vert_dist < 3.0

		if age >= pickup_delay:
			var to_player := player_center - global_position
			var dist := to_player.length()
			if dist <= COLLECT_DIST or (horiz_dist <= 0.85 and vert_dist <= 1.4):
				collect_into_player(target_player)
				return
			elif _magnetizing:
				global_position += to_player.normalized() * minf(dist, MAGNET_SPEED * delta)
				return
			elif horiz_dist <= PICKUP_RADIUS and vert_dist <= PICKUP_VERTICAL_RANGE:
				if target_player.inventory != null and target_player.inventory.has_space_for(item_id, 1):
					_magnetizing = true
					return

	# Simulate physics if not magnetizing
	_step_physics(delta)

	# Merge with nearby identical resting drops
	if on_ground and age > 0.6:
		_try_merge_nearby()


func _step_physics(delta: float) -> void:
	var water_y := target_player.water_level if (target_player != null and is_instance_valid(target_player)) else -100.0
	var in_water := (global_position.y < water_y) and (world == null or world.is_water_at(global_position, water_y))
	if in_water:
		# Float gently up to the water surface
		velocity.y = lerpf(velocity.y, 1.4, 5.0 * delta)
		velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)
		on_ground = false
	else:
		velocity.y -= GRAVITY * delta

	var next_pos := global_position + velocity * delta
	if world != null:
		# Horizontal collision check
		var horiz_probe := Vector3(next_pos.x, global_position.y + 0.1, next_pos.z)
		if world.is_solid_at(horiz_probe):
			velocity.x = -velocity.x * 0.3
			velocity.z = -velocity.z * 0.3
			next_pos.x = global_position.x
			next_pos.z = global_position.z

		# Vertical ground collision check
		var foot_probe := Vector3(next_pos.x, next_pos.y - 0.12, next_pos.z)
		if velocity.y <= 0.0 and world.is_solid_at(foot_probe):
			# Snap onto top of voxel cell
			var vox_y := floori(foot_probe.y / VoxelWorld.VS)
			next_pos.y = float(vox_y + 1) * VoxelWorld.VS + 0.12
			if velocity.y < -1.8:
				velocity.y = -velocity.y * 0.25
			else:
				velocity.y = 0.0
				on_ground = true
			velocity.x = move_toward(velocity.x, 0.0, 9.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 9.0 * delta)
		else:
			on_ground = false

	global_position = next_pos


func _try_merge_nearby() -> void:
	for other: DroppedItem in active_drops:
		if other == null or other == self or not is_instance_valid(other) or other.is_queued_for_deletion():
			continue
		if other.item_id != item_id or other._magnetizing:
			continue
		if global_position.distance_squared_to(other.global_position) <= MERGE_DIST * MERGE_DIST:
			count += other.count
			_update_label_text()
			other.queue_free()
			break


## Attempts to collect this drop into `p_player`'s inventory when walking over it.
## Returns the number of items picked up.
func collect_into_player(p_player: Player) -> int:
	if p_player == null or p_player.inventory == null or count <= 0:
		return 0
	var remainder: int = p_player.inventory.add_item(item_id, count)
	var added: int = count - remainder
	if added > 0:
		if p_player.quests != null:
			p_player.quests.notify_event(QuestDef.ObjectiveType.GATHER_ITEM, item_id, added, p_player.inventory)
		if p_player.hud != null:
			var def: ItemDef = ItemDB.get_item(item_id)
			var item_name: String = def.display_name if def else String(item_id)
			p_player.hud.show_toast("+%d %s" % [added, item_name])
		count -= added
		if count <= 0:
			queue_free()
		else:
			_magnetizing = false
			_update_label_text()
	else:
		_magnetizing = false
	return added
