class_name StationEntity
extends WorldEntity
## Physical 3D Crafting, Smelting, Forging, and Culinary Workstation in the world.
## Wraps a CraftingStation and enables station-specific crafting in InventoryUI
## (or direct crafting in headless tests), plus placeable & rechargeable fire mechanics.

signal recipe_crafted(recipe_id: StringName, count: int)

const U := VoxelWorld.VS * 0.5
const INITIAL_CAMPFIRE_FUEL_SEC := 90.0

var station: CraftingStation
var station_tag: StringName = &"workbench"

var _flame_node: Node3D = null
var _fire_light: OmniLight3D = null
var _fire_particles: CPUParticles3D = null
var _flicker_time: float = 0.0


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
	if p_station_tag == &"campfire":
		station.fuel_remaining_sec = INITIAL_CAMPFIRE_FUEL_SEC
	station.craft_completed.connect(_on_dish_done)
	station.station_halted.connect(func(reason: String) -> void:
		if reason.begins_with("Fuel depleted"):
			_notify_nearby("The fire under the %s went out. Add fuel to keep cooking." % entity_name))


# ------------------------------------------------------------------ timed cooking

func is_cooking_station() -> bool:
	return CraftingStation.is_cooking_station(station_tag)


func _local_player() -> Player:
	if manager != null and manager.main != null and manager.main.get("player") != null:
		var p: Player = manager.main.player
		if p != null and is_instance_valid(p):
			return p
	return null


## Toast only when the local player is close enough to care.
func _notify_nearby(msg: String, radius: float = 24.0) -> void:
	var p := _local_player()
	if p != null and p.hud != null and is_inside_tree() and p.global_position.distance_to(global_position) <= radius:
		p.hud.show_toast(msg)


func _on_dish_done(_recipe_id: StringName, _out_id: StringName, _count: int) -> void:
	if manager != null:
		manager.push_state(self)
	if not station.queue.is_empty():
		return   # more in the queue; one message when the whole order is done
	if _cook_claims():
		return   # the village cook's dish: they carry it to the pantry
	var n := station.output_count()
	if n > 0:
		_notify_nearby("Ready at the %s: %s" % [entity_name, tray_text()])
		if is_inside_tree():
			CombatAudio.play_sound("tame_chime", global_position, -6.0)


## The village cook is tending this fire (their dishes go straight to the town's stores).
func _cook_claims() -> bool:
	if manager == null or manager.main == null or manager.main.get("village") == null:
		return false
	var v: SettlementManager = manager.main.village
	return v != null and v.cook_orders.pending.has(CookOrders.key_for(grid_coord))


## "3 Fish Stew, 1 Kelp Tea" for what's sitting in the tray.
func tray_text() -> String:
	var parts: Array[String] = []
	for item_id: StringName in station.output:
		var d: ItemDef = ItemDB.get_item(item_id)
		parts.append("%d %s" % [int(station.output[item_id]), d.name if d != null else String(item_id)])
	return ", ".join(parts)


## Moves finished dishes into the player's bag. Returns how many items were taken.
func collect_output(player: Player) -> int:
	if player == null or player.inventory == null or station.output.is_empty():
		return 0
	var batches_before: Dictionary = station.output_batches.duplicate()
	var taken := station.take_output(player.inventory)
	var total := 0
	var parts: Array[String] = []
	for item_id: StringName in taken:
		var n: int = taken[item_id]
		total += n
		var d: ItemDef = ItemDB.get_item(item_id)
		parts.append("%d %s" % [n, d.name if d != null else String(item_id)])
		# Quest credit once per cook, given when the dish actually reaches the player.
		var cooks: int = int(batches_before.get(item_id, 1))
		if not station.output.has(item_id):
			station.output_batches.erase(item_id)
		else:
			cooks = 0   # partly collected (bag full): credit when the rest is taken
		for i in cooks:
			player.quest_event(QuestDef.ObjectiveType.CRAFT_ITEM, item_id)
	if player.hud != null:
		if total > 0:
			player.hud.show_toast("Collected %s from the %s" % [", ".join(parts), entity_name]
				+ ("  (bag full, the rest is still here)" if not station.output.is_empty() else ""))
		else:
			player.hud.show_toast("Your bag is full.")
	if total > 0 and manager != null:
		manager.push_state(self)
	return total


