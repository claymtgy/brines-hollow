class_name SaltPanEntity
extends WorldEntity
## Clay salt pan (wraps farming/salt_pan.gd). The high tide fills it with brine; at low tide
## the sun evaporates it into sea salt. Simulated on the host/server, collected by anyone.

const U := VoxelWorld.VS * 0.5

var pan: SaltPan
var _brine_node: MeshInstance3D
var _salt_node: MeshInstance3D


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"salt_pan", "Clay Salt Pan", p_coord)
	entity_type = EntityType.TRAP
	pan = SaltPan.new(p_coord)
	size = Vector3(14, 2, 14) * U
	state_changed.connect(_refresh_visuals)


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(14, 2, 14)
	g.box(0, 0, 0, 13, 0, 13, Palette.COBBLE)
	g.box(0, 1, 0, 13, 1, 13, Palette.SANDSTONE_B)
	g.box(1, 1, 1, 12, 1, 12, 0)
	_mesh_instance = _voxel_model(g)
	var water := Prefabs.Grid.new(12, 1, 12)
	water.box(0, 0, 0, 11, 0, 11, Palette.SHUTTER)
	_brine_node = _voxel_model(water)
	_brine_node.position.y = U * 0.6
	var salt := Prefabs.Grid.new(12, 1, 12)
	salt.box(0, 0, 0, 11, 0, 11, Palette.WHITEWASH)
	_salt_node = _voxel_model(salt)
	_salt_node.position.y = U * 0.7
	_refresh_visuals()


func _refresh_visuals() -> void:
	if _salt_node == null:
		return
	_salt_node.visible = pan.accumulated_salt > 0
	_brine_node.visible = pan.brine_level > 0.0 and pan.accumulated_salt == 0


func get_interaction_prompt(_player: Player) -> String:
	if pan.accumulated_salt > 0:
		return "F  Collect %d sea salt" % pan.accumulated_salt
	if pan.brine_level > 0.0:
		return "Salt pan: evaporating %d%%" % int(pan.evaporation_progress * 100.0)
	return "Salt pan: waiting for the high tide to fill it"


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if pan.accumulated_salt > 0:
		manager.request_action(self, &"harvest", {})
	elif player.hud:
		player.hud.show_toast(get_interaction_prompt(player))


func server_action(action: StringName, _args: Dictionary, _peer: int) -> Dictionary:
	if action == &"harvest" and pan.accumulated_salt > 0:
		var n := pan.harvest()
		_refresh_visuals()
		return {"changed": true, "grant": [[&"sea_salt", n]], "gathered": true, "toast": "Collected %d sea salt!" % n}
	return {}


func server_tick(delta: float, env: Dictionary) -> bool:
	var salt := pan.accumulated_salt
	var full := pan.brine_level > 0.0
	var pct := int(pan.evaporation_progress * 10.0)
	pan.tick(delta, float(env.get("tide_vox", 0.0)), bool(env.get("daylight", true)), false)
	var changed := salt != pan.accumulated_salt or full != (pan.brine_level > 0.0) or pct != int(pan.evaporation_progress * 10.0)
	if changed:
		_refresh_visuals()
	return changed


func pickup_items() -> Array:
	var out := super.pickup_items()
	if pan.accumulated_salt > 0:
		out.append([&"sea_salt", pan.accumulated_salt])
	return out


func serialize() -> Dictionary:
	var d := super.serialize()
	d["pan"] = pan.serialize()
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	if data.has("pan"):
		pan = SaltPan.deserialize(data["pan"])
		pan.pos = grid_coord
	_refresh_visuals()
