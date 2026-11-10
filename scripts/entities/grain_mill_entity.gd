class_name AutomatedGrainMillEntity
extends WorldEntity
## Automated Grain Mill: stone quern powered by kinetic torque from an adjacent Tide Wheel.
## Automatically grinds Shore Wheat into fine baking flour when powered.

const U := VoxelWorld.VS * 0.5

var wheat_stored := 0
var flour_stored := 0
var _process_t := 0.0
var _grindstone: Node3D
var _rot := 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"automated_grain_mill", "Automated Grain Mill", p_coord)
	entity_type = EntityType.WORKSTATION
	item_id = &"automated_grain_mill"
	size = Vector3(12, 10, 12) * U


func _build_visuals() -> void:
	var root := Node3D.new()
	var g := Prefabs.Grid.new(12, 10, 12)
	# Circular stone base & hopper
	g.box(2, 0, 2, 10, 4, 10, Palette.STONE)
	g.box(3, 4, 3, 9, 8, 9, Palette.DARK_WOOD)          # grain hopper
	g.box(4, 5, 4, 8, 8, 8, Palette.CLEAR)
	g.box(5, 1, 10, 7, 3, 11, Palette.PLANK)            # meal spout
	var mi_base := _voxel_model(g)
	mi_base.position = Vector3(-6, 0, -6) * U
	root.add_child(mi_base)

	# Rotating upper grindstone & axle
	_grindstone = Node3D.new()
	_grindstone.position = Vector3(0, 4.5 * U, 0)
	root.add_child(_grindstone)
	var qg := Prefabs.Grid.new(8, 2, 8)
	qg.box(1, 0, 1, 7, 2, 7, Palette.COBBLE)
	qg.box(3, 0, 3, 5, 4, 5, Palette.METAL)             # iron drive shaft
	var mi_stone := _voxel_model(qg)
	mi_stone.position = Vector3(-4, 0, -4) * U
	_grindstone.add_child(mi_stone)

	_mesh_instance = root


func _process(dt: float) -> void:
	var powered := TideWheelEntity.is_powered_at(position)
	if powered:
		_rot += dt * 3.0
		if _grindstone != null:
			_grindstone.rotation.y = _rot

		if wheat_stored > 0:
			_process_t -= dt
			if _process_t <= 0.0:
				_process_t = 3.5
				wheat_stored -= 1
				flour_stored += 2
				CombatAudio.play_sound("tell_snap", position, -6.0)


func get_interaction_prompt(_player: Player) -> String:
	var powered := TideWheelEntity.is_powered_at(position)
	var status := "Powered by Tide Wheel" if powered else "Requires Adjacent Tide Wheel"
	return "Automated Grain Mill · Wheat: %d, Flour: %d (%s)  ·  F: Load Wheat / Take Flour" % [wheat_stored, flour_stored, status]


func client_interact(player: Player) -> void:
	if flour_stored > 0:
		player.inventory.add_item(&"wheat_flour", flour_stored)
		if player.hud != null:
			player.hud.show_toast("Collected %d Shore Wheat Flour" % flour_stored)
		flour_stored = 0
		return

	# Load wheat from player inventory
	var has_wheat: int = player.inventory.count_item(&"shore_wheat")
	if has_wheat > 0:
		var take_count := mini(has_wheat, 5)
		player.inventory.remove_item(&"shore_wheat", take_count)
		wheat_stored += take_count
		if player.hud != null:
			player.hud.show_toast("Added %d Shore Wheat to Grain Mill" % take_count)
		CombatAudio.play_sound("block", position)
	else:
		if player.hud != null:
			player.hud.show_toast("Need Shore Wheat to mill flour")