func is_fire_station() -> bool:
	return station != null and station.requires_fuel


func is_lit() -> bool:
	if station == null:
		return false
	if station.requires_fuel:
		return station.fuel_remaining_sec > 0.0
	return station_tag == &"furnace" or station_tag == &"hearth_pot"


func _get_active_fuel_item(player: Player) -> StringName:
	if player == null or player.inventory == null:
		return &""
	var active_slot := player.inventory.get_active_item()
	if active_slot != null and not active_slot.is_empty():
		if CraftingStation.is_fuel_item(active_slot.item_id):
			return active_slot.item_id
	return &""


func recharge_fire(player: Player) -> bool:
	if player == null or player.inventory == null or station == null:
		return false
	var preferred := _get_active_fuel_item(player)
	var res := station.recharge_from_inventory(player.inventory, preferred)
	if bool(res.get("recharged", false)):
		var iid: StringName = res.get("item_id", &"driftwood")
		var idef: ItemDef = ItemDB.get_item(iid)
		var iname: String = idef.name if idef != null else String(iid)
		var added_sec: float = float(res.get("added_sec", 20.0))
		if player.hud:
			player.hud.show_toast("Recharged %s with %s (+%.0fs)! Burn time: %.0fs" % [
				entity_name, iname, added_sec, station.fuel_remaining_sec
			])
		_update_fire_visuals(0.0)
		if manager != null:
			manager.push_state(self)
		return true
	else:
		if player.hud:
			player.hud.show_toast(String(res.get("reason", "Need wood or driftwood to recharge fire.")))
		return false


func _build_visuals() -> void:
	var g: Prefabs.Grid
	match station_tag:
		&"campfire":
			# Base stone ring + crossed timber logs (unlit when flames are hidden)
			g = Prefabs.Grid.new(8, 5, 8)
			for z in range(1, 7):
				for x in range(1, 7):
					var d := Vector2(x - 3.5, z - 3.5).length()
					if d >= 2.0 and d <= 3.2:
						g.setv(x, 0, z, Palette.COBBLE)
					elif d < 2.0:
						g.setv(x, 0, z, Palette.DARK_WOOD)
			g.box(2, 1, 3, 5, 1, 4, Palette.TRUNK)
			g.box(3, 1, 2, 4, 1, 5, Palette.DRIFTWOOD)
		&"furnace":
			g = Prefabs.Grid.new(9, 11, 9)
			g.box(0, 0, 0, 8, 7, 8, Palette.COBBLE)
			g.box(1, 0, 1, 7, 7, 7, Palette.STONE)
			g.box(2, 8, 2, 6, 10, 6, Palette.COBBLE)
			g.box(3, 1, 7, 5, 4, 8, Palette.BEDROCK)  # Firebox opening
			g.box(3, 1, 6, 5, 3, 7, Palette.LANTERN)  # Glowing coals
		&"anvil":
			g = Prefabs.Grid.new(9, 8, 6)
			g.box(2, 0, 1, 6, 2, 4, Palette.DARK_WOOD) # Timber block base
			g.box(2, 3, 2, 6, 4, 3, Palette.BEDROCK)   # Iron waist
			g.box(0, 5, 1, 8, 7, 4, Palette.METAL)     # Anvil face + horn
		&"hearth_pot":
			g = Prefabs.Grid.new(8, 8, 8)
			g.box(1, 0, 1, 6, 1, 6, Palette.COBBLE)
			g.box(2, 1, 2, 5, 1, 5, Palette.LANTERN)
			g.box(1, 2, 1, 6, 6, 6, Palette.BEDROCK)
			g.box(2, 3, 2, 5, 6, 5, Palette.ROOF_RED)
		&"smokehouse":
			g = Prefabs.Grid.new(9, 14, 9)
			g.box(0, 0, 0, 8, 1, 8, Palette.COBBLE)
			g.box(0, 2, 0, 8, 11, 8, Palette.DARK_WOOD)
			g.box(1, 12, 1, 7, 13, 7, Palette.ROOF_RED)
			g.box(3, 2, 8, 5, 8, 8, Palette.PLANK)
			g.setv(5, 5, 8, Palette.METAL)
		&"saltery":
			g = Prefabs.Grid.new(9, 6, 9)
			g.box(0, 0, 0, 8, 5, 8, Palette.PLANK)
			g.box(1, 2, 1, 7, 5, 7, Palette.WHITEWASH)
			g.box(0, 1, 0, 8, 1, 8, Palette.METAL)
		&"brewery":
			g = Prefabs.Grid.new(8, 9, 8)
			g.box(0, 0, 0, 7, 4, 7, Palette.DARK_WOOD)
			g.box(2, 5, 2, 5, 8, 5, Palette.BUOY)
			g.box(3, 8, 3, 4, 8, 4, Palette.METAL)
		_: # workbench
			g = Prefabs.Grid.new(10, 7, 7)
			# Four sturdy legs
			g.box(0, 0, 0, 1, 5, 1, Palette.DARK_WOOD)
			g.box(8, 0, 0, 9, 5, 1, Palette.DARK_WOOD)
			g.box(0, 0, 5, 1, 5, 6, Palette.DARK_WOOD)
			g.box(8, 0, 5, 9, 5, 6, Palette.DARK_WOOD)
			# Plank tabletop + vice + tool rack
			g.box(0, 5, 0, 9, 6, 6, Palette.PLANK)
			g.box(1, 6, 1, 3, 6, 2, Palette.METAL)
	_mesh_instance = _voxel_model(g)

	if station_tag == &"campfire" or station_tag == &"smokehouse" or station_tag == &"furnace":
		_build_fire_effects()
		_update_fire_visuals(0.0)


