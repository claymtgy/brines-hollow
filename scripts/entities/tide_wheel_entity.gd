class_name TideWheelEntity
extends WorldEntity
## Undershot Tide Mill Water Wheel: harnesses the ebb and flow of tidal currents.
## Must be placed in intertidal channels or shallows. While water moves, generates mechanical torque
## that automatically powers adjacent machines (Grain Mills, Sawmills) within 8m.

const U := VoxelWorld.VS * 0.5
const POWER_RADIUS := 8.0

static var active_wheels: Array[TideWheelEntity] = []

var _wheel_mesh: Node3D
var _rot := 0.0
var turning := false


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"tide_wheel", "Tide Mill Water Wheel", p_coord)
	entity_type = EntityType.WORKSTATION
	item_id = &"tide_wheel"
	size = Vector3(16, 16, 12) * U


func _build_visuals() -> void:
	var root := Node3D.new()
	# Heavy timber A-frame supports on sides
	var fg := Prefabs.Grid.new(16, 16, 12)
	fg.box(1, 0, 1, 3, 14, 3, Palette.DARK_WOOD)
	fg.box(13, 0, 1, 15, 14, 3, Palette.DARK_WOOD)
	fg.box(1, 0, 9, 3, 14, 11, Palette.DARK_WOOD)
	fg.box(13, 0, 9, 15, 14, 11, Palette.DARK_WOOD)
	fg.box(0, 12, 1, 16, 14, 11, Palette.DARK_WOOD)         # cross axle mount
	var mi_frame := _voxel_model(fg)
	mi_frame.position = Vector3(-8, 0, -6) * U
	root.add_child(mi_frame)

	# Rotating 8-paddle wooden undershot waterwheel
	_wheel_mesh = Node3D.new()
	_wheel_mesh.position = Vector3(0, 12 * U, 0)
	root.add_child(_wheel_mesh)

	var wg := Prefabs.Grid.new(14, 14, 8)
	# Wheel hub & rim
	wg.box(5, 5, 1, 9, 9, 7, Palette.DARK_WOOD)
	wg.box(1, 1, 1, 13, 13, 7, Palette.PLANK)
	wg.box(2, 2, 2, 12, 12, 6, Palette.CLEAR)
	# 4 cross paddles
	wg.box(6, 0, 2, 8, 14, 6, Palette.DRIFTWOOD)
	wg.box(0, 6, 2, 14, 8, 6, Palette.DRIFTWOOD)
	var mi_wheel := _voxel_model(wg)
	mi_wheel.position = Vector3(-7, -7, -4) * U
	_wheel_mesh.add_child(mi_wheel)

	_mesh_instance = root


func _ready() -> void:
	active_wheels.append(self)


func _exit_tree() -> void:
	active_wheels.erase(self)


func _process(dt: float) -> void:
	# Check if water is moving (tide rising or falling)
	var em := EntityManager.current
	var sky: SkyCycle = em.main.sky if (em != null and em.main != null) else null
	turning = false
	if sky != null:
		var tide_speed: float = absf(sky.tide_velocity()) if sky.has_method("tide_velocity") else 0.5
		var water_m: float = sky.water_level_m()
		if position.y <= water_m + 1.5 and position.y >= water_m - 3.0:
			turning = true
			_rot += dt * maxf(1.0, tide_speed * 4.0)
			if _wheel_mesh != null:
				_wheel_mesh.rotation.x = _rot


static func is_powered_at(pos: Vector3) -> bool:
	for tw in active_wheels:
		if is_instance_valid(tw) and tw.turning and pos.distance_to(tw.position) <= POWER_RADIUS:
			return true
	return false


func get_interaction_prompt(_player: Player) -> String:
	if turning:
		return "Tide Mill Water Wheel · Generating Mechanical Torque"
	return "Tide Mill Water Wheel · Waiting for Tidal Flow"
