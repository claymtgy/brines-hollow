class_name TroughEntity
extends WorldEntity
## Livestock Feeding and Watering Trough.
## Provides feed (wheat, kale, samphire, kelp) and water for livestock (Salt-Goats and Shore-Sheep).
## Animals path to the trough to satisfy hunger and thirst. Auto-fills with water during rain.

const U := VoxelWorld.VS * 0.5
const FEED_ITEMS := [&"shore_wheat", &"tide_kale", &"samphire", &"kelp_frond", &"seed_shore_wheat"]

var feed_count: int = 0
var water_count: int = 0
var max_feed: int = 10
var max_water: int = 10

var _feed_mesh: MeshInstance3D
var _water_mesh: MeshInstance3D
var _rain_accumulator: float = 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"feed_trough", "Livestock Trough", p_coord)
	entity_type = EntityType.CONTAINER
	size = Vector3(14, 5, 8) * U
	state_changed.connect(_refresh_visuals)


func _build_visuals() -> void:
	# Wooden trough frame
	var g := Prefabs.Grid.new(14, 5, 8)
	# Corner legs
	for x in [0, 13]:
		for z in [0, 7]:
			g.box(x, 0, z, x, 4, z, Palette.DARK_WOOD)
	# Bottom floor
	g.box(1, 1, 1, 12, 1, 6, Palette.PLANK)
	# Side slats
	g.box(0, 2, 0, 13, 4, 0, Palette.PLANK)
	g.box(0, 2, 7, 13, 4, 7, Palette.PLANK)
	g.box(0, 2, 1, 0, 4, 6, Palette.PLANK)
	g.box(13, 2, 1, 13, 4, 6, Palette.PLANK)
	_mesh_instance = _voxel_model(g)

	# Feed layer (hay / grains)
	var hay := Prefabs.Grid.new(12, 2, 6)
	hay.box(0, 0, 0, 11, 1, 5, Palette.FLOWER_Y)
	_feed_mesh = _voxel_model(hay)
	_feed_mesh.position.y = U * 1.5

	# Water layer (reflective blue)
	var water := Prefabs.Grid.new(12, 1, 6)
	water.box(0, 0, 0, 11, 0, 5, Palette.SHUTTER)
	_water_mesh = _voxel_model(water)
	_water_mesh.position.y = U * 2.2

	_refresh_visuals()


func _refresh_visuals() -> void:
	if _feed_mesh != null:
		_feed_mesh.visible = feed_count > 0
		if feed_count > 0:
			_feed_mesh.scale = Vector3(1.0, clampf(float(feed_count) / float(max_feed), 0.35, 1.0), 1.0)
	if _water_mesh != null:
		_water_mesh.visible = water_count > 0
		if water_count > 0:
			_water_mesh.scale = Vector3(1.0, clampf(float(water_count) / float(max_water), 0.35, 1.0), 1.0)


func has_feed() -> bool:
	return feed_count > 0


func has_water() -> bool:
	return water_count > 0


func consume_feed() -> bool:
	if feed_count > 0:
		feed_count -= 1
		state_changed.emit()
		return true
	return false


func consume_water() -> bool:
	if water_count > 0:
		water_count -= 1
		state_changed.emit()
		return true
	return false


func get_interaction_prompt(player: Player) -> String:
	if player != null and player.inventory != null:
		var slot: ItemSlot = player.inventory.get_active_item()
		if slot != null and not slot.is_empty():
			if slot.item_id in FEED_ITEMS:
				if feed_count >= max_feed:
					return "Trough: Feed Full (%d/%d)" % [feed_count, max_feed]
				return "F  Add %s to Trough (%d/%d)" % [slot.item_id, feed_count, max_feed]
			elif slot.item_id == &"wooden_bucket":
				if water_count >= max_water:
					return "Trough: Water Full (%d/%d)" % [water_count, max_water]
				return "F  Fill Trough with Water (%d/%d)" % [water_count, max_water]

	return "Trough: %d/%d Feed, %d/%d Water" % [feed_count, max_feed, water_count, max_water]


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if player == null or player.inventory == null:
		return
	var slot: ItemSlot = player.inventory.get_active_item()
	if slot != null and not slot.is_empty():
		if slot.item_id in FEED_ITEMS:
			if feed_count < max_feed:
				manager.request_action(self, &"add_feed", {"item": slot.item_id})
				return
		elif slot.item_id == &"wooden_bucket":
			if water_count < max_water:
				manager.request_action(self, &"add_water", {})
				return

	if player.hud != null:
		player.hud.show_toast(get_interaction_prompt(player))


func server_action(action: StringName, args: Dictionary, _sender_id: int = 1) -> Dictionary:
	match action:
		&"add_feed":
			var item: StringName = StringName(args.get("item", &""))
			if item in FEED_ITEMS and feed_count < max_feed:
				feed_count = mini(feed_count + 3, max_feed)
				return {"ok": true, "cost": [[item, 1]]}
		&"add_water":
			if water_count < max_water:
				water_count = mini(water_count + 4, max_water)
				return {"ok": true}
		&"animal_feed":
			if feed_count > 0:
				feed_count -= 1
				return {"ok": true}
		&"animal_drink":
			if water_count > 0:
				water_count -= 1
				return {"ok": true}
	return {"ok": false}


func server_tick(delta: float, _env: Dictionary = {}) -> bool:
	# Naturally collect rainwater during storms and showers
	if manager != null and manager.main != null and manager.main.get("sky") != null:
		var sky = manager.main.sky
		if sky.has_method("is_raining") and sky.is_raining():
			_rain_accumulator += delta
			if _rain_accumulator >= 15.0:
				_rain_accumulator = 0.0
				if water_count < max_water:
					water_count = mini(water_count + 1, max_water)
					return true
	return false


func serialize() -> Dictionary:
	var d := super.serialize()
	d.merge({
		"feed": feed_count,
		"water": water_count,
	}, true)
	return d


func deserialize(data: Dictionary) -> void:
	if data.has("id"):
		super.deserialize(data)
	feed_count = int(data.get("feed", 0))
	water_count = int(data.get("water", 0))
	_refresh_visuals()


func pickup_items() -> Array:
	var out: Array = [[&"feed_trough", 1]]
	if feed_count > 0:
		out.append([&"shore_wheat", clampi(feed_count / 2, 1, 5)])
	return out
