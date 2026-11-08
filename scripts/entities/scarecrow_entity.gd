class_name ScarecrowEntity
extends WorldEntity
## Driftwood scarecrow in an old oilskin. Birds keep clear of it: sea eagles won't swoop on
## animals within RADIUS, and gulls won't dive for fish there. It sways in the wind.

const U := VoxelWorld.VS * 0.5
const RADIUS := 14.0

var _rig: Node3D
var _phase := 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"scarecrow", "Oilskin Scarecrow", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"scarecrow"
	size = Vector3(4, 22, 4) * U


func _build_visuals() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	var g := Prefabs.Grid.new(13, 22, 3)
	g.box(6, 0, 1, 6, 17, 1, Palette.DRIFTWOOD)       # post
	g.box(0, 14, 1, 12, 14, 1, Palette.DRIFTWOOD)     # cross-arm
	g.box(4, 8, 0, 8, 15, 2, Palette.COAT_A)          # oilskin coat
	g.box(1, 13, 0, 3, 15, 2, Palette.COAT_A)         # sleeves
	g.box(9, 13, 0, 11, 15, 2, Palette.COAT_A)
	g.box(0, 13, 1, 0, 14, 1, Palette.GRASS_DRY)      # straw hands
	g.box(12, 13, 1, 12, 14, 1, Palette.GRASS_DRY)
	g.box(5, 16, 0, 7, 18, 2, Palette.GRASS_DRY)      # sack-and-straw head
	g.setv(5, 17, 2, Palette.EYE)
	g.setv(7, 17, 2, Palette.EYE)
	g.box(4, 19, 0, 8, 19, 2, Palette.HAT_A)          # sou'wester
	g.box(5, 20, 0, 7, 21, 2, Palette.HAT_A)
	g.box(4, 7, 0, 8, 7, 2, Palette.GRASS_DRY)        # straw fringe
	_mesh_instance = _voxel_model(g)
	_mesh_instance.reparent(_rig, false)


func _process(dt: float) -> void:
	if _rig == null:
		return
	_phase += dt
	_rig.rotation.z = sin(_phase * 1.3) * 0.04
	_rig.rotation.x = sin(_phase * 0.9 + 1.0) * 0.025


func get_interaction_prompt(_player: Player) -> String:
	return "Oilskin Scarecrow (sea eagles and gulls keep clear within %d m)  ·  hold F to pick up" % int(RADIUS)


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if player != null and player.hud != null:
		player.hud.show_toast("The scarecrow's coat flaps. No bird will come near.")