func emits_light() -> bool:
	return station_tag in [&"campfire", &"smokehouse", &"furnace", &"hearth_pot"]


func _build_fire_effects() -> void:
	_flame_node = Node3D.new()
	_flame_node.position = Vector3(0.0, 2.0 * U, 0.0)
	add_child(_flame_node)

	if station_tag == &"campfire":
		var fg := Prefabs.Grid.new(4, 4, 4)
		fg.box(1, 0, 1, 2, 1, 2, Palette.LANTERN)
		fg.setv(1, 2, 1, Palette.BUOY)
		fg.setv(2, 2, 2, Palette.LANTERN)
		fg.setv(1, 3, 2, Palette.LANTERN)
		var f_mat := StandardMaterial3D.new()
		f_mat.vertex_color_use_as_albedo = true
		f_mat.vertex_color_is_srgb = true
		f_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var flame_mesh := MeshInstance3D.new()
		flame_mesh.mesh = Mesher.mesh_from_grid(fg.data, fg.sx, fg.sy, fg.sz, U, f_mat, f_mat)
		flame_mesh.position = Vector3(-fg.sx * 0.5 * U, 0.0, -fg.sz * 0.5 * U)
		flame_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame_node.add_child(flame_mesh)

	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.60, 0.22)
	_fire_light.light_energy = 1.65 if station_tag == &"campfire" else 1.15
	_fire_light.omni_range = 7.5 if station_tag == &"campfire" else 5.0
	_fire_light.position = Vector3(0.0, 0.35, 0.0)
	_flame_node.add_child(_fire_light)

	_fire_particles = CPUParticles3D.new()
	_fire_particles.amount = 14
	_fire_particles.lifetime = 1.1
	_fire_particles.position = Vector3(0.0, 0.18, 0.0)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.05, 0.05, 0.05)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.68, 0.22)
	spark_mesh.material = spark_mat
	_fire_particles.mesh = spark_mesh
	_fire_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_fire_particles.emission_sphere_radius = 0.14
	_fire_particles.direction = Vector3(0.0, 1.0, 0.0)
	_fire_particles.spread = 22.0
	_fire_particles.gravity = Vector3(0.0, 0.65, 0.0)
	_fire_particles.initial_velocity_min = 0.35
	_fire_particles.initial_velocity_max = 0.85
	_fire_particles.scale_amount_min = 0.5
	_fire_particles.scale_amount_max = 1.1
	_flame_node.add_child(_fire_particles)


