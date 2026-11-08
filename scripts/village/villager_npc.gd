class_name VillagerNPC
extends Node3D
## A resident of one of the NPC villages on the other islands. Each peer runs its own copy:
## where a villager should be is a pure function of the (synced) time of day, so nothing
## about their movement needs networking. See NpcVillages.

const WALK_SPEED := 1.4
const ROLE_TOOL := {"trader": 2, "elder": -1, "fisher": 3, "farmer": 4, "mender": 1}
const ROLE_TITLE := {"trader": "Trader", "elder": "Village Elder", "fisher": "Fisher", "farmer": "Farmer", "mender": "Net-Mender"}

var key := ""                 # "<village>:<role>"
var role := "fisher"
var villager_name := ""
var home := Vector3.ZERO      # metres, feet at the cottage door
var work := Vector3.ZERO      # metres, feet at the work spot
var world: VoxelWorld
var sky: SkyCycle
var model: CharacterModel
var label: Label3D
var marker: Label3D
var _speed := 0.0
var _stuck_t := 0.0
var _seed := 0
var talking := false          # face the player and stand still while a dialogue is open


func setup(p_key: String, p_role: String, p_name: String, p_home: Vector3, p_work: Vector3, look_seed: int,
		p_world: VoxelWorld, p_sky: SkyCycle) -> void:
	key = p_key
	role = p_role
	villager_name = p_name
	home = p_home
	work = p_work
	world = p_world
	sky = p_sky
	_seed = look_seed
	name = "Villager_" + p_key.replace(":", "_")
	var cust := CharacterCustomizer.new()
	cust.randomize_appearance(look_seed)
	model = CharacterModel.new()
	add_child(model)
	var coats := [Palette.COAT_A, Palette.COAT_B, Palette.ROOF_BLUE, Palette.ROOF_RED, Palette.SHUTTER]
	model.setup(coats[look_seed % coats.size()], [Palette.HAT_A, Palette.HAT_B, Palette.DARK_WOOD][look_seed % 3], cust)
	label = Label3D.new()
	label.position = Vector3(0, 2.2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 34
	label.outline_size = 10
	label.pixel_size = 0.004
	label.modulate = Color(1.0, 0.95, 0.82)
	label.text = "%s\n%s" % [villager_name, ROLE_TITLE.get(role, "")]
	add_child(label)
	marker = Label3D.new()
	marker.position = Vector3(0, 2.75, 0)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.font_size = 96
	marker.outline_size = 16
	marker.pixel_size = 0.004
	marker.modulate = UiTheme.BRASS
	marker.no_depth_test = true
	add_child(marker)
	position = goal()


## At home overnight, at work by day. Workers drift about their spot a little.
func is_home_time() -> bool:
	var t := sky.time_of_day if sky != null else 0.5
	return t < 0.27 or t > 0.86


func goal() -> Vector3:
	if is_home_time():
		return home
	if role == "trader" or role == "elder":
		return work
	var t := (sky.time_of_day if sky != null else 0.5) * 24.0 * 60.0   # game minutes
	var slot := int(t / 20.0)                                            # a new spot every 20 game minutes
	var h := hash([_seed, slot])
	var ang := float(h % 628) / 100.0
	var r := 0.6 + float((h >> 10) % 100) / 100.0 * 2.2
	return work + Vector3(cos(ang) * r, 0, sin(ang) * r)


## Is the villager out and about (not tucked up indoors)?
func is_available() -> bool:
	return visible


func step(delta: float, player_pos: Vector3) -> void:
	var g := goal()
	var flat := Vector2(g.x - position.x, g.z - position.z)
	var far := position.distance_to(player_pos) > 70.0
	if talking:
		_speed = 0.0
		var to := player_pos - position
		model.rotation.y = lerp_angle(model.rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 6.0))
	elif far and flat.length() > 0.5:
		position = _ground(g)          # nobody watching: just be there
		_speed = 0.0
	elif flat.length() > 0.35:
		_walk(delta, g)
	else:
		_speed = 0.0
		if role == "fisher" and not is_home_time():
			model.rotation.y = lerp_angle(model.rotation.y, atan2(work.x - home.x, work.z - home.z), 1.0 - exp(-delta * 3.0))
		elif position.distance_to(player_pos) < 8.0:
			var to := player_pos - position
			model.rotation.y = lerp_angle(model.rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 4.0))
	# Indoors overnight once they've reached their door.
	var inside := is_home_time() and Vector2(position.x - home.x, position.z - home.z).length() < 0.6 and not talking
	visible = not inside
	var at_work := not is_home_time() and _speed == 0.0 and not talking
	model.set_tool(int(ROLE_TOOL.get(role, -1)) if at_work else -1)
	model.animate(delta, _speed, true, false)
	if at_work and role in ["farmer", "mender"] and fmod(Time.get_ticks_msec() / 1000.0 + float(_seed % 7) * 0.31, 2.6) < delta:
		model.swing()
	if marker.text != "":
		marker.position.y = 2.75 + sin(Time.get_ticks_msec() / 1000.0 * 3.0 + _seed) * 0.06


func _ground(p: Vector3) -> Vector3:
	if world == null:
		return p
	var hit: Dictionary = world.raycast(p + Vector3(0, 3.0, 0), Vector3.DOWN, 10.0, true)
	if hit.is_empty():
		return p
	return Vector3(p.x, p.y + 3.0 - float(hit.dist), p.z)


func _walk(delta: float, goal_pos: Vector3) -> void:
	var to := goal_pos - position
	to.y = 0
	var dir := to.normalized()
	var budget := minf(WALK_SPEED * delta, to.length())
	var moved := 0.0
	while moved < budget - 0.001:
		var stepped := false
		for turn in [0.0, 0.6, -0.6, 1.2, -1.2]:
			var d2 := dir.rotated(Vector3.UP, turn)
			var next := _ground(position + d2 * minf(0.25, budget - moved))
			var water := sky.water_level_m() if sky != null else -INF
			if next.y >= water - 0.3 and absf(next.y - position.y) <= 0.6:
				position = next
				stepped = true
				break
		if not stepped:
			break
		moved += 0.25
	_speed = WALK_SPEED if moved > 0.0 else 0.0
	_stuck_t = 0.0 if moved > 0.0 else _stuck_t + delta
	model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-delta * 8.0))
	if _stuck_t > 3.0:
		_stuck_t = 0.0
		position = _ground(goal_pos)   # blocked (a fence, a build): step to where they're going
