class_name MirrorEntity
extends WorldEntity
## Barber's Looking Glass: restyle your fisherfolk. Appearance belongs to the player
## (saved in their profile), so the mirror itself has no shared state.
##   F            next hairstyle
##   Shift + F    next beard style

signal appearance_adjusted(player: Player)

const U := VoxelWorld.VS * 0.5


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"barber_mirror", "Barber's Looking Glass", p_coord)
	entity_type = EntityType.MIRROR
	size = Vector3(7, 16, 3) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(7, 16, 3)
	g.box(1, 0, 0, 5, 0, 2, Palette.DARK_WOOD)          # foot
	g.box(3, 1, 1, 3, 3, 1, Palette.DARK_WOOD)          # stem
	g.box(0, 4, 1, 6, 15, 1, Palette.DARK_WOOD)         # frame
	g.box(1, 5, 2, 5, 14, 2, Palette.SHUTTER)           # glass (front = +z)
	g.box(2, 11, 2, 3, 13, 2, Palette.WHITEWASH)        # glint
	_mesh_instance = _voxel_model(g)


func get_interaction_prompt(_player: Player) -> String:
	return "F  Next hairstyle    Shift+F  Next beard"


func client_interact(player: Player) -> void:
	if Input.is_action_pressed("sprint") and player.customizer:
		var next_beard: int = (int(player.customizer.beard_style) + 1) % CharacterPalette.BeardStyle.size()
		player.customizer.set_beard(next_beard as CharacterPalette.BeardStyle, player.customizer.beard_color)
		appearance_adjusted.emit(player)
		if player.hud:
			player.hud.show_toast("Trimmed beard: style #%d" % (next_beard + 1))
		return
	interact(player)


func interact(player: Player) -> void:
	super.interact(player)
	if player.customizer:
		var next_hair: int = (int(player.customizer.hair_style) + 1) % CharacterPalette.HairStyle.size()
		player.customizer.set_hair(next_hair as CharacterPalette.HairStyle, player.customizer.hair_color)
		appearance_adjusted.emit(player)
		if player.hud:
			player.hud.show_toast("Gazed in looking glass. Styled hair: Style #%d" % (next_hair + 1))