func _update_fire_visuals(delta: float) -> void:
	if _flame_node == null:
		return
	var lit := is_lit()
	_flame_node.visible = lit
	if _fire_light != null:
		_fire_light.visible = lit
	if _fire_particles != null and _fire_particles.emitting != lit:
		_fire_particles.emitting = lit
	if not lit:
		return

	_flicker_time += delta * 9.5
	var fuel_factor := 1.0
	if station.requires_fuel:
		fuel_factor = clampf(station.fuel_remaining_sec / 25.0, 0.35, 1.0)
	var pulse := 1.0 + 0.12 * sin(_flicker_time) + 0.07 * cos(_flicker_time * 2.3)
	_flame_node.scale = Vector3(
		lerpf(0.75, 1.0, fuel_factor) * (0.95 + 0.08 * sin(_flicker_time * 1.7)),
		lerpf(0.55, 1.0, fuel_factor) * pulse,
		lerpf(0.75, 1.0, fuel_factor) * (0.95 + 0.08 * cos(_flicker_time * 1.4))
	)
	if _fire_light != null:
		var base_e := 1.65 if station_tag == &"campfire" else 1.15
		_fire_light.light_energy = base_e * fuel_factor * pulse


## What's on the fire, for the end of the prompt ("" when idle).
func cooking_text() -> String:
	if not station.is_active or station.active_recipe == null:
		return ""
	var t := "cooking %s" % station.active_recipe.name
	if station.is_paused():
		t += ", fire is out"
	else:
		t += ", %ds" % int(ceil(station.seconds_left()))
	if not station.queue.is_empty():
		t += " (+%d queued)" % station.queue.size()
	return t


func get_interaction_prompt(player: Player) -> String:
	if not station.output.is_empty():
		return "F  Collect %s" % tray_text()
	var base := _base_prompt(player)
	var cooking := cooking_text()
	return base if cooking == "" else "%s  ·  %s" % [base, cooking]


func _base_prompt(player: Player) -> String:
	if station.requires_fuel:
		var held_fuel := _get_active_fuel_item(player)
		var fuel_sec := int(ceil(station.fuel_remaining_sec))
		if station.fuel_remaining_sec <= 0.0:
			return "F  Light / Recharge %s (Fire Out — Add Wood)  |  Shift+F  Cook UI" % entity_name
		elif held_fuel != &"":
			var fdef := ItemDB.get_item(held_fuel)
			var fname := fdef.name if fdef != null else String(held_fuel)
			return "F  Recharge %s (+%s) [%ds left]  |  Shift+F  Cook UI" % [entity_name, fname, fuel_sec]
		else:
			return "F  Use %s (Lit: %ds fuel — Shift+F or Hold Wood to Recharge)" % [entity_name, fuel_sec]

	if player != null and player.crafting_ui != null:
		var known := 0
		for r: RecipeDef in RecipeDB.get_station_exclusive_recipes(station_tag):
			if player.recipes == null or player.recipes.knows(r.id):
				known += 1
		return "F  Use %s (%d recipe%s known)" % [entity_name, known, "" if known == 1 else "s"]

	for r: RecipeDef in RecipeDB.get_craftable_recipes(player.inventory, station_tag):
		if player.recipes == null or player.recipes.knows(r.id):
			return "F  Use %s: Craft %s" % [entity_name, r.name]
	var known: int = player.recipes.recipes_for(station_tag).known.size() if player.recipes != null else 0
	return "F  Use %s  (%d recipe%s known)" % [entity_name, known, "" if known == 1 else "s"]


