class_name ReaverDockEntity
extends WorldEntity
## Reaver Outpost Dock: conquered pirate palisade mooring pier that can be claimed
## by players to spawn a seaworthy pirate outrigger skiff and salvage chests.

var visual_node: Node3D = null
var is_claimed: bool = false
var skiff_spawned: bool = false


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"reaver_dock", "Sea-Reaver Outpost Dock", p_coord)
	entity_type = EntityType.WORKSTATION


func _ready() -> void:
	super._ready()
	_build_visuals()


func _build_visuals() -> void:
	if visual_node != null:
		visual_node.queue_free()
	visual_node = Node3D.new()
	add_child(visual_node)

	# Weathered dark-wood pier with iron rings and skull/crossbones pennant
	var g := Prefabs.Grid.new(12, 6, 16)
	g.box(2, 0, 0, 9, 2, 15, Palette.DARK_WOOD)     # Pier deck
	g.box(1, 0, 1, 2, 4, 2, Palette.TRUNK)           # Mooring bollards
	g.box(9, 0, 1, 10, 4, 2, Palette.TRUNK)
	g.box(1, 0, 14, 2, 4, 15, Palette.TRUNK)
	g.box(9, 0, 14, 10, 4, 15, Palette.TRUNK)
	# Pirate pennant flag
	g.box(5, 3, 14, 6, 5, 14, Palette.METAL)
	g.box(6, 4, 12, 8, 5, 13, Palette.ROOF_RED if not is_claimed else Palette.WHITEWASH)

	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mi.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VoxelWorld.VS, mat, mat)
	mi.position = Vector3(-g.sx * 0.5, 0.0, -g.sz * 0.5) * VoxelWorld.VS
	visual_node.add_child(mi)


func interact_prompt() -> String:
	if not is_claimed:
		return "[E] Claim Reaver Outpost Dock (Capture Pirate Skiff)"
	return "[E] Reaver Dock Mooring (Dock Cleared)"


func interact(player: Node) -> void:
	if not is_claimed:
		is_claimed = true
		_build_visuals() # Refresh flag color
		CombatAudio.play_sound("fanfare", position)
		if player != null and "inventory" in player and player.inventory != null:
			# Grant captured skiff kit and brass guilders
			player.inventory.add_item(&"skiff_kit", 1)
			player.inventory.add_item(&"brass_guilder", 15)
			if "hud" in player and player.hud != null:
				player.hud.show_banner("Reaver Outpost Dock Claimed!", "Seaworthy Skiff Kit and 15 Brass Guilders secured.")
	else:
		if player != null and "hud" in player and player.hud != null:
			player.hud.show_toast("Reaver Dock is secure and ready for vessel mooring.")


func serialize() -> Dictionary:
	var data := super.serialize()
	data["is_claimed"] = is_claimed
	data["skiff_spawned"] = skiff_spawned
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	is_claimed = bool(data.get("is_claimed", false))
	skiff_spawned = bool(data.get("skiff_spawned", false))
	_build_visuals()
