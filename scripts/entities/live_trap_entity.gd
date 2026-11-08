class_name LiveTrapEntity
extends WorldEntity
## Live-Capture Trap: a wicker-and-wire cage. Bait it with fish or kelp; a fox or stoat that
## comes raiding goes for the bait first and the door drops behind it. Press F on a full
## trap to carry the animal off to a far islet and let it go (no harm done, and the farm is
## left alone for a good while after).

const U := VoxelWorld.VS * 0.5
const LURE_RANGE := 12.0     ## metres: raiders this close smell the bait

enum TrapState { EMPTY, BAITED, CAUGHT }

var trap_state := TrapState.EMPTY
var caught_kind := &""
var _door: MeshInstance3D
var _bait_mesh: MeshInstance3D
var _caught_mesh: MeshInstance3D


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"live_trap", "Live-Capture Trap", p_coord)
	entity_type = EntityType.TRAP
	item_id = &"live_trap"
	size = Vector3(8, 7, 14) * U
	solid = false   # raiders walk in; players step over it
	state_changed.connect(_refresh)


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(8, 7, 14)
	g.box(0, 0, 0, 7, 0, 13, Palette.PLANK)              # floor
	for z in range(0, 14, 3):                            # wire hoops
		g.box(0, 1, z, 0, 5, z, Palette.METAL)
		g.box(7, 1, z, 7, 5, z, Palette.METAL)
		g.box(0, 6, z, 7, 6, z, Palette.METAL)
	g.box(0, 6, 0, 0, 6, 13, Palette.DRIFTWOOD)
	g.box(7, 6, 0, 7, 6, 13, Palette.DRIFTWOOD)
	g.box(0, 1, 13, 7, 6, 13, Palette.METAL)             # back wall
	_mesh_instance = _voxel_model(g)
	var door := Prefabs.Grid.new(8, 6, 1)
	door.box(0, 0, 0, 7, 5, 0, Palette.METAL)
	for x in [1, 3, 4, 6]:
		for y in [1, 2, 3, 4]:
			door.setv(x, y, 0, Palette.AIR)
	_door = _voxel_model(door)
	_door.position.z = -7.0 * U
	var bait := Prefabs.Grid.new(3, 1, 4)
	bait.box(0, 0, 0, 2, 0, 3, Palette.SHUTTER)
	_bait_mesh = _voxel_model(bait)
	_bait_mesh.position += Vector3(0, U, 3.0 * U)
	var animal := Prefabs.Grid.new(4, 4, 8)
	animal.box(0, 0, 0, 3, 3, 7, Palette.ROOF_RED)
	animal.box(1, 0, 6, 2, 1, 7, Palette.WHITEWASH)
	animal.setv(0, 3, 7, Palette.EYE)
	animal.setv(3, 3, 7, Palette.EYE)
	_caught_mesh = _voxel_model(animal)
	_caught_mesh.position.y = U
	_refresh()


func _refresh() -> void:
	if _door == null:
		return
	_door.visible = trap_state == TrapState.CAUGHT
	_bait_mesh.visible = trap_state == TrapState.BAITED
	_caught_mesh.visible = trap_state == TrapState.CAUGHT
	if trap_state == TrapState.CAUGHT:
		_caught_mesh.scale = Vector3(0.6, 0.6, 0.7) if caught_kind in [&"stoat", &"rat"] else Vector3.ONE


func caught_name() -> String:
	match caught_kind:
		&"stoat": return "stoat"
		&"rat": return "shore rat"
	return "fox"


func is_baited() -> bool:
	return trap_state == TrapState.BAITED


func get_interaction_prompt(player: Player) -> String:
	match trap_state:
		TrapState.CAUGHT:
			return "F  Carry the %s off to a far islet and let it go" % caught_name()
		TrapState.BAITED:
			return "Live-Capture Trap (baited)  ·  hold F to pick up"
	var slot: ItemSlot = player.inventory.get_active_item() if player != null and player.inventory != null else null
	if slot != null and not slot.is_empty() and Placeables.is_bait(slot.item_id):
		return "F  Bait the trap"
	return "Live-Capture Trap: hold fish or kelp and press F to bait it"


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if manager == null:
		return
	if trap_state == TrapState.CAUGHT:
		manager.request_action(self, &"release", {})
		return
	if trap_state == TrapState.EMPTY and player != null and player.inventory != null:
		var slot: ItemSlot = player.inventory.get_active_item()
		if slot != null and not slot.is_empty() and Placeables.is_bait(slot.item_id):
			var item := slot.item_id
			if player.inventory.remove_item(item, 1):
				manager.request_action(self, &"bait", {"item": item})
			return
	if player != null and player.hud != null:
		player.hud.show_toast(get_interaction_prompt(player))


func server_action(action: StringName, args: Dictionary, _peer: int) -> Dictionary:
	match action:
		&"bait":
			if trap_state == TrapState.EMPTY:
				trap_state = TrapState.BAITED
				_refresh()
				return {"changed": true, "toast": "Trap baited. Raiders will go for it first."}
			# Already baited: hand the bait back.
			return {"grant": [[StringName(args.get("item", &"kelp_frond")), 1]]}
		&"release":
			if trap_state == TrapState.CAUGHT:
				var who := caught_name()
				trap_state = TrapState.EMPTY
				caught_kind = &""
				_refresh()
				var cn: Node = manager.main.get("creatures") if manager != null and manager.main != null else null
				if cn != null and cn.get("wildlife") != null:
					cn.wildlife.on_raider_relocated(position)
				return {"changed": true, "toast": "You carry the %s to a far islet and let it go. It won't be back soon." % who}
	return {}


## Authority: a raider walked into the bait.
func capture(kind: StringName) -> bool:
	if trap_state != TrapState.BAITED:
		return false
	trap_state = TrapState.CAUGHT
	caught_kind = kind
	_refresh()
	if manager != null:
		manager._broadcast_state(self)
	return true


func pickup_items() -> Array:
	return [[&"live_trap", 1]]


func serialize() -> Dictionary:
	var d := super.serialize()
	d["trap"] = int(trap_state)
	d["caught"] = String(caught_kind)
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	trap_state = int(data.get("trap", 0)) as TrapState
	caught_kind = StringName(data.get("caught", ""))
	_refresh()