func client_interact(player: Player) -> void:
	# Finished dishes first: one press of F empties the tray into your bag.
	if player != null and not station.output.is_empty():
		collect_output(player)
		return
	if player != null and station.requires_fuel:
		var held_fuel := _get_active_fuel_item(player)
		var shift_held := Input.is_key_pressed(KEY_SHIFT)
		if station.fuel_remaining_sec <= 0.0 and not shift_held:
			if recharge_fire(player):
				return
			# If player has no fuel in inventory, fall through and open station UI so they can see the fuel panel
		elif held_fuel != &"" and not shift_held:
			recharge_fire(player)
			return
		elif shift_held and station.fuel_remaining_sec > 0.0:
			recharge_fire(player)
			return

	if player != null and player.crafting_ui != null:
		player.crafting_ui.open(self)
		return
	super.client_interact(player)


func interact(player: Player) -> void:
	super.interact(player)
	if not station.output.is_empty():
		collect_output(player)
		return
	if station.queue_full():
		return

	if station.requires_fuel and station.fuel_remaining_sec <= 0.0:
		if recharge_fire(player):
			return
		return

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
			if CraftingStation.is_timed(recipe):
				player.hud.show_toast("Started cooking %s (%.0fs)..." % [recipe.name, recipe.craft_time_sec])
			else:
				player.hud.show_toast("Crafted %s at %s!" % [recipe.name, entity_name])


func tick(delta: float) -> void:
	if station.is_active:
		station.tick(delta, null)   # finished dishes wait in the tray
	elif station_tag == &"campfire" and station.fuel_remaining_sec > 0.0:
		station.fuel_remaining_sec = maxf(0.0, station.fuel_remaining_sec - delta)
		if station.fuel_remaining_sec <= 0.0:
			station.fuel_updated.emit(0.0)

	_update_fire_visuals(delta)
	_update_steam()

	# Grant warmth / rested stamina regeneration when standing near a lit campfire
	if station_tag == &"campfire" and is_lit() and is_inside_tree():
		if manager != null and manager.main != null and manager.main.get("player") != null:
			var p: Player = manager.main.player
			if p != null and is_instance_valid(p) and p.vitality != null:
				if p.global_position.distance_to(global_position) <= 4.5:
					p.vitality.is_rested = true


func serialize() -> Dictionary:
	var d := super.serialize()
	d["station_tag"] = String(station_tag)
	d["fuel_remaining"] = station.fuel_remaining_sec
	d["is_active"] = station.is_active
	d["recipe_id"] = String(station.active_recipe.id) if station.active_recipe != null else ""
	d["cook_timer"] = station.cook_timer
	d["total_cook_time"] = station.total_cook_time
	d["cooking"] = station.serialize_cooking()
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
	if station.is_active and station.active_recipe == null:
		station.is_active = false   # recipe no longer exists
	station.deserialize_cooking(data.get("cooking", {}))
	_update_fire_visuals(0.0)


# ------------------------------------------------------------------ steam

var _steam: CPUParticles3D = null


## A wisp of steam / smoke above any cooking station while a dish is on.
func _update_steam() -> void:
	if not is_cooking_station() or not is_inside_tree():
		return
	var on := station.is_active and not station.is_paused()
	if _steam == null:
		if not on:
			return
		_steam = CPUParticles3D.new()
		_steam.amount = 10
		_steam.lifetime = 2.2
		var top := 14.0 if station_tag == &"smokehouse" else (9.0 if station_tag == &"brewery" else 7.0)
		_steam.position = Vector3(0.0, top * U, 0.0)
		var m := SphereMesh.new()
		m.radius = 0.06
		m.height = 0.12
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.85, 0.85, 0.82, 0.45) if station_tag != &"smokehouse" else Color(0.45, 0.43, 0.40, 0.5)
		m.material = mat
		_steam.mesh = m
		_steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_steam.emission_sphere_radius = 0.1
		_steam.direction = Vector3.UP
		_steam.spread = 12.0
		_steam.gravity = Vector3(0.05, 0.25, 0.0)
		_steam.initial_velocity_min = 0.15
		_steam.initial_velocity_max = 0.35
		_steam.scale_amount_min = 0.8
		_steam.scale_amount_max = 1.8
		add_child(_steam)
	if _steam.emitting != on:
		_steam.emitting = on
