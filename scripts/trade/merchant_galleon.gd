class_name MerchantGalleon
extends Node3D
## Visiting High-Seas Merchant Galleon: majestic three-masted trading ship.
## Anchors offshore or beside deep-water piers to buy municipal export goods and sell foreign luxury wares.

const U := VoxelWorld.VS * 0.5

var merchant: MerchantBoat
var visual: Node3D
var _t: float = 0.0
var _hull_mat: StandardMaterial3D
var _sail_mat: StandardMaterial3D


func _init() -> void:
	merchant = MerchantBoat.new("The Sovereign's Pride", MerchantBoat.MerchantType.TRADE_GALLEON)
	_build_visuals()


func _build_visuals() -> void:
	visual = Node3D.new()
	add_child(visual)

	var g := Prefabs.Grid.new(16, 12, 36)

	# Deep displacement galleon hull (stepped keel, broad midships, high stern castle)
	g.box(4, 0, 4, 11, 2, 32, Palette.DARK_WOOD) # keel
	g.box(2, 2, 2, 13, 5, 34, Palette.PLANK)     # lower hull
	g.box(1, 5, 0, 14, 7, 35, Palette.PLANK)     # upper gunwales

	# Raised forecastle deck (bow)
	g.box(2, 7, 28, 13, 9, 34, Palette.PLANK)

	# Towering multi-deck stern castle (aft)
	g.box(2, 7, 2, 13, 10, 12, Palette.PLANK)
	g.box(3, 10, 2, 12, 11, 8, Palette.DARK_WOOD) # captain's poop deck

	# Stern gallery lantern windows
	g.box(4, 8, 1, 11, 9, 1, Palette.LANTERN)

	# Foremast (z=26), Mainmast (z=18), Mizzenmast (z=8)
	g.box(7, 7, 26, 8, 22, 26, Palette.TRUNK)
	g.box(7, 7, 18, 8, 25, 18, Palette.TRUNK)
	g.box(7, 10, 8, 8, 20, 8, Palette.TRUNK)

	# Crow's nests
	g.box(6, 18, 25, 9, 19, 27, Palette.DARK_WOOD)
	g.box(6, 21, 17, 9, 22, 19, Palette.DARK_WOOD)

	# Square yards and billowing sails
	g.box(2, 14, 26, 13, 17, 26, Palette.WHITEWASH) # fore course
	g.box(1, 15, 18, 14, 19, 18, Palette.WHITEWASH) # main course
	g.box(3, 13, 8, 12, 16, 8, Palette.WHITEWASH)   # mizzen course

	var mi := _voxel_model(g)
	mi.position = Vector3(-8, -2, -18) * U
	visual.add_child(mi)


func _voxel_model(g: Prefabs.Grid) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	var mi := MeshInstance3D.new()
	mi.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, U, mat, mat)
	return mi


func _process(dt: float) -> void:
	_t += dt
	# Gentle deep-keel harbor roll and pitch
	if visual != null:
		visual.position.y = sin(_t * 0.8) * 0.08
		visual.rotation.z = sin(_t * 0.6) * 0.02
		visual.rotation.x = cos(_t * 0.5) * 0.015


func get_interaction_prompt(_player: Player) -> String:
	return "The Sovereign's Pride · Visiting Merchant Galleon  ·  F: Board & Trade"


func client_interact(player: Player) -> void:
	if player == null:
		return
	CombatAudio.play_sound("pickup", global_position)
	var em := EntityManager.current
	if em != null and em.main != null and em.main.get("trade") != null:
		var trade_mgr = em.main.trade
		if trade_mgr.has_method("open_with_merchant"):
			trade_mgr.open_with_merchant(merchant)
		elif trade_mgr.get("ui") != null:
			trade_mgr.merchant = merchant
			trade_mgr.ui.open()
	elif player.hud != null and player.hud.has_method("show_toast"):
		player.hud.show_toast("Visiting Galleon: Ready for trade contracts.")
