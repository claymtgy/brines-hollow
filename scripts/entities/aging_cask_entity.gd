class_name AgingCaskEntity
extends WorldEntity
## Oak Aging Cask: Homestead workstation for curing dairy and fermenting craft brews.
## Cures Salt-Goat Milk into Aged Brine Cheese, and ferments grains into Vintage Maritime Ale.

const U := VoxelWorld.VS * 0.5
const CURE_TIME_SEC := 45.0

var is_fermenting: bool = false
var progress_sec: float = 0.0
var current_input: StringName = &""
var current_output: StringName = &""
var output_ready: bool = false


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"aging_cask", "Oak Aging Cask", p_coord)
	entity_type = EntityType.WORKSTATION
	item_id = &"aging_cask"
	size = Vector3(6, 6, 6) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(6, 6, 6)
	# Timber cradle legs
	g.box(0, 0, 0, 1, 1, 5, Palette.DARK_WOOD)
	g.box(4, 0, 0, 5, 1, 5, Palette.DARK_WOOD)
	# Barrel body
	g.box(1, 1, 0, 4, 5, 5, Palette.DRIFTWOOD)
	# Iron binding hoops
	g.box(0, 2, 1, 5, 4, 1, Palette.METAL)
	g.box(0, 2, 4, 5, 4, 4, Palette.METAL)
	# Brass spigot
	g.box(2, 2, 5, 3, 3, 5, Palette.METAL)

	_mesh_instance = _voxel_model(g)


func _process(dt: float) -> void:
	advance_time(dt)


func advance_time(dt: float) -> void:
	if not is_fermenting:
		return
	progress_sec += dt
	if progress_sec >= CURE_TIME_SEC:
		is_fermenting = false
		output_ready = true


func interact(player: Node) -> void:
	if player == null or not ("inventory" in player):
		return
	var inv: Inventory = player.inventory
	if inv == null:
		return

	# If finished, claim the aged produce
	if output_ready:
		output_ready = false
		inv.add_item(current_output, 1)
		if player.has_method("quest_event"):
			player.quest_event(QuestDef.ObjectiveType.GATHER_ITEM, current_output)
		current_input = &""
		current_output = &""
		progress_sec = 0.0
		return

	if is_fermenting:
		return

	# Start fermentation recipe
	if inv.has_item(&"salt_milk"):
		inv.remove_item(&"salt_milk", 1)
		current_input = &"salt_milk"
		current_output = &"aged_brine_cheese"
		is_fermenting = true
		progress_sec = 0.0
	elif inv.has_item(&"wheat_flour") or inv.has_item(&"brackish_rye"):
		if inv.has_item(&"brackish_rye"):
			inv.remove_item(&"brackish_rye", 1)
			current_output = &"maritime_stout"
		else:
			inv.remove_item(&"wheat_flour", 1)
			current_output = &"vintage_maritime_ale"
		is_fermenting = true
		progress_sec = 0.0


func serialize() -> Dictionary:
	var d := super.serialize()
	d["is_fermenting"] = is_fermenting
	d["progress"] = progress_sec
	d["input"] = String(current_input)
	d["output"] = String(current_output)
	d["ready"] = output_ready
	return d


func deserialize(d: Dictionary) -> void:
	super.deserialize(d)
	is_fermenting = bool(d.get("is_fermenting", false))
	progress_sec = float(d.get("progress", 0.0))
	current_input = StringName(d.get("input", ""))
	current_output = StringName(d.get("output", ""))
	output_ready = bool(d.get("ready", false))
