class_name PlacementController
extends Node3D
## Player-side placing, using and picking up of world entities.
##
##   Tap F (X on a pad)      use the nearest entity            -> WorldEntity.client_interact()
##   Hold F 0.6 s            pick it up (returns the item + contents)
##   Blueprints tool (3)     Q/E cycles past the voxel prefabs into placeable furniture; LMB places,
##                           paying Placeables.build_cost() from the inventory
##   Item tool (5)           holding a placeable item in the hotbar: LMB places it (consumes the item)
##   R                       rotate (shared with prefab rotation)
##
## Placement rules: ground support under the footprint centre, free voxels inside the footprint,
## no overlap with solid entities/boats/the player, and the type's rule
## (&"intertidal" = between low and high tide).

const HOLD_PICKUP_SEC := 0.6
const VS := VoxelWorld.VS

var player: Player
var entity_blueprint: StringName = &""  # Blueprints tool: placeable type selected (&"" = voxel prefab)
var _bp_index := -1
var _hold_t := -1.0
var _hold_target: WorldEntity = null
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var arrow: PlacementArrow           ## points out of the front of what you're placing
var _place_coord := Vector3i.ZERO
var _place_type: StringName = &""
var _place_ok := false
var _place_reason := ""


func setup(p: Player) -> void:
	player = p
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost.material_override = _ghost_mat
	_ghost.top_level = true
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	arrow = PlacementArrow.new()
	add_child(arrow)


# ---------------------------------------------------------------- input

## Called from Player._unhandled_input. Returns true if the event was consumed.
func handle_input(e: InputEvent) -> bool:
	if player.entities == null:
		return false
	if e.is_action_pressed("interact"):
		var boats: Node = player.entities.main.boats if player.entities.main != null else null
		if boats != null and boats.nearest_boardable(player.position) != null:
			return false  # boarding a boat wins
		var ent := player.entities.get_closest_interactable(player.position)
		if ent != null and ent.can_interact(player):
			_hold_t = 0.0
			_hold_target = ent
			return true
	elif e.is_action_released("interact") and _hold_target != null:
		var ent := _hold_target
		_hold_target = null
		_hold_t = -1.0
		if is_instance_valid(ent):
			ent.client_interact(player)
		return true
	return false


func _process(delta: float) -> void:
	if _hold_target == null:
		return
	if not is_instance_valid(_hold_target):
		_hold_target = null
		return
	_hold_t += delta
	if _hold_t >= HOLD_PICKUP_SEC:
		var ent := _hold_target
		_hold_target = null
		_hold_t = -1.0
		if ent.item_id == &"":
			_toast("%s can't be picked up." % ent.entity_name)
		else:
			player.entities.request_remove(ent.grid_coord)


## Blueprints tool Q/E: cycle through voxel prefabs, then placeable furniture.
func cycle_blueprint(d: int) -> void:
	var types := Placeables.blueprint_types()
	var n := Prefabs.count() + types.size()
	if _bp_index < 0:
		_bp_index = player.prefab_id if entity_blueprint == &"" else Prefabs.count() + types.find(entity_blueprint)
	_bp_index = posmod(_bp_index + d, n)
	if _bp_index < Prefabs.count():
		entity_blueprint = &""
		player.prefab_id = _bp_index
	else:
		entity_blueprint = types[_bp_index - Prefabs.count()]


## Type the player is about to place right now, or &"".
func active_type() -> StringName:
	if player.tool == 2:
		return entity_blueprint
	if player.tool == 4:
		var slot := player.inventory.get_active_item()
		if slot != null and not slot.is_empty():
			return EntityManager.type_for_item(slot.item_id)
	return &""


## HUD line for the current placement mode ("" when not placing).
func hud_text() -> String:
	var t := active_type()
	if t == &"":
		return ""
	var def: ItemDef = ItemDB.get_item(t)
	var name: String = def.name if def != null else String(t)
	var cost := "1 %s" % name if player.tool == 4 else BuildCosts.describe(Placeables.build_cost(t))
	var status := "" if _place_ok or _place_reason == "" else "   - %s" % _place_reason
	return "%s   cost: %s   (R rotate, hold F on it to pick up)%s" % [name, cost, status]


# ---------------------------------------------------------------- ghost

