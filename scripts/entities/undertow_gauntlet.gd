class_name UndertowGauntletAltar
extends WorldEntity
## The Undertow Gauntlet: an ancient submerged trial altar revealed during spring low tides.
## Ringing the altar initiates escalating waves of abyssal predators before the incoming tide returns.
## Victory awards the Undertow Champion's Crest and the Ancient Regulator Keystone!

const U := VoxelWorld.VS * 0.5
const TOTAL_WAVES := 3

static var current: UndertowGauntletAltar

var active := false
var is_endless := false
var highest_wave := 0
var current_wave := 0
var enemies_alive: Array[Creature] = []
var _check_t := 0.0
var _glow_light: OmniLight3D


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"undertow_altar", "Undertow Gauntlet Altar", p_coord)
	entity_type = EntityType.WORKSTATION
	item_id = &"undertow_altar"
	size = Vector3(10, 8, 10) * U


func _build_visuals() -> void:
	var root := Node3D.new()
	var g := Prefabs.Grid.new(10, 8, 10)
	# Stepped basalt dais
	g.box(0, 0, 0, 9, 2, 9, Palette.BEDROCK)
	g.box(2, 2, 2, 7, 4, 7, Palette.STONE)
	g.box(3, 4, 3, 6, 7, 6, Palette.COBBLE)
	g.box(4, 7, 4, 5, 7, 5, Palette.GLOW_TEAL)          # central abyssal glyph
	var mi_dais := _voxel_model(g)
	mi_dais.position = Vector3(-5, 0, -5) * U
	root.add_child(mi_dais)

	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color(0.1, 0.9, 0.75)
	_glow_light.light_energy = 1.8
	_glow_light.omni_range = 8.0
	_glow_light.position = Vector3(0, 8 * U, 0)
	root.add_child(_glow_light)

	_mesh_instance = root


func _ready() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func is_spring_low_tide() -> bool:
	var em := EntityManager.current
	var sky: SkyCycle = em.main.sky if (em != null and em.main != null) else null
	if sky != null:
		return sky.water_level_vox <= (VoxelWorld.SEA_MID - VoxelWorld.TIDE_AMP * 0.7)
	return true


func start_gauntlet() -> bool:
	if active or not is_spring_low_tide():
		return false
	is_endless = false
	active = true
	current_wave = 1
	enemies_alive.clear()

	CombatAudio.play_sound("tell_roar", position)
	var em := EntityManager.current
	if em != null and em.main != null and em.main.get("hud") != null:
		em.main.hud.show_banner("THE UNDERTOW GAUNTLET", "Defeat the abyssal horrors before the incoming tide returns! (Wave 1/3)")

	_spawn_wave(current_wave)
	return true


func start_endless_mode() -> bool:
	if active:
		return false
	is_endless = true
	active = true
	current_wave = 1
	enemies_alive.clear()

	CombatAudio.play_sound("tell_roar", position)
	var em := EntityManager.current
	if em != null and em.main != null and em.main.get("hud") != null:
		em.main.hud.show_banner("ENDLESS UNDERTOW GAUNTLET", "Infinite abyssal waves emerge! How deep can you survive? (Wave 1)")

	_spawn_wave(current_wave)
	return true


func _spawn_wave(wave: int) -> void:
	enemies_alive.clear()
	var net: CreatureNet = CreatureNet.current
	if net == null or not net.is_authority():
		return

	var count := 2 + wave * 2
	for i in count:
		var ang := (TAU / count) * i
		var spawn_pos := position + Vector3(cos(ang) * 22.0, 1.0, sin(ang) * 22.0)
		var kind := &"abyssal_angler" if (i % 2 == 1) else &"reaver"
		var c := net.spawn(kind, spawn_pos)
		if c != null:
			c.roused = true
			enemies_alive.append(c)


func _process(dt: float) -> void:
	if not active:
		return
	_check_t -= dt
	if _check_t > 0.0:
		return
	_check_t = 1.0

	enemies_alive = enemies_alive.filter(func(c: Creature) -> bool:
		return is_instance_valid(c) and c.state != Creature.State.DEAD)

	if enemies_alive.is_empty():
		_advance_wave()


func _advance_wave() -> void:
	var em := EntityManager.current
	var main_node: Node = em.main if em != null else null

	if is_endless:
		highest_wave = maxi(highest_wave, current_wave)
		current_wave += 1
		CombatAudio.play_sound("tell_roar", position)
		if main_node != null and main_node.get("hud") != null:
			main_node.hud.show_banner("Wave %d Cleared!" % (current_wave - 1), "Endless Gauntlet continues! Incoming Wave %d!" % current_wave)
		if (current_wave - 1) % 3 == 0 and main_node != null and main_node.has_method("spawn_item_drop"):
			main_node.spawn_item_drop(position + Vector3.UP * 1.5, &"abyssal_pearl", 1)
			main_node.spawn_item_drop(position + Vector3.UP * 1.5, &"ancient_weapon_fragment", 2)
		_spawn_wave(current_wave)
		return

	if current_wave < TOTAL_WAVES:
		current_wave += 1
		CombatAudio.play_sound("tell_roar", position)
		if main_node != null and main_node.get("hud") != null:
			main_node.hud.show_banner("Wave %d Cleared!" % (current_wave - 1), "The sea rises! Next wave emerging! (Wave %d/3)" % current_wave)
		_spawn_wave(current_wave)
	else:
		active = false
		CombatAudio.play_sound("fanfare", position)
		if main_node != null:
			if main_node.get("hud") != null:
				main_node.hud.show_banner("Undertow Gauntlet Conquered!", "You survived the deep surge! Champion's Crest & Keystone awarded.")
			if main_node.has_method("spawn_item_drop"):
				main_node.spawn_item_drop(position + Vector3.UP * 1.5, &"undertow_crest", 1)
				main_node.spawn_item_drop(position + Vector3.UP * 1.5, &"regulator_keystone", 1)
				main_node.spawn_item_drop(position + Vector3.UP * 1.5, &"ancient_weapon_fragment", 3)


func get_interaction_prompt(_player: Player) -> String:
	if active:
		if is_endless:
			return "Endless Undertow Gauntlet · Wave %d in progress" % current_wave
		return "Undertow Gauntlet · Trial in progress (Wave %d/3)" % current_wave
	if not is_spring_low_tide():
		return "Undertow Altar · Submerged (Awakens only at Spring Low Tide)"
	return "F  Channel Undertow Altar · Begin Gauntlet (Hold Shift for Endless)"


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if Input.is_key_pressed(KEY_SHIFT):
		start_endless_mode()
	else:
		start_gauntlet()
