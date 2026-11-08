class_name CoopEntity
extends WorldEntity
## Shore Poultry Coop for Ducks and Puffins.
## Houses coastal fowl, provides shelter and nest boxes.
## When stocked with grain/wheat, birds produce Shore-Duck Eggs and Down Feathers.

const U := VoxelWorld.VS * 0.5
const FEED_ITEMS := [&"shore_wheat", &"seed_shore_wheat", &"tide_kale"]

var feed_count: int = 4
var egg_count: int = 0
var feather_count: int = 0
var max_feed: int = 10
var max_eggs: int = 6
var max_feathers: int = 6
var resident_birds: int = 2

var _produce_timer: float = 0.0
var _egg_mesh: MeshInstance3D


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"poultry_coop", "Shore Poultry Coop", p_coord)
	entity_type = EntityType.CONTAINER
	size = Vector3(16, 14, 16) * U
	state_changed.connect(_refresh_visuals)


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(16, 14, 16)
	# Stilt legs (lifted off damp mud)
	for x in [1, 14]:
		for z in [1, 14]:
			g.box(x, 0, z, x + 1, 2, z + 1, Palette.DARK_WOOD)

	# Main floor & walls
	g.box(1, 2, 1, 14, 2, 14, Palette.PLANK)
	# Side walls
	g.box(1, 3, 1, 1, 9, 14, Palette.WHITEWASH)
	g.box(14, 3, 1, 14, 9, 14, Palette.WHITEWASH)
	g.box(2, 3, 1, 13, 9, 1, Palette.WHITEWASH)
	# Front wall with pop-hole door
	g.box(2, 3, 14, 5, 9, 14, Palette.WHITEWASH)
	g.box(10, 3, 14, 13, 9, 14, Palette.WHITEWASH)
	g.box(6, 7, 14, 9, 9, 14, Palette.WHITEWASH) # Door lintel

	# Pitched roof (gable style)
	for y in range(0, 4):
		var x0 := y
		var x1 := 15 - y
		g.box(x0, 10 + y, 0, x1, 10 + y, 15, Palette.ROOF_RED)

	# Nest boxes protruding on the side
	g.box(0, 3, 4, 0, 6, 11, Palette.DARK_WOOD)
	g.box(0, 2, 4, 1, 2, 11, Palette.DARK_WOOD)

	_mesh_instance = _voxel_model(g)

	# Visual eggs inside the nest box
	var egg_g := Prefabs.Grid.new(2, 2, 4)
	egg_g.box(0, 0, 0, 1, 1, 1, Palette.WHITEWASH)
	egg_g.box(0, 0, 2, 1, 1, 3, Palette.WHITEWASH)
	_egg_mesh = _voxel_model(egg_g)
	_egg_mesh.position = Vector3(-8.5 * U, 3.5 * U, -1.0 * U)

	_refresh_visuals()


func _refresh_visuals() -> void:
	if _egg_mesh != null:
		_egg_mesh.visible = egg_count > 0


func get_interaction_prompt(player: Player) -> String:
	if egg_count > 0 or feather_count > 0:
		return "F  Collect %d Eggs, %d Feathers" % [egg_count, feather_count]
	if player != null and player.inventory != null:
		var slot: ItemSlot = player.inventory.get_active_item()
		if slot != null and not slot.is_empty() and slot.item_id in FEED_ITEMS:
			if feed_count >= max_feed:
				return "Coop: Feed Full (%d/%d)" % [feed_count, max_feed]
			return "F  Fill Coop Feed with %s (%d/%d)" % [slot.item_id, feed_count, max_feed]
	return "Coop: %d Ducks (%d/%d Feed, %d Eggs)" % [resident_birds, feed_count, max_feed, egg_count]


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if egg_count > 0 or feather_count > 0:
		manager.request_action(self, &"collect", {})
		return

	if player != null and player.inventory != null:
		var slot: ItemSlot = player.inventory.get_active_item()
		if slot != null and not slot.is_empty() and slot.item_id in FEED_ITEMS:
			if feed_count < max_feed:
				manager.request_action(self, &"add_feed", {"item": slot.item_id})
				return

	if player.hud != null:
		player.hud.show_toast(get_interaction_prompt(player))


func server_action(action: StringName, args: Dictionary, _sender_id: int = 1) -> Dictionary:
	match action:
		&"collect":
			if egg_count <= 0 and feather_count <= 0:
				return {"ok": false}
			var grants: Array = []
			if egg_count > 0:
				grants.append([&"sea_egg", egg_count])
			if feather_count > 0:
				grants.append([&"down_feather", feather_count])
			egg_count = 0
			feather_count = 0
			return {"ok": true, "grant": grants}
		&"add_feed":
			var item: StringName = StringName(args.get("item", &""))
			if item in FEED_ITEMS and feed_count < max_feed:
				feed_count = mini(feed_count + 3, max_feed)
				return {"ok": true, "cost": [[item, 1]]}
	return {"ok": false}


func server_tick(delta: float, _env: Dictionary = {}) -> bool:
	if feed_count > 0 and (egg_count < max_eggs or feather_count < max_feathers):
		_produce_timer += delta
		# Lay an egg / shed feather roughly every 120 seconds per bird
		var interval := 120.0 / float(maxi(1, resident_birds))
		if _produce_timer >= interval:
			_produce_timer = 0.0
			feed_count -= 1
			var changed := false
			if egg_count < max_eggs:
				egg_count += 1
				changed = true
			if feather_count < max_feathers and randf() < 0.65:
				feather_count += 1
				changed = true
			return changed
	return false


func serialize() -> Dictionary:
	var d := super.serialize()
	d.merge({
		"feed": feed_count,
		"eggs": egg_count,
		"feathers": feather_count,
		"birds": resident_birds,
		"timer": _produce_timer,
	}, true)
	return d


func deserialize(data: Dictionary) -> void:
	if data.has("id"):
		super.deserialize(data)
	feed_count = int(data.get("feed", 4))
	egg_count = int(data.get("eggs", 0))
	feather_count = int(data.get("feathers", 0))
	resident_birds = int(data.get("birds", 2))
	_produce_timer = float(data.get("timer", 0.0))
	_refresh_visuals()


func pickup_items() -> Array:
	var out: Array = [[&"poultry_coop", 1]]
	if egg_count > 0:
		out.append([&"sea_egg", egg_count])
	if feather_count > 0:
		out.append([&"down_feather", feather_count])
	return out
