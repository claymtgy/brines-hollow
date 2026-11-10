class_name MangroveBeehiveEntity
extends WorldEntity
## Mangrove Beehive: apiculture apiary placed near crops, marsh flowers, and coastal mangroves.
## Produces Marsh Honey and Natural Beeswax. Production accelerates when placed near active crops.

const U := VoxelWorld.VS * 0.5
const BASE_CYCLE_SEC := 35.0
const FLORA_RADIUS := 12.0
const MAX_STORED := 8

var honey_stored: int = 0
var wax_stored: int = 0
var cycle_progress: float = 0.0
var _check_t: float = 0.0
var _cached_flora_bonus: float = 1.0
var _flora_check_t: float = 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"mangrove_beehive", "Mangrove Beehive", p_coord)
	entity_type = EntityType.WORKSTATION
	item_id = &"mangrove_beehive"
	size = Vector3(6, 8, 6) * U


func _build_visuals() -> void:
	var root := Node3D.new()
	var g := Prefabs.Grid.new(6, 8, 6)

	# Stand / stilt legs
	g.box(1, 0, 1, 1, 2, 1, Palette.DARK_WOOD)
	g.box(4, 0, 1, 4, 2, 1, Palette.DARK_WOOD)
	g.box(1, 0, 4, 1, 2, 4, Palette.DARK_WOOD)
	g.box(4, 0, 4, 4, 2, 4, Palette.DARK_WOOD)

	# Slatted wooden brood box & honey super
	g.box(1, 2, 1, 4, 5, 4, Palette.PLANK)
	g.box(1, 6, 1, 4, 6, 4, Palette.ROOF_RED) # pitched outer roof cover
	g.box(2, 7, 2, 3, 7, 3, Palette.ROOF_RED)

	# Honey entrance slot accent
	g.setv(2, 3, 0, Palette.ROOF_RED)

	var mi := _voxel_model(g)
	mi.position = Vector3(-3, 0, -3) * U
	root.add_child(mi)

	_mesh_instance = root


func _process(dt: float) -> void:
	_flora_check_t -= dt
	if _flora_check_t <= 0.0:
		_flora_check_t = 5.0
		_recalculate_flora_bonus()

	_check_t -= dt
	if _check_t > 0.0:
		return
	_check_t = 1.0
	tick(1.0)


func _recalculate_flora_bonus() -> void:
	_cached_flora_bonus = 1.0
	var em := EntityManager.current
	if em == null:
		return

	# Check for nearby crop entities or living flora
	for e in em.all_entities():
		if e != self and is_instance_valid(e):
			if e.item_id == &"feed_trough" or e.item_id == &"pine_sapling":
				if position.distance_squared_to(e.position) <= (FLORA_RADIUS * FLORA_RADIUS):
					_cached_flora_bonus = 1.8
					break


func tick(delta: float) -> void:
	if honey_stored >= MAX_STORED and wax_stored >= MAX_STORED:
		return

	var speed := _cached_flora_bonus
	cycle_progress += delta * speed

	if cycle_progress >= BASE_CYCLE_SEC:
		cycle_progress = 0.0
		if honey_stored < MAX_STORED:
			honey_stored += 1
		if wax_stored < MAX_STORED:
			wax_stored += 1


func get_interaction_prompt(_player: Player) -> String:
	var total := honey_stored + wax_stored
	if total <= 0:
		var bonus_str := " (Foraging near flora: 1.8x speed)" if _cached_flora_bonus > 1.2 else ""
		return "Mangrove Beehive · Busy bees at work...%s" % bonus_str
	return "Mangrove Beehive · %d Honey, %d Wax ready  ·  F: Harvest" % [honey_stored, wax_stored]


func client_interact(player: Player) -> void:
	interacted.emit(player)
	var total := honey_stored + wax_stored
	if total <= 0:
		if player.hud != null:
			player.hud.show_toast("The bees are still accumulating comb.")
		return

	var harvested_names: Array[String] = []
	if honey_stored > 0:
		player.inventory.add_item(&"marsh_honey", honey_stored)
		harvested_names.append("%d Marsh Honey" % honey_stored)
		honey_stored = 0

	if wax_stored > 0:
		player.inventory.add_item(&"beeswax", wax_stored)
		harvested_names.append("%d Beeswax" % wax_stored)
		wax_stored = 0

	CombatAudio.play_sound("pickup", position)
	if player.hud != null:
		player.hud.show_toast("Harvested: " + ", ".join(harvested_names))


func serialize() -> Dictionary:
	var d := super.serialize()
	d["honey_stored"] = honey_stored
	d["wax_stored"] = wax_stored
	d["cycle_progress"] = cycle_progress
	return d


func deserialize(d: Dictionary) -> void:
	super.deserialize(d)
	honey_stored = int(d.get("honey_stored", 0))
	wax_stored = int(d.get("wax_stored", 0))
	cycle_progress = float(d.get("cycle_progress", 0.0))
