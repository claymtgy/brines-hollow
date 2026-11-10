class_name BanquetTableEntity
extends WorldEntity
## Communal Banquet Table: large harvest table for village gatherings, festivals, and feasts.
## Players and villagers contribute hearty culinary dishes; when filled with 3+ dishes, a grand
## feast can be celebrated, granting the "Banquet Rested" blessing and village morale.

const U := VoxelWorld.VS * 0.5
const MAX_DISHES := 6

var dishes: Array[StringName] = []
var _dishes_group: Node3D


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"banquet_table", "Communal Banquet Table", p_coord)
	entity_type = EntityType.WORKSTATION
	item_id = &"banquet_table"
	size = Vector3(14, 5, 8) * U


func _build_visuals() -> void:
	var root := Node3D.new()
	var g := Prefabs.Grid.new(14, 5, 8)

	# 4 Heavy wooden table legs
	g.box(1, 0, 1, 2, 3, 2, Palette.DARK_WOOD)
	g.box(11, 0, 1, 12, 3, 2, Palette.DARK_WOOD)
	g.box(1, 0, 5, 2, 3, 6, Palette.DARK_WOOD)
	g.box(11, 0, 5, 12, 3, 6, Palette.DARK_WOOD)

	# Thick plank tabletop
	g.box(0, 3, 0, 13, 3, 7, Palette.PLANK)

	# Scarlet festival runner down the center
	g.box(1, 4, 2, 12, 4, 5, Palette.ROOF_RED)

	# Side benches
	g.box(0, 1, 0, 13, 1, 0, Palette.PLANK)
	g.box(0, 1, 7, 13, 1, 7, Palette.PLANK)

	var mi := _voxel_model(g)
	mi.position = Vector3(-7, 0, -4) * U
	root.add_child(mi)

	_dishes_group = Node3D.new()
	_dishes_group.name = "Dishes"
	root.add_child(_dishes_group)

	_mesh_instance = root
	_update_dish_visuals()


func _update_dish_visuals() -> void:
	if _dishes_group == null:
		return
	for ch in _dishes_group.get_children():
		ch.queue_free()

	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.85, 0.82, 0.75) # ceramic cream

	var food_mat := StandardMaterial3D.new()
	food_mat.albedo_color = Color(0.8, 0.45, 0.2) # roast golden amber

	for i in dishes.size():
		var plate := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.12
		cyl.bottom_radius = 0.10
		cyl.height = 0.04
		plate.mesh = cyl
		plate.material_override = plate_mat

		var offset_x := -0.6 + float(i) * 0.25
		plate.position = Vector3(offset_x, 4 * U + 0.02, 0.0)

		var morsel := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.07
		sph.height = 0.08
		morsel.mesh = sph
		morsel.material_override = food_mat
		morsel.position.y = 0.04
		plate.add_child(morsel)

		_dishes_group.add_child(plate)


func get_interaction_prompt(player: Player) -> String:
	if player == null:
		return "Communal Banquet Table"

	# If holding food and table not full:
	var held_id: StringName = player.inventory.selected_item_id()
	var idef := ItemDB.get_item(held_id)
	if idef != null and idef.category == ItemDef.Category.FOOD and dishes.size() < MAX_DISHES:
		return "Communal Banquet Table (%d/%d dishes)  ·  F: Contribute %s" % [dishes.size(), MAX_DISHES, idef.name]

	if dishes.size() >= 3:
		return "Communal Banquet Table (%d dishes)  ·  F: Partake in Grand Feast!" % dishes.size()

	return "Communal Banquet Table (%d/%d dishes)  ·  Hold culinary dish to contribute" % [dishes.size(), MAX_DISHES]


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if player == null:
		return

	var held_id: StringName = player.inventory.selected_item_id()
	var idef := ItemDB.get_item(held_id)

	# Contribute food if player is holding food and table isn't full
	if idef != null and idef.category == ItemDef.Category.FOOD and dishes.size() < MAX_DISHES:
		player.inventory.remove_item(held_id, 1)
		dishes.append(held_id)
		CombatAudio.play_sound("pickup", position)
		_update_dish_visuals()
		if player.hud != null:
			player.hud.show_toast("Contributed %s to the banquet table! (%d/%d)" % [idef.name, dishes.size(), MAX_DISHES])
		return

	# If table has 3+ dishes, feast!
	if dishes.size() >= 3:
		_partake_feast(player)
	else:
		if player.hud != null:
			player.hud.show_toast("The feast needs at least 3 culinary dishes to begin!")


func _partake_feast(player: Player) -> void:
	CombatAudio.play_sound("fanfare", position)

	# Grant Banquet Rested buff to player
	if player.vitality != null:
		player.vitality.current_hp = player.vitality.get_max_hp() + 50.0
		player.vitality.current_stamina = player.vitality.get_max_stamina() + 50.0

	# Village morale boost
	var em := EntityManager.current
	if em != null and em.main != null and em.main.get("village") != null:
		var v = em.main.village
		if v.has_method("add_morale"):
			v.add_morale(25.0)

	dishes.clear()
	_update_dish_visuals()

	if player.hud != null:
		player.hud.show_banner("COMMUNAL FEAST CELEBRATED!", "The village rejoices! Granted 'Banquet Rested' (+50 Max HP & Stamina).")


func serialize() -> Dictionary:
	var d := super.serialize()
	var arr: Array = []
	for dish in dishes:
		arr.append(String(dish))
	d["dishes"] = arr
	return d


func deserialize(d: Dictionary) -> void:
	super.deserialize(d)
	dishes.clear()
	if d.has("dishes") and d["dishes"] is Array:
		for s in d["dishes"]:
			dishes.append(StringName(s))
	_update_dish_visuals()