## Called after Player._update_target each frame.
func update_ghost() -> void:
	_place_type = active_type()
	_ghost.visible = false
	arrow.visible = false
	_place_ok = false
	_place_reason = ""
	if _place_type == &"" or player.entities == null:
		return
	player._ghost.visible = false
	if player._ghost_arrow != null:
		player._ghost_arrow.visible = false
	# Keep player._highlight visible so the block/entity under the cursor stays highlighted
	if player.target.is_empty():
		_place_reason = "aim at the ground"
		return
	var cell: Vector3i = player.target.cell
	var nrm: Vector3i = player.target.normal
	var c := cell + nrm
	if nrm.y != 1:
		# Side hit: drop to the floor below.
		for k in 8:
			if player.world.get_voxel(c.x, c.y - 1, c.z) != 0:
				break
			c.y -= 1
	_place_coord = c
	var probe := _probe(_place_type, c, player.prefab_rot)
	var box := probe.get_aabb()
	_place_reason = _check(probe, box)
	probe.free()
	_place_ok = _place_reason == ""
	(_ghost.mesh as BoxMesh).size = box.size
	_ghost.global_position = box.get_center()
	_ghost_mat.albedo_color = Color(0.55, 1.0, 0.7, 0.45) if _place_ok else Color(1.0, 0.45, 0.4, 0.45)
	_ghost.visible = true
	arrow.show_for(box, PlacementArrow.entity_front(player.prefab_rot),
		Color(0.55, 1.0, 0.7) if _place_ok else Color(1.0, 0.45, 0.4))


func _probe(type: StringName, c: Vector3i, rot: int) -> WorldEntity:
	var def := EntityManager.get_type_def(type)
	var e: WorldEntity = (def.factory as Callable).call(c) if not def.is_empty() else WorldEntity.new(type, "", c)
	e.rotation_steps = rot
	return e


func _check(probe: WorldEntity, box: AABB) -> String:
	var w := player.world
	var rule: StringName = EntityManager.get_type_def(_place_type).get("rule", &"ground")
	var c := probe.grid_coord
	var m := w.get_voxel(c.x, c.y - 1, c.z)
	if m == 0 or Palette.is_foliage(m):
		return "needs solid ground"
	if rule == &"soil" and not (m in [Palette.GRASS, Palette.GRASS_DRY, Palette.DIRT, Palette.SAND]):
		return "needs dirt, grass, or sand to take root"
	var lo := Vector3i((box.position / VS).floor())
	var hi := Vector3i(((box.end - Vector3.ONE * 0.001) / VS).floor())
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				var v := w.get_voxel(x, y, z)
				if v != 0 and not Palette.is_foliage(v):
					return "blocked"
	if rule == &"intertidal":
		var low := VoxelWorld.SEA_MID - VoxelWorld.TIDE_AMP
		var high := VoxelWorld.SEA_MID + VoxelWorld.TIDE_AMP
		if c.y < low or c.y > high - 1:
			return "must sit between low and high tide"
	if player.entities.overlaps_any(_place_type, c, probe.rotation_steps):
		return "something's in the way"
	var pbox := AABB(player.position - Vector3(Player.HW, 0, Player.HW), Vector3(Player.HW * 2, Player.H, Player.HW * 2))
	if pbox.intersects(box):
		return "you're standing there"
	return ""


# ---------------------------------------------------------------- placing

## Called at the start of Player._use_tool. Returns true if this handled the click.
func try_use() -> bool:
	var t := active_type()
	if t == &"":
		return false
	if not _place_ok:
		_toast("Can't place here: %s" % _place_reason if _place_reason != "" else "Can't place here")
		return true
	var is_creative: bool = player != null and player.get("creative_mode") == true
	if not is_creative:
		if player.tool == 4:
			if player.inventory.remove_item(t, 1) <= 0:
				return true
		else:
			var cost := Placeables.build_cost(t)
			if not BuildCosts.can_afford(player.inventory, cost):
				_toast("Need " + BuildCosts.describe_missing(player.inventory, cost))
				return true
			BuildCosts.pay(player.inventory, cost)
	if not player.entities.request_place(t, _place_coord, player.prefab_rot):
		if not is_creative:
			_refund(t)
		_toast("Can't place that there")
	else:
		player.quest_event(QuestDef.ObjectiveType.PLACE_ENTITY, t)
	return true


func _refund(t: StringName) -> void:
	if player.tool == 4:
		player.inventory.add_item(t, 1)
	else:
		var cost := Placeables.build_cost(t)
		for item: StringName in cost:
			player.inventory.add_item(item, cost[item])


func _toast(t: String) -> void:
	if player.hud:
		player.hud.show_toast(t)
