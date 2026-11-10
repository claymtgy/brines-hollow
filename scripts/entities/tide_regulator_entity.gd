class_name TideRegulatorEntity
extends WorldEntity
## Ancient Tide Regulator: a towering pre-deluge monolithic obelisk that channels the ocean's core currents.
## Requires 4 attuned Biome Boss Relics to restore natural equilibrium to the archipelago:
##   1. The Hulk's Pearl (Biome 1: Hollow Flats)
##   2. Heart of the Siren (Biome 2: Murk-Reef)
##   3. Geothermal Core (Biome 3: Basalt Skerries)
##   4. Regulator Keystone (The Undertow Gauntlet)

const U := VoxelWorld.VS * 0.5

static var current: TideRegulatorEntity

var attuned_relics := {
	&"hulk_pearl": false,
	&"siren_heart": false,
	&"geothermal_core": false,
	&"regulator_keystone": false
}
var fully_restored := false
var _light: OmniLight3D
var _pillar: Node3D
var _orbit_nodes: Array[MeshInstance3D] = []
var _rot := 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"tide_regulator", "Ancient Tide Regulator", p_coord)
	entity_type = EntityType.WORKSTATION
	item_id = &"tide_regulator"
	size = Vector3(14, 28, 14) * U


func _build_visuals() -> void:
	var root := Node3D.new()
	var g := Prefabs.Grid.new(14, 28, 14)
	# Stepped ancient foundation
	g.box(1, 0, 1, 12, 3, 12, Palette.BEDROCK)
	g.box(3, 3, 3, 10, 6, 10, Palette.STONE)
	# Tapered obelisk column
	g.box(4, 6, 4, 9, 24, 9, Palette.COBBLE)
	g.box(5, 24, 5, 8, 27, 8, Palette.GLOW_TEAL)         # crowning crystal apex
	# 4 relic sockets carved into the obelisk faces
	g.setv(3, 14, 6, Palette.METAL)
	g.setv(10, 14, 6, Palette.METAL)
	g.setv(6, 14, 3, Palette.METAL)
	g.setv(6, 14, 10, Palette.METAL)
	var mi_pillar := _voxel_model(g)
	mi_pillar.position = Vector3(-7, 0, -7) * U
	root.add_child(mi_pillar)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.2, 0.95, 0.85)
	_light.light_energy = 1.5
	_light.omni_range = 14.0
	_light.position = Vector3(0, 26 * U, 0)
	root.add_child(_light)

	_mesh_instance = root


func _ready() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _process(dt: float) -> void:
	if not fully_restored:
		return
	_rot += dt * 1.5
	if _light != null:
		_light.light_energy = 3.5 + sin(_rot * 3.0) * 0.8


func count_attuned() -> int:
	var c := 0
	for k in attuned_relics:
		if attuned_relics[k]:
			c += 1
	return c


func get_interaction_prompt(_player: Player) -> String:
	if fully_restored:
		return "Ancient Tide Regulator · Equilibrium Restored (4/4)"
	return "Ancient Tide Regulator · %d/4 Relics Attuned  ·  F: Attune Relic" % count_attuned()


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if fully_restored:
		if player.hud != null:
			player.hud.show_toast("The archipelago's tides are calm and balanced.")
		return

	var inserted := false
	# Check for Deluge Core direct attunement
	if player.inventory.count_item(&"deluge_core") > 0:
		player.inventory.remove_item(&"deluge_core", 1)
		for k in attuned_relics:
			attuned_relics[k] = true
		inserted = true
		CombatAudio.play_sound("fanfare", position)
		if player.hud != null:
			player.hud.show_toast("Attuned the Core of the Great Deluge!")
		complete_grand_equilibrium()
		return

	for relic_id: StringName in attuned_relics.keys():
		if not attuned_relics[relic_id] and player.inventory.count_item(relic_id) > 0:
			player.inventory.remove_item(relic_id, 1)
			attuned_relics[relic_id] = true
			inserted = true
			CombatAudio.play_sound("parry", position)
			if player.hud != null:
				var def: ItemDef = ItemDB.get_item(relic_id)
				var r_name := def.name if def != null else String(relic_id)
				player.hud.show_toast("Attuned %s into the Tide Regulator!" % r_name)
			break

	if not inserted:
		if player.hud != null:
			player.hud.show_toast("Hold a Boss Relic (Hulk's Pearl, Siren's Heart, Geothermal Core, Deluge Core, or Keystone) to attune.")
		return

	if count_attuned() >= 4:
		complete_grand_equilibrium()


func complete_grand_equilibrium() -> void:
	fully_restored = true
	WeatherModel.deluge_calmed = true
	CombatAudio.play_sound("fanfare", position)
	var em := EntityManager.current
	if em != null and em.main != null:
		if "deluge_calmed" in em.main:
			em.main.deluge_calmed = true
		if em.main.get("hud") != null:
			em.main.hud.show_banner("GRAND EQUILIBRIUM RESTORED!", "The Great Deluge is stilled. Calm seas prevail! Creative Mode unlocked in pause menu.")
