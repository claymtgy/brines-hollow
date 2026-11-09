class_name WarHornEntity
extends WorldEntity
## The War Horn Totem at the heart of a Sea-Reaver outpost: a tarred mast hung with skulls of
## driftwood and a great curled horn. While it stands, the outpost's garrison keeps coming
## back. Beat the guards and topple it (F): the outpost is captured for good and a bunk is
## laid in the big tent, so you can sleep there and wake at your new forward base.

const U := VoxelWorld.VS * 0.5

var outpost := -1
var toppled := false


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"war_horn_totem", "War Horn Totem", p_coord)
	size = Vector3(8, 34, 8) * U
	entity_type = EntityType.TRAP
	state_changed.connect(_rebuild)


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(10, 36, 10)
	if toppled:
		# down in the dirt, with a blue rag of a flag stuck where it stood
		g.box(1, 0, 4, 8, 1, 5, Palette.DARK_WOOD)
		g.box(7, 1, 3, 9, 3, 6, Palette.SANDSTONE_C)
		g.box(4, 0, 4, 4, 18, 4, Palette.TRUNK)
		g.box(5, 12, 4, 8, 17, 4, Palette.ROOF_BLUE)
	else:
		g.box(4, 0, 4, 5, 30, 5, Palette.DARK_WOOD)
		for y in [8, 16, 24]:
			g.box(3, y, 3, 6, y, 6, Palette.TRUNK)
		# the horn: a great curled shell on its cradle
		for k in 9:
			var a := k * 0.45
			var x := 5 + roundi(cos(a) * (4 - k * 0.3))
			var y := 26 + roundi(sin(a) * 3.0)
			g.box(x - 1, y, 3, x, y + 1, 6, Palette.SANDSTONE_C if k % 2 == 0 else Palette.BUOY)
		g.box(2, 31, 4, 7, 31, 5, Palette.ROOF_RED)            # a torn red pennant
		g.setv(1, 30, 4, Palette.ROOF_RED)
		# driftwood "skulls" and a shell necklace
		for y in [12, 20]:
			g.box(3, y, 6, 6, y + 2, 7, Palette.WHITEWASH)
			g.setv(4, y + 1, 7, Palette.EYE)
			g.setv(5, y + 1, 7, Palette.EYE)
	_mesh_instance = _voxel_model(g)
	_mesh_instance.position = Vector3(-5, 0, -5) * U


func _rebuild() -> void:
	if _mesh_instance != null:
		_mesh_instance.queue_free()
		_mesh_instance = null
	_build_visuals()


func get_interaction_prompt(_player: Player) -> String:
	if toppled:
		return "War Horn Totem (toppled): this outpost is yours"
	return "F  Topple the War Horn Totem"


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if toppled:
		if player.hud:
			player.hud.show_toast(get_interaction_prompt(player))
		return
	manager.request_action(self, &"topple", {})


func server_action(action: StringName, _args: Dictionary, _peer: int) -> Dictionary:
	if action != &"topple" or toppled:
		return {}
	var ro := ReaverOutposts.current
	if ro == null:
		return {}
	if outpost < 0:
		outpost = ro.index_near(grid_coord)
	var why := ro.try_capture(outpost)
	if why != "":
		return {"toast": why}
	toppled = true
	_rebuild()
	# the forward base: a bunk in the big tent
	if manager != null and manager.has_method("_place_at") and outpost >= 0 and outpost < ro.outposts.size():
		var bunk: Vector3i = ro.outposts[outpost].bunk
		manager.call_deferred("_place_at", &"fisher_bed", bunk, 0, 4)
	return {"changed": true, "toast": "You topple the War Horn. The outpost is yours: a forward base."}


func serialize() -> Dictionary:
	var d := super.serialize()
	d["outpost"] = outpost
	d["toppled"] = toppled
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	outpost = int(data.get("outpost", -1))
	toppled = bool(data.get("toppled", false))
	if _mesh_instance != null:
		_rebuild()
