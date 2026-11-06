class_name StationEntity
extends WorldEntity
## Physical 3D Crafting and Culinary Workstation in the world.
## Wraps a CraftingStation and enables proximity crafting, cooking, and fuel replenishment.

signal recipe_crafted(recipe_id: StringName, count: int)

var station: CraftingStation
var station_tag: StringName = &"workbench"


func _init(
	p_station_tag: StringName = &"workbench",
	p_name: String = "Workstation",
	p_coord: Vector3i = Vector3i.ZERO
) -> void:
	super._init(p_station_tag, p_name, p_coord)
	entity_type = EntityType.WORKSTATION
	station_tag = p_station_tag
	var req_fuel: bool = (p_station_tag == &"smokehouse" or p_station_tag == &"campfire")
	station = CraftingStation.new(station_tag, p_name, req_fuel)


func _build_visuals() -> void:
	_mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	var mat := StandardMaterial3D.new()

	match station_tag:
		&"campfire":
			box.size = Vector3(0.65, 0.35, 0.65)
			mat.albedo_color = Color(0.85, 0.45, 0.18) # Fiery orange/ember
		&"hearth_pot":
			box.size = Vector3(0.70, 0.55, 0.70)
			mat.albedo_color = Color(0.22, 0.22, 0.25) # Cast iron pot
		&"smokehouse":
			box.size = Vector3(0.85, 1.40, 0.85)
			mat.albedo_color = Color(0.38, 0.26, 0.16) # Smoked dark timber
		&"saltery":
			box.size = Vector3(0.80, 0.60, 0.80)
			mat.albedo_color = Color(0.78, 0.82, 0.85) # Salt-encrusted brine tub
		&"brewery":
			box.size = Vector3(0.65, 0.75, 0.65)
			mat.albedo_color = Color(0.65, 0.45, 0.28) # Copper kettle / wood
		_:
			box.size = Vector3(0.80, 0.65, 0.80)
			mat.albedo_color = Color(0.55, 0.40, 0.25) # Carpentry timber

	_mesh_instance.mesh = box
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func get_interaction_prompt(player: Player) -> String:
	if station.is_active and station.active_recipe != null:
		var sec_rem: int = int(ceil(maxf(0.0, station.total_cook_time - station.cook_timer)))
		return "E/F  %s: Cooking %s (%ds left)" % [entity_name, station.active_recipe.name, sec_rem]

	var craftable: Array[RecipeDef] = RecipeDB.get_craftable_recipes(player.inventory, station_tag)
	if craftable.is_empty():
		return "F  Inspect %s (Missing ingredients)" % entity_name
	var first_recipe: RecipeDef = craftable[0]
	return "F  Use %s: Craft %s" % [entity_name, first_recipe.name]


func interact(player: Player) -> void:
	super.interact(player)
	if station.is_active:
		# Station is currently processing
		return

	# If station requires fuel and is completely unfueled, prioritize refueling
	if station.requires_fuel and station.fuel_remaining_sec <= 0.0:
		var fueled_count: int = 0
		for fuel_type: StringName in CraftingStation.FUEL_BURN_TIMES.keys():
			if player.inventory.has_item(fuel_type, 1):
				fueled_count = station.add_fuel_from_inventory(player.inventory, fuel_type, 1)
				if fueled_count > 0:
					break
		if fueled_count > 0:
			if player.hud:
				player.hud.show_toast("Added fuel to %s! Burn time: %.0fs" % [entity_name, station.fuel_remaining_sec])
			return
		else:
			if player.hud:
				player.hud.show_toast("%s needs driftwood or wood planks for fuel." % entity_name)
			return

	# Find first craftable recipe with player's inventory
	var craftable: Array[RecipeDef] = RecipeDB.get_craftable_recipes(player.inventory, station_tag)
	if craftable.is_empty():
		if player.hud:
			player.hud.show_toast("No ingredients to craft at %s." % entity_name)
		return

	var recipe: RecipeDef = craftable[0]
	var success := station.craft_recipe(recipe.id, player.inventory)
	if success:
		recipe_crafted.emit(recipe.id, 1)
		if player.hud:
			if recipe.craft_time_sec > 0.0:
				player.hud.show_toast("Started cooking %s (%.0fs)..." % [recipe.name, recipe.craft_time_sec])
			else:
				player.hud.show_toast("Crafted %s at %s!" % [recipe.name, entity_name])


func tick(delta: float) -> void:
	if station.is_active:
		station.tick(delta, null)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["station_tag"] = String(station_tag)
	d["fuel_remaining"] = station.fuel_remaining_sec
	d["is_active"] = station.is_active
	d["recipe_id"] = String(station.active_recipe.id) if station.active_recipe != null else ""
	d["cook_timer"] = station.cook_timer
	d["total_cook_time"] = station.total_cook_time
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	station_tag = StringName(data.get("station_tag", "workbench"))
	station.station_id = station_tag
	station.requires_fuel = (station_tag == &"smokehouse" or station_tag == &"campfire")
	station.fuel_remaining_sec = float(data.get("fuel_remaining", 0.0))
	station.is_active = bool(data.get("is_active", false))
	var rec_id := StringName(data.get("recipe_id", ""))
	if RecipeDB.has_recipe(rec_id):
		station.active_recipe = RecipeDB.get_recipe(rec_id)
	station.cook_timer = float(data.get("cook_timer", 0.0))
	station.total_cook_time = float(data.get("total_cook_time", 0.0))
