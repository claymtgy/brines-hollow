class_name BedEntity
extends WorldEntity
## Physical 3D Bed / Fisher's Bunk in the world.
## Interacting triggers restful sleep, restores vitality, and applies Sea-Breeze Rested comfort buff.

signal player_slept(player: Player)


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"fisher_bed", "Fisher's Bunk", p_coord)
	entity_type = EntityType.BED


func _build_visuals() -> void:
	_mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.85, 0.40, 1.40)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.70, 0.76, 0.82) # Duck canvas quilt & wool bedding
	_mesh_instance.mesh = box
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func get_interaction_prompt(_player: Player) -> String:
	return "F  Rest in Fisher's Bunk (Restore Vitality & Gain Rested Buff)"


func interact(player: Player) -> void:
	super.interact(player)
	if player.vitality:
		player.vitality.set_rested(true)
		player.vitality.heal(player.vitality.get_max_hp())
		player.vitality.current_stamina = player.vitality.get_max_stamina()

	if player.sky:
		# Advance to early morning dawn (0.28)
		player.sky.time_of_day = 0.28

	player_slept.emit(player)
	if player.hud:
		player.hud.show_toast("Rested comfortably! Restored Health & Stamina (+50% Stamina Regen).")
