class_name BedEntity
extends WorldEntity
## Fisher's Bunk: rest to restore vitality (Rested buff), set your wake-up point, and at night
## sleep through to dawn (the host/server moves the clock for everyone).

signal player_slept(player: Player)

const U := VoxelWorld.VS * 0.5


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"fisher_bed", "Fisher's Bunk", p_coord)
	entity_type = EntityType.BED
	size = Vector3(11, 5, 22) * U   # 1.0 x 0.45 x 2.0 m: fits the 1.8 m fisherfolk


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(11, 6, 22)
	g.box(0, 0, 0, 10, 2, 21, Palette.DARK_WOOD)        # frame
	g.box(1, 3, 1, 9, 3, 20, Palette.WHITEWASH)         # mattress
	g.box(1, 4, 6, 9, 4, 20, Palette.SHUTTER)           # wool blanket
	g.box(2, 4, 1, 8, 4, 4, Palette.WHITEWASH)          # pillow
	g.box(0, 3, 0, 10, 5, 0, Palette.DARK_WOOD)         # headboard
	_mesh_instance = _voxel_model(g)


func get_interaction_prompt(player: Player) -> String:
	var night: bool = player.sky != null and not player.sky.is_day()
	return "F  Sleep until Dawn · Fisher's Bunk · Restores Vitality" if night else "F  Rest in Fisher's Bunk · Restores Vitality"


func client_interact(player: Player) -> void:
	interacted.emit(player)
	_rest_locally(player)
	if manager != null:
		manager.request_action(self, &"sleep", {})
	elif player.sky != null:
		player.sky.time_of_day = 0.28


func _rest_locally(player: Player) -> void:
	if player.vitality:
		player.vitality.set_rested(true)
		player.vitality.heal(player.vitality.get_max_hp())
		player.vitality.current_stamina = player.vitality.get_max_stamina()
	player.set_meta("respawn_point", position + Vector3(0.0, 0.05, 0.0))
	player_slept.emit(player)
	if player.hud:
		player.hud.show_toast("Rested comfortably. You'll wake here if you faint.")


## Authority: sleeping at night skips to dawn for the whole world.
func server_action(action: StringName, _args: Dictionary, _peer: int) -> Dictionary:
	if action == &"sleep" and manager != null:
		return manager.try_sleep_in_bed(self, _peer)
	if false:
		var sky: SkyCycle = manager.main.sky
		if not sky.is_day():
			sky.time_of_day = 0.27
			return {"toast": "You sleep until dawn."}
	return {}


## Legacy local interaction (tests).
func interact(player: Player) -> void:
	super.interact(player)
	_rest_locally(player)
	if player.sky:
		player.sky.time_of_day = 0.28
