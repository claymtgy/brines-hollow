class_name LanternEntity
extends WorldEntity
## Kelp-Oil Lantern Post: a placeable light. Cave eels won't come near it, and foxes and
## stoats won't raid a pen it lights. Always lit (it burns kelp oil slowly; no upkeep yet).

const U := VoxelWorld.VS * 0.5

var _light: OmniLight3D


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"lantern_post", "Kelp-Oil Lantern Post", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"lantern_post"
	size = Vector3(3, 18, 3) * U


func emits_light() -> bool:
	return true


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(5, 20, 5)
	g.box(1, 0, 1, 3, 0, 3, Palette.COBBLE)           # footing
	g.box(2, 1, 2, 2, 15, 2, Palette.DARK_WOOD)       # post
	g.box(1, 16, 1, 3, 16, 3, Palette.METAL)          # lamp base
	g.box(1, 17, 1, 3, 18, 3, Palette.LANTERN)        # glowing glass
	g.box(1, 19, 1, 3, 19, 3, Palette.METAL)          # cap
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.8
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.vertex_color_is_srgb = true
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.8, 0.45)
	glow.emission_energy_multiplier = 2.0
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, U, m, glow)
	_mesh_instance.position = Vector3(-g.sx * 0.5, 0.0, -g.sz * 0.5) * U
	add_child(_mesh_instance)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.78, 0.45)
	_light.light_energy = 1.4
	_light.omni_range = 7.0
	_light.position = Vector3(0, 17.5 * U, 0)
	add_child(_light)


func get_interaction_prompt(_player: Player) -> String:
	return "Kelp-Oil Lantern Post (keeps eels and foxes away)  ·  hold F to pick up"


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if player != null and player.hud != null:
		player.hud.show_toast("The lantern burns steadily. Foxes and eels keep their distance.")
