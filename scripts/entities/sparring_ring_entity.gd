class_name SparringRingEntity
extends WorldEntity
## Town Sparring Ring: a sand circle with boundary ropes for friendly player dueling.
## Combat inside the ring is strictly non-lethal (zero death penalty).
## Reaching 0 HP triggers a knockout flourish, full health reset, and victory fanfare!

const U := VoxelWorld.VS * 0.5
const RING_RADIUS := 5.5

static var active_rings: Array[SparringRingEntity] = []


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"sparring_ring", "Town Sparring Ring", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"sparring_ring"
	size = Vector3(24, 6, 24) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(24, 6, 24)
	# Sand circle floor
	for z in 24:
		for x in 24:
			var d := Vector2(x - 11.5, z - 11.5).length()
			if d <= 11.0:
				g.setv(x, 0, z, Palette.SAND)
	# 4 timber corner posts
	var corners := [Vector2i(2, 2), Vector2i(21, 2), Vector2i(2, 21), Vector2i(21, 21)]
	for c in corners:
		g.box(c.x, 0, c.y, c.x + 1, 5, c.y + 1, Palette.DARK_WOOD)

	# Boundary ropes connecting the posts
	g.box(3, 3, 2, 20, 3, 2, Palette.GRASS_DRY)
	g.box(3, 3, 21, 20, 3, 21, Palette.GRASS_DRY)
	g.box(2, 3, 3, 2, 3, 20, Palette.GRASS_DRY)
	g.box(21, 3, 3, 21, 3, 20, Palette.GRASS_DRY)

	_mesh_instance = _voxel_model(g)


func _ready() -> void:
	active_rings.append(self)


func _exit_tree() -> void:
	active_rings.erase(self)


static func is_in_sparring_ring(pos: Vector3) -> bool:
	for r in active_rings:
		if is_instance_valid(r) and r.position.distance_to(pos) <= RING_RADIUS:
			return true
	return false


static func handle_sparring_defeat(player: Player, winner_name: String = "") -> void:
	if player == null or player.vitality == null:
		return
	player.vitality.current_health = player.vitality.max_health
	CombatAudio.play_sound("fanfare", player.position)
	if player.hud != null:
		var msg := "Bout Concluded! %s scored the winning hit!" % winner_name if winner_name != "" else "Bout Concluded! Good sparring!"
		player.hud.show_banner("Sparring Victory", msg)
	player.quest_event(QuestDef.ObjectiveType.WIN_SPARRING, &"sparring_ring")


func get_interaction_prompt(_player: Player) -> String:
	return "Sparring Ring · Zero-Penalty Sand Arena"
