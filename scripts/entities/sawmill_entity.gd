class_name AutomatedSawmillEntity
extends WorldEntity
## Automated Sawmill: mechanical reciprocating saw frame powered by an adjacent Tide Wheel.
## Automatically slices Driftwood and Logs into construction planks.

const U := VoxelWorld.VS * 0.5

var logs_stored := 0
var planks_stored := 0
var _process_t := 0.0
var _saw_blade: Node3D
var _phase := 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"automated_sawmill", "Automated Sawmill", p_coord)
	entity_type = EntityType.WORKSTATION
	item_id = &"automated_sawmill"
	size = Vector3(14, 12, 10) * U


func _build_visuals() -> void:
	var root := Node3D.new()
	var g := Prefabs.Grid.new(14, 12, 10)
	# Timber log carriage bed & iron framing
	g.box(1, 0, 1, 13, 3, 9, Palette.DARK_WOOD)          # carriage track
	g.box(2, 3, 2, 12, 4, 8, Palette.PLANK)
	g.box(6, 4, 1, 8, 11, 2, Palette.METAL)              # vertical guide frame
	g.box(6, 4, 8, 8, 11, 9, Palette.METAL)
	var mi_frame := _voxel_model(g)
	mi_frame.position = Vector3(-7, 0, -5) * U
	root.add_child(mi_frame)

	# Reciprocating steel vertical saw blade
	_saw_blade = Node3D.new()
	_saw_blade.position = Vector3(0, 7 * U, 0)
	root.add_child(_saw_blade)
	var sg := Prefabs.Grid.new(2, 8, 6)
	sg.box(0, 0, 0, 1, 7, 1, Palette.METAL)              # iron blade
	sg.box(0, 2, 1, 1, 5, 5, Palette.HANDLE)             # saw teeth
	var mi_blade := _voxel_model(sg)
	mi_blade.position = Vector3(-1, -4, -3) * U
	_saw_blade.add_child(mi_blade)

	_mesh_instance = root


func _process(dt: float) -> void:
	var powered := TideWheelEntity.is_powered_at(position)
	if powered:
		_phase += dt * 6.0
		if _saw_blade != null:
			_saw_blade.position.y = (7.0 + sin(_phase) * 1.8) * U

		if logs_stored > 0:
			_process_t -= dt
			if _process_t <= 0.0:
				_process_t = 3.0
				logs_stored -= 1
				planks_stored += 3
				CombatAudio.play_sound("hit_shell", position, -6.0)


func get_interaction_prompt(_player: Player) -> String:
	var powered := TideWheelEntity.is_powered_at(position)
	var status := "Powered by Tide Wheel" if powered else "Requires Adjacent Tide Wheel"
	return "Automated Sawmill · Logs: %d, Planks: %d (%s)  ·  F: Load Logs / Take Planks" % [logs_stored, planks_stored, status]


func client_interact(player: Player) -> void:
	if planks_stored > 0:
		player.inventory.add_item(&"wood_plank", planks_stored)
		if player.hud != null:
			player.hud.show_toast("Collected %d Wood Planks" % planks_stored)
		planks_stored = 0
		return

	# Load driftwood or logs from player inventory
	var has_wood: int = player.inventory.count_item(&"driftwood")
	if has_wood > 0:
		var take_count := mini(has_wood, 4)
		player.inventory.remove_item(&"driftwood", take_count)
		logs_stored += take_count
		if player.hud != null:
			player.hud.show_toast("Added %d Driftwood to Sawmill" % take_count)
		CombatAudio.play_sound("block", position)
	else:
		if player.hud != null:
			player.hud.show_toast("Need Driftwood to mill planks")
