class_name StormIncursionManager
extends Node
## Manages high-stakes opt-in Storm Incursions when ringing the Harbour Bell during violent storms.
## Waves of elite Sea-Reavers assault the village perimeter. Defeating them awards top-tier smelting
## ores and Ancient Weapon Fragments.

const TOTAL_WAVES := 3
const SPAWN_RADIUS := 45.0

static var current: StormIncursionManager

var active := false
var current_wave := 0
var village_center := Vector3.ZERO
var raiders_alive: Array[Creature] = []
var _wave_check_t := 0.0


func _ready() -> void:
	current = self


func start_incursion(center: Vector3) -> bool:
	if active:
		return false
	active = true
	current_wave = 1
	village_center = center
	raiders_alive.clear()

	CombatAudio.play_sound("tell_roar", village_center)

	var em := EntityManager.current
	var main_node: Node = em.main if em != null else null
	if main_node != null and main_node.get("hud") != null:
		main_node.hud.show_banner("STORM INCURSION", "Elite Sea-Reavers assault the village! Defend the perimeter! (Wave 1/3)")

	_spawn_wave(current_wave)
	return true


func _spawn_wave(wave: int) -> void:
	raiders_alive.clear()
	var net: CreatureNet = CreatureNet.current
	if net == null and EntityManager.current != null and EntityManager.current.main != null:
		net = EntityManager.current.main.creatures
	if net == null or not net.is_authority():
		return

	var count := 3 + wave * 2
	for i in count:
		var ang := (TAU / count) * i + randf_range(-0.2, 0.2)
		var spawn_pos := village_center + Vector3(cos(ang) * SPAWN_RADIUS, 1.0, sin(ang) * SPAWN_RADIUS)
		var is_harpooner := (i % 2 == 1)
		var kind := &"reaver_harpooner" if is_harpooner else &"reaver"
		var r := net.spawn(kind, spawn_pos) as SeaReaver
		if r != null:
			r.roused = true
			r.max_hp = CombatMath.creature_hp(45.0 + wave * 15.0, net.difficulty)
			r.hp = r.max_hp
			raiders_alive.append(r)


func _process(dt: float) -> void:
	if not active:
		return
	_wave_check_t += dt
	if _wave_check_t < 1.0:
		return
	_wave_check_t = 0.0

	# Filter dead or invalid raiders
	raiders_alive = raiders_alive.filter(func(c: Creature) -> bool:
		return is_instance_valid(c) and c.state != Creature.State.DEAD)

	if raiders_alive.is_empty():
		_advance_wave()


func _advance_wave() -> void:
	var em := EntityManager.current
	var main_node: Node = em.main if em != null else null

	if current_wave < TOTAL_WAVES:
		current_wave += 1
		CombatAudio.play_sound("tell_roar", village_center)
		if main_node != null and main_node.get("hud") != null:
			main_node.hud.show_banner("Wave %d Cleared!" % (current_wave - 1), "Reinforcements approaching! Prepare defenses! (Wave %d/3)" % current_wave)
		_spawn_wave(current_wave)
	else:
		# Incursion Complete! Victory!
		active = false
		CombatAudio.play_sound("fanfare", village_center)
		if main_node != null:
			if main_node.get("hud") != null:
				main_node.hud.show_banner("Storm Incursion Repelled!", "The sea-reavers break and flee into the storm! Rewards granted.")
			if main_node.get("player") != null:
				main_node.player.quest_event(QuestDef.ObjectiveType.SURVIVE_INCURSION, &"storm_incursion")

		# Spawn rewards at village center
		if main_node != null and main_node.has_method("spawn_item_drop"):
			main_node.spawn_item_drop(village_center + Vector3.UP * 1.5, &"ancient_weapon_fragment", 2)
			main_node.spawn_item_drop(village_center + Vector3.UP * 1.5, &"reaver_crest", 1)
			main_node.spawn_item_drop(village_center + Vector3.UP * 1.5, &"iron_ingot", 4)
			main_node.spawn_item_drop(village_center + Vector3.UP * 1.5, &"sea_brass_ingot", 3)
