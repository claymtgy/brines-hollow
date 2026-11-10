class_name NoticeBoardEntity
extends WorldEntity
## A town notice board where villagers post daily chore requests and community bulletins.
## Completing chore requests rewards players with Brass Guilders and boosts village morale.

signal chore_completed(chore_id: StringName, reward_brass: int)
signal chores_refreshed

const U := VoxelWorld.VS * 0.5

class Chore:
	var id: StringName = &""
	var villager_name: String = ""
	var title: String = ""
	var description: String = ""
	var item_requested: StringName = &""
	var count_requested: int = 1
	var reward_brass: int = 10
	var reward_morale: float = 0.05
	var completed: bool = false

	func _init(p_id: StringName = &"", p_villager: String = "", p_title: String = "", p_item: StringName = &"", p_count: int = 1, p_reward: int = 10) -> void:
		id = p_id
		villager_name = p_villager
		title = p_title
		item_requested = p_item
		count_requested = p_count
		reward_brass = p_reward

	func serialize() -> Dictionary:
		return {
			"id": String(id),
			"villager_name": villager_name,
			"title": title,
			"description": description,
			"item_requested": String(item_requested),
			"count_requested": count_requested,
			"reward_brass": reward_brass,
			"reward_morale": reward_morale,
			"completed": completed
		}

	static func deserialize(d: Dictionary) -> Chore:
		var c := Chore.new(
			StringName(d.get("id", "")),
			d.get("villager_name", "Villager"),
			d.get("title", "Community Chore"),
			StringName(d.get("item_requested", "")),
			int(d.get("count_requested", 1)),
			int(d.get("reward_brass", 10))
		)
		c.description = d.get("description", "")
		c.reward_morale = float(d.get("reward_morale", 0.05))
		c.completed = bool(d.get("completed", false))
		return c


var active_chores: Array[Chore] = []
var day_last_refreshed: int = -1


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"notice_board", "Town Notice Board", p_coord)
	entity_type = EntityType.WORKSTATION
	size = Vector3(8, 9, 2) * U
	solid = true
	generate_default_chores()


func generate_default_chores() -> void:
	active_chores.clear()
	add_chore(Chore.new(&"chore_mara_fish", "Mara the Fisher", "Low-Tide Mackerel Supply", &"silver_mackerel", 3, 15))
	add_chore(Chore.new(&"chore_tobin_timber", "Tobin the Carpenter", "Driftwood Shoring", &"driftwood", 5, 20))
	add_chore(Chore.new(&"chore_barnaby_herbs", "Barnaby the Cook", "Sea Greens for the Pot", &"samphire", 4, 14))


func add_chore(chore: Chore) -> void:
	for c in active_chores:
		if c.id == chore.id:
			return
	active_chores.append(chore)
	state_changed.emit()


func get_active_chore_count() -> int:
	var count := 0
	for c in active_chores:
		if not c.completed:
			count += 1
	return count


## Refreshes chores based on the town's recruited villagers
func refresh_chores(drifters: Array[DrifterDef]) -> void:
	active_chores.clear()
	for d in drifters:
		match d.profession:
			DrifterDef.Profession.FISHER:
				add_chore(Chore.new(
					StringName("chore_%s_fish" % d.name.to_lower()),
					d.name,
					"Morning Catch for the Smoker",
					&"silver_mackerel",
					2,
					12
				))
			DrifterDef.Profession.FARMER:
				add_chore(Chore.new(
					StringName("chore_%s_crops" % d.name.to_lower()),
					d.name,
					"Harvest Grain Delivery",
					&"shore_wheat",
					4,
					16
				))
			DrifterDef.Profession.CARPENTER:
				add_chore(Chore.new(
					StringName("chore_%s_wood" % d.name.to_lower()),
					d.name,
					"Timber for Village Repairs",
					&"wood_plank",
					6,
					18
				))
			DrifterDef.Profession.BUILDER:
				add_chore(Chore.new(
					StringName("chore_%s_masonry" % d.name.to_lower()),
					d.name,
					"Foundation Cobblestone",
					&"cobblestone",
					8,
					22
				))
			DrifterDef.Profession.RANCHER:
				add_chore(Chore.new(
					StringName("chore_%s_wool" % d.name.to_lower()),
					d.name,
					"Sheared Wool Bundle",
					&"sea_wool",
					2,
					15
				))
	if active_chores.is_empty():
		generate_default_chores()
	chores_refreshed.emit()
	state_changed.emit()


## Tries to complete a chore by ID using player inventory items.
## Grants Brass Guilders and triggers completion signal.
func complete_chore(chore_id: StringName, player: Player) -> bool:
	for chore in active_chores:
		if chore.id == chore_id and not chore.completed:
			if player.inventory != null and player.inventory.has_item(chore.item_requested, chore.count_requested):
				player.inventory.remove_item(chore.item_requested, chore.count_requested)
				player.inventory.add_item(&"brass_guilder", chore.reward_brass)
				chore.completed = true
				chore_completed.emit(chore_id, chore.reward_brass)
				state_changed.emit()
				return true
	return false


func _build_visuals() -> void:
	# Heavy timber posts with cross-boards and pinned parchment notes
	var g := Prefabs.Grid.new(8, 9, 2)
	# Twin timber support posts
	g.box(0, 0, 0, 1, 8, 1, Palette.DARK_WOOD)
	g.box(6, 0, 0, 7, 8, 1, Palette.DARK_WOOD)
	# Upper and lower framing rails
	g.box(1, 7, 0, 6, 8, 1, Palette.DARK_WOOD)
	g.box(1, 2, 0, 6, 2, 0, Palette.DARK_WOOD)
	# Weathered backboard
	g.box(1, 3, 0, 6, 6, 0, Palette.PLANK)
	# Pinned parchment chore notices
	g.box(2, 4, 1, 3, 5, 1, Palette.WHITEWASH)
	g.box(4, 4, 1, 5, 6, 1, Palette.WHITEWASH)
	g.setv(2, 6, 1, Palette.METAL) # Brass tack
	g.setv(5, 7, 1, Palette.METAL)
	_mesh_instance = _voxel_model(g)


func get_interaction_prompt(player: Player) -> String:
	var pending := get_active_chore_count()
	var turn_in := ""
	if player.inventory != null:
		for c in active_chores:
			if not c.completed and player.inventory.has_item(c.item_requested, c.count_requested):
				turn_in = "    F Turn in %s (%s)" % [c.title, c.item_requested]
				break
	return "F Read Notice Board · %d Active Notices%s" % [pending, turn_in]


func client_interact(player: Player) -> void:
	interacted.emit(player)
	# Automatically turn in the first fulfillable chore
	for chore in active_chores:
		if not chore.completed:
			if complete_chore(chore.id, player):
				return


func serialize() -> Dictionary:
	var ch_data := []
	for c in active_chores:
		ch_data.append(c.serialize())
	return {
		"day_last_refreshed": day_last_refreshed,
		"chores": ch_data
	}


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	day_last_refreshed = int(data.get("day_last_refreshed", -1))
	active_chores.clear()
	if data.has("chores"):
		for ch_dict in data["chores"]:
			active_chores.append(Chore.deserialize(ch_dict))
	if active_chores.is_empty():
		generate_default_chores()
