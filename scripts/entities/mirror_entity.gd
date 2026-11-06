class_name MirrorEntity
extends WorldEntity
## Physical 3D Barber's Standing Looking Glass in the world.
## Allows players to adjust and cycle hairstyles, beards, and fisherfolk appearance diegetically.

signal appearance_adjusted(player: Player)


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"barber_mirror", "Barber's Looking Glass", p_coord)
	entity_type = EntityType.MIRROR


func _build_visuals() -> void:
	_mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.50, 1.20, 0.15)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.85, 0.92) # Polished silver/glass mirror
	mat.metallic = 0.8
	mat.roughness = 0.2
	_mesh_instance.mesh = box
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func get_interaction_prompt(_player: Player) -> String:
	return "F  Gaze into Barber's Looking Glass (Cycle Hairstyle & Beard)"


func interact(player: Player) -> void:
	super.interact(player)
	if player.customizer:
		# Diegetically cycle hairstyle to the next variant
		var next_hair: int = (int(player.customizer.hair_style) + 1) % CharacterPalette.HairStyle.size()
		player.customizer.set_hair(next_hair as CharacterPalette.HairStyle, player.customizer.hair_color)
		appearance_adjusted.emit(player)
		if player.hud:
			player.hud.show_toast("Gazed in looking glass. Styled hair: Style #%d" % (next_hair + 1))
