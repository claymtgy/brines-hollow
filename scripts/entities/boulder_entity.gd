class_name BoulderEntity
extends WorldEntity
## A loose boulder on the rocks above the Barnacled Hulk's strand. Push it (F) and it
## tumbles down onto whatever is below: the Hulk, if you lured it close enough, cracking its
## shell. Another works loose from the rock a little while later.

const U := VoxelWorld.VS * 0.5
const REGROW_SEC := 75.0

var pushed := false
var _regrow := 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"loose_boulder", "Loose Boulder", p_coord)
	entity_type = EntityType.TRAP
	size = Vector3(14, 12, 14) * U
	state_changed.connect(_refresh)


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(14, 13, 14)
	for z in 14:
		for y in 13:
			for x in 14:
				var e := Vector3((x - 6.5) / 7.0, (y - 6.0) / 6.5, (z - 6.5) / 7.0)
				if e.length() <= 1.0 + sin(x * 1.7 + z) * 0.06:
					g.setv(x, y, z, Palette.STONE if (x + y + z) % 4 != 0 else Palette.GRAVEL)
	g.box(3, 11, 5, 6, 12, 8, Palette.KELP)          # lichen
	_mesh_instance = _voxel_model(g)
	_refresh()


func _refresh() -> void:
	if _mesh_instance != null:
		_mesh_instance.visible = not pushed


func get_interaction_prompt(_player: Player) -> String:
	if pushed:
		return "The rock where the boulder sat: another will work loose soon"
	return "F  Push the boulder off the rocks"


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if pushed:
		if player.hud:
			player.hud.show_toast(get_interaction_prompt(player))
		return
	manager.request_action(self, &"push", {})


func server_action(action: StringName, _args: Dictionary, peer: int) -> Dictionary:
	if action != &"push" or pushed:
		return {}
	pushed = true
	_regrow = REGROW_SEC
	_refresh()
	var lair := HulkLair.current
	var hit := lair != null and lair.drop_boulder(position, peer)
	return {"changed": true, "toast": "" if hit else "The boulder thunders down onto the empty strand."}


func server_tick(delta: float, _env: Dictionary) -> bool:
	if not pushed:
		return false
	_regrow -= delta
	if _regrow <= 0.0:
		pushed = false
		_refresh()
		return true
	return false


func serialize() -> Dictionary:
	var d := super.serialize()
	d["pushed"] = pushed
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	pushed = bool(data.get("pushed", false))
	_refresh()
