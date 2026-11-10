class_name BarricadeEntity
extends WorldEntity
## Defensive Spike Barricade: heavy driftwood timbers bound with iron spikes.
## Placed at beach heads and village perimeters to slow and damage invading raiders.

const U := VoxelWorld.VS * 0.5
const THORNS_DAMAGE := 12.0
const SLOW_RADIUS := 2.5

var _thorns_cd := 0.0
var _check_t := 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"defense_barricade", "Spike Barricade", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"defense_barricade"
	size = Vector3(14, 10, 6) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(14, 10, 6)
	# Heavy angled timber beams (cheval de frise)
	g.box(1, 0, 1, 12, 2, 4, Palette.DARK_WOOD)         # heavy horizontal footing
	g.box(2, 2, 2, 11, 4, 3, Palette.PLANK)             # crossbeam
	# Sharpened upward-angled stakes
	for x in [2, 5, 8, 11]:
		g.box(x, 1, 0, x + 1, 8, 5, Palette.DRIFTWOOD)
		g.box(x, 8, 0, x + 1, 9, 2, Palette.METAL)      # iron spike tip
	_mesh_instance = _voxel_model(g)


func _process(dt: float) -> void:
	_thorns_cd = maxf(0.0, _thorns_cd - dt)
	if _thorns_cd > 0.0 or not is_inside_tree():
		return

	_check_t -= dt
	if _check_t > 0.0:
		return
	_check_t = 0.15

	# Damage and slow any hostile creatures passing through
	var net: CreatureNet = CreatureNet.current
	if net == null and EntityManager.current != null and EntityManager.current.main != null:
		net = EntityManager.current.main.creatures
	if net != null and not net.creatures.is_empty():
		for c: Creature in net.creatures.values():
			if is_instance_valid(c) and c.state != Creature.State.DEAD and position.distance_to(c.position) <= SLOW_RADIUS:
				_thorns_cd = 1.0
				c.vel *= 0.35
				if c.has_method("on_hit"):
					c.on_hit(THORNS_DAMAGE, position, 0.8, 0)
				CombatAudio.play_sound("hit_shell" if c.is_armored() else "hit_flesh", position)
				break


func get_interaction_prompt(_player: Player) -> String:
	return "Spike Barricade · Thorns & Slow Defense"
