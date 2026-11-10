class_name RegattaBuoyEntity
extends WorldEntity
## Buoy Regatta Course Checkpoint: a floating barrel buoy with a glowing colored pennant.
## Placeable in water to create timed boat obstacle races across reefs and currents!

const U := VoxelWorld.VS * 0.5
const TRIGGER_RADIUS := 6.5

static var active_buoys: Array[RegattaBuoyEntity] = []
static var race_in_progress := false
static var race_start_time_msec := 0
static var next_expected_gate := 1
static var best_record_sec := 999.0

var gate_number := 1
var _light: OmniLight3D
var _bob_phase := 0.0
var _check_t := 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"regatta_buoy", "Regatta Checkpoint Buoy", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"regatta_buoy"
	size = Vector3(8, 14, 8) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(8, 14, 8)
	# Floating barrel base
	g.box(1, 1, 1, 6, 6, 6, Palette.DARK_WOOD)
	g.box(1, 2, 1, 6, 2, 6, Palette.METAL)              # brass hoop
	g.box(1, 5, 1, 6, 5, 6, Palette.METAL)

	# Mast and pennant flag
	g.box(3, 7, 3, 4, 13, 4, Palette.PLANK)             # mast
	g.box(4, 10, 3, 7, 13, 3, Palette.FLOWER_Y)         # bright pennant

	_mesh_instance = _voxel_model(g)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.85, 0.3)
	_light.light_energy = 1.2
	_light.omni_range = 8.0
	_light.position = Vector3(0, 13 * U, 0)
	add_child(_light)


func _ready() -> void:
	if not active_buoys.has(self):
		active_buoys.append(self)
		gate_number = active_buoys.size()


func _exit_tree() -> void:
	active_buoys.erase(self)


func _process(dt: float) -> void:
	_bob_phase += dt * 2.0
	if _mesh_instance != null:
		_mesh_instance.position.y = sin(_bob_phase) * 0.08

	_check_t -= dt
	if _check_t > 0.0:
		return
	_check_t = 0.1

	var em := EntityManager.current
	if em == null or em.main == null:
		return
	var player: Player = em.main.player
	if player == null or not player.is_seated():
		return

	if position.distance_to(player.position) <= TRIGGER_RADIUS:
		_trigger_gate(player)


func _trigger_gate(player: Player) -> void:
	var hud = player.hud
	if gate_number == 1 and not race_in_progress:
		# Start the race!
		race_in_progress = true
		race_start_time_msec = Time.get_ticks_msec()
		next_expected_gate = 2
		CombatAudio.play_sound("parry", position)
		if hud != null:
			hud.show_banner("Regatta Started!", "Gate 1 cleared! Race to Gate 2!")
	elif race_in_progress and gate_number == next_expected_gate:
		CombatAudio.play_sound("parry", position)
		if next_expected_gate >= active_buoys.size() and active_buoys.size() > 1:
			# Finish Line!
			race_in_progress = false
			var elapsed := (Time.get_ticks_msec() - race_start_time_msec) / 1000.0
			var is_record := elapsed < best_record_sec
			if is_record:
				best_record_sec = elapsed
			CombatAudio.play_sound("fanfare", position)
			if hud != null:
				var time_str := "%02d:%04.1f" % [int(elapsed / 60), fmod(elapsed, 60.0)]
				var title := "New Course Record!" if is_record else "Course Completed!"
				hud.show_banner(title, "Final Time: %s%s" % [time_str, " · New Best Lap!" if is_record else ""])
			if player != null:
				player.quest_event(QuestDef.ObjectiveType.COMPLETE_REGATTA, &"regatta_buoy")
		else:
			# Split gate cleared
			next_expected_gate += 1
			var split := (Time.get_ticks_msec() - race_start_time_msec) / 1000.0
			if hud != null:
				hud.show_toast("Gate %d Cleared · Split: %.1fs" % [gate_number, split])


func get_interaction_prompt(_player: Player) -> String:
	return "Regatta Buoy · Gate %d of %d" % [gate_number, max(1, active_buoys.size())]
