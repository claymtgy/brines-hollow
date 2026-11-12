class_name DrifterNPC
extends Node3D
## A drifter in the world: stranded on a beach until recruited, then a villager with a
## daily routine. The host / server simulates movement (path following); clients only
## interpolate the states it broadcasts.

const VS := VoxelWorld.VS
const WALK_SPEED := 1.5          # m/s
## One per DrifterDef.Profession, in the same order.
const PROFESSION_NAMES := ["Fisher", "Farmer", "Carpenter", "Smoker & Cook", "Lamplighter", "Trader", "Rancher", "Builder"]

var idx := 0                      # roster index (stable across peers)
var def: DrifterDef
var recruited := false
var castaway := false              # trapped in a shipwreck on an outer island
var voyage := false                # host: recruited far from home, sails back when unwatched
var wreck_pos := Vector3.ZERO     # metres: where they washed up
var model: CharacterModel
var label: Label3D
var marker: Label3D

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
	marker = Label3D.new()
	marker.name = "QuestMarker"
	marker.position = Vector3(0, 2.65, 0)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.font_size = 96
	marker.outline_size = 16
	marker.pixel_size = 0.004
	marker.modulate = UiTheme.BRASS
	marker.no_depth_test = true
	add_child(marker)
	refresh_label()
	refresh_marker(null)


func profession_name() -> String:
	return PROFESSION_NAMES[clampi(int(def.profession), 0, PROFESSION_NAMES.size() - 1)]


func refresh_label() -> void:
	if label == null:
		return
	var tag := "" if recruited else ("\n(trapped in the wreck)" if castaway else "\n(stranded)")
	if voyage:
		tag = "\n(sailing home)"
	label.text = "%s the %s%s" % [def.name, profession_name(), tag]


func set_quest_marker(p_text: String) -> void:
	if marker != null:
		marker.text = p_text


func matches_quest_target(target: Variant) -> bool:
	if def == null:
		return false
	var t_str: String = String(target).strip_edges().to_lower()
	if t_str == "":
		return false
	var my_name: String = def.name.to_lower()
	var my_id: String = String(def.id).to_lower()
	var my_prof: String = profession_name().to_lower()

	if t_str == my_name or t_str == my_id or t_str == my_prof:
		return true
	if my_name != "" and (t_str.contains(my_name) or my_name.contains(t_str)):
		return true
	if my_prof != "" and t_str.contains(my_prof):
		return true
	if my_name == "corwin" and t_str.contains("corin"):
		return true
	if "cook" in my_prof and "cook" in t_str:
		return true
	return false


func get_available_quest(qm: QuestManager) -> QuestDef:
	if qm == null:
		return null
	for q_id in qm.available_quests.keys():
		var qd: QuestDef = qm.available_quests[q_id]
		if matches_quest_target(qd.giver_name) or matches_quest_target(qd.id):
			return qd
	return null


func refresh_marker(qm: QuestManager) -> void:
	if marker == null:
		return
	if qm == null:
		marker.text = ""
		return

	# Priority 1: Ready to turn in or talk to ("?")
	for q_id in qm.active_quests.keys():
		var qd: QuestDef = qm.active_quests[q_id]
		# Check if rewards are paused for this quest and NPC matches giver
		if qm.paused_reward_quests.has(qd.id) and matches_quest_target(qd.giver_name):
			marker.text = "?"
			marker.modulate = UiTheme.BRASS
			return

		# Check if NPC is target of active TALK_TO step and all preceding steps are done
		var talk_step_found := false
		var other_steps_done := true
		for s in qd.steps:
			if not s.is_completed:
				if s.type == QuestDef.ObjectiveType.TALK_TO and matches_quest_target(s.target_id):
					talk_step_found = true
				else:
					other_steps_done = false
		if talk_step_found and other_steps_done:
			marker.text = "?"
			marker.modulate = UiTheme.BRASS
			return

		# Check if all steps in quest are done and this NPC is the giver
		if qd.is_complete() and matches_quest_target(qd.giver_name):
			marker.text = "?"
			marker.modulate = UiTheme.BRASS
			return

	# Priority 2: New available quest to offer ("!")
	var avail := get_available_quest(qm)
	if avail != null:
		marker.text = "!"
		marker.modulate = UiTheme.BRASS
		return

	marker.text = ""


# ---------------------------------------------------------------- authority simulation

func set_path(p: Array, goal: Vector3, key: String) -> void:
	path = p
	path_goal = goal
	target_key = key


func at_goal() -> bool:
	return path.is_empty() and path_goal != Vector3.INF and Vector2(position.x - path_goal.x, position.z - path_goal.z).length() < 0.6


func simulate(delta: float) -> void:
	if path.is_empty() or talk_look_t > 0.0:   # (paused while someone is talking to them)
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


var talk_look_t := 0.0


func face_player(player_pos: Vector3) -> void:
	var to := player_pos - position
	if to.length_squared() > 0.01:
		facing = atan2(to.x, to.z)
		talk_look_t = 5.0


func _process(delta: float) -> void:
	if talk_look_t > 0.0:
		talk_look_t -= delta
	elif _has_net:
		position = position.lerp(_net_pos, 1.0 - exp(-delta * 10.0))
		facing = lerp_angle(facing, _net_yaw, 1.0 - exp(-delta * 10.0))
	model.rotation.y = facing
	# Fisher: rod(3), Farmer: hoe(4), Carpenter: hammer(1), Cook: cutlass/knife(5),
	# Lamplighter: lantern(8), Trader: ledger(2), Rancher: shears/axe(9), Builder: hammer(1)
	var tool_by_prof := [3, 4, 1, 5, 8, 2, 9, 1]
	model.set_tool(tool_by_prof[clampi(int(def.profession), 0, tool_by_prof.size() - 1)] if activity == 2 else -1)
	model.animate(delta, speed, true, false)
	if activity == 2 and fmod(Time.get_ticks_msec() / 1000.0 + idx * 0.37, 2.2) < delta:
		model.swing()   # busy at work
	if marker != null and marker.text != "":
		marker.position.y = 2.65 + sin(Time.get_ticks_msec() / 1000.0 * 3.0 + idx) * 0.06
	# Evening tavern dance / social sway when happy
	if activity == 1 and def.morale >= 0.5:
		var dance_phase := Time.get_ticks_msec() / 1000.0 * 2.8 + idx * 1.2
		model.rotation.z = sin(dance_phase) * 0.08
		model.position.y = absf(sin(dance_phase)) * 0.04
	else:
		model.rotation.z = 0.0
		model.position.y = -0.25 if activity == 3 else 0.0   # settled into bed
