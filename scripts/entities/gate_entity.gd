class_name GateEntity
extends WorldEntity
## Latched Pen Gate: a 2 m gate leaf for livestock pens. Closed, it blocks players, livestock
## and raiding foxes and stoats; open, everything walks through. F toggles it.
## The low boards reach the ground, so nothing slips underneath (unlike a rail fence).

const U := VoxelWorld.VS * 0.5
const W := 22   # leaf width in character voxels (~2 m)

var is_open := false
var _leaf: Node3D


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"pen_gate", "Latched Pen Gate", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"pen_gate"
	size = Vector3(W + 4, 13, 2) * U
	state_changed.connect(_refresh)


func _build_visuals() -> void:
	var posts := Prefabs.Grid.new(W + 4, 14, 2)
	posts.box(0, 0, 0, 1, 13, 1, Palette.DARK_WOOD)
	posts.box(W + 2, 0, 0, W + 3, 13, 1, Palette.DARK_WOOD)
	_mesh_instance = _voxel_model(posts)
	# The leaf hinges on the left post.
	_leaf = Node3D.new()
	_leaf.position = Vector3(-W * 0.5 * U, 0, 0)
	add_child(_leaf)
	var g := Prefabs.Grid.new(W, 12, 1)
	g.box(0, 0, 0, W - 1, 4, 0, Palette.PLANK)            # boards right down to the ground
	g.box(0, 7, 0, W - 1, 7, 0, Palette.DRIFTWOOD)       # middle rail
	g.box(0, 11, 0, W - 1, 11, 0, Palette.DRIFTWOOD)     # top rail
	for x in [0, W / 2, W - 1]:
		g.box(x, 0, 0, x, 11, 0, Palette.DRIFTWOOD)
	for i in range(5, 11):                                # diagonal brace
		g.setv(int((i - 5) * (W - 1) / 6.0), i, 0, Palette.DARK_WOOD)
	g.box(W - 2, 8, 0, W - 1, 9, 0, Palette.METAL)        # latch
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	var mi := MeshInstance3D.new()
	mi.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, U, mat, mat)
	mi.position = Vector3(0, 0, -0.5 * U)
	_leaf.add_child(mi)
	_refresh()


func _refresh() -> void:
	solid = not is_open
	if _leaf != null:
		_leaf.rotation.y = -PI * 0.5 if is_open else 0.0


func get_interaction_prompt(_player: Player) -> String:
	return "F  %s the gate" % ("Close" if is_open else "Open")


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if manager != null:
		manager.request_action(self, &"toggle", {})
	else:
		is_open = not is_open
		_refresh()


func server_action(action: StringName, _args: Dictionary, _peer: int) -> Dictionary:
	if action == &"toggle":
		is_open = not is_open
		_refresh()
		return {"changed": true}
	return {}


func interact(player: Player) -> void:
	super.interact(player)
	is_open = not is_open
	_refresh()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["open"] = is_open
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	is_open = bool(data.get("open", false))
	_refresh()
