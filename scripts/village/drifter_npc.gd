class_name DrifterNPC
extends Node3D
## A drifter in the world: stranded on a beach until recruited, then a villager with a
## daily routine. The host / server simulates movement (path following); clients only
## interpolate the states it broadcasts.

const VS := VoxelWorld.VS
const WALK_SPEED := 1.5          # m/s
const PROFESSION_NAMES := ["Fisher", "Farmer", "Carpenter", "Smoker & Cook", "Lamplighter", "Trader"]

var idx := 0                      # roster index (stable across peers)
var def: DrifterDef
var recruited := false
var wreck_pos := Vector3.ZERO     # metres: where they washed up
var model: CharacterModel
var label: Label3D

# simulation (authority)
var path: Array = []              # Vector3 waypoints (metres, feet)
var path_goal := Vector3.INF
var target_key := ""              # what the current path leads to (routine + place)
var idle_t := 0.0
var speed := 0.0
var facing := 0.0
var activity := 0                 # 0 idle, 1 walking, 2 working, 3 sleeping

# interpolation (clients)
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _has_net := false


func setup(p_idx: int, p_def: DrifterDef, p_wreck: Vector3, look_seed: int) -> void:
	idx = p_idx
	def = p_def
	wreck_pos = p_wreck
	position = p_wreck
	var cust := CharacterCustomizer.new()
	cust.randomize_appearance(look_seed)
	model = CharacterModel.new()
	add_child(model)
	model.setup(Palette.COAT_B, Palette.HAT_B, cust)
	label = Label3D.new()
	label.position = Vector3(0, 2.2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 10
	label.pixel_size = 0.004
	label.modulate = Color(1.0, 0.95, 0.82)
	add_child(label)
	refresh_label()


func profession_name() -> String:
	return PROFESSION_NAMES[clampi(int(def.profession), 0, PROFESSION_NAMES.size() - 1)]


func refresh_label() -> void:
	if label == null:
		return
	label.text = "%s the %s%s" % [def.name, profession_name(), "" if recruited else "\n(stranded)"]


# ---------------------------------------------------------------- authority simulation

func set_path(p: Array, goal: Vector3, key: String) -> void:
	path = p
	path_goal = goal
	target_key = key


func at_goal() -> bool:
	return path.is_empty() and path_goal != Vector3.INF and Vector2(position.x - path_goal.x, position.z - path_goal.z).length() < 0.6


func simulate(delta: float) -> void:
	if path.is_empty():
		speed = 0.0
		return
	var wp: Vector3 = path[0]
	var to := Vector3(wp.x - position.x, 0, wp.z - position.z)
	var d := to.length()
	if d < 0.12:
		position.y = wp.y
		path.pop_front()
		return
	var step := minf(d, WALK_SPEED * delta)
	position += to / d * step
	# feet glide toward the waypoint height (steps are <= 0.54 m)
	position.y = lerpf(position.y, wp.y, 1.0 - exp(-delta * 10.0))
	speed = WALK_SPEED
	facing = lerp_angle(facing, atan2(to.x, to.z), 1.0 - exp(-delta * 10.0))


## Skip straight to the goal (no player nearby to watch the walk).
func teleport_to_goal() -> void:
	if path_goal != Vector3.INF:
		position = path_goal
	path.clear()
	speed = 0.0


# ---------------------------------------------------------------- network state

func apply_net(pos: Vector3, yaw: float, spd: float, act: int) -> void:
	_net_pos = pos
	_net_yaw = yaw
	speed = spd
	activity = act
	if not _has_net or position.distance_to(pos) > 6.0:
		position = pos
		facing = yaw
	_has_net = true


func _process(delta: float) -> void:
	if _has_net:
		position = position.lerp(_net_pos, 1.0 - exp(-delta * 10.0))
		facing = lerp_angle(facing, _net_yaw, 1.0 - exp(-delta * 10.0))
	model.rotation.y = facing
	# rod / hoe / hammer / none / lantern / ledger-plan while working, empty hands otherwise
	model.set_tool([3, 4, 1, -1, 8, 2][clampi(int(def.profession), 0, 5)] if activity == 2 else -1)
	model.animate(delta, speed, true, false)
	if activity == 2 and fmod(Time.get_ticks_msec() / 1000.0 + idx * 0.37, 2.2) < delta:
		model.swing()   # busy at work
	model.position.y = -0.25 if activity == 3 else 0.0   # settled into bed
