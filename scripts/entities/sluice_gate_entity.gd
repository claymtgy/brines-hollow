class_name SluiceGateEntity
extends WorldEntity
## Tidal Sluice Gate: heavy timber & iron flood gate used to control tidal flow in channels and estuaries.
## Interacting toggles the gate open or closed, impounding water for tide mills or protecting fields.

const U := VoxelWorld.VS * 0.5

var is_open := false
var _gate_slab: Node3D


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"sluice_gate", "Tidal Sluice Gate", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"sluice_gate"
	size = Vector3(14, 14, 6) * U


func _build_visuals() -> void:
	var root := Node3D.new()
	var g := Prefabs.Grid.new(14, 14, 6)
	# Side piers & top gantry
	g.box(1, 0, 1, 4, 13, 5, Palette.STONE)               # left pier
	g.box(10, 0, 1, 13, 13, 5, Palette.STONE)             # right pier
	g.box(1, 11, 1, 13, 13, 5, Palette.DARK_WOOD)         # top lintel & winch beam
	g.box(6, 13, 2, 8, 14, 4, Palette.METAL)             # iron winch wheel
	var mi_piers := _voxel_model(g)
	mi_piers.position = Vector3(-7, 0, -3) * U
	root.add_child(mi_piers)

	# Moving vertical wooden gate slab
	_gate_slab = Node3D.new()
	root.add_child(_gate_slab)
	var sg := Prefabs.Grid.new(8, 9, 2)
	sg.box(0, 0, 0, 7, 8, 1, Palette.PLANK)
	sg.box(1, 1, 0, 6, 7, 1, Palette.DARK_WOOD)
	var mi_gate := _voxel_model(sg)
	mi_gate.position = Vector3(-4, 0, -1) * U
	_gate_slab.add_child(mi_gate)
	_update_gate_pos()

	_mesh_instance = root


func _update_gate_pos() -> void:
	if _gate_slab != null:
		_gate_slab.position.y = (7.5 if is_open else 1.0) * U


func toggle_gate() -> void:
	is_open = not is_open
	_update_gate_pos()
	CombatAudio.play_sound("parry", position, -4.0)


func get_interaction_prompt(_player: Player) -> String:
	return "F  %s Tidal Sluice Gate  ·  Hold F to pick up" % ["Lower" if is_open else "Raise"]


func client_interact(player: Player) -> void:
	interacted.emit(player)
	toggle_gate()
	if player.hud != null:
		player.hud.show_toast("Sluice Gate %s" % ["Raised (Open)" if is_open else "Lowered (Closed)"])
